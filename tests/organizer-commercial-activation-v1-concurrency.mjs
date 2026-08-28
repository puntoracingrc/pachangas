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
const databaseName = `pachangas_wave7c_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7c-concurrency-${suffix}.sql`);
const platformOwner = "7b000000-0000-4000-8000-000000000003";
const originalOwner = "7b000000-0000-4000-8000-000000000001";
const nextOwner = "7b000000-0000-4000-8000-000000000005";
const teamId = "7b000000-0000-4000-8000-000000000010";
const testPriceId = "price_wave7c_test_team_month";
let summary;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("ORGANIZER_COMMERCIAL_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 196);
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

function query(sql, label = "query Wave 7C concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function authenticated(actorId, role, statement) {
  return `begin;
set local role ${role};
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role, sub: actorId }))}, true);
${statement};
commit;`;
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

function assertOneWinner(results, loserPattern = /STALE_REVISION|CONFLICT|NOT_WITHDRAWABLE/) {
  assert.equal(results.filter((result) => result.code === 0).length, 1, JSON.stringify(results));
  assert.equal(results.filter((result) => result.code !== 0 && loserPattern.test(result.stderr)).length, 1, JSON.stringify(results));
}

function commercialPayload(planCode) {
  const team = planCode === "TEAM_ORGANIZER_PRO";
  return {
    annualAmountMinor: team ? 9900 : 29000,
    billingIntervals: ["month", "year"],
    confirmLivePricing: "CONFIRM_STRIPE_LIVE_PRICING",
    currency: "EUR",
    effectiveFrom: "2026-09-01T00:00:00Z",
    monthlyAmountMinor: team ? 990 : 2900,
    privacyRevision: "terms-privacy-wave7c",
    reason: `Approve ${planCode} race decision`,
    stripeTaxBehavior: "inclusive",
    taxDisplayMode: "TAX_INCLUDED",
    termsRevision: "terms-commercial-wave7c",
  };
}

function commercialCommand(operationId, decisionId, revision, action, payload) {
  return authenticated(platformOwner, "authenticated", `select public.command_pachanga_organizer_commercial_decision_v1(
    ${quote(operationId)}::uuid, ${quote(decisionId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function prepareCatalog(operationId, decisionId, revision, reason) {
  return authenticated(platformOwner, "authenticated", `select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
    ${quote(operationId)}::uuid, ${quote(decisionId)}::uuid, ${revision}, 'live', ${quote(reason)},
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function confirmCatalog(operationId, suffixValue) {
  return service(`select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
    ${quote(operationId)}::uuid, ${quote(`prod_wave7c_live_race_${suffixValue}`)},
    ${quote(`price_wave7c_live_race_month_${suffixValue}`)},
    ${quote(`price_wave7c_live_race_year_${suffixValue}`)},
    'eur', 990, 9900, 'inclusive',
    '{"product_family":"organizer","plan_code":"TEAM_ORGANIZER_PRO","organizer_kind":"team","environment":"live","catalog_revision":"organizer-plan-v1"}'::jsonb,
    'organizer-plan-v1'
  )`);
}

function prepareCheckout(operationId, actorId, expectedRevision) {
  return service(`select public.prepare_pachanga_organizer_checkout_service_v1(
    ${quote(operationId)}::uuid, ${quote(actorId)}::uuid, 'TEAM', ${quote(teamId)}::uuid,
    'TEAM_ORGANIZER_PRO', 'month', 'test', ${expectedRevision},
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function transferOwner(actorId, targetOwnerId, operationId, expectedRevision) {
  return authenticated(actorId, "authenticated", `select public.transfer_pachanga_group_ownership_authoritative_v1(
    ${quote(teamId)}::uuid, ${quote(targetOwnerId)}::uuid, ${quote(operationId)}::uuid, ${expectedRevision},
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function preparePortal(operationId, actorId, expectedRevision) {
  return service(`select public.prepare_pachanga_organizer_portal_service_v1(
    ${quote(operationId)}::uuid, ${quote(actorId)}::uuid, 'TEAM', ${quote(teamId)}::uuid,
    'test', ${expectedRevision},
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function service(statement) {
  return authenticated(platformOwner, "service_role", statement);
}

function stripeSubscriptionEvent({ deliveryId, eventId, eventType, createdAt, status, customerId = "cus_wave7c_team", periodEnd = "2026-10-01T00:00:00Z" }) {
  const payload = {
    objectType: "subscription",
    objectId: "sub_wave7c_race",
    customerId,
    subscriptionId: "sub_wave7c_race",
    priceId: testPriceId,
    subscriptionStatus: status,
    billingInterval: "month",
    currentPeriodStart: "2026-08-01T00:00:00Z",
    currentPeriodEnd: periodEnd,
    cancelAtPeriodEnd: false,
    ...(status === "canceled" ? { canceledAt: createdAt } : {}),
  };
  return service(`select public.ingest_pachanga_stripe_event_v1(
    ${quote(deliveryId)}::uuid, 'test', ${quote(eventId)}, ${quote(eventType)}, '2026-06-30.basil',
    ${quote(createdAt)}::timestamptz, repeat('a',64), ${quote(JSON.stringify(payload))}::jsonb,
    ${quote(`req-${eventId}`)}
  )`);
}

function stripeInvoicePaidEvent({ deliveryId, eventId, createdAt }) {
  const payload = {
    objectType: "invoice",
    objectId: "in_wave7c_race",
    customerId: "cus_wave7c_team",
    subscriptionId: "sub_wave7c_race",
    subscriptionStatus: "active",
    invoiceId: "in_wave7c_race",
    invoiceStatus: "paid",
    currency: "eur",
    amountDue: "990",
    amountPaid: "990",
    paidAt: createdAt,
  };
  return service(`select public.ingest_pachanga_stripe_event_v1(
    ${quote(deliveryId)}::uuid, 'test', ${quote(eventId)}, 'invoice.paid', '2026-06-30.basil',
    ${quote(createdAt)}::timestamptz, repeat('b',64), ${quote(JSON.stringify(payload))}::jsonb,
    ${quote(`req-${eventId}`)}
  )`);
}

function createCompetition(operationId, actorId, expectedRevision, slug) {
  return authenticated(actorId, "authenticated", `select public.command_pachanga_competition_foundation_v1(
    ${quote(operationId)}::uuid, ${quote(teamId)}::uuid, ${expectedRevision}, 'competition.create',
    ${quote(JSON.stringify({ name: `Wave 7C ${slug}`, slug, competitionType: "LEAGUE", visibility: "private", reason: "Wave 7C concurrency" }))}::jsonb,
    '{"clientVersion":"7.3.0+concurrency","surface":"wave7c_concurrency"}'::jsonb
  )`);
}

function cleanup() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 7C database");
  if (exists === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 7C database");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()`, "terminate Wave 7C clients");
    admin(`drop database ${databaseName}`, "drop Wave 7C database");
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
  admin(`create database ${databaseName} template template0`, "create Wave 7C concurrency database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 7C infrastructure");
  query("create publication supabase_realtime;", "create Wave 7C Realtime publication");

  const migrationArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    migrationArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, migrationArgs, "bootstrap Wave 7C concurrency schema");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
    "-c", "begin",
    "-f", resolve(root, "tests/organizer-plans-stripe-billing-v1-fixture.sql"),
    "-f", resolve(root, "tests/organizer-commercial-activation-v1-db.sql"),
    "-c", "commit",
  ], "prepare canonical Wave 7C race state");

  const oldTeamDecision = query("select id from private.pachanga_organizer_commercial_decisions_v1 where plan_code='TEAM_ORGANIZER_PRO' and status='published'", "read published Team decision");
  const oldClubDecision = query("select id from private.pachanga_organizer_commercial_decisions_v1 where plan_code='CLUB_ORGANIZER' and status='published'", "read published Club decision");
  const teamDecision = randomUUID();
  const clubDecision = randomUUID();
  query(`
    select set_config('pachangas.billing_commercial_authority','wave7c-concurrency-fixture',false);
    insert into private.pachanga_organizer_commercial_decisions_v1(
      id, plan_code, organizer_kind, currency, monthly_amount_minor, annual_amount_minor,
      tax_display_mode, stripe_tax_behavior, trial_days, effective_from,
      public_copy_revision, terms_revision, privacy_revision, decision_kind, status,
      supersedes_id, revision, operation_id
    ) values
      (${quote(teamDecision)}::uuid,'TEAM_ORGANIZER_PRO','TEAM','EUR',990,9900,'TAX_INCLUDED','inclusive',0,
       '2026-09-01T00:00:00Z','pricing-wave7c','terms-commercial-wave7c','terms-privacy-wave7c','PROPOSED','pending_approval',${quote(oldTeamDecision)}::uuid,6,gen_random_uuid()),
      (${quote(clubDecision)}::uuid,'CLUB_ORGANIZER','CLUB','EUR',2900,29000,'TAX_INCLUDED','inclusive',0,
       '2026-09-01T00:00:00Z','pricing-wave7c','terms-commercial-wave7c','terms-privacy-wave7c','PROPOSED','pending_approval',${quote(oldClubDecision)}::uuid,6,gen_random_uuid());
  `, "insert pending commercial race decisions");

  const approvalRace = await Promise.all([
    concurrent(commercialCommand(randomUUID(), teamDecision, 6, "commercial_decision.approve", commercialPayload("TEAM_ORGANIZER_PRO")), "approval A"),
    concurrent(commercialCommand(randomUUID(), teamDecision, 6, "commercial_decision.approve", commercialPayload("TEAM_ORGANIZER_PRO")), "approval B"),
  ]);
  assertOneWinner(approvalRace);
  assert.equal(query(`select status||'|'||revision from private.pachanga_organizer_commercial_decisions_v1 where id=${quote(teamDecision)}::uuid`, "read approval race"), "approved|7");

  const approvalWithdrawalRace = await Promise.all([
    concurrent(commercialCommand(randomUUID(), clubDecision, 6, "commercial_decision.approve", commercialPayload("CLUB_ORGANIZER")), "approval vs withdrawal approval"),
    concurrent(commercialCommand(randomUUID(), clubDecision, 6, "commercial_decision.withdraw", { reason: "Withdraw competing commercial decision" }), "approval vs withdrawal withdrawal"),
  ]);
  assertOneWinner(approvalWithdrawalRace);
  assert.equal(query(`select status||'|'||revision from private.pachanga_organizer_commercial_decisions_v1 where id=${quote(clubDecision)}::uuid`, "read approval-withdrawal race"), "approved|7");

  query(`select set_config('pachangas.billing_settings_authority','wave7c-concurrency-fixture',false);
    update private.pachanga_organizer_billing_settings set
      organizer_terms_revision='terms-commercial-wave7c',
      organizer_privacy_revision='terms-privacy-wave7c',
      revision=revision+1, updated_at=clock_timestamp()
    where singleton`, "align canonical legal revisions for publication race");

  const catalogOperationA = randomUUID();
  const catalogOperationB = randomUUID();
  query(prepareCatalog(catalogOperationA, teamDecision, 7, "Prepare first concurrent live catalog"), "prepare live catalog A");
  query(prepareCatalog(catalogOperationB, teamDecision, 7, "Prepare second concurrent live catalog"), "prepare live catalog B");
  const catalogRace = await Promise.all([
    concurrent(confirmCatalog(catalogOperationA, "a"), "live catalog publication A"),
    concurrent(confirmCatalog(catalogOperationB, "b"), "live catalog publication B"),
  ]);
  assertOneWinner(catalogRace);
  assert.equal(query(`select status||'|'||revision from private.pachanga_organizer_commercial_decisions_v1 where id=${quote(teamDecision)}::uuid`, "read live publication race"), "published|8");
  assert.equal(query("select count(*) from private.pachanga_organizer_plan_price_mappings where stripe_mode='live' and plan_revision_id in (select revisions.id from public.pachanga_organizer_plan_revisions revisions join public.pachanga_organizer_plan_catalog plans on plans.id=revisions.plan_id where plans.plan_code='TEAM_ORGANIZER_PRO') and active", "count Team live mappings"), "2");

  const accountId = query(`select id from private.pachanga_organizer_billing_accounts where organizer_group_id=${quote(teamId)}::uuid and stripe_mode='test'`, "read TEST billing account");
  const accountRevisionBeforeCheckout = Number(query(`select revision from private.pachanga_organizer_billing_accounts where id=${quote(accountId)}::uuid`, "read checkout account revision"));
  const groupRevisionBeforeTransfer = Number(query(`select payload_revision from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read group revision"));
  const checkoutOperation = randomUUID();
  const ownerTransferRace = await Promise.all([
    concurrent(prepareCheckout(checkoutOperation, originalOwner, accountRevisionBeforeCheckout), "Checkout vs owner transfer Checkout"),
    concurrent(transferOwner(originalOwner, nextOwner, randomUUID(), groupRevisionBeforeTransfer), "Checkout vs owner transfer transfer"),
  ]);
  assert.ok(ownerTransferRace.some((result) => result.code === 0), JSON.stringify(ownerTransferRace));
  if (query(`select owner_id from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read owner after Checkout race") === originalOwner) {
    const confirmedGroupRevision = Number(query(`select payload_revision from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read confirmed group revision for transfer retry"));
    query(transferOwner(originalOwner, nextOwner, randomUUID(), confirmedGroupRevision), "converge owner after Checkout won race");
  }
  assert.equal(query(`select owner_id from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read transferred owner"), nextOwner);
  assert.equal(query(`select count(*) from private.pachanga_organizer_checkout_intents_v1 intents join private.pachanga_organizer_billing_accounts accounts on accounts.id=intents.billing_account_id where accounts.organizer_group_id=${quote(teamId)}::uuid and intents.actor_id=${quote(originalOwner)}::uuid and intents.status in ('PREPARED','SESSION_CREATED')`, "read stale owner checkout intents"), "0");

  query(stripeSubscriptionEvent({
    deliveryId: randomUUID(), eventId: "evt_wave7c_race_active_01",
    eventType: "customer.subscription.updated", createdAt: "2026-08-29T01:00:00Z", status: "active",
  }), "seed active subscription");
  const subscriptionRevision = Number(query("select revision from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race'", "read subscription revision"));
  const reconciliationId = randomUUID();
  query(`insert into private.pachanga_stripe_billing_reconciliations_v1(
    id, operation_id, billing_account_id, stripe_mode, reason, status, revision
  ) values (${quote(reconciliationId)}::uuid,gen_random_uuid(),${quote(accountId)}::uuid,'test','Wave 7C webhook race','RUNNING',1)`, "seed running reconciliation");
  const reconciliationRace = await Promise.all([
    concurrent(stripeSubscriptionEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_webhook_02",
      eventType: "customer.subscription.updated", createdAt: "2026-08-29T02:00:00Z", status: "past_due",
    }), "webhook vs reconciliation webhook"),
    concurrent(service(`select public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
      ${quote(randomUUID())}::uuid, ${quote(reconciliationId)}::uuid, 1,
      '2026-08-29T01:30:00Z'::timestamptz, 'cus_wave7c_team', 'sub_wave7c_race',
      ${quote(testPriceId)}, 'active', 'month', '2026-08-01T00:00:00Z'::timestamptz,
      '2026-10-01T00:00:00Z'::timestamptz, false, null, array['REMOTE_DRIFT'], ${subscriptionRevision}
    )`), "webhook vs reconciliation snapshot"),
  ]);
  assert.ok(reconciliationRace.some((result) => result.code === 0), JSON.stringify(reconciliationRace));
  assert.equal(query("select status||'|'||last_event_id from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race'", "read webhook-reconciliation winner"), "past_due|evt_wave7c_race_webhook_02");

  const cancellationInvoiceRace = await Promise.all([
    concurrent(stripeSubscriptionEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_cancel_04",
      eventType: "customer.subscription.deleted", createdAt: "2026-08-29T04:00:00Z", status: "canceled",
    }), "cancellation vs invoice cancellation"),
    concurrent(stripeInvoicePaidEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_invoice_03", createdAt: "2026-08-29T03:00:00Z",
    }), "cancellation vs invoice paid"),
  ]);
  assert.equal(cancellationInvoiceRace.filter((result) => result.code === 0).length, 2, JSON.stringify(cancellationInvoiceRace));
  assert.equal(query("select status||'|'||last_event_id from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race'", "read cancellation-invoice winner"), "canceled|evt_wave7c_race_cancel_04");

  query(stripeSubscriptionEvent({
    deliveryId: randomUUID(), eventId: "evt_wave7c_race_reactivate_05",
    eventType: "customer.subscription.updated", createdAt: "2026-08-29T05:00:00Z", status: "active",
  }), "reactivate for competition race");
  query("update private.pachanga_competition_foundation_settings set foundation_enabled=true,creation_enabled=true,context_binding_enabled=true,revision=revision+1 where singleton", "enable competition fixture flags");
  const organizerRevision = Number(query(`select coalesce((select revision from public.pachanga_competition_organizer_states where organizer_group_id=${quote(teamId)}::uuid),0)`, "read organizer revision"));
  const planCompetitionRace = await Promise.all([
    concurrent(stripeSubscriptionEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_plan_cancel_06",
      eventType: "customer.subscription.deleted", createdAt: "2026-08-29T06:00:00Z", status: "canceled",
      periodEnd: "2026-08-02T00:00:00Z",
    }), "plan change vs competition cancellation"),
    concurrent(createCompetition(randomUUID(), nextOwner, organizerRevision, `wave-7c-race-${suffix}`), "plan change vs competition creation"),
  ]);
  assert.ok(planCompetitionRace.some((result) => result.code === 0), JSON.stringify(planCompetitionRace));
  const planRaceFirstStatus = query("select status from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race'", "read plan race first winner");
  let planRaceReplay = null;
  if (planRaceFirstStatus !== "canceled") {
    planRaceReplay = query(stripeSubscriptionEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_plan_cancel_06",
      eventType: "customer.subscription.deleted", createdAt: "2026-08-29T06:00:00Z", status: "canceled",
      periodEnd: "2026-08-02T00:00:00Z",
    }), "replay cancellation after competition won race");
  }
  const planRaceProjection = query("select status||'|'||last_event_id||'|'||last_event_created_at from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race'", "read plan change projection");
  const planRaceEvent = query("select processing_status||'|'||coalesce(safe_error_code,'')||'|'||attempt_count from private.pachanga_stripe_webhook_events_v2 where stripe_mode='test' and stripe_event_id='evt_wave7c_race_plan_cancel_06'", "read plan change event");
  const planRaceDeliveries = query("select count(*) from private.pachanga_stripe_webhook_deliveries_v1 deliveries join private.pachanga_stripe_webhook_events_v2 events on events.id=deliveries.webhook_event_id where events.stripe_mode='test' and events.stripe_event_id='evt_wave7c_race_plan_cancel_06'", "read plan change deliveries");
  assert.match(planRaceProjection, /^canceled\|/, JSON.stringify({ planCompetitionRace, planRaceFirstStatus, planRaceReplay, planRaceProjection, planRaceEvent, planRaceDeliveries }));
  assert.equal(query(`select count(*) from public.pachanga_competition_entitlement_grants where organizer_group_id=${quote(teamId)}::uuid and capability in ('competition_create','tournament_create') and status='active'`, "read revoked creation entitlement"), "0");

  query(stripeSubscriptionEvent({
    deliveryId: randomUUID(), eventId: "evt_wave7c_race_reactivate_07",
    eventType: "customer.subscription.updated", createdAt: "2026-08-29T07:00:00Z", status: "active",
  }), "reactivate for Portal race");
  const accountRevisionBeforePortal = Number(query(`select revision from private.pachanga_organizer_billing_accounts where id=${quote(accountId)}::uuid`, "read Portal account revision"));
  const groupRevisionBeforeReturn = Number(query(`select payload_revision from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read return-transfer group revision"));
  const portalOperation = randomUUID();
  const portalRevocationRace = await Promise.all([
    concurrent(preparePortal(portalOperation, nextOwner, accountRevisionBeforePortal), "Portal vs owner revocation Portal"),
    concurrent(transferOwner(nextOwner, originalOwner, randomUUID(), groupRevisionBeforeReturn), "Portal vs owner revocation transfer"),
  ]);
  assert.ok(portalRevocationRace.some((result) => result.code === 0), JSON.stringify(portalRevocationRace));
  if (query(`select owner_id from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read owner after Portal race") === nextOwner) {
    const confirmedGroupRevision = Number(query(`select payload_revision from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read confirmed group revision for owner return"));
    query(transferOwner(nextOwner, originalOwner, randomUUID(), confirmedGroupRevision), "converge owner after Portal won race");
  }
  assert.equal(query(`select owner_id from public.pachanga_groups where id=${quote(teamId)}::uuid`, "read restored owner"), originalOwner);
  assert.equal(query(`select count(*) from private.pachanga_organizer_portal_intents_v1 intents join private.pachanga_organizer_billing_accounts accounts on accounts.id=intents.billing_account_id where accounts.organizer_group_id=${quote(teamId)}::uuid and intents.actor_id=${quote(nextOwner)}::uuid and intents.status in ('PREPARED','SESSION_CREATED')`, "read stale owner Portal intents"), "0");

  const continuityCompetition = randomUUID();
  const continuityEdition = randomUUID();
  query(`insert into public.pachanga_competitions(
      id,organizer_kind,organizer_group_id,name,slug,competition_type,visibility,status,created_by
    ) values (${quote(continuityCompetition)}::uuid,'TEAM',${quote(teamId)}::uuid,'Wave 7C Continuity','wave-7c-continuity-${suffix}','LEAGUE','private','draft',${quote(originalOwner)}::uuid);
    insert into public.pachanga_competition_editions(
      id,competition_id,name,season_label,starts_at,ends_at,status,created_by
    ) values (${quote(continuityEdition)}::uuid,${quote(continuityCompetition)}::uuid,'Wave 7C Active Edition','2026-27','2026-08-01','2026-12-31','active',${quote(originalOwner)}::uuid)`, "seed active edition continuity");
  assert.equal(query(`select count(*) from private.pachanga_competition_billing_continuity_grants_v1 where edition_id=${quote(continuityEdition)}::uuid and status='active'`, "read continuity snapshot"), "1");
  const expiryContinuityRace = await Promise.all([
    concurrent(stripeSubscriptionEvent({
      deliveryId: randomUUID(), eventId: "evt_wave7c_race_expire_08",
      eventType: "customer.subscription.deleted", createdAt: "2026-08-29T08:00:00Z", status: "canceled",
      periodEnd: "2026-08-02T00:00:00Z",
    }), "entitlement expiry vs continuity webhook"),
    concurrent(service(`select public.process_pachanga_billing_expirations_service_v1(${quote(randomUUID())}::uuid,10)`), "entitlement expiry vs continuity worker"),
  ]);
  assert.equal(expiryContinuityRace.filter((result) => result.code === 0).length, 2, JSON.stringify(expiryContinuityRace));
  assert.equal(query("select processing_status from private.pachanga_stripe_webhook_events_v2 where stripe_mode='test' and stripe_event_id='evt_wave7c_race_expire_08'", "read continuity event status"), "PROCESSED");
  assert.equal(query("select status from private.pachanga_organizer_access_grants_v1 where subscription_projection_id=(select id from private.pachanga_stripe_subscription_projections_v1 where stripe_subscription_id='sub_wave7c_race')", "read continuity access"), "continuity");
  assert.equal(query(`select count(*) from private.pachanga_competition_billing_continuity_grants_v1 where edition_id=${quote(continuityEdition)}::uuid and status='active'`, "read surviving continuity"), "1");

  summary = {
    approvalVsApproval: "PASS",
    approvalVsWithdrawal: "PASS",
    database: "ephemeral-local",
    entitlementExpiryVsContinuity: "PASS",
    livePricePublication: "PASS",
    ownerTransferVsCheckout: "PASS",
    planChangeVsCompetitionCreation: "PASS",
    portalVsOwnerRevocation: "PASS",
    webhookCancellationVsInvoicePaid: "PASS",
    webhookVsReconciliation: "PASS",
  };
} finally {
  cleanup();
}

process.stdout.write(`${JSON.stringify({ ...summary, cleanup: "PASS" })}\n`);
