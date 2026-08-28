import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TOURNAMENT_GROUP_STAGE_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const suffix = randomBytes(5).toString("hex");
const freshDatabase = `pachangas_r6c_fresh_${suffix}`;
const upgradeDatabase = `pachangas_r6c_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6c-migrations-${suffix}.sql`);
const featureMigrations = [
  "20260827205347_tournament_knockout_bracket_authority_v1.sql",
  "20260827205351_tournament_knockout_progression_results_v1.sql",
  "20260827205356_tournament_knockout_canonical_match_adapter_v1.sql",
  "20260827205359_tournament_knockout_read_models_hub_v1.sql",
  "20260827205403_tournament_knockout_access_realtime_v1.sql",
  "20260827205409_tournament_knockout_hardening_flags_v1.sql",
];
const compatibilityMigrations = [
  "20260828045324_tournament_knockout_flag_authority_compatibility_v1.sql",
];
const waveMigrations = [...featureMigrations, ...compatibilityMigrations];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6C_MIGRATION_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .filter((name) => name.slice(0, 14) <= "20260828045324")
  .sort();
assert.equal(migrationNames.length, 176);
assert.deepEqual(migrationNames.slice(-waveMigrations.length), waveMigrations);
const preWave = migrationNames.filter((name) => !waveMigrations.includes(name));
assert.equal(preWave.length, 169);

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 512 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function targetUrl(database) {
  const value = new URL(adminUrl);
  value.pathname = `/${database}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run("psql", ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(database, sql, label) {
  return run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(database), "-c", sql,
  ], label);
}

function apply(database, migrations, label, includeBaseline = true) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(database)];
  if (includeBaseline) args.push("-f", resolve(root, manifest.baselinePath));
  for (const migration of migrations) {
    if (!includeBaseline || migration.slice(0, 14) > manifest.absorbsThrough) {
      args.push("-f", resolve(root, "supabase/migrations", migration));
    }
  }
  run("psql", args, label);
}

function provision(database) {
  admin(`create database ${database} template template0`, `create ${database}`);
  run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(database), "-f", infrastructureDump,
  ], `restore ${database} Supabase infrastructure`);
  query(database, "create publication supabase_realtime;", `create ${database} Realtime publication`);
}

function normalizedSchema(database) {
  return run("pg_dump", [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--schema=simulation", targetUrl(database),
  ], `export ${database} product schema`)
    .split("\n")
    .filter((line) => !/^--|^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
}

function drop(database) {
  if (admin(`select count(*) from pg_database where datname=${literal(database)}`, `inspect ${database}`) === "0") return;
  admin(`alter database ${database} with allow_connections false`, `close ${database}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${literal(database)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${database}`);
  admin(`drop database if exists ${database}`, `drop ${database}`);
}

try {
  run("pg_dump", [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export R6C Supabase infrastructure");

  provision(freshDatabase);
  apply(freshDatabase, migrationNames, "fresh bootstrap to exact ledger 176");

  provision(upgradeDatabase);
  apply(upgradeDatabase, preWave, "prepare exact ledger 169");
  assert.equal(query(
    upgradeDatabase,
    "select to_regclass('public.pachanga_tournament_brackets') is null;",
    "verify R6C tables absent at ledger 169",
  ), "t");
  apply(upgradeDatabase, waveMigrations, "upgrade exact R6C wave 169 to 176", false);

  const freshSchema = normalizedSchema(freshDatabase);
  const upgradeSchema = normalizedSchema(upgradeDatabase);
  assert.equal(upgradeSchema, freshSchema, "fresh and 169-to-176 R6C schemas diverged");
  const schemaHash = createHash("sha256").update(freshSchema).digest("hex");

  const defaults = JSON.parse(query(freshDatabase, `
    select jsonb_build_object(
      'foundationOff', not settings.tournament_knockout_foundation_enabled,
      'matchGenerationOff', not settings.tournament_knockout_match_generation_enabled,
      'progressionOff', not settings.tournament_bracket_progression_enabled,
      'extraTimeOff', not settings.tournament_extra_time_enabled,
      'penaltiesOff', not settings.tournament_penalty_shootout_enabled,
      'thirdPlaceOff', not settings.tournament_third_place_enabled,
      'completionOff', not settings.tournament_completion_enabled,
      'twoLegOff', not settings.tournament_two_leg_enabled,
      'doubleEliminationOff', not settings.tournament_double_elimination_enabled,
      'brackets', (select count(*) from public.pachanga_tournament_brackets),
      'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes),
      'advances', (select count(*) from public.pachanga_tournament_bracket_advance_decisions),
      'completions', (select count(*) from public.pachanga_tournament_completion_snapshots),
      'authenticatedDirectInsert', has_table_privilege(
        'authenticated', 'public.pachanga_tournament_brackets', 'INSERT'
      ),
      'privateAdvanceExecute', has_function_privilege(
        'authenticated', 'private.pachanga_tournament_knockout_apply_official_decision_v1(uuid)', 'EXECUTE'
      )
    )::text
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton;
  `, "verify inert R6C defaults"));
  assert.deepEqual(defaults, {
    advances: 0,
    authenticatedDirectInsert: false,
    brackets: 0,
    completionOff: true,
    completions: 0,
    doubleEliminationOff: true,
    extraTimeOff: true,
    foundationOff: true,
    matchGenerationOff: true,
    nodes: 0,
    penaltiesOff: true,
    privateAdvanceExecute: false,
    progressionOff: true,
    thirdPlaceOff: true,
    twoLegOff: true,
  });

  process.stdout.write(`R6C_MIGRATION_REPORT|${JSON.stringify({
    baseLedger: 169,
    compatibilityMigrations,
    featureMigrations,
    finalLedger: 176,
    flagsDefaultOff: true,
    productRowsDefault: 0,
    schemaEquivalence: "PASS",
    schemaHash,
    waveMigrations,
  })}\n`);
} finally {
  let cleanupError;
  for (const database of [freshDatabase, upgradeDatabase]) {
    try {
      drop(database);
    } catch (error) {
      cleanupError ??= error;
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    }
  }
  rmSync(infrastructureDump, { force: true });
  if (cleanupError) throw cleanupError;
}
