import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { leagueOperationalFixtureSql } from "./league-operational-exceptions-v1-fixture.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4d_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4d-db-infrastructure-${suffix}.sql`);
const r4dMigrations = [
  "20260824230726_league_operational_exceptions_schema_v1.sql",
  "20260824230732_league_operational_exceptions_commands_v1.sql",
  "20260824230733_league_operational_exceptions_access_v1.sql",
  "20260824230734_league_operational_exceptions_hardening_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4D_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 135);
assert.deepEqual(migrationNames.slice(-4), r4dMigrations);
const preR4dIncremental = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !r4dMigrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !r4dMigrations.includes(name)).length, 131);

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
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label) {
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

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close R4D DB test database");
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname=activity.usename
      where activity.datname=${quote(databaseName)}
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`,
    "terminate R4D DB test database",
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      "inspect R4D DB test database",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4D_DB_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop R4D DB test database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R4D DB test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preR4dIncremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 131-migration R4D base");
  assert.equal(query(
    "select to_regclass('public.pachanga_competition_fixture_changes') is null",
    "verify pre-R4D base",
  ), "t");

  apply(
    r4dMigrations.map((name) => resolve(root, "supabase/migrations", name)),
    "install R4D migrations",
  );
  const inactive = JSON.parse(query(`
    select jsonb_build_object(
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.league_operational_exceptions_foundation_enabled
          or settings.league_postponements_enabled
          or settings.league_rescheduling_enabled
          or settings.league_venue_changes_enabled
          or settings.league_late_arrival_enabled
          or settings.league_no_show_enabled
          or settings.league_match_suspensions_enabled
          or settings.league_administrative_decisions_enabled
          or settings.league_public_exception_status_enabled
      ),
      'rows', (
        (select count(*) from public.pachanga_competition_fixture_changes)
        + (select count(*) from public.pachanga_competition_postponement_requests)
        + (select count(*) from public.pachanga_competition_late_arrival_incidents)
        + (select count(*) from public.pachanga_competition_no_show_incidents)
        + (select count(*) from public.pachanga_competition_match_suspensions)
        + (select count(*) from public.pachanga_competition_administrative_decisions)
      )
    )::text;
  `, "verify inactive R4D install"));
  assert.deepEqual(inactive, { flagsOff: true, rows: 0 });

  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl()],
    "load R4D isolated fixture",
    `begin;\n${leagueOperationalFixtureSql({ enableFlags: true })}\ncommit;\n`,
  );
  run(
    psqlBin,
    [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
      "-f", resolve(root, "tests/league-operational-exceptions-v1-db.sql"),
    ],
    "R4D SQL, RLS, idempotency and adversarial suite",
  );

  process.stdout.write(`${JSON.stringify({
    baseLedger: 131,
    database: "temporary",
    r4dMigrations: 4,
    flagsDefaultOff: true,
    productRowsDefault: 0,
    sqlRlsIdempotencyAdversarial: "PASS",
    canonicalMatchPolicy: "SAME_CANONICAL_MATCH",
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
