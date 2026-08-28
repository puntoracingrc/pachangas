import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";
import {
  createR6cFixture,
  r6cCheckpointMarkers,
} from "./tournament-knockout-bracket-v1-postgres-fixture.mjs";

const OWNER_ID = "63010000-0000-4000-8000-000000000001";
const PLATFORM_ID = "63010000-0000-4000-8000-000000000090";
const CLIENT_METADATA = {
  clientVersion: "6.2.0+r6c-concurrency",
  installedMode: "standalone",
  serviceWorkerVersion: "r6c-concurrency",
  surface: "r6c_concurrency",
};
const harness = createR6cPostgresHarness("concurrency");
const fixture = createR6cFixture(harness);
const psqlBin = process.env.PSQL_BIN || "psql";
const r6bBase = harness.databaseName("r6b");
const reservedBase = harness.databaseName("reserved");
const generatedBase = harness.databaseName("generated");
const quarterfinalsBase = harness.databaseName("quarterfinals");
const semifinalsBase = harness.databaseName("semifinals");
const finalBase = harness.databaseName("final");
const reports = [];

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function jwt(actorId) {
  return quote(JSON.stringify({ role: "authenticated", sub: actorId }));
}

function transaction(actorId, statement, delayMs = 0) {
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='120s';
    set local role authenticated;
    set local request.jwt.claims=${jwt(actorId)};
    ${delayMs > 0 ? `select pg_sleep(${delayMs / 1000});` : ""}
    ${statement}
    commit;
  `;
}

function context(database) {
  return JSON.parse(harness.query(database, `
    with competition as (
      select competitions.id
      from public.pachanga_competitions competitions
      where competitions.slug='r6a-concurrency-fixture'
    )
    select jsonb_build_object(
      'competitionId', competition.id,
      'stateRevision', (select states.revision
        from public.pachanga_tournament_group_stage_states states
        where states.competition_id=competition.id),
      'bracketId', (select brackets.id
        from public.pachanga_tournament_brackets brackets
        where brackets.competition_id=competition.id),
      'bracketRevision', (select brackets.revision
        from public.pachanga_tournament_brackets brackets
        where brackets.competition_id=competition.id)
    )::text from competition;
  `, "read R6C concurrency context"));
}

function nodeContext(database, roundCode, nodeOrder = 1) {
  return JSON.parse(harness.query(database, `
    select jsonb_build_object(
      'nodeId', nodes.id,
      'canonicalMatchId', nodes.canonical_match_id,
      'contextId', contexts.id,
      'contextRevision', contexts.revision,
      'homeEntryId', nodes.home_entry_id,
      'awayEntryId', nodes.away_entry_id,
      'winnerEntryId', nodes.winner_entry_id,
      'loserEntryId', nodes.loser_entry_id,
      'officialDecisionId', sheets.active_official_decision_id
    )::text
    from public.pachanga_tournament_bracket_nodes nodes
    left join public.pachanga_competition_match_contexts contexts
      on contexts.canonical_match_id=nodes.canonical_match_id
    left join public.pachanga_competition_match_sheets sheets
      on sheets.competition_match_context_id=contexts.id
    where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder};
  `, `read R6C ${roundCode} concurrency node`));
}

function r6cSql(database, action, payload, operationId = randomUUID(), delayMs = 0) {
  const current = context(database);
  const expectedRevision = current.bracketRevision ?? current.stateRevision;
  return transaction(OWNER_ID, `
    select jsonb_build_object(
      'action', ${quote(action)},
      'operationId', ${quote(operationId)}::uuid,
      'expectedRevision', ${expectedRevision},
      'confirmedRevision', receipt.response -> 'confirmedRevision'
    )
    from (
      select public.command_pachanga_tournament_knockout_v1(
        ${quote(operationId)}::uuid,
        ${quote(current.competitionId)}::uuid,
        ${expectedRevision},
        ${quote(action)},
        ${quote(JSON.stringify(payload))}::jsonb,
        ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
      ) as response
    ) receipt;
  `, delayMs);
}

function r4cSql(node, payload, delayMs = 0) {
  const operationId = randomUUID();
  return transaction(OWNER_ID, `
    select jsonb_build_object(
      'action', 'official_result.supersede',
      'operationId', ${quote(operationId)}::uuid,
      'expectedRevision', ${node.contextRevision},
      'confirmedRevision', receipt.response -> 'confirmedRevision'
    )
    from (
      select public.command_pachanga_league_match_operations_v1(
        ${quote(operationId)}::uuid,
        ${quote(node.contextId)}::uuid,
        ${node.contextRevision},
        'official_result.supersede',
        ${quote(JSON.stringify(payload))}::jsonb,
        ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
      ) as response
    ) receipt;
  `, delayMs);
}

function r4dCancelSql(node, delayMs = 0) {
  const operationId = randomUUID();
  return transaction(OWNER_ID, `
    select jsonb_build_object(
      'action', 'fixture.cancel',
      'operationId', ${quote(operationId)}::uuid,
      'expectedRevision', ${node.contextRevision},
      'confirmedRevision', receipt.response -> 'confirmedRevision'
    )
    from (
      select public.command_pachanga_league_operational_exceptions_v1(
        ${quote(operationId)}::uuid,
        ${quote(node.contextId)}::uuid,
        ${node.contextRevision},
        'fixture.cancel',
        '{"cancellationOutcome":"NO_RESULT","reasonCode":"OTHER","publicSummary":"R6C concurrency cancellation"}'::jsonb,
        ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
      ) as response
    ) receipt;
  `, delayMs);
}

function runConcurrent(database, sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(psqlBin, [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", harness.targetUrl(database),
    ], {
      cwd: harness.root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({
      code,
      label,
      stdout: stdout.trim(),
      stderr: stderr.trim(),
    }));
    child.stdin.end(sql);
  });
}

function invariants(database) {
  return JSON.parse(harness.query(database, `
    select jsonb_build_object(
      'brackets', (select count(*) from public.pachanga_tournament_brackets),
      'duplicateNodeMatches', (select count(*) from (
        select nodes.canonical_match_id
        from public.pachanga_tournament_bracket_nodes nodes
        where nodes.canonical_match_id is not null
        group by nodes.canonical_match_id having count(*)>1
      ) duplicates),
      'duplicateContextBindings', (select count(*) from (
        select contexts.canonical_match_id
        from public.pachanga_competition_match_contexts contexts
        join public.pachanga_tournament_brackets brackets
          on brackets.competition_id=contexts.competition_id
        where contexts.source_kind='COMPETITION_GENERATED'
        group by contexts.canonical_match_id having count(*)>1
      ) duplicates),
      'invalidWinners', (select count(*)
        from public.pachanga_tournament_bracket_nodes nodes
        where nodes.winner_entry_id is not null
          and nodes.winner_entry_id not in (nodes.home_entry_id,nodes.away_entry_id)),
      'duplicateAdvanceRevisions', (select count(*) from (
        select advances.source_node_id, advances.revision
        from public.pachanga_tournament_bracket_advance_decisions advances
        group by advances.source_node_id, advances.revision having count(*)>1
      ) duplicates),
      'duplicateCompletionRevisions', (select count(*) from (
        select snapshots.bracket_id, snapshots.revision
        from public.pachanga_tournament_completion_snapshots snapshots
        group by snapshots.bracket_id, snapshots.revision having count(*)>1
      ) duplicates)
    )::text;
  `, "read R6C concurrency invariants"));
}

async function race(database, label, leftSql, rightSql) {
  const results = await Promise.all([
    runConcurrent(database, leftSql, `${label}:left`),
    runConcurrent(database, rightSql, `${label}:right`),
  ]);
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one conflict: ${JSON.stringify(results)}`);
  assert.match(
    `${losers[0].stdout}\n${losers[0].stderr}`,
    /STALE_REVISION|PT409|ALREADY_STARTED|WINDOW_CLOSED|OFFICIAL_DECISION_INVALID|TOURNAMENT_[A-Z_]+|R4[CD]_[A-Z_]+/i,
    `${label} loser must expose a stable authority conflict`,
  );
  const snapshot = invariants(database);
  assert.equal(snapshot.duplicateNodeMatches, 0, `${label} duplicated a node match`);
  assert.equal(snapshot.duplicateContextBindings, 0, `${label} duplicated a context binding`);
  assert.equal(snapshot.invalidWinners, 0, `${label} persisted an invalid winner`);
  assert.equal(snapshot.duplicateAdvanceRevisions, 0, `${label} duplicated an advance revision`);
  assert.equal(snapshot.duplicateCompletionRevisions, 0, `${label} duplicated completion revision`);
  reports.push({ label, loser: losers[0].stderr.split("\n").at(-1), invariants: snapshot });
}

function enableFlags(database) {
  harness.query(database, `
    set request.jwt.claims=${jwt(PLATFORM_ID)};
    select public.command_pachanga_tournament_knockout_platform_v1(
      ${quote(randomUUID())}::uuid,
      '00000000-0000-0000-0000-00000000c6c1'::uuid,
      (select revision from private.pachanga_competition_foundation_settings where singleton),
      'tournament.knockout.flags.set',
      '{"knockoutFoundationEnabled":true,"knockoutMatchGenerationEnabled":true,"bracketProgressionEnabled":true,"extraTimeEnabled":true,"penaltyShootoutEnabled":true,"thirdPlaceEnabled":true,"completionEnabled":true,"reason":"R6C concurrency flags"}'::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `, "enable R6C concurrency flags");
}

function prepareDecision(database, roundCode, nodeOrder, scoreHome, scoreAway) {
  const evidence = {
    scoreAfterRegulationHome: scoreHome,
    scoreAfterRegulationAway: scoreAway,
    extraTimePlayed: false,
  };
  const candidateId = harness.query(database, `
    select decisions.id
    from public.pachanga_competition_official_result_decisions decisions
    where decisions.canonical_match_id<>(
        select nodes.canonical_match_id
        from public.pachanga_tournament_bracket_nodes nodes
        where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder}
      )
      and not exists (
        select 1 from public.pachanga_tournament_knockout_result_resolutions resolutions
        where resolutions.official_result_decision_id=decisions.id
      )
    order by decisions.server_sequence, decisions.id limit 1;
  `, `select ${roundCode} R6C concurrency decision candidate`);
  assert.match(candidateId, /^[0-9a-f-]{36}$/i);
  const decisionId = harness.query(database, `
    set session_replication_role=replica;
    with target as (
      select nodes.id as node_id, nodes.canonical_match_id,
        contexts.id as context_id, sheets.active_official_decision_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      left join public.pachanga_competition_match_sheets sheets
        on sheets.competition_match_context_id=contexts.id
      where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder}
    )
    update public.pachanga_competition_official_result_decisions decisions set
      canonical_match_id=target.canonical_match_id,
      competition_match_context_id=target.context_id,
      supersedes_decision_id=target.active_official_decision_id,
      outcome=case when target.active_official_decision_id is null
        then 'MIRROR_SPORTING_RESULT' else 'CORRECTED_EFFECTIVE_SCORE' end,
      effective_score_home=${scoreHome}, effective_score_away=${scoreAway},
      operation_id=gen_random_uuid(), reason_code='r6c.concurrency.decision'
    from target where decisions.id=${quote(candidateId)}::uuid;
    update private.pachanga_competition_official_result_evidence evidence_rows set
      evidence=jsonb_build_object('knockout', ${quote(JSON.stringify(evidence))}::jsonb)
    where evidence_rows.official_result_decision_id=${quote(candidateId)}::uuid;
    with target as (
      select nodes.canonical_match_id, contexts.id context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder}
    )
    update public.pachanga_competition_match_sheets sheets
    set active_official_decision_id=null
    from target where sheets.active_official_decision_id=${quote(candidateId)}::uuid
      and sheets.competition_match_context_id<>(select context_id from target);
    with target as (
      select nodes.canonical_match_id, contexts.id context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder}
    )
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id,
      active_official_decision_id, created_by
    ) select target.canonical_match_id,target.context_id,
        ${quote(candidateId)}::uuid,${quote(OWNER_ID)}::uuid
      from target
    on conflict (competition_match_context_id) do update
      set active_official_decision_id=excluded.active_official_decision_id;
    update public.pachanga_competition_match_contexts contexts
    set status='official'
    where contexts.id=(
      select target_contexts.id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts target_contexts
        on target_contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder}
    );
    set session_replication_role=origin;
    select decisions.id
    from public.pachanga_competition_official_result_decisions decisions
    where decisions.id=${quote(candidateId)}::uuid
      and not exists (
        select 1 from public.pachanga_tournament_knockout_result_resolutions resolutions
        where resolutions.official_result_decision_id=decisions.id
      );
  `, `prepare ${roundCode} R6C concurrency decision`);
  assert.match(decisionId, /^[0-9a-f-]{36}$/i);
  return decisionId;
}

function resetSemifinalForGeneration(database) {
  const semifinal = nodeContext(database, "SEMIFINAL", 1);
  harness.query(database, `
    set session_replication_role=replica;
    update public.pachanga_competition_match_contexts contexts
      set status='retired'
      where contexts.id=${quote(semifinal.contextId)}::uuid;
    update public.pachanga_canonical_matches matches
      set status='retired'
      where matches.id=${quote(semifinal.canonicalMatchId)}::uuid;
    update public.pachanga_tournament_bracket_nodes nodes
      set canonical_match_id=null, status='scheduled'
      where nodes.id=${quote(semifinal.nodeId)}::uuid;
    set session_replication_role=origin;
  `, "reset R6C semifinal generation checkpoint");
  return semifinal.nodeId;
}

function addThirdPlaceNode(database) {
  const nodeId = randomUUID();
  harness.query(database, `
    set session_replication_role=replica;
    update public.pachanga_tournament_brackets set third_place_enabled=true;
    insert into public.pachanga_tournament_bracket_nodes(
      id,bracket_id,bracket_revision_id,round_code,round_order,node_order,node_kind,
      home_entry_id,away_entry_id,status,revision,updated_by
    )
    select ${quote(nodeId)}::uuid,brackets.id,brackets.current_revision_id,
      'THIRD_PLACE',3,2,'THIRD_PLACE',
      (select loser_entry_id from public.pachanga_tournament_bracket_nodes
        where round_code='SEMIFINAL' and node_order=1),
      (select loser_entry_id from public.pachanga_tournament_bracket_nodes
        where round_code='SEMIFINAL' and node_order=2),
      'ready',1,${quote(OWNER_ID)}::uuid
    from public.pachanga_tournament_brackets brackets;
    insert into public.pachanga_tournament_bracket_node_slots(
      id,bracket_id,bracket_revision_id,bracket_node_id,side,slot_revision,
      source_kind,source_key,source_node_id,resolved_entry_id,resolution_status,
      source_snapshot,operation_id,created_by
    )
    select gen_random_uuid(),brackets.id,brackets.current_revision_id,
      ${quote(nodeId)}::uuid,sides.side,1,'LOSER_OF',
      'LOSER:' || sources.id::text,sources.id,sources.loser_entry_id,'RESOLVED',
      jsonb_build_object('sourceKind','LOSER_OF','sourceNodeId',sources.id),
      gen_random_uuid(),${quote(OWNER_ID)}::uuid
    from public.pachanga_tournament_brackets brackets
    cross join (values ('HOME',1),('AWAY',2)) sides(side,node_order)
    join public.pachanga_tournament_bracket_nodes sources
      on sources.round_code='SEMIFINAL' and sources.node_order=sides.node_order;
    set session_replication_role=origin;
  `, "add isolated R6C third-place node");
  harness.query(database, r6cSql(database, "bracket.reserve_slot", {
    nodeId,
    startsAt: "2027-06-22T20:30:00+02:00",
    endsAt: "2027-06-22T22:30:00+02:00",
    timezone: "Europe/Madrid",
    venueLabel: "Campo R6C tercer puesto",
    resourceKey: "r6c-third-place",
    reason: "Reserva del tercer puesto concurrente",
  }), "reserve R6C third-place fixture");
  return nodeId;
}

try {
  fixture.prepareR6b(r6bBase);
  fixture.prepareR6c(reservedBase, r6cCheckpointMarkers.reserved);
  fixture.prepareR6c(generatedBase, r6cCheckpointMarkers.quarterfinalsGenerated);
  fixture.prepareR6c(quarterfinalsBase, r6cCheckpointMarkers.quarterfinalsAdvanced);
  fixture.prepareR6c(semifinalsBase, r6cCheckpointMarkers.semifinalsAdvanced);
  fixture.prepareR6c(finalBase, r6cCheckpointMarkers.finalAdvanced);

  {
    const database = harness.clone(r6bBase, "activate");
    enableFlags(database);
    const current = context(database);
    const payload = { reason: "Concurrent bracket activation" };
    await race(database, "two_activations",
      r6cSql(database, "bracket.activate", payload),
      r6cSql(database, "bracket.activate", payload, randomUUID(), 20));
    assert.equal(invariants(database).brackets, 1);
    assert.ok(current.stateRevision > 0);
  }

  {
    const database = harness.clone(reservedBase, "reserve");
    const nodeId = nodeContext(database, "QUARTERFINAL", 1).nodeId;
    await race(database, "two_reservations",
      r6cSql(database, "bracket.reserve_slot", {
        nodeId, startsAt: "2027-07-01T18:00:00+02:00", endsAt: "2027-07-01T20:00:00+02:00",
        timezone: "Europe/Madrid", venueLabel: "Campo concurrencia A",
        resourceKey: "r6c-reserve-a", reason: "Reserva concurrente A",
      }),
      r6cSql(database, "bracket.reserve_slot", {
        nodeId, startsAt: "2027-07-01T20:00:00+02:00", endsAt: "2027-07-01T22:00:00+02:00",
        timezone: "Europe/Madrid", venueLabel: "Campo concurrencia B",
        resourceKey: "r6c-reserve-b", reason: "Reserva concurrente B",
      }, randomUUID(), 20));
  }

  {
    const database = harness.clone(reservedBase, "generate");
    const nodeId = nodeContext(database, "QUARTERFINAL", 1).nodeId;
    await race(database, "two_match_generations",
      r6cSql(database, "bracket.node.generate_match", { nodeId, reason: "Generate QF A" }),
      r6cSql(database, "bracket.node.generate_match", { nodeId, reason: "Generate QF B" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(generatedBase, "advance");
    const decisionId = prepareDecision(database, "QUARTERFINAL", 1, 2, 0);
    await race(database, "two_advances",
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Advance A" }),
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Advance B" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(quarterfinalsBase, "official_correction");
    const node = nodeContext(database, "QUARTERFINAL", 1);
    await race(database, "official_result_vs_correction",
      r4cSql(node, {
        outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 0, scoreAway: 2,
        reasonCode: "r6c.concurrent.correction.a", publicExplanation: "Corrección A",
        privateEvidence: { knockout: { scoreAfterRegulationHome: 0, scoreAfterRegulationAway: 2, extraTimePlayed: false } },
      }),
      r4cSql(node, {
        outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 3, scoreAway: 0,
        reasonCode: "r6c.concurrent.correction.b", publicExplanation: "Corrección B",
        privateEvidence: { knockout: { scoreAfterRegulationHome: 3, scoreAfterRegulationAway: 0, extraTimePlayed: false } },
      }, 20));
  }

  {
    const database = harness.clone(quarterfinalsBase, "advance_invalidate");
    const nodeId = nodeContext(database, "QUARTERFINAL", 1).nodeId;
    const decisionId = prepareDecision(database, "QUARTERFINAL", 1, 0, 2);
    await race(database, "advance_vs_bracket_invalidation",
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Apply correction" }),
      r6cSql(database, "bracket.node.invalidate", { nodeId, reason: "Invalidate concurrent branch" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(generatedBase, "advance_cancel");
    const decisionId = prepareDecision(database, "QUARTERFINAL", 1, 2, 0);
    const node = nodeContext(database, "QUARTERFINAL", 1);
    await race(database, "advance_vs_r4d_cancellation",
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Advance before cancellation" }),
      r4dCancelSql(node, 20));
  }

  {
    const database = harness.clone(quarterfinalsBase, "correction_semifinal");
    const semifinalId = resetSemifinalForGeneration(database);
    const decisionId = prepareDecision(database, "QUARTERFINAL", 1, 0, 2);
    await race(database, "quarterfinal_correction_vs_semifinal_generation",
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Correct quarterfinal" }),
      r6cSql(database, "bracket.node.generate_match", { nodeId: semifinalId, reason: "Generate semifinal" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(finalBase, "completion");
    await race(database, "two_completion_rebuilds",
      r6cSql(database, "tournament.completion.rebuild", { reason: "Completion A" }),
      r6cSql(database, "tournament.completion.rebuild", { reason: "Completion B" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(finalBase, "complete_correction");
    const decisionId = prepareDecision(database, "FINAL", 1, 0, 2);
    await race(database, "complete_vs_final_correction",
      r6cSql(database, "tournament.complete", { reason: "Complete tournament" }),
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Correct final" }, randomUUID(), 20));
  }

  {
    const database = harness.clone(semifinalsBase, "third_place");
    const thirdPlaceId = addThirdPlaceNode(database);
    const decisionId = prepareDecision(database, "SEMIFINAL", 1, 0, 2);
    await race(database, "third_place_generation_vs_semifinal_correction",
      r6cSql(database, "bracket.node.generate_match", { nodeId: thirdPlaceId, reason: "Generate third place" }),
      r6cSql(database, "bracket.result.advance", { officialDecisionId: decisionId, reason: "Correct semifinal" }, randomUUID(), 20));
  }

  process.stdout.write(`R6C_CONCURRENCY_REPORT|${JSON.stringify({
    races: reports,
    raceCount: reports.length,
    result: "ONE_WINNER_ONE_CONFLICT",
  })}\n`);
} finally {
  harness.cleanup();
}
