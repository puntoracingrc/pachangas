import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { leagueOperationalFixtureSql } from "./league-operational-exceptions-v1-fixture.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4d_performance_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4d-performance-${suffix}.sql`);

if (!adminUrl) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4D_PERFORMANCE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

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

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close R4D performance database");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate R4D performance database");
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      "inspect R4D performance database",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4D_PERFORMANCE_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop R4D performance database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R4D performance database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore performance infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create performance publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R4D performance database");
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl()],
    "load R4D performance fixture",
    `begin;\n${leagueOperationalFixtureSql({ enableFlags: true })}\ncommit;\n`,
  );
  const output = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-f", resolve(root, "tests/league-operational-exceptions-v1-performance.sql"),
  ], "R4D command performance suite");
  const measurements = output.split("\n")
    .map((value) => value.trim())
    .filter((value) => value.startsWith("R4D_PERFORMANCE|"))
    .map((value) => JSON.parse(value.slice("R4D_PERFORMANCE|".length)));
  const expected = [
    "request_create", "request_respond", "reschedule", "venue_change",
    "no_show_confirmation", "suspension_resolution",
    "administrative_decision", "standings_rebuild",
  ];
  assert.deepEqual(measurements.map((entry) => entry.label), expected);
  for (const measurement of measurements) {
    assert.ok(measurement.durationMs >= 0 && measurement.durationMs < 2000,
      `${measurement.label} exceeded the 2000ms local stop threshold: ${measurement.durationMs}`);
  }
  process.stdout.write(`${JSON.stringify({
    stopThresholdMs: 2000,
    measurements: Object.fromEntries(measurements.map((entry) => [entry.label, entry.durationMs])),
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
