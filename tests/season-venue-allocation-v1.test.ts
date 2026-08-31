import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("Wave 9B exposes the complete role-aware product surface", async () => {
  const [client, navigation, css] = await Promise.all([
    source("app/_components/season-venue-planner-client.tsx"),
    source("app/_components/product-navigation-contract.ts"),
    source("app/_components/season-venue-planner.module.css"),
  ]);
  for (const path of [
    "app/competiciones/[competition]/gestion/campos/page.tsx",
    "app/competiciones/[competition]/gestion/campos/plan/page.tsx",
    "app/competiciones/[competition]/gestion/campos/revisiones/page.tsx",
    "app/clubes/gestionar/campos/bloques/page.tsx",
    "app/clubes/gestionar/campos/pools/page.tsx",
    "app/reservas/recurrentes/page.tsx",
    "app/reservas/recurrentes/[series]/page.tsx",
  ]) assert.ok((await source(path)).length > 0, `${path} must exist`);
  for (const action of [
    "allocation.item.assign", "allocation.item.move", "allocation.item.swap",
    "allocation.item.remove", "allocation.lock.create", "allocation.lock.remove",
    "allocation_constraint.create", "allocation_constraint.remove",
    "allocation_inputs.freeze", "allocation.generate", "allocation.regenerate",
    "allocation.hold", "allocation.validate", "allocation.publish",
    "venue_pool.offer", "venue_pool.accept", "venue_pool.activate",
  ]) assert.match(client, new RegExp(action.replaceAll(".", "\\.")));
  assert.match(client, /read\(\{ poolId: selectedPoolId, view: "pool" \}/);
  assert.match(client, /venueText\(entry\.authorizationId\)/);
  assert.match(client, /quality\.hardViolations/);
  assert.match(client, /quality\.recurringBlockUsage/);
  assert.match(navigation, /id: "season-venues"/);
  assert.match(css, /max-width: 760px/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
});

test("commands remain central, revisioned and unavailable offline", async () => {
  const [client, commandRoute, contract] = await Promise.all([
    source("app/_components/season-venue-planner-client.tsx"),
    source("app/api/season-venues/command/route.ts"),
    source("app/season-venue-allocation-contract.ts"),
  ]);
  assert.match(client, /crypto\.randomUUID\(\)/);
  assert.match(client, /expectedRevision/);
  assert.match(client, /Sin conexión: no se ha enviado ni confirmado ningún cambio/);
  assert.match(client, /await load\(accessToken, clubId, "mutation"\)/);
  assert.doesNotMatch(client, /optimistic|pendingQueue|offlineQueue/i);
  assert.match(commandRoute, /clientWriteGateResponse/);
  assert.match(commandRoute, /origin !== new URL\(request\.url\)\.origin/);
  assert.match(commandRoute, /command_pachanga_competition_venue_allocation_v1/);
  assert.match(commandRoute, /operation_id: operationId/);
  assert.match(commandRoute, /expected_revision: expectedRevision/);
  assert.doesNotMatch(commandRoute, /service_role|SUPABASE_SERVICE_ROLE/i);
  assert.match(contract, /privateAddress|coordinates|operationId/i);
  assert.match(contract, /750_000/);
});

test("read models invalidate through Realtime and APIs remain outside the Service Worker cache", async () => {
  const [client, readRoute, worker] = await Promise.all([
    source("app/_components/season-venue-planner-client.tsx"),
    source("app/api/season-venues/read/route.ts"),
    source("app/service-worker-source.ts"),
  ]);
  assert.match(client, /postgres_changes/);
  assert.match(client, /pachanga_venue_invalidations/);
  assert.match(client, /status === "SUBSCRIBED"/);
  assert.match(client, /load\(session\.access_token, targetClubId, "realtime"\)/);
  assert.match(readRoute, /get_pachanga_season_venue_catalog_v1/);
  assert.match(readRoute, /venueApiJson/);
  assert.match(worker, /pathname\.startsWith\("\/api\/"\)/);
  assert.doesNotMatch(worker, /\/api\/season-venues/);
});

test("all eight migrations are forward-only, gated and privacy-safe", async () => {
  const migrations = await Promise.all([
    "20260830223000_venue_recurring_reservation_series_v1.sql",
    "20260830223002_competition_venue_pool_authorization_v1.sql",
    "20260830223004_competition_venue_allocation_plans_v1.sql",
    "20260830223006_competition_venue_allocation_constraints_quality_v1.sql",
    "20260830223008_competition_venue_allocation_engine_commands_v1.sql",
    "20260830223010_competition_venue_allocation_publication_v1.sql",
    "20260830223012_competition_venue_allocation_read_models_v1.sql",
    "20260830223014_competition_venue_allocation_hardening_flags_v1.sql",
  ].map((name) => source(`supabase/migrations/${name}`)));
  assert.equal(migrations.length, 8);
  const joined = migrations.join("\n");
  assert.match(joined, /end_date <= start_date \+ 728/);
  assert.match(joined, /then 728 else 364 end/);
  assert.match(joined, /WEEKLY/);
  assert.match(joined, /BIWEEKLY/);
  assert.match(joined, /get_pachanga_season_venue_catalog_v1/);
  assert.match(joined, /command_pachanga_competition_venue_allocation_v1/);
  assert.match(joined, /competition_venue_allocation_publish_enabled/);
  assert.match(joined, /demo_world_v35_enabled/);
  assert.match(joined, /pachanga_referee_assert_available_v1[\s\S]*pachanga_club_venues[\s\S]*venues\.municipality/);
  assert.match(joined, /pachanga_competition_venue_can_v1\([\s\S]*'read'/);
  assert.match(joined, /joint_schedule_venue_optimization_enabled/);
  assert.match(joined, /venue_payments_enabled/);
  assert.match(joined, /revoke all on function/);
  assert.doesNotMatch(joined, /errcode\s*=\s*'40001'/);
  assert.doesNotMatch(joined, /sk_live_|rk_live_|whsec_/);
});

test("staging is canonical, transactional and two-device reproducible", async () => {
  const [bootstrap, dataset, staging] = await Promise.all([
    source("tests/season-venue-allocation-v1-staging-schema-bootstrap.mjs"),
    source("tests/season-venue-allocation-v1-staging-dataset.sql"),
    source("tests/season-venue-allocation-v1-staging-e2e.mjs"),
  ]);
  assert.match(bootstrap, /SEASON_VENUE_STAGING_SCHEMA_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(bootstrap, /SEASON_VENUE_STAGING_EMPTY_BRANCH_NOT_EMPTY/);
  assert.match(bootstrap, /create table supabase_migrations\.schema_migrations/);
  assert.match(bootstrap, /PSQL_ATOMIC_LEDGER/);
  assert.match(bootstrap, /pachanga_groups_team_code_key/);
  assert.match(bootstrap, /7b9a69ed794f9f71dc0a0efc91c9ae75b20f79fef9c4261eb5c19a4a1d0fee12/);
  assert.doesNotMatch(bootstrap, /db", "push/);
  assert.match(dataset, /WAVE9B_STAGING_DATASET_REQUIRES_EMPTY_BRANCH/);
  assert.match(dataset, /\\set ON_ERROR_STOP on/);
  assert.match(dataset, /command_pachanga_league_participation_platform_v1/);
  assert.match(dataset, /command_pachanga_referee_assignment_beta_admin_v1/);
  assert.match(dataset, /TOURNAMENT_PRIVATE_BETA_V1/);
  assert.match(dataset, /begin;[\s\S]*commit;/i);
  assert.match(staging, /createAccount\("device-a"\)/);
  assert.match(staging, /createAccount\("device-b"\)/);
  assert.match(staging, /accountA\.id[\s\S]*'club_venue_manager'/);
  assert.match(staging, /accountB\.id[\s\S]*'club_reservation_manager'/);
  assert.match(staging, /"ON_ERROR_STOP=1"/);
  assert.match(staging, /WAVE9B_REALTIME_SUBSCRIPTION_TIMEOUT/);
  assert.match(staging, /"demoWorldV34Enabled"/);
  assert.match(staging, /assert\.equal\(stale\.status, 409\)/);
  assert.match(staging, /assert\.deepEqual\(JSON\.parse\(runSql/);
  assert.match(staging, /VERCEL_AUTOMATION_BYPASS_SECRET/);
  assert.match(staging, /x-vercel-protection-bypass/);
  assert.doesNotMatch(staging, /x-vercel-set-bypass-cookie/);
  assert.match(staging, /WAVE9B_STAGING_PRODUCT_RESIDUE_REQUIRES_BRANCH_REPLACEMENT/);
  assert.match(staging, /wave9bReceipts: 0/);
  assert.match(staging, /assert\.equal\(topology\.matches, 50\)|matches: 50/);
  assert.doesNotMatch(staging, /NEXT_PUBLIC_.*SERVICE_ROLE|pachangasiq\.com.*previewUrl/);
});
