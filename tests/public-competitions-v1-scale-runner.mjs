import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
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
const databaseName = `pachangas_wave7a_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7a-scale-${suffix}.sql`);

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("PUBLIC_COMPETITIONS_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 183);

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

function cleanupDatabase() {
  if (admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect scale DB") === "0") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close scale DB");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    where activity.datname=${quote(databaseName)} and activity.backend_type='client backend'
      and activity.pid<>pg_backend_pid()`, "terminate scale clients");
  admin(`drop database if exists ${databaseName}`, "drop scale DB");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 7A scale DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore scale infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"],
    "create scale Realtime publication");
  const applyArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 7A scale schema");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/public-competitions-v1-fixture.sql")], "load scale actors");
  const output = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-f", resolve(root, "tests/public-competitions-v1-scale.sql")], "run Wave 7A representative scale");
  const summaryLine = output.split("\n").findLast((line) => line.trim().startsWith("{"));
  assert.ok(summaryLine, `Scale summary missing: ${output}`);
  const summary = JSON.parse(summaryLine);
  assert.equal(summary.rollback, true);
  const remaining = Number(run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-c", "select count(*) from public.pachanga_competitions where slug like 'wave7a-scale-competition-%'"],
  "verify scale rollback"));
  assert.equal(remaining, 0);
  process.stdout.write(`${JSON.stringify(summary)}\n`);
} finally {
  cleanupDatabase();
  try {
    unlinkSync(infrastructureDump);
  } catch (error) {
    if (!(error instanceof Error) || error.code !== "ENOENT") throw error;
  }
}
