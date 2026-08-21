import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = [
  "supabase/migrations/20260821141114_club_foundation_v1.sql",
  "supabase/migrations/20260821141121_club_competition_organizer_adapter_v1.sql",
  "supabase/migrations/20260821141129_club_platform_access_v1.sql",
  "supabase/migrations/20260821142109_club_invitation_response_token_hardening_v1.sql",
] as const;

async function source(path: string) { return readFile(new URL(path, root), "utf8"); }

test("Club is a canonical authority distinct from Team", async () => {
  const core = await source(migrations[0]);
  assert.match(core, /create table if not exists public\.pachanga_clubs/);
  for (const column of ["club_type", "operational_status", "verification_status", "partnership_status", "primary_owner_id", "revision", "server_sequence"]) {
    assert.match(core, new RegExp(`${column} [^,]+`));
  }
  assert.match(core, /references public\.pachanga_groups\(id\)/);
  assert.doesNotMatch(core, /create table[^;]+pachanga_clubs[^;]+inherits|pachanga_clubs\s+as\s+select[^;]+pachanga_groups/i);
  assert.doesNotMatch(core, /insert into public\.pachanga_clubs[\s\S]{0,200}select[\s\S]{0,200}from public\.pachanga_groups/i);
});

test("all five Club feature flags default off and depend on the foundation", async () => {
  const core = await source(migrations[0]);
  for (const flag of [
    "club_foundation_enabled",
    "club_self_service_creation_enabled",
    "club_team_relationships_enabled",
    "club_public_profiles_enabled",
    "club_competition_organizer_enabled",
  ]) assert.match(core, new RegExp(`${flag} boolean not null default false`));
  assert.match(core, /not club_self_service_creation_enabled or club_foundation_enabled/);
  assert.match(core, /not club_competition_organizer_enabled or club_foundation_enabled/);
});

test("creation is verified, rate limited and atomically creates an active primary owner", async () => {
  const core = await source(migrations[0]);
  assert.match(core, /users\.email_confirmed_at is not null/);
  assert.match(core, /CLUB_DRAFT_LIMIT_REACHED/);
  assert.match(core, /CLUB_CREATION_RATE_LIMITED/);
  assert.match(core, /'club_owner', 'active'/);
  assert.match(core, /CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED/);
  assert.match(core, /LAST_CLUB_OWNER_REQUIRED/);
  assert.match(core, /PRIMARY_OWNER_TARGET_MUST_BE_ACTIVE_OWNER/);
  assert.match(core, /beforePrimaryOwnerId/);
  assert.match(core, /afterPrimaryOwnerId/);
});

test("staff roles fail closed and future reserved roles remain unavailable", async () => {
  const core = await source(migrations[0]);
  for (const role of ["club_owner", "club_admin", "club_competition_manager", "club_viewer"]) assert.match(core, new RegExp(`'${role}'`));
  for (const role of ["club_venue_manager", "club_referee_manager", "club_finance_manager"]) assert.match(core, new RegExp(`'${role}'`));
  assert.match(core, /selected_role in \('club_venue_manager', 'club_referee_manager', 'club_finance_manager'\)[\s\S]*?FEATURE_NOT_AVAILABLE/);
  const adminBlock = core.match(/when 'club_admin'[\s\S]*?when 'club_competition_manager'/)?.[0] ?? "";
  assert.doesNotMatch(adminBlock, /competition_create/);
});

test("Club invitations store only token hashes and are one-use, expiring and email-bound", async () => {
  const core = await source(migrations[0]);
  const hardening = await source(migrations[3]);
  assert.match(core, /private\.pachanga_club_invitation_secrets/);
  assert.match(core, /extensions\.gen_random_bytes\(32\)/);
  assert.match(core, /extensions\.digest\(one_time_token, 'sha256'\)/);
  assert.match(core, /tokenReturnedOnce/);
  assert.match(core, /selected_secret\.consumed_at is not null/);
  assert.match(core, /lower\(users\.email\) = selected_secret\.target_email_normalized/);
  assert.match(core, /target_email_normalized = null/);
  assert.match(core, /CLUB_INVITATION_TOKEN_INVALID/);
  assert.doesNotMatch(core, /one_time_token\s+text[^;]+public\.pachanga_club_invitations/i);
  assert.match(hardening, /command_pachanga_club_foundation_v1_internal_r2/);
  assert.match(hardening, /if command_action = 'membership\.invite' then/);
  assert.match(hardening, /response[\s\S]*- 'oneTimeToken'[\s\S]*- 'invitationId'[\s\S]*- 'tokenReturnedOnce'/);
  assert.match(hardening, /revoke all on function public\.command_pachanga_club_foundation_v1_internal_r2[\s\S]*authenticated/);
});

test("Club-Team links require a two-sided handshake and never transfer Team authority", async () => {
  const core = await source(migrations[0]);
  assert.match(core, /relationship_type in \('MEMBER', 'AFFILIATED', 'HOSTED'\)/);
  assert.match(core, /status in \('invited', 'requested', 'active', 'rejected', 'cancelled', 'ended'\)/);
  assert.match(core, /TEAM_OWNER_REQUIRED/);
  assert.match(core, /pachanga_club_require_v1\(selected_relationship\.club_id, actor_id, 'team_links_manage'\)/);
  assert.match(core, /pachanga_club_team_relationship_current_idx/);
  assert.doesNotMatch(core, /update public\.pachanga_groups[^;]+owner_id/i);
  assert.doesNotMatch(core, /alter table public\.pachanga_groups[^;]+club_id/i);
});

test("TEAM and CLUB competition organizers use real foreign keys and an XOR constraint", async () => {
  const adapter = await source(migrations[1]);
  for (const table of ["pachanga_competition_organizer_states", "pachanga_competition_entitlement_grants", "pachanga_competitions", "pachanga_competition_invalidations"]) {
    assert.match(adapter, new RegExp(`alter table public\\.${table}`));
  }
  assert.match(adapter, /organizer_club_id uuid references public\.pachanga_clubs\(id\)/);
  assert.match(adapter, /organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null/);
  assert.match(adapter, /organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null/);
  assert.match(adapter, /command_pachanga_competition_foundation_v2/);
  assert.match(adapter, /normalized_kind = 'TEAM'[\s\S]*?command_pachanga_competition_foundation_v1/);
});

test("Club competition creation requires active status, explicit entitlement and the correct Club role", async () => {
  const [adapter, platform] = await Promise.all([source(migrations[1]), source(migrations[2])]);
  assert.match(adapter, /CLUB_MUST_BE_ACTIVE/);
  assert.match(adapter, /selected_role not in \('club_owner', 'club_competition_manager'\)/);
  assert.match(adapter, /COMPETITION_ENTITLEMENT_REQUIRED/);
  assert.match(adapter, /'club_competition_manager'[\s\S]*?'competition_director'/);
  assert.match(platform, /partnershipDoesNotGrantEntitlement/);
  assert.match(platform, /grant_source = 'partnership' and selected_club\.partnership_status <> 'active'/);
  assert.doesNotMatch(platform.match(/command_action = 'club\.partnership\.set'[\s\S]*?elsif command_action in \('club\.entitlement/)?.[0] ?? "", /insert into public\.pachanga_competition_entitlement_grants/);
});

test("all Club writes are idempotent, revisioned, sequenced and auditable", async () => {
  const core = await source(migrations[0]);
  assert.match(core, /operation_id uuid not null unique/);
  assert.match(core, /expected_revision bigint/);
  assert.match(core, /pg_advisory_xact_lock\(hashtextextended\(operation_id::text/);
  assert.match(core, /OPERATION_ID_REUSED/);
  assert.match(core, /STALE_REVISION/);
  assert.match(core, /pachanga_club_operation_receipts/);
  assert.match(core, /pachanga_club_events/);
  assert.match(core, /CLUB_AUDIT_LEDGER_IMMUTABLE/);
  assert.match(core, /before update or delete on private\.pachanga_club_operation_receipts/);
});

test("RLS exposes only scoped invalidations and no direct authenticated writes", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const table of ["pachanga_clubs", "pachanga_club_memberships", "pachanga_club_invitations", "pachanga_club_team_relationships", "pachanga_club_invalidations"]) {
    assert.match(combined, new RegExp(`alter table public\\.${table} enable row level security`));
    assert.match(combined, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
  }
  assert.match(combined, /pachanga_club_can_read_invalidation_v2/);
  assert.match(combined, /alter publication supabase_realtime add table public\.pachanga_club_invalidations/);
  assert.doesNotMatch(combined, /grant (?:insert|update|delete|all) on table public\.pachanga_club[^;]+to (?:anon|authenticated)/i);
});

test("public Club profiles are reduced, gated and never expose staff or exact places", async () => {
  const core = await source(migrations[0]);
  const publicSnapshot = core.match(/create or replace function private\.pachanga_public_club_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(publicSnapshot, /club_public_profiles_enabled/);
  assert.match(publicSnapshot, /clubs\.operational_status = 'active'/);
  assert.match(publicSnapshot, /clubs\.visibility = 'public'/);
  assert.match(publicSnapshot, /generalArea/);
  assert.doesNotMatch(publicSnapshot, /primary_owner_id|memberships|target_email|place_id|website_url/);
  assert.match(publicSnapshot, /limit 100/);
});

test("Club read models are bounded and platform listings are paginated", async () => {
  const [core, adapter, platform] = await Promise.all(migrations.map(source));
  const privateSnapshot = core.match(/create or replace function private\.pachanga_club_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  const myClubs = core.match(/create or replace function public\.get_my_pachanga_club_foundation_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(privateSnapshot, /'memberships', 200/);
  assert.match(privateSnapshot, /'pendingInvitations', 200/);
  assert.match(privateSnapshot, /'teamRelationships', 200/);
  assert.match(myClubs, /limit 50/);
  assert.match(myClubs, /limit 100/);
  assert.match(adapter, /where rows\.organizer_kind = 'CLUB'[\s\S]*?limit 100/);
  assert.match(platform, /bounded_size integer := least\(greatest\(coalesce\(page_size, 50\), 1\), 200\)/);
  assert.match(platform, /offset bounded_offset limit bounded_size/);
});

test("Control Center preserves existing capabilities and adds only the approved Club roles", async () => {
  const platform = await source(migrations[2]);
  assert.match(platform, /platform_owner[\s\S]*?'rankings\.write'[\s\S]*?'competitions\.manage'[\s\S]*?'clubs\.read', 'clubs\.manage'/);
  assert.match(platform, /platform_admin[\s\S]*?'rankings\.write'[\s\S]*?'clubs\.read', 'clubs\.manage'/);
  assert.match(platform, /when 'support'[\s\S]*?'clubs\.read'/);
  for (const role of ["moderator", "finance", "ops"]) {
    const block = platform.match(new RegExp(`when '${role}'[\\s\\S]*?(?=when '|else)`))?.[0] ?? "";
    assert.doesNotMatch(block, /clubs\.(?:read|manage)/);
  }
  assert.match(platform, /search_pachanga_platform_v1/);
  assert.match(platform, /'type', 'club'/);
  assert.doesNotMatch(platform.match(/'type', 'club'[\s\S]*?union all/)?.[0] ?? "", /email|place_id/);
});

test("PWA protects Club writes, records known operations and never treats reads as writes", () => {
  for (const rpc of ["command_pachanga_club_foundation_v1", "command_pachanga_club_platform_v1", "command_pachanga_competition_foundation_v2"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:club-foundation-command"), true);
  assert.equal(isKnownClientWriteOperation("api:platform-admin-clubs"), true);
  assert.equal(classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/get_my_pachanga_club_foundation_v1", { method: "POST" }), null);
});

test("Club UI caches only read models and refetches after scoped Realtime invalidation", async () => {
  const [lab, labStyles, route, publicLayout, publicStyles, adminPage] = await Promise.all([
    source("app/laboratorio-club-foundation/page.tsx"),
    source("app/laboratorio-club-foundation/page.module.css"),
    source("app/api/clubs/command/route.ts"),
    source("app/clubes/[slug]/layout.tsx"),
    source("app/clubes/[slug]/public-club.module.css"),
    source("app/admin/clubs/page.tsx"),
  ]);
  assert.match(lab, /pachangas-club-foundation-read-v1/);
  assert.match(lab, /get_my_pachanga_club_foundation_v1/);
  assert.match(lab, /pachanga_club_invalidations/);
  assert.match(lab, /loadCanonical\(actorId, "realtime"\)/);
  assert.match(lab, /clientWriteFetch\("api:club-foundation-command"/);
  for (const action of [
    "club.primary_owner.transfer",
    "team_relationship.request",
    "team_relationship.cancel",
    "membership.accept",
    "competition.create",
  ]) assert.match(lab, new RegExp(action.replaceAll(".", "\\.")));
  assert.match(lab, /get_pachanga_club_invitation_v1/);
  assert.match(lab, /\/admin\/clubs\?club=/);
  assert.match(lab, /window\.location\.hash/);
  assert.doesNotMatch(lab, /\.from\("pachanga_club[^\"]+"\)\.(?:insert|update|delete)/);
  assert.doesNotMatch(lab, /setData\([^)]*payload\.new/);
  assert.match(route, /platformUserClient\(token\)/);
  assert.doesNotMatch(route, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(publicLayout, /robots: \{ follow: false, index: false \}/);
  assert.match(adminPage, /requirePlatformPage\("clubs\.read"\)/);
  for (const inset of ["top", "right", "bottom", "left"]) {
    assert.match(labStyles, new RegExp(`env\\(safe-area-inset-${inset}\\)`));
    assert.match(publicStyles, new RegExp(`env\\(safe-area-inset-${inset}\\)`));
  }
});

test("the generic Control Center read model understands both organizer kinds", async () => {
  const [platform, data, page] = await Promise.all([
    source(migrations[2]),
    source("app/admin/_lib/platform-data.ts"),
    source("app/admin/competitions/page.tsx"),
  ]);
  assert.match(platform, /get_pachanga_platform_competition_foundation_v2/);
  assert.match(platform, /left join public\.pachanga_clubs clubs/);
  assert.match(platform, /'organizerKind', selected\.organizer_kind/);
  assert.match(data, /get_pachanga_platform_competition_foundation_v2/);
  assert.match(page, /organizerKind/);
});

test("authoritative entitlement reads use one materialized server clock", async () => {
  const [adapter, platform] = await Promise.all([source(migrations[1]), source(migrations[2])]);
  assert.match(adapter, /with authority_time as materialized \(\s*select clock_timestamp\(\) as checked_at/);
  assert.match(platform, /authority_time timestamptz := clock_timestamp\(\)/);
  assert.doesNotMatch(adapter, /created_at\s+desc\s+limit\s+1/i);
});

test("authenticated staging QA covers the complete R2 story and restores all flags", async () => {
  const staging = await source("tests/club-foundation-v1-staging-e2e.mjs");
  for (const action of [
    "club.create",
    "club.profile.update",
    "club.review.submit",
    "membership.invite",
    "membership.accept",
    "membership.revoke",
    "club.primary_owner.transfer",
    "team_relationship.invite",
    "team_relationship.request",
    "team_relationship.accept",
    "team_relationship.reject",
    "team_relationship.cancel",
    "team_relationship.end",
    "club.entitlement.grant",
    "club.entitlement.revoke",
    "competition.create",
  ]) assert.match(staging, new RegExp(action.replaceAll(".", "\\.")));
  assert.match(staging, /pachanga_club_invalidations/);
  assert.match(staging, /CLUB_INVITATION_TOKEN_INVALID/);
  assert.match(staging, /CLUB_INVITATION_EMAIL_MISMATCH/);
  assert.match(staging, /CLUB_MUST_BE_ACTIVE/);
  assert.match(staging, /COMPETITION_ENTITLEMENT_REQUIRED/);
  assert.match(staging, /foundationEnabled: false/);
  assert.match(staging, /teamRelationshipsEnabled: false/);
  assert.match(staging, /archiveFixtureClub/);
});

test("R2 leaves Rating, Demo World and later competition engines untouched", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const table of ["pachanga_player_profiles", "pachanga_player_rating_votes", "pachanga_match_rating_snapshots", "pachanga_season_score_snapshots"]) {
    assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.)?${table}`, "i"));
  }
  assert.doesNotMatch(combined, /demo.world|simulation\.synthetic/i);
  assert.doesNotMatch(combined, /fixture_generator|generate_matchday|competition_standings|referee_assignment/i);
});
