import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TEAM_OPERATIONAL_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave8b_db_${suffix}`;
const freshDatabaseName = `pachangas_wave8b_fresh_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave8b-db-${suffix}.sql`);
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("TEAM_OPERATIONAL_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 212);
assert.equal(migrations.at(-1), "20260829221312_team_operational_hardening_indexes_flags_v1.sql");
const waveMigrations = migrations.slice(-8);
const preWaveMigrations = migrations.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !waveMigrations.includes(name)
));
assert.equal(migrations.filter((name) => !waveMigrations.includes(name)).length, 204);

function targetUrl(name = databaseName) {
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

function query(args, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", ...args], label);
}

function applyTo(name, files, label) {
  const args = ["-q", "--single-transaction", targetUrl(name)];
  for (const file of files) args.push("-f", file);
  query(args, label);
}

function normalizedSchema(name) {
  return run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--schema=simulation", targetUrl(name),
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
    admin("select pg_sleep(0.25)", `wait for ${name} internal clients`);
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      join pg_roles roles on roles.oid=activity.usesysid
      where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`, `terminate ${name} clients`);
    admin(`drop database ${name}`, `drop ${name}`);
  }
}

function cleanup() {
  dropDatabase(databaseName);
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

  admin(`create database ${databaseName} template template0`, "create Wave 8B upgrade database");
  query(["-q", targetUrl(), "-f", infrastructureDump], "restore Wave 8B upgrade infrastructure");
  query(["-Atq", targetUrl(), "-c", "create publication supabase_realtime"], "create upgrade Realtime publication");
  applyTo(databaseName, [
    resolve(root, manifest.baselinePath),
    ...preWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 204-migration Wave 8B base");
  assert.equal(
    query(["-Atq", targetUrl(), "-c", "select to_regclass('private.pachanga_team_operational_states_v1') is null"], "verify pre-Wave 8B base"),
    "t",
  );
  applyTo(
    databaseName,
    waveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
    "upgrade 204 to 212",
  );

  admin(`create database ${freshDatabaseName} template template0`, "create Wave 8B fresh database");
  query(["-q", targetUrl(freshDatabaseName), "-f", infrastructureDump], "restore Wave 8B fresh infrastructure");
  query(["-Atq", targetUrl(freshDatabaseName), "-c", "create publication supabase_realtime"], "create fresh Realtime publication");
  applyTo(freshDatabaseName, [
    resolve(root, manifest.baselinePath),
    ...migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "fresh bootstrap to 212");

  const upgradedSchema = normalizedSchema(databaseName);
  const freshSchema = normalizedSchema(freshDatabaseName);
  assert.equal(freshSchema, upgradedSchema, "fresh and 204-to-212 schemas must be identical");
  schemaHash = createHash("sha256").update(upgradedSchema).digest("hex");
  query(["-q", targetUrl(), "-f", resolve(root, "tests/team-operational-state-v1-fixture.sql")], "load Wave 8B synthetic fixture");
  const output = query([
    "-Atq", targetUrl(), "-c", "begin",
    "-f", resolve(root, "tests/team-operational-state-v1-db.sql"),
    "-c", "rollback",
  ], "Wave 8B SQL, RLS, idempotency and product guard suite");
  assert.match(output, /TEAM_OPERATIONAL_STATE_V1_DB_PASS/);
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
  finalLedger: 212,
  migrations: 8,
  schemaEquivalence: "PASS",
  schemaHash,
  sqlRlsIdempotencyGuards: "PASS",
  cleanup: "PASS",
})}\n`);
