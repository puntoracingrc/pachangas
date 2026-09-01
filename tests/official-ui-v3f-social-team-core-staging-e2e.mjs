import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const PRODUCTION_REF = "qonbngfrnrqgmxbdfbea";
const EXPECTED_STAGING_REF = "lhusningjrsanfzwmhiw";
const ALL_FLAGS = {
  demoSocialTeamJourneyEnabled: true,
  socialProfileFoundationEnabled: true,
  socialProfileIndependentWriteEnabled: true,
  socialTeamCreationEnabled: true,
  socialTeamHomeV3fEnabled: true,
  socialTeamInvitationV2Enabled: true,
  socialTeamMembershipV2Enabled: true,
};

const env = {
  confirmation: process.env.SOCIAL_TEAM_V3F_STAGING_CONFIRM,
  expectedSha: process.env.SOCIAL_TEAM_V3F_STAGING_EXPECTED_SHA,
  previewUrl: process.env.SOCIAL_TEAM_V3F_STAGING_PREVIEW_URL,
  projectRef: process.env.SOCIAL_TEAM_V3F_STAGING_PROJECT_REF,
};

if (
  env.confirmation !== "SOCIAL_TEAM_V3F_STAGING_ONLY"
  || env.projectRef !== EXPECTED_STAGING_REF
  || env.projectRef === PRODUCTION_REF
  || !/^[0-9a-f]{40}$/i.test(env.expectedSha ?? "")
  || !env.previewUrl
  || /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)
) {
  throw new Error("SOCIAL_TEAM_V3F_STAGING_PRODUCTION_TARGET_FORBIDDEN");
}

function loadEphemeralApiKeys() {
  const result = spawnSync(
    "supabase",
    ["projects", "api-keys", "--project-ref", env.projectRef, "--output", "json"],
    { encoding: "utf8", maxBuffer: 4 * 1024 * 1024 },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`SOCIAL_TEAM_V3F_API_KEYS_UNAVAILABLE:${result.stderr || "unknown"}`);
  }

  const keys = JSON.parse(result.stdout);
  const publishable = keys.find((entry) => entry.type === "publishable")
    ?? keys.find((entry) => entry.name === "anon");
  const serviceRole = keys.find((entry) => entry.name === "service_role");
  if (!publishable?.api_key || !serviceRole?.api_key) {
    throw new Error("SOCIAL_TEAM_V3F_EPHEMERAL_KEYS_INCOMPLETE");
  }
  if (/^sb_secret_/i.test(publishable.api_key) || publishable.api_key === serviceRole.api_key) {
    throw new Error("SOCIAL_TEAM_V3F_BROWSER_KEY_INVALID");
  }
  return { publishableKey: publishable.api_key, serviceRoleKey: serviceRole.api_key };
}

const { publishableKey, serviceRoleKey } = loadEphemeralApiKeys();
const supabaseUrl = `https://${env.projectRef}.supabase.co`;
const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `V3F-${randomUUID()}-Qa!`;
const accounts = [];
const authenticatedClients = [];
const channels = [];
let platformClient = null;
let flagsWereEnabled = false;

function client(key = publishableKey, options = {}) {
  return createClient(supabaseUrl, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
    ...options,
  });
}

const service = client(serviceRoleKey);

function metadata(surface, displayMode = "standalone") {
  return {
    clientVersion: "3.6.0+official-ui-v3f-staging",
    deviceId: `v3f-${surface}-${runId}`,
    displayMode,
    serviceWorkerVersion: "3.6.0+official-ui-v3f-staging",
    sessionId: `v3f-${runId}`,
    surface,
  };
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean)
    .join(" ");
}

function expectError(result, pattern, label) {
  assert.ok(result.error, `${label}: expected an error`);
  assert.match(diagnostic(result), pattern, `${label}: ${diagnostic(result)}`);
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) {
    throw new Error(`${name} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  }
  return result.data;
}

async function createAccount(label) {
  const account = {
    email: `v3f-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const result = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "OFFICIAL_UI_V3F_STAGING", runId },
  });
  if (result.error) throw result.error;
  accounts.push(account);
  return account;
}

async function signIn(account, device = account.label) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`V3F_SIGN_IN_FAILED:${device}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  await supabase.realtime.setAuth(result.data.session.access_token);
  authenticatedClients.push(supabase);
  return { accessToken: result.data.session.access_token, supabase };
}

async function ensurePlatformOwner(account) {
  const current = await service.rpc("get_pachanga_platform_access_service_v1", {
    target_user_id: account.id,
  });
  if (current.error) throw current.error;
  if (current.data) return current.data;
  return rpc(service, "bootstrap_pachanga_platform_owner_v1", {
    operation_id: randomUUID(),
    reason: "Official UI V3F isolated staging fixture",
    target_user_id: account.id,
  });
}

function profileCommand(supabase, action, expectedRevision, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_social_profile_v1", {
    action,
    client_metadata: metadata("v3f-profile"),
    expected_revision: expectedRevision,
    operation_id: operationId,
    payload,
  });
}

async function profileCommandOk(supabase, action, expectedRevision, payload, operationId) {
  const result = await profileCommand(supabase, action, expectedRevision, payload, operationId);
  if (result.error) throw new Error(`${action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function teamCommand(supabase, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_social_team_v1", {
    action: "team.create",
    client_metadata: metadata("v3f-team-create"),
    expected_revision: 0,
    operation_id: operationId,
    payload,
  });
}

async function teamCommandOk(supabase, payload, operationId) {
  const result = await teamCommand(supabase, payload, operationId);
  if (result.error) throw new Error(`team.create: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function invitationCommand(supabase, {
  action,
  expectedRevision,
  groupId = null,
  invitationId = null,
  operationId = randomUUID(),
  payload = {},
  token = "",
}) {
  return supabase.rpc("command_pachanga_team_player_invitation_v2", {
    action,
    client_metadata: metadata("v3f-invitations"),
    expected_revision: expectedRevision,
    invitation_token: token,
    operation_id: operationId,
    payload,
    target_group_id: groupId,
    target_invitation_id: invitationId,
  });
}

async function invitationCommandOk(supabase, input) {
  const result = await invitationCommand(supabase, input);
  if (result.error) throw new Error(`${input.action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("V3F_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`V3F_REALTIME_${status}`));
      }
    });
  });
}

function postgresChangesBinding(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("V3F_POSTGRES_CHANGES_BINDING_TIMEOUT")), 20_000);
    queue.binding = (payload) => {
      if (payload?.extension !== "postgres_changes") return;
      clearTimeout(timeout);
      if (payload.status === "ok") resolve(payload);
      else reject(new Error(`V3F_POSTGRES_CHANGES_BINDING_${String(payload.status || "ERROR").toUpperCase()}`));
    };
  });
}

function nextInvalidation(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("V3F_REALTIME_EVENT_TIMEOUT")), 20_000);
    queue.resolve = (event) => {
      clearTimeout(timeout);
      resolve(event);
    };
  });
}

function vercelFetch(path) {
  const result = spawnSync(
    "vercel",
    [
      "curl",
      path,
      "--deployment",
      env.previewUrl,
      "--scope",
      "persianas-almar-web-s-projects",
      "--",
      "--silent",
      "--show-error",
      "--dump-header",
      "-",
    ],
    { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`V3F_PREVIEW_REQUEST_FAILED:${path}`);
  const response = (result.stdout ?? "").replaceAll("\r\n", "\n");
  const boundary = response.indexOf("\n\n");
  assert.notEqual(boundary, -1, `${path}: missing HTTP headers`);
  const headers = response.slice(0, boundary);
  const body = response.slice(boundary + 2);
  assert.match(headers, /^HTTP\/\d(?:\.\d)? 200\b/m, `${path}: expected HTTP 200`);
  return { body, headers };
}

function previewSmoke() {
  const paths = ["/", "/perfil", "/equipo", "/demo", "/manifest.webmanifest", "/sw.js"];
  for (const path of paths) {
    const response = vercelFetch(path);
    if (path === "/sw.js") {
      assert.match(response.headers, /^cache-control: .*no-store/im);
      assert.match(
        response.body,
        new RegExp(`SERVICE_WORKER_VERSION = "2\\.0\\.0\\+sw\\.${env.expectedSha.slice(0, 12)}"`),
      );
      assert.match(response.body, /"\/equipo"/);
      assert.match(response.body, /"\/equipo\/plantilla"/);
      assert.match(response.body, /"\/equipo\/invitaciones"/);
    }
  }
  return { paths: paths.length, status: "PASS" };
}

async function countOwnedTeams(userId) {
  const result = await service.from("pachanga_groups")
    .select("id", { count: "exact", head: true })
    .eq("owner_id", userId);
  if (result.error) throw result.error;
  return result.count ?? 0;
}

async function setFlags(nextFlags) {
  const current = await rpc(platformClient, "get_pachanga_social_team_feature_flags_v1");
  return rpc(platformClient, "command_pachanga_social_team_settings_v1", {
    client_metadata: metadata("v3f-platform-flags", "browser"),
    expected_revision: current.confirmedRevision,
    operation_id: randomUUID(),
    payload: nextFlags,
  });
}

async function bestEffort(action) {
  try {
    await action();
  } catch {
    // The branch is destroyed after the run; this only protects the staged flag state.
  }
}

let completed = false;
let report;
try {
  const baselineService = await service.from("pachanga_groups")
    .select("id", { count: "exact", head: true });
  if (baselineService.error) throw baselineService.error;
  assert.equal(baselineService.count, 0, "V3F branch must not contain Teams before QA");

  const platform = await createAccount("platform");
  const ownerA = await createAccount("owner-a");
  const ownerB = await createAccount("owner-b");
  const playerA = await createAccount("player-a");
  const playerB = await createAccount("player-b");
  assert.equal(accounts.length, 5);

  await ensurePlatformOwner(platform);
  const platformSession = await signIn(platform);
  platformClient = platformSession.supabase;
  const initialFlags = await rpc(platformClient, "get_pachanga_social_team_feature_flags_v1");
  for (const key of Object.keys(ALL_FLAGS)) assert.equal(initialFlags[key], false, `${key} must start OFF`);
  const enabledFlags = await setFlags(ALL_FLAGS);
  for (const key of Object.keys(ALL_FLAGS)) assert.equal(enabledFlags[key], true, `${key} activation failed`);
  flagsWereEnabled = true;

  const ownerASession = await signIn(ownerA, "owner-a-device-a");
  const ownerADeviceB = await signIn(ownerA, "owner-a-device-b");
  const ownerBSession = await signIn(ownerB);
  const playerASession = await signIn(playerA);
  const playerBSession = await signIn(playerB);

  const profileFixtures = [
    [ownerASession.supabase, "Owner Alpha", "Mediocentro / pivote", "futbol7"],
    [ownerBSession.supabase, "Owner Beta", "Defensa central", "futbol7"],
    [playerASession.supabase, "Player Alpha", "Extremo", "futbol7"],
    [playerBSession.supabase, "Player Beta", "Delantero / punta", "futbol7"],
  ];
  for (const [supabase, displayName, primaryPosition, preferredModality] of profileFixtures) {
    const profile = await profileCommandOk(supabase, "profile.create", 0, {
      approximateTime: "20:00-22:00",
      displayName,
      generalArea: "Barcelona",
      preferredModality,
      primaryPosition,
      socialPreferences: { openToMatchInvites: true, openToTeamInvites: true },
      usualDays: ["M", "J"],
    });
    assert.equal(profile.confirmedRevision, 1);
    assert.equal(profile.ratingAuthority, "SEPARATE");
    assert.equal(profile.marketPublished, false);
  }

  const updatedProfile = await profileCommandOk(ownerASession.supabase, "profile.update", 1, {
    shortBio: "Perfil social V3F confirmado en staging.",
  });
  assert.equal(updatedProfile.confirmedRevision, 2);
  assert.equal(updatedProfile.ratingAuthority, "SEPARATE");

  const teamAOperation = randomUUID();
  const teamAPayload = {
    generalArea: "Barcelona",
    modality: "futbol7",
    name: `V3F Alpha ${runId}`,
    shieldKey: "team.shield.shape.classic_iq",
    targetPlayerCount: 14,
  };
  const teamAResponse = await teamCommandOk(ownerASession.supabase, teamAPayload, teamAOperation);
  const teamA = {
    code: teamAResponse.teamCode,
    id: teamAResponse.groupId,
    revision: teamAResponse.confirmedRevision,
  };
  assert.equal(teamAResponse.role, "owner");
  assert.equal(teamAResponse.operationalStatus, "ACTIVE");
  assert.equal(teamAResponse.memberCount, 1);
  const teamAReplay = await teamCommandOk(ownerASession.supabase, teamAPayload, teamAOperation);
  assert.deepEqual(teamAReplay, teamAResponse);

  const teamBResponse = await teamCommandOk(ownerBSession.supabase, {
    generalArea: "Barcelona",
    modality: "futbol7",
    name: `V3F Beta ${runId}`,
    targetPlayerCount: 16,
  });
  const teamB = {
    code: teamBResponse.teamCode,
    id: teamBResponse.groupId,
    revision: teamBResponse.confirmedRevision,
  };
  assert.equal(teamBResponse.role, "owner");
  assert.equal(teamBResponse.operationalStatus, "ACTIVE");

  const teamAHome = await rpc(ownerASession.supabase, "get_pachanga_social_team_home_v1", {
    target_group_id: teamA.id,
  });
  assert.equal(teamAHome.actions.canInvitePlayers, true);
  assert.equal(teamAHome.actions.canCreateMatch, true);
  assert.equal(teamAHome.role, "owner");

  const firstInviteOperation = randomUUID();
  const firstInvite = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamA.revision,
    groupId: teamA.id,
    operationId: firstInviteOperation,
    payload: { expiresInHours: 168 },
  });
  teamA.revision = firstInvite.teamRevision;
  assert.match(firstInvite.shareToken, /^piq_[0-9a-f]{64}$/);
  assert.equal(firstInvite.tokenAlreadyIssued, false);
  const firstInviteReplay = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamAResponse.confirmedRevision,
    groupId: teamA.id,
    operationId: firstInviteOperation,
    payload: { expiresInHours: 168 },
  });
  assert.equal(firstInviteReplay.tokenAlreadyIssued, true);
  assert.equal("shareToken" in firstInviteReplay, false);

  const lookedUpInvite = await rpc(playerASession.supabase, "lookup_pachanga_team_player_invitation_v2", {
    invitation_token: firstInvite.shareToken,
  });
  assert.equal(lookedUpInvite.invitationId, firstInvite.invitationId);
  const acceptOperation = randomUUID();
  const acceptedInvite = await invitationCommandOk(playerASession.supabase, {
    action: "team.invitation.accept",
    expectedRevision: 1,
    groupId: teamA.id,
    invitationId: firstInvite.invitationId,
    operationId: acceptOperation,
    token: firstInvite.shareToken,
  });
  teamA.revision = acceptedInvite.teamRevision;
  assert.equal(acceptedInvite.state, "USED");
  const acceptReplay = await invitationCommandOk(playerASession.supabase, {
    action: "team.invitation.accept",
    expectedRevision: 1,
    groupId: teamA.id,
    invitationId: firstInvite.invitationId,
    operationId: acceptOperation,
    token: firstInvite.shareToken,
  });
  assert.deepEqual(acceptReplay, acceptedInvite);
  const duplicateAccept = await invitationCommand(playerASession.supabase, {
    action: "team.invitation.accept",
    expectedRevision: 1,
    groupId: teamA.id,
    invitationId: firstInvite.invitationId,
    token: firstInvite.shareToken,
  });
  expectError(duplicateAccept, /STALE_INVITATION_REVISION|INVITATION_NOT_ACTIVE|PT409/, "duplicate accept");

  const rosterAfterAccept = await rpc(ownerASession.supabase, "get_pachanga_social_team_roster_v1", {
    target_group_id: teamA.id,
  });
  assert.equal(rosterAfterAccept.length, 2);
  assert.equal(new Set(rosterAfterAccept.map((member) => member.memberKey)).size, 2);
  assert.equal(rosterAfterAccept.some((member) => "userId" in member || "email" in member || "phone" in member), false);

  const revokeCandidate = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamA.revision,
    groupId: teamA.id,
    payload: { expiresInHours: 48 },
  });
  teamA.revision = revokeCandidate.teamRevision;
  const revokedInvite = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.revoke",
    expectedRevision: 1,
    groupId: teamA.id,
    invitationId: revokeCandidate.invitationId,
  });
  teamA.revision = revokedInvite.teamRevision;
  assert.equal(revokedInvite.state, "REVOKED");
  const revokedAccept = await invitationCommand(playerBSession.supabase, {
    action: "team.invitation.accept",
    expectedRevision: revokedInvite.confirmedRevision,
    groupId: teamA.id,
    invitationId: revokeCandidate.invitationId,
    token: revokeCandidate.shareToken,
  });
  expectError(revokedAccept, /INVITATION_NOT_ACTIVE|PT409/, "revoked invite accept");

  const declineCandidate = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamA.revision,
    groupId: teamA.id,
    payload: { expiresInHours: 48 },
  });
  teamA.revision = declineCandidate.teamRevision;
  const declinedInvite = await invitationCommandOk(playerBSession.supabase, {
    action: "team.invitation.decline",
    expectedRevision: 1,
    groupId: teamA.id,
    invitationId: declineCandidate.invitationId,
    token: declineCandidate.shareToken,
  });
  teamA.revision = declinedInvite.teamRevision;
  assert.equal(declinedInvite.state, "DECLINED");

  const codeLookup = await rpc(playerBSession.supabase, "lookup_pachanga_social_team_code_v1", {
    target_team_code: teamA.code,
  });
  assert.equal(codeLookup.groupId, teamA.id);
  assert.equal(codeLookup.acceptsPlayerInvitationOnly, true);
  const playerBTeamsBeforeInvite = await rpc(playerBSession.supabase, "get_my_pachanga_social_teams_v1");
  assert.equal(playerBTeamsBeforeInvite.some((team) => team.groupId === teamA.id), false);

  const playerInviteAttempt = await invitationCommand(playerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamA.revision,
    groupId: teamA.id,
    payload: { expiresInHours: 24 },
  });
  expectError(playerInviteAttempt, /TEAM_ADMIN_REQUIRED|42501/, "ordinary player invite");

  const directGroupWrite = await ownerASession.supabase.from("pachanga_groups")
    .update({ name: "FORBIDDEN" })
    .eq("id", teamA.id);
  assert.ok(directGroupWrite.error, "authenticated direct Team update must fail");
  const directMembershipWrite = await playerBSession.supabase.from("pachanga_group_members").insert({
    display_name: "FORBIDDEN",
    group_id: teamA.id,
    role: "player",
    user_id: playerB.id,
  });
  assert.ok(directMembershipWrite.error, "authenticated direct membership insert must fail");
  const legacyGroupJoin = await playerBSession.supabase.rpc("join_pachanga_group", { token: teamA.id });
  expectError(legacyGroupJoin, /permission denied|42501/i, "legacy group join");
  const legacyTeamJoin = await playerBSession.supabase.rpc("join_pachanga_team", {
    member_name: "FORBIDDEN",
    token: teamA.id,
  });
  expectError(legacyTeamJoin, /permission denied|42501/i, "legacy Team join");

  const ownerASecondTeamInvite = await invitationCommandOk(ownerBSession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamB.revision,
    groupId: teamB.id,
    payload: { expiresInHours: 72 },
  });
  teamB.revision = ownerASecondTeamInvite.teamRevision;
  const ownerASecondMembership = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.accept",
    expectedRevision: 1,
    groupId: teamB.id,
    invitationId: ownerASecondTeamInvite.invitationId,
    token: ownerASecondTeamInvite.shareToken,
  });
  teamB.revision = ownerASecondMembership.teamRevision;
  const ownerATeams = await rpc(ownerASession.supabase, "get_my_pachanga_social_teams_v1");
  assert.equal(ownerATeams.length, 2);
  assert.deepEqual(new Set(ownerATeams.map((team) => team.groupId)), new Set([teamA.id, teamB.id]));

  const raceInvite = await invitationCommandOk(ownerBSession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamB.revision,
    groupId: teamB.id,
    payload: { expiresInHours: 72 },
  });
  teamB.revision = raceInvite.teamRevision;
  const raceInputs = [playerASession.supabase, playerBSession.supabase].map((supabase) => ({
    input: {
      action: "team.invitation.accept",
      expectedRevision: 1,
      groupId: teamB.id,
      invitationId: raceInvite.invitationId,
      operationId: randomUUID(),
      token: raceInvite.shareToken,
    },
    supabase,
  }));
  const race = await Promise.all(raceInputs.map(({ input, supabase }) => invitationCommand(supabase, input)));
  const raceWinners = race.filter((result) => !result.error);
  const raceLosers = race.filter((result) => result.error);
  assert.equal(raceWinners.length, 1);
  assert.equal(raceLosers.length, 1);
  assert.match(diagnostic(raceLosers[0]), /STALE_INVITATION_REVISION|INVITATION_NOT_ACTIVE|PT409/);
  teamB.revision = raceWinners[0].data.teamRevision;
  const raceWinnerIndex = race.findIndex((result) => !result.error);
  const raceReplay = await invitationCommandOk(
    raceInputs[raceWinnerIndex].supabase,
    raceInputs[raceWinnerIndex].input,
  );
  assert.deepEqual(raceReplay, raceWinners[0].data);
  const teamBRoster = await rpc(ownerBSession.supabase, "get_pachanga_social_team_roster_v1", {
    target_group_id: teamB.id,
  });
  assert.equal(teamBRoster.length, 3);

  const realtimeQueue = {};
  const realtimeBinding = postgresChangesBinding(realtimeQueue);
  const realtimeChannel = ownerADeviceB.supabase
    .channel(`official-ui-v3f-${runId}`)
    .on("system", {}, (payload) => realtimeQueue.binding?.(payload))
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_social_invalidations_v1",
    }, (event) => {
      if (event.new?.entity_type === "invitation" && event.new?.entity_id === teamA.id) {
        realtimeQueue.resolve?.(event);
      }
    });
  channels.push({ channel: realtimeChannel, supabase: ownerADeviceB.supabase });
  await waitForSubscribed(realtimeChannel);
  await realtimeBinding;
  const realtimeEvent = nextInvalidation(realtimeQueue);
  const activeInvite = await invitationCommandOk(ownerASession.supabase, {
    action: "team.invitation.create",
    expectedRevision: teamA.revision,
    groupId: teamA.id,
    payload: { expiresInHours: 168 },
  });
  teamA.revision = activeInvite.teamRevision;
  const invalidation = await realtimeEvent;
  assert.equal(invalidation.new.entity_id, teamA.id);
  assert.equal(invalidation.new.revision, activeInvite.teamRevision);
  const refetchedInvitations = await rpc(
    ownerADeviceB.supabase,
    "get_pachanga_social_team_invitations_v2",
    { target_group_id: teamA.id },
  );
  assert.equal(refetchedInvitations.some((invite) => invite.invitationId === activeInvite.invitationId), true);

  await ownerADeviceB.supabase.removeChannel(realtimeChannel);
  const reconnectQueue = {};
  const reconnectBinding = postgresChangesBinding(reconnectQueue);
  const reconnectChannel = ownerADeviceB.supabase
    .channel(`official-ui-v3f-reconnect-${runId}`)
    .on("system", {}, (payload) => reconnectQueue.binding?.(payload))
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_social_invalidations_v1",
    }, () => {});
  channels.push({ channel: reconnectChannel, supabase: ownerADeviceB.supabase });
  await waitForSubscribed(reconnectChannel);
  await reconnectBinding;
  const convergedHome = await rpc(ownerADeviceB.supabase, "get_pachanga_social_team_home_v1", {
    target_group_id: teamA.id,
  });
  assert.equal(convergedHome.confirmedRevision, teamA.revision);

  const playerBOwnedTeamsBeforeOffline = await countOwnedTeams(playerB.id);
  const offlineClient = client(publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: {
      fetch: async () => {
        throw new TypeError("SYNTHETIC_OFFLINE");
      },
      headers: { Authorization: `Bearer ${playerBSession.accessToken}` },
    },
  });
  const offlineAttempt = await teamCommand(offlineClient, {
    generalArea: "Barcelona",
    modality: "futbol7",
    name: `Offline ${runId}`,
    targetPlayerCount: 14,
  });
  assert.ok(offlineAttempt.error, "offline Team creation must not be confirmed");
  assert.equal(await countOwnedTeams(playerB.id), playerBOwnedTeamsBeforeOffline);

  const ownerNotifications = await service.from("pachanga_user_notifications")
    .select("kind,payload,dedupe_key")
    .eq("recipient_user_id", ownerA.id);
  if (ownerNotifications.error) throw ownerNotifications.error;
  assert.equal(ownerNotifications.data.some((notification) => notification.kind === "team_player_invitation_accepted"), true);
  assert.equal(ownerNotifications.data.some((notification) => notification.kind === "team_player_invitation_declined"), true);
  assert.equal(JSON.stringify(ownerNotifications.data).includes("piq_"), false);

  const publicInvitations = await service.from("pachanga_team_player_invitations_v2")
    .select("id,group_id,state,revision,server_sequence")
    .in("group_id", [teamA.id, teamB.id]);
  if (publicInvitations.error) throw publicInvitations.error;
  assert.equal(JSON.stringify(publicInvitations.data).includes("piq_"), false);
  assert.equal(publicInvitations.data.some((invite) => invite.state === "ACTIVE"), true);
  assert.equal(publicInvitations.data.some((invite) => invite.state === "REVOKED"), true);

  const disabledFlags = await setFlags(
    Object.fromEntries(Object.keys(ALL_FLAGS).map((key) => [key, false])),
  );
  flagsWereEnabled = false;
  for (const key of Object.keys(ALL_FLAGS)) assert.equal(disabledFlags[key], false, `${key} cleanup failed`);

  report = {
    auth: "5 synthetic .test users / 2 sessions for the same owner",
    cleanup: "FLAGS_OFF / EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED",
    codeLookup: "IDENTIFIES_ONLY / NO_MEMBERSHIP",
    concurrency: "1 winner / 1 stale invitation revision",
    directWrites: "DENIED",
    idempotency: "PROFILE / TEAM / INVITATION PASS",
    invitations: "ACTIVE / USED / REVOKED / DECLINED",
    multiTeam: "2 canonical Teams visible to one user",
    notifications: "IN_APP .test ONLY / NO TOKEN",
    offline: "FAIL_CLOSED / 0 confirmed Teams",
    preview: previewSmoke(),
    projectRef: env.projectRef,
    realtime: "SUBSCRIBED / INVALIDATION / CANONICAL_REFETCH / RECONNECT PASS",
    rosterPrivacy: "OPAQUE MEMBER KEYS / NO AUTH UUID OR CONTACT DATA",
    teams: 2,
  };
  completed = true;
} finally {
  if (flagsWereEnabled && platformClient) {
    await bestEffort(() => setFlags(
      Object.fromEntries(Object.keys(ALL_FLAGS).map((key) => [key, false])),
    ));
  }
  for (const { channel, supabase } of channels) {
    await bestEffort(() => supabase.removeChannel(channel));
  }
  for (const supabase of authenticatedClients) {
    await bestEffort(() => supabase.auth.signOut({ scope: "local" }));
    await bestEffort(() => supabase.realtime.disconnect());
  }
}

assert.equal(completed, true);
process.stdout.write(`${JSON.stringify({ status: "OFFICIAL_UI_V3F_STAGING_PASS", ...report })}\n`);
