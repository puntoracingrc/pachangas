import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";
import { performance } from "node:perf_hooks";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";
import {
  createR6cFixture,
  r6cCheckpointMarkers,
} from "./tournament-knockout-bracket-v1-postgres-fixture.mjs";

const OWNER_ID = "63010000-0000-4000-8000-000000000001";
const PLATFORM_ID = "63010000-0000-4000-8000-000000000090";
const SAMPLE_COUNT = 11;
const STATEMENT_TIMEOUT_MS = 120_000;
const PROCESS_TIMEOUT_MS = 130_000;
const CLIENT_METADATA = {
  clientVersion: "6.2.0+r6c-performance",
  installedMode: "browser",
  serviceWorkerVersion: "r6c-performance",
  surface: "r6c_performance",
};

const harness = createR6cPostgresHarness("performance");
const fixture = createR6cFixture(harness);
const r6bBase = harness.databaseName("r6b");
const reservedBase = harness.databaseName("reserved");
const generatedBase = harness.databaseName("generated");
const quarterfinalsBase = harness.databaseName("quarterfinals");
const finalBase = harness.databaseName("final");

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function claims(actorId) {
  return quote(JSON.stringify({ role: "authenticated", sub: actorId }));
}

function runBounded(database, sql, label) {
  const startedAt = performance.now();
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", harness.targetUrl(database),
  ], {
    cwd: harness.root,
    encoding: "utf8",
    env: { ...process.env, PGAPPNAME: "pachangas-r6c-performance" },
    input: sql,
    maxBuffer: 16 * 1024 * 1024,
    timeout: PROCESS_TIMEOUT_MS,
  });
  const elapsedMs = performance.now() - startedAt;
  if (result.error) throw result.error;
  assert.equal(result.signal, null, `${label} exceeded the bounded process timeout`);
  assert.equal(result.status, 0, `${label} failed:\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  assert.ok(result.stdout.trim(), `${label} returned no proof`);
  return elapsedMs;
}

function transaction(actorId, statement) {
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='${STATEMENT_TIMEOUT_MS}ms';
    set local role authenticated;
    set local request.jwt.claims=${claims(actorId)};
    ${statement}
    rollback;
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
      'bracketRevision', (select brackets.revision
        from public.pachanga_tournament_brackets brackets
        where brackets.competition_id=competition.id)
    )::text from competition;
  `, "read R6C performance context"));
}

function nodeId(database, roundCode, nodeOrder = 1) {
  return harness.query(database, `
    select nodes.id
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.round_code=${quote(roundCode)} and nodes.node_order=${nodeOrder};
  `, `read R6C performance ${roundCode} node`);
}

function command(database, action, payload, expectedRevision = null) {
  const current = context(database);
  const revision = expectedRevision ?? current.bracketRevision ?? current.stateRevision;
  return transaction(OWNER_ID, `
    select response ->> 'confirmedRevision'
    from (
      select public.command_pachanga_tournament_knockout_v1(
        ${quote(randomUUID())}::uuid,
        ${quote(current.competitionId)}::uuid,
        ${revision},
        ${quote(action)},
        ${quote(JSON.stringify(payload))}::jsonb,
        ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
      ) response
    ) receipt;
  `);
}

function read(database, functionName) {
  const current = context(database);
  return transaction(OWNER_ID, `
    select jsonb_typeof(public.${functionName}(${quote(current.competitionId)}::uuid));
  `);
}

function enableFlags(database) {
  harness.query(database, `
    set request.jwt.claims=${claims(PLATFORM_ID)};
    select public.command_pachanga_tournament_knockout_platform_v1(
      ${quote(randomUUID())}::uuid,
      '00000000-0000-0000-0000-00000000c6c1'::uuid,
      (select revision from private.pachanga_competition_foundation_settings where singleton),
      'tournament.knockout.flags.set',
      '{"knockoutFoundationEnabled":true,"knockoutMatchGenerationEnabled":true,"bracketProgressionEnabled":true,"extraTimeEnabled":true,"penaltyShootoutEnabled":true,"thirdPlaceEnabled":true,"completionEnabled":true,"reason":"R6C performance flags"}'::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `, "enable R6C performance flags");
}

function prepareNodeResolution(database) {
  harness.query(database, `
    set session_replication_role=replica;
    with sources as (
      select nodes.id, nodes.home_entry_id, nodes.away_entry_id
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.round_code='QUARTERFINAL' and nodes.node_order in (1,2)
    )
    update public.pachanga_tournament_bracket_nodes nodes set
      winner_entry_id=sources.home_entry_id,
      loser_entry_id=sources.away_entry_id,
      status='advanced'
    from sources where nodes.id=sources.id;
    update public.pachanga_tournament_bracket_nodes nodes set
      home_entry_id=null, away_entry_id=null, status='awaiting_sources'
    where nodes.round_code='SEMIFINAL' and nodes.node_order=1;
    set session_replication_role=origin;
  `, "prepare R6C node-resolution performance checkpoint");
  return nodeId(database, "SEMIFINAL", 1);
}

function prepareDecision(database) {
  const targetNodeId = nodeId(database, "QUARTERFINAL", 1);
  const candidateId = harness.query(database, `
    select decisions.id
    from public.pachanga_competition_official_result_decisions decisions
    where not exists (
      select 1 from public.pachanga_tournament_knockout_result_resolutions resolutions
      where resolutions.official_result_decision_id=decisions.id
    )
    order by decisions.server_sequence, decisions.id limit 1;
  `, "select R6C performance official decision candidate");
  assert.match(candidateId, /^[0-9a-f-]{36}$/i);
  harness.query(database, `
    set session_replication_role=replica;
    with target as (
      select nodes.canonical_match_id, contexts.id as context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.id=${quote(targetNodeId)}::uuid
    )
    update public.pachanga_competition_official_result_decisions decisions set
      canonical_match_id=target.canonical_match_id,
      competition_match_context_id=target.context_id,
      supersedes_decision_id=null,
      outcome='MIRROR_SPORTING_RESULT',
      effective_score_home=2,
      effective_score_away=0,
      operation_id=gen_random_uuid(),
      reason_code='r6c.performance.decision'
    from target where decisions.id=${quote(candidateId)}::uuid;
    update private.pachanga_competition_official_result_evidence evidence_rows set
      evidence='{"knockout":{"scoreAfterRegulationHome":2,"scoreAfterRegulationAway":0,"extraTimePlayed":false}}'::jsonb
    where evidence_rows.official_result_decision_id=${quote(candidateId)}::uuid;
    with target as (
      select nodes.canonical_match_id, contexts.id as context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.id=${quote(targetNodeId)}::uuid
    )
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id,
      active_official_decision_id, created_by
    ) select target.canonical_match_id, target.context_id,
        ${quote(candidateId)}::uuid, ${quote(OWNER_ID)}::uuid
      from target
    on conflict (competition_match_context_id) do update
      set active_official_decision_id=excluded.active_official_decision_id;
    update public.pachanga_competition_match_contexts contexts set status='official'
    where contexts.id=(
      select target_contexts.id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts target_contexts
        on target_contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.id=${quote(targetNodeId)}::uuid
    );
    set session_replication_role=origin;
  `, "prepare R6C advance performance decision");
  return candidateId;
}

function percentile(values, target) {
  const ordered = [...values].sort((left, right) => left - right);
  return ordered[Math.ceil(target * ordered.length) - 1];
}

function benchmark(label, database, sqlFactory) {
  const samples = [];
  for (let index = 0; index < SAMPLE_COUNT; index += 1) {
    samples.push(runBounded(database, sqlFactory(), `${label} sample ${index + 1}`));
  }
  const p50 = percentile(samples, 0.5);
  const p95 = percentile(samples, 0.95);
  assert.ok(p95 < STATEMENT_TIMEOUT_MS, `${label} p95 reached the statement timeout`);
  return {
    maxMs: Number(Math.max(...samples).toFixed(2)),
    minMs: Number(Math.min(...samples).toFixed(2)),
    p50Ms: Number(p50.toFixed(2)),
    p95Ms: Number(p95.toFixed(2)),
    samples: samples.length,
  };
}

try {
  fixture.prepareR6b(r6bBase);
  fixture.prepareR6c(reservedBase, r6cCheckpointMarkers.reserved);
  fixture.prepareR6c(generatedBase, r6cCheckpointMarkers.quarterfinalsGenerated);
  fixture.prepareR6c(quarterfinalsBase, r6cCheckpointMarkers.quarterfinalsAdvanced);
  fixture.prepareR6c(finalBase, r6cCheckpointMarkers.finalAdvanced);

  const activationDatabase = harness.clone(r6bBase, "activation");
  const resolutionDatabase = harness.clone(generatedBase, "resolution");
  const advanceDatabase = harness.clone(generatedBase, "advance");
  enableFlags(activationDatabase);
  const resolutionNodeId = prepareNodeResolution(resolutionDatabase);
  const advanceDecisionId = prepareDecision(advanceDatabase);
  const generationNodeId = nodeId(reservedBase, "QUARTERFINAL", 1);
  const invalidationNodeId = nodeId(quarterfinalsBase, "QUARTERFINAL", 1);

  const metrics = {
    bracketActivation: benchmark("bracket activation", activationDatabase, () => command(
      activationDatabase, "bracket.activate", { reason: "R6C performance activation" },
    )),
    nodeResolution: benchmark("node resolution", resolutionDatabase, () => command(
      resolutionDatabase, "bracket.node.resolve",
      { nodeId: resolutionNodeId, reason: "R6C performance resolution" },
    )),
    matchGeneration: benchmark("match generation", reservedBase, () => command(
      reservedBase, "bracket.node.generate_match",
      { nodeId: generationNodeId, reason: "R6C performance generation" },
    )),
    advance: benchmark("advance", advanceDatabase, () => command(
      advanceDatabase, "bracket.result.advance",
      { officialDecisionId: advanceDecisionId, reason: "R6C performance advance" },
    )),
    downstreamInvalidation: benchmark("downstream invalidation", quarterfinalsBase, () => command(
      quarterfinalsBase, "bracket.node.invalidate",
      { nodeId: invalidationNodeId, reason: "R6C performance invalidation" },
    )),
    bracketView: benchmark("bracket view", finalBase, () => read(
      finalBase, "get_pachanga_tournament_knockout_v1",
    )),
    organizerDesk: benchmark("organizer desk", finalBase, () => read(
      finalBase, "get_pachanga_tournament_group_hub_v1",
    )),
    completionRebuild: benchmark("completion rebuild", finalBase, () => command(
      finalBase, "tournament.completion.rebuild",
      { reason: "R6C performance completion rebuild" },
    )),
  };

  process.stdout.write(`R6C_PERFORMANCE_REPORT|${JSON.stringify({
    metrics,
    processTimeoutMs: PROCESS_TIMEOUT_MS,
    statementTimeoutMs: STATEMENT_TIMEOUT_MS,
  })}\n`);
} finally {
  harness.cleanup();
}
