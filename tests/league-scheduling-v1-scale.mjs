import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_SCHEDULING_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4b_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4b-scale-${suffix}.sql`);
const expectedItems = 95000;

if (!adminUrl) throw new Error("LEAGUE_SCHEDULING_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) throw new Error("R4B_SCALE_LOCAL_DATABASE_REQUIRED");
const migrations = readdirSync(resolve(root, "supabase/migrations")).filter((name) => /^\d{14}_.+\.sql$/.test(name)).sort().filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

function targetUrl() { const value = new URL(adminUrl); value.pathname = `/${databaseName}`; value.searchParams.set("sslmode", "disable"); return value.toString(); }
function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, { cwd: root, encoding: "utf8", env: process.env, input, maxBuffer: 128 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  return (result.stdout ?? "").trim();
}
function admin(sql, label) { return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label); }
function query(sql, label) { return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()], label, sql); }
function apply(files, label) { const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()]; for (const file of files) args.push("-f", file); run(psqlBin, args, label); }
function quote(value) { return `'${String(value).replaceAll("'", "''")}'`; }
function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close scale DB");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid() and not roles.rolsuper`, "terminate scale DB");
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, "inspect scale DB"));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4B_SCALE_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop scale DB");
}

const startedAt = performance.now();
try {
  run(pgDumpBin, ["--schema-only", "--no-owner", "--no-privileges", "--no-publications", "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation", "--exclude-schema=supabase_migrations", "--exclude-schema=realtime", "--file", infrastructureDump, adminUrl], "export infrastructure");
  admin(`create database ${databaseName} template template0`, "create scale DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore scale infrastructure");
  query("create publication supabase_realtime;", "create scale publication");
  apply([resolve(root, manifest.baselinePath), ...migrations.map((name) => resolve(root, "supabase/migrations", name))], "bootstrap scale DB");
  const suite = readFileSync(resolve(root, "tests/league-scheduling-v1-db.sql"), "utf8");
  const setup = suite.slice(0, suite.indexOf("do $body$"));
  const scale = readFileSync(resolve(root, "tests/league-scheduling-v1-scale.sql"), "utf8");
  const output = query(`begin;\n${setup}\n${scale}\nrollback;`, "R4B isolated scale transaction");
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, "R4B scale returned no metrics");
  const metrics = JSON.parse(line);
  assert.equal(metrics.items, expectedItems);
  assert.equal(metrics.slots, 95000);
  assert.equal(metrics.constraints, 5000);
  assert.equal(metrics.preferences, 10000);
  assert.equal(metrics.planLookup, 250);
  assert.equal(metrics.teamCalendarLookup, 9500);
  assert.equal(metrics.roundLookup, 10);
  for (const name of ["constraints", "pairLookup", "preferences", "roundRead", "slotConflict", "teamOverlap"]) {
    assert.ok(metrics.queryPlans[name], `missing ${name} query plan`);
    assert.ok(metrics.queryPlans[name].executionMs < 100, `${name} query exceeded 100ms`);
  }
  assert.ok(metrics.queryPlans.pairLookup.indexes.length > 0, "pair lookup did not use an index");
  assert.ok(metrics.queryPlans.slotConflict.indexes.length > 0, "slot conflict lookup did not use an index");
  assert.ok(metrics.queryPlans.roundRead.indexes.length > 0, "round lookup did not use an index");
  process.stdout.write(`${JSON.stringify({ ...metrics, durationMs: Math.round(performance.now() - startedAt), rollback: true })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
