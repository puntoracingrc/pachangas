import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.ORGANIZER_BILLING_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave7b_scale_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7b-scale-${suffix}.sql`);
const waveMigrationPattern = /^2026082816375[0-6]_/;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("ORGANIZER_BILLING_SCALE_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
const waveMigrations = migrations.filter((name) => waveMigrationPattern.test(name));
assert.equal(migrations.length, 190);
assert.equal(waveMigrations.length, 7);

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
    maxBuffer: 512 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function timedRun(binary, args, label) {
  const result = spawnSync("/usr/bin/time", ["-lp", binary, ...args], {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 512 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  const stderr = result.stderr ?? "";
  const metric = (name) => Number(stderr.match(new RegExp(`^${name}\\s+([0-9.]+)$`, "m"))?.[1] ?? 0);
  const rss = Number(stderr.match(/^\s*([0-9]+)\s+maximum resident set size$/m)?.[1] ?? 0);
  return {
    realMs: Math.round(metric("real") * 1000),
    userCpuMs: Math.round(metric("user") * 1000),
    systemCpuMs: Math.round(metric("sys") * 1000),
    maxResidentBytes: rss,
  };
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label = "query Wave 7B scale database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function databaseMetric() {
  return JSON.parse(query(`select jsonb_build_object(
    'ungrantedLocks', (select count(*) from pg_locks where not granted),
    'indexBytes', (
      select coalesce(sum(pg_relation_size(indexes.indexrelid)), 0)
      from pg_index indexes
      join pg_class tables on tables.oid=indexes.indrelid
      join pg_namespace namespaces on namespaces.oid=tables.relnamespace
      where namespaces.nspname in ('public','private')
        and (tables.relname like 'pachanga_organizer%' or tables.relname like 'pachanga_stripe%'
          or tables.relname like 'pachanga_competition_entitlement%')
    ),
    'catalogRows', case when to_regclass('public.pachanga_organizer_plan_catalog') is null then 0
      else (select count(*) from public.pachanga_organizer_plan_catalog) end
  )::text`, "read Wave 7B migration metric"));
}

function explain(sql, expectedIndex, label) {
  const plan = JSON.parse(query(`explain (analyze, buffers, format json) ${sql}`, label));
  const planText = JSON.stringify(plan);
  assert.match(planText, new RegExp(expectedIndex), `${label} did not use ${expectedIndex}: ${planText}`);
  const executionMs = Number(plan[0]["Execution Time"]);
  assert.ok(executionMs < 100, `${label} exceeded 100ms: ${executionMs}`);
  return { executionMs, expectedIndex };
}

function cleanup() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 7B scale database");
  if (exists === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 7B scale database");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()`, "terminate Wave 7B scale clients");
    admin(`drop database ${databaseName}`, "drop Wave 7B scale database");
  }
  rmSync(infrastructureDump, { force: true });
}

let finalSummary;
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 7B scale database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 7B scale infrastructure");
  query("create publication supabase_realtime;", "create Wave 7B scale Realtime publication");

  const preWaveArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough && !waveMigrationPattern.test(name))) {
    preWaveArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  const preWaveTiming = timedRun(psqlBin, preWaveArgs, "bootstrap pre-Wave 7B scale schema");

  const migrationMetrics = [];
  for (const name of waveMigrations) {
    const timing = timedRun(psqlBin, [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
      "-c", "set lock_timeout='5s'; set statement_timeout='5min';",
      "-f", resolve(root, "supabase/migrations", name),
    ], `apply ${name}`);
    const metric = databaseMetric();
    assert.equal(metric.ungrantedLocks, 0, `${name} left an ungranted lock`);
    assert.ok(timing.realMs < 30_000, `${name} exceeded the local 30s migration threshold`);
    migrationMetrics.push({ migration: basename(name), ...timing, ...metric });
  }

  const seedTiming = timedRun(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/organizer-plans-stripe-billing-v1-scale.sql"),
  ], "load Wave 7B representative volume");
  assert.ok(seedTiming.realMs < 120_000, `Wave 7B representative seed exceeded 120s: ${seedTiming.realMs}`);

  const rows = JSON.parse(query(`select jsonb_build_object(
    'accounts', (select count(*) from private.pachanga_organizer_billing_accounts),
    'subscriptions', (select count(*) from private.pachanga_stripe_subscription_projections_v1),
    'accessGrants', (select count(*) from private.pachanga_organizer_access_grants_v1),
    'entitlements', (select count(*) from public.pachanga_competition_entitlement_grants where billing_access_grant_id is not null),
    'webhookEvents', (select count(*) from private.pachanga_stripe_webhook_events_v2),
    'deliveries', (select count(*) from private.pachanga_stripe_webhook_deliveries_v1),
    'invoices', (select count(*) from private.pachanga_stripe_invoice_projections_v1),
    'paymentFailures', (select count(*) from private.pachanga_stripe_payment_failures_v1),
    'reconciliations', (select count(*) from private.pachanga_stripe_billing_reconciliations_v1)
  )::text`, "read Wave 7B representative rows"));
  assert.deepEqual(rows, {
    accounts: 2000,
    subscriptions: 2000,
    accessGrants: 2000,
    entitlements: 37660,
    webhookEvents: 10000,
    deliveries: 10000,
    invoices: 4000,
    paymentFailures: 400,
    reconciliations: 10000,
  });

  const queryPlans = {
    accountByCustomer: explain(
      "select id from private.pachanga_organizer_billing_accounts where stripe_mode='test' and stripe_customer_id='cus_wave7b_scale_1444'",
      "pachanga_organizer_billing_account_customer_idx",
      "explain billing account by Stripe Customer",
    ),
    latestSubscription: explain(
      "select id from private.pachanga_stripe_subscription_projections_v1 where billing_account_id=md5('wave7b-scale-account:1444')::uuid order by server_sequence desc,id desc limit 1",
      "pachanga_stripe_subscription_account_idx",
      "explain latest subscription",
    ),
    latestInvoice: explain(
      "select id from private.pachanga_stripe_invoice_projections_v1 where billing_account_id=md5('wave7b-scale-account:1444')::uuid order by last_event_created_at desc,last_event_id desc limit 1",
      "pachanga_stripe_invoice_account_idx",
      "explain latest invoice",
    ),
    eventIdentity: explain(
      "select id from private.pachanga_stripe_webhook_events_v2 where stripe_mode='test' and stripe_event_id='evt_wave7b_scale_9444'",
      "pachanga_stripe_webhook_events__stripe_mode_stripe_event_id_key",
      "explain Stripe event identity",
    ),
    reconciliationQueue: explain(
      "select id from private.pachanga_stripe_billing_reconciliations_v1 where status in ('PENDING','FAILED') order by server_sequence,id limit 20",
      "pachanga_stripe_reconciliation_queue_idx",
      "explain reconciliation queue",
    ),
  };

  const finalMetric = databaseMetric();
  assert.equal(finalMetric.ungrantedLocks, 0);
  assert.ok(finalMetric.indexBytes < 256 * 1024 * 1024, `Wave 7B indexes exceeded 256MiB: ${finalMetric.indexBytes}`);
  finalSummary = {
    database: "ephemeral-local",
    ledger: 190,
    preWaveTiming,
    migrationMetrics,
    seedTiming,
    rows,
    queryPlans,
    finalIndexBytes: finalMetric.indexBytes,
    ungrantedLocks: finalMetric.ungrantedLocks,
    thresholds: {
      migrationMs: 30_000,
      seedMs: 120_000,
      queryMs: 100,
      indexBytes: 256 * 1024 * 1024,
    },
  };
} finally {
  cleanup();
}

process.stdout.write(`${JSON.stringify({ ...finalSummary, cleanup: "PASS" })}\n`);
