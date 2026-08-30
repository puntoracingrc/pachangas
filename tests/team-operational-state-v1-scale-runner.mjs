import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
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
const databaseName = `pachangas_wave8b_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave8b-scale-${suffix}.sql`);
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("TEAM_OPERATIONAL_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 212);

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
    maxBuffer: 512 * 1024 * 1024,
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

function cleanup() {
  if (admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 8B scale DB") === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 8B scale DB");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      where activity.datname=${quote(databaseName)} and activity.backend_type='client backend'
        and activity.pid<>pg_backend_pid()`, "terminate Wave 8B scale clients");
    admin(`drop database ${databaseName}`, "drop Wave 8B scale DB");
  }
  rmSync(infrastructureDump, { force: true });
}

let summary;
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 8B scale DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 8B scale infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime"],
    "create Wave 8B scale Realtime publication");
  const applyArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 8B scale schema");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/team-operational-state-v1-fixture.sql")], "load Wave 8B scale actors");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', '{"role":"authenticated","sub":"8b000000-0000-4000-8000-000000000020"}', true);
    select public.command_pachanga_team_operational_settings_v1(
      gen_random_uuid(), 1,
      '{"foundationEnabled":true,"enforcementEnabled":true,"restrictionsEnabled":true,"continuityEnabled":true,"appealsEnabled":true,"crossProductGuardsEnabled":true,"publicProjectionEnabled":true,"demoWorldV31Enabled":true,"reason":"Wave 8B scale activation"}'::jsonb
    );
    commit;
  `], "activate Wave 8B scale flags");
  const output = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-f", resolve(root, "tests/team-operational-state-v1-scale.sql")], "run Wave 8B representative scale");
  const summaryLine = output.split("\n").findLast((line) => line.trim().startsWith("{"));
  assert.ok(summaryLine, `Scale summary missing: ${output}`);
  summary = JSON.parse(summaryLine);
  assert.equal(summary.rollback, true);
  assert.equal(Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)} and state <> 'idle'`, "inspect active scale sessions")), 0);
  const remaining = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-c", "select count(*) from public.pachanga_groups where name like 'Wave 8B Scale Team %'"], "verify Wave 8B scale rollback");
  assert.equal(remaining, "0");
} finally {
  try {
    cleanup();
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({ ...summary, cleanup: "PASS" })}\n`);
