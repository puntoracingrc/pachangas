import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.PUBLIC_COMPETITIONS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const upgradeDatabase = `pachangas_wave7a_upgrade_${suffix}`;
const freshDatabase = `pachangas_wave7a_fresh_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7a-infrastructure-${suffix}.sql`);
const waveMigrations = [
  "20260828072045_tournament_knockout_fk_index_hardening_v1.sql",
  "20260828072047_public_competition_publication_consent_v1.sql",
  "20260828072048_competition_registration_requests_waitlist_v1.sql",
  "20260828072049_public_competition_read_models_directory_v1.sql",
  "20260828072051_public_competition_commands_authority_v1.sql",
  "20260828072052_public_competition_access_realtime_v1.sql",
  "20260828072053_public_competition_product_flags_hardening_v1.sql",
];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("PUBLIC_COMPETITIONS_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 183);
assert.deepEqual(migrationNames.slice(-waveMigrations.length), waveMigrations);
const preWaveMigrations = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !waveMigrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !waveMigrations.includes(name)).length, 176);
assert.equal(preWaveMigrations.length, 176 - manifest.absorbedMigrations.length);

function databaseUrl(name) {
  const value = new URL(adminUrl);
  value.pathname = `/${name}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 192 * 1024 * 1024,
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

function query(name, sql, label) {
  return run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(name), "-c", sql,
  ], label);
}

function apply(name, files, label) {
  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", databaseUrl(name),
  ];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function normalizedSchema(name) {
  return run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--schema=simulation", databaseUrl(name),
  ], `export ${name} schema`)
    .split("\n")
    .filter((line) => !/^--|^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
}

function createDatabase(name) {
  admin(`create database ${name} template template0`, `create ${name}`);
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(name), "-f", infrastructureDump,
  ], `restore infrastructure for ${name}`);
  query(name, "create publication supabase_realtime;", `create Realtime publication for ${name}`);
}

function dropDatabase(name) {
  if (admin(`select count(*) from pg_database where datname=${quote(name)}`, `inspect ${name}`) === "0") return;
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity
    where activity.datname=${quote(name)}
      and activity.backend_type='client backend'
      and activity.pid<>pg_backend_pid()`, `terminate ${name}`);
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");

  createDatabase(upgradeDatabase);
  apply(upgradeDatabase, [
    resolve(root, manifest.baselinePath),
    ...preWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 176-migration Wave 7A base");
  assert.equal(query(upgradeDatabase,
    "select to_regclass('public.pachanga_competition_publications') is null",
    "verify pre-Wave 7A base"), "t");
  apply(upgradeDatabase, waveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
    "upgrade 176 to Wave 7A");

  createDatabase(freshDatabase);
  apply(freshDatabase, [
    resolve(root, manifest.baselinePath),
    ...migrationNames
      .filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "install fresh 183-migration schema");

  const upgradedSchema = normalizedSchema(upgradeDatabase);
  const freshSchema = normalizedSchema(freshDatabase);
  assert.equal(freshSchema, upgradedSchema, "fresh and 176-to-183 schemas must be identical");
  const schemaHash = createHash("sha256").update(upgradedSchema).digest("hex");

  const inactive = JSON.parse(query(upgradeDatabase, `
    select jsonb_build_object(
      'foundationOff', not settings.public_competition_foundation_enabled,
      'publicationOff', not settings.public_competition_publication_enabled,
      'discoveryOff', not settings.public_competition_discovery_enabled,
      'registrationOff', not settings.public_competition_registration_requests_enabled,
      'waitlistOff', not settings.public_competition_waitlist_enabled,
      'disciplineOff', not settings.public_competition_discipline_enabled,
      'autoAcceptOff', not settings.public_competition_auto_accept_enabled,
      'publications', (select count(*) from public.pachanga_competition_publications),
      'requests', (select count(*) from public.pachanga_competition_registration_requests),
      'reports', (select count(*) from private.pachanga_competition_reports),
      'anonAuthorityExecute', has_function_privilege(
        'anon',
        'public.command_pachanga_competition_registration_request_v1(uuid,uuid,bigint,text,jsonb,jsonb)',
        'EXECUTE'
      )
    )::text
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton;
  `, "verify inert Wave 7A install"));
  assert.deepEqual(inactive, {
    anonAuthorityExecute: false,
    autoAcceptOff: true,
    disciplineOff: true,
    discoveryOff: true,
    foundationOff: true,
    publicationOff: true,
    publications: 0,
    registrationOff: true,
    reports: 0,
    requests: 0,
    waitlistOff: true,
  });

  const output = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(upgradeDatabase),
    "-c", "begin",
    "-f", resolve(root, "tests/public-competitions-v1-fixture.sql"),
    "-f", resolve(root, "tests/public-competitions-v1-db.sql"),
    "-c", "rollback",
  ], "Wave 7A SQL, RLS, privacy, idempotency and read-model suite");
  assert.match(output, /PUBLIC_COMPETITIONS_V1_DB_OK/);

  process.stdout.write(`${JSON.stringify({
    baseLedger: 176,
    bootstrapFilesBeforeWave: 1 + preWaveMigrations.length,
    finalLedger: 183,
    database: "temporary",
    flagsDefaultOff: true,
    migrations: waveMigrations.length,
    schemaEquivalence: "PASS",
    schemaHash,
    sqlRlsPrivacyIdempotency: "PASS",
  })}\n`);
} finally {
  let cleanupError;
  for (const name of [upgradeDatabase, freshDatabase]) {
    try {
      dropDatabase(name);
    } catch (error) {
      cleanupError ??= error;
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    }
  }
  try {
    unlinkSync(infrastructureDump);
  } catch (error) {
    if (!(error instanceof Error) || error.code !== "ENOENT") throw error;
  }
  if (cleanupError) throw cleanupError;
}
