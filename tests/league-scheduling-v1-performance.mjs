import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_SCHEDULING_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const infrastructureDump = resolve(tmpdir(), `pachangas-r4b-performance-${suffix}.sql`);
const managerId = "e4010000-0000-4000-8000-000000000003";
const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const suite = readFileSync(resolve(root, "tests/league-scheduling-v1-db.sql"), "utf8");
const baseSetup = suite.slice(0, suite.indexOf("do $body$"));

if (!adminUrl) throw new Error("LEAGUE_SCHEDULING_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4B_PERFORMANCE_LOCAL_DATABASE_REQUIRED");
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function databaseUrl(databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function databaseQuery(databaseName, sql, label) {
  return run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq",
    databaseUrl(databaseName), "-c", sql,
  ], label);
}

function databaseInput(databaseName, sql, label) {
  return run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq",
    databaseUrl(databaseName),
  ], label, sql);
}

function apply(databaseName, files, label) {
  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    databaseUrl(databaseName),
  ];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function dropDatabase(databaseName) {
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname = activity.usename
      where activity.datname='${databaseName}'
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`,
    `terminate ${databaseName}`,
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname='${databaseName}'`,
      `inspect ${databaseName}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4B_PERFORMANCE_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
}

function actorClaims(userId, role = "authenticated") {
  return JSON.stringify({ role, sub: userId }).replaceAll("'", "''");
}

function jsonLine(output) {
  const line = output.split("\n").filter((value) => value.trim().startsWith("{")).at(-1);
  if (!line) throw new Error(`R4B_PERFORMANCE_JSON_MISSING:\n${output}`);
  return JSON.parse(line);
}

function timedJson(databaseName, sql, label) {
  const startedAt = performance.now();
  const value = jsonLine(databaseQuery(databaseName, sql, label));
  return { durationMs: Number((performance.now() - startedAt).toFixed(3)), value };
}

function commandSql({ action, aggregateId, expectedRevision, operationSeed, payload, userId = managerId }) {
  const metadata = JSON.stringify({
    clientVersion: "4.0.0+r4b-performance",
    installedMode: "browser",
    serviceWorkerVersion: "sw-r4b-performance",
    surface: "r4b_performance",
  }).replaceAll("'", "''");
  const encodedPayload = JSON.stringify(payload).replaceAll("'", "''");
  return `
    set lock_timeout = '5s';
    set statement_timeout = '180s';
    select set_config('request.jwt.claims', '${actorClaims(userId)}', false);
    select public.command_pachanga_league_scheduling_v1(
      md5('${operationSeed}')::uuid,
      '${aggregateId}'::uuid,
      ${expectedRevision},
      '${action}',
      '${encodedPayload}'::jsonb,
      '${metadata}'::jsonb
    )::text;
  `;
}

function extraEntriesSql(teamCount) {
  if (teamCount <= 6) return "";
  return `
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    select md5('r4b-owner-' || value)::uuid,
      'r4b-owner-' || value || '@example.test', clock_timestamp(),
      jsonb_build_object('full_name', 'Team ' || value || ' owner')
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    select md5('r4b-team-' || value)::uuid, md5('r4b-owner-' || value)::uuid,
      'R4B Team ' || value, 'R4P' || lpad(value::text, 5, '0'),
      '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb, 1
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    select md5('r4b-team-' || value)::uuid, md5('r4b-owner-' || value)::uuid,
      'owner', 'Team ' || value || ' owner'
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source, status,
      rule_revision_id, accepted_by, accepted_at, reason_code, created_by
    )
    select md5('r4b-entry-' || value)::uuid,
      'e4040000-0000-4000-8000-000000000001'::uuid,
      'e4070000-0000-4000-8000-000000000001'::uuid,
      'e40b0000-0000-4000-8000-000000000001'::uuid,
      md5('r4b-team-' || value)::uuid, 'ORGANIZER_INVITATION', 'accepted',
      'e4060000-0000-4000-8000-000000000001'::uuid,
      '${managerId}'::uuid, clock_timestamp(), 'r4b.performance.accepted', '${managerId}'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_stage_memberships(
      id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
      status, reason, assigned_by
    )
    select md5('r4b-membership-' || value)::uuid, md5('r4b-entry-' || value)::uuid,
      'e4080000-0000-4000-8000-000000000001'::uuid,
      'e4090000-0000-4000-8000-000000000001'::uuid,
      'e40a0000-0000-4000-8000-000000000001'::uuid,
      'e4060000-0000-4000-8000-000000000001'::uuid,
      'active', 'R4B performance membership', '${managerId}'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_rosters(
      id, entry_id, category_id, rule_revision_id, status, revision, created_by
    )
    select md5('r4b-roster-' || value)::uuid, md5('r4b-entry-' || value)::uuid,
      'e40b0000-0000-4000-8000-000000000001'::uuid,
      'e4060000-0000-4000-8000-000000000001'::uuid,
      'locked', 1, '${managerId}'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_roster_revisions(
      id, roster_id, revision_number, roster_status, rule_revision_id, member_count,
      eligibility_summary, member_set_checksum, reason, created_by
    )
    select md5('r4b-roster-revision-' || value)::uuid, md5('r4b-roster-' || value)::uuid,
      1, 'locked', 'e4060000-0000-4000-8000-000000000001'::uuid, 0,
      '{"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}'::jsonb,
      encode(extensions.digest(convert_to('r4b-roster-' || value, 'UTF8'), 'sha256'), 'hex'),
      'R4B performance locked roster', '${managerId}'::uuid
    from generate_series(7, ${teamCount}) value;

    update public.pachanga_competition_rosters rosters set current_revision_id = revisions.id
    from public.pachanga_competition_roster_revisions revisions
    where revisions.roster_id = rosters.id and rosters.id in (
      select md5('r4b-roster-' || value)::uuid from generate_series(7, ${teamCount}) value
    );
  `;
}

function seedSlotsSql(teamCount, legs) {
  const fixtures = teamCount * (teamCount - 1) / 2 * legs;
  return `
    insert into public.pachanga_competition_schedule_slots(
      competition_id, edition_id, stage_id, division_id, competition_group_id,
      starts_at, ends_at, timezone, venue_label, resource_key, status, created_by
    )
    select 'e4040000-0000-4000-8000-000000000001'::uuid,
      'e4070000-0000-4000-8000-000000000001'::uuid,
      'e4080000-0000-4000-8000-000000000001'::uuid,
      'e4090000-0000-4000-8000-000000000001'::uuid,
      'e40a0000-0000-4000-8000-000000000001'::uuid,
      '2027-01-16T08:00:00Z'::timestamptz + value * interval '3 hours',
      '2027-01-16T09:30:00Z'::timestamptz + value * interval '3 hours',
      'Europe/Madrid', 'Performance venue', 'performance-resource-' || value,
      'available', '${managerId}'::uuid
    from generate_series(1, ${fixtures + 64}) value;
  `;
}

const scenarioResults = [];
run(pgDumpBin, [
  "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
  "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
  "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
  "--file", infrastructureDump, adminUrl,
], "export performance infrastructure");

try {
  for (const { teamCount, legs } of [
    { teamCount: 6, legs: 1 },
    { teamCount: 20, legs: 2 },
    { teamCount: 32, legs: 2 },
  ]) {
    const databaseName = `pachangas_r4b_perf_${teamCount}_${suffix}`;
    try {
      admin(`create database ${databaseName} template template0`, `create ${databaseName}`);
      run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(databaseName), "-f", infrastructureDump], `restore ${databaseName}`);
      databaseQuery(databaseName, "create publication supabase_realtime", `publication ${databaseName}`);
      apply(databaseName, [
        resolve(root, manifest.baselinePath),
        ...migrations.map((name) => resolve(root, "supabase/migrations", name)),
      ], `bootstrap ${databaseName}`);
      const setup = legs === 2 ? baseSetup.replace('"legs":1', '"legs":2') : baseSetup;
      databaseInput(databaseName, `${setup}\n${extraEntriesSql(teamCount)}`, `seed ${teamCount} teams`);
      databaseQuery(databaseName, `
        update private.pachanga_competition_foundation_settings set
          foundation_enabled=true,
          league_participation_foundation_enabled=true,
          league_registration_enabled=true,
          league_rosters_enabled=true,
          league_scheduling_foundation_enabled=true,
          league_schedule_generation_enabled=true,
          league_schedule_editing_enabled=true,
          league_schedule_publication_enabled=true,
          league_public_calendar_enabled=true,
          league_canonical_fixture_creation_enabled=true
        where singleton;
        ${seedSlotsSql(teamCount, legs)}
      `, `enable and seed ${teamCount}`);

      const create = timedJson(databaseName, commandSql({
        action: "schedule_plan.create",
        aggregateId: "e4080000-0000-4000-8000-000000000001",
        expectedRevision: 1,
        operationSeed: `r4b-performance-create-${teamCount}`,
        payload: {
          categoryId: "e40b0000-0000-4000-8000-000000000001",
          divisionId: "e4090000-0000-4000-8000-000000000001",
          groupId: "e40a0000-0000-4000-8000-000000000001",
          legs,
          reason: `R4B performance ${teamCount}`,
          ruleRevisionId: "e4060000-0000-4000-8000-000000000001",
        },
      }), `create plan ${teamCount}`);
      const planId = create.value.snapshot.plan.id;
      assert.equal(Number(create.value.snapshot.plan.entryCount), teamCount);

      const generate = timedJson(databaseName, commandSql({
        action: "schedule.generate",
        aggregateId: planId,
        expectedRevision: 1,
        operationSeed: `r4b-performance-generate-${teamCount}`,
        payload: { seed: `r4b-performance-${teamCount}` },
      }), `generate ${teamCount}`);
      const expectedFixtures = teamCount * (teamCount - 1) / 2 * legs;
      const expectedRounds = (teamCount % 2 === 0 ? teamCount - 1 : teamCount) * legs;
      assert.equal(Number(generate.value.snapshot.counts.items), expectedFixtures);
      assert.equal(Number(generate.value.snapshot.counts.rounds), expectedRounds);
      assert.equal(Number(generate.value.snapshot.counts.unassigned), 0);

      const workbench = timedJson(databaseName, `
        select set_config('request.jwt.claims', '${actorClaims(managerId)}', false);
        select public.get_pachanga_league_schedule_workbench_v1('${planId}'::uuid, 0, 200)::text;
      `, `workbench ${teamCount}`);
      assert.equal(workbench.value.items.length, Math.min(expectedFixtures, 200));

      const result = {
        createMs: create.durationMs,
        fixtures: expectedFixtures,
        generateMs: generate.durationMs,
        legs,
        rounds: expectedRounds,
        teams: teamCount,
        workbenchMs: workbench.durationMs,
      };

      if (teamCount === 6) {
        const validate = timedJson(databaseName, commandSql({
          action: "schedule.validate",
          aggregateId: planId,
          expectedRevision: 2,
          operationSeed: "r4b-performance-validate-6",
          payload: { reason: "R4B performance validation" },
        }), "validate 6");
        assert.equal(validate.value.snapshot.validation.status, "VALID");
        const publish = timedJson(databaseName, commandSql({
          action: "schedule.publish",
          aggregateId: planId,
          expectedRevision: 3,
          operationSeed: "r4b-performance-publish-6",
          payload: { reason: "R4B performance publication" },
        }), "publish 6");
        assert.equal(Number(publish.value.snapshot.publication.canonicalMatchCount), 15);
        const roundId = databaseQuery(databaseName, `
          select id from public.pachanga_competition_rounds
          where schedule_revision_id=(select current_revision_id from public.pachanga_competition_schedule_plans where id='${planId}'::uuid)
          order by round_number, id limit 1
        `, "published round").split("\n").at(-1);
        const teamCalendar = timedJson(databaseName, `
          select set_config('request.jwt.claims', '${actorClaims("ad46b41e-6dd3-c3f0-9b93-b024a0f822c4")}', false);
          select public.get_pachanga_my_league_schedule_v1(md5('r4b-entry-1')::uuid)::text;
        `, "team calendar");
        const publicCalendar = timedJson(databaseName, `
          select set_config('request.jwt.claims', '${actorClaims("00000000-0000-0000-0000-000000000000", "anon")}', false);
          select public.get_pachanga_public_league_calendar_v1('e4040000-0000-4000-8000-000000000001'::uuid,1,20)::text;
        `, "public calendar");
        const roundDetail = timedJson(databaseName, `
          select set_config('request.jwt.claims', '${actorClaims("00000000-0000-0000-0000-000000000000", "anon")}', false);
          select public.get_pachanga_league_round_detail_v1('${roundId}'::uuid)::text;
        `, "round detail");
        assert.equal(teamCalendar.value.fixtures.length, 5);
        assert.equal(publicCalendar.value.rounds.length, 5);
        assert.equal(roundDetail.value.fixtures.length, 3);
        Object.assign(result, {
          publicCalendarMs: publicCalendar.durationMs,
          publishMs: publish.durationMs,
          roundDetailMs: roundDetail.durationMs,
          teamCalendarMs: teamCalendar.durationMs,
          validateMs: validate.durationMs,
        });
      }
      scenarioResults.push(result);
    } finally {
      dropDatabase(databaseName);
    }
  }
  const twentyTeams = scenarioResults.find((scenario) => scenario.teams === 20);
  assert.ok(twentyTeams.generateMs < 180_000, "20-team generation exceeded statement timeout objective");
  process.stdout.write(`${JSON.stringify({
    database: "temporary",
    measurements: scenarioResults,
    statementTimeoutMs: 180_000,
  })}\n`);
} finally {
  rmSync(infrastructureDump, { force: true });
}
