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
const freshName = `pachangas_r4b_fresh_${suffix}`;
const upgradeName = `pachangas_r4b_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4b-bootstrap-${suffix}.sql`);
const r4bMigrations = [
  "20260823224156_league_scheduling_schema_v1.sql",
  "20260823224218_league_scheduling_commands_v1.sql",
  "20260823224235_league_scheduling_access_v1.sql",
  "20260823224236_league_scheduling_hardening_v1.sql",
];
const originalR4bLedger = 119;

if (!adminUrl) throw new Error("LEAGUE_SCHEDULING_DATABASE_URL is required");
const parsedAdmin = new URL(adminUrl);
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsedAdmin.hostname)) {
  throw new Error("R4B_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
const incremental = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const r4bStart = incremental.indexOf(r4bMigrations[0]);
assert.notEqual(r4bStart, -1, "R4B migrations are missing from the current ledger");
assert.deepEqual(incremental.slice(r4bStart, r4bStart + r4bMigrations.length), r4bMigrations);
const preR4bIncremental = incremental.slice(0, r4bStart);
const postR4bIncremental = incremental.slice(r4bStart + r4bMigrations.length);
assert.equal(
  migrationNames.length - postR4bIncremental.length - r4bMigrations.length,
  originalR4bLedger,
  "The immutable pre-R4B ledger checkpoint changed",
);

function targetUrl(databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(databaseName, sql) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], `query ${databaseName}`);
}

function apply(databaseName, files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(databaseName)];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function provision(databaseName) {
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(databaseName), "-f", infrastructureDump], `restore infrastructure ${databaseName}`);
  query(databaseName, "create publication supabase_realtime;");
}

function contract(databaseName) {
  return JSON.parse(query(databaseName, `
    select jsonb_build_object(
      'tables', (select jsonb_agg(relname order by relname)
        from pg_class relations join pg_namespace namespaces on namespaces.oid=relations.relnamespace
        where namespaces.nspname='public' and relations.relkind='r'
          and relations.relname in (
            'pachanga_competition_schedule_plans','pachanga_competition_schedule_revisions',
            'pachanga_competition_schedule_slots','pachanga_competition_rounds',
            'pachanga_competition_round_byes','pachanga_competition_schedule_items',
            'pachanga_competition_schedule_validations'
          )),
      'command', to_regprocedure('public.command_pachanga_league_scheduling_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'platformCommand', to_regprocedure('public.command_pachanga_league_scheduling_platform_v1(uuid,uuid,bigint,jsonb,jsonb)') is not null,
      'workbench', to_regprocedure('public.get_pachanga_league_schedule_workbench_v1(uuid,integer,integer)') is not null,
      'publicCalendar', to_regprocedure('public.get_pachanga_public_league_calendar_v1(uuid,integer,integer)') is not null,
      'interactiveMaximumTeams', private.pachanga_league_schedule_interactive_maximum_teams_v1(),
      'engineMaximumTeams', 32,
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings
        where settings.league_scheduling_foundation_enabled
          or settings.league_schedule_generation_enabled
          or settings.league_schedule_editing_enabled
          or settings.league_schedule_publication_enabled
          or settings.league_public_calendar_enabled
          or settings.league_canonical_fixture_creation_enabled
      ),
      'engine', 'league-round-robin-v1',
      'canonicalMatches', (select count(*) from public.pachanga_canonical_matches),
      'matchContexts', (select count(*) from public.pachanga_competition_match_contexts)
    )::text;
  `));
}

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function dropDatabase(name) {
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity
    join pg_roles roles on roles.rolname = activity.usename
    where activity.datname=${literal(name)}
      and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${literal(name)}`,
      `inspect ${name}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4B_BOOTSTRAP_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${freshName} template template0`, "create fresh R4B database");
  admin(`create database ${upgradeName} template template0`, "create upgrade R4B database");
  provision(freshName);
  provision(upgradeName);

  const baseline = resolve(root, manifest.baselinePath);
  apply(freshName, [baseline, ...incremental.map((name) => resolve(root, "supabase/migrations", name))], "fresh R4B bootstrap");
  apply(upgradeName, [baseline, ...preR4bIncremental.map((name) => resolve(root, "supabase/migrations", name))], "prepare exact 119 ledger");
  assert.equal(query(upgradeName, "select to_regclass('public.pachanga_competition_schedule_plans') is null"), "t");
  apply(upgradeName, r4bMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 119 to R4B");
  apply(upgradeName, postR4bIncremental.map((name) => resolve(root, "supabase/migrations", name)), "upgrade R4B to current ledger");

  const freshContract = contract(freshName);
  const upgradeContract = contract(upgradeName);
  assert.deepEqual(upgradeContract, freshContract, "Fresh and upgraded R4B schemas diverged");
  assert.equal(freshContract.tables.length, 7);
  assert.equal(freshContract.command, true);
  assert.equal(freshContract.platformCommand, true);
  assert.equal(freshContract.workbench, true);
  assert.equal(freshContract.publicCalendar, true);
  assert.equal(freshContract.interactiveMaximumTeams, 20);
  assert.equal(freshContract.engineMaximumTeams, 32);
  assert.equal(freshContract.flagsOff, true);
  assert.equal(freshContract.engine, "league-round-robin-v1");
  assert.equal(freshContract.canonicalMatches, 0);
  assert.equal(freshContract.matchContexts, 0);

  process.stdout.write(`${JSON.stringify({
    freshLedger: migrationNames.length,
    upgradeFromLedger: originalR4bLedger,
    r4bMigrations: r4bMigrations.length,
    postR4bMigrations: postR4bIncremental.length,
    schemasEqual: true,
    flagsOff: true,
    canonicalMatches: 0,
  })}\n`);
} finally {
  dropDatabase(freshName);
  dropDatabase(upgradeName);
  rmSync(infrastructureDump, { force: true });
}
