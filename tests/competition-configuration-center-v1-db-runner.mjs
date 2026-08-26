import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.COMPETITION_CONFIGURATION_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_configuration_v1_${suffix}`;
const freshDatabaseName = `pachangas_configuration_fresh_v1_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-configuration-v1-${suffix}.sql`);
const waveMigrations = [
  "20260826123000_competition_configuration_center_schema_v1.sql",
  "20260826123100_competition_configuration_rules_v1.sql",
  "20260826123200_league_wizard_v2_commands.sql",
  "20260826123300_competition_configuration_commands_v1.sql",
  "20260826123400_competition_configuration_engine_policy_v1.sql",
  "20260826123500_competition_configuration_control_center_v1.sql",
];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("COMPETITION_CONFIGURATION_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 158);
assert.deepEqual(migrationNames.slice(-waveMigrations.length), waveMigrations);
const preWaveMigrations = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !waveMigrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !waveMigrations.includes(name)).length, 152);

function databaseUrl(name = databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${name}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
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

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(), "-c", sql], label);
}

function applyTo(name, files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", databaseUrl(name)];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function apply(files, label) {
  applyTo(databaseName, files, label);
}

function normalizedSchema(name) {
  return run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--schema=simulation", databaseUrl(name),
  ], `export ${name} product schema`)
    .split("\n")
    .filter((line) => !/^--|^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
}

function dropDatabase(name) {
  if (admin(`select count(*) from pg_database where datname=${quote(name)}`, `inspect ${name}`) === "0") return;
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(name)}`,
      `wait for ${name}`,
    ));
    if (connections === 0) {
      admin(`drop database if exists ${name}`, `drop ${name}`);
      return;
    }
    spawnSync("sleep", ["0.1"]);
  }
  throw new Error(`COMPETITION_CONFIGURATION_DB_CLEANUP_CONNECTIONS_REMAIN:${name}`);
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create configuration test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  query("create publication supabase_realtime;", "create configuration Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 152-migration pre-Wave-5A base");
  assert.equal(query(
    "select to_regclass('private.pachanga_competition_configuration_drafts') is null",
    "verify pre-Wave-5A base",
  ), "t");

  apply(waveMigrations.map((name) => resolve(root, "supabase/migrations", name)), "install Wave 5A migrations");

  admin(`create database ${freshDatabaseName} template template0`, "create fresh schema comparison database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(freshDatabaseName), "-f", infrastructureDump], "restore fresh Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(freshDatabaseName), "-c", "create publication supabase_realtime;"], "create fresh Realtime publication");
  applyTo(freshDatabaseName, [
    resolve(root, manifest.baselinePath),
    ...migrationNames
      .filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "install fresh 158-migration schema");
  const upgradedSchema = normalizedSchema(databaseName);
  const freshSchema = normalizedSchema(freshDatabaseName);
  const schemaHash = createHash("sha256").update(upgradedSchema).digest("hex");
  assert.equal(freshSchema, upgradedSchema, "fresh and 152-to-158 schemas must be identical");
  const inactive = JSON.parse(query(`
    select jsonb_build_object(
      'configurationCenterOff', not settings.competition_configuration_center_enabled,
      'wizardV2Off', not settings.league_wizard_v2_enabled,
      'drafts', (select count(*) from private.pachanga_competition_configuration_drafts),
      'receipts', (select count(*) from private.pachanga_competition_configuration_receipts),
      'events', (select count(*) from private.pachanga_competition_configuration_events),
      'invalidations', (select count(*) from public.pachanga_competition_configuration_invalidations),
      'directAuthenticatedDraftInsert', has_table_privilege(
        'authenticated', 'private.pachanga_competition_configuration_drafts', 'INSERT'
      ),
      'privateHealthClientExecute', has_function_privilege(
        'authenticated', 'private.pachanga_competition_configuration_health_v1(jsonb,smallint[])', 'EXECUTE'
      )
    )::text
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton;
  `, "verify inert Wave 5A install"));
  assert.deepEqual(inactive, {
    configurationCenterOff: true,
    directAuthenticatedDraftInsert: false,
    drafts: 0,
    events: 0,
    invalidations: 0,
    privateHealthClientExecute: false,
    receipts: 0,
    wizardV2Off: true,
  });

  const output = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(),
    "-c", "begin",
    "-f", resolve(root, "tests/competition-configuration-center-v1-fixture.sql"),
    "-f", resolve(root, "tests/competition-configuration-center-v1-db.sql"),
    "-c", "rollback",
  ], "Wave 5A SQL, RLS, idempotency and engine regression suite");
  assert.match(output, /COMPETITION_CONFIGURATION_CENTER_V1_DB_OK/);

  process.stdout.write(`${JSON.stringify({
    baseLedger: 152,
    database: "temporary",
    flagsDefaultOff: true,
    productRowsDefault: 0,
    sqlRlsIdempotencyEngines: "PASS",
    schemaEquivalence: "PASS",
    schemaHash,
    waveMigrations: waveMigrations.length,
  })}\n`);
} finally {
  let cleanupError;
  for (const name of [databaseName, freshDatabaseName]) {
    try {
      dropDatabase(name);
    } catch (error) {
      cleanupError ??= error;
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    }
  }
  rmSync(infrastructureDump, { force: true });
  if (cleanupError) throw cleanupError;
}
