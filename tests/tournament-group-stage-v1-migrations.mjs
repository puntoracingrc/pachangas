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
const freshDatabase = `pachangas_r6b_fresh_${suffix}`;
const upgradeDatabase = `pachangas_r6b_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6b-migrations-${suffix}.sql`);
const waveMigrations = [
  "20260827105014_tournament_group_stage_schema_qualification_v1.sql",
  "20260827105018_tournament_group_stage_r4b_adapter_v1.sql",
  "20260827105022_tournament_group_stage_canonical_matches_v1.sql",
  "20260827105027_tournament_group_stage_read_models_hub_v1.sql",
  "20260827105033_tournament_group_stage_access_realtime_v1.sql",
  "20260827105036_tournament_group_stage_hardening_flags_v1.sql",
];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6B_MIGRATION_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 169);
assert.deepEqual(migrationNames.slice(-waveMigrations.length), waveMigrations);
const preWave = migrationNames.filter((name) => !waveMigrations.includes(name));
assert.equal(preWave.length, 163);

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 256 * 1024 * 1024,
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

function apply(database, migrations, label) {
  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(database),
    "-f", resolve(root, manifest.baselinePath),
  ];
  for (const migration of migrations) {
    if (migration.slice(0, 14) > manifest.absorbsThrough) {
      args.push("-f", resolve(root, "supabase/migrations", migration));
    }
  }
  run("psql", args, label);
}

function applyWave(database) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(database)];
  for (const migration of waveMigrations) args.push("-f", resolve(root, "supabase/migrations", migration));
  run("psql", args, "upgrade exact R6B wave 163 to 169");
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
  ], "export R6B Supabase infrastructure");

  provision(freshDatabase);
  apply(freshDatabase, migrationNames, "fresh bootstrap to exact ledger 169");

  provision(upgradeDatabase);
  apply(upgradeDatabase, preWave, "prepare exact ledger 163");
  assert.equal(query(
    upgradeDatabase,
    "select to_regclass('public.pachanga_tournament_group_stage_states') is null;",
    "verify R6B tables absent at ledger 163",
  ), "t");
  applyWave(upgradeDatabase);

  const freshSchema = normalizedSchema(freshDatabase);
  const upgradeSchema = normalizedSchema(upgradeDatabase);
  assert.equal(upgradeSchema, freshSchema, "fresh and 163-to-169 R6B schemas diverged");
  const schemaHash = createHash("sha256").update(freshSchema).digest("hex");

  const defaults = JSON.parse(query(freshDatabase, `
    select jsonb_build_object(
      'groupStageOff', not settings.tournament_group_stage_enabled,
      'groupSchedulingOff', not settings.tournament_group_scheduling_enabled,
      'groupMatchGenerationOff', not settings.tournament_group_match_generation_enabled,
      'trackingOff', not settings.tournament_group_tracking_enabled,
      'standingsOff', not settings.tournament_group_standings_enabled,
      'qualificationOff', not settings.tournament_qualification_enabled,
      'bracketTemplateOff', not settings.tournament_bracket_template_enabled,
      'knockoutGenerationOff', not settings.tournament_knockout_match_generation_enabled,
      'bracketProgressionOff', not settings.tournament_bracket_progression_enabled,
      'publicDiscoveryOff', not settings.tournament_public_discovery_enabled,
      'states', (select count(*) from public.pachanga_tournament_group_stage_states),
      'preparations', (select count(*) from public.pachanga_tournament_group_stage_preparations),
      'scheduleMappings', (select count(*) from public.pachanga_tournament_group_schedule_plans),
      'qualifications', (select count(*) from public.pachanga_tournament_qualification_snapshots),
      'brackets', (select count(*) from public.pachanga_tournament_bracket_templates),
      'authenticatedDirectInsert', has_table_privilege(
        'authenticated', 'public.pachanga_tournament_group_stage_states', 'INSERT'
      ),
      'privatePublishExecute', has_function_privilege(
        'authenticated', 'private.pachanga_tournament_group_schedule_publish_v1(uuid,uuid,uuid,bigint)', 'EXECUTE'
      )
    )::text
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton;
  `, "verify inert R6B defaults"));
  assert.deepEqual(defaults, {
    authenticatedDirectInsert: false,
    bracketProgressionOff: true,
    bracketTemplateOff: true,
    brackets: 0,
    groupMatchGenerationOff: true,
    groupSchedulingOff: true,
    groupStageOff: true,
    knockoutGenerationOff: true,
    preparations: 0,
    privatePublishExecute: false,
    publicDiscoveryOff: true,
    qualificationOff: true,
    qualifications: 0,
    scheduleMappings: 0,
    standingsOff: true,
    states: 0,
    trackingOff: true,
  });

  process.stdout.write(`R6B_MIGRATION_REPORT|${JSON.stringify({
    baseLedger: 163,
    finalLedger: 169,
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
