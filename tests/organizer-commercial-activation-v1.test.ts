import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const migrations = [
  "20260828205310_organizer_commercial_decisions_v1.sql",
  "20260828205311_organizer_commercial_commands_v1.sql",
  "20260828205313_organizer_stripe_catalog_authority_v1.sql",
  "20260828205314_organizer_checkout_portal_activation_gates_v1.sql",
  "20260828205316_organizer_commercial_read_models_v1.sql",
  "20260828205317_organizer_commercial_hardening_flags_v1.sql",
] as const;

async function source(path: string) {
  return readFile(resolve(root, path), "utf8");
}

test("Wave 7C installs six additive migrations with all commercial flags off", async () => {
  const sql = (await Promise.all(migrations.map((name) => source(`supabase/migrations/${name}`)))).join("\n");
  assert.match(sql, /commercial_decision_workflow_enabled boolean not null default false/);
  assert.match(sql, /stripe_test_checkout_enabled boolean not null default false/);
  assert.match(sql, /demo_world_v29_enabled boolean not null default false/);
  assert.match(sql, /WAVE7C_FLAGS_MUST_START_DISABLED/);
  assert.doesNotMatch(sql, /insert into private\.pachanga_organizer_plan_price_mappings[\s\S]*prod_[A-Za-z0-9]/i);
});

test("commercial approval is platform-owned, revisioned and exact", async () => {
  const sql = await source(`supabase/migrations/${migrations[1]}`);
  assert.match(sql, /pachanga_billing_require_platform_owner_v1/);
  assert.match(sql, /CONFIRM_STRIPE_LIVE_PRICING/);
  assert.match(sql, /\["month", "year"\]/);
  assert.match(sql, /BILLING_COMMERCIAL_APPROVAL_MISMATCH/);
  assert.match(sql, /BILLING_OPERATION_ID_REUSED/);
  assert.match(sql, /STALE_REVISION/);
});

test("legacy writes cannot bypass catalog readback or live activation", async () => {
  const gates = await source(`supabase/migrations/${migrations[3]}`);
  assert.match(gates, /BILLING_STRIPE_CATALOG_AUTHORITY_REQUIRED/);
  assert.match(gates, /BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED/);
  assert.match(gates, /BILLING_LIVE_ACTIVATION_GATE_INCOMPLETE/);
  assert.match(gates, /CONFIRM_ORGANIZER_LIVE_CHECKOUT/);
  assert.match(gates, /emergency_disable_only/);
});

test("public and owner read models redact Stripe authority and separate modes", async () => {
  const reads = await source(`supabase/migrations/${migrations[4]}`);
  assert.match(reads, /base ->> 'status' = 'NOT_AVAILABLE'/);
  assert.match(reads, /decisions\.status = 'published'/);
  assert.match(reads, /pachanga_billing_redact_stripe_id_v1/);
  assert.match(reads, /'sandboxCheckout', settings\.stripe_test_checkout_enabled/);
  assert.match(reads, /'liveCheckout', settings\.live_checkout_enabled/);
  assert.doesNotMatch(reads, /'stripeProductId'/);
});

test("public Organizer catalog uses the anonymous canonical RPC without service role", async () => {
  const [route, shared, reads] = await Promise.all([
    source("app/api/billing/organizer/catalog/route.ts"),
    source("app/api/billing/_shared.ts"),
    source(`supabase/migrations/${migrations[4]}`),
  ]);
  assert.match(route, /publicSupabaseClient\(\)\.rpc\("get_pachanga_organizer_plan_catalog_v1"\)/);
  assert.doesNotMatch(route, /billingServiceClient|SUPABASE_SERVICE_ROLE_KEY|service_role/);
  assert.match(shared, /publicSupabaseClient[\s\S]*NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.match(reads, /grant execute on function public\.get_pachanga_organizer_plan_catalog_v1\(\) to anon, authenticated, service_role/);
});

test("Organizer webhook remains distinct from Stripe V1", async () => {
  const [organizer, legacy] = await Promise.all([
    source("app/api/webhooks/stripe/route.ts"),
    source("app/api/stripe/webhook/route.ts"),
  ]);
  assert.match(organizer, /organizerWebhookSecrets\(\)/);
  assert.match(organizer, /verifiedMode/);
  assert.match(organizer, /ingest_pachanga_stripe_event_v1/);
  assert.match(legacy, /STRIPE_WEBHOOK_SECRET/);
  assert.doesNotMatch(legacy, /organizerWebhookSecrets/);
});

test("Organizer TEST accepts restricted server keys without weakening LIVE or public-key checks", async () => {
  const shared = await source("app/api/billing/organizer/_shared.ts");
  assert.match(shared, /mode === "live" \? \["sk_live_"\] : \["sk_test_", "rk_test_"\]/);
  assert.match(shared, /expectedPrefixes\.some\(\(prefix\) => value\.startsWith\(prefix\)\)/);
  assert.doesNotMatch(shared, /"pk_test_"|"pk_live_"|"rk_live_"/);
});

test("Stripe catalog provisioning resumes exact resources without duplicate creation", async () => {
  const adapter = await source("app/api/billing/organizer/_stripe-commercial.ts");
  assert.match(adapter, /stripe\.products\.list\(\{ active: true, limit: 100 \}\)/);
  assert.match(adapter, /stripe\.prices\.list\(\{ active: true, limit: 100, product: productId, type: "recurring" \}\)/);
  assert.match(adapter, /matchingCatalogProduct/);
  assert.match(adapter, /matchingCatalogPrice/);
  assert.match(adapter, /BILLING_STRIPE_CATALOG_DUPLICATE_PRODUCT/);
  assert.match(adapter, /BILLING_STRIPE_CATALOG_DUPLICATE_PRICE/);
  assert.match(adapter, /BILLING_STRIPE_CATALOG_READBACK_MISMATCH/);
});

test("owner billing actions keep TEST and LIVE Portal authority separate", async () => {
  const client = await source("app/_components/organizer-billing-client.tsx");
  assert.match(client, /mode === "test" \? organizerBillingBoolean\(availability\.sandboxPortal\) : organizerBillingBoolean\(availability\.livePortal\)/);
  assert.doesNotMatch(client, /organizerBillingBoolean\(availability\.portal\)/);
});

test("public pricing derives annual savings from the canonical monthly and yearly prices", async () => {
  const client = await source("app/_components/organizer-plans-client.tsx");
  assert.match(client, /Number\(monthly\.unitAmount\) \* 12 - Number\(annual\.unitAmount\)/);
  assert.match(client, /Ahorro anual/);
  assert.doesNotMatch(client, /9[,.]90|29[,.]00|99[,.]00|290[,.]00/);
});

test("team owner transfer expires the previous owner's billing intents", async () => {
  const hardening = await source(`supabase/migrations/${migrations[5]}`);
  assert.match(hardening, /after update of owner_id on public\.pachanga_groups/);
  assert.match(hardening, /intents\.actor_id = old\.owner_id/);
  assert.match(hardening, /billing_contact_user_id = new\.owner_id/);
  assert.match(hardening, /pachanga_billing_revalidate_intent_owner_v1/);
  assert.match(hardening, /before insert on private\.pachanga_organizer_checkout_intents_v1/);
  assert.match(hardening, /before insert on private\.pachanga_organizer_portal_intents_v1/);
  assert.match(hardening, /BILLING_OWNER_REQUIRED/);
  assert.match(hardening, /old\.status = 'EXPIRED' and new\.status = 'WEBHOOK_CONFIRMED'/);
});
