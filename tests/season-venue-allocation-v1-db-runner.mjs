import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.SEASON_VENUE_ALLOCATION_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const upgradeDatabaseName = `pachangas_wave9b_upgrade_${suffix}`;
const freshDatabaseName = `pachangas_wave9b_fresh_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave9b-infra-${suffix}.sql`);
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("SEASON_VENUE_ALLOCATION_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 228);
assert.equal(migrations.at(-1), "20260830223014_competition_venue_allocation_hardening_flags_v1.sql");
const waveMigrations = migrations.slice(-8);
const preWaveMigrations = migrations.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !waveMigrations.includes(name)
));
assert.equal(migrations.filter((name) => !waveMigrations.includes(name)).length, 220);

function targetUrl(name) {
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
    maxBuffer: 256 * 1024 * 1024,
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

function query(name, args, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", ...args, targetUrl(name)], label);
}

function applyTo(name, files, label) {
  const args = ["-q", "--single-transaction"];
  for (const file of files) args.push("-f", file);
  query(name, args, label);
}

function normalizedSchema(name) {
  return run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", targetUrl(name),
  ], `export ${name} product schema`)
    .split("\n")
    .filter((line) => !/^--|^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
}

function dropDatabase(name) {
  const exists = admin(`select count(*) from pg_database where datname=${quote(name)}`, `inspect ${name}`);
  if (exists === "1") {
    admin(`alter database ${name} with allow_connections false`, `close ${name}`);
    admin(
      `select pg_terminate_backend(pid) from pg_stat_activity where datname=${quote(name)} and pid<>pg_backend_pid()`,
      `terminate ${name} clients`,
    );
    admin(`drop database ${name}`, `drop ${name}`);
  }
}

function cleanup() {
  dropDatabase(upgradeDatabaseName);
  dropDatabase(freshDatabaseName);
  rmSync(infrastructureDump, { force: true });
}

let schemaHash;
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");

  for (const name of [upgradeDatabaseName, freshDatabaseName]) {
    admin(`create database ${name} template template0`, `create ${name}`);
    query(name, ["-q", "-f", infrastructureDump], `restore ${name} infrastructure`);
    query(name, ["-Atq", "-c", "create publication supabase_realtime"], `create ${name} Realtime publication`);
  }

  applyTo(upgradeDatabaseName, [
    resolve(root, manifest.baselinePath),
    ...preWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 220-migration Wave 9A base");
  applyTo(
    upgradeDatabaseName,
    waveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
    "upgrade 220 to 228",
  );

  applyTo(freshDatabaseName, [
    resolve(root, manifest.baselinePath),
    ...migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "fresh bootstrap to 228");

  const upgradedSchema = normalizedSchema(upgradeDatabaseName);
  const freshSchema = normalizedSchema(freshDatabaseName);
  assert.equal(freshSchema, upgradedSchema, "fresh and 220-to-228 schemas must be identical");
  schemaHash = createHash("sha256").update(upgradedSchema).digest("hex");
  assert.equal(
    query(upgradeDatabaseName, [
      "-Atq", "-c",
      `select count(*) from private.pachanga_venue_settings_v1
       where singleton
         and not venue_recurring_series_enabled
         and not competition_venue_pool_enabled
         and not competition_venue_allocation_foundation_enabled
         and not demo_world_v35_enabled`,
    ], "verify Wave 9B flags born OFF"),
    "1",
  );
  const functionalOutput = query(upgradeDatabaseName, [
    "-q", "--single-transaction",
    "-f", resolve(root, "tests/season-venue-allocation-v1-fixture.sql"),
    "-f", resolve(root, "tests/season-venue-allocation-v1-db.sql"),
  ], "run Wave 9B canonical DB/RLS/allocation suite");
  assert.match(functionalOutput, /SEASON_VENUE_ALLOCATION_V1_DB_PASS/);
} finally {
  try {
    cleanup();
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({
  database: "ephemeral-local",
  baseLedger: 220,
  finalLedger: 228,
  migrations: 8,
  schemaEquivalence: "PASS",
  schemaHash,
  flagsBornOff: "PASS",
  canonicalLifecycle: "PASS",
  cleanup: "PASS",
})}\n`);
