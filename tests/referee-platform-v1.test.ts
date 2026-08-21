import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = [
  "supabase/migrations/20260821182105_referee_platform_foundation_v1.sql",
  "supabase/migrations/20260821182106_referee_club_assignment_authority_v1.sql",
  "supabase/migrations/20260821182107_referee_platform_access_v1.sql",
] as const;

async function source(path: string) { return readFile(new URL(path, root), "utf8"); }

test("R3 models one independent referee facet per universal user without rating", async () => {
  const core = await source(migrations[0]);
  assert.match(core, /create table if not exists public\.pachanga_referee_profiles/);
  assert.match(core, /user_id uuid not null unique references auth\.users\(id\)/);
  for (const column of ["slug", "operational_status", "verification_status", "visibility", "marketplace_status", "revision", "server_sequence"]) {
    assert.match(core, new RegExp(`${column} [^,]+`));
  }
  assert.doesNotMatch(core, /(?:referee_rating|referee_overall|referee_grl|referee_facets|referee_votes|referee_season_score|referee_rank|referee_stars)/i);
});

test("all six referee feature flags default off and dependent features require the foundation", async () => {
  const core = await source(migrations[0]);
  for (const flag of [
    "referee_foundation_enabled", "referee_self_service_enabled", "referee_public_profiles_enabled",
    "referee_marketplace_enabled", "referee_club_relationships_enabled", "referee_assignments_enabled",
  ]) assert.match(core, new RegExp(`${flag} boolean not null default false`));
  assert.match(core, /not referee_self_service_enabled or referee_foundation_enabled/);
  assert.match(core, /not referee_marketplace_enabled or \(referee_foundation_enabled and referee_public_profiles_enabled\)/);
  assert.match(core, /not referee_assignments_enabled or referee_foundation_enabled/);
});

test("self-service activation validates verified email, profile completeness and rate limits", async () => {
  const [authority, platform] = await Promise.all([source(migrations[1]), source(migrations[2])]);
  assert.match(authority, /users\.email_confirmed_at is not null[\s\S]*?VERIFIED_EMAIL_REQUIRED/);
  assert.match(platform, /REFEREE_RATE_LIMITED/);
  assert.match(authority, /REFEREE_PROFILE_ALREADY_EXISTS/);
  assert.match(authority, /REFEREE_PROFILE_INCOMPLETE/);
  assert.match(authority, /pachanga_referee_modalities/);
  assert.match(authority, /pachanga_referee_service_areas/);
  assert.doesNotMatch(authority.match(/command_action = 'profile\.create'[\s\S]*?elsif command_action in/)?.[0] ?? "", /insert into public\.pachanga_player_profiles/);
});

test("public referee snapshots are minimized and private availability remains private", async () => {
  const core = await source(migrations[0]);
  const publicSnapshot = core.match(/create or replace function private\.pachanga_referee_public_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(publicSnapshot, /displayName/);
  assert.match(publicSnapshot, /disciplineStatsStatus', 'NOT_AVAILABLE'/);
  assert.match(publicSnapshot, /yellowCardsShown', null/);
  assert.doesNotMatch(publicSnapshot, /user_id|target_email|private_reason|proposal_message|authority_used|event_payload|phone/i);
  assert.match(core, /get_pachanga_public_referee_v1/);
  assert.match(core, /referee_public_profiles_enabled/);
});

test("marketplace is explainable, paginated and exposes only an opaque profile target", async () => {
  const core = await source(migrations[0]);
  const market = core.match(/create or replace function public\.search_pachanga_referee_market_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(market, /safe_page_size integer := least\(60/);
  assert.match(market, /filter_relevance_then_recent_activity/);
  assert.match(market, /refereeProfileId/);
  for (const filter of ["zone", "province", "municipality", "modality", "weekday", "availabilityStatus", "clubId", "minExperienceYear", "verified"]) {
    assert.match(market, new RegExp(filter));
  }
  assert.doesNotMatch(market, /rating|stars|overall|popularity/i);
});

test("Club-referee relations preserve history and invitation secrets never enter ledgers", async () => {
  const combined = (await Promise.all(migrations.slice(0, 2).map(source))).join("\n");
  assert.match(combined, /relationship_type in \('REGULAR', 'COLLABORATOR', 'PREFERRED'\)/);
  assert.match(combined, /status in \('invited', 'requested', 'active', 'rejected', 'cancelled', 'ended'\)/);
  assert.match(combined, /extensions\.gen_random_bytes\(32\)/);
  assert.match(combined, /extensions\.digest\(one_time_token, 'sha256'\)/);
  assert.match(combined, /oneTimeToken/);
  assert.match(combined, /target_email_normalized = null/);
  assert.match(combined, /ended_at/);
  assert.doesNotMatch(combined.match(/create table private\.pachanga_referee_operation_receipts[\s\S]*?;/)?.[0] ?? "", /token|email/i);
  assert.doesNotMatch(combined.match(/create table private\.pachanga_referee_events[\s\S]*?;/)?.[0] ?? "", /token|email/i);
});

test("club_referee_manager gains only scoped referee authority", async () => {
  const authority = await source(migrations[1]);
  const roleBlock = authority.match(/when 'club_referee_manager'[\s\S]*?when 'club_viewer'/)?.[0] ?? "";
  assert.match(roleBlock, /'read', 'referee_manage'/);
  assert.doesNotMatch(roleBlock, /owners_manage|members_manage|team_links_manage|competition_create|billing/);
  assert.match(authority, /competition_referee_manager/);
  assert.match(authority, /competition_referees/);
});

test("assignments bind exact canonical matches, use server schedules and activate only MAIN_REFEREE", async () => {
  const authority = await source(migrations[1]);
  assert.match(authority, /pachanga_canonical_match_bindings/);
  assert.match(authority, /binding_status = 'active'/);
  assert.match(authority, /REFEREE_CANONICAL_MATCH_REQUIRED/);
  assert.match(authority, /scheduleRevision/);
  assert.match(authority, /MATCH_SCHEDULE_CHANGED/);
  assert.match(authority, /target_role <> 'MAIN_REFEREE'[\s\S]*?REFEREE_ROLE_NOT_AVAILABLE/);
  assert.match(authority, /REFEREE_ASSIGNMENT_TEAM_OWNER_REQUIRED/);
  assert.match(authority, /REFEREE_CLUB_NOT_COMPETITION_ORGANIZER/);
  assert.match(authority, /REFEREE_COMPETITION_ENTITLEMENT_REQUIRED/);
  assert.doesNotMatch(authority, /canonical\.backfill|similarity|levenshtein/i);
});

test("assignment slot and time conflicts are enforced transactionally", async () => {
  const combined = (await Promise.all(migrations.slice(0, 2).map(source))).join("\n");
  assert.match(combined, /pachanga_referee_assignment_active_slot_idx/);
  assert.match(combined, /pg_advisory_xact_lock\(hashtextextended\('referee-assignment-profile:/);
  assert.match(combined, /pg_advisory_xact_lock\(hashtextextended\('referee-assignment-slot:/);
  assert.match(combined, /tstzrange\(existing\.scheduled_start, existing\.scheduled_end, '\[\)'\)/);
  assert.match(combined, /REFEREE_ASSIGNMENT_TIME_CONFLICT/);
  assert.match(combined, /REFEREE_ASSIGNMENT_SLOT_TAKEN/);
  assert.match(combined, /STALE_REVISION/);
});

test("completion and statistics remain canonical, reconstructible and discipline-free", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(combined, /reconcile_pachanga_referee_assignment_v1/);
  assert.match(combined, /REFEREE_CANONICAL_MATCH_NOT_CONCLUDED/);
  assert.match(combined, /refresh_mode not in \('incremental', 'full_rebuild'\)/);
  assert.match(combined, /checksum/);
  assert.match(combined, /discipline_stats_status text not null default 'NOT_AVAILABLE'/);
  assert.match(combined, /yellow_cards_shown integer/);
  assert.doesNotMatch(combined, /update public\.pachanga_referee_statistics_snapshots[\s\S]{0,500}(?:yellow_cards_shown|red_cards_shown|blue_cards_shown)\s*=/i);
});

test("R3 direct writes are revoked and Realtime carries scoped invalidations only", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const table of [
    "pachanga_referee_profiles", "pachanga_referee_modalities", "pachanga_referee_service_areas",
    "pachanga_referee_availability_windows", "pachanga_referee_availability_exceptions",
    "pachanga_club_referee_relationships", "pachanga_referee_assignments", "pachanga_referee_statistics_snapshots",
  ]) {
    assert.match(combined, new RegExp(`'${table}'`));
  }
  assert.match(combined, /execute format\('alter table public\.%I enable row level security'/);
  assert.match(combined, /execute format\('revoke all on table public\.%I from public, anon, authenticated'/);
  assert.match(combined, /alter publication supabase_realtime add table public\.pachanga_referee_invalidations/);
  assert.match(
    combined,
    /grant execute on function private\.pachanga_referee_can_read_invalidation_v1\([\s\S]*?\) to authenticated/,
  );
  assert.doesNotMatch(combined, /alter publication supabase_realtime add table public\.pachanga_referee_(?:profiles|assignments|statistics)/);
  assert.doesNotMatch(combined, /grant (?:insert|update|delete|all) on table public\.pachanga_referee[^;]+to (?:anon|authenticated)/i);
});

test("operation envelopes resolve the actor server-side and persist immutable receipts and events", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(combined, /operation_id uuid/);
  assert.match(combined, /expected_revision bigint/);
  assert.match(combined, /actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(combined, /OPERATION_ID_REUSED/);
  assert.match(combined, /REFEREE_LEDGER_IMMUTABLE/);
  assert.match(combined, /before update or delete on private\.pachanga_referee_operation_receipts/);
  assert.match(combined, /before update or delete on private\.pachanga_referee_events/);
  assert.doesNotMatch(combined, /command_payload\s*->>\s*'actorId'/);
});

test("private reads are bounded and Control Center and Mercado paginate server-side", async () => {
  const [core, platform] = await Promise.all([source(migrations[0]), source(migrations[2])]);
  const privateSnapshot = core.match(/create or replace function private\.pachanga_referee_private_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(privateSnapshot, /limit 200/);
  assert.match(core, /limit 100/);
  assert.match(platform, /safe_page_size integer := least\(greatest\(coalesce\(target_page_size, 50\), 1\), 100\)/);
  assert.match(platform, /limit safe_page_size offset \(safe_page - 1\) \* safe_page_size/);
});

test("Control Center preserves prior capabilities and adds referee scopes without PII search", async () => {
  const platform = await source(migrations[2]);
  assert.match(platform, /platform_owner[\s\S]*?'rankings\.write'[\s\S]*?'clubs\.manage'[\s\S]*?'referees\.read', 'referees\.manage'/);
  assert.match(platform, /platform_admin[\s\S]*?'referees\.read', 'referees\.manage'/);
  assert.match(platform, /when 'support'[\s\S]*?'referees\.read'/);
  assert.match(platform, /search_pachanga_platform_referees_v1/);
  const search = platform.match(/create or replace function public\.search_pachanga_platform_referees_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.doesNotMatch(search, /email|phone|target_user_id/i);
});

test("PWA classifies every R3 write and never reports an offline success", () => {
  for (const rpc of [
    "command_pachanga_referee_platform_v1", "command_pachanga_referee_platform_admin_v1",
    "command_pachanga_club_referee_manager_v1", "reconcile_pachanga_referee_assignment_v1",
  ]) assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  assert.equal(isKnownClientWriteOperation("api:referee-command"), true);
  assert.equal(isKnownClientWriteOperation("api:platform-admin-referees"), true);
});

test("R3 routes are noindex, server-confirmed and free of service-role browser authority", async () => {
  const [privateLayout, publicLayout, labLayout, commandRoute, client, market, admin] = await Promise.all([
    source("app/perfil/arbitro/layout.tsx"), source("app/arbitros/[slug]/layout.tsx"),
    source("app/laboratorio-referee-platform/layout.tsx"), source("app/api/referees/command/route.ts"),
    source("app/_components/referee-platform-client.tsx"), source("app/mercado/referee-marketplace-panel.tsx"),
    source("app/admin/referees/page.tsx"),
  ]);
  for (const layout of [privateLayout, publicLayout, labLayout]) assert.match(layout, /robots: \{ follow: false, index: false \}/);
  assert.match(commandRoute, /clientWriteGateResponse|refereeWriteGate/);
  assert.match(commandRoute, /platformUserClient|refereeSession/);
  assert.doesNotMatch(commandRoute + client + market, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(client, /pachanga_referee_invalidations/);
  assert.match(client, /loadCanonical\(actorId, token, "realtime"\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
  assert.match(market, /pageSize/);
  assert.match(market, /RefereeProfileCard/);
  assert.doesNotMatch(market, /rating|stars|overall|GRL/);
  assert.match(admin, /requirePlatformPage\("referees\.read"\)/);
});

test("R3 staging harness requires isolated credentials, two devices, Realtime and cleanup", async () => {
  const staging = await source("tests/referee-platform-v1-staging-e2e.mjs");
  for (const variable of [
    "REFEREE_PLATFORM_STAGING_URL",
    "REFEREE_PLATFORM_STAGING_PUBLISHABLE_KEY",
    "REFEREE_PLATFORM_STAGING_PASSWORD",
  ]) assert.match(staging, new RegExp(variable));
  assert.match(staging, /refereeOneDesktop/);
  assert.match(staging, /refereeOneMobile/);
  assert.match(staging, /pachanga_referee_invalidations/);
  assert.match(staging, /invalidationPromise[\s\S]*?mySnapshot\(refereeOneMobile\)/);
  assert.match(staging, /relationship\.invite/);
  assert.match(staging, /assignment\.replace/);
  assert.match(staging, /reconcile_pachanga_referee_assignment_v1/);
  assert.match(staging, /disable-r3-flags/);
  assert.match(staging, /foundationEnabled: false/);
  assert.doesNotMatch(staging, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("R3 does not write Rating, results, rewards, conduct, billing, ranking or Demo authorities", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const table of [
    "pachanga_player_profiles", "pachanga_individual_rating_evidence", "pachanga_match_participants",
    "pachanga_match_scorers", "pachanga_reward_grants", "pachanga_conduct_reports",
    "pachanga_stripe_webhook_events", "pachanga_provincial_ranking_entries",
  ]) assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.|private\\.)?${table}`, "i"));
  assert.doesNotMatch(combined, /demo.world|simulation\.synthetic|stripe\.products|create extension.*cron/i);
});
