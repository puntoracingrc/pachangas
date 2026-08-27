import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TOURNAMENT_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r6a_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6a-scale-${suffix}.sql`);

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6A_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
assert.equal(migrations.length + manifest.absorbedMigrations.length, 163);

function targetUrl() {
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
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function dropDatabase() {
  if (admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect R6A scale database") === "0") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close R6A scale database");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate R6A scale database");
  admin(`drop database if exists ${databaseName}`, "drop R6A scale database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R6A scale database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create Realtime publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R6A scale database");
  const fixtureOutput = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-f", resolve(root, "tests/tournament-foundation-draw-v1-fixture.sql")], "load R6A scale fixture");
  assert.match(fixtureOutput, /R6A_FIXTURE_OK/);
  const output = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-f", resolve(root, "tests/tournament-foundation-draw-v1-scale.sql")], "run R6A scale rollback");
  const lines = output.split("\n").map((line) => line.trim());
  const report = JSON.parse(lines.find((line) => line.startsWith("R6A_SCALE_REPORT|"))?.slice("R6A_SCALE_REPORT|".length) ?? "null");
  const rollback = JSON.parse(lines.find((line) => line.startsWith("R6A_SCALE_ROLLBACK|"))?.slice("R6A_SCALE_ROLLBACK|".length) ?? "null");
  assert.deepEqual({
    constraints: report.constraints,
    manualLocks: report.manualLocks,
    placements: report.placements,
    plans: report.plans,
    revisions: report.revisions,
  }, { constraints: 20000, manualLocks: 20000, placements: 100000, plans: 10000, revisions: 20000 });
  assert.deepEqual(rollback, { plans: 0, revisions: 0, stages: 0 });
  assert.ok(report.durationMs < 180000);
  for (const key of ["planLookupMs", "revisionLookupMs", "placementLookupMs", "auditLookupMs"]) {
    assert.ok(report[key] < 1000, `${key} exceeded 1000ms`);
  }
  process.stdout.write(`${JSON.stringify({ database: "temporary", report, rollback: "PASS" })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
