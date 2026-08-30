import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.VENUE_OPERATIONS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave9a_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave9a-scale-${suffix}.sql`);
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("VENUE_OPERATIONS_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 220);
assert.equal(migrations.at(-1), "20260830145100_venue_hardening_indexes_flags_v1.sql");

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

function query(sql, label = "query Wave 9A scale database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function dropDatabase() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect scale database");
  if (exists !== "1") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close scale database");
  admin(`select pg_terminate_backend(pid) from pg_stat_activity where datname=${quote(databaseName)} and pid<>pg_backend_pid()`, "terminate scale clients");
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
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore scale infrastructure");
  query("create publication supabase_realtime", "create scale Realtime publication");
  apply([
    resolve(root, manifest.baselinePath),
    ...migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "bootstrap Wave 9A scale database");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, "tests/venue-operations-v1-fixture.sql"),
  ], "load Wave 9A scale fixture");
  query(`
    grant usage on schema auth to authenticated,anon;
    grant execute on function auth.uid() to authenticated,anon;
    grant execute on function auth.jwt() to authenticated,anon;
    update private.pachanga_club_foundation_settings
      set club_foundation_enabled=true where singleton;
    update private.pachanga_venue_settings_v1 set
      venue_foundation_enabled=true,
      venue_management_enabled=true,
      venue_public_profiles_enabled=true,
      venue_public_directory_enabled=true,
      venue_availability_enabled=true,
      venue_reservation_requests_enabled=true,
      venue_counteroffers_enabled=true,
      venue_reservation_holds_enabled=true,
      venue_canonical_reservations_enabled=true,
      venue_match_binding_enabled=true,
      venue_r4d_integration_enabled=true,
      demo_world_v34_enabled=true
    where singleton;
  `, "enable disposable scale flags");

  const output = run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-f", resolve(root, "tests/venue-operations-v1-scale.sql"),
  ], "run exact Wave 9A scale corpus and latency suite");
  const jsonLine = output.split("\n").map((line) => line.trim()).findLast((line) => line.startsWith("{"));
  assert.ok(jsonLine, `scale suite returned no JSON evidence: ${output.slice(-2000)}`);
  evidence = JSON.parse(jsonLine);

  assert.deepEqual(evidence.corpus, {
    venues: 1000,
    pitches: 5000,
    availabilityTemplates: 40000,
    availabilityExceptions: 10000,
    availabilityTotal: 50000,
    reservationRequests: 100000,
    reservations: 50000,
    invalidations: 100000,
  });
  assert.deepEqual(Object.keys(evidence.metrics).sort(), [
    "accept", "availability_query", "conflict_detection", "directory", "health",
    "hold", "match_binding", "request_submit", "reservation_desk",
  ]);
  for (const [metric, values] of Object.entries(evidence.metrics)) {
    assert.ok(values.samples >= 20, `${metric} has too few samples`);
    assert.ok(values.p50Ms >= 0 && values.p95Ms >= values.p50Ms, `${metric} percentiles are invalid`);
  }

  const rollbackCounts = JSON.parse(query(`select jsonb_build_object(
    'venues',(select count(*) from public.pachanga_club_venues),
    'pitches',(select count(*) from public.pachanga_venue_pitches),
    'templates',(select count(*) from public.pachanga_venue_availability_templates),
    'exceptions',(select count(*) from public.pachanga_venue_availability_exceptions),
    'requests',(select count(*) from public.pachanga_venue_reservation_requests),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations)
  )::text`, "verify scale rollback"));
  assert.deepEqual(rollbackCounts, {
    venues: 0,
    pitches: 0,
    templates: 0,
    exceptions: 0,
    requests: 0,
    reservations: 0,
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
