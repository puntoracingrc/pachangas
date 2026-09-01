import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  DEFAULT_SOCIAL_ONBOARDING_DRAFT,
  SOCIAL_PROFILE_FIELD_CLASSIFICATION,
  TEAM_CREATION_AUTHORITY,
  deriveSocialEntryState,
  mapTeamJoinError,
  normalizeSocialOnboardingDraft,
  parseTeamInvitationInput,
  playerMarketPresentationState,
  socialProfileMinimumReady,
  socialOnboardingFlowFromSearch,
  socialProfileModalities,
  socialWriteAvailability,
} from "../app/social-onboarding-contract";
import { DEMO_SOCIAL_FIRST_TIME_STORIES } from "../app/demo-world/demo-social-first-time-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("V3E classifies social profile fields without exposing technical authority", () => {
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.displayName, "ESSENTIAL");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.position, "ESSENTIAL");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.modalities, "ESSENTIAL");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.avatar, "OPTIONAL");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.marketVisibility, "MARKET_ONLY");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.teamCode, "TEAM_ONLY");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.email, "PRIVATE");
  assert.equal(SOCIAL_PROFILE_FIELD_CLASSIFICATION.profileRevision, "TECHNICAL");
});

test("all five first-access states derive only from canonical profile and memberships", () => {
  const ready = { displayName: "Alex", modalities: ["futbol7"], position: "Mediocentro" };
  assert.equal(deriveSocialEntryState({ invitationPending: false, membershipCount: 0, profile: null }), "NEW_USER");
  assert.equal(deriveSocialEntryState({ invitationPending: false, membershipCount: 0, profile: ready }), "PROFILE_READY_NO_TEAM");
  assert.equal(deriveSocialEntryState({ invitationPending: true, membershipCount: 0, profile: ready }), "TEAM_INVITATION_PENDING");
  assert.equal(deriveSocialEntryState({ invitationPending: false, membershipCount: 1, profile: ready }), "TEAM_MEMBER");
  assert.equal(deriveSocialEntryState({ invitationPending: false, membershipCount: 2, profile: ready }), "MULTI_TEAM_MEMBER");
});

test("minimum profile requires only name, position and one modality", () => {
  assert.equal(socialProfileMinimumReady({ displayName: "Alex", modalities: ["futbol7"], position: "Pivote" }), true);
  assert.equal(socialProfileMinimumReady({ displayName: "Alex", modalities: [], position: "Pivote" }), false);
  assert.equal(socialProfileMinimumReady({ displayName: "", modalities: ["futbol7"], position: "Pivote" }), false);
});

test("the local draft is bounded, resumable and never preserves a blob as authority", () => {
  const draft = normalizeSocialOnboardingDraft({
    approximateTime: "20:00-22:00",
    avatarPreviewUrl: "blob:private-preview",
    days: ["L", "X", "invalid"],
    displayName: ` Alex ${"x".repeat(100)}`,
    modality: "invalid",
    position: "invalid",
    zone: `Barcelona ${"z".repeat(200)}`,
  });
  assert.equal(draft.avatarPreviewUrl, "");
  assert.deepEqual(draft.days, ["L", "X"]);
  assert.equal(draft.modality, "futbol7");
  assert.equal(draft.position, DEFAULT_SOCIAL_ONBOARDING_DRAFT.position);
  assert.ok(draft.displayName.length <= 80);
  assert.ok(draft.zone.length <= 120);
});

test("canonical modalities prefer explicit market data and fall back to assessment answers", () => {
  assert.deepEqual(socialProfileModalities({ marketModalities: ["futbol7"] }), ["futbol7"]);
  assert.deepEqual(socialProfileModalities({
    assessmentSummary: { initial: { modeShares: [{ mode: "sala", percentage: 100 }, { mode: "futbol11", percentage: 0 }] } },
  }), ["sala"]);
});

test("team invitation input accepts full, compact and linked UUIDs without auto-joining", () => {
  const uuid = "12345678-1234-4234-9234-1234567890ab";
  assert.deepEqual(parseTeamInvitationInput(uuid), { kind: "invite", token: uuid });
  assert.deepEqual(parseTeamInvitationInput(uuid.replaceAll("-", "")), { kind: "invite", token: uuid });
  assert.deepEqual(parseTeamInvitationInput(`https://pachangasiq.com/?i=${uuid}`), { kind: "invite", token: uuid });
  assert.deepEqual(parseTeamInvitationInput("PIQ2026"), { kind: "team-code", code: "PIQ2026" });
  assert.deepEqual(parseTeamInvitationInput("not a valid code"), { kind: "invalid", reason: "INVALID" });
});

test("join errors are safe product copy and offline writes fail closed", () => {
  assert.equal(mapTeamJoinError(new Error("Invalid invite token")), "INVITACIÓN NO VÁLIDA");
  assert.equal(mapTeamJoinError(new Error("Invite expired")), "INVITACIÓN CADUCADA");
  assert.equal(mapTeamJoinError(new Error("Already member")), "YA PERTENECES A ESTE EQUIPO");
  assert.equal(mapTeamJoinError(new Error("Team suspended")), "EQUIPO NO DISPONIBLE");
  assert.deepEqual(socialWriteAvailability(false), { allowed: false, label: "Necesitas conexión para confirmar esta acción." });
});

test("market visibility is explicit and revocable", () => {
  assert.equal(playerMarketPresentationState(null), "NO PUBLICADO");
  assert.equal(playerMarketPresentationState({ availability: "Martes", enabled: false }), "PAUSADO");
  assert.equal(playerMarketPresentationState({ enabled: true }), "PUBLICADO");
});

test("the three-step onboarding is optional, resumable and keeps the card optional", async () => {
  const component = await source("app/_components/social-onboarding.tsx");
  assert.match(component, /\[1, 2, 3\]\.map/);
  assert.match(component, /Paso 1[\s\S]*Tu perfil/);
  assert.match(component, /Paso 2[\s\S]*Dónde y cuándo juegas/);
  assert.match(component, /Paso 3[\s\S]*¿Cómo quieres empezar\?/);
  assert.match(component, /Ahora no/);
  assert.match(component, /Continuar configuración inicial/);
  assert.match(component, /Foto[\s\S]*Opcional/);
  assert.doesNotMatch(component, /onboardingCompleted/);
});

test("the onboarding offers exactly the three social starts and no competition setup", async () => {
  const component = await source("app/_components/social-onboarding.tsx");
  for (const label of ["Unirme a un equipo", "Crear mi equipo", "Buscar una pachanga"]) assert.match(component, new RegExp(label));
  for (const forbidden of ["Liga", "Torneo", "Billing", "Stripe", "RuleRevision"]) assert.doesNotMatch(component, new RegExp(forbidden));
});

test("incoming invitations wait for explicit confirmation and canonical readback", async () => {
  const [page, component] = await Promise.all([source("app/page.tsx"), source("app/_components/social-onboarding.tsx")]);
  const connectStart = page.indexOf("const connectGroupEffect");
  const connect = page.slice(connectStart, page.indexOf("useEffect(() => {", connectStart));
  const confirmStart = page.indexOf("async function confirmSocialInvitation");
  const confirm = page.slice(confirmStart, page.indexOf("function createTeam", confirmStart));
  assert.match(connect, /setPendingSocialInvitation/);
  assert.doesNotMatch(connect, /join_pachanga_team|accept_pachanga_admin_invite_authoritative_v1/);
  assert.match(confirm, /accept_pachanga_admin_invite_authoritative_v1/);
  assert.match(confirm, /operation_id: id\(\)/);
  assert.match(confirm, /command_pachanga_team_player_invitation_v2/);
  assert.match(confirm, /team\.invitation\.accept/);
  assert.doesNotMatch(confirm, /join_pachanga_team/);
  assert.match(confirm, /await loadTeams\(client, groupId\)/);
  assert.match(component, /const visibleOpen = Boolean\(forcedView \|\| open\)/);
  assert.doesNotMatch(component, /visibleOpen = Boolean\(invitation \|\|/);
  assert.match(page, /dismissed=\{pendingSocialInvitation \? false : socialOnboardingDismissed\}/);
  assert.match(page, /key=\{pendingSocialInvitation\?\.token \?\? "social-onboarding"\}/);
});

test("team creation uses one authoritative command and never confirms locally", async () => {
  const [page, component] = await Promise.all([source("app/page.tsx"), source("app/_components/social-onboarding.tsx")]);
  assert.equal(TEAM_CREATION_AUTHORITY.available, true);
  assert.equal(TEAM_CREATION_AUTHORITY.command, "command_pachanga_social_team_v1");
  const createStart = page.indexOf("async function createSocialTeam");
  const create = page.slice(createStart, page.indexOf("async function lookupSocialTeamCode", createStart));
  assert.match(create, /command_pachanga_social_team_v1/);
  assert.match(create, /team\.create/);
  assert.match(create, /expected_revision: 0/);
  assert.match(create, /operation_id: id\(\)/);
  assert.match(create, /await loadTeams\(supabase, team\.groupId\)/);
  assert.match(component, /creating \? "Creando\.\.\." : "Crear equipo"/);
  assert.doesNotMatch(component, /Crear equipo<\/button><p[^>]*>.*solo local/i);
});

test("a registered user without a team gets a clean canonical empty state", async () => {
  const [page, shell, retos] = await Promise.all([
    source("app/page.tsx"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/retos/page.tsx"),
  ]);
  assert.match(page, /applyPayload\(emptyTeamPayload\("Tu espacio de jugador"\), null\)/);
  assert.match(page, /data-team-state=\{hasRealTeam \? "member" : "no-team"\}/);
  assert.match(shell, /Unirme a un equipo/);
  assert.match(shell, /Buscar una pachanga/);
  assert.match(shell, /isPlayerWithoutTeam \? "Empezar" : "Mi equipo"/);
  assert.match(retos, /type: selectedMembership \? "team" : "profile"/);
});

test("Mi perfil is a clean cached read model with canonical Realtime invalidation", async () => {
  const profile = await source("app/perfil/profile-client.tsx");
  assert.match(profile, /pachangas-profile-read-cache/);
  assert.match(profile, /pachanga_player_profiles/);
  assert.match(profile, /get_my_pachanga_social_teams_v1/);
  assert.match(profile, /get_my_pachanga_social_profile_v1/);
  assert.match(profile, /pachanga_social_invalidations_v1/);
  assert.match(profile, /nextStatus === "SUBSCRIBED"/);
  assert.match(profile, /window\.addEventListener\("online"/);
  assert.match(profile, /Resumen de perfil/);
  assert.match(profile, /Tu carta aún no está creada/);
  assert.match(profile, /La carta es opcional/);
  assert.match(profile, /Tu perfil no se publica hasta que lo autorices expresamente/);
  assert.doesNotMatch(profile, />UUID<|>Provider<|>Revisión<|>Auth metadata</i);
});

test("profile privacy copy excludes private and technical fields from the public surface", async () => {
  const [profile, page] = await Promise.all([source("app/perfil/profile-client.tsx"), source("app/perfil/page.tsx")]);
  assert.match(profile, /Email, teléfono, fecha de nacimiento completa, coordenadas exactas, identidad Auth y notas privadas/);
  assert.doesNotMatch(profile, /service_role|NEXT_PUBLIC.*SECRET|auth\.users/);
  assert.match(page, /robots: \{ follow: false, index: false \}/);
});

test("avatar, card and market entry reuse existing product authorities", async () => {
  const [page, profile, card] = await Promise.all([
    source("app/page.tsx"),
    source("app/perfil/profile-client.tsx"),
    source("app/personalizar-carta/page.tsx"),
  ]);
  assert.match(page, /patch_pachanga_player_profile_authoritative_v2/);
  assert.match(page, /upsert_pachanga_own_player_profile_authoritative_v2/);
  assert.match(profile, /href="\/personalizar-carta"/);
  assert.match(profile, /playerMarketPresentationState/);
  assert.match(card, /CLIENT_VERSION/);
});

test("canonical routes and PWA caches cover profile and team entry without offline writes", async () => {
  const [team, join, create, worker] = await Promise.all([
    source("app/equipo/page.tsx"),
    source("app/equipo/unirse/page.tsx"),
    source("app/equipo/crear/page.tsx"),
    source("app/service-worker-source.ts"),
  ]);
  assert.match(team, /SocialTeamProduct/);
  assert.doesNotMatch(team, /redirect\(/);
  assert.match(join, /redirect\("\/\?social=join"\)/);
  assert.match(create, /redirect\("\/\?social=create"\)/);
  for (const route of ["/perfil", "/equipo", "/equipo/plantilla", "/equipo/invitaciones", "/equipo/unirse", "/equipo/crear"]) assert.ok(worker.includes(`"${route}"`));
  assert.match(worker, /if \(request\.method !== "GET"\) return/);
});

test("social deep links restore through popstate and OAuth keeps the original intent", async () => {
  const page = await source("app/page.tsx");
  assert.equal(socialOnboardingFlowFromSearch("?social=join"), "join");
  assert.equal(socialOnboardingFlowFromSearch("?social=create&equipo=PIQ"), "create");
  assert.equal(socialOnboardingFlowFromSearch("?social=unknown"), null);
  assert.match(page, /window\.addEventListener\("popstate", restoreSocialIntent\)/);
  assert.match(page, /resolveGoogleAuthReturnHref\(window\.location\.href, window\.location\.origin\)/);
});

test("the social Demo has all 26 V3F stories and loads on demand", async () => {
  const [journey, demo] = await Promise.all([
    source("app/demo-world/demo-social-first-time-journey.tsx"),
    source("app/demo-world/demo-world-app.tsx"),
  ]);
  assert.equal(DEMO_SOCIAL_FIRST_TIME_STORIES.length, 26);
  assert.match(journey, /REMOTE WRITES 0/);
  assert.match(journey, /NOTIFICACIONES 0/);
  assert.match(journey, /STRIPE 0/);
  assert.doesNotMatch(journey, /supabase|\.rpc\(|fetch\(|method:\s*["'](?:POST|PUT|PATCH|DELETE)/i);
  assert.match(journey, /join-confirm/);
  assert.match(journey, /Buscar equipo/);
  assert.match(journey, /Confirmar entrada/);
  assert.match(journey, /createStep === 1/);
  assert.match(journey, /createStep === 2/);
  assert.match(journey, /createStep === 3/);
  assert.match(journey, /PIQ-DEMO-NUEVO/);
  assert.match(journey, /Crear primer partido/);
  assert.match(journey, /Repetir aceptación/);
  assert.match(journey, /Revocar otro enlace/);
  assert.match(journey, /Intentar invitar/);
  assert.match(journey, /data-demo-social-first-time="v3f"/);
  assert.match(journey, /Ver como otro equipo/);
  assert.match(demo, /dynamic\([\s\S]*demo-social-first-time-journey/);
  assert.match(demo, />Empezar<\/button>/);
  assert.match(demo, /socialJourneyLauncher[\s\S]*Primeros pasos/);
  assert.match(demo, /journey[\s\S]*first-time/);
  assert.match(journey, /map\(\(story, index\) => <li key=\{`\$\{index\}-\$\{story\}`\}/);
});

test("V3A, V3B, V3C and V3D remain the social destinations", async () => {
  const [navigation, page, retos, market] = await Promise.all([
    source("app/_components/product-navigation-contract.ts"),
    source("app/page.tsx"),
    source("app/retos/page.tsx"),
    source("app/mercado/marketplace-client.tsx"),
  ]);
  for (const destination of ["inicio", "partido", "retos", "mercado"]) assert.match(navigation, new RegExp(destination));
  assert.match(page, /OfficialMatchesOverview/);
  assert.match(retos, /TeamChallengesPanel/);
  assert.match(market, /type MarketTab = "equipos" \| "jugadores" \| "partidos"/);
});

test("role separation stays canonical and never compares platform owner email in React", async () => {
  const [shell, ownerHook] = await Promise.all([
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/_components/use-canonical-platform-owner.ts"),
  ]);
  assert.match(shell, /perspective === "team-admin" \|\| perspective === "team-owner"/);
  assert.match(shell, /platformOwner \? <Link href="\/admin">Administración<\/Link>/);
  assert.match(shell, /platformOwner \? <Link href="\/admin\/demo">Mundo Demo completo<\/Link>/);
  assert.match(ownerHook, /body\?\.access\?\.role === "platform_owner"/);
  assert.doesNotMatch(ownerHook, /puntoracingrc|@gmail|email/i);
});

test("responsive surfaces preserve portrait, compact landscape, safe areas and reduced motion", async () => {
  const [onboarding, profile, demo] = await Promise.all([
    source("app/_components/social-onboarding.module.css"),
    source("app/perfil/profile.module.css"),
    source("app/demo-world/demo-social-first-time-journey.module.css"),
  ]);
  assert.match(onboarding, /@media\(max-width:720px\)/);
  assert.match(onboarding, /@media\(orientation:landscape\) and \(pointer:coarse\)/);
  assert.match(onboarding, /prefers-reduced-motion/);
  assert.match(profile, /@media\(max-width:760px\)/);
  assert.match(profile, /@media\(orientation:landscape\) and \(pointer:coarse\)/);
  assert.match(demo, /env\(safe-area-inset-top\)/);
  assert.match(demo, /@media\(orientation:landscape\) and \(pointer:coarse\)/);
  assert.match(demo, /prefers-reduced-motion/);
});
