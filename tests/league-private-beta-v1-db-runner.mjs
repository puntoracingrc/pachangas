import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_PRIVATE_BETA_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const includeScale = process.env.LEAGUE_PRIVATE_BETA_INCLUDE_SCALE === "1";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_league_beta_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-league-beta-db-${suffix}.sql`);
const betaMigrations = [
  "20260825074304_league_private_beta_schema_v1.sql",
  "20260825074353_league_private_beta_commands_v1.sql",
  "20260825074358_league_private_beta_access_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_PRIVATE_BETA_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("LEAGUE_PRIVATE_BETA_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 139);
assert.deepEqual(migrationNames.slice(-betaMigrations.length), betaMigrations);
const preBetaMigrations = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !betaMigrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !betaMigrations.includes(name)).length, 136);

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
  admin(`alter database ${databaseName} with allow_connections false`, "close beta DB test database");
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate beta DB test database");
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, "inspect beta DB test database")) === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error("LEAGUE_PRIVATE_BETA_DB_CLEANUP_CONNECTIONS_REMAIN");
  }
  admin(`drop database if exists ${databaseName}`, "drop beta DB test database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create beta DB test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  query("create publication supabase_realtime;", "create Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preBetaMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 136-migration beta base");
  assert.equal(query(
    "select to_regclass('private.pachanga_league_private_beta_wizards') is null",
    "verify pre-beta base",
  ), "t");

  apply(betaMigrations.map((name) => resolve(root, "supabase/migrations", name)), "install beta migrations");
  const inactive = JSON.parse(query(`
    select jsonb_build_object(
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.league_private_beta_enabled
          or settings.league_private_beta_creation_enabled
          or settings.league_private_beta_public_discovery_enabled
      ),
      'productRows', (select count(*) from public.pachanga_competitions where product_key='LEAGUE_PRIVATE_BETA_V1'),
      'grants', (select count(*) from public.pachanga_competition_entitlement_grants where program_key='LEAGUE_PRIVATE_BETA_V1'),
      'wizards', (select count(*) from private.pachanga_league_private_beta_wizards)
    )::text;
  `, "verify inactive beta install"));
  assert.deepEqual(inactive, { flagsOff: true, grants: 0, productRows: 0, wizards: 0 });

  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/league-private-beta-v1-db.sql"),
  ], "beta SQL, RLS, idempotency and adversarial suite");
  if (includeScale) {
    run(psqlBin, [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
      "-f", resolve(root, "tests/league-private-beta-v1-scale.sql"),
    ], "beta bounded scale suite");
  }

  process.stdout.write(`${JSON.stringify({
    baseLedger: 136,
    betaMigrations: betaMigrations.length,
    database: "temporary",
    flagsDefaultOff: true,
    productRowsDefault: 0,
    scale: includeScale ? "PASS" : "NOT_RUN",
    sqlRlsIdempotencyAdversarial: "PASS",
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
