import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = [
  "supabase/migrations/20260830145047_venue_pitch_foundation_v1.sql",
  "supabase/migrations/20260830145049_venue_availability_templates_exceptions_v1.sql",
  "supabase/migrations/20260830145051_venue_reservation_requests_holds_v1.sql",
  "supabase/migrations/20260830145053_venue_canonical_match_binding_r4d_v1.sql",
  "supabase/migrations/20260830145054_venue_command_receipts_events_v1.sql",
  "supabase/migrations/20260830145056_venue_read_models_control_center_v1.sql",
  "supabase/migrations/20260830145058_venue_rls_realtime_notifications_v1.sql",
  "supabase/migrations/20260830145100_venue_hardening_indexes_flags_v1.sql",
] as const;

async function source(path: string) { return readFile(new URL(path, root), "utf8"); }

test("Wave 9A is exactly eight forward-only migrations and every feature is born OFF", async () => {
  assert.equal(migrations.length, 8);
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const flag of [
    "venue_foundation_enabled", "venue_management_enabled", "venue_public_profiles_enabled",
    "venue_public_directory_enabled", "venue_availability_enabled", "venue_reservation_requests_enabled",
    "venue_counteroffers_enabled", "venue_reservation_holds_enabled", "venue_canonical_reservations_enabled",
    "venue_match_binding_enabled", "venue_r4d_integration_enabled", "demo_world_v34_enabled",
    "venue_payments_enabled", "venue_recurring_bookings_enabled",
    "venue_bulk_competition_allocation_enabled", "venue_external_integrations_enabled",
  ]) assert.match(combined, new RegExp(`${flag} boolean not null default false`));
  assert.doesNotMatch(combined, /insert into\s+(?:public\.|private\.)?pachanga_(?:stripe|payment|charge|customer)/i);
  const commandSurface = await source(migrations[4]);
  assert.doesNotMatch(commandSurface, /when 'venue\.(?:payment|recurring|bulk|external)|when 'reservation\.(?:payment|recurring|bulk|external)/i);
});

test("one authoritative command enforces actor, operationId and expected revision", async () => {
  const commands = await source(migrations[4]);
  assert.match(commands, /command_pachanga_venue_reservation_v1/);
  assert.match(commands, /operation_id uuid/);
  assert.match(commands, /expected_revision bigint/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /'STALE_REVISION'/);
  assert.match(commands, /private\.pachanga_venue_operation_receipts/);
  assert.match(commands, /private\.pachanga_venue_events/);
  assert.match(commands, /server_sequence/);
  assert.doesNotMatch(commands, /last-write-wins/i);
});

test("R4D preserves CanonicalMatch identity and forces referee reconfirmation", async () => {
  const combined = `${await source(migrations[3])}\n${await source(migrations[4])}\n${await source(migrations[6])}`;
  assert.match(combined, /previous_binding_id/);
  assert.match(combined, /fixture_change_revision_id/);
  assert.match(combined, /RECONFIRMATION_REQUIRED/);
  assert.match(combined, /VENUE_ACTION_REQUIRED/);
  assert.match(combined, /status='HISTORICAL'/);
  assert.match(combined, /canonical_match_id/);
});

test("public, requester, Club, Match, Home and platform read models are separated", async () => {
  const reads = await source(migrations[5]);
  for (const rpc of [
    "get_pachanga_public_venues_v1", "get_pachanga_public_venue_v1",
    "get_pachanga_venue_availability_v1", "get_pachanga_my_venue_reservations_v1",
    "get_pachanga_club_venue_desk_v1", "get_pachanga_venue_reservation_v1",
    "get_pachanga_match_venue_v1", "get_pachanga_venue_home_status_v1",
    "get_pachanga_venue_control_center_v1",
  ]) assert.match(reads, new RegExp(rpc));
  assert.match(reads, /pachanga_venue_private_location_can_v1/);
  assert.match(reads, /operationalLocation/);
  assert.match(reads, /private\.pachanga_venue_publicly_visible_v1/);
  assert.match(reads, /NOT_IN_CANONICAL_LEDGER/);
  assert.match(reads, /partnerCandidates/);
});

test("Venue APIs use authenticated user clients, no-store and strict command envelopes", async () => {
  const routes = [
    "app/api/venues/directory/route.ts", "app/api/venues/availability/route.ts",
    "app/api/venues/my/route.ts", "app/api/venues/home/route.ts",
    "app/api/venues/club/[clubId]/route.ts", "app/api/venues/reservation/[reservationId]/route.ts",
    "app/api/venues/match/[canonicalMatchId]/route.ts", "app/api/venues/command/route.ts",
  ];
  const contents = await Promise.all(routes.map(source));
  for (const content of contents) assert.doesNotMatch(content, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  const shared = await source("app/api/venues/_shared.ts");
  assert.match(shared, /noStoreHeaders/);
  assert.match(shared, /platformUserClient\(token\)/);
  const command = contents.at(-1)!;
  assert.match(command, /origin !== new URL\(request\.url\)\.origin/);
  assert.match(command, /clientWriteGateResponse/);
  assert.match(command, /operationId/);
  assert.match(command, /expectedRevision/);
  assert.match(command, /actionFields/);
  assert.doesNotMatch(command, /reservation\.hold\.expire/);
});

test("clients refetch canonical snapshots after Realtime and stale revisions", async () => {
  const [club, detail, home, requester, match] = await Promise.all([
    source("app/clubes/gestionar/club-venue-operations-client.tsx"),
    source("app/reservas/[reservation]/venue-reservation-detail-client.tsx"),
    source("app/_components/venue-home-status.tsx"),
    source("app/reservas/venue-reservations-client.tsx"),
    source("app/_components/venue-match-panel.tsx"),
  ]);
  assert.match(club, /selectedClubIdRef\.current/);
  assert.doesNotMatch(club, /loadDesk\(initialClub, token, "realtime"\)/);
  assert.match(detail, /STALE_REVISION\/i\.test\(detail\)/);
  for (const client of [club, home, requester, match]) {
    assert.match(client, /pachanga_venue_invalidations/);
    assert.match(client, /SUBSCRIBED/);
  }
});

test("offline writes fail closed while derived shells and Demo V3.4 can be cached", async () => {
  const [club, requester, detail, worker] = await Promise.all([
    source("app/clubes/gestionar/club-venue-operations-client.tsx"),
    source("app/reservas/venue-reservations-client.tsx"),
    source("app/reservas/[reservation]/venue-reservation-detail-client.tsx"),
    source("app/service-worker-source.ts"),
  ]);
  for (const client of [club, requester, detail]) assert.match(client, /Sin conexión:[^\n]+no se ha enviado ningún cambio/);
  assert.match(worker, /\/demo-world\/v3-4\/manifest\.json/);
  assert.match(worker, /\/campos/);
  assert.match(worker, /\/reservas/);
  assert.match(worker, /isSensitivePath/);
  assert.equal(classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_venue_reservation_v1", { method: "POST" }), "rpc:command_pachanga_venue_reservation_v1");
  assert.equal(isKnownClientWriteOperation("api:venue-operations-command"), true);
});

test("product navigation adds contextual Campos and Reservas without a sixth primary tab", async () => {
  const [navigation, page, admin, shell, styles] = await Promise.all([
    source("app/_components/product-navigation-contract.ts"),
    source("app/page.tsx"),
    source("app/admin/venues/page.tsx"),
    source("app/admin/_lib/platform-contract.ts"),
    source("app/venue-operations.module.css"),
  ]);
  assert.match(navigation, /\/campos/);
  assert.match(navigation, /\/reservas/);
  assert.match(page, /Campo y reserva/);
  assert.match(page, /VenueMatchPanel/);
  assert.match(page, /VenueHomeStatus/);
  assert.match(admin, /Venue Operations/);
  assert.match(shell, /\/admin\/venues/);
  assert.match(styles, /\.hero a:not\(\.action\):not\(\.secondaryAction\):not\(\.dangerAction\)/);
  assert.match(styles, /\.action,[\s\S]*background: #badb3b;[\s\S]*color: #10160c;/);
});

test("staging bootstrap bypasses fixture guards only inside one transaction", async () => {
  const bootstrap = await source("tests/venue-operations-v1-staging-bootstrap.sql");
  assert.match(bootstrap, /begin;[\s\S]*set local session_replication_role = replica;/);
  assert.match(bootstrap, /\\ir venue-operations-v1-fixture\.sql/);
  assert.match(bootstrap, /set local session_replication_role = origin;[\s\S]*\\ir venue-operations-v1-db\.sql[\s\S]*commit;/);
  assert.match(bootstrap, /VENUE_OPERATIONS_V1_STAGING_BOOTSTRAP_PASS/);
  assert.doesNotMatch(bootstrap, /set\s+session_replication_role\s*=\s*replica\s*;/);
});

test("staging schema bootstrap is branch-only and reconciles the exact migration frontier", async () => {
  const bootstrap = await source("tests/venue-operations-v1-staging-schema-bootstrap.mjs");
  assert.match(bootstrap, /VENUE_OPERATIONS_STAGING_SCHEMA_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(bootstrap, /manifest\.absorbedMigrations\.slice\(0, 10\)/);
  assert.match(bootstrap, /"migration", "repair"/);
  assert.match(bootstrap, /"db", "push"/);
  assert.match(bootstrap, /enabled = true/);
  assert.match(bootstrap, /mkdtempSync/);
  assert.match(bootstrap, /rmSync\(cliWorkdir/);
  assert.match(bootstrap, /ledgerCount: 220/);
  assert.match(bootstrap, /flagsBornOff: true/);
});

test("staging dataset has the exact synthetic field-operations topology", async () => {
  const dataset = await source("tests/venue-operations-v1-staging-dataset.sql");
  for (const expected of [
    /count\(\*\) from public\.pachanga_clubs\) <> 3/,
    /count\(\*\) from public\.pachanga_groups\) <> 6/,
    /count\(\*\) from public\.pachanga_club_venues\) <> 6/,
    /count\(\*\) from public\.pachanga_venue_pitches\) <> 12/,
    /competition_type='LEAGUE'\) <> 1/,
    /competition_type='TOURNAMENT'\) <> 1/,
    /count\(\*\) from public\.pachanga_canonical_matches\) <> 20/,
  ]) assert.match(dataset, expected);
  assert.match(dataset, /command_pachanga_club_foundation_v1/);
  assert.match(dataset, /command_pachanga_venue_reservation_v1/);
  assert.match(dataset, /VENUE_OPERATIONS_V1_STAGING_DATASET_PASS/);
});

test("staging runner is production-safe and certifies Auth, Realtime and convergence", async () => {
  const staging = await source("tests/venue-operations-v1-staging-e2e.mjs");
  assert.match(staging, /VENUE_OPERATIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(staging, /env\.projectRef === productionRef/);
  assert.match(staging, /2 synthetic accounts \/ 2 authenticated devices/);
  assert.match(staging, /status: "VENUE_OPERATIONS_V1_STAGING_PASS"/);
  assert.match(staging, /STALE_REVISION\|PT409/);
  assert.match(staging, /pachanga_venue_invalidations/);
  assert.match(staging, /SUBSCRIBED/);
  assert.match(staging, /VENUE_POSTGRES_CHANGES_BINDING_TIMEOUT/);
  assert.match(staging, /payload\?\.extension !== "postgres_changes"/);
  assert.match(staging, /VENUE_OPERATIONS_STAGING_PREVIEW_VERCEL_CLI/);
  assert.match(staging, /"curl", path/);
  assert.match(staging, /await clubDesk\(deviceB\)/);
  assert.match(staging, /EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED/);
  assert.doesNotMatch(staging, /qonbngfrnrqgmxbdfbea\.supabase\.co/);
});
