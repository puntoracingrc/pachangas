import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { DEMO_SOCIAL_FIRST_TIME_STORIES } from "../app/demo-world/demo-social-first-time-contract";
import { PRODUCT_PRIMARY_DESTINATIONS } from "../app/_components/product-navigation-contract";
import { knownClientWriteRpcNames } from "../app/pwa-write-classifier";
import {
  normalizeCanonicalSocialProfile,
  normalizeSocialTeamFlags,
  normalizeSocialTeamHome,
  normalizeSocialTeamInvitation,
  normalizeSocialTeamRoster,
  socialProfileCacheKey,
  socialTeamCacheKey,
} from "../app/social-team-core-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("V3F normalizes canonical profile, flags and team read models", () => {
  const profile = normalizeCanonicalSocialProfile({
    approximateTime: "20:00-22:00",
    avatarRef: "/avatar.png",
    confirmedRevision: 2,
    displayName: "Alex Demo",
    generalArea: "Gràcia",
    preferredModality: "futbol7",
    primaryPosition: "Pivote",
    revision: 2,
    serverSequence: 42,
    updatedAt: "2026-09-01T20:00:00Z",
    usualDays: ["M", "J"],
  });
  assert.equal(profile?.displayName, "Alex Demo");
  assert.equal(profile?.revision, 2);
  assert.deepEqual(profile?.usualDays, ["M", "J"]);

  const flags = normalizeSocialTeamFlags({
    confirmedRevision: 1,
    demoSocialTeamJourneyEnabled: true,
    serverSequence: 10,
    socialProfileFoundationEnabled: true,
    socialProfileIndependentWriteEnabled: true,
    socialTeamCreationEnabled: true,
    socialTeamHomeV3fEnabled: true,
    socialTeamInvitationV2Enabled: true,
    socialTeamMembershipV2Enabled: true,
    updatedAt: "2026-09-01T20:00:00Z",
  });
  assert.equal(flags?.socialTeamHomeV3fEnabled, true);

  const home = normalizeSocialTeamHome({
    actions: { canCreateMatch: true, canInvitePlayers: true },
    activeInvitationCount: 1,
    generalArea: "Barcelona",
    groupId: "group-demo",
    memberCount: 2,
    modality: "futbol7",
    name: "Cobalto Social",
    operationalStatus: "ACTIVE",
    revision: 3,
    role: "owner",
    serverSequence: 50,
    teamCode: "PIQDEMO",
  });
  assert.equal(home?.role, "owner");
  assert.equal(home?.actions.canInvitePlayers, true);
});

test("V3F roster and invitation normalizers omit private authority fields", () => {
  const roster = normalizeSocialTeamRoster([{
    authUserId: "must-not-survive",
    avatarRef: null,
    displayName: "Jugador Demo",
    email: "private@example.test",
    joinedAt: "2026-09-01T20:00:00Z",
    memberKey: "opaque-member-key-000001",
    phone: "+34000000000",
    preferredModality: "futbol7",
    primaryPosition: "Defensa",
    role: "player",
  }]);
  assert.deepEqual(Object.keys(roster[0]).sort(), [
    "avatarRef", "displayName", "isCurrentUser", "joinedAt", "memberKey",
    "preferredModality", "primaryPosition", "role",
  ]);

  const invitation = normalizeSocialTeamInvitation({
    createdAt: "2026-09-01T20:00:00Z",
    createdByName: "Admin Demo",
    expiresAt: "2026-09-08T20:00:00Z",
    groupId: "group-demo",
    invitationId: "invite-demo",
    revision: 1,
    shareToken: "must-not-survive",
    state: "ACTIVE",
    tokenHash: "must-not-survive",
  });
  assert.ok(invitation);
  assert.equal("shareToken" in invitation, false);
  assert.equal("tokenHash" in invitation, false);
});

test("V3F profile and team commands are classified as authoritative writes", () => {
  const writes = knownClientWriteRpcNames();
  for (const rpc of [
    "command_pachanga_social_profile_v1",
    "command_pachanga_social_team_settings_v1",
    "command_pachanga_social_team_v1",
    "command_pachanga_team_membership_request_v1",
    "command_pachanga_team_player_invitation_v2",
  ]) assert.ok(writes.includes(rpc));
});

test("V3F onboarding sends intentions and reads back canonical state", async () => {
  const [page, onboarding] = await Promise.all([
    source("app/page.tsx"),
    source("app/_components/social-onboarding.tsx"),
  ]);
  assert.match(page, /command_pachanga_social_profile_v1/);
  assert.match(page, /command_pachanga_social_team_v1/);
  assert.match(page, /command_pachanga_team_player_invitation_v2/);
  assert.match(page, /lookup_pachanga_social_team_code_v1/);
  assert.match(page, /await loadTeams\(supabase, team\.groupId\)/);
  assert.match(page, /window\.location\.replace\(`\/equipo\?team=/);
  assert.doesNotMatch(page, /rpc\("join_pachanga_team"/);
  assert.match(onboarding, /writeAvailability\.label/);
  assert.match(onboarding, /Crear equipo/);
  assert.match(onboarding, /Equipo encontrado\. Envía una solicitud para que un admin la revise/);
});

test("V3F team pages use canonical read models, cache only reads and refetch on invalidation", async () => {
  const [team, homePage, rosterPage, invitationPage] = await Promise.all([
    source("app/equipo/social-team-client.tsx"),
    source("app/equipo/page.tsx"),
    source("app/equipo/plantilla/page.tsx"),
    source("app/equipo/invitaciones/page.tsx"),
  ]);
  for (const rpc of [
    "get_my_pachanga_social_teams_v1",
    "get_pachanga_social_team_home_v1",
    "get_pachanga_team_players_v1",
    "get_pachanga_social_team_invitations_v2",
  ]) assert.match(team, new RegExp(rpc));
  assert.match(team, /pachanga_social_invalidations_v1/);
  assert.match(team, /nextStatus === "SUBSCRIBED"/);
  assert.match(team, /Sin conexión: puedes consultar la copia confirmada, pero no modificarla/);
  assert.match(team, /writeJson\(socialTeamCacheKey/);
  assert.doesNotMatch(team, /localStorage\.setItem\([^\n]*(shareToken|freshShareUrl)/);
  assert.match(homePage, /surface="home"/);
  assert.match(rosterPage, /surface="roster"/);
  assert.match(invitationPage, /surface="invitations"/);
});

test("V3F team role controls allow owner and admin while keeping players read-only", async () => {
  const team = await source("app/equipo/social-team-client.tsx");
  assert.match(team, /selected\.role === "owner" \|\| selected\.role === "admin"/);
  assert.match(team, /home\.actions\.canInvitePlayers/);
  assert.match(team, /Solo para administradores/);
  assert.match(team, /data-admin-only="invitations"/);
  assert.match(team, /cada persona entrará únicamente como jugador/);
  assert.match(team, /team\.invitation\.create/);
  assert.match(team, /team\.invitation\.revoke/);
});

test("V3F invitations present the reusable team link before individual links and the non-authoritative code", async () => {
  const team = await source("app/equipo/social-team-client.tsx");
  const sharedPosition = team.indexOf("Enlace del equipo");
  const individualPosition = team.indexOf("Invitación individual");
  const codePosition = team.indexOf("Código del equipo");
  assert.ok(sharedPosition >= 0 && individualPosition > sharedPosition && codePosition > individualPosition);
  assert.match(team, /Crear enlace para compartir/);
  assert.match(team, /Crear enlace de un solo uso/);
  assert.match(team, /maxUses: inviteMode === "TEAM_LINK" \? 100 : 1/);
  assert.match(team, /Identifica al equipo, pero no permite unirse/);
  assert.match(team, /Enlace copiado al portapapeles/);
  assert.match(team, /get_pachanga_team_membership_requests_v1/);
  assert.match(team, /command_pachanga_team_membership_request_v1/);
  assert.match(team, /Pendientes de aprobación/);
});

test("V3F invitation snapshots expose membership state without leaking raw tokens", () => {
  const invitation = normalizeSocialTeamInvitation({
    alreadyMember: true,
    groupId: "group-demo",
    invitationId: "invite-demo",
    inviteMode: "TEAM_LINK",
    maxUses: 100,
    state: "ACTIVE",
    useCount: 4,
  });
  assert.equal(invitation?.alreadyMember, true);
  assert.equal(invitation?.inviteMode, "TEAM_LINK");
  assert.equal(invitation?.useCount, 4);
});

test("V3F keeps five primary tabs and includes Team directly", () => {
  assert.deepEqual(PRODUCT_PRIMARY_DESTINATIONS.map((entry) => entry.id), ["inicio", "partido", "retos", "mercado", "equipo"]);
  assert.equal(PRODUCT_PRIMARY_DESTINATIONS.some((entry) => entry.id === "equipo"), true);
});

test("V3F caches only canonical snapshots under versioned per-user keys", () => {
  assert.equal(socialProfileCacheKey("user-demo"), "pachangas-social-profile-cache:v3f-1:user-demo");
  assert.equal(socialTeamCacheKey("user-demo", "team-demo"), "pachangas-social-team-cache:players-v1:user-demo:team-demo");
});

test("V3F Demo covers the 26 local stories with no remote writer", async () => {
  const journey = await source("app/demo-world/demo-social-first-time-journey.tsx");
  assert.equal(DEMO_SOCIAL_FIRST_TIME_STORIES.length, 26);
  for (const story of [
    "Comparte una invitación sintética",
    "Demuestra cero membresía duplicada",
    "Código de equipo identifica pero no concede acceso",
    "Jugador ordinario no puede invitar",
    "Abre Partidos",
  ]) assert.ok(DEMO_SOCIAL_FIRST_TIME_STORIES.includes(story as never));
  assert.match(journey, /data-demo-social-first-time="v3f"/);
  assert.match(journey, /Replay idempotente/);
  assert.match(journey, /Enlace revocado/);
  assert.match(journey, /Remote writes: 0/);
  assert.doesNotMatch(journey, /supabase|\.rpc\(|fetch\(|method:\s*["'](?:POST|PUT|PATCH|DELETE)/i);
});

test("V3F Service Worker keeps Team read surfaces available without caching writes", async () => {
  const worker = await source("app/service-worker-source.ts");
  for (const route of ["/equipo", "/equipo/plantilla", "/equipo/invitaciones", "/perfil"]) {
    assert.ok(worker.includes(`"${route}"`));
  }
  assert.match(worker, /if \(request\.method !== "GET"\) return/);
  assert.match(worker, /networkFirstNavigation/);
});

test("V3F public entry keeps the brand inside compact landscape viewports", async () => {
  const css = await source("app/globals.css");
  assert.match(
    css,
    /@media \(orientation: landscape\) and \(max-height: 560px\)[\s\S]*?\.demo-world-entry-shell \.brand-hero-logo\s*\{[^}]*transform:\s*translateX\(-16\.5%\);/,
  );
});

test("V3F migrations keep raw invitation tokens hashed and Rating untouched", async () => {
  const [profileSql, teamSql, invitationSql, hardeningSql, teamNameSql, reusableInviteSql, reusableInviteDbTest] = await Promise.all([
    source("supabase/migrations/20260901214524_social_team_core_evidence_v1.sql"),
    source("supabase/migrations/20260901214525_atomic_social_team_creation_v1.sql"),
    source("supabase/migrations/20260901214526_team_player_invitations_v2.sql"),
    source("supabase/migrations/20260901214527_social_team_read_models_rls_flags_v1.sql"),
    source("supabase/migrations/20260905212126_unique_team_names_and_length_v1.sql"),
    source("supabase/migrations/20260906020600_reusable_team_join_links_v1.sql"),
    source("tests/reusable-team-join-links-v1-db.sql"),
  ]);
  assert.match(profileSql, /command_pachanga_social_profile_v1/);
  assert.match(teamSql, /command_pachanga_social_team_v1/);
  assert.match(invitationSql, /extensions\.digest\(convert_to\(raw_token/);
  assert.match(invitationSql, /command_pachanga_team_player_invitation_v2/);
  assert.match(hardeningSql, /revoke insert, update, delete/);
  assert.match(teamNameSql, /pachanga_groups_name_unique_v1_idx/);
  assert.match(teamNameSql, /TEAM_NAME_TOO_LONG/);
  assert.match(teamNameSql, /char_length\([\s\S]*between 2 and 32/);
  assert.match(teamNameSql, /translate\([\s\S]*lower\([\s\S]*regexp_replace/);
  assert.match(teamNameSql, /before insert or update of name/);
  assert.match(reusableInviteSql, /invite_mode = 'TEAM_LINK'/);
  assert.match(reusableInviteSql, /'alreadyMember', exists/);
  assert.match(reusableInviteSql, /insert into public\.pachanga_group_members\(group_id, user_id, role, display_name\)/);
  assert.match(reusableInviteSql, /select invitation\.group_id, actor_id, 'player'/);
  assert.match(reusableInviteSql, /pachanga_team_membership_requests_v1/);
  assert.match(reusableInviteDbTest, /A second player must be able to use the same shared link/);
  assert.match(reusableInviteDbTest, /An existing member must never be duplicated/);
  assert.match(reusableInviteDbTest, /No invitation or membership request may grant owner\/admin/);
  for (const sql of [profileSql, teamSql, invitationSql, hardeningSql, teamNameSql, reusableInviteSql]) {
    assert.doesNotMatch(sql, /update\s+public\.pachanga_player_profiles[\s\S]{0,160}(current_overall|current_facets|rating)/i);
  }
});
