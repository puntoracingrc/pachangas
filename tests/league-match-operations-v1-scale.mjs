import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_MATCH_OPERATIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4c_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4c-scale-${suffix}.sql`);

if (!adminUrl) throw new Error("LEAGUE_MATCH_OPERATIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4C_SCALE_LOCAL_DATABASE_REQUIRED");
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

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 128 * 1024 * 1024,
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

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close R4C scale DB");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate R4C scale DB");
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, "inspect R4C scale DB"));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4C_SCALE_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop R4C scale DB");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure for scale");
  admin(`create database ${databaseName} template template0`, "create R4C scale DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore R4C scale infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create scale Realtime publication");
  const migrationFiles = [
    resolve(root, manifest.baselinePath),
    ...migrations.map((name) => resolve(root, "supabase/migrations", name)),
  ];
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(), ...migrationFiles.flatMap((file) => ["-f", file])],
    "bootstrap R4C scale DB",
  );
  const output = run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-f", resolve(root, "tests/league-match-operations-v1-scale.sql")],
    "R4C scale and performance suite",
  );
  const reportLine = output.split("\n").filter((line) => line.startsWith("{")) .at(-1);
  assert.ok(reportLine, `R4C scale report missing: ${output}`);
  const report = JSON.parse(reportLine);
  assert.equal(report.scale["20Teams"].fixtures, 380);
  assert.equal(report.scale["32Teams"].fixtures, 992);
  assert.equal(report.scale.resultRevisions, 10000);
  assert.equal(report.scale.officialDecisions, 10000);
  assert.equal(report.scale.historicalRebuilds, 1000);
  assert.equal(report.historySelectionStable, true);
  process.stdout.write(`${JSON.stringify(report)}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
