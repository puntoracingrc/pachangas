import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
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
const databaseName = `pachangas_r4b_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4b-concurrency-${suffix}.sql`);

if (!adminUrl) throw new Error("LEAGUE_SCHEDULING_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4B_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label = "query R4B concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function commandSql(actorId, operationId, aggregateId, revision, action, payload = {}) {
  return `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_league_scheduling_v1(
      ${quote(operationId)}::uuid,
      ${quote(aggregateId)}::uuid,
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"4.0.0+r4b-concurrency","serviceWorkerVersion":"sw-r4b-concurrency","installedMode":"standalone","surface":"r4b_concurrency"}'::jsonb
    );
    commit;
  `;
}

function command(actorId, aggregateId, revision, action, payload = {}) {
  const output = query(commandSql(actorId, randomUUID(), aggregateId, revision, action, payload), action);
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${action} returned no response`);
  return JSON.parse(line);
}

function concurrent(sql, label) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()], {
      cwd: root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolve({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

async function race(action, aggregateId, revision, payload) {
  const attempts = [
    { actorId: "e4010000-0000-4000-8000-000000000002", label: `${action}:director`, operationId: randomUUID() },
    { actorId: "e4010000-0000-4000-8000-000000000003", label: `${action}:manager`, operationId: randomUUID() },
  ];
  return Promise.all(attempts.map(async (attempt) => ({
    ...await concurrent(
      commandSql(attempt.actorId, attempt.operationId, aggregateId, revision, action, payload),
      attempt.label,
    ),
    operationId: attempt.operationId,
  })));
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one stale loser`);
  assert.match(losers[0].stderr, /STALE_REVISION|PT409/);
}

function extraEntriesSql(teamCount) {
  return `
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    select md5('r4b-concurrency-owner-' || value)::uuid,
      'r4b-concurrency-owner-' || value || '@example.test', clock_timestamp(),
      jsonb_build_object('full_name', 'Concurrency team ' || value || ' owner')
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    select md5('r4b-concurrency-team-' || value)::uuid,
      md5('r4b-concurrency-owner-' || value)::uuid,
      'R4B Concurrency Team ' || value, 'R4C' || lpad(value::text, 5, '0'),
      '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb, 1
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    select md5('r4b-concurrency-team-' || value)::uuid,
      md5('r4b-concurrency-owner-' || value)::uuid,
      'owner', 'Concurrency team ' || value || ' owner'
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source, status,
      rule_revision_id, accepted_by, accepted_at, reason_code, created_by
    )
    select md5('r4b-concurrency-entry-' || value)::uuid,
      'e4040000-0000-4000-8000-000000000001'::uuid,
      'e4070000-0000-4000-8000-000000000001'::uuid,
      'e40b0000-0000-4000-8000-000000000001'::uuid,
      md5('r4b-concurrency-team-' || value)::uuid,
      'ORGANIZER_INVITATION', 'accepted',
      'e4060000-0000-4000-8000-000000000001'::uuid,
      'e4010000-0000-4000-8000-000000000003'::uuid,
      clock_timestamp(), 'r4b.concurrency.accepted',
      'e4010000-0000-4000-8000-000000000003'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_stage_memberships(
      id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
      status, reason, assigned_by
    )
    select md5('r4b-concurrency-membership-' || value)::uuid,
      md5('r4b-concurrency-entry-' || value)::uuid,
      'e4080000-0000-4000-8000-000000000001'::uuid,
      'e4090000-0000-4000-8000-000000000001'::uuid,
      'e40a0000-0000-4000-8000-000000000001'::uuid,
      'e4060000-0000-4000-8000-000000000001'::uuid,
      'active', 'R4B concurrency membership',
      'e4010000-0000-4000-8000-000000000003'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_rosters(
      id, entry_id, category_id, rule_revision_id, status, revision, created_by
    )
    select md5('r4b-concurrency-roster-' || value)::uuid,
      md5('r4b-concurrency-entry-' || value)::uuid,
      'e40b0000-0000-4000-8000-000000000001'::uuid,
      'e4060000-0000-4000-8000-000000000001'::uuid,
      'locked', 1, 'e4010000-0000-4000-8000-000000000003'::uuid
    from generate_series(7, ${teamCount}) value;

    insert into public.pachanga_competition_roster_revisions(
      id, roster_id, revision_number, roster_status, rule_revision_id,
      member_count, eligibility_summary, member_set_checksum, reason, created_by
    )
    select md5('r4b-concurrency-roster-revision-' || value)::uuid,
      md5('r4b-concurrency-roster-' || value)::uuid,
      1, 'locked', 'e4060000-0000-4000-8000-000000000001'::uuid, 0,
      '{"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}'::jsonb,
      encode(extensions.digest(convert_to('r4b-concurrency-roster-' || value, 'UTF8'), 'sha256'), 'hex'),
      'R4B concurrency locked roster',
      'e4010000-0000-4000-8000-000000000003'::uuid
    from generate_series(7, ${teamCount}) value;

    update public.pachanga_competition_rosters rosters
    set current_revision_id = revisions.id
    from public.pachanga_competition_roster_revisions revisions
    where revisions.roster_id = rosters.id
      and rosters.id in (
        select md5('r4b-concurrency-roster-' || value)::uuid
        from generate_series(7, ${teamCount}) value
      );
  `;
}

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close concurrency DB");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid() and not roles.rolsuper`, "terminate concurrency DB");
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, "inspect concurrency DB"));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4B_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop concurrency DB");
}

let publishRace = [];
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create concurrency DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore concurrency infrastructure");
  query("create publication supabase_realtime;", "create concurrency publication");
  apply([resolve(root, manifest.baselinePath), ...migrations.map((name) => resolve(root, "supabase/migrations", name))], "bootstrap concurrency DB");

  const dbSuite = readFileSync(resolve(root, "tests/league-scheduling-v1-db.sql"), "utf8");
  const setup = dbSuite.slice(0, dbSuite.indexOf("do $body$"));
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl()], "load R4B concurrency fixture", setup);
  query(`update private.pachanga_competition_foundation_settings set
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
    where singleton`, "enable disposable R4B flags");
  query(extraEntriesSql(21), "seed 21-team capacity race");

  const planResponse = command(
    "e4010000-0000-4000-8000-000000000003",
    "e4080000-0000-4000-8000-000000000001",
    1,
    "schedule_plan.create",
    {
      categoryId: "e40b0000-0000-4000-8000-000000000001",
      divisionId: "e4090000-0000-4000-8000-000000000001",
      groupId: "e40a0000-0000-4000-8000-000000000001",
      legs: 1,
      reason: "Concurrency plan",
      ruleRevisionId: "e4060000-0000-4000-8000-000000000001",
    },
  );
  const planId = planResponse.snapshot.plan.id;
  assert.equal(Number(planResponse.snapshot.plan.entryCount), 21);

  const capacityRace = await race(
    "schedule.generate",
    planId,
    1,
    { reason: "Over-limit concurrency race", seed: "capacity-race" },
  );
  assert.equal(capacityRace.filter((result) => result.code === 0).length, 0);
  for (const result of capacityRace) {
    assert.match(result.stderr, /SCHEDULE_INTERACTIVE_CAPACITY_EXCEEDED/);
  }
  const capacityOperationIds = capacityRace.map((result) => quote(result.operationId)).join(",");
  assert.deepEqual(JSON.parse(query(`select jsonb_build_object(
    'events', (select count(*) from private.pachanga_competition_events
      where operation_id in (${capacityOperationIds})),
    'receipts', (select count(*) from private.pachanga_competition_operation_receipts
      where operation_id in (${capacityOperationIds})),
    'revisions', (select count(*) from public.pachanga_competition_schedule_revisions
      where schedule_plan_id=${quote(planId)}::uuid),
    'planRevision', (select revision from public.pachanga_competition_schedule_plans
      where id=${quote(planId)}::uuid)
  )::text`)), { events: 0, planRevision: 1, receipts: 0, revisions: 0 });

  query(`update public.pachanga_competition_rosters
    set status='draft', revision=revision+1
    where entry_id in (
      select md5('r4b-concurrency-entry-' || value)::uuid
      from generate_series(7, 21) value
    )`, "return concurrency scope to six eligible teams");
  const reconciledWorkbenchOutput = query(`
    select set_config('request.jwt.claims', '${JSON.stringify({ role: "authenticated", sub: "e4010000-0000-4000-8000-000000000003" }).replaceAll("'", "''")}', false);
    select public.get_pachanga_league_schedule_workbench_v1(${quote(planId)}::uuid,0,200)::text;
  `, "reconciled workbench");
  const reconciledWorkbench = JSON.parse(
    reconciledWorkbenchOutput.split("\n").filter((line) => line.startsWith("{")).at(-1),
  );
  assert.deepEqual(reconciledWorkbench.interactiveGeneration, {
    allowed: true,
    eligibleTeams: 6,
    maximumTeams: 20,
    reasonCode: null,
    source: "CANONICAL_CURRENT_INPUTS",
  });
  query(`
    update public.pachanga_competition_stage_memberships
    set status='archived', revision=revision+1
    where entry_id in (
      select md5('r4b-concurrency-entry-' || value)::uuid
      from generate_series(7, 21) value
    );
    update public.pachanga_competition_entries
    set status='withdrawn', withdrawn_at=clock_timestamp(), revision=revision+1
    where id in (
      select md5('r4b-concurrency-entry-' || value)::uuid
      from generate_series(7, 21) value
    );
  `, "archive synthetic over-limit entries after roster regression");
  command("e4010000-0000-4000-8000-000000000003", planId, 1, "schedule_slot.bulk_create", {
    durationMinutes: 90,
    endDate: "2027-02-21",
    localTime: "20:00",
    reason: "Concurrency slots",
    resourceKey: "pitch-1",
    startDate: "2027-02-01",
    timezone: "Europe/Madrid",
    venueLabel: "Pista QA",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
  });

  const generateRace = await race("schedule.generate", planId, 2, { reason: "Generation race", seed: "concurrency-seed" });
  assertOneWinner(generateRace, "generation race");
  assert.equal(query(`select revision || ':' || status from public.pachanga_competition_schedule_plans where id=${quote(planId)}::uuid`), "3:generated");

  const validationResponse = command(
    "e4010000-0000-4000-8000-000000000003",
    planId,
    3,
    "schedule.validate",
    { reason: "Concurrency validation" },
  );
  assert.equal(
    validationResponse.snapshot.validation.status,
    "VALID",
    JSON.stringify(validationResponse.snapshot.validation),
  );
  publishRace = await race("schedule.publish", planId, 4, { reason: "Publication race" });
  assertOneWinner(publishRace, "publication race");

  const counts = query(`select jsonb_build_object(
    'canonical', (select count(*) from public.pachanga_canonical_match_bindings where source_kind='competition_generated'),
    'contexts', (select count(*) from public.pachanga_competition_match_contexts where competition_id='e4040000-0000-4000-8000-000000000001'),
    'items', (select count(*) from public.pachanga_competition_schedule_items where status='published'),
    'rounds', (select count(*) from public.pachanga_competition_rounds where status='published')
  )::text`);
  assert.deepEqual(JSON.parse(counts), { canonical: 15, contexts: 15, items: 15, rounds: 5 });
  process.stdout.write(`${JSON.stringify({ capacityRace: "2 rejected / 0 writes", generationRace: "1 winner / 1 stale", publishRace: "1 winner / 1 stale", canonicalMatches: 15 })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
