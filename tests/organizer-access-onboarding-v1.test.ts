import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {
  organizerAccessActions,
  organizerAccessCacheKey,
  organizerAccessPlatformActions,
} from "../app/organizer-access-contract";
import { knownClientWriteRpcNames } from "../app/pwa-write-classifier";

const root = process.cwd();
const migrationNames = [
  "20260829152223_organizer_access_applications_revisions_v1.sql",
  "20260829152228_organizer_access_review_decisions_messages_v1.sql",
  "20260829152232_organizer_access_entitlement_bridge_authority_v1.sql",
  "20260829152237_organizer_guided_onboarding_workspace_v1.sql",
  "20260829152241_organizer_access_read_models_control_center_v1.sql",
  "20260829152246_organizer_access_rls_realtime_notifications_v1.sql",
  "20260829152250_organizer_access_hardening_indexes_flags_v1.sql",
] as const;

async function source(relativePath: string) {
  return readFile(path.join(root, relativePath), "utf8");
}

async function migrationSource(index: number) {
  return source(`supabase/migrations/${migrationNames[index]}`);
}

test("Wave 8A consists of exactly seven forward-only migrations after ledger 197", async () => {
  const actual = (await readdir(path.join(root, "supabase/migrations")))
    .filter((name) => name >= "20260829152223" && /organizer_(?:access|guided)/.test(name))
    .sort();
  assert.deepEqual(actual, [...migrationNames]);
  assert.equal(actual.length, 7);
  assert.ok(actual.every((name) => /^202608291522\d{2}_.+\.sql$/.test(name)));
});

test("applications are private revisioned aggregates with one active organizer-plan application", async () => {
  const sql = await migrationSource(0);
  assert.match(sql, /create table private\.pachanga_organizer_access_applications_v1/);
  assert.match(sql, /create table private\.pachanga_organizer_access_application_revisions_v1/);
  assert.match(sql, /status text not null default 'draft'/);
  assert.match(sql, /server_sequence bigint not null/);
  assert.match(sql, /where\s+status\s+in\s*\(\s*'draft',\s*'submitted',\s*'under_review',\s*'needs_information'\s*\)/s);
  assert.match(sql, /unique \(application_id, version\)/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete) on table private\.pachanga_organizer_access/i);
});

test("review decisions, private notes, receipts and events are immutable server authority", async () => {
  const sql = `${await migrationSource(0)}\n${await migrationSource(1)}`;
  for (const table of [
    "pachanga_organizer_access_messages_v1",
    "pachanga_organizer_access_decisions_v1",
    "pachanga_organizer_access_operation_receipts_v1",
    "pachanga_organizer_access_events_v1",
  ]) assert.match(sql, new RegExp(`create table private\\.${table}`));
  assert.match(sql, /check \(visibility in \('APPLICANT_SHARED', 'PLATFORM_PRIVATE'\)\)/);
  assert.match(sql, /operation_id uuid not null unique/);
  assert.match(sql, /server_sequence bigint not null/);
});

test("approval bridges to the existing entitlement grant and never manufactures subscriptions", async () => {
  const sql = `${await migrationSource(2)}\n${await migrationSource(4)}`;
  assert.match(sql, /pachanga_competition_entitlement_grants/);
  assert.match(sql, /billing_access_grant_id/);
  assert.match(sql, /'PARTNERSHIP','PROMOTION','PRIVATE_BETA','PLATFORM_GRANT'/);
  assert.match(sql, /when 'PARTNERSHIP' then 'partnership'/);
  assert.match(sql, /when 'SUBSCRIPTION' then 'PAID_PLAN_INTEREST'/);
  assert.match(sql, /ORGANIZER_ACCESS_GRANT_SOURCE_INVALID/);
  assert.doesNotMatch(sql, /insert into private\.pachanga_organizer_subscriptions_v1/i);
});

test("RBAC separates platform review, approval, support and finance", async () => {
  const sql = await migrationSource(2);
  assert.match(sql, /when 'platform_owner' then jsonb_build_array/);
  assert.match(sql, /when 'support' then jsonb_build_array\([\s\S]*?'organizer_access\.support'[\s\S]*?\)/);
  assert.match(sql, /when 'finance' then jsonb_build_array\([\s\S]*?'billing\.read'[\s\S]*?\)/);
  const supportBlock = sql.match(/when 'support'[\s\S]*?when 'finance'/)?.[0] ?? "";
  const financeBlock = sql.match(/when 'finance'[\s\S]*?when 'ops'/)?.[0] ?? "";
  assert.doesNotMatch(supportBlock, /organizer_access\.approve/);
  assert.doesNotMatch(financeBlock, /organizer_access\.approve/);
});

test("the command envelope is allowlisted and rejects client-authored authority", async () => {
  assert.deepEqual(organizerAccessActions, [
    "application.create", "application.update", "application.submit", "application.withdraw",
    "application.respond_information", "application.reconsider", "onboarding.refresh", "competition.launch",
  ]);
  assert.deepEqual(organizerAccessPlatformActions, [
    "review.start", "review.request_information", "review.approve", "review.reject", "review.expire",
    "settings.flags", "rate_limit.override",
  ]);
  const shared = await source("app/api/organizer-access/_shared.ts");
  assert.match(shared, /const serverFields = new Set\(\[/);
  for (const field of ["accessGrantId", "actorId", "assignedReviewer", "confirmedRevision", "serverSequence"]) {
    assert.match(shared, new RegExp(`"${field}"`));
  }
  assert.match(shared, /Object\.keys\(raw\)\.some\(\(key\) => !allowed\.has\(key\) \|\| serverFields\.has\(key\)\)/);
  assert.match(shared, /count < 2 \|\| count > 10_000/);
  assert.match(shared, /payload\.organizerKind = kind/);
  assert.match(shared, /payload\.planCode = planCode/);
  assert.match(shared, /ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED/);
  assert.match(shared, /ORGANIZER_ACCESS_SERVER_FIELDS_FORBIDDEN/);
});

test("the canonical command enforces idempotency, revisions, lifecycle and rate limits", async () => {
  const sql = await migrationSource(4);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\(operation_id::text/);
  assert.match(sql, /pachanga_organizer_access_replay_v1/);
  assert.match(sql, /if application\.revision <> expected_revision then raise exception 'STALE_REVISION'/);
  assert.match(sql, /status <> 'draft'.*ORGANIZER_ACCESS_APPLICATION_NOT_SUBMITTABLE/s);
  assert.match(sql, /status not in \('draft','submitted','under_review','needs_information'\).*NOT_WITHDRAWABLE/s);
  assert.match(sql, /requested_access_mode = 'PARTNERSHIP_REVIEW'/);
  assert.match(sql, /status = 'approved_interest'/);
  assert.match(sql, /grantCreated', false/);
  assert.match(sql, /pachanga_organizer_access_rate_limit_v1/);
});

test("guided onboarding derives one next action and hands off to existing League or Tournament engines", async () => {
  const [workspaceSql, commandSql] = await Promise.all([migrationSource(3), migrationSource(4)]);
  for (const action of [
    "COMPLETE_ORGANIZER_PROFILE", "CREATE_FIRST_COMPETITION", "CONTINUE_COMPETITION_DRAFT",
    "INVITE_TEAMS", "CONFIGURE_RULES", "GENERATE_SCHEDULE", "PREPARE_DRAW",
    "PUBLISH_COMPETITION", "PREPARE_FIRST_MATCH", "ONBOARDING_COMPLETE",
  ]) assert.match(workspaceSql, new RegExp(action));
  assert.match(commandSql, /command_pachanga_league_private_beta_v2/);
  assert.match(commandSql, /command_pachanga_tournament_draw_v1/);
  assert.match(commandSql, /FIRST_COMPETITION_ALREADY_LAUNCHED/);
  assert.match(commandSql, /pachanga_organizer_billing_creation_allowed_v1/);
});

test("applicant reads redact platform-private fields while Control Center keeps audited review data", async () => {
  const [sql, admin] = await Promise.all([
    migrationSource(4),
    source("app/admin/organizer-access/organizer-access-admin-client.tsx"),
  ]);
  assert.match(sql, /'assignedReviewer', case when include_platform_private then application\.assigned_reviewer end/);
  assert.match(sql, /messages\.visibility = 'APPLICANT_SHARED'/);
  assert.match(sql, /privateNote/);
  assert.match(sql, /get_pachanga_platform_organizer_access_v1/);
  assert.match(sql, /get_pachanga_organizer_access_health_v1/);
  for (const count of ["rejected", "expired", "withdrawn"]) assert.match(sql, new RegExp(`'${count}', \\(select count\\(\\*\\)`));
  assert.match(admin, /Actualizada desde/);
  assert.match(admin, /Actualizada hasta/);
  assert.match(admin, /Owner actual/);
  assert.match(admin, /solicitudes relacionadas/);
  assert.match(admin, /Salud de la cola/);
});

test("Realtime is invalidation-only, readable by participants and drives canonical refetch", async () => {
  const [sql, client] = await Promise.all([
    migrationSource(5),
    source("app/_components/organizer-access-client.tsx"),
  ]);
  assert.match(sql, /create table public\.pachanga_organizer_access_invalidations_v1/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /create policy "Organizer access participants read invalidations"/);
  assert.match(sql, /alter publication supabase_realtime add table public\.pachanga_organizer_access_invalidations_v1/);
  assert.match(client, /table: organizerAccessRealtimeTable/);
  assert.match(client, /if \(state === "SUBSCRIBED"\) reconcile\(\)/);
  assert.match(client, /void loadHome\(token, userId\)/);
  assert.doesNotMatch(client, /payload\.new/);
});

test("all organizer access lifecycle notifications are mandatory, semantic and idempotent", async () => {
  const [sql, expiryRoute, reconcileRoute] = await Promise.all([
    migrationSource(5),
    source("app/api/internal/billing/expire/route.ts"),
    source("app/api/internal/billing/reconcile/route.ts"),
  ]);
  for (const action of [
    "application.submit", "review.start", "review.request_information",
    "application.respond_information", "review.approve", "review.reject",
    "access.granted", "onboarding.available", "competition.launch",
    "onboarding.completed", "access.expiry_notification",
  ]) assert.match(sql, new RegExp(action.replace(".", "\\.")));
  assert.match(sql, /organizer_access_warning/);
  assert.match(sql, /process_pachanga_organizer_access_expiry_notifications_v1/);
  assert.match(sql, /coalesce\(\(select auth\.role\(\)\), ''\) <> 'service_role'/);
  assert.match(sql, /grants\.valid_until <= clock_timestamp\(\) \+ interval '7 days'/);
  assert.match(sql, /where notifications\.dedupe_key = dedupe_key_value/);
  assert.match(sql, /for update of grants skip locked/);
  assert.match(expiryRoute, /process_pachanga_organizer_access_expiry_notifications_v1/);
  assert.match(reconcileRoute, /process_pachanga_organizer_access_expiry_notifications_v1/);
  assert.doesNotMatch(`${expiryRoute}\n${reconcileRoute}`, /NEXT_PUBLIC/);
});

test("PWA caches read models but blocks offline writes and never reports fake success", async () => {
  const [client, worker] = await Promise.all([
    source("app/_components/organizer-access-client.tsx"),
    source("app/service-worker-source.ts"),
  ]);
  assert.equal(organizerAccessCacheKey("actor"), "pachangas-organizer-access-v1:actor");
  assert.match(client, /localStorage\.setItem\(organizerAccessCacheKey/);
  assert.match(client, /This cache is optional and never authorizes a write/);
  assert.match(client, /!online \|\| cached/);
  assert.match(client, /Sin conexión: puedes consultar la copia local, pero no se guardan operaciones deportivas ni permisos/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /Cambio confirmado por el servidor/);
  assert.match(client, /clientWriteFetch\("api:organizer-access-command"/);
  assert.match(worker, /"\/organizacion\/empezar"/);
  assert.match(worker, /"\/organizacion\/onboarding"/);
  assert.match(worker, /"\/organizacion\/solicitar-acceso"/);
});

test("API routes are authenticated, no-store, origin-checked and service-role-free", async () => {
  const routeSources = await Promise.all([
    source("app/api/organizer-access/_shared.ts"),
    source("app/api/organizer-access/command/route.ts"),
    source("app/api/organizer-access/me/route.ts"),
    source("app/api/organizer-access/application/[applicationId]/route.ts"),
    source("app/api/platform-admin/organizer-access/route.ts"),
  ]);
  const combined = routeSources.join("\n");
  assert.match(combined, /noStoreHeaders/);
  assert.match(combined, /requireOrganizerAccessOrigin\(request\)/);
  assert.match(combined, /clientWriteGateResponse|organizerAccessWriteGate/);
  assert.match(combined, /command_pachanga_organizer_access_application_v1/);
  assert.match(combined, /get_my_pachanga_organizer_access_v1/);
  assert.match(combined, /get_pachanga_organizer_access_application_v1/);
  assert.doesNotMatch(combined, /SUPABASE_SERVICE_ROLE_KEY|service_role/);
});

test("Plans, navigation and PWA write classification expose organizer access without enabling Checkout", async () => {
  const [plans, shell, home] = await Promise.all([
    source("app/_components/organizer-plans-client.tsx"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/page.tsx"),
  ]);
  assert.match(plans, /Solicitar colaboración/);
  assert.match(plans, /Solicitar acceso/);
  assert.match(plans, /\/organizacion\/solicitar-acceso\?plan=/);
  assert.match(shell, /Organizar/);
  assert.match(shell, /\/organizacion\/solicitudes/);
  assert.match(home, /<Link href="\/organizacion\/solicitudes">Organizar<\/Link>/);
  assert.ok(knownClientWriteRpcNames().includes("command_pachanga_organizer_access_application_v1"));
});

test("Wave 8A leaves all Stripe and live-commerce activation outside its migrations", async () => {
  const sql = (await Promise.all(migrationNames.map((_, index) => migrationSource(index)))).join("\n");
  assert.doesNotMatch(sql, /stripe\.(?:com|checkout)|create checkout|checkout\.sessions|portal\.sessions/i);
  assert.doesNotMatch(sql, /live_checkout_enabled\s*=\s*true|live_prices_approved\s*=\s*true|portal_enabled\s*=\s*true/i);
  assert.doesNotMatch(sql, /insert into private\.pachanga_organizer_plan_price_mappings/i);
});

test("Demo World verification separates volatile raw hashes from deterministic projections", async () => {
  const simulation = await source("scripts/demo-world/simulate-demo-world-v2.ts");
  assert.match(simulation, /function projectionHash/);
  assert.match(simulation, /authorityProjectionHash: projectionHash\(authorityProof\)/);
  assert.match(simulation, /snapshotProjectionHash: projectionHash\(generated\)/);
  assert.match(simulation, /demoWorldVerificationProjection\(authorityProof\)/);
  assert.match(simulation, /demoWorldVerificationProjection\(generated\)/);
});
