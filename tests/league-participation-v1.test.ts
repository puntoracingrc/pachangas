import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";
import { leagueParticipationActions } from "../app/league-participation-contract";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260822192941_league_participation_access_v1.sql",
  clubEntitlementBridge: "supabase/migrations/20260822193624_club_competition_rule_entitlement_bridge_v1.sql",
  clubManageEntitlementBridge: "supabase/migrations/20260822194325_club_competition_manage_entitlement_bridge_v1.sql",
  commands: "supabase/migrations/20260822192935_league_participation_commands_v1.sql",
  ownerScopePrecedence: "supabase/migrations/20260822195054_league_team_owner_scope_precedence_v1.sql",
  schema: "supabase/migrations/20260822192929_league_participation_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R4A creates generic participation authorities without creating the League schedule engine", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_categories",
    "pachanga_competition_entries",
    "pachanga_competition_entry_invitations",
    "pachanga_competition_team_delegates",
    "pachanga_competition_stage_memberships",
    "pachanga_competition_rosters",
    "pachanga_competition_roster_revisions",
    "pachanga_competition_roster_members",
    "pachanga_player_competition_credentials",
    "pachanga_competition_eligibility_waivers",
    "pachanga_competition_team_kits",
    "pachanga_competition_player_jersey_numbers",
    "pachanga_team_availability_constraints",
    "pachanga_team_schedule_preferences",
  ]) assert.match(schema, new RegExp(`create table if not exists (?:public|private)\\.${table}`));
  assert.doesNotMatch(schema, /create table[^;]+(?:competition_rounds|league_fixtures|competition_standings|match_squads|temporary_player)/i);
  assert.doesNotMatch(schema, /round_robin|fixture_generator|calculate_standings/i);
});

test("all six R4A flags are off by default and preserve dependency constraints", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "league_participation_foundation_enabled",
    "league_registration_enabled",
    "league_public_registration_enabled",
    "league_delegates_enabled",
    "league_rosters_enabled",
    "league_schedule_preferences_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /not league_public_registration_enabled or league_registration_enabled/);
  assert.match(schema, /not league_rosters_enabled or league_registration_enabled/);
});

test("the command envelope is authenticated, idempotent, revisioned and LEAGUE-only", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /operation_id uuid[\s\S]+aggregate_id uuid[\s\S]+expected_revision bigint[\s\S]+command_action text[\s\S]+client_metadata jsonb/);
  assert.match(commands, /actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(commands, /pg_advisory_xact_lock\(hashtextextended\(operation_id::text/);
  assert.match(commands, /pachanga_competition_replay_v1/);
  assert.match(commands, /IDEMPOTENCY_KEY_REUSED|pachanga_competition_request_hash_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /using errcode = 'PT409'/);
  assert.match(commands, /competition_type <> 'LEAGUE'[\s\S]+FEATURE_NOT_AVAILABLE/);
  assert.match(commands, /edition\.scheduled[\s\S]+edition\.active[\s\S]+edition\.completed/);
});

test("Club-organized competitions publish rules through the organizer-aware entitlement bridge", async () => {
  const [bridge, managementBridge] = await Promise.all([
    source(paths.clubEntitlementBridge),
    source(paths.clubManageEntitlementBridge),
  ]);
  assert.match(bridge, /command_pachanga_competition_foundation_v1/);
  assert.match(bridge, /pachanga_competition_active_entitlement_v2/);
  assert.match(bridge, /competition_row\.organizer_kind/);
  assert.match(bridge, /coalesce\(competition_row\.organizer_group_id, competition_row\.organizer_club_id\)/);
  assert.match(bridge, /occurrence_count <> 1/);
  assert.match(managementBridge, /command_pachanga_club_platform_v1/);
  assert.match(managementBridge, /'competition_create', 'competition_manage'/);
  assert.match(managementBridge, /grants\.capability = trim\(command_payload ->> 'capability'\)/);
  assert.match(managementBridge, /CLUB_MANAGE_ENTITLEMENT_PATCH_BASE_MISMATCH/);
});

test("the implemented lifecycle covers categories, registration, entries, delegates, rosters and stage memberships", async () => {
  const combined = `${await source(paths.schema)}\n${await source(paths.commands)}`;
  for (const action of leagueParticipationActions) assert.match(combined, new RegExp(action.replaceAll(".", "\\.")));
  for (const status of ["draft", "active", "closed", "archived"]) assert.match(combined, new RegExp(`'${status}'`));
  for (const status of ["submitted", "invited", "accepted", "rejected", "withdrawn", "declined", "expired"]) assert.match(combined, new RegExp(`'${status}'`));
  for (const status of ["changes_requested", "approved", "locked", "amended"]) assert.match(combined, new RegExp(`'${status}'`));
  assert.match(combined, /PUBLIC_APPROVAL/);
  assert.match(combined, /INVITE_ONLY/);
  assert.match(combined, /PRIVATE_CODE[\s\S]+AUTO_ACCEPT/);
  assert.match(combined, /REGISTRATION_MODE_NOT_AVAILABLE/);
});

test("team authority remains owner-first and delegates stay scoped to one accepted entry", async () => {
  const [commands, ownerScopePrecedence] = await Promise.all([
    source(paths.commands),
    source(paths.ownerScopePrecedence),
  ]);
  assert.match(commands, /pachanga_league_assert_team_owner_v1/);
  assert.match(commands, /groups\.owner_id = target_actor_id/);
  assert.match(commands, /scope not in \('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER'\)/);
  assert.match(commands, /delegates\.entry_id = target_entry_id/);
  assert.match(commands, /where delegates\.entry_id = entry_row\.id/);
  assert.match(commands, /TARGET_DELEGATE_ALREADY_PRIMARY/);
  assert.match(commands, /replaced_by_delegate_id = created_id/);
  assert.doesNotMatch(commands, /update public\.pachanga_group_members[^;]+delegate/i);
  assert.doesNotMatch(commands, /update public\.pachanga_club_memberships[^;]+delegate/i);
  assert.ok(
    ownerScopePrecedence.indexOf("return 'TEAM_OWNER'")
      < ownerScopePrecedence.indexOf("return 'ORGANIZER'"),
  );
});

test("rosters preserve immutable revisions and react safely when a player leaves the team", async () => {
  const [schema, commands] = await Promise.all([source(paths.schema), source(paths.commands)]);
  assert.match(schema, /ROSTER_REVISION_IMMUTABLE/);
  assert.match(schema, /before update or delete on public\.pachanga_competition_roster_revisions/);
  assert.match(commands, /pachanga_league_clone_roster_revision_v1/);
  assert.match(commands, /pachanga_league_roster_checksum_v1/);
  assert.match(commands, /mark_departed_competition_roster_members_v1/);
  assert.match(commands, /eligibility\.team_membership_ended/);
  assert.match(commands, /review_required/);
  assert.doesNotMatch(schema, /foreign key \(source_group_id, source_user_id\)[\s\S]+pachanga_group_members/);
});

test("eligibility is server-calculated while credential evidence stays private", async () => {
  const [schema, commands, access] = await Promise.all([source(paths.schema), source(paths.commands), source(paths.access)]);
  assert.match(commands, /pachanga_league_member_eligibility_v1/);
  assert.match(commands, /age_at_reference/);
  assert.match(commands, /PLAYER_MULTI_TEAM_CONFLICT/);
  assert.match(commands, /FORBIDDEN_SAME_EDITION_CATEGORY/);
  assert.match(commands, /credential\.review/);
  assert.match(commands, /eligibility\.waive/);
  assert.match(schema, /private\.pachanga_competition_credential_evidence/);
  assert.doesNotMatch(access, /evidence_reference|evidenceReference/);
  assert.doesNotMatch(access, /birth_date|email/);
});

test("canonical reads expose next actions, warnings, limits and stable pagination without private evidence", async () => {
  const access = await source(paths.access);
  for (const rpc of [
    "get_pachanga_league_public_registration_v1",
    "get_my_pachanga_competition_entries_v1",
    "get_pachanga_competition_registration_desk_v1",
    "get_pachanga_competition_entry_v1",
    "get_pachanga_competition_roster_v1",
    "get_pachanga_platform_league_participation_v1",
  ]) assert.match(access, new RegExp(`create or replace function public\\.${rpc}`));
  assert.match(access, /'teamLimits'/);
  assert.match(access, /'nextValidAction'/);
  assert.match(access, /'pendingActions'/);
  assert.match(access, /'warningCount'/);
  assert.match(access, /page_offset integer/);
  assert.match(access, /page_size integer/);
  assert.match(access, /server_sequence desc, [^\n]*id desc/);
  assert.doesNotMatch(access, /evidence_reference|reason_text_private[^\n]+public/i);
});

test("Realtime only invalidates scoped canonical reads and never rebuilds state from WAL", async () => {
  const [access, client] = await Promise.all([
    source(paths.access),
    source("app/_components/league-participation-client.tsx"),
  ]);
  assert.match(access, /pachanga_league_can_read_invalidation_v1/);
  assert.match(access, /entries\.team_id = target_group_id/);
  assert.match(access, /target_user_id = actor_id/);
  assert.match(client, /invalidationMatches/);
  assert.match(client, /loadCanonical\(token, actorId, "realtime"\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
  assert.match(client, /Read caching is optional and never authoritative/);
});

test("R4A writes are PWA protected and offline state is never presented as confirmed", async () => {
  for (const rpc of ["command_pachanga_league_participation_v1", "command_pachanga_league_participation_platform_v1"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:league-participation-command"), true);
  const client = await source("app/_components/league-participation-client.tsx");
  assert.match(client, /Esperando confirmación del servidor/);
  assert.match(client, /Cambio confirmado por PostgreSQL/);
  assert.match(client, /clientWriteFetch\("api:league-participation-command"/);
  assert.doesNotMatch(client, /localStorage\.setItem[^\n]+(?:entry|roster|credential)/i);
});

test("the API accepts only whitelisted semantic payloads and never exposes service authority", async () => {
  const [shared, commandRoute] = await Promise.all([
    source("app/api/competitions/participation/_shared.ts"),
    source("app/api/competitions/participation/command/route.ts"),
  ]);
  assert.match(commandRoute, /requireLeagueOrigin/);
  assert.match(commandRoute, /leagueWriteGate/);
  assert.match(commandRoute, /leagueCommandPayload/);
  assert.match(shared, /clientVersion/);
  assert.doesNotMatch(`${shared}\n${commandRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  assert.match(shared, /if \(action === "entry\.submit" \|\| action === "entry\.invite"\)[\s\S]+teamId: uuid\(input, "teamId"\)/);
  assert.match(shared, /if \(!leagueUuidPattern\.test\(value\)\) throw new Error\("INVALID_LEAGUE_COMMAND"\)/);
  assert.doesNotMatch(shared, /actorId|actor_id|submittedBy|verifiedBy/);
});

test("Official UI V2 surfaces are noindex, gated and distinguish hard constraints from preferences", async () => {
  const [client, css, labLayout, mainPage, mobileNav, visualAudit] = await Promise.all([
    source("app/_components/league-participation-client.tsx"),
    source("app/_components/league-participation-client.module.css"),
    source("app/laboratorio-league-participation/layout.tsx"),
    source("app/page.tsx"),
    source("app/mobile-app-nav.tsx"),
    source("scripts/visual-audit-v1.mjs"),
  ]);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /NO PUEDO JUGAR/);
  assert.match(client, /PREFERIRÍA JUGAR/);
  assert.match(css, /data-kind="soft"/);
  assert.match(css, /orientation: landscape/);
  assert.match(labLayout, /follow: false, index: false/);
  assert.doesNotMatch(mainPage, /laboratorio-league-participation/);
  assert.doesNotMatch(mobileNav, /laboratorio-league-participation/);
  for (const surface of ["index", "public", "mine", "desk", "entry", "roster"]) {
    assert.match(visualAudit, new RegExp(`lab-league-${surface}`));
  }
});

test("the visual audit requires real standalone display mode and Service Worker control", async () => {
  const visualAudit = await source("scripts/visual-audit-v1.mjs");
  assert.match(visualAudit, /VISUAL_AUDIT_APP_MODE/);
  assert.match(visualAudit, /displayMode !== "standalone"/);
  assert.match(visualAudit, /!result\.metrics\.serviceWorkerControlled/);
});

test("Control Center extends the existing competitions surface and does not create a parallel admin", async () => {
  const [page, route] = await Promise.all([
    source("app/admin/competitions/page.tsx"),
    source("app/api/platform-admin/competitions/route.ts"),
  ]);
  assert.match(page, /League Participation/);
  assert.match(page, /eligibilityWarnings/);
  assert.match(page, /duplicateConflicts/);
  assert.match(route, /command_pachanga_league_participation_platform_v1/);
  assert.match(route, /clientWriteGateResponse/);
});

test("R4A migrations do not mutate Rating, matches, results, discipline, rewards, conduct, billing or ranking", async () => {
  const combined = `${await source(paths.schema)}\n${await source(paths.commands)}\n${await source(paths.access)}`;
  for (const table of [
    "pachanga_player_rating_snapshots",
    "pachanga_individual_rating_evidence",
    "pachanga_match_participants",
    "pachanga_match_scorers",
    "pachanga_external_results",
    "pachanga_disciplinary_events",
    "pachanga_reward_grants",
    "pachanga_conduct_reports",
    "pachanga_stripe_webhook_events",
    "pachanga_provincial_ranking_entries",
  ]) assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.|private\\.)?${table}`, "i"));
  assert.doesNotMatch(combined, /CRON_SECRET|canonical\.backfill|stripe_products|stripe_prices/i);
});

test("multi-team validation serializes competing roster writes across every current roster state", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /pg_advisory_xact_lock\(hashtextextended\([\s\S]+league-roster-player:[\s\S]+91406/);
  assert.match(commands, /rosters\.status in \([\s\S]*'draft'[\s\S]*'submitted'[\s\S]*'approved'[\s\S]*'locked'[\s\S]*'changes_requested'[\s\S]*'amended'[\s\S]*\)/);
});

test("canonical latest-state reads use monotonic sequence plus a stable identifier", async () => {
  const combined = `${await source(paths.commands)}\n${await source(paths.access)}`;
  assert.doesNotMatch(combined, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|\)|;|$)/i);
  for (const pattern of [
    /order by editions\.server_sequence desc, editions\.id desc/,
    /order by entries\.server_sequence desc, entries\.id desc/,
    /order by events\.server_sequence desc, events\.id desc/,
    /order by memberships\.server_sequence desc, memberships\.id desc/,
  ]) assert.match(combined, pattern);
});

test("bootstrap, concurrency, scale and staging harnesses remain explicit R4A gates", async () => {
  const [bootstrap, concurrency, scale, staging, packageJson] = await Promise.all([
    source("tests/league-participation-v1-bootstrap.mjs"),
    source("tests/league-participation-v1-concurrency.mjs"),
    source("tests/league-participation-v1-scale.sql"),
    source("tests/league-participation-v1-staging-e2e.mjs"),
    source("package.json"),
  ]);
  assert.match(bootstrap, /upgradeFromLedger: 113/);
  assert.match(bootstrap, /schemasEqual: true/);
  assert.match(concurrency, /multiTeamLock/);
  assert.match(scale, /150000/);
  assert.match(staging, /R4A_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(packageJson, /test:league-participation:bootstrap/);
});

test("staging cleanup revokes and cancels tagged fixtures through canonical commands", async () => {
  const staging = await source("tests/league-participation-v1-staging-e2e.mjs");
  assert.match(staging, /revokeTaggedQaCredentials/);
  assert.match(staging, /credential\.review/);
  assert.match(staging, /cancelTaggedQaCompetitions/);
  assert.match(staging, /competition\.cancel/);
  assert.doesNotMatch(staging, /from\("pachanga_player_competition_credentials"\)[\s\S]{0,240}\.update\(/);
});
