import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createR6bPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const OWNER_ID = "63010000-0000-4000-8000-000000000001";
const OUTSIDER_ID = "65010000-0000-4000-8000-000000000099";
const CLIENT_METADATA = {
  clientVersion: "6.1.0+r6b-negatives",
  installedMode: "browser",
  serviceWorkerVersion: "r6b-negatives",
  surface: "r6b_negatives",
};
const harness = createR6bPostgresHarness("negatives");
const source = readFileSync(resolve(harness.root, "tests/tournament-group-stage-v1-db.sql"), "utf8")
  .replace(
    "\\ir tournament-foundation-draw-v1-fixture.sql",
    `\\i '${resolve(harness.root, "tests/tournament-foundation-draw-v1-fixture.sql").replaceAll("'", "''")}'`,
  );
const reports = [];

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function committedPrefix(marker) {
  const position = source.indexOf(marker);
  assert.notEqual(position, -1, `R6B negative checkpoint marker missing: ${marker}`);
  return `${source.slice(0, position)}\ncommit;\n`;
}

function transaction(actorId, statement, role = "authenticated") {
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='90s';
    set local role ${role};
    select set_config(
      'request.jwt.claims',
      ${quote(JSON.stringify({ role, sub: actorId }))},
      true
    );
    ${statement}
    commit;
  `;
}

function context(database) {
  return JSON.parse(harness.query(database, `
    with competition as (
      select competitions.* from public.pachanga_competitions competitions
      where competitions.slug='r6a-concurrency-fixture'
    ), selected_context as (
      select contexts.*
      from public.pachanga_competition_match_contexts contexts
      join competition on competition.id=contexts.competition_id
      order by contexts.server_sequence, contexts.id limit 1
    )
    select jsonb_build_object(
      'competitionId', competition.id,
      'competitionRevision', competition.tournament_revision,
      'stateId', state.id,
      'stateRevision', state.revision,
      'contextId', selected_context.id,
      'contextRevision', selected_context.revision,
      'canonicalMatchId', selected_context.canonical_match_id,
      'homeEntryId', selected_context.home_entry_id,
      'homeOwnerId', home_team.owner_id,
      'groupId', selected_context.competition_group_id
    )::text
    from competition
    left join public.pachanga_tournament_group_stage_states state
      on state.competition_id=competition.id
    left join selected_context on true
    left join public.pachanga_competition_entries home_entry
      on home_entry.id=selected_context.home_entry_id
    left join public.pachanga_groups home_team on home_team.id=home_entry.team_id;
  `, "read R6B negative fixture context"));
}

function r6bSql(fixture, action, actorId = OWNER_ID, payload = {}) {
  return transaction(actorId, `
    select public.command_pachanga_tournament_group_stage_v1(
      ${quote(randomUUID())}::uuid,
      ${quote(fixture.competitionId)}::uuid,
      ${fixture.stateId ? fixture.stateRevision : fixture.competitionRevision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `);
}

function r4cSql(fixture, action, actorId, payload) {
  return transaction(actorId, `
    select public.command_pachanga_league_match_operations_v1(
      ${quote(randomUUID())}::uuid,
      ${quote(fixture.contextId)}::uuid,
      ${fixture.contextRevision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `);
}

function execute(database, sql, label) {
  return harness.psql(database, ["-Atq"], label, sql);
}

function expectFailure(database, label, sql, pattern) {
  let caught;
  try {
    execute(database, sql, label);
  } catch (error) {
    caught = error;
  }
  assert.ok(caught, `${label} unexpectedly succeeded`);
  assert.match(String(caught.message), pattern, `${label} returned the wrong stable failure`);
  reports.push({ label, result: "REJECTED", error: String(caught.message).match(pattern)?.[0] ?? "conflict" });
}

function loadCheckpoint(baseDatabase, name, marker) {
  const database = harness.clone(baseDatabase, name);
  execute(database, committedPrefix(marker), `load R6B ${name} checkpoint`);
  return database;
}

function assertProvisionalThenBlocked(database, label) {
  execute(database, r6bSql(context(database), "qualification.rebuild"), `${label}: rebuild qualification`);
  assert.equal(harness.query(database, `
    select snapshots.status
    from public.pachanga_tournament_group_stage_states states
    join public.pachanga_tournament_qualification_snapshots snapshots
      on snapshots.id=states.current_qualification_snapshot_id
    where states.competition_id=(select id from public.pachanga_competitions
      where slug='r6a-concurrency-fixture');
  `, `${label}: read provisional qualification`), "PROVISIONAL");
  expectFailure(
    database,
    `${label}: validate final qualification`,
    r6bSql(context(database), "qualification.validate"),
    /TOURNAMENT_QUALIFICATION_NOT_READY/,
  );
}

const baseDatabase = harness.databaseName("base");

try {
  harness.bootstrap(baseDatabase);
  const preTemplate = loadCheckpoint(
    baseDatabase,
    "pre_template",
    "insert into r6b_test_state values (\n  'prepare_expected',",
  );
  const preparedTemplate = loadCheckpoint(
    baseDatabase,
    "prepared_template",
    "-- Six globally compatible slots per four-team group.",
  );
  const validatedTemplate = loadCheckpoint(
    baseDatabase,
    "validated_template",
    "insert into r6b_test_state values (\n  'publish_expected',",
  );
  const activatedTemplate = loadCheckpoint(
    baseDatabase,
    "activated_template",
    "-- Build a real R4C result lifecycle for every canonical group match.",
  );
  const resultsTemplate = loadCheckpoint(
    baseDatabase,
    "results_template",
    "insert into r6b_test_state values (\n  'qualification_rebuild_expected',",
  );

  {
    const database = harness.clone(preTemplate, "draw_unpublished");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_draw_plans plans
      set status='validated',published_at=null
      where plans.competition_id=(select id from public.pachanga_competitions
        where slug='r6a-concurrency-fixture');
      set session_replication_role=origin;
    `, "corrupt R6B published DrawPlan fixture");
    expectFailure(database, "DrawPlan not published", r6bSql(context(database), "group_stage.prepare"),
      /TOURNAMENT_PUBLISHED_GROUP_DRAW_REQUIRED/);
  }

  {
    const database = harness.clone(preTemplate, "freeze_stale");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_participant_freezes freezes
      set rule_revision_id=(
        select entries.rule_revision_id
        from public.pachanga_competition_entries entries
        where entries.competition_id=freezes.competition_id
          and entries.rule_revision_id is distinct from freezes.rule_revision_id
        order by entries.server_sequence limit 1
      )
      where freezes.id=(select plans.participant_freeze_id
        from public.pachanga_competition_draw_plans plans
        join public.pachanga_competitions competitions on competitions.id=plans.competition_id
        where competitions.slug='r6a-concurrency-fixture');
      set session_replication_role=origin;
    `, "corrupt R6B ParticipantFreeze lineage fixture");
    expectFailure(database, "ParticipantFreeze stale", r6bSql(context(database), "group_stage.prepare"),
      /TOURNAMENT_GROUP_STAGE_INPUT_STALE/);
  }

  {
    const database = harness.clone(preTemplate, "entry_withdrawn");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_entries entries set status='withdrawn'
      where entries.id=(select selected.id from public.pachanga_competition_entries selected
        join public.pachanga_competitions competitions on competitions.id=selected.competition_id
        where competitions.slug='r6a-concurrency-fixture' and selected.status='accepted'
        order by selected.server_sequence limit 1);
      set session_replication_role=origin;
    `, "withdraw one frozen R6B Entry fixture");
    expectFailure(database, "withdrawn frozen Entry", r6bSql(context(database), "group_stage.prepare"),
      /TOURNAMENT_GROUP_STAGE_INPUT_STALE/);
  }

  {
    const database = harness.clone(preparedTemplate, "duplicate_group_participant");
    expectFailure(database, "duplicate participant in Group", `
      insert into public.pachanga_competition_stage_memberships(
        id,entry_id,stage_id,division_id,competition_group_id,rule_revision_id,
        status,reason,assigned_by
      ) select gen_random_uuid(),memberships.entry_id,memberships.stage_id,
        memberships.division_id,memberships.competition_group_id,
        memberships.rule_revision_id,'active','R6B duplicate participant fixture',
        memberships.assigned_by
      from public.pachanga_competition_stage_memberships memberships
      order by memberships.server_sequence limit 1;
    `, /duplicate key value|pachanga_competition_stage_membership_active_idx/i);
  }

  {
    const database = harness.clone(preparedTemplate, "team_two_groups");
    expectFailure(database, "Team in two Groups", `
      insert into public.pachanga_competition_stage_memberships(
        id,entry_id,stage_id,division_id,competition_group_id,rule_revision_id,
        status,reason,assigned_by
      ) select gen_random_uuid(),source.entry_id,source.stage_id,source.division_id,
        target.id,source.rule_revision_id,'active','R6B cross-Group duplicate fixture',
        source.assigned_by
      from public.pachanga_competition_stage_memberships source
      join public.pachanga_competition_groups target
        on target.stage_id=source.stage_id
       and target.id is distinct from source.competition_group_id
      order by source.server_sequence,target.group_order limit 1;
    `, /duplicate key value|pachanga_competition_stage_membership_active_idx/i);
  }

  {
    const database = harness.clone(validatedTemplate, "duplicate_fixture");
    expectFailure(database, "duplicate fixture", `
      insert into public.pachanga_competition_schedule_items(
        id,schedule_revision_id,round_id,home_entry_id,away_entry_id,pairing_key,
        leg_number,slot_id,scheduled_start,scheduled_end,timezone,venue_id,
        venue_label,venue_status,status,revision
      ) select gen_random_uuid(),items.schedule_revision_id,items.round_id,
        items.home_entry_id,items.away_entry_id,items.pairing_key,items.leg_number,
        items.slot_id,items.scheduled_start,items.scheduled_end,items.timezone,
        items.venue_id,items.venue_label,items.venue_status,items.status,items.revision
      from public.pachanga_competition_schedule_items items
      order by items.server_sequence limit 1;
    `, /duplicate key value|pachanga_competition_schedule_items_schedule_revision_id_pairing_key_leg_number_key/i);
  }

  {
    const database = harness.clone(preparedTemplate, "rule_revision_stale");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_draw_plans plans
      set current_revision_id=(select revisions.id
        from public.pachanga_competition_draw_revisions revisions
        where revisions.draw_plan_id=plans.id
          and revisions.id is distinct from plans.current_revision_id
        order by revisions.server_sequence limit 1)
      where plans.competition_id=(select id from public.pachanga_competitions
        where slug='r6a-concurrency-fixture');
      set session_replication_role=origin;
    `, "stale R6B Rule/DrawRevision fixture");
    expectFailure(database, "RuleRevision lineage stale", r6bSql(context(database), "group_schedule.generate"),
      /TOURNAMENT_GROUP_STAGE_INPUT_STALE/);
  }

  {
    const database = harness.clone(activatedTemplate, "unofficial_result");
    let fixture = context(database);
    harness.query(database, `
      update public.pachanga_competition_match_contexts contexts set
        status='played',revision=contexts.revision+1,
        server_sequence=nextval('private.pachanga_competition_sequence'),updated_at=clock_timestamp()
      where contexts.id=${quote(fixture.contextId)}::uuid;
      insert into public.pachanga_competition_match_sheets(
        canonical_match_id,competition_match_context_id,created_by
      ) values (
        ${quote(fixture.canonicalMatchId)}::uuid,${quote(fixture.contextId)}::uuid,
        ${quote(OWNER_ID)}::uuid
      );
    `, "prepare unofficial R6B SportingResult fixture");
    fixture.contextRevision = Number(harness.query(database, `
      select revision from public.pachanga_competition_match_contexts
      where id=${quote(fixture.contextId)}::uuid;
    `, "refresh unofficial R6B MatchContext revision"));
    execute(database, r4cSql(fixture, "sporting_result.submit", fixture.homeOwnerId, {
      entryId: fixture.homeEntryId,
      scoreAway: 1,
      scoreHome: 2,
    }), "submit unofficial R6B SportingResult");
    assert.equal(Number(harness.query(database, `
      select count(*) from public.pachanga_competition_standing_states states
      where states.stage_id=(select stage_id from public.pachanga_competition_match_contexts
        where id=${quote(fixture.contextId)}::uuid);
    `, "read unofficial R6B standings")), 0);
    reports.push({ label: "unofficial result excluded from standings", result: "PASS" });
  }

  {
    const database = harness.clone(resultsTemplate, "pending_dispute");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_sporting_results results set state='disputed'
      where results.id=(select selected.id from public.pachanga_competition_sporting_results selected
        order by selected.server_sequence limit 1);
      update public.pachanga_competition_match_contexts contexts set status='result_pending'
      where contexts.id=(select selected.competition_match_context_id
        from public.pachanga_competition_sporting_results selected
        where selected.state='disputed' order by selected.server_sequence limit 1);
      set session_replication_role=origin;
    `, "prepare pending R6B dispute fixture");
    assertProvisionalThenBlocked(database, "pending dispute cannot close Group");
  }

  {
    const database = harness.clone(resultsTemplate, "postponed_match");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_match_contexts contexts set status='postponed'
      where contexts.id=(select selected.id from public.pachanga_competition_match_contexts selected
        order by selected.server_sequence limit 1);
      set session_replication_role=origin;
    `, "prepare postponed R6B match fixture");
    assertProvisionalThenBlocked(database, "postponed match cannot close Group");
  }

  {
    const database = harness.clone(activatedTemplate, "qualification_too_early");
    expectFailure(database, "qualification published before completion",
      r6bSql(context(database), "qualification.publish"), /TOURNAMENT_QUALIFICATION_NOT_READY/);
  }

  {
    const database = harness.clone(preTemplate, "cross_group_policy_missing");
    harness.query(database, `
      set session_replication_role=replica;
      update public.pachanga_competition_rule_revisions revisions set
        rule_document=jsonb_set(
          jsonb_set(
            jsonb_set(revisions.rule_document,
              '{structure,qualificationPolicy,kind}',
              '"TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP"'::jsonb),
            '{structure,qualificationPolicy,extraQualifierCount}','1'::jsonb),
          '{structure,qualificationPolicy,comparatorCriteria}','[]'::jsonb)
      where revisions.id=(select plans.rule_revision_id
        from public.pachanga_competition_draw_plans plans
        join public.pachanga_competitions competitions on competitions.id=plans.competition_id
        where competitions.slug='r6a-concurrency-fixture');
      set session_replication_role=origin;
    `, "remove R6B cross-Group comparator policy");
    expectFailure(database, "cross-Group policy absent", r6bSql(context(database), "group_stage.prepare"),
      /CROSS_GROUP_QUALIFICATION_POLICY_REQUIRED/);
  }

  {
    const database = harness.clone(preparedTemplate, "knockout_action");
    expectFailure(database, "knockout match generation remains unavailable",
      r6bSql(context(database), "knockout_match.generate"), /INVALID_TOURNAMENT_GROUP_STAGE_COMMAND/);
  }

  {
    const database = harness.clone(preparedTemplate, "progression_action");
    expectFailure(database, "bracket progression remains unavailable",
      r6bSql(context(database), "bracket.progress"), /INVALID_TOURNAMENT_GROUP_STAGE_COMMAND/);
  }

  {
    const database = harness.clone(preparedTemplate, "direct_write");
    expectFailure(database, "authenticated direct R6B table write", transaction(OWNER_ID, `
      insert into public.pachanga_tournament_qualification_snapshots default values;
    `), /permission denied for table pachanga_tournament_qualification_snapshots/i);
  }

  {
    const database = harness.clone(preTemplate, "actor_without_grant");
    const participantOwner = harness.query(database, `
      select teams.owner_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id=entries.team_id
      join public.pachanga_competitions competitions on competitions.id=entries.competition_id
      where competitions.slug='r6a-concurrency-fixture'
        and teams.owner_id is distinct from '${OWNER_ID}'::uuid
      order by entries.server_sequence limit 1;
    `, "read non-organizer R6B participant");
    expectFailure(database, "actor without Tournament grant",
      r6bSql(context(database), "group_stage.prepare", participantOwner),
      /TOURNAMENT_SCHEDULE_MANAGER_REQUIRED/);
  }

  {
    const database = harness.clone(preparedTemplate, "public_discovery");
    const fixture = context(database);
    expectFailure(database, "anonymous Tournament public discovery", transaction(OUTSIDER_ID, `
      select public.get_pachanga_tournament_group_hub_v1(${quote(fixture.competitionId)}::uuid);
    `, "anon"), /permission denied for function get_pachanga_tournament_group_hub_v1|AUTHENTICATION_REQUIRED/i);
    expectFailure(database, "unrelated authenticated Tournament discovery", transaction(OUTSIDER_ID, `
      select public.get_pachanga_tournament_group_hub_v1(${quote(fixture.competitionId)}::uuid);
    `), /TOURNAMENT_READ_FORBIDDEN/);
  }

  assert.equal(reports.length, 18);
  process.stdout.write(`R6B_NEGATIVE_REPORT|${JSON.stringify({
    canonicalCases: reports.length,
    cases: reports,
    directWrites: 0,
    knockoutMatches: 0,
    result: "18/18",
  })}\n`);
} finally {
  harness.cleanup();
}
