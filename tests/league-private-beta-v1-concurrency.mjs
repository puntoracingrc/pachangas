import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_PRIVATE_BETA_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_league_beta_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-league-beta-concurrency-${suffix}.sql`);
const caseDatabases = new Set();

if (!adminUrl) throw new Error("LEAGUE_PRIVATE_BETA_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("LEAGUE_PRIVATE_BETA_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
assert.equal(migrations.length + 36, 139);

const ownerId = "bc010000-0000-4000-8000-000000000001";
const platformId = "bc010000-0000-4000-8000-000000000002";
const groupId = "bc020000-0000-4000-8000-000000000001";

function targetUrl(databaseName) {
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

function query(databaseName, sql, label = "query beta concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], label);
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function authenticatedSql(actorId, statement) {
  return `begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    ${statement};
    commit;`;
}

function userCommandSql(operationId, aggregateId, revision, action, payload = {}) {
  return authenticatedSql(ownerId, `select public.command_pachanga_league_private_beta_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${revision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"4.0.0+beta-concurrency","surface":"beta_concurrency"}'::jsonb
  )`);
}

function platformCommandSql(operationId, revision, action, payload = {}) {
  return authenticatedSql(platformId, `select public.command_pachanga_league_private_beta_platform_v1(
    ${quote(operationId)}::uuid, ${quote(groupId)}::uuid, ${revision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"4.0.0+beta-concurrency","surface":"beta_concurrency"}'::jsonb
  )`);
}

function concurrent(databaseName, sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName)], {
      cwd: root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

function assertOneWinner(results, label) {
  assert.equal(results.filter((result) => result.code === 0).length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  const loser = results.find((result) => result.code !== 0);
  assert.ok(loser);
  assert.match(loser.stderr, /STALE_REVISION|duplicate key|ACTIVE_EDITION_LIMIT|IDEMPOTENCY/i);
}

function cloneCase(label) {
  const databaseName = `pachangas_league_beta_${label}_${suffix}`;
  admin(`create database ${databaseName} template ${templateDatabase}`, `clone ${label}`);
  caseDatabases.add(databaseName);
  return databaseName;
}

function dropDatabase(databaseName) {
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${databaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, `inspect ${databaseName}`)) === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`LEAGUE_PRIVATE_BETA_CONCURRENCY_CONNECTIONS_REMAIN:${databaseName}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function parseResponse(output) {
  const line = output.split("\n").filter((item) => item.startsWith("{")).at(-1);
  assert.ok(line, `No canonical response in ${output}`);
  return JSON.parse(line);
}

const fixtureSql = `
  insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
    ('${ownerId}', 'beta-concurrency-owner@example.test', clock_timestamp(), '{"full_name":"Beta Owner"}'),
    ('${platformId}', 'beta-concurrency-platform@example.test', clock_timestamp(), '{"full_name":"Beta Platform"}');
  insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
    ('${groupId}', '${ownerId}', 'Beta Concurrency Team', 'BCON01', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');
  insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
    ('${groupId}', '${ownerId}', 'owner', 'Beta Owner');
  insert into private.pachanga_platform_admin_roles(user_id, role, active) values
    ('${platformId}', 'platform_owner', true);
  ${platformCommandSql("bc030000-0000-4000-8000-000000000001", 0, "beta.bundle.grant", {
    organizerKind: "TEAM", maxTeams: 12, expiresAt: "2027-12-31T23:59:59Z", reason: "concurrency fixture",
  })}
  update private.pachanga_competition_foundation_settings set
    foundation_enabled=true, creation_enabled=true, context_binding_enabled=true,
    league_participation_foundation_enabled=true, league_registration_enabled=true,
    league_delegates_enabled=true, league_rosters_enabled=true,
    league_schedule_preferences_enabled=true, league_scheduling_foundation_enabled=true,
    league_schedule_generation_enabled=true, league_schedule_editing_enabled=true,
    league_schedule_publication_enabled=true, league_canonical_fixture_creation_enabled=true,
    league_match_operations_foundation_enabled=true, league_match_squads_enabled=true,
    league_match_attendance_enabled=true, league_sporting_results_enabled=true,
    league_result_confirmation_enabled=true, league_official_results_enabled=true,
    league_standings_enabled=true, league_operational_exceptions_foundation_enabled=true,
    league_postponements_enabled=true, league_rescheduling_enabled=true,
    league_venue_changes_enabled=true, league_late_arrival_enabled=true,
    league_no_show_enabled=true, league_match_suspensions_enabled=true,
    league_administrative_decisions_enabled=true,
    league_public_registration_enabled=false, league_public_calendar_enabled=false,
    league_public_standings_enabled=false, league_public_exception_status_enabled=false,
    league_private_beta_enabled=true, league_private_beta_creation_enabled=true,
    league_private_beta_public_discovery_enabled=false,
    revision=revision+1, server_sequence=nextval('private.pachanga_competition_sequence'),
    updated_by='${platformId}', updated_at=clock_timestamp()
  where singleton;
`;

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create beta concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump], "restore concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create concurrency publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap beta concurrency template");
  query(templateDatabase, fixtureSql, "load beta concurrency fixture");

  const summaries = {};
  let databaseName = cloneCase("same_operation");
  const sharedOperation = randomUUID();
  let results = await Promise.all([
    concurrent(databaseName, userCommandSql(sharedOperation, groupId, 1, "wizard.create", { organizerKind: "TEAM", reason: "same operation" }), "same operation A"),
    concurrent(databaseName, userCommandSql(sharedOperation, groupId, 1, "wizard.create", { organizerKind: "TEAM", reason: "same operation" }), "same operation B"),
  ]);
  assert.equal(results.filter((result) => result.code === 0).length, 2, JSON.stringify(results));
  assert.deepEqual(parseResponse(results[0].stdout), parseResponse(results[1].stdout));
  assert.equal(Number(query(databaseName, "select count(*) from private.pachanga_league_private_beta_wizards")), 1);
  assert.equal(Number(query(databaseName, `select count(*) from private.pachanga_league_private_beta_operation_receipts where operation_id='${sharedOperation}'`)), 1);
  summaries.sameOperation = "2 clients / 1 effect / identical response";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_creates");
  results = await Promise.all([
    concurrent(databaseName, userCommandSql(randomUUID(), groupId, 1, "wizard.create", { organizerKind: "TEAM", reason: "create A" }), "create A"),
    concurrent(databaseName, userCommandSql(randomUUID(), groupId, 1, "wizard.create", { organizerKind: "TEAM", reason: "create B" }), "create B"),
  ]);
  assertOneWinner(results, "two wizard creates");
  assert.equal(Number(query(databaseName, "select count(*) from private.pachanga_league_private_beta_wizards")), 1);
  summaries.twoCreates = "1 winner / 1 explicit conflict";

  const wizardId = query(databaseName, "select id from private.pachanga_league_private_beta_wizards limit 1");
  results = await Promise.all([
    concurrent(databaseName, userCommandSql(randomUUID(), wizardId, 1, "wizard.step.save", { step: 1, data: { name: "Liga A", slug: "liga-a" }, reason: "step A" }), "step A"),
    concurrent(databaseName, userCommandSql(randomUUID(), wizardId, 1, "wizard.step.save", { step: 1, data: { name: "Liga B", slug: "liga-b" }, reason: "step B" }), "step B"),
  ]);
  assertOneWinner(results, "two wizard step writes");
  assert.equal(Number(query(databaseName, `select revision from private.pachanga_league_private_beta_wizards where id='${wizardId}'`)), 2);
  assert.equal(Number(query(databaseName, `select cardinality(completed_steps) from private.pachanga_league_private_beta_wizards where id='${wizardId}'`)), 1);
  summaries.twoStepWrites = "1 winner / 1 stale / revision 2";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_revokes");
  const bundleId = query(databaseName, "select bundle_id from public.pachanga_competition_entitlement_grants where program_key='LEAGUE_PRIVATE_BETA_V1' limit 1");
  results = await Promise.all([
    concurrent(databaseName, platformCommandSql(randomUUID(), 1, "beta.bundle.revoke", { organizerKind: "TEAM", bundleId, reason: "revoke A" }), "revoke A"),
    concurrent(databaseName, platformCommandSql(randomUUID(), 1, "beta.bundle.revoke", { organizerKind: "TEAM", bundleId, reason: "revoke B" }), "revoke B"),
  ]);
  assertOneWinner(results, "two bundle revocations");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_entitlement_grants where bundle_id='" + bundleId + "' and status='active'")), 0);
  summaries.twoRevokes = "1 winner / 1 stale / 0 active capabilities";
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({ concurrency: "PASS", cases: summaries })}\n`);
} finally {
  for (const databaseName of [...caseDatabases]) dropDatabase(databaseName);
  dropDatabase(templateDatabase);
  rmSync(infrastructureDump, { force: true });
}
