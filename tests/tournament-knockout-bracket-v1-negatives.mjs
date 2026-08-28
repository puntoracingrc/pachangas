import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";
import {
  createR6cFixture,
  r6cCheckpointMarkers,
} from "./tournament-knockout-bracket-v1-postgres-fixture.mjs";

const OWNER_ID = "63010000-0000-4000-8000-000000000001";
const PLATFORM_ID = "63010000-0000-4000-8000-000000000090";
const metadata = JSON.stringify({
  clientVersion: "6.2.0+r6c-negatives",
  installedMode: "browser",
  serviceWorkerVersion: "r6c-negatives",
  surface: "r6c_negatives",
});
const harness = createR6cPostgresHarness("negatives");
const fixture = createR6cFixture(harness);
const r6bBase = harness.databaseName("r6b_base");
const generatedBase = harness.databaseName("generated_base");
const cases = [];

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function claims(actorId) {
  return `set request.jwt.claims = ${quote(JSON.stringify({
    role: "authenticated",
    sub: actorId,
  }))};`;
}

function competitionId(database) {
  return harness.query(database, `
    select id from public.pachanga_competitions
    where slug='r6a-concurrency-fixture';
  `, "read R6C negative competition");
}

function stateRevision(database) {
  return Number(harness.query(database, `
    select states.revision
    from public.pachanga_tournament_group_stage_states states
    join public.pachanga_competitions competitions on competitions.id=states.competition_id
    where competitions.slug='r6a-concurrency-fixture';
  `, "read R6C negative GroupStage revision"));
}

function bracketRevision(database) {
  return Number(harness.query(database, `
    select brackets.revision
    from public.pachanga_tournament_brackets brackets
    join public.pachanga_competitions competitions on competitions.id=brackets.competition_id
    where competitions.slug='r6a-concurrency-fixture';
  `, "read R6C negative bracket revision"));
}

function commandSql(database, action, payload, actorId = OWNER_ID, revision = null) {
  return `${claims(actorId)}
    select public.command_pachanga_tournament_knockout_v1(
      ${quote(randomUUID())}::uuid,
      ${quote(competitionId(database))}::uuid,
      ${revision ?? bracketRevision(database)},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(metadata)}::jsonb
    )::text;
  `;
}

function enableFlags(database) {
  harness.query(database, `${claims(PLATFORM_ID)}
    select public.command_pachanga_tournament_knockout_platform_v1(
      ${quote(randomUUID())}::uuid,
      '00000000-0000-0000-0000-00000000c6c1'::uuid,
      (select revision from private.pachanga_competition_foundation_settings where singleton),
      'tournament.knockout.flags.set',
      '{"knockoutFoundationEnabled":true,"knockoutMatchGenerationEnabled":true,"bracketProgressionEnabled":true,"extraTimeEnabled":true,"penaltyShootoutEnabled":true,"thirdPlaceEnabled":true,"completionEnabled":true,"reason":"R6C negative matrix"}'::jsonb,
      ${quote(metadata)}::jsonb
    );
  `, "enable R6C negative flags");
}

function expectError(database, label, sql, pattern) {
  try {
    harness.query(database, sql, `R6C negative ${label}`);
    assert.fail(`${label} unexpectedly succeeded`);
  } catch (error) {
    assert.match(String(error), pattern, `${label} returned the wrong authority error`);
  }
  cases.push(label);
}

function cloneR6b(name) {
  const database = harness.clone(r6bBase, name);
  enableFlags(database);
  return database;
}

function firstNode(database) {
  return harness.query(database, `
    select nodes.id
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.round_code='QUARTERFINAL'
    order by nodes.node_order limit 1;
  `, "read R6C negative node");
}

function repurposeOfficialDecision(database, evidence, { active = true } = {}) {
  const activateDecision = active ? `
    with target as (
      select nodes.canonical_match_id, contexts.id as context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code='QUARTERFINAL'
      order by nodes.node_order limit 1
    ), candidate as (
      select decisions.id
      from public.pachanga_competition_official_result_decisions decisions
      join target on target.canonical_match_id=decisions.canonical_match_id
      order by decisions.server_sequence, decisions.id limit 1
    )
    update public.pachanga_competition_match_sheets sheets set
      canonical_match_id=target.canonical_match_id,
      competition_match_context_id=target.context_id,
      active_official_decision_id=candidate.id
    from target, candidate
    where sheets.active_official_decision_id=candidate.id;
    update public.pachanga_competition_match_contexts contexts set status='official'
    where contexts.id=(
      select target_contexts.id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts target_contexts
        on target_contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code='QUARTERFINAL'
      order by nodes.node_order limit 1
    );
  ` : "";
  const decisionId = harness.query(database, `
    set session_replication_role=replica;
    with target as (
      select nodes.canonical_match_id, contexts.id as context_id
      from public.pachanga_tournament_bracket_nodes nodes
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id=nodes.canonical_match_id
      where nodes.round_code='QUARTERFINAL'
      order by nodes.node_order limit 1
    ), candidate as (
      select decisions.id
      from public.pachanga_competition_official_result_decisions decisions
      where not exists (
        select 1 from public.pachanga_tournament_knockout_result_resolutions resolutions
        where resolutions.official_result_decision_id=decisions.id
      )
      order by decisions.server_sequence, decisions.id limit 1
    )
    update public.pachanga_competition_official_result_decisions decisions set
      canonical_match_id=target.canonical_match_id,
      competition_match_context_id=target.context_id,
      supersedes_decision_id=null,
      outcome='MIRROR_SPORTING_RESULT',
      effective_score_home=1,
      effective_score_away=1,
      operation_id=gen_random_uuid(),
      reason_code='r6c.negative.tie'
    from target, candidate where decisions.id=candidate.id;
    with candidate as (
      select decisions.id
      from public.pachanga_competition_official_result_decisions decisions
      join public.pachanga_tournament_bracket_nodes nodes
        on nodes.canonical_match_id=decisions.canonical_match_id
      where nodes.round_code='QUARTERFINAL'
      order by decisions.server_sequence, decisions.id limit 1
    )
    update private.pachanga_competition_official_result_evidence evidence_rows set
      evidence=jsonb_build_object('knockout', ${quote(JSON.stringify(evidence))}::jsonb)
    from candidate where evidence_rows.official_result_decision_id=candidate.id;
    ${activateDecision}
    set session_replication_role=origin;
    select decisions.id
    from public.pachanga_competition_official_result_decisions decisions
    join public.pachanga_tournament_bracket_nodes nodes
      on nodes.canonical_match_id=decisions.canonical_match_id
    where nodes.round_code='QUARTERFINAL'
    order by decisions.server_sequence, decisions.id limit 1;
  `, "prepare isolated R6C official decision");
  assert.match(decisionId, /^[0-9a-f-]{36}$/i);
  return decisionId;
}

try {
  fixture.prepareR6b(r6bBase);
  fixture.prepareR6c(generatedBase, r6cCheckpointMarkers.quarterfinalsGenerated);

  {
    const database = cloneR6b("qualification_unpublished");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_tournament_qualification_snapshots snapshots
      set status='READY', published_by=null, published_at=null
      where snapshots.id=(select current_qualification_snapshot_id
        from public.pachanga_tournament_group_stage_states);
      set session_replication_role=origin;
    `, "make R6C qualification unpublished");
    expectError(database, "qualification_not_published", commandSql(
      database, "bracket.activate", { reason: "Reject unpublished qualification" },
      OWNER_ID, stateRevision(database),
    ), /TOURNAMENT_BRACKET_INPUT_STALE|TOURNAMENT_QUALIFICATION_NOT_PUBLISHED/i);
  }

  {
    const database = cloneR6b("template_stale");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_tournament_bracket_templates templates
      set qualification_snapshot_id=(
        select snapshots.id
        from public.pachanga_tournament_qualification_snapshots snapshots
        where snapshots.id<>(select current_qualification_snapshot_id
          from public.pachanga_tournament_group_stage_states)
        order by snapshots.server_sequence desc, snapshots.id desc limit 1
      )
      where templates.id=(select current_bracket_template_id
        from public.pachanga_tournament_group_stage_states);
      set session_replication_role=origin;
    `, "make R6C template stale");
    expectError(database, "bracket_template_stale", commandSql(
      database, "bracket.activate", { reason: "Reject stale bracket template" },
      OWNER_ID, stateRevision(database),
    ), /TOURNAMENT_BRACKET_INPUT_STALE/i);
  }

  {
    const database = cloneR6b("duplicate_entry");
    harness.query(database, `
      set session_replication_role=replica;
      with ranked as (
        select slots.id, first_value(slots.resolved_entry_id) over (
          order by slots.bracket_order
        ) first_entry, row_number() over (order by slots.bracket_order) row_number
        from public.pachanga_tournament_bracket_slots slots
        where slots.bracket_template_id=(select current_bracket_template_id
          from public.pachanga_tournament_group_stage_states)
      )
      update public.pachanga_tournament_bracket_slots slots
      set resolved_entry_id=ranked.first_entry
      from ranked where slots.id=ranked.id and ranked.row_number=2;
      set session_replication_role=origin;
    `, "duplicate R6C template entry");
    expectError(database, "duplicate_slot_and_team", commandSql(
      database, "bracket.activate", { reason: "Reject duplicate participant" },
      OWNER_ID, stateRevision(database),
    ), /TOURNAMENT_BRACKET_TEMPLATE_INVALID|TOURNAMENT_BRACKET_DUPLICATE_ENTRY/i);
  }

  {
    const database = cloneR6b("source_unresolved");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_tournament_bracket_slots slots
      set resolved_entry_id=null, status='PENDING_SOURCE'
      where slots.id=(
        select selected.id from public.pachanga_tournament_bracket_slots selected
        where selected.bracket_template_id=(select current_bracket_template_id
          from public.pachanga_tournament_group_stage_states)
        order by selected.bracket_order limit 1
      );
      set session_replication_role=origin;
    `, "make R6C source unresolved");
    expectError(database, "unresolved_source", commandSql(
      database, "bracket.activate", { reason: "Reject unresolved source" },
      OWNER_ID, stateRevision(database),
    ), /TOURNAMENT_BRACKET_TEMPLATE_INVALID|TOURNAMENT_BRACKET_SOURCE_UNRESOLVED/i);
  }

  {
    const database = harness.clone(generatedBase, "duplicate_match");
    const nodeId = firstNode(database);
    const beforeMatch = harness.query(database, `
      select canonical_match_id from public.pachanga_tournament_bracket_nodes where id=${quote(nodeId)}::uuid;
    `);
    const response = JSON.parse(harness.query(database, commandSql(
      database, "bracket.node.generate_match", { nodeId, reason: "No duplicate match" },
    ), "replay R6C match generation"));
    const snapshotNode = response.snapshot.rounds
      .flatMap((round) => round.nodes)
      .find((node) => node.id === nodeId);
    assert.equal(snapshotNode.match.canonicalMatchId, beforeMatch);
    assert.equal(Number(harness.query(database, `
      select count(*) from public.pachanga_competition_match_contexts contexts
      where contexts.canonical_match_id=${quote(beforeMatch)}::uuid;
    `)), 1);
    cases.push("match_generated_twice");
  }

  {
    const database = harness.clone(generatedBase, "nonofficial_result");
    expectError(database, "result_not_official", commandSql(
      database, "bracket.result.advance",
      { officialDecisionId: randomUUID(), reason: "Reject non-official result" },
    ), /TOURNAMENT_OFFICIAL_DECISION_NOT_FOUND/i);
  }

  {
    const database = harness.clone(generatedBase, "inactive_official_result");
    const decisionId = repurposeOfficialDecision(database, {
      scoreAfterRegulationHome: 2,
      scoreAfterRegulationAway: 0,
      extraTimePlayed: false,
    }, { active: false });
    expectError(database, "inactive_official_decision", commandSql(
      database, "bracket.result.advance",
      { officialDecisionId: decisionId, reason: "Reject inactive official decision" },
    ), /TOURNAMENT_KNOCKOUT_OFFICIAL_DECISION_INVALID/i);
  }

  {
    const database = harness.clone(generatedBase, "unresolved_tie");
    const decisionId = repurposeOfficialDecision(database, {
      scoreAfterRegulationHome: 1,
      scoreAfterRegulationAway: 1,
      extraTimePlayed: false,
    });
    expectError(database, "tie_without_tiebreak", commandSql(
      database, "bracket.result.advance",
      { officialDecisionId: decisionId, reason: "Reject unresolved tie" },
    ), /KNOCKOUT_WINNER_REQUIRED|TOURNAMENT_EXTRA_TIME_REQUIRED/i);
  }

  {
    const database = harness.clone(generatedBase, "tied_shootout");
    const decisionId = repurposeOfficialDecision(database, {
      scoreAfterRegulationHome: 1,
      scoreAfterRegulationAway: 1,
      extraTimePlayed: true,
      scoreAfterExtraTimeHome: 1,
      scoreAfterExtraTimeAway: 1,
      shootoutHome: 4,
      shootoutAway: 4,
    });
    expectError(database, "tied_shootout", commandSql(
      database, "bracket.result.advance",
      { officialDecisionId: decisionId, reason: "Reject tied shootout" },
    ), /KNOCKOUT_WINNER_REQUIRED/i);
  }

  {
    const database = harness.clone(generatedBase, "forged_winner");
    expectError(database, "winner_sent_by_client", commandSql(
      database, "bracket.node.generate_match",
      { nodeId: firstNode(database), winnerEntryId: randomUUID(), reason: "Forged winner" },
    ), /TOURNAMENT_SERVER_FIELDS_FORBIDDEN/i);
  }

  {
    const database = harness.clone(generatedBase, "referee_advance");
    const outsiderId = harness.query(database, `
      select teams.owner_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id=entries.team_id
      join public.pachanga_competitions competitions on competitions.id=entries.competition_id
      where competitions.slug='r6a-concurrency-fixture'
        and teams.owner_id<>${quote(OWNER_ID)}::uuid
      order by teams.owner_id limit 1;
    `, "select R6C referee-like actor");
    expectError(database, "referee_cannot_advance", commandSql(
      database, "bracket.result.advance",
      { officialDecisionId: randomUUID(), reason: "Referee cannot advance" },
      outsiderId,
    ), /TOURNAMENT_RESULT_MANAGER_REQUIRED/i);
  }

  {
    const database = harness.clone(generatedBase, "advanced_formats");
    expectError(database, "two_leg_payload", commandSql(
      database, "bracket.node.resolve",
      { nodeId: firstNode(database), tieFormat: "TWO_LEG_AGGREGATE", reason: "Reject two leg" },
    ), /TOURNAMENT_KNOCKOUT_NODE_PAYLOAD_INVALID/i);
    expectError(database, "double_elimination_payload", commandSql(
      database, "bracket.node.resolve",
      { nodeId: firstNode(database), doubleElimination: true, reason: "Reject double elimination" },
    ), /TOURNAMENT_KNOCKOUT_NODE_PAYLOAD_INVALID/i);
  }

  {
    const database = harness.clone(generatedBase, "public_discovery");
    expectError(database, "public_discovery", `${claims(PLATFORM_ID)}
      select public.command_pachanga_tournament_knockout_platform_v1(
        ${quote(randomUUID())}::uuid,
        '00000000-0000-0000-0000-00000000c6c1'::uuid,
        (select revision from private.pachanga_competition_foundation_settings where singleton),
        'tournament.knockout.flags.set',
        '{"publicDiscoveryEnabled":true,"reason":"Must remain private"}'::jsonb,
        ${quote(metadata)}::jsonb
      );
    `, /INVALID_TOURNAMENT_KNOCKOUT_PLATFORM_COMMAND|PAYLOAD|PUBLIC_DISCOVERY/i);
  }

  {
    const database = harness.clone(generatedBase, "direct_write");
    expectError(database, "direct_table_write", `
      set role authenticated;
      update public.pachanga_tournament_bracket_nodes set status='advanced';
    `, /permission denied|insufficient privilege/i);
  }

  assert.equal(Number(harness.query(generatedBase, `
    select count(*) from public.pachanga_tournament_bracket_nodes nodes
    where nodes.canonical_match_id is not null
      and exists (
        select 1 from public.pachanga_tournament_bracket_node_slots slots
        where slots.bracket_node_id=nodes.id and slots.source_kind='BYE'
      );
  `)), 0, "a BYE must never create a CanonicalMatch");
  cases.push("bye_creates_no_match");

  process.stdout.write(`R6C_NEGATIVE_REPORT|${JSON.stringify({
    cases,
    directWrites: 0,
    advancedFormats: "FAIL_CLOSED",
    publicDiscovery: "OFF",
  })}\n`);
} finally {
  harness.cleanup();
}
