import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const migrations = [
  "supabase/migrations/20260828163750_organizer_billing_accounts_plan_catalog_v1.sql",
  "supabase/migrations/20260828163751_stripe_event_ledger_projections_v1.sql",
  "supabase/migrations/20260828163752_organizer_billing_entitlement_continuity_v1.sql",
  "supabase/migrations/20260828163753_organizer_billing_commands_manual_grants_v1.sql",
  "supabase/migrations/20260828163754_organizer_billing_read_models_control_center_v2.sql",
  "supabase/migrations/20260828163755_organizer_billing_access_realtime_v1.sql",
  "supabase/migrations/20260828163756_organizer_billing_hardening_flags_v1.sql",
] as const;

function source(path: string) {
  return readFile(new URL(`../${path}`, import.meta.url), "utf8");
}

async function sqlSource() {
  return (await Promise.all(migrations.map(source))).join("\n");
}

test("Wave 7B owns seven forward migrations after production ledger 183", async () => {
  assert.equal(migrations.length, 7);
  const sql = await sqlSource();
  for (const marker of [
    "pachanga_organizer_plan_catalog",
    "pachanga_organizer_billing_accounts",
    "pachanga_stripe_webhook_events_v2",
    "pachanga_organizer_access_grants_v1",
    "pachanga_organizer_billing_operation_receipts_v1",
    "pachanga_organizer_billing_invalidations_v1",
  ]) assert.match(sql, new RegExp(marker));
  for (const migration of migrations) {
    const current = await source(migration);
    assert.match(current, /set lock_timeout = '5s'/);
    assert.match(current, /set statement_timeout = '5min'/);
  }
});

test("plan catalog installs without invented live Prices or enabled commerce", async () => {
  const [catalog, hardening] = await Promise.all([source(migrations[0]), source(migrations[6])]);
  assert.match(catalog, /'CLUB_PARTNER'/);
  assert.match(catalog, /'CLUB_ORGANIZER'/);
  assert.match(catalog, /'TEAM_ORGANIZER_PRO'/);
  assert.doesNotMatch(catalog, /insert into private\.pachanga_organizer_plan_price_mappings/i);
  assert.match(hardening, /live_checkout_enabled = false/);
  assert.match(hardening, /live_prices_approved = false/);
  assert.match(hardening, /tax_health = 'UNCONFIGURED'/);
});

test("browser Checkout sends intent only and cannot select Stripe mode or Price", async () => {
  const [shared, checkout] = await Promise.all([
    source("app/api/billing/organizer/_shared.ts"),
    source("app/api/billing/organizer/checkout/route.ts"),
  ]);
  assert.match(shared, /new Set\(\["billingInterval", "expectedRevision", "operationId", "organizerId", "organizerKind", "planCode"\]\)/);
  assert.doesNotMatch(shared, /new Set\([^\n]+(?:stripeMode|stripePriceId|customerId)/);
  assert.match(checkout, /organizerBillingMode\(\)/);
  assert.match(checkout, /prepare_pachanga_organizer_checkout_service_v1/);
  assert.match(checkout, /idempotencyKey: `\$\{input\.operationId\}:checkout`/);
  assert.match(checkout, /mode: "subscription"/);
  assert.doesNotMatch(checkout, /input\.(?:stripeMode|stripePriceId|stripeCustomerId)/);
});

test("Checkout redirect never grants access and signed webhook owns projection", async () => {
  const [commands, webhook] = await Promise.all([
    source(migrations[3]),
    source("app/api/webhooks/stripe/route.ts"),
  ]);
  assert.match(commands, /Checkout success webhook must remain non-authoritative|checkout\.session\.completed/);
  assert.match(commands, /perform private\.pachanga_billing_sync_entitlement_v1\(subscription\.id/);
  assert.match(webhook, /await request\.text\(\)/);
  assert.match(webhook, /webhooks\.constructEvent/);
  assert.match(webhook, /stripeEventMode\(verified\) !== candidate\.mode/);
  assert.match(webhook, /ingest_pachanga_stripe_event_v1/);
  assert.doesNotMatch(webhook, /await request\.json\(\)/);
});

test("reconciliation is service-only, revisioned and cannot beat a concurrent webhook", async () => {
  const [sql, route] = await Promise.all([
    source(migrations[4]),
    source("app/api/internal/billing/reconcile/route.ts"),
  ]);
  assert.match(sql, /localProjectionRevision/);
  assert.match(sql, /expected_projection_revision bigint default 0/);
  assert.match(sql, /coalesce\(subscription\.revision, 0\) <> expected_projection_revision/);
  assert.match(sql, /subscription\.last_event_created_at >= observed_at/);
  assert.match(sql, /projection_source = 'STRIPE_RECONCILIATION'/);
  assert.match(sql, /grant execute on function public\.apply_pachanga_billing_reconciliation_snapshot_service_v1[^;]+ to service_role/);
  assert.doesNotMatch(sql, /grant execute on function public\.apply_pachanga_billing_reconciliation_snapshot_service_v1[^;]+ to authenticated/);
  assert.match(route, /CRON_SECRET/);
  assert.match(route, /process_pachanga_billing_expirations_service_v1/);
  assert.match(route, /subscriptions\.retrieve/);
  assert.match(route, /organizerSubscriptionDifferenceCodes/);
  assert.match(route, /apply_pachanga_billing_reconciliation_snapshot_service_v1/);
  assert.doesNotMatch(route, /\.from\(/);
});

test("owner and platform read models keep full Stripe identities private", async () => {
  const sql = await source(migrations[4]);
  assert.match(sql, /pachanga_billing_redact_stripe_id_v1/);
  assert.match(sql, /get_my_pachanga_billing_organizers_v1/);
  assert.match(sql, /private\.pachanga_billing_owner_can_manage_v1/);
  assert.doesNotMatch(sql, /'stripeCustomerId'\s*,\s*billing_accounts\.stripe_customer_id/);
  assert.doesNotMatch(sql, /'stripePriceId'\s*,\s*subscriptions\.stripe_price_id/);
});

test("all organizer browser mutations stay behind the permanent PWA write gate", () => {
  for (const operation of [
    "api:organizer-billing-checkout",
    "api:organizer-billing-portal",
    "api:platform-admin-billing",
  ]) assert.equal(isKnownClientWriteOperation(operation), true, operation);
});

test("Realtime is invalidation-only and clients must refetch canonical read models", async () => {
  const realtime = await source(migrations[5]);
  assert.match(realtime, /pachanga_organizer_billing_invalidations_v1/);
  assert.match(realtime, /replica identity full/i);
  for (const entityKind of ["BILLING_ACCOUNT", "ACCESS_GRANT", "SUBSCRIPTION", "RECONCILIATION"]) {
    assert.match(realtime, new RegExp(`'${entityKind}'`));
  }
  assert.doesNotMatch(realtime, /payload\.new|last-write-wins|offlineQueue/i);
});

test("Vercel invokes canonical billing reconciliation hourly", async () => {
  const vercel = JSON.parse(await source("vercel.json")) as { crons?: Array<{ path: string; schedule: string }> };
  assert.deepEqual(vercel.crons?.find((entry) => entry.path === "/api/internal/billing/reconcile"), {
    path: "/api/internal/billing/reconcile",
    schedule: "17 * * * *",
  });
});
