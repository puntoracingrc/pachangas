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
  assert.match(checkout, /customer_update: \{ address: "auto", name: "auto" \}/);
  assert.match(checkout, /tax_id_collection: \{ enabled: true \}/);
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
  const [sql, route, platformRoute] = await Promise.all([
    source(migrations[4]),
    source("app/api/internal/billing/reconcile/route.ts"),
    source("app/api/platform-admin/billing/route.ts"),
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
  assert.match(platformRoute, /action === "reconciliation\.request"/);
  assert.match(platformRoute, /request_pachanga_billing_reconciliation_platform_v1/);
  assert.match(platformRoute, /billing_account_id: aggregateId/);
  assert.doesNotMatch(platformRoute, /commandPayload\("reconciliation\.request"/);
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

test("public plans cache only canonical GET data and never invent a checkout", async () => {
  const [client, serviceWorker, home] = await Promise.all([
    source("app/_components/organizer-plans-client.tsx"),
    source("app/service-worker-source.ts"),
    source("app/page.tsx"),
  ]);
  assert.match(client, /fetch\("\/api\/billing\/organizer\/catalog", \{ cache: "no-store" \}\)/);
  assert.match(client, /storeCatalogCache\(canonical\)/);
  assert.match(client, /Precio pendiente de publicacion/);
  assert.match(client, /checkoutAvailable/);
  assert.match(client, /Solicitar acceso/);
  assert.match(client, /No incluidas/);
  assert.match(client, /Impuestos incluidos/);
  assert.doesNotMatch(client, /clientWriteFetch|method:\s*"POST"|offlineQueue/i);
  assert.match(serviceWorker, /"\/planes-organizador"/);
  assert.doesNotMatch(serviceWorker, /"\/ajustes\/facturacion"/);
  assert.match(home, /href="\/planes-organizador"/);
  assert.match(home, /currentRole === "owner" \? <(?:a|Link)[^>]+href="\/ajustes\/facturacion"/);
});

test("owner billing treats local state as read-only and refetches after invalidation", async () => {
  const client = await source("app/_components/organizer-billing-client.tsx");
  assert.match(client, /Copia guardada, solo lectura/);
  assert.match(client, /const actionDisabled = busy \|\| fromCache \|\| !online/);
  assert.match(client, /las operaciones de facturacion no se guardan ni se ponen en cola/);
  assert.match(client, /clientWriteFetch\(`api:organizer-billing-\$\{kind\}`/);
  assert.match(client, /operationFor\(pending, key\)/);
  assert.match(client, /pachanga_organizer_billing_invalidations_v1/);
  assert.match(client, /loadSnapshot\(selected, token, false\)/);
  assert.match(client, /canonical\.entitlementActive/);
  assert.match(client, /El retorno de Stripe no concede acceso/);
  assert.doesNotMatch(client, /\.rpc\(|service_role|offlineQueue/i);
});

test("Control Center keeps live approval and reconciliation on dedicated platform commands", async () => {
  const [client, route] = await Promise.all([
    source("app/admin/billing/organizer-billing-admin-client.tsx"),
    source("app/api/platform-admin/billing/route.ts"),
  ]);
  assert.match(client, /commercial_decision\.approve/);
  assert.match(client, /disabled=\{!canApproveLive[^\n]+decisionStatus !== "pending_approval"/);
  assert.match(client, /stripe_catalog\.provision/);
  assert.match(client, /disabled=\{!canApproveLive[^\n]+decisionStatus !== "approved"[^\n]+LIVE_READY/);
  assert.match(client, /live_checkout\.activate/);
  assert.match(client, /disabled=\{!canApproveLive[^\n]+!liveGateReady[^\n]+!liveConfirmation/);
  assert.match(client, /reconciliation\.request/);
  assert.match(client, /manual\.grant/);
  assert.match(client, /manual\.revoke/);
  assert.match(client, /manual\.renew/);
  assert.match(route, /request_pachanga_billing_reconciliation_platform_v1/);
  assert.match(route, /command_pachanga_organizer_commercial_decision_v1/);
  assert.match(route, /activate_pachanga_organizer_live_checkout_platform_v1/);
  assert.match(route, /command_pachanga_organizer_billing_platform_v1/);
  assert.doesNotMatch(client, /service_role|stripeCustomerId|stripeSubscriptionId/);
});
