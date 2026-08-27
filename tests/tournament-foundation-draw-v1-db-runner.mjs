import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TOURNAMENT_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r6a_upgrade_${suffix}`;
const freshDatabaseName = `pachangas_r6a_fresh_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6a-db-${suffix}.sql`);
const waveMigrations = [
  "20260826195034_tournament_foundation_participant_freeze_v1.sql",
  "20260826195036_tournament_draw_schema_revisions_v1.sql",
  "20260826195037_tournament_draw_commands_engine_v1.sql",
  "20260826195039_tournament_draw_access_read_models_v1.sql",
  "20260826195040_tournament_draw_hardening_indexes_flags_v1.sql",
];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6A_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 163);
assert.deepEqual(migrationNames.slice(-waveMigrations.length), waveMigrations);
assert.equal(migrationNames.filter((name) => !waveMigrations.includes(name)).length, 158);
const preWaveMigrations = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !waveMigrations.includes(name)
));

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

function query(sql, label, name = databaseName) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(name), "-c", sql], label);
}

function applyTo(name, files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", databaseUrl(name)];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
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

function createDatabase(name) {
  admin(`create database ${name} template template0`, `create ${name}`);
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(name), "-f", infrastructureDump], `restore ${name} infrastructure`);
  query("create publication supabase_realtime;", `create ${name} Realtime publication`, name);
}

function dropDatabase(name) {
  if (admin(`select count(*) from pg_database where datname=${quote(name)}`, `inspect ${name}`) === "0") return;
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");

  createDatabase(databaseName);
  applyTo(databaseName, [
    resolve(root, manifest.baselinePath),
    ...preWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 158-migration R6A base");
  assert.equal(query(
    "select to_regclass('public.pachanga_competition_draw_plans') is null",
    "verify R6A table absent before upgrade",
  ), "t");

  applyTo(databaseName, waveMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 158 to 163");

  createDatabase(freshDatabaseName);
  applyTo(freshDatabaseName, [
    resolve(root, manifest.baselinePath),
    ...migrationNames
      .filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "install fresh 163-migration schema");

  const upgradedSchema = normalizedSchema(databaseName);
  const freshSchema = normalizedSchema(freshDatabaseName);
  assert.equal(freshSchema, upgradedSchema, "fresh and 158-to-163 schemas must be identical");
  const schemaHash = createHash("sha256").update(upgradedSchema).digest("hex");

  const inactive = JSON.parse(query(`
    select jsonb_build_object(
      'foundationOff', not settings.tournament_foundation_enabled,
      'privateBetaOff', not settings.tournament_private_beta_enabled,
      'creationOff', not settings.tournament_creation_enabled,
      'drawOff', not settings.tournament_draw_enabled,
      'manualOff', not settings.tournament_draw_manual_enabled,
      'hybridOff', not settings.tournament_draw_hybrid_enabled,
      'publishOff', not settings.tournament_draw_publish_enabled,
      'publicDiscoveryOff', not settings.tournament_public_discovery_enabled,
      'matchGenerationOff', not settings.tournament_match_generation_enabled,
      'bracketProgressionOff', not settings.tournament_bracket_progression_enabled,
      'plans', (select count(*) from public.pachanga_competition_draw_plans),
      'revisions', (select count(*) from public.pachanga_competition_draw_revisions),
      'directAuthenticatedInsert', has_table_privilege(
        'authenticated', 'public.pachanga_competition_draw_plans', 'INSERT'
      ),
      'privateSolverClientExecute', has_function_privilege(
        'authenticated', 'private.pachanga_tournament_solve_v1(uuid,text)', 'EXECUTE'
      ),
      'generalAuthorizationClientExecute', has_function_privilege(
        'authenticated', 'private.pachanga_tournament_can_v1(uuid,uuid,text)', 'EXECUTE'
      ),
      'realtimeAuthorizationClientExecute', has_function_privilege(
        'authenticated', 'private.pachanga_tournament_realtime_can_read_v1(uuid)', 'EXECUTE'
      )
    )::text
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton;
  `, "verify inert R6A install"));
  assert.deepEqual(inactive, {
    bracketProgressionOff: true,
    creationOff: true,
    directAuthenticatedInsert: false,
    drawOff: true,
    foundationOff: true,
    generalAuthorizationClientExecute: false,
    hybridOff: true,
    manualOff: true,
    matchGenerationOff: true,
    plans: 0,
    privateBetaOff: true,
    privateSolverClientExecute: false,
    publicDiscoveryOff: true,
    publishOff: true,
    realtimeAuthorizationClientExecute: true,
    revisions: 0,
  });

  const dbOutput = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(),
    "-f", resolve(root, "tests/tournament-foundation-draw-v1-db.sql"),
  ], "R6A SQL, RLS and idempotency suite");
  assert.match(dbOutput, /R6A_DB_REPORT\|/);

  const engineOutput = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(),
    "-f", resolve(root, "tests/tournament-foundation-draw-v1-engine.sql"),
  ], "R6A deterministic engine matrix");
  const engineReportLine = engineOutput.split("\n").find((line) => line.startsWith("R6A_ENGINE_REPORT|"));
  assert.ok(engineReportLine, "R6A engine report missing");
  const engineReport = JSON.parse(engineReportLine.slice("R6A_ENGINE_REPORT|".length));
  assert.equal(engineReport.cases, 9);
  assert.equal(engineReport.tournamentMatches, 0);

  process.stdout.write(`${JSON.stringify({
    baseLedger: 158,
    database: "temporary",
    engineCases: engineReport.cases,
    finalLedger: 163,
    flagsDefaultOff: true,
    schemaEquivalence: "PASS",
    schemaHash,
    sqlRlsIdempotency: "PASS",
    tournamentMatches: engineReport.tournamentMatches,
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
