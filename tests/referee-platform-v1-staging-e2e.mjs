import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.REFEREE_PLATFORM_STAGING_URL;
const publishableKey = process.env.REFEREE_PLATFORM_STAGING_PUBLISHABLE_KEY;
const password = process.env.REFEREE_PLATFORM_STAGING_PASSWORD;

for (const [name, value] of Object.entries({
  REFEREE_PLATFORM_STAGING_PASSWORD: password,
  REFEREE_PLATFORM_STAGING_PUBLISHABLE_KEY: publishableKey,
  REFEREE_PLATFORM_STAGING_URL: url,
})) {
  if (!value) throw new Error(`${name} is required`);
}

const USERS = {
  platformOwner: {
    id: "a3200000-0000-4000-8000-000000000001",
    email: "r3-platform-owner-20260821@pachangasiq.test",
  },
  refereeOne: {
    id: "a3200000-0000-4000-8000-000000000002",
    email: "r3-referee-one-20260821@pachangasiq.test",
  },
  refereeTwo: {
    id: "a3200000-0000-4000-8000-000000000003",
    email: "r3-referee-two-20260821@pachangasiq.test",
  },
  playerReferee: {
    id: "a3200000-0000-4000-8000-000000000004",
    email: "r3-player-referee-20260821@pachangasiq.test",
  },
  teamOwner: {
    id: "a3200000-0000-4000-8000-000000000005",
    email: "r3-team-owner-20260821@pachangasiq.test",
  },
  teamAdmin: {
    id: "a3200000-0000-4000-8000-000000000006",
    email: "r3-team-admin-20260821@pachangasiq.test",
  },
  clubManagerA: {
    id: "a3200000-0000-4000-8000-000000000007",
    email: "r3-club-manager-a-20260821@pachangasiq.test",
  },
  clubManagerB: {
    id: "a3200000-0000-4000-8000-000000000008",
    email: "r3-club-manager-b-20260821@pachangasiq.test",
  },
  normal: {
    id: "a3200000-0000-4000-8000-000000000009",
    email: "r3-normal-20260821@pachangasiq.test",
  },
};

const GROUP_A = "a3210000-0000-4000-8000-000000000001";
const CLUB_A = "a3220000-0000-4000-8000-000000000001";
const CLUB_B = "a3220000-0000-4000-8000-000000000002";
const FLAGS_AGGREGATE = "00000000-0000-0000-0000-00000000a3f3";

function newClient() {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(account) {
  const supabase = newClient();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: account.email,
    password,
  });
  if (error) throw error;
  assert.equal(data.user?.id, account.id);
  clients.push(supabase);
  return supabase;
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

function command(supabase, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
  surface = "referee-platform-staging",
}) {
  return supabase.rpc("command_pachanga_referee_platform_v1", {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+r3-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r3-staging",
      surface,
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function commandOk(supabase, input) {
  const result = await command(supabase, input);
  if (result.error) {
    throw new Error(
      `${input.action}:${input.aggregateId}@${input.expectedRevision} failed `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function adminCommand(supabase, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return supabase.rpc("command_pachanga_referee_platform_admin_v1", {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+r3-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r3-staging",
      surface: "referee-platform-staging-control",
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function adminCommandOk(supabase, input) {
  const result = await adminCommand(supabase, input);
  if (result.error) {
    throw new Error(
      `admin:${input.action}:${input.aggregateId}@${input.expectedRevision} failed `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function expectRpcError(result, pattern, code) {
  assert.ok(result.error, `Expected RPC failure matching ${pattern}`);
  if (code) assert.equal(result.error.code, code);
  assert.match(
    [result.error.message, result.error.details, result.error.hint].filter(Boolean).join(" "),
    pattern,
  );
}

async function flags(supabase) {
  return rpc(supabase, "get_pachanga_referee_foundation_flags_v1");
}

async function setFlags(supabase, next, reason) {
  const current = await flags(supabase);
  return adminCommandOk(supabase, {
    action: "referee_flags.set",
    aggregateId: FLAGS_AGGREGATE,
    expectedRevision: current.revision,
    payload: { ...next, reason },
  });
}

async function mySnapshot(supabase) {
  const snapshot = await rpc(supabase, "get_my_pachanga_referee_platform_v1");
  return snapshot?.profile ?? null;
}

function profileFrom(receipt) {
  const profile = receipt?.snapshot?.profile;
  assert.ok(profile?.id, "Referee command must return a canonical profile snapshot");
  return profile;
}

async function createActiveProfile(supabase, {
  id,
  slug,
  listed = false,
  modality = "FOOTBALL_7",
  municipality = "Barcelona",
}) {
  let receipt = await commandOk(supabase, {
    action: "profile.create",
    aggregateId: id,
    expectedRevision: 0,
    payload: {
      availabilityStatus: "AVAILABLE",
      bio: `Perfil arbitral QA ${slug}.`,
      experienceSinceYear: 2019,
      experienceSummary: "Experiencia declarada en futbol amateur.",
      reason: "R3 staging profile",
      slug,
    },
  });
  const createReplay = await command(supabase, {
    action: "profile.create",
    aggregateId: id,
    expectedRevision: 0,
    operationId: receipt.operationId,
    payload: {
      availabilityStatus: "AVAILABLE",
      bio: `Perfil arbitral QA ${slug}.`,
      experienceSinceYear: 2019,
      experienceSummary: "Experiencia declarada en futbol amateur.",
      reason: "R3 staging profile",
      slug,
    },
  });
  assert.ifError(createReplay.error);
  assert.equal(createReplay.data.serverSequence, receipt.serverSequence);

  receipt = await commandOk(supabase, {
    action: "profile.modalities.replace",
    aggregateId: id,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      modalities: [{ experienceSinceYear: 2019, modality }],
      reason: "R3 staging modalities",
    },
  });
  receipt = await commandOk(supabase, {
    action: "profile.areas.replace",
    aggregateId: id,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      areas: [{
        countryCode: "ES",
        generalArea: municipality,
        municipality,
        province: "Barcelona",
        travelRadiusKm: 35,
      }],
      reason: "R3 staging service area",
    },
  });
  receipt = await commandOk(supabase, {
    action: "profile.availability.replace",
    aggregateId: id,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      exceptions: [{
        reason: "Private QA exception",
        unavailableFrom: "2026-10-01T08:00:00Z",
        unavailableUntil: "2026-10-01T12:00:00Z",
      }],
      reason: "R3 staging availability",
      windows: [{
        endLocalTime: "21:00",
        publicVisible: true,
        startLocalTime: "15:00",
        timezone: "Europe/Madrid",
        weekday: 6,
      }],
    },
  });
  receipt = await commandOk(supabase, {
    action: "profile.update",
    aggregateId: id,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      availabilityStatus: "AVAILABLE",
      availableForAssignments: true,
      reason: "R3 staging public settings",
      shareRecurringAvailability: true,
      visibility: "public",
    },
  });
  receipt = await commandOk(supabase, {
    action: "profile.activate",
    aggregateId: id,
    expectedRevision: receipt.confirmedRevision,
    payload: { reason: "R3 staging activate" },
  });
  if (listed) {
    receipt = await commandOk(supabase, {
      action: "marketplace.list",
      aggregateId: id,
      expectedRevision: receipt.confirmedRevision,
      payload: { reason: "R3 staging market listing" },
    });
  }
  return receipt;
}

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Realtime subscription timed out")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`Realtime subscription failed: ${status}`));
      }
    });
  });
}

function invalidationQueue() {
  const queued = [];
  let waiter;
  return {
    clear() { queued.length = 0; },
    next() {
      if (queued.length > 0) return Promise.resolve(queued.shift());
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          waiter = undefined;
          reject(new Error("Referee invalidation timed out"));
        }, 30_000);
        waiter = (payload) => {
          clearTimeout(timeout);
          waiter = undefined;
          resolve(payload);
        };
      });
    },
    push(payload) {
      if (waiter) waiter(payload);
      else queued.push(payload);
    },
  };
}

async function notificationCount(supabase, dedupeKey) {
  const result = await supabase
    .from("pachanga_user_notifications")
    .select("id", { count: "exact", head: true })
    .eq("dedupe_key", dedupeKey);
  if (result.error) throw result.error;
  return result.count ?? 0;
}

async function bestEffort(label, action) {
  try {
    await action();
  } catch (error) {
    console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error);
  }
}

async function archiveOwnProfile(supabase) {
  const snapshot = await mySnapshot(supabase);
  const profile = snapshot?.profile;
  if (!profile || profile.operationalStatus === "archived") return;
  await commandOk(supabase, {
    action: "profile.archive",
    aggregateId: profile.id,
    expectedRevision: profile.revision,
    payload: { reason: "R3 staging cleanup" },
    surface: "referee-platform-staging-cleanup",
  });
}

const clients = [];
const channels = [];
const relationshipCleanup = [];
const activeAssignmentCleanup = [];
let platformOwner;
let refereeOneDesktop;
let refereeOneMobile;
let refereeTwo;
let playerReferee;
let teamOwner;
let teamAdmin;
let clubManagerA;
let clubManagerB;
let normal;
let completed = false;

try {
  [
    platformOwner,
    refereeOneDesktop,
    refereeOneMobile,
    refereeTwo,
    playerReferee,
    teamOwner,
    teamAdmin,
    clubManagerA,
    clubManagerB,
    normal,
  ] = await Promise.all([
    signIn(USERS.platformOwner),
    signIn(USERS.refereeOne),
    signIn(USERS.refereeOne),
    signIn(USERS.refereeTwo),
    signIn(USERS.playerReferee),
    signIn(USERS.teamOwner),
    signIn(USERS.teamAdmin),
    signIn(USERS.clubManagerA),
    signIn(USERS.clubManagerB),
    signIn(USERS.normal),
  ]);

  await setFlags(platformOwner, {
    assignmentsEnabled: true,
    clubRelationshipsEnabled: true,
    foundationEnabled: true,
    marketplaceEnabled: true,
    publicProfilesEnabled: true,
    selfServiceEnabled: true,
  }, "R3 staging QA window");

  const runTag = Date.now().toString(36);
  const profileOneId = randomUUID();
  const profileTwoId = randomUUID();
  const playerRefereeProfileId = randomUUID();

  let profileOneReceipt = await createActiveProfile(refereeOneDesktop, {
    id: profileOneId,
    listed: true,
    slug: `r3-referee-one-${runTag}`,
  });
  await createActiveProfile(refereeTwo, {
    id: profileTwoId,
    modality: "FOOTBALL_11",
    municipality: "Sabadell",
    slug: `r3-referee-two-${runTag}`,
  });
  const playerReceipt = await commandOk(playerReferee, {
    action: "profile.create",
    aggregateId: playerRefereeProfileId,
    expectedRevision: 0,
    payload: {
      bio: "Jugador y arbitro conservan facetas independientes.",
      experienceSummary: "Perfil arbitral separado del PlayerProfile.",
      reason: "R3 player plus referee",
      slug: `r3-player-referee-${runTag}`,
    },
  });
  assert.equal(profileFrom(playerReceipt).operationalStatus, "draft");

  const queue = invalidationQueue();
  const channel = refereeOneMobile
    .channel(`r3-referee-${runTag}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `target_user_id=eq.${USERS.refereeOne.id}`,
      schema: "public",
      table: "pachanga_referee_invalidations",
    }, (payload) => queue.push(payload));
  channels.push([refereeOneMobile, channel]);
  await waitForSubscription(channel);
  queue.clear();
  const invalidationPromise = queue.next();
  profileOneReceipt = await commandOk(refereeOneDesktop, {
    action: "profile.update",
    aggregateId: profileOneId,
    expectedRevision: profileOneReceipt.confirmedRevision,
    payload: { bio: "Perfil arbitral actualizado desde desktop.", reason: "Realtime QA" },
  });
  const invalidation = await invalidationPromise;
  assert.equal(invalidation.new.referee_profile_id, profileOneId);
  const mobileSnapshot = await mySnapshot(refereeOneMobile);
  assert.equal(mobileSnapshot.profile.bio, "Perfil arbitral actualizado desde desktop.");
  assert.equal(mobileSnapshot.profile.revision, profileOneReceipt.confirmedRevision);

  const market = await rpc(refereeOneDesktop, "search_pachanga_referee_market_v1", {
    target_filters: { area: "Barcelona", modality: "FOOTBALL_7" },
    target_page: 1,
    target_page_size: 10,
  });
  assert.ok(market.items.some((item) => item.refereeProfileId === profileOneId));
  assert.equal(market.ordering, "filter_relevance_then_recent_activity");
  assert.equal(JSON.stringify(market).includes("@pachangasiq.test"), false);
  assert.equal(JSON.stringify(market).includes("Private QA exception"), false);

  const publicProfile = await rpc(normal, "get_pachanga_public_referee_v1", {
    target_slug: `r3-referee-one-${runTag}`,
  });
  assert.equal(publicProfile.slug, `r3-referee-one-${runTag}`);
  assert.equal(JSON.stringify(publicProfile).includes("@pachangasiq.test"), false);
  assert.equal(JSON.stringify(publicProfile).includes("Private QA exception"), false);
  assert.equal(JSON.stringify(publicProfile).match(/rating|stars|overall|grl/i), null);

  const inviteOperationId = randomUUID();
  const relationAId = randomUUID();
  const invitation = await commandOk(clubManagerA, {
    action: "relationship.invite",
    aggregateId: relationAId,
    expectedRevision: 0,
    operationId: inviteOperationId,
    payload: {
      clubId: CLUB_A,
      reason: "R3 registered referee invitation",
      relationshipType: "REGULAR",
      targetKind: "registered_user",
      targetUserId: USERS.refereeOne.id,
    },
  });
  assert.equal(invitation.oneTimeToken?.length, 64);
  const invitationReplay = await command(clubManagerA, {
    action: "relationship.invite",
    aggregateId: relationAId,
    expectedRevision: 0,
    operationId: inviteOperationId,
    payload: {
      clubId: CLUB_A,
      reason: "R3 registered referee invitation",
      relationshipType: "REGULAR",
      targetKind: "registered_user",
      targetUserId: USERS.refereeOne.id,
    },
  });
  assert.ifError(invitationReplay.error);
  assert.equal("oneTimeToken" in invitationReplay.data, false);
  assert.equal(await notificationCount(
    refereeOneDesktop,
    `referee-club-invite:${inviteOperationId}:${USERS.refereeOne.id}`,
  ), 1);
  let relationA = await commandOk(refereeOneDesktop, {
    action: "relationship.accept",
    aggregateId: relationAId,
    expectedRevision: 1,
    payload: { reason: "R3 accept registered Club invite" },
  });
  assert.equal(relationA.snapshot.relationship.status, "active");
  relationshipCleanup.push({
    actor: refereeOneDesktop,
    id: relationAId,
    revision: relationA.confirmedRevision,
  });

  const relationEmailId = randomUUID();
  const emailInvitation = await commandOk(clubManagerA, {
    action: "relationship.invite",
    aggregateId: relationEmailId,
    expectedRevision: 0,
    payload: {
      clubId: CLUB_A,
      reason: "R3 email referee invitation",
      relationshipType: "COLLABORATOR",
      targetEmail: USERS.refereeTwo.email,
      targetKind: "email_target",
    },
  });
  const tokenlessEmailResponse = await command(refereeTwo, {
    action: "relationship.accept",
    aggregateId: relationEmailId,
    expectedRevision: 1,
    payload: { reason: "Token is mandatory for email invitation" },
  });
  expectRpcError(tokenlessEmailResponse, /TOKEN_INVALID/, "42501");
  const relationEmail = await commandOk(refereeTwo, {
    action: "relationship.accept",
    aggregateId: relationEmailId,
    expectedRevision: 1,
    payload: {
      reason: "R3 accept email Club invite",
      token: emailInvitation.oneTimeToken,
    },
  });
  assert.equal(relationEmail.snapshot.relationship.status, "active");
  relationshipCleanup.push({
    actor: refereeTwo,
    id: relationEmailId,
    revision: relationEmail.confirmedRevision,
  });
  const consumedToken = await command(refereeTwo, {
    action: "relationship.accept",
    aggregateId: relationEmailId,
    expectedRevision: relationEmail.confirmedRevision,
    payload: { reason: "Consumed token replay", token: emailInvitation.oneTimeToken },
  });
  expectRpcError(consumedToken, /NOT_PENDING|TOKEN_INVALID/, "PT409");

  const relationBId = randomUUID();
  const relationRequest = await commandOk(refereeOneDesktop, {
    action: "relationship.request",
    aggregateId: relationBId,
    expectedRevision: 0,
    payload: {
      clubId: CLUB_B,
      reason: "R3 referee requests second Club",
      relationshipType: "PREFERRED",
    },
  });
  const relationB = await commandOk(clubManagerB, {
    action: "relationship.accept",
    aggregateId: relationBId,
    expectedRevision: relationRequest.confirmedRevision,
    payload: { reason: "R3 Club B accepts request" },
  });
  assert.equal(relationB.snapshot.relationship.status, "active");
  relationshipCleanup.push({
    actor: refereeOneDesktop,
    id: relationBId,
    revision: relationB.confirmedRevision,
  });
  assert.equal((await mySnapshot(refereeOneDesktop)).relationships.filter((item) => item.status === "active").length, 2);

  const unauthorizedAssignment = await command(teamAdmin, {
    action: "assignment.propose",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: {
      refereeProfileId: profileOneId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-finalized",
      sourceKind: "group_match",
    },
  });
  expectRpcError(unauthorizedAssignment, /TEAM_OWNER_REQUIRED/, "42501");

  const unboundAssignment = await command(teamOwner, {
    action: "assignment.propose",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: {
      refereeProfileId: profileOneId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-unbound",
      sourceKind: "group_match",
    },
  });
  expectRpcError(unboundAssignment, /CANONICAL_MATCH_REQUIRED/, "P0002");

  const primaryAssignmentId = randomUUID();
  let primary = await commandOk(teamOwner, {
    action: "assignment.propose",
    aggregateId: primaryAssignmentId,
    expectedRevision: 0,
    payload: {
      assignmentRole: "MAIN_REFEREE",
      message: "R3 staging individual match",
      refereeProfileId: profileOneId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-finalized",
      sourceKind: "group_match",
    },
  });
  const strangerAccept = await command(normal, {
    action: "assignment.accept",
    aggregateId: primaryAssignmentId,
    expectedRevision: primary.confirmedRevision,
    payload: { reason: "Another user cannot accept" },
  });
  expectRpcError(strangerAccept, /PROFILE_OWNER_REQUIRED/, "42501");
  primary = await commandOk(refereeOneDesktop, {
    action: "assignment.accept",
    aggregateId: primaryAssignmentId,
    expectedRevision: primary.confirmedRevision,
    payload: { reason: "R3 referee accepts" },
  });
  primary = await commandOk(teamOwner, {
    action: "assignment.confirm",
    aggregateId: primaryAssignmentId,
    expectedRevision: primary.confirmedRevision,
    payload: { reason: "R3 team owner confirms" },
  });
  assert.equal(primary.snapshot.assignment.status, "confirmed");

  const replacementAssignmentId = randomUUID();
  const replacementProposal = await commandOk(teamOwner, {
    action: "assignment.replace",
    aggregateId: primaryAssignmentId,
    expectedRevision: primary.confirmedRevision,
    payload: {
      message: "R3 replacement proposal",
      newAssignmentId: replacementAssignmentId,
      newRefereeProfileId: profileTwoId,
      reason: "R3 replace confirmed referee",
    },
  });
  assert.equal(replacementProposal.snapshot.replacement.status, "proposed");
  let replacement = await commandOk(refereeTwo, {
    action: "assignment.accept",
    aggregateId: replacementAssignmentId,
    expectedRevision: 1,
    payload: { reason: "R3 replacement accepts" },
  });
  replacement = await commandOk(teamOwner, {
    action: "assignment.confirm",
    aggregateId: replacementAssignmentId,
    expectedRevision: replacement.confirmedRevision,
    payload: { reason: "R3 replacement confirmed" },
  });
  assert.equal(replacement.snapshot.assignment.status, "confirmed");

  const overlapAssignmentId = randomUUID();
  let overlap = await commandOk(teamOwner, {
    action: "assignment.propose",
    aggregateId: overlapAssignmentId,
    expectedRevision: 0,
    payload: {
      refereeProfileId: profileTwoId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-overlap",
      sourceKind: "group_match",
    },
  });
  activeAssignmentCleanup.push({ id: overlapAssignmentId, revision: overlap.confirmedRevision });
  const conflict = await command(refereeTwo, {
    action: "assignment.accept",
    aggregateId: overlapAssignmentId,
    expectedRevision: overlap.confirmedRevision,
    payload: { reason: "R3 overlap must fail" },
  });
  expectRpcError(conflict, /TIME_CONFLICT/, "PT409");

  const declineAssignmentId = randomUUID();
  let declined = await commandOk(teamOwner, {
    action: "assignment.propose",
    aggregateId: declineAssignmentId,
    expectedRevision: 0,
    payload: {
      refereeProfileId: profileOneId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-decline",
      sourceKind: "group_match",
    },
  });
  declined = await commandOk(refereeOneDesktop, {
    action: "assignment.decline",
    aggregateId: declineAssignmentId,
    expectedRevision: declined.confirmedRevision,
    payload: { reason: "R3 decline path" },
  });
  assert.equal(declined.snapshot.assignment.status, "declined");

  const cancelAssignmentId = randomUUID();
  let cancelled = await commandOk(teamOwner, {
    action: "assignment.propose",
    aggregateId: cancelAssignmentId,
    expectedRevision: 0,
    payload: {
      refereeProfileId: profileOneId,
      requesterId: GROUP_A,
      requesterKind: "TEAM",
      sourceGroupId: GROUP_A,
      sourceId: "r3-stage-cancel",
      sourceKind: "group_match",
    },
  });
  cancelled = await commandOk(teamOwner, {
    action: "assignment.cancel",
    aggregateId: cancelAssignmentId,
    expectedRevision: cancelled.confirmedRevision,
    payload: { reasonCode: "qa_cancel", reasonText: "R3 cancellation path" },
  });
  assert.equal(cancelled.snapshot.assignment.status, "cancelled");

  const reconciled = await rpc(platformOwner, "reconcile_pachanga_referee_assignment_v1", {
    client_metadata: {
      clientVersion: "1.0.0+r3-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r3-staging",
      surface: "referee-platform-staging",
    },
    expected_revision: replacement.confirmedRevision,
    operation_id: randomUUID(),
    target_assignment_id: replacementAssignmentId,
  });
  assert.equal(reconciled.snapshot.assignment.status, "completed");
  assert.equal(reconciled.snapshot.statistics.matches_completed, 1);
  assert.equal(reconciled.snapshot.statistics.discipline_stats_status, "NOT_AVAILABLE");
  assert.equal(reconciled.snapshot.statistics.yellow_cards_shown, null);

  const rebuilt = await adminCommandOk(platformOwner, {
    action: "stats.rebuild",
    aggregateId: profileTwoId,
    expectedRevision: reconciled.snapshot.statistics.revision,
    payload: { reason: "R3 staging full rebuild" },
  });
  assert.equal(
    rebuilt.snapshot.statistics.checksum,
    reconciled.snapshot.statistics.checksum,
  );

  const adminProfile = await rpc(platformOwner, "get_pachanga_platform_referee_v1", {
    target_profile_id: profileTwoId,
  });
  const serializedAdmin = JSON.stringify(adminProfile);
  assert.equal(serializedAdmin.includes(emailInvitation.oneTimeToken), false);
  assert.equal(serializedAdmin.includes(USERS.refereeTwo.email), false);
  assert.equal(serializedAdmin.match(/refereeRating|refereeOverall|refereeGrl|stars/i), null);

  completed = true;
  console.log(JSON.stringify({
    assignments: "propose_accept_confirm_decline_cancel_replace_reconcile",
    clubs: "registered_email_request_multiclub",
    idempotency: "profile_and_invitation_replay",
    marketplace: "filtered_and_private",
    pwaMode: "standalone_metadata",
    realtime: "invalidation_then_canonical_refetch",
    status: "PASS",
    twoDevices: "same_referee_desktop_mobile",
  }));
} finally {
  if (platformOwner) {
    await bestEffort("enable-r3-cleanup-window", () => setFlags(platformOwner, {
      assignmentsEnabled: true,
      clubRelationshipsEnabled: true,
      foundationEnabled: true,
      marketplaceEnabled: false,
      publicProfilesEnabled: false,
      selfServiceEnabled: true,
    }, "R3 staging cleanup window"));

    for (const assignment of activeAssignmentCleanup) {
      if (!teamOwner) break;
      await bestEffort(`cancel-assignment-${assignment.id}`, async () => {
        const current = await rpc(teamOwner, "get_pachanga_referee_assignment_v1", {
          target_assignment_id: assignment.id,
        });
        if (!["proposed", "accepted", "confirmed"].includes(current.assignment.status)) return;
        await commandOk(teamOwner, {
          action: "assignment.cancel",
          aggregateId: assignment.id,
          expectedRevision: current.assignment.revision,
          payload: { reasonCode: "qa_cleanup", reasonText: "R3 staging cleanup" },
          surface: "referee-platform-staging-cleanup",
        });
      });
    }

    for (const relationship of relationshipCleanup) {
      await bestEffort(`end-relationship-${relationship.id}`, async () => {
        await commandOk(relationship.actor, {
          action: "relationship.end",
          aggregateId: relationship.id,
          expectedRevision: relationship.revision,
          payload: { reason: "R3 staging cleanup" },
          surface: "referee-platform-staging-cleanup",
        });
      });
    }

    for (const [label, supabase] of [
      ["referee-one", refereeOneDesktop],
      ["referee-two", refereeTwo],
      ["player-referee", playerReferee],
    ]) {
      if (supabase) await bestEffort(`archive-${label}`, () => archiveOwnProfile(supabase));
    }

    await bestEffort("disable-r3-flags", () => setFlags(platformOwner, {
      assignmentsEnabled: false,
      clubRelationshipsEnabled: false,
      foundationEnabled: false,
      marketplaceEnabled: false,
      publicProfilesEnabled: false,
      selfServiceEnabled: false,
    }, "R3 staging QA complete"));
  }

  for (const [supabase, channel] of channels) {
    await bestEffort("remove-channel", () => supabase.removeChannel(channel));
  }
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", () => supabase.realtime.disconnect());
  }
}

assert.equal(completed, true, "R3 staging story did not complete");
