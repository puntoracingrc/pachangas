import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrationPaths = [
  "supabase/migrations/20260824101500_clubs_referees_beta_publication_consent_schema_v1.sql",
  "supabase/migrations/20260824101501_clubs_referees_beta_authority_v1.sql",
  "supabase/migrations/20260824101502_clubs_referees_beta_read_models_notifications_v1.sql",
  "supabase/migrations/20260824101503_referee_restore_private_v1.sql",
] as const;
async function source(path: string) { return readFile(new URL(path, root), "utf8"); }

test("publication consent is append-only, actor-bound and tied to canonical public content", async () => {
  const [schema, authority] = await Promise.all(migrationPaths.slice(0, 2).map(source));
  assert.match(schema, /create table if not exists private\.pachanga_publication_consents/);
  assert.match(schema, /operation_id uuid not null unique/);
  assert.match(schema, /content_fingerprint text not null/);
  assert.match(schema, /'availableForAssignments', profiles\.available_for_assignments/);
  assert.match(schema, /before update or delete on private\.pachanga_publication_consents/);
  assert.match(schema, /order by consents\.server_sequence desc, consents\.id desc/);
  assert.match(authority, /CLUB_PRIMARY_OWNER_REQUIRED/);
  assert.match(authority, /REFEREE_PROFILE_OWNER_REQUIRED/);
  assert.match(authority, /CLUB_PUBLICATION_CONSENT_REQUIRED/);
  assert.match(authority, /REFEREE_PUBLICATION_CONSENT_REQUIRED/);
  assert.match(authority, /CLUB_APPROVAL_REQUIRES_PENDING_REVIEW/);
  assert.match(authority, /CLUB_PUBLICATION_PAUSE_REQUIRED/);
  assert.match(authority, /REFEREE_PUBLICATION_PAUSE_REQUIRED/);
  assert.match(authority, /before update of operational_status, marketplace_status, visibility, slug,[\s\S]*?available_for_assignments/);
  assert.match(authority, /REFEREE_RELATIONSHIP_CLUB_NOT_ACTIVE/);
});

test("server authority rate limits risky Club and referee actions without breaking idempotent replay", async () => {
  const authority = await source(migrationPaths[1]);
  assert.match(authority, /pachanga_club_rate_limit_v1/);
  assert.match(authority, /membership\.invite'[\s\S]*?20/);
  assert.match(authority, /team_relationship\.%'[\s\S]*?30/);
  assert.match(authority, /pachanga_referee_rate_limit_v1/);
  assert.match(authority, /relationship\.%'[\s\S]*?30/);
  assert.match(authority, /command_pachanga_referee_platform_v1_pre_beta/);
  assert.match(authority, /referee-rate-limit:/);
  assert.match(authority, /club-rate-limit:/);
  assert.match(authority, /CLUB_NOT_ACTIVE/);
  assert.match(authority, /command_action in \('relationship\.invite', 'relationship\.request'\)[\s\S]*?operational_status = 'active'/);
  assert.match(authority, /if not exists \([\s\S]*?pachanga_club_operation_receipts[\s\S]*?perform private\.pachanga_club_rate_limit_v1/);
  assert.match(authority, /replay := private\.pachanga_referee_replay_v1[\s\S]*?if replay is null then[\s\S]*?pachanga_referee_rate_limit_v1/);
});

test("a suspended referee with stale publication evidence restores privately", async () => {
  const restore = await source(migrationPaths[3]);
  assert.match(restore, /old\.operational_status = 'suspended'/);
  assert.match(restore, /new\.operational_status = 'active'/);
  assert.match(restore, /new\.visibility := 'private'/);
  assert.match(restore, /old\.operational_status = 'suspended'[\s\S]*?new\.visibility = 'private'[\s\S]*?pachanga_publication_consent_valid_v1/);
  assert.match(restore, /create or replace function private\.pachanga_referee_publication_guard_v1/);
  assert.doesNotMatch(restore, /marketplace_status\s*:=\s*'listed'|available_for_assignments\s*:=\s*true/i);
});

test("public Club directory is paginated, flag-gated and privacy reduced", async () => {
  const reads = await source(migrationPaths[2]);
  const directory = reads.match(/create or replace function public\.search_pachanga_public_clubs_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(directory, /club_foundation_enabled and settings\.club_public_profiles_enabled/);
  assert.match(directory, /clubs\.operational_status = 'active'/);
  assert.match(directory, /clubs\.visibility = 'public'/);
  assert.match(directory, /safe_page_size integer := least\(60/);
  assert.match(directory, /'enabled', false/);
  assert.match(directory, /'enabled', true/);
  assert.doesNotMatch(directory, /email|phone|primary_owner_id|target_user_id|target_email|entitlement/i);
});

test("private beta read models expose choices and relationships without Auth identity or invitation secrets", async () => {
  const reads = await source(migrationPaths[2]);
  const relationships = reads.match(/create or replace function private\.pachanga_club_referee_relationships_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(relationships, /refereeProfileId/);
  assert.match(relationships, /refereeName/);
  assert.doesNotMatch(relationships, /target_user_id|created_by|target_email|token_hash/);
  assert.match(reads, /'ownedTeams'/);
  assert.match(reads, /'teamCandidates'/);
  assert.match(reads, /'refereeManage'/);
  assert.match(reads, /\/perfil\/arbitro\?section=clubs/);
  assert.match(reads, /new\.kind = 'referee_club_invitation'[\s\S]*?'\/perfil\/arbitro\?section=clubs'/);
  assert.match(reads, /relationship_initiated_by = 'CLUB'[\s\S]*?'\/clubes\/gestionar\?club='/);
  const candidates = reads.match(/create or replace function private\.pachanga_club_team_candidates_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "";
  assert.match(candidates, /pachanga_challengeable_team_profiles/);
  assert.doesNotMatch(candidates, /zone_lat|zone_lng|place_id|owner_id|created_by|updated_by/);
});

test("product APIs enforce PWA write gating and never use service role", async () => {
  const [clubRoute, refereeRoute, clubRead, directoryRead] = await Promise.all([
    source("app/api/clubs/command/route.ts"),
    source("app/api/referees/command/route.ts"),
    source("app/api/clubs/me/route.ts"),
    source("app/api/clubs/directory/route.ts"),
  ]);
  assert.match(clubRoute, /clientWriteGateResponse\(request\)/);
  assert.match(refereeRoute, /refereeWriteGate\(request\)/);
  assert.match(clubRoute, /command_pachanga_publication_consent_v1/);
  assert.match(refereeRoute, /command_pachanga_publication_consent_v1/);
  assert.match(clubRoute, /command_pachanga_club_referee_invite_by_profile_v1/);
  for (const contents of [clubRoute, refereeRoute, clubRead, directoryRead]) assert.doesNotMatch(contents, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
});

test("Official UI beta surfaces reuse the same canonical directories and hide referee assignments while OFF", async () => {
  const [clubDirectory, clubManager, refereeProfile, refereeMarket, market] = await Promise.all([
    source("app/clubes/club-directory-client.tsx"),
    source("app/clubes/gestionar/club-manager-client.tsx"),
    source("app/_components/referee-platform-client.tsx"),
    source("app/mercado/referee-marketplace-panel.tsx"),
    source("app/mercado/page.tsx"),
  ]);
  for (const contents of [clubDirectory, clubManager, refereeProfile, refereeMarket]) assert.match(contents, /BETA/);
  assert.match(clubDirectory, /\/api\/clubs\/directory/);
  assert.match(clubManager, /\/api\/clubs\/me/);
  assert.match(clubManager, /pachanga_club_invalidations/);
  assert.match(clubManager, /team_relationship\.cancel/);
  assert.match(clubManager, /referee_relationship\.cancel/);
  assert.match(clubManager, /kind: action === "referee_relationship\.invite" \? "referee" : "staff"/);
  assert.match(clubManager, /externalInvitation\.id === text\(item\.id\)/);
  assert.match(clubManager, /CLUB_PUBLICATION_PAUSE_REQUIRED/);
  assert.match(refereeProfile, /publication\.consent/);
  assert.match(refereeProfile, /REFEREE_PUBLICATION_PAUSE_REQUIRED/);
  assert.match(refereeProfile, /relationship\.cancel/);
  assert.match(refereeProfile, /flags\.assignmentsEnabled === true/);
  assert.match(refereeMarket, /assignmentsEnabled \?/);
  assert.match(refereeMarket, /marketplaceEnabled/);
  assert.match(refereeMarket, /Crear mi ficha de árbitro/);
  assert.match(refereeMarket, /<select name="club">/);
  assert.doesNotMatch(refereeMarket, /placeholder="ID del Club"/);
  assert.match(market, /id: "clubes"/);
  assert.match(market, /selfServiceCreationEnabled/);
  assert.match(market, /selfServiceEnabled/);
  assert.match(market, /refereeProductEnabled/);
  assert.match(market, /clubProductEnabled/);
  assert.match(market, /value === "arbitros"[\s\S]*?value === "clubes"/);
  assert.match(market, /<ClubDirectoryClient directoryEnabled=\{clubDirectoryEnabled\} embedded/);
});

test("SEO is indexable only from canonical public read models", async () => {
  const [clubDirectoryPage, clubPage, refereePage, publicData] = await Promise.all([
    source("app/clubes/page.tsx"),
    source("app/clubes/[slug]/page.tsx"),
    source("app/arbitros/[slug]/page.tsx"),
    source("app/public-product-data.ts"),
  ]);
  assert.match(clubDirectoryPage, /robots: \{ follow: enabled, index: enabled \}/);
  assert.match(clubPage, /robots: \{ follow: Boolean\(club\), index: Boolean\(club\) \}/);
  assert.match(refereePage, /robots: \{ follow: Boolean\(profile\), index: Boolean\(profile\) \}/);
  assert.match(publicData, /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/);
  assert.doesNotMatch(publicData, /SERVICE_ROLE/);
});

test("new authoritative writes are classified by the PWA bridge", () => {
  for (const rpc of ["command_pachanga_publication_consent_v1", "command_pachanga_club_referee_invite_by_profile_v1"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:club-foundation-command"), true);
  assert.equal(isKnownClientWriteOperation("api:referee-command"), true);
});

test("Wave 1 does not activate competitions, assignments, Rating or canonical backfill", async () => {
  const combined = (await Promise.all(migrationPaths.map(source))).join("\n");
  for (const target of ["pachanga_player_rating_votes", "pachanga_player_rating_snapshots", "pachanga_match_rating_snapshots", "pachanga_season_score_snapshots"]) {
    assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.)?${target}`, "i"));
  }
  assert.doesNotMatch(combined, /canonical\.backfill|referee_assignments_enabled\s*=\s*true|club_competition_organizer_enabled\s*=\s*true/i);
});
