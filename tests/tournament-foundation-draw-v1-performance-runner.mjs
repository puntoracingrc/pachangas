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
const databaseName = `pachangas_r6a_performance_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6a-performance-${suffix}.sql`);

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6A_PERFORMANCE_LOCAL_DATABASE_REQUIRED");
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
  if (result.status !== 0) {
    const stdoutTail = (result.stdout ?? "").slice(-6000);
    const stderrTail = (result.stderr ?? "").slice(-6000);
    throw new Error(`${label} failed (${result.status}):\n${stdoutTail}\n${stderrTail}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function dropDatabase() {
  if (admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect R6A performance database") === "0") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close R6A performance database");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate R6A performance database");
  admin(`drop database if exists ${databaseName}`, "drop R6A performance database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R6A performance database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create Realtime publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R6A performance database");
  const output = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-v", "R6A_ENGINE_KEEP=1",
    "-c", "begin",
    "-f", resolve(root, "tests/tournament-foundation-draw-v1-engine.sql"),
    "-f", resolve(root, "tests/tournament-foundation-draw-v1-performance.sql"),
    "-c", "rollback",
  ], "run R6A performance matrix");
  const reportLine = output.split("\n").find((line) => line.startsWith("R6A_PERFORMANCE_REPORT|"));
  assert.ok(reportLine, "R6A performance report missing");
  const report = JSON.parse(reportLine.slice("R6A_PERFORMANCE_REPORT|".length));
  const expected = [
    "8 teams pure random",
    "16 teams seeded pots",
    "32 teams constraint optimized",
    "64 teams engine capacity",
    "manual swap",
    "hybrid complete",
    "validate",
    "publish",
    "organizer desk",
    "audit view",
  ];
  assert.deepEqual(Object.keys(report.operations).sort(), expected.sort());
  assert.equal(report.samples, 260);
  assert.equal(report.solverAttemptCap, 128);
  assert.equal(report.tournamentMatches, 0);
  for (const [operation, metrics] of Object.entries(report.operations)) {
    assert.ok(metrics.p95Ms < 120000, `${operation} p95 exceeded bounded limit`);
  }
  process.stdout.write(`${JSON.stringify({ database: "temporary", report, rollback: "PASS" })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
