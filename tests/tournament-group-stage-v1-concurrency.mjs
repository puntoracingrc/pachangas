import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createR6bPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const OWNER_ID = "63010000-0000-4000-8000-000000000001";
const CLIENT_METADATA = {
  clientVersion: "6.1.0+r6b-concurrency",
  installedMode: "standalone",
  serviceWorkerVersion: "r6b-concurrency",
  surface: "r6b_concurrency",
};
const harness = createR6bPostgresHarness("concurrency");
const psqlBin = process.env.PSQL_BIN || "psql";
const source = readFileSync(resolve(harness.root, "tests/tournament-group-stage-v1-db.sql"), "utf8")
  .replace(
    "\\ir tournament-foundation-draw-v1-fixture.sql",
    `\\i '${resolve(harness.root, "tests/tournament-foundation-draw-v1-fixture.sql").replaceAll("'", "''")}'`,
  );

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function committedPrefix(marker) {
  const position = source.indexOf(marker);
  assert.notEqual(position, -1, `R6B concurrency marker missing: ${marker}`);
  return `${source.slice(0, position)}\ncommit;\n`;
}

function fixtureContext(database) {
  return JSON.parse(harness.query(database, `
    with competition as (
      select competitions.*
      from public.pachanga_competitions competitions
      where competitions.slug='r6a-concurrency-fixture'
    ), selected_context as (
      select contexts.*
      from public.pachanga_competition_match_contexts contexts
      join competition on competition.id=contexts.competition_id
      order by contexts.server_sequence, contexts.id
      limit 1
    )
    select jsonb_build_object(
      'competitionId', competition.id,
      'competitionRevision', competition.tournament_revision,
      'drawPlanId', draw_plan.id,
      'drawRevisionId', draw_plan.current_revision_id,
      'stateId', state.id,
      'stateRevision', state.revision,
      'stateStatus', state.status,
      'entryId', entry.id,
      'entryOwnerId', team.owner_id,
      'groupId', group_map.competition_group_id,
      'contextId', selected_context.id,
      'contextRevision', selected_context.revision,
      'scoreHome', official.effective_score_home,
      'scoreAway', official.effective_score_away,
      'standingStateId', standing.id,
      'standingRevision', standing.revision,
      'qualificationSnapshotId', state.current_qualification_snapshot_id,
      'bracketTemplateId', state.current_bracket_template_id
    )::text
    from competition
    join public.pachanga_competition_draw_plans draw_plan
      on draw_plan.competition_id=competition.id
    left join public.pachanga_tournament_group_stage_states state
      on state.competition_id=competition.id
    left join lateral (
      select entries.*
      from public.pachanga_competition_entries entries
      where entries.competition_id=competition.id and entries.status='accepted'
      order by entries.server_sequence, entries.id
      limit 1
    ) entry on true
    left join public.pachanga_groups team on team.id=entry.team_id
    left join lateral (
      select mappings.*
      from public.pachanga_tournament_group_schedule_plans mappings
      where mappings.group_stage_state_id=state.id
      order by mappings.server_sequence, mappings.id
      limit 1
    ) group_map on true
    left join selected_context on true
    left join public.pachanga_competition_standing_states standing
      on standing.stage_id=selected_context.stage_id
     and standing.competition_group_id=selected_context.competition_group_id
    left join public.pachanga_competition_match_sheets sheet
      on sheet.competition_match_context_id=selected_context.id
    left join public.pachanga_competition_official_result_decisions official
      on official.id=sheet.active_official_decision_id;
  `, "read R6B concurrency context"));
}

function transaction(actorId, statement, delayMs = 0) {
  const delay = delayMs > 0 ? `select pg_sleep(${delayMs / 1000});` : "";
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='90s';
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    ${delay}
    ${statement}
    commit;
  `;
}

function r6bSql(context, action, operationId = randomUUID(), payload = {}, delayMs = 0) {
  return transaction(OWNER_ID, `
    select public.command_pachanga_tournament_group_stage_v1(
      ${quote(operationId)}::uuid,
      ${quote(context.competitionId)}::uuid,
      ${context.stateId ? context.stateRevision : context.competitionRevision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `, delayMs);
}

function drawSql(context, action, payload, actorId = OWNER_ID, delayMs = 0) {
  return transaction(actorId, `
    select public.command_pachanga_tournament_draw_v1(
      ${quote(randomUUID())}::uuid,
      ${quote(context.competitionId)}::uuid,
      ${context.competitionRevision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
  `, delayMs);
}

function r4cSql(context, action, expectedRevision, payload, delayMs = 0) {
  return r4cContextSql(
    OWNER_ID,
    context.contextId,
    action,
    expectedRevision,
    payload,
    delayMs,
  );
}

function r4cContextSql(actorId, contextId, action, expectedRevision, payload, delayMs = 0) {
  return transaction(actorId, `
    select public.command_pachanga_league_match_operations_v1(
      ${quote(randomUUID())}::uuid,
      ${quote(contextId)}::uuid,
      ${expectedRevision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      ${quote(JSON.stringify(CLIENT_METADATA))}::jsonb
    );
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
      stderr: stderr.trim(),
      stdout: stdout.trim(),
    }));
    child.stdin.end(sql);
  });
}

function invariantSnapshot(database) {
  return JSON.parse(harness.query(database, `
    with competition as (
      select id from public.pachanga_competitions
      where slug='r6a-concurrency-fixture'
    )
    select jsonb_build_object(
      'acceptedEntries', (
        select count(*) from public.pachanga_competition_entries entries
        join competition on competition.id=entries.competition_id
        where entries.status='accepted'
      ),
      'duplicateMemberships', (
        select count(*) from (
          select memberships.entry_id
          from public.pachanga_competition_stage_memberships memberships
          join public.pachanga_competition_stages stages on stages.id=memberships.stage_id
          join public.pachanga_competition_editions editions on editions.id=stages.edition_id
          join competition on competition.id=editions.competition_id
          where memberships.status='active'
          group by memberships.entry_id
          having count(distinct memberships.competition_group_id)>1
        ) duplicates
      ),
      'contexts', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        join competition on competition.id=contexts.competition_id
      ),
      'canonicalMatches', (
        select count(distinct contexts.canonical_match_id)
        from public.pachanga_competition_match_contexts contexts
        join competition on competition.id=contexts.competition_id
      ),
      'duplicateCanonicalBindings', (
        select count(*) from (
          select contexts.schedule_item_id
          from public.pachanga_competition_match_contexts contexts
          join competition on competition.id=contexts.competition_id
          group by contexts.schedule_item_id
          having count(*)>1
        ) duplicates
      ),
      'knockoutMatches', 0
    )::text;
  `, "read R6B concurrency invariants"));
}

async function race(database, label, leftSql, rightSql, expected = {}) {
  const results = await Promise.all([
    runConcurrent(database, leftSql, `${label}:left`),
    runConcurrent(database, rightSql, `${label}:right`),
  ]);
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one stale/conflict loser: ${JSON.stringify(results)}`);
  assert.match(
    `${losers[0].stdout}\n${losers[0].stderr}`,
    /STALE_REVISION|PT409|TOURNAMENT_[A-Z_]+|DRAW_[A-Z_]+|R4C_[A-Z_]+/i,
    `${label} loser must expose a stable conflict`,
  );
  if (expected.winner) {
    assert.equal(winners[0].label, `${label}:${expected.winner}`, `${label} winner mismatch`);
  }
  const invariants = invariantSnapshot(database);
  assert.equal(invariants.acceptedEntries, 16, `${label} altered the frozen participant set`);
  assert.equal(invariants.duplicateMemberships, 0, `${label} duplicated a Group membership`);
  assert.equal(invariants.contexts, invariants.canonicalMatches, `${label} duplicated a CanonicalMatch binding`);
  assert.equal(invariants.duplicateCanonicalBindings, 0, `${label} duplicated a schedule item binding`);
  assert.equal(invariants.knockoutMatches, 0, `${label} generated a knockout match`);
  if (expected.contexts !== undefined) {
    assert.equal(invariants.contexts, expected.contexts, `${label} changed the canonical match count`);
  }
  if (expected.contextsByWinner) {
    const winnerSide = winners[0].label.endsWith(":left") ? "left" : "right";
    assert.equal(
      invariants.contexts,
      expected.contextsByWinner[winnerSide],
      `${label} produced a partial canonical publication`,
    );
  }
  return {
    conflict: `${losers[0].stdout}\n${losers[0].stderr}`.match(
      /STALE_REVISION|TOURNAMENT_[A-Z_]+|DRAW_[A-Z_]+|R4C_[A-Z_]+/i,
    )?.[0] ?? "PT409",
    label,
    winner: winners[0].label.endsWith(":left") ? "left" : "right",
  };
}

function execute(database, sql, label) {
  return harness.psql(database, ["-Atq"], label, sql);
}

function addGroupSlots(database) {
  const groups = JSON.parse(harness.query(database, `
    select jsonb_agg(jsonb_build_object(
      'id', groups.id,
      'groupOrder', groups.group_order
    ) order by groups.group_order)::text
    from public.pachanga_competition_groups groups
    join public.pachanga_competition_stages stages on stages.id=groups.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture';
  `, "enumerate R6B concurrency Groups"));
  assert.equal(groups.length, 4, "R6B concurrency fixture requires four Groups");
  const baseDate = new Date();
  baseDate.setUTCHours(0, 0, 0, 0);
  baseDate.setUTCDate(baseDate.getUTCDate() + 31);
  for (const group of groups) {
    const slots = Array.from({ length: 6 }, (_, index) => {
      const startsAt = new Date(baseDate.getTime() + index * 24 * 60 * 60 * 1000);
      const endsAt = new Date(startsAt.getTime() + 90 * 60 * 1000);
      return {
        endsAt: endsAt.toISOString(),
        startsAt: startsAt.toISOString(),
        timezone: "Europe/Madrid",
        venueLabel: `R6B Concurrency Group ${group.groupOrder}`,
      };
    });
    const context = fixtureContext(database);
    execute(
      database,
      r6bSql(context, "group_schedule.create", randomUUID(), { groupId: group.id, slots }),
      `create R6B concurrency slots for Group ${group.groupOrder}`,
    );
  }
}

function runR6b(database, action, payload = {}) {
  const context = fixtureContext(database);
  execute(database, r6bSql(context, action, randomUUID(), payload), `prepare R6B ${action}`);
  return fixtureContext(database);
}

function completeCanonicalResults(database) {
  harness.query(database, `
    insert into public.pachanga_competition_staff_assignments(
      competition_id, user_id, staff_role, status, assigned_by
    ) values (
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
      '${OWNER_ID}', 'competition_director', 'active', '${OWNER_ID}'
    ) on conflict do nothing;
  `, "grant R6B concurrency result authority");
  const matches = JSON.parse(harness.query(database, `
    select jsonb_agg(jsonb_build_object(
      'id', contexts.id,
      'homeEntryId', contexts.home_entry_id,
      'awayEntryId', contexts.away_entry_id,
      'homeOwnerId', home_teams.owner_id,
      'awayOwnerId', away_teams.owner_id,
      'homeNumber', substring(home_teams.team_code from 3)::integer,
      'awayNumber', substring(away_teams.team_code from 3)::integer
    ) order by contexts.server_sequence, contexts.id)::text
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_entries home_entries on home_entries.id=contexts.home_entry_id
    join public.pachanga_groups home_teams on home_teams.id=home_entries.team_id
    join public.pachanga_competition_entries away_entries on away_entries.id=contexts.away_entry_id
    join public.pachanga_groups away_teams on away_teams.id=away_entries.team_id
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture';
  `, "enumerate R6B concurrency matches"));
  assert.equal(matches.length, 24, "R6B result checkpoint requires 24 matches");
  for (const match of matches) {
    harness.query(database, `
      update public.pachanga_competition_match_contexts contexts set
        status='played', revision=contexts.revision+1,
        server_sequence=nextval('private.pachanga_competition_sequence'),
        updated_at=clock_timestamp()
      where contexts.id=${quote(match.id)}::uuid;
      insert into public.pachanga_competition_match_sheets(
        canonical_match_id, competition_match_context_id, created_by
      ) select contexts.canonical_match_id, contexts.id, '${OWNER_ID}'::uuid
        from public.pachanga_competition_match_contexts contexts
        where contexts.id=${quote(match.id)}::uuid;
    `, "prepare R6B played match boundary");
    const scoreHome = match.homeNumber < match.awayNumber ? 2 : 0;
    const scoreAway = match.awayNumber < match.homeNumber ? 2 : 0;
    let revision = Number(harness.query(database, `
      select revision from public.pachanga_competition_match_contexts
      where id=${quote(match.id)}::uuid;
    `));
    execute(database, r4cContextSql(match.homeOwnerId, match.id, "sporting_result.submit", revision, {
      entryId: match.homeEntryId,
      scoreAway,
      scoreHome,
    }), "submit R6B concurrency result");
    revision = Number(harness.query(database, `
      select revision from public.pachanga_competition_match_contexts
      where id=${quote(match.id)}::uuid;
    `));
    execute(database, r4cContextSql(match.awayOwnerId, match.id, "sporting_result.accept", revision, {
      entryId: match.awayEntryId,
    }), "accept R6B concurrency result");
    revision = Number(harness.query(database, `
      select revision from public.pachanga_competition_match_contexts
      where id=${quote(match.id)}::uuid;
    `));
    execute(database, r4cContextSql(OWNER_ID, match.id, "official_result.publish", revision, {
      outcome: "MIRROR_SPORTING_RESULT",
      publicExplanation: "Resultado bilateral confirmado.",
      reasonCode: "r6b.concurrency.official",
    }), "publish R6B concurrency official result");
  }
  assert.equal(Number(harness.query(database, `
    select count(*) from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture' and contexts.status='official';
  `)), 24, "R6B concurrency checkpoint must have 24 official matches");
  assert.equal(Number(harness.query(database, `
    select count(*) from public.pachanga_competition_standing_states states
    join public.pachanga_competition_stages stages on stages.id=states.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture'
      and states.health_status='CURRENT' and states.current_snapshot_id is not null;
  `)), 4, "R6B concurrency checkpoint must have four current standings");
}

const baseDatabase = harness.databaseName("base");
const reports = [];

try {
  harness.bootstrap(baseDatabase);

  const preTemplate = harness.clone(baseDatabase, "pre_template");
  execute(preTemplate, committedPrefix("insert into r6b_test_state values (\n  'prepare_expected',"), "load R6B pre-prepare template");

  const preparedTemplate = harness.clone(preTemplate, "prepared_template");
  runR6b(preparedTemplate, "group_stage.prepare");

  const slotsTemplate = harness.clone(preparedTemplate, "slots_template");
  addGroupSlots(slotsTemplate);

  const validatedTemplate = harness.clone(slotsTemplate, "validated_template");
  runR6b(validatedTemplate, "group_schedule.generate");
  runR6b(validatedTemplate, "group_schedule.validate");

  const resultsTemplate = harness.clone(validatedTemplate, "results_template");
  runR6b(resultsTemplate, "group_schedule.publish");
  runR6b(resultsTemplate, "group_stage.activate");
  completeCanonicalResults(resultsTemplate);

  const qualificationReadyTemplate = harness.clone(resultsTemplate, "qualification_ready_template");
  runR6b(qualificationReadyTemplate, "qualification.rebuild");
  runR6b(qualificationReadyTemplate, "qualification.validate");

  const qualificationPublishedTemplate = harness.clone(qualificationReadyTemplate, "qualification_published_template");
  runR6b(qualificationPublishedTemplate, "qualification.publish");

  const bracketDraftTemplate = harness.clone(qualificationPublishedTemplate, "bracket_draft_template");
  runR6b(bracketDraftTemplate, "bracket_template.create");

  {
    const database = harness.clone(preTemplate, "two_preparations");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "two preparations",
      r6bSql(context, "group_stage.prepare"),
      r6bSql(context, "group_stage.prepare"),
      { contexts: 0 },
    ));
  }

  {
    const database = harness.clone(slotsTemplate, "generate_draw_change");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "generate vs DrawRevision change",
      r6bSql(context, "group_schedule.generate"),
      drawSql(context, "draw.regenerate", {
        planId: context.drawPlanId,
        publicSeed: "R6B-CONCURRENT-DRAW-CHANGE",
        reason: "R6B concurrent DrawRevision change",
        seedMode: "CUSTOM_PUBLIC_SEED",
      }, OWNER_ID, 200),
      { contexts: 0, winner: "left" },
    ));
  }

  {
    const database = harness.clone(slotsTemplate, "generate_withdrawal");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "generate vs participant withdrawal",
      r6bSql(context, "group_schedule.generate"),
      drawSql(context, "participant.withdraw", {
        entryId: context.entryId,
        reason: "R6B concurrent frozen participant withdrawal",
      }, context.entryOwnerId, 200),
      { contexts: 0, winner: "left" },
    ));
  }

  {
    const database = harness.clone(validatedTemplate, "publish_schedule_edit");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "publish vs schedule edit",
      r6bSql(context, "group_schedule.publish"),
      r6bSql(context, "group_schedule.create", randomUUID(), {
        groupId: context.groupId,
        slots: [{
          endsAt: "2027-10-01T19:30:00.000Z",
          startsAt: "2027-10-01T18:00:00.000Z",
          timezone: "Europe/Madrid",
          venueLabel: "R6B Concurrent Edit",
        }],
      }),
      { contextsByWinner: { left: 24, right: 0 } },
    ));
  }

  {
    const database = harness.clone(validatedTemplate, "two_publishes");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "two publishes",
      r6bSql(context, "group_schedule.publish"),
      r6bSql(context, "group_schedule.publish"),
      { contexts: 24 },
    ));
  }

  {
    const database = harness.clone(resultsTemplate, "official_standings");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "official result vs standings rebuild",
      r4cSql(context, "official_result.supersede", context.contextRevision, {
        outcome: "CORRECTED_EFFECTIVE_SCORE",
        publicExplanation: "Corrección concurrente R6B.",
        reasonCode: "r6b.concurrency.official",
        scoreAway: context.scoreAway > context.scoreHome ? context.scoreAway + 1 : context.scoreAway,
        scoreHome: context.scoreHome > context.scoreAway ? context.scoreHome + 1 : context.scoreHome,
      }),
      r4cSql(context, "standings.rebuild", context.standingRevision, { rebuildKind: "FULL_AUDIT" }, 200),
      { contexts: 24, winner: "left" },
    ));
  }

  {
    const database = harness.clone(qualificationPublishedTemplate, "result_completion");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "result correction vs group completion",
      r6bSql(context, "group_stage.complete"),
      r4cSql(context, "official_result.supersede", context.contextRevision, {
        outcome: "CORRECTED_EFFECTIVE_SCORE",
        publicExplanation: "Corrección posterior al cierre R6B.",
        reasonCode: "r6b.concurrency.complete",
        scoreAway: 2,
        scoreHome: 2,
      }, 200),
      { contexts: 24, winner: "left" },
    ));
  }

  {
    const database = harness.clone(resultsTemplate, "two_qualification_rebuilds");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "two qualification rebuilds",
      r6bSql(context, "qualification.rebuild"),
      r6bSql(context, "qualification.rebuild"),
      { contexts: 24 },
    ));
  }

  {
    const database = harness.clone(qualificationReadyTemplate, "qualification_result");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "qualification publish vs result correction",
      r6bSql(context, "qualification.publish"),
      r4cSql(context, "official_result.supersede", context.contextRevision, {
        outcome: "CORRECTED_EFFECTIVE_SCORE",
        publicExplanation: "Corrección concurrente a clasificación R6B.",
        reasonCode: "r6b.concurrency.qualification",
        scoreAway: 3,
        scoreHome: 3,
      }, 200),
      { contexts: 24, winner: "left" },
    ));
  }

  {
    const database = harness.clone(bracketDraftTemplate, "bracket_supersession");
    const context = fixtureContext(database);
    reports.push(await race(
      database,
      "bracket template publish vs qualification supersession",
      r6bSql(context, "qualification.rebuild"),
      r6bSql(context, "bracket_template.publish", randomUUID(), {}, 200),
      { contexts: 24 },
    ));
  }

  assert.equal(reports.length, 10);
  process.stdout.write(`R6B_CONCURRENCY_REPORT|${JSON.stringify({
    canonicalMatches: 24,
    knockoutMatches: 0,
    races: reports,
    result: "10/10 one winner and one stale/conflict",
  })}\n`);
} finally {
  harness.cleanup();
}
