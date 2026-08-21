import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrationPaths = [
  "supabase/migrations/20260821054224_competition_canonical_match_foundation_v1.sql",
  "supabase/migrations/20260821054225_competition_organizer_core_v1.sql",
  "supabase/migrations/20260821054227_competition_platform_access_v1.sql",
] as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("canonical match bindings preserve exact source identity and fail ambiguous cases closed", async () => {
  const [canonical, platform] = await Promise.all([source(migrationPaths[0]), source(migrationPaths[2])]);
  assert.match(canonical, /create table if not exists public\.pachanga_canonical_matches/);
  assert.match(canonical, /create table if not exists public\.pachanga_canonical_match_bindings/);
  assert.match(canonical, /source_kind text not null/);
  assert.match(canonical, /source_group_id uuid/);
  assert.match(canonical, /source_id text not null/);
  assert.match(canonical, /where binding_status = 'active'/);
  assert.match(platform, /'group_match'/);
  assert.match(platform, /'open_match'/);
  assert.match(platform, /'team_challenge'/);
  assert.match(platform, /'external_match'/);
  assert.match(platform, /pachanga_canonical_match_binding_reviews/);
  assert.match(platform, /private\.pachanga_backfill_canonical_matches_v1/);
  assert.match(platform, /related_canonical_id := private\.pachanga_related_canonical_match_v1/);
  assert.doesNotMatch(platform, /date_trunc\([^\n]+canonical|similarity\([^\n]+canonical|score_home\s*=\s*score_away/i);
});

test("canonical health is materialized, invalidated by source events and never recalculated by reads", async () => {
  const platform = await source(migrationPaths[2]);
  assert.match(platform, /create table if not exists private\.pachanga_canonical_match_health_state/);
  assert.match(platform, /create or replace function private\.pachanga_compute_canonical_match_health_v1/);
  assert.match(platform, /create or replace function private\.pachanga_refresh_canonical_match_health_v1/);
  assert.match(platform, /create or replace function private\.pachanga_mark_canonical_match_health_dirty_v1/);
  assert.match(platform, /select state\.snapshot \|\| jsonb_build_object\(/);
  assert.match(platform, /'stale', state\.dirty/);
  assert.match(platform, /perform private\.pachanga_refresh_canonical_match_health_v1\(\)/);
  assert.doesNotMatch(
    platform.match(/create or replace function public\.get_pachanga_platform_canonical_match_health_v1\(\)[\s\S]*?\$\$;/)?.[0] ?? "",
    /pachanga_compute_canonical_match_health_v1/,
  );
});

test("competition foundation is versioned and does not create a league or tournament engine", async () => {
  const core = await source(migrationPaths[1]);
  for (const table of [
    "pachanga_competitions",
    "pachanga_competition_editions",
    "pachanga_competition_rule_sets",
    "pachanga_competition_rule_revisions",
    "pachanga_competition_stages",
    "pachanga_competition_divisions",
    "pachanga_competition_groups",
    "pachanga_competition_stage_edges",
    "pachanga_competition_match_contexts",
  ]) assert.match(core, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(core, /competition_type text not null/);
  assert.match(core, /check \(competition_type in \('LEAGUE', 'TOURNAMENT'\)\)/);
  assert.match(core, /organizer_kind text not null default 'TEAM'/);
  assert.match(core, /FEATURE_NOT_AVAILABLE/);
  assert.doesNotMatch(core, /create table[^;]+(?:league_matches|tournament_matches|competition_results|competition_standings)/i);
  assert.doesNotMatch(core, /round_robin|fixture_generator|generate_matchday|calculate_standings/i);
});

test("rule documents have deterministic checksums, structural validation and immutable history", async () => {
  const core = await source(migrationPaths[1]);
  assert.match(core, /target_schema_version \|\| ':' \|\| target_document::text/);
  for (const section of ["format", "registration", "structure", "results", "operations", "discipline", "governance", "publication", "futureCapabilities"]) {
    assert.match(core, new RegExp(`'${section}'`));
  }
  assert.match(core, /stageGraph requires exactly one root/);
  assert.match(core, /undeclared stage cycles are not supported in R1/);
  assert.match(core, /required stage is unreachable/);
  assert.match(core, /minimum exceeds maximum/);
  assert.match(core, /hard constraint cannot equal a preference/);
  assert.match(core, /mutable live preset references are forbidden/);
  assert.match(core, /before update or delete on public\.pachanga_competition_rule_revisions/);
  assert.match(core, /RULE_REVISION_IMMUTABLE/);
  assert.match(core, /RULE_REVISION_FROZEN/);
});

test("all writes use command envelopes, receipts and monotonic server events", async () => {
  const combined = (await Promise.all(migrationPaths.map(source))).join("\n");
  assert.match(combined, /operation_id uuid/);
  assert.match(combined, /expected_revision bigint/);
  assert.match(combined, /pg_advisory_xact_lock\(hashtextextended\(operation_id::text/);
  assert.match(combined, /pachanga_competition_operation_receipts/);
  assert.match(combined, /pachanga_competition_events/);
  assert.match(combined, /request_hash/);
  assert.match(combined, /STALE_REVISION/);
  assert.match(combined, /using errcode = 'PT409'/);
  assert.match(combined, /server_sequence bigint not null/);
  assert.match(combined, /IDEMPOTENCY_KEY_REUSED/);
});

test("team ownership, entitlements and staff are resolved by PostgreSQL", async () => {
  const [core, platform] = await Promise.all([source(migrationPaths[1]), source(migrationPaths[2])]);
  assert.match(core, /group_row\.owner_id <> actor_id/);
  assert.match(core, /COMPETITION_OWNER_REQUIRED/);
  assert.match(core, /COMPETITION_ENTITLEMENT_REQUIRED/);
  assert.match(core, /competition_create/);
  assert.match(core, /competition_manage/);
  assert.match(core, /competition_staff/);
  assert.match(core, /competition_rules/);
  assert.match(core, /grants\.expires_at is null or grants\.expires_at > statement_timestamp\(\)/);
  assert.match(core, /competition_owner|competition_director|competition_admin|rules_manager|viewer/);
  assert.match(platform, /platform_grant/);
  assert.match(platform, /pachanga_platform_require_v1\('competitions\.manage'\)/);
  assert.doesNotMatch(platform, /stripe|billing_status|subscription/i);
});

test("foundation tables reject direct client writes and expose only scoped read paths", async () => {
  const combined = (await Promise.all(migrationPaths.map(source))).join("\n");
  assert.match(combined, /alter table public\.pachanga_competitions enable row level security/);
  assert.match(combined, /revoke all on table public\.pachanga_competitions from public, anon, authenticated/);
  assert.match(combined, /grant execute on function public\.command_pachanga_competition_foundation_v1[\s\S]+to authenticated, service_role/);
  assert.match(combined, /grant execute on function public\.command_pachanga_competition_platform_v1[\s\S]+to authenticated, service_role/);
  assert.match(combined, /private\.pachanga_competition_require_v1/);
  assert.match(combined, /private\.pachanga_platform_require_v1\('competitions\.read'\)/);
  assert.doesNotMatch(combined, /grant (?:insert|update|delete|all) on table public\.pachanga_competition[^;]+to (?:anon|authenticated)/i);
});

test("feature flags are off by default and context binding remains a lab-only operation", async () => {
  const [core, platform] = await Promise.all([source(migrationPaths[1]), source(migrationPaths[2])]);
  assert.match(core, /foundation_enabled boolean not null default false/);
  assert.match(core, /creation_enabled boolean not null default false/);
  assert.match(core, /context_binding_enabled boolean not null default false/);
  assert.match(platform, /command_action = 'competition_match_context\.bind'/);
  assert.match(platform, /pachanga_competition_assert_flags_v1\(false, true\)/);
});

test("PWA blocks unconfirmed competition writes while reads remain ordinary reads", () => {
  for (const rpc of ["command_pachanga_competition_foundation_v1", "command_pachanga_competition_platform_v1"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:platform-admin-competitions"), true);
  assert.equal(classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/get_my_pachanga_competition_foundation_v1", { method: "POST" }), null);
});

test("Realtime invalidates a user-scoped local read cache and refetches the canonical model", async () => {
  const lab = await source("app/laboratorio-competition-foundation/page.tsx");
  assert.match(lab, /pachangas-competition-foundation-read-v1/);
  assert.match(lab, /get_my_pachanga_competition_foundation_v1/);
  assert.match(lab, /pachanga_competition_invalidations/);
  assert.match(lab, /loadCanonical\(actorId, "realtime"\)/);
  assert.match(lab, /command_pachanga_competition_foundation_v1/);
  assert.doesNotMatch(lab, /\.from\("pachanga_competitions"\)\.(?:insert|update|delete)/);
  assert.doesNotMatch(lab, /setData\([^)]*payload\.new/);
});

test("the internal UI is protected, noindex and absent from public navigation", async () => {
  const [layout, lab, adminPage, adminRoute, contract, mainPage, mobileNav] = await Promise.all([
    source("app/laboratorio-competition-foundation/layout.tsx"),
    source("app/laboratorio-competition-foundation/page.tsx"),
    source("app/admin/competitions/page.tsx"),
    source("app/api/platform-admin/competitions/route.ts"),
    source("app/admin/_lib/platform-contract.ts"),
    source("app/page.tsx"),
    source("app/mobile-app-nav.tsx"),
  ]);
  assert.match(layout, /robots: \{ follow: false, index: false \}/);
  assert.match(lab, /client\.auth\.getSession/);
  assert.match(lab, /Inicia sesión para abrir el laboratorio/);
  assert.match(adminPage, /requirePlatformPage\("competitions\.read"\)/);
  assert.match(adminRoute, /requirePlatformRequest\(request, "competitions\.manage"\)/);
  assert.match(adminRoute, /requireSameOriginMutation\(request\)/);
  assert.match(contract, /competitions\.read/);
  assert.doesNotMatch(mainPage, /laboratorio-competition-foundation/);
  assert.doesNotMatch(mobileNav, /laboratorio-competition-foundation/);
  assert.doesNotMatch(adminRoute, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("Control Center consumes the exact canonical health contract", async () => {
  const adminPage = await source("app/admin/competitions/page.tsx");
  for (const key of [
    "canonicalMatches",
    "bindingsTotal",
    "unboundSources",
    "ambiguousBindings",
    "duplicateConflicts",
    "orphanCanonicalMatches",
    "contextsLinked",
  ]) assert.match(adminPage, new RegExp(`bindingHealth\\.${key}`));
  assert.match(adminPage, /bindingHealth\.stale/);
  assert.doesNotMatch(adminPage, /bindingHealth\.(?:activeBindings|reviewsOpen)/);
});

test("R1 leaves Rating, results, rewards, conduct, billing, ranking and Demo World untouched", async () => {
  const combined = (await Promise.all(migrationPaths.map(source))).join("\n");
  for (const table of [
    "pachanga_player_profiles",
    "pachanga_match_participants",
    "pachanga_match_scorers",
    "pachanga_achievement_grants",
    "pachanga_reward_grants",
    "pachanga_conduct_reports",
    "pachanga_season_score_snapshots",
  ]) {
    assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.)?${table}`, "i"));
  }
  assert.doesNotMatch(combined, /stripe_products|stripe_prices|create subscription/i);
  assert.doesNotMatch(combined, /demo-world|synthetic_world/i);
});
