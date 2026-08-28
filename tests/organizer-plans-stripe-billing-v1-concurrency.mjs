import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.ORGANIZER_BILLING_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave7b_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7b-concurrency-${suffix}.sql`);
const platformActor = "7b000000-0000-4000-8000-000000000003";
const teamId = "7b000000-0000-4000-8000-000000000010";
const billingAccountId = "7b500000-0000-4000-8000-000000000001";
let completedSummary;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("ORGANIZER_BILLING_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.at(-1), "20260828205317_organizer_commercial_hardening_flags_v1.sql");

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

function query(sql, label = "query Wave 7B concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function authenticated(actorId, role, statement) {
  return `begin;
set local role ${role};
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role, sub: actorId }))}, true);
${statement};
commit;`;
}

function platformCommand(operationId, revision, flagKey, enabled) {
  return authenticated(platformActor, "authenticated", `select public.command_pachanga_organizer_billing_platform_v1(
    ${quote(operationId)}::uuid,
    '7b000000-0000-4000-8000-000000000099'::uuid,
    ${revision},
    'settings.flag',
    ${quote(JSON.stringify({ flagKey, enabled, reason: "Wave 7B concurrency gate" }))}::jsonb,
    '{"clientVersion":"7.1.0+concurrency","serviceWorkerVersion":"sw-wave7b","installedMode":"standalone","surface":"wave7b_concurrency"}'::jsonb
  )`);
}

function stripeEvent(deliveryOperationId, eventId) {
  return authenticated(platformActor, "service_role", `select public.ingest_pachanga_stripe_event_v1(
    ${quote(deliveryOperationId)}::uuid,
    'test', ${quote(eventId)}, 'customer.subscription.updated', '2026-06-30.basil',
    '2026-08-28T18:00:00Z'::timestamptz, repeat('a', 64),
    '{"objectType":"subscription","objectId":"sub_wave7b_concurrency","customerId":"cus_wave7b_concurrency","subscriptionId":"sub_wave7b_concurrency","priceId":"price_wave7b_concurrency","subscriptionStatus":"active","billingInterval":"month","currentPeriodStart":"2026-08-28T18:00:00Z","currentPeriodEnd":"2026-09-28T18:00:00Z","cancelAtPeriodEnd":false}'::jsonb,
    ${quote(`req-${deliveryOperationId}`)}
  )`);
}

function serviceCall(statement) {
  return authenticated(platformActor, "service_role", statement);
}

function concurrent(sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()],
      { cwd: root, env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.stdin.end(sql);
  });
}

function lastJson(result) {
  const line = result.stdout.split("\n").findLast((value) => value.trim().startsWith("{"));
  assert.ok(line, `${result.label} returned no JSON: ${JSON.stringify(result)}`);
  return JSON.parse(line);
}

function cleanup() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 7B database");
  if (exists === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 7B database");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()`, "terminate Wave 7B clients");
    admin(`drop database ${databaseName}`, "drop Wave 7B database");
  }
  rmSync(infrastructureDump, { force: true });
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 7B concurrency database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 7B infrastructure");
  query("create publication supabase_realtime;", "create Wave 7B Realtime publication");

  const migrationArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    migrationArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, migrationArgs, "bootstrap Wave 7B concurrency schema");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-c", "begin", "-f", resolve(root, "tests/organizer-plans-stripe-billing-v1-fixture.sql"),
    "-c", "commit"], "load Wave 7B fixture");

  query(`
    select set_config('pachangas.billing_settings_authority','wave7b-concurrency-fixture',false);
    select set_config('pachangas.billing_mapping_authority','wave7b-concurrency-fixture',false);
    update private.pachanga_organizer_billing_settings set
      foundation_enabled=true, plan_catalog_enabled=true, partner_grants_enabled=true,
      billing_accounts_enabled=true, organizer_ui_enabled=true, webhook_ingest_enabled=true,
      stripe_sandbox_enabled=true, portal_enabled=true, reconciliation_enabled=true,
      demo_world_v28_enabled=false, live_checkout_enabled=false, live_prices_approved=false,
      revision=1, updated_at=clock_timestamp()
    where singleton;
    insert into private.pachanga_organizer_plan_price_mappings(
      plan_revision_id, stripe_mode, billing_interval, stripe_product_id, stripe_price_id,
      currency, unit_amount, tax_behavior, approved, active
    ) values (
      '00000000-0000-0000-0000-00000000b713', 'test', 'month',
      'prod_wave7b_concurrency', 'price_wave7b_concurrency', 'eur', 1299,
      'unspecified', false, true
    );
    insert into private.pachanga_organizer_billing_accounts(
      id, organizer_kind, organizer_group_id, stripe_mode, stripe_customer_id,
      billing_contact_user_id, tax_configuration_status, current_plan_family, status
    ) values (
      ${quote(billingAccountId)}::uuid, 'TEAM', ${quote(teamId)}::uuid, 'test',
      'cus_wave7b_concurrency', '7b000000-0000-4000-8000-000000000001'::uuid,
      'TEST_READY', 'ORGANIZER', 'ready'
    );
    select set_config('pachangas.billing_settings_authority','',false);
    select set_config('pachangas.billing_mapping_authority','',false);
  `, "prepare Wave 7B concurrency state");

  const replayOperation = randomUUID();
  const initialRevision = Number(query(
    "select revision from private.pachanga_organizer_billing_settings where singleton",
    "read replay revision",
  ));
  const replayRace = await Promise.all([
    concurrent(platformCommand(replayOperation, initialRevision, "demo_world_v28_enabled", true), "same operation A"),
    concurrent(platformCommand(replayOperation, initialRevision, "demo_world_v28_enabled", true), "same operation B"),
  ]);
  assert.equal(replayRace.filter((result) => result.code === 0).length, 2, JSON.stringify(replayRace));
  assert.deepEqual(replayRace.map(lastJson).map((value) => value.replayed).sort(), [false, true]);
  assert.equal(Number(query(
    `select count(*) from private.pachanga_organizer_billing_operation_receipts_v1 where operation_id=${quote(replayOperation)}::uuid`,
    "count replay receipts",
  )), 1);

  const staleRevision = Number(query(
    "select revision from private.pachanga_organizer_billing_settings where singleton",
    "read stale-race revision",
  ));
  const staleRace = await Promise.all([
    concurrent(platformCommand(randomUUID(), staleRevision, "demo_world_v28_enabled", false), "stale operation A"),
    concurrent(platformCommand(randomUUID(), staleRevision, "demo_world_v28_enabled", true), "stale operation B"),
  ]);
  assert.equal(staleRace.filter((result) => result.code === 0).length, 1, JSON.stringify(staleRace));
  assert.equal(staleRace.filter((result) => /STALE_REVISION/.test(result.stderr)).length, 1, JSON.stringify(staleRace));

  const eventId = "evt_wave7b_concurrent_subscription";
  const deliveryA = randomUUID();
  const deliveryB = randomUUID();
  const webhookRace = await Promise.all([
    concurrent(stripeEvent(deliveryA, eventId), "Stripe delivery A"),
    concurrent(stripeEvent(deliveryB, eventId), "Stripe delivery B"),
  ]);
  assert.equal(webhookRace.filter((result) => result.code === 0).length, 2, JSON.stringify(webhookRace));
  assert.deepEqual(webhookRace.map(lastJson).map((value) => value.duplicate).sort(), [false, true]);
  assert.equal(query(`select concat_ws('|',
    (select count(*) from private.pachanga_stripe_webhook_events_v2 where stripe_event_id=${quote(eventId)}),
    (select count(*) from private.pachanga_stripe_webhook_deliveries_v1 where operation_id in (${quote(deliveryA)}::uuid,${quote(deliveryB)}::uuid)),
    (select count(*) from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7b_concurrency'),
    (select count(*) from private.pachanga_organizer_access_grants_v1 where subscription_projection_id is not null),
    (select count(*) from public.pachanga_competition_entitlement_grants where billing_subscription_projection_id is not null and status='active')
  )`, "read Stripe race effects"), "1|2|1|1|20");

  query(`
    update private.pachanga_stripe_subscription_projections_v1 set
      status='past_due', grace_ends_at=clock_timestamp()-interval '1 minute', revision=revision+1
    where stripe_subscription_id='sub_wave7b_concurrency';
    insert into private.pachanga_stripe_billing_reconciliations_v1(
      operation_id, billing_account_id, stripe_mode, reason, difference_codes, safe_error_code
    ) values
      (${quote(randomUUID())}::uuid, ${quote(billingAccountId)}::uuid, 'test', 'Wave 7B concurrent reconciliation A', array['REMOTE_DRIFT'], 'BILLING_REMOTE_DRIFT'),
      (${quote(randomUUID())}::uuid, ${quote(billingAccountId)}::uuid, 'test', 'Wave 7B concurrent reconciliation B', array['LOCAL_DRIFT'], 'BILLING_LOCAL_DRIFT');
  `, "prepare expiry and reconciliation races");

  const expiryRace = await Promise.all([
    concurrent(serviceCall(`select public.process_pachanga_billing_expirations_service_v1(${quote(randomUUID())}::uuid, 10)`), "expiry A"),
    concurrent(serviceCall(`select public.process_pachanga_billing_expirations_service_v1(${quote(randomUUID())}::uuid, 10)`), "expiry B"),
  ]);
  assert.equal(expiryRace.filter((result) => result.code === 0).length, 2, JSON.stringify(expiryRace));
  assert.equal(expiryRace.map(lastJson).reduce((sum, value) => sum + value.subscriptionsExpired, 0), 1);
  const followUpExpiry = JSON.parse(query(serviceCall(
    `select public.process_pachanga_billing_expirations_service_v1(${quote(randomUUID())}::uuid, 10)`,
  ), "verify expiry is not reapplied").split("\n").findLast((value) => value.startsWith("{")));
  assert.equal(followUpExpiry.subscriptionsExpired, 0, "An expired subscription must not be reprocessed by every cron run");
  assert.equal(query(`select concat_ws('|', status, revision) from private.pachanga_organizer_access_grants_v1
    where subscription_projection_id is not null`, "read expired access"), "revoked|2");

  const claimRace = await Promise.all([
    concurrent(serviceCall(`select public.claim_pachanga_billing_reconciliation_service_v1(${quote(randomUUID())}::uuid, 10)`), "reconciliation claim A"),
    concurrent(serviceCall(`select public.claim_pachanga_billing_reconciliation_service_v1(${quote(randomUUID())}::uuid, 10)`), "reconciliation claim B"),
  ]);
  assert.equal(claimRace.filter((result) => result.code === 0).length, 2, JSON.stringify(claimRace));
  assert.equal(claimRace.map(lastJson).reduce((sum, value) => sum + value.items.length, 0), 2);
  assert.equal(query("select count(*) from private.pachanga_stripe_billing_reconciliations_v1 where status='RUNNING'", "read claimed queue"), "2");

  completedSummary = {
    database: "ephemeral-local",
    sameOperationReplay: "PASS",
    staleRevisionRace: "PASS",
    duplicateStripeEvent: "PASS",
    expirationRace: "PASS",
    reconciliationRace: "PASS",
  };
} finally {
  cleanup();
}

process.stdout.write(`${JSON.stringify({ ...completedSummary, cleanup: "PASS" })}\n`);
