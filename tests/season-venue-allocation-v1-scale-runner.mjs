import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
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
const databaseName = `pachangas_wave9b_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave9b-scale-${suffix}.sql`);
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("SEASON_VENUE_ALLOCATION_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 228);
assert.equal(migrations.at(-1), "20260830223014_competition_venue_allocation_hardening_flags_v1.sql");

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

function query(args, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", ...args, targetUrl()], label);
}

function dropDatabase() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect scale database");
  if (exists !== "1") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close scale database");
  admin(
    `select pg_terminate_backend(pid) from pg_stat_activity where datname=${quote(databaseName)} and pid<>pg_backend_pid()`,
    "terminate scale clients",
  );
  admin(`drop database ${databaseName}`, "drop scale database");
}

let evidence;
const startedAt = performance.now();
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create scale database");
  query(["-q", "-f", infrastructureDump], "restore scale infrastructure");
  query(["-Atq", "-c", "create publication supabase_realtime"], "create scale Realtime publication");

  const bootstrapArgs = ["-q", "--single-transaction", "-f", resolve(root, manifest.baselinePath)];
  for (const migration of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    bootstrapArgs.push("-f", resolve(root, "supabase/migrations", migration));
  }
  query(bootstrapArgs, "bootstrap Wave 9B scale database");
  query([
    "-q", "--single-transaction", "-f", resolve(root, "tests/season-venue-allocation-v1-fixture.sql"),
  ], "load Wave 9B scale fixture");

  const output = query([
    "-Atq", "-f", resolve(root, "tests/season-venue-allocation-v1-scale.sql"),
  ], "run exact Wave 9B scale corpus and latency suite");
  const jsonLine = output.split("\n").map((line) => line.trim()).findLast((line) => line.startsWith("{"));
  assert.ok(jsonLine, `scale suite returned no JSON evidence: ${output.slice(-3000)}`);
  evidence = JSON.parse(jsonLine);

  assert.deepEqual(evidence.corpus, {
    recurringSeries: 1000,
    occurrences: 25000,
    venuePools: 1000,
    allocationPlans: 10000,
    allocationItems: 100000,
    manualLocks: 50000,
    reservations: 50000,
    bindings: 50000,
    invalidations: 50000,
    bindingsAndInvalidations: 100000,
  });
  assert.deepEqual(evidence.competitionSizes, {
    16: 16,
    32: 32,
    64: 64,
    128: 128,
    256: 256,
  });
  assert.deepEqual(Object.keys(evidence.metrics).sort(), [
    "automatic_generation", "bulk_hold", "health", "hybrid_completion",
    "input_freeze", "organizer_desk", "pool_read", "publish",
    "series_materialization", "validation",
  ]);
  for (const [metric, values] of Object.entries(evidence.metrics)) {
    assert.equal(values.samples, 25, `${metric} must have 25 samples`);
    assert.ok(values.p50Ms >= 0 && values.p95Ms >= values.p50Ms, `${metric} percentiles are invalid`);
    assert.ok(values.p95Ms < 2500, `${metric} p95 ${values.p95Ms}ms exceeds 2500ms`);
  }

  const rollback = JSON.parse(query([
    "-Atq", "-c", `select jsonb_build_object(
      'series',(select count(*) from public.pachanga_venue_recurring_series),
      'pools',(select count(*) from public.pachanga_competition_venue_pools),
      'plans',(select count(*) from public.pachanga_competition_venue_allocation_plans),
      'items',(select count(*) from public.pachanga_competition_venue_allocation_items),
      'locks',(select count(*) from public.pachanga_competition_venue_allocation_locks),
      'reservations',(select count(*) from public.pachanga_venue_reservations),
      'bindings',(select count(*) from public.pachanga_venue_match_bindings),
      'invalidations',(select count(*) from public.pachanga_venue_invalidations)
    )::text`,
  ], "verify scale rollback"));
  assert.deepEqual(rollback, {
    series: 0,
    pools: 0,
    plans: 0,
    items: 0,
    locks: 0,
    reservations: 0,
    bindings: 0,
    invalidations: 0,
  });
  evidence.fullRollback = "PASS";
} finally {
  try {
    dropDatabase();
    rmSync(infrastructureDump, { force: true });
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({
  ...evidence,
  wallSeconds: Number(((performance.now() - startedAt) / 1000).toFixed(3)),
  cleanup: "PASS",
})}\n`);
