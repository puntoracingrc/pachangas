import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.CLUB_FOUNDATION_STAGING_URL;
const publishableKey = process.env.CLUB_FOUNDATION_STAGING_PUBLISHABLE_KEY;
const password = process.env.CLUB_FOUNDATION_STAGING_PASSWORD;

for (const [name, value] of Object.entries({
  CLUB_FOUNDATION_STAGING_PASSWORD: password,
  CLUB_FOUNDATION_STAGING_PUBLISHABLE_KEY: publishableKey,
  CLUB_FOUNDATION_STAGING_URL: url,
})) {
  if (!value) throw new Error(`${name} is required`);
}

const USERS = {
  platformOwner: {
    id: "f1700000-0000-4000-8000-000000000001",
    email: "r1-platform-owner-20260821@pachangasiq.test",
  },
  ownerA: {
    id: "f1700000-0000-4000-8000-000000000002",
    email: "r1-owner-a-20260821@pachangasiq.test",
  },
  adminA: {
    id: "f1700000-0000-4000-8000-000000000003",
    email: "r1-admin-a-20260821@pachangasiq.test",
  },
  playerA: {
    id: "f1700000-0000-4000-8000-000000000004",
    email: "r1-player-a-20260821@pachangasiq.test",
  },
  ownerB: {
    id: "f1700000-0000-4000-8000-000000000005",
    email: "r1-owner-b-20260821@pachangasiq.test",
  },
  staffA: {
    id: "f1700000-0000-4000-8000-000000000006",
    email: "r1-staff-a-20260821@pachangasiq.test",
  },
  platformAdmin: {
    id: "f1700000-0000-4000-8000-000000000007",
    email: "r1-normal-20260821@pachangasiq.test",
  },
};

const GROUP_A = "f1800000-0000-4000-8000-000000000001";
const GROUP_B = "f1800000-0000-4000-8000-000000000002";
const CLUB_FLAGS_ID = "00000000-0000-0000-0000-00000000c101";
const COMPETITION_FLAGS_ID = "00000000-0000-0000-0000-00000000c001";

function client() {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(account) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword({
    email: account.email,
    password,
  });
  if (error) throw error;
  assert.equal(data.user?.id, account.id);
  return supabase;
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
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

function command(supabase, name, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
  surface = "club-foundation-staging",
}) {
  return supabase.rpc(name, {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+r2-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r2-staging",
      surface,
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

function competitionCommand(supabase, {
  action = "competition.create",
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  organizerKind = "CLUB",
  payload = {},
}) {
  return supabase.rpc("command_pachanga_competition_foundation_v2", {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+r2-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r2-staging",
      surface: "club-foundation-staging",
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
    organizer_kind: organizerKind,
  });
}

async function commandOk(supabase, name, input) {
  const result = await command(supabase, name, input);
  if (result.error) {
    throw new Error(
      `${name}:${input.action}:${input.aggregateId}@${input.expectedRevision} failed `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function confirmClubPublication(supabase, clubId, expectedRevision) {
  return rpc(supabase, "command_pachanga_publication_consent_v1", {
    client_metadata: {
      clientVersion: "1.0.0+r2-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+r2-staging",
      surface: "club-foundation-staging",
    },
    confirmations: { informationCorrect: true, representationAuthorized: true },
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
    subject_id: clubId,
    subject_kind: "CLUB",
  });
}

async function competitionCommandOk(supabase, input) {
  const result = await competitionCommand(supabase, input);
  if (result.error) {
    throw new Error(
      `command_pachanga_competition_foundation_v2:${input.action}:`
      + `${input.aggregateId}@${input.expectedRevision} failed `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function clubFrom(receipt) {
  const club = receipt?.snapshot?.club;
  assert.ok(club?.id, "Club receipt must contain a canonical Club snapshot");
  return club;
}

function relationshipFrom(snapshot, predicate) {
  const relationship = snapshot.teamRelationships.find(predicate);
  assert.ok(relationship, "Relationship must exist in the canonical Club snapshot");
  return relationship;
}

function membershipFrom(snapshot, userId) {
  const membership = snapshot.memberships.find((item) => (
    item.userId === userId && item.status === "active"
  ));
  assert.ok(membership, `Active membership for ${userId} must exist`);
  return membership;
}

async function clubSnapshot(supabase, clubId) {
  return rpc(supabase, "get_pachanga_club_foundation_snapshot_v1", {
    target_club_id: clubId,
  });
}

async function clubFlags(supabase) {
  return rpc(supabase, "get_pachanga_club_foundation_flags_v1");
}

async function setClubFlags(platform, next, reason) {
  const current = await clubFlags(platform);
  return commandOk(platform, "command_pachanga_club_platform_v1", {
    action: "club_flags.set",
    aggregateId: CLUB_FLAGS_ID,
    expectedRevision: current.revision,
    payload: { ...next, reason },
    surface: "club-foundation-staging-control",
  });
}

async function competitionOverview(platform) {
  return rpc(platform, "get_pachanga_platform_competition_foundation_v1", {
    page_offset: 0,
    page_size: 200,
  });
}

async function setCompetitionFlags(platform, next, reason) {
  const current = await competitionOverview(platform);
  return commandOk(platform, "command_pachanga_competition_platform_v1", {
    action: "foundation_flags.set",
    aggregateId: COMPETITION_FLAGS_ID,
    expectedRevision: current.flags.revision,
    payload: { ...next, reason },
    surface: "club-foundation-staging-control",
  });
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

function createInvalidationQueue(label) {
  const queued = [];
  let waiter;
  return {
    clear() {
      queued.length = 0;
    },
    next() {
      if (queued.length > 0) return Promise.resolve(queued.shift());
      assert.equal(waiter, undefined, `Only one ${label} waiter may be active`);
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          waiter = undefined;
          reject(new Error(`${label} invalidation timed out`));
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

async function ensurePlatformAdmin(platformOwner, platformAdmin) {
  const probe = await platformAdmin.rpc("get_pachanga_platform_clubs_v1", {
    page_offset: 0,
    page_size: 1,
  });
  if (!probe.error) return;
  const assigned = await rpc(platformOwner, "set_pachanga_platform_role_v1", {
    expected_revision: 0,
    next_active: true,
    next_role: "platform_admin",
    operation_id: randomUUID(),
    reason: "R2 staging platform admin fixture",
    target_user_id: USERS.platformAdmin.id,
  });
  assert.equal(assigned.role, "platform_admin");
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

const clients = [];
const fixtureClubs = [];
const fixtureOwners = new Map();
const fixtureCompetitionAssignments = [];
const channels = [];
let platformOwner;
let ownerDesktop;
let ownerMobile;
let adminA;
let playerA;
let ownerB;
let ownerBMobile;
let staffA;
let platformAdmin;
let completed = false;

async function archiveFixtureClub(clubId, ownerClient, preferredPrimaryOwnerId) {
  let snapshot;
  try {
    snapshot = await clubSnapshot(ownerClient, clubId);
  } catch {
    return;
  }

  for (const relationship of snapshot.teamRelationships) {
    if (relationship.status === "active") {
      await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
        action: "team_relationship.end",
        aggregateId: relationship.id,
        expectedRevision: relationship.revision,
        payload: { reason: "R2 staging cleanup" },
        surface: "club-foundation-staging-cleanup",
      });
    } else if (relationship.status === "invited" && relationship.initiatedBy === "CLUB") {
      await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
        action: "team_relationship.cancel",
        aggregateId: relationship.id,
        expectedRevision: relationship.revision,
        payload: { reason: "R2 staging cleanup" },
        surface: "club-foundation-staging-cleanup",
      });
    } else if (relationship.status === "requested") {
      await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
        action: "team_relationship.reject",
        aggregateId: relationship.id,
        expectedRevision: relationship.revision,
        payload: { reason: "R2 staging cleanup" },
        surface: "club-foundation-staging-cleanup",
      });
    }
  }

  snapshot = await clubSnapshot(ownerClient, clubId);
  for (const invitation of snapshot.pendingInvitations) {
    await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
      action: "membership.invitation.revoke",
      aggregateId: invitation.id,
      expectedRevision: invitation.revision,
      payload: { reason: "R2 staging cleanup" },
      surface: "club-foundation-staging-cleanup",
    });
  }

  snapshot = await clubSnapshot(ownerClient, clubId);
  if (
    preferredPrimaryOwnerId
    && snapshot.club.primaryOwnerId !== preferredPrimaryOwnerId
    && snapshot.memberships.some((item) => (
      item.userId === preferredPrimaryOwnerId
      && item.role === "club_owner"
      && item.status === "active"
    ))
  ) {
    await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
      action: "club.primary_owner.transfer",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: {
        reason: "R2 staging cleanup primary owner restore",
        retainPreviousOwner: true,
        targetUserId: preferredPrimaryOwnerId,
      },
      surface: "club-foundation-staging-cleanup",
    });
  }

  snapshot = await clubSnapshot(ownerClient, clubId);
  for (const membership of snapshot.memberships) {
    if (
      membership.status === "active"
      && membership.userId !== snapshot.club.primaryOwnerId
    ) {
      await commandOk(ownerClient, "command_pachanga_club_foundation_v1", {
        action: "membership.revoke",
        aggregateId: membership.id,
        expectedRevision: membership.revision,
        payload: { reason: "R2 staging cleanup" },
        surface: "club-foundation-staging-cleanup",
      });
    }
  }

  snapshot = await clubSnapshot(platformOwner, clubId);
  for (const grant of snapshot.entitlements.grants ?? []) {
    if (grant.status === "active") {
      const latest = await clubSnapshot(platformOwner, clubId);
      await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
        action: "club.entitlement.revoke",
        aggregateId: clubId,
        expectedRevision: latest.club.revision,
        payload: {
          entitlementId: grant.id,
          reason: "R2 staging cleanup",
        },
        surface: "club-foundation-staging-cleanup",
      });
    }
  }

  snapshot = await clubSnapshot(platformOwner, clubId);
  if (snapshot.club.operationalStatus !== "archived") {
    await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
      action: "club.status.set",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: { reason: "R2 staging cleanup", status: "archived" },
      surface: "club-foundation-staging-cleanup",
    });
  }
}

try {
  platformOwner = await signIn(USERS.platformOwner);
  ownerDesktop = await signIn(USERS.ownerA);
  ownerMobile = await signIn(USERS.ownerA);
  adminA = await signIn(USERS.adminA);
  playerA = await signIn(USERS.playerA);
  ownerB = await signIn(USERS.ownerB);
  ownerBMobile = await signIn(USERS.ownerB);
  staffA = await signIn(USERS.staffA);
  platformAdmin = await signIn(USERS.platformAdmin);
  clients.push(
    platformOwner,
    ownerDesktop,
    ownerMobile,
    adminA,
    playerA,
    ownerB,
    ownerBMobile,
    staffA,
    platformAdmin,
  );
  await ensurePlatformAdmin(platformOwner, platformAdmin);

  const anonymous = client();
  const initialFlags = await clubFlags(platformOwner);
  assert.equal(initialFlags.foundationEnabled, false);
  assert.equal(initialFlags.selfServiceCreationEnabled, false);

  const disabledClubId = randomUUID();
  const disabledCreate = await command(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "club.create",
    aggregateId: disabledClubId,
    expectedRevision: 0,
    payload: {
      clubType: "FOOTBALL_CLUB",
      name: "Disabled R2 staging Club",
      slug: `disabled-r2-${Date.now()}`,
    },
  });
  expectRpcError(disabledCreate, /CLUB_FOUNDATION_DISABLED|CLUB_SELF_SERVICE_CREATION_DISABLED/);

  await setClubFlags(platformOwner, {
    competitionOrganizerEnabled: true,
    foundationEnabled: true,
    publicProfilesEnabled: true,
    selfServiceCreationEnabled: true,
    teamRelationshipsEnabled: true,
  }, "R2 authenticated staging QA");
  await setCompetitionFlags(platformOwner, {
    contextBindingEnabled: false,
    creationEnabled: true,
    foundationEnabled: true,
  }, "R2 Club organizer staging QA");

  const runTag = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  const clubAId = randomUUID();
  const clubBId = randomUUID();
  fixtureClubs.push(clubAId, clubBId);
  fixtureOwners.set(clubAId, USERS.ownerA.id);
  fixtureOwners.set(clubBId, USERS.playerA.id);

  const createAOperation = randomUUID();
  const createAInput = {
    action: "club.create",
    aggregateId: clubAId,
    expectedRevision: 0,
    operationId: createAOperation,
    payload: {
      clubType: "FOOTBALL_CLUB",
      countryCode: "ES",
      description: "Private R2 staging description",
      generalArea: "Eixample",
      municipality: "Barcelona",
      name: `Club A R2 ${runTag}`,
      placeId: "r2-private-place-id",
      province: "Barcelona",
      reason: "R2 staging Club A create",
      slug: `club-a-r2-${runTag}`,
      visibility: "private",
    },
  };
  const createdA = await commandOk(
    ownerDesktop,
    "command_pachanga_club_foundation_v1",
    createAInput,
  );
  const createAReplay = await commandOk(
    ownerMobile,
    "command_pachanga_club_foundation_v1",
    createAInput,
  );
  assert.deepEqual(createAReplay, createdA);
  assert.equal(clubFrom(createdA).primaryOwnerId, USERS.ownerA.id);
  assert.equal(membershipFrom(createdA.snapshot, USERS.ownerA.id).role, "club_owner");

  const createdB = await commandOk(playerA, "command_pachanga_club_foundation_v1", {
    action: "club.create",
    aggregateId: clubBId,
    expectedRevision: 0,
    payload: {
      clubType: "ASSOCIATION",
      countryCode: "ES",
      municipality: "Badalona",
      name: `Club B R2 ${runTag}`,
      province: "Barcelona",
      reason: "R2 staging Club B create",
      slug: `club-b-r2-${runTag}`,
      visibility: "private",
    },
  });
  assert.equal(clubFrom(createdB).operationalStatus, "draft");

  const duplicateSlug = `club-race-r2-${runTag}`;
  const slugRaceIds = [randomUUID(), randomUUID()];
  const slugRace = await Promise.all(slugRaceIds.map((aggregateId, index) => (
    command(ownerDesktop, "command_pachanga_club_foundation_v1", {
      action: "club.create",
      aggregateId,
      expectedRevision: 0,
      payload: {
        clubType: "OTHER",
        name: `Slug race ${index} ${runTag}`,
        reason: "R2 same slug race",
        slug: duplicateSlug,
      },
    })
  )));
  assert.equal(slugRace.filter((result) => !result.error).length, 1);
  assert.equal(slugRace.filter((result) => result.error).length, 1);
  expectRpcError(slugRace.find((result) => result.error), /CLUB_CONFLICT/, "PT409");
  const slugRaceClub = clubFrom(slugRace.find((result) => !result.error).data);
  fixtureClubs.push(slugRaceClub.id);
  fixtureOwners.set(slugRaceClub.id, USERS.ownerA.id);

  const directInsert = await ownerDesktop.from("pachanga_clubs").insert({
    id: randomUUID(),
    name: "Forbidden direct Club",
    primary_owner_id: USERS.ownerA.id,
    slug: `forbidden-${runTag}`,
  });
  assert.ok(directInsert.error);

  const invalidations = createInvalidationQueue("Club");
  const profileChannel = ownerMobile
    .channel(`club-r2-profile-${randomUUID()}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `club_id=eq.${clubAId}`,
      schema: "public",
      table: "pachanga_club_invalidations",
    }, (payload) => invalidations.push(payload));
  channels.push([ownerMobile, profileChannel]);
  await waitForSubscription(profileChannel);

  invalidations.clear();
  const profileInvalidation = invalidations.next();
  const profileUpdated = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "club.profile.update",
    aggregateId: clubAId,
    expectedRevision: clubFrom(createdA).revision,
    payload: {
      description: "Canonical profile updated from desktop",
      municipality: "Barcelona",
      name: `Club A R2 ${runTag}`,
      reason: "R2 desktop profile update",
      visibility: "public",
    },
  });
  const invalidationPayload = await profileInvalidation;
  assert.equal(invalidationPayload.new.club_id, clubAId);
  assert.equal(invalidationPayload.new.revision, profileUpdated.confirmedRevision);
  const mobileRefetch = await clubSnapshot(ownerMobile, clubAId);
  assert.equal(mobileRefetch.club.description, "Canonical profile updated from desktop");

  const staleProfile = await command(ownerMobile, "command_pachanga_club_foundation_v1", {
    action: "club.profile.update",
    aggregateId: clubAId,
    expectedRevision: clubFrom(createdA).revision,
    payload: { description: "Stale mobile value", reason: "R2 stale profile" },
  });
  expectRpcError(staleProfile, /STALE_REVISION/, "PT409");

  const clubAConsent = await confirmClubPublication(ownerDesktop, clubAId, profileUpdated.snapshot.club.revision);
  const reviewSubmitted = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "club.review.submit",
    aggregateId: clubAId,
    expectedRevision: clubAConsent.confirmedRevision,
    payload: { reason: "R2 submit Club A review" },
  });
  assert.equal(reviewSubmitted.snapshot.club.operationalStatus, "pending_review");
  assert.equal(reviewSubmitted.snapshot.club.verificationStatus, "pending");

  let clubAPlatform = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.status.set",
    aggregateId: clubAId,
    expectedRevision: reviewSubmitted.snapshot.club.revision,
    payload: { reason: "R2 approve Club A", status: "active" },
  });
  clubAPlatform = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.verification.set",
    aggregateId: clubAId,
    expectedRevision: clubAPlatform.snapshot.club.revision,
    payload: { reason: "R2 verify Club A", status: "verified" },
  });
  clubAPlatform = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.partnership.set",
    aggregateId: clubAId,
    expectedRevision: clubAPlatform.snapshot.club.revision,
    payload: { reason: "R2 partner Club A", status: "active" },
  });
  assert.equal(clubAPlatform.snapshot.club.partnershipStatus, "active");
  assert.equal(clubAPlatform.snapshot.entitlements.canCreate, false);

  const clubBConsent = await confirmClubPublication(playerA, clubBId, createdB.snapshot.club.revision);
  const clubBReview = await commandOk(playerA, "command_pachanga_club_foundation_v1", {
    action: "club.review.submit",
    aggregateId: clubBId,
    expectedRevision: clubBConsent.confirmedRevision,
    payload: { reason: "R2 submit Club B review" },
  });
  let clubBPlatform = await commandOk(platformAdmin, "command_pachanga_club_platform_v1", {
    action: "club.status.set",
    aggregateId: clubBId,
    expectedRevision: clubBReview.snapshot.club.revision,
    payload: { reason: "R2 activate Club B", status: "active" },
  });

  const anonymousPublic = await rpc(anonymous, "get_pachanga_public_club_v1", {
    target_slug: clubAPlatform.snapshot.club.slug,
  });
  assert.equal(anonymousPublic.name, clubAPlatform.snapshot.club.name);
  assert.equal(anonymousPublic.verified, true);
  assert.equal(anonymousPublic.partner, true);
  const publicSerialized = JSON.stringify(anonymousPublic);
  for (const secret of ["primaryOwnerId", "memberships", "placeId", "entitlements", "@"] ) {
    assert.equal(publicSerialized.includes(secret), false, `Public model leaked ${secret}`);
  }

  const outsiderRead = await ownerB.rpc("get_pachanga_club_foundation_snapshot_v1", {
    target_club_id: clubAId,
  });
  expectRpcError(outsiderRead, /CLUB_NOT_FOUND_OR_FORBIDDEN/, "42501");

  // A Team request predates the future Club admin. It must not be replayed as a historical notification.
  let clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const prehistoryRequestOperation = randomUUID();
  const prehistoryRequest = await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.request",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: prehistoryRequestOperation,
    payload: {
      groupId: GROUP_B,
      reason: "R2 prehistory request",
      relationshipType: "HOSTED",
    },
  });
  const prehistoryRelationship = relationshipFrom(
    prehistoryRequest.snapshot,
    (item) => item.groupId === GROUP_B && item.status === "requested",
  );

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const adminInviteOperation = randomUUID();
  const adminInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: adminInviteOperation,
    payload: {
      reason: "R2 invite Club admin",
      role: "club_admin",
      targetKind: "registered_user",
      targetUserId: USERS.adminA.id,
    },
  });
  assert.equal(adminInvite.oneTimeToken.length, 64);
  const adminInviteReplay = await commandOk(ownerMobile, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: adminInviteOperation,
    payload: {
      reason: "R2 invite Club admin",
      role: "club_admin",
      targetKind: "registered_user",
      targetUserId: USERS.adminA.id,
    },
  });
  assert.equal(adminInviteReplay.serverSequence, adminInvite.serverSequence);
  assert.equal("oneTimeToken" in adminInviteReplay, false);
  assert.equal(await notificationCount(
    adminA,
    `club-staff-invitation:${adminInviteOperation}:${USERS.adminA.id}`,
  ), 1);

  const adminAcceptOperation = randomUUID();
  const adminAccepted = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: adminInvite.invitationId,
    expectedRevision: 1,
    operationId: adminAcceptOperation,
    payload: { reason: "R2 accept Club admin", token: adminInvite.oneTimeToken },
  });
  for (const field of ["oneTimeToken", "invitationId", "tokenReturnedOnce"]) {
    assert.equal(field in adminAccepted, false, `membership.accept must not return ${field}`);
  }
  const adminAcceptedReplay = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: adminInvite.invitationId,
    expectedRevision: 1,
    operationId: adminAcceptOperation,
    payload: { reason: "R2 accept Club admin", token: adminInvite.oneTimeToken },
  });
  assert.deepEqual(adminAcceptedReplay, adminAccepted);
  assert.equal(membershipFrom(adminAccepted.snapshot, USERS.adminA.id).role, "club_admin");
  assert.equal(await notificationCount(
    adminA,
    `club-team-request:${prehistoryRequestOperation}:${USERS.adminA.id}`,
  ), 0);

  const prehistoryRejected = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.reject",
    aggregateId: prehistoryRelationship.id,
    expectedRevision: prehistoryRelationship.revision,
    payload: { reason: "R2 close prehistory request" },
  });
  assert.equal(relationshipFrom(
    prehistoryRejected.snapshot,
    (item) => item.id === prehistoryRelationship.id,
  ).status, "rejected");

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const managerInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 invite competition manager",
      role: "club_competition_manager",
      targetKind: "registered_user",
      targetUserId: USERS.staffA.id,
    },
  });
  const alteredToken = `${managerInvite.oneTimeToken.slice(0, 63)}${managerInvite.oneTimeToken.endsWith("0") ? "1" : "0"}`;
  const alteredAccept = await command(staffA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: managerInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 altered token", token: alteredToken },
  });
  expectRpcError(alteredAccept, /CLUB_INVITATION_TOKEN_INVALID/, "42501");
  const managerAccepted = await commandOk(staffA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: managerInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 accept competition manager", token: managerInvite.oneTimeToken },
  });
  assert.equal(membershipFrom(managerAccepted.snapshot, USERS.staffA.id).role, "club_competition_manager");
  const managerCannotInvite = await command(staffA, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: managerAccepted.snapshot.club.revision,
    payload: {
      reason: "R2 manager forbidden staff change",
      role: "club_viewer",
      targetKind: "registered_user",
      targetUserId: USERS.playerA.id,
    },
  });
  expectRpcError(managerCannotInvite, /CLUB_CAPABILITY_REQUIRED/, "42501");

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const emailInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 email viewer invitation",
      role: "club_viewer",
      targetEmail: USERS.platformAdmin.email,
      targetKind: "email_target",
    },
  });
  const wrongEmailAccept = await command(ownerB, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: emailInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 wrong email", token: emailInvite.oneTimeToken },
  });
  expectRpcError(wrongEmailAccept, /CLUB_INVITATION_EMAIL_MISMATCH/, "42501");
  const resolvedEmailInvite = await rpc(platformAdmin, "get_pachanga_club_invitation_v1", {
    invitation_token: emailInvite.oneTimeToken,
    target_invitation_id: emailInvite.invitationId,
  });
  assert.equal(resolvedEmailInvite.clubId, clubAId);
  const viewerAccepted = await commandOk(platformAdmin, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: emailInvite.invitationId,
    expectedRevision: resolvedEmailInvite.revision,
    payload: { reason: "R2 accept email viewer", token: emailInvite.oneTimeToken },
  });
  assert.equal(membershipFrom(viewerAccepted.snapshot, USERS.platformAdmin.id).role, "club_viewer");
  const reusedToken = await command(platformAdmin, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: emailInvite.invitationId,
    expectedRevision: 2,
    payload: { reason: "R2 token reuse", token: emailInvite.oneTimeToken },
  });
  expectRpcError(reusedToken, /CLUB_INVITATION_NOT_PENDING|CLUB_INVITATION_TOKEN_INVALID/, "PT409");

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const viewerMembership = membershipFrom(clubASnapshot, USERS.platformAdmin.id);
  await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.revoke",
    aggregateId: viewerMembership.id,
    expectedRevision: viewerMembership.revision,
    payload: { reason: "R2 revoke viewer after email QA" },
  });

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const revokedInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 revocable email invitation",
      role: "club_viewer",
      targetEmail: USERS.playerA.email,
      targetKind: "email_target",
    },
  });
  await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invitation.revoke",
    aggregateId: revokedInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 revoke invitation" },
  });
  const revokedTokenUse = await command(playerA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: revokedInvite.invitationId,
    expectedRevision: 2,
    payload: { reason: "R2 revoked token use", token: revokedInvite.oneTimeToken },
  });
  expectRpcError(revokedTokenUse, /CLUB_INVITATION_NOT_PENDING|CLUB_INVITATION_TOKEN_INVALID/, "PT409");

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const expiringInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      expiresAt: new Date(Date.now() + 1_500).toISOString(),
      reason: "R2 expiring email invitation",
      role: "club_viewer",
      targetEmail: USERS.adminA.email,
      targetKind: "email_target",
    },
  });
  await new Promise((resolve) => setTimeout(resolve, 1_800));
  const expiredTokenUse = await command(adminA, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: expiringInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 expired token", token: expiringInvite.oneTimeToken },
  });
  expectRpcError(expiredTokenUse, /CLUB_INVITATION_EXPIRED/, "42501");
  await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invitation.revoke",
    aggregateId: expiringInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 cleanup expired invitation" },
  });

  const inventedToken = await ownerB.rpc("get_pachanga_club_invitation_v1", {
    invitation_token: "0".repeat(64),
    target_invitation_id: randomUUID(),
  });
  expectRpcError(inventedToken, /CLUB_INVITATION_TOKEN_INVALID/, "42501");

  // Club A invites Team A. Team admin cannot respond; two owner devices race.
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const teamInviteOperation = randomUUID();
  const teamInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: teamInviteOperation,
    payload: {
      groupId: GROUP_A,
      reason: "R2 invite Team A",
      relationshipType: "AFFILIATED",
    },
  });
  const teamInviteReplay = await commandOk(ownerMobile, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: teamInviteOperation,
    payload: {
      groupId: GROUP_A,
      reason: "R2 invite Team A",
      relationshipType: "AFFILIATED",
    },
  });
  assert.deepEqual(teamInviteReplay, teamInvite);
  const invitedTeamA = relationshipFrom(
    teamInvite.snapshot,
    (item) => item.groupId === GROUP_A && item.status === "invited",
  );
  const teamAdminResponse = await command(adminA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.accept",
    aggregateId: invitedTeamA.id,
    expectedRevision: invitedTeamA.revision,
    payload: { reason: "R2 Team admin forbidden" },
  });
  expectRpcError(teamAdminResponse, /TEAM_OWNER_REQUIRED/, "42501");

  const relationshipRace = await Promise.all([
    command(ownerDesktop, "command_pachanga_club_foundation_v1", {
      action: "team_relationship.accept",
      aggregateId: invitedTeamA.id,
      expectedRevision: invitedTeamA.revision,
      payload: { reason: "R2 owner desktop accepts" },
    }),
    command(ownerMobile, "command_pachanga_club_foundation_v1", {
      action: "team_relationship.reject",
      aggregateId: invitedTeamA.id,
      expectedRevision: invitedTeamA.revision,
      payload: { reason: "R2 owner mobile rejects" },
    }),
  ]);
  assert.equal(relationshipRace.filter((result) => !result.error).length, 1);
  assert.equal(relationshipRace.filter((result) => result.error).length, 1);
  expectRpcError(
    relationshipRace.find((result) => result.error),
    /STALE_REVISION|CLUB_TEAM_RELATIONSHIP_NOT_PENDING/,
  );
  const teamARaceWinner = relationshipRace.find((result) => !result.error).data;
  const racedTeamA = relationshipFrom(teamARaceWinner.snapshot, (item) => item.id === invitedTeamA.id);
  if (racedTeamA.status === "active") {
    await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
      action: "team_relationship.visibility.set",
      aggregateId: racedTeamA.id,
      expectedRevision: racedTeamA.revision,
      payload: { reason: "R2 Team profile consent", showOnClubProfile: true },
    });
    const visibleSnapshot = await clubSnapshot(ownerDesktop, clubAId);
    const visibleTeamA = relationshipFrom(visibleSnapshot, (item) => item.id === racedTeamA.id);
    await commandOk(adminA, "command_pachanga_club_foundation_v1", {
      action: "team_relationship.end",
      aggregateId: visibleTeamA.id,
      expectedRevision: visibleTeamA.revision,
      payload: { reason: "R2 Club admin ends Team A link" },
    });
  }

  // Ensure an accepted Team A link and public consent independently of the race outcome.
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const secondTeamAInvite = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      groupId: GROUP_A,
      reason: "R2 deterministic Team A link",
      relationshipType: "MEMBER",
    },
  });
  const secondTeamARelationship = relationshipFrom(
    secondTeamAInvite.snapshot,
    (item) => item.groupId === GROUP_A && item.status === "invited",
  );
  let acceptedTeamA = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.accept",
    aggregateId: secondTeamARelationship.id,
    expectedRevision: secondTeamARelationship.revision,
    payload: { reason: "R2 Team A owner accepts" },
  });
  let acceptedTeamARelationship = relationshipFrom(
    acceptedTeamA.snapshot,
    (item) => item.id === secondTeamARelationship.id,
  );
  acceptedTeamA = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.visibility.set",
    aggregateId: acceptedTeamARelationship.id,
    expectedRevision: acceptedTeamARelationship.revision,
    payload: { reason: "R2 Team A profile consent", showOnClubProfile: true },
  });
  acceptedTeamARelationship = relationshipFrom(
    acceptedTeamA.snapshot,
    (item) => item.id === secondTeamARelationship.id,
  );
  assert.equal(acceptedTeamARelationship.showOnClubProfile, true);

  const teamOwnerLimited = await clubSnapshot(ownerDesktop, clubAId);
  assert.equal(teamOwnerLimited.capabilities.read, true, "Club owner remains a full Club reader");
  const publicWithTeam = await rpc(anonymous, "get_pachanga_public_club_v1", {
    target_slug: clubAPlatform.snapshot.club.slug,
  });
  assert.ok(publicWithTeam.teams.some((team) => team.name));

  // Team B request accepted by the Club admin, then ended by the Team owner.
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const teamBRequest = await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.request",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      groupId: GROUP_B,
      reason: "R2 Team B requests Club A",
      relationshipType: "HOSTED",
    },
  });
  const requestedTeamB = relationshipFrom(
    teamBRequest.snapshot,
    (item) => item.groupId === GROUP_B && item.status === "requested",
  );
  const teamBAccepted = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.accept",
    aggregateId: requestedTeamB.id,
    expectedRevision: requestedTeamB.revision,
    payload: { reason: "R2 Club admin accepts Team B" },
  });
  const activeTeamB = relationshipFrom(teamBAccepted.snapshot, (item) => item.id === requestedTeamB.id);
  assert.equal(activeTeamB.status, "active");

  const teamBOwnerView = await clubSnapshot(ownerB, clubAId);
  assert.equal(teamBOwnerView.capabilities.read, false);
  assert.equal(teamBOwnerView.club.description, null);
  assert.equal(teamBOwnerView.club.placeId, null);
  assert.equal(teamBOwnerView.club.primaryOwnerId, null);
  assert.deepEqual(teamBOwnerView.memberships, []);
  assert.deepEqual(teamBOwnerView.pendingInvitations, []);
  assert.deepEqual(teamBOwnerView.entitlements, []);
  assert.ok(teamBOwnerView.teamRelationships.length >= 1);
  assert.ok(teamBOwnerView.teamRelationships.every((item) => item.groupId === GROUP_B));
  assert.ok(teamBOwnerView.teamRelationships.some((item) => (
    item.id === activeTeamB.id && item.status === "active"
  )));

  const teamBEnded = await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.end",
    aggregateId: activeTeamB.id,
    expectedRevision: activeTeamB.revision,
    payload: { reason: "R2 Team B owner ends link" },
  });
  assert.ok(relationshipFrom(
    teamBEnded.snapshot,
    (item) => item.id === activeTeamB.id,
  ).endedAt);

  // Explicit rejection and cancellation preserve separate history rows.
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const rejectInvite = await commandOk(adminA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: { groupId: GROUP_B, reason: "R2 rejection path", relationshipType: "MEMBER" },
  });
  const rejectRelationship = relationshipFrom(
    rejectInvite.snapshot,
    (item) => item.groupId === GROUP_B && item.status === "invited",
  );
  await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.reject",
    aggregateId: rejectRelationship.id,
    expectedRevision: rejectRelationship.revision,
    payload: { reason: "R2 Team B rejects" },
  });
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const cancelRequest = await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.request",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: { groupId: GROUP_B, reason: "R2 cancellation path", relationshipType: "AFFILIATED" },
  });
  const cancelRelationship = relationshipFrom(
    cancelRequest.snapshot,
    (item) => item.groupId === GROUP_B && item.status === "requested",
  );
  await commandOk(ownerB, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.cancel",
    aggregateId: cancelRelationship.id,
    expectedRevision: cancelRelationship.revision,
    payload: { reason: "R2 Team B cancels" },
  });
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  assert.ok(clubASnapshot.teamRelationships.some((item) => item.status === "rejected"));
  assert.ok(clubASnapshot.teamRelationships.some((item) => item.status === "cancelled"));
  assert.ok(clubASnapshot.teamRelationships.some((item) => item.status === "ended"));

  // Multi-Club: Team A is linked to Club B without changing Team authority.
  const clubBInvite = await commandOk(playerA, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.invite",
    aggregateId: clubBId,
    expectedRevision: clubBPlatform.snapshot.club.revision,
    payload: { groupId: GROUP_A, reason: "R2 multi-Club", relationshipType: "HOSTED" },
  });
  const clubBTeamA = relationshipFrom(clubBInvite.snapshot, (item) => item.status === "invited");
  const clubBLinked = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.accept",
    aggregateId: clubBTeamA.id,
    expectedRevision: clubBTeamA.revision,
    payload: { reason: "R2 Team A accepts second Club" },
  });
  const clubBActive = relationshipFrom(clubBLinked.snapshot, (item) => item.id === clubBTeamA.id);
  assert.equal(clubBActive.status, "active");
  await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "team_relationship.end",
    aggregateId: clubBActive.id,
    expectedRevision: clubBActive.revision,
    payload: { reason: "R2 Team owner ends second Club" },
  });

  // Concurrent invitation acceptance creates exactly one active owner membership.
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const ownerInvite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 invite next owner",
      role: "club_owner",
      targetKind: "registered_user",
      targetUserId: USERS.ownerB.id,
    },
  });
  const ownerAcceptRace = await Promise.all([
    command(ownerB, "command_pachanga_club_foundation_v1", {
      action: "membership.accept",
      aggregateId: ownerInvite.invitationId,
      expectedRevision: 1,
      payload: { reason: "R2 owner accept desktop", token: ownerInvite.oneTimeToken },
    }),
    command(ownerBMobile, "command_pachanga_club_foundation_v1", {
      action: "membership.accept",
      aggregateId: ownerInvite.invitationId,
      expectedRevision: 1,
      payload: { reason: "R2 owner accept mobile", token: ownerInvite.oneTimeToken },
    }),
  ]);
  assert.equal(ownerAcceptRace.filter((result) => !result.error).length, 1);
  assert.equal(ownerAcceptRace.filter((result) => result.error).length, 1);
  expectRpcError(
    ownerAcceptRace.find((result) => result.error),
    /STALE_REVISION|CLUB_INVITATION_NOT_PENDING|CLUB_INVITATION_TOKEN_INVALID/,
  );
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  assert.equal(clubASnapshot.memberships.filter((item) => (
    item.userId === USERS.ownerB.id && item.role === "club_owner" && item.status === "active"
  )).length, 1);

  const owner2Invite = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.invite",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 invite second transfer target",
      role: "club_owner",
      targetKind: "registered_user",
      targetUserId: USERS.platformAdmin.id,
    },
  });
  await commandOk(platformAdmin, "command_pachanga_club_foundation_v1", {
    action: "membership.accept",
    aggregateId: owner2Invite.invitationId,
    expectedRevision: 1,
    payload: { reason: "R2 accept second owner", token: owner2Invite.oneTimeToken },
  });

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const forbiddenAdminTransfer = await command(adminA, "command_pachanga_club_foundation_v1", {
    action: "club.primary_owner.transfer",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: {
      reason: "R2 admin transfer forbidden",
      retainPreviousOwner: true,
      targetUserId: USERS.ownerB.id,
    },
  });
  expectRpcError(forbiddenAdminTransfer, /CLUB_CAPABILITY_REQUIRED/, "42501");

  const transferRace = await Promise.all([
    command(ownerDesktop, "command_pachanga_club_foundation_v1", {
      action: "club.primary_owner.transfer",
      aggregateId: clubAId,
      expectedRevision: clubASnapshot.club.revision,
      payload: {
        reason: "R2 transfer race owner B",
        retainPreviousOwner: true,
        targetUserId: USERS.ownerB.id,
      },
    }),
    command(ownerMobile, "command_pachanga_club_foundation_v1", {
      action: "club.primary_owner.transfer",
      aggregateId: clubAId,
      expectedRevision: clubASnapshot.club.revision,
      payload: {
        reason: "R2 transfer race platform admin",
        retainPreviousOwner: true,
        targetUserId: USERS.platformAdmin.id,
      },
    }),
  ]);
  assert.equal(transferRace.filter((result) => !result.error).length, 1);
  assert.equal(transferRace.filter((result) => result.error).length, 1);
  expectRpcError(transferRace.find((result) => result.error), /STALE_REVISION/, "PT409");

  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  if (clubASnapshot.club.primaryOwnerId !== USERS.ownerA.id) {
    await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
      action: "club.primary_owner.transfer",
      aggregateId: clubAId,
      expectedRevision: clubASnapshot.club.revision,
      payload: {
        reason: "R2 restore owner before replay test",
        retainPreviousOwner: true,
        targetUserId: USERS.ownerA.id,
      },
    });
  }
  clubASnapshot = await clubSnapshot(ownerDesktop, clubAId);
  const transferOperation = randomUUID();
  const transferred = await commandOk(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "club.primary_owner.transfer",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: transferOperation,
    payload: {
      reason: "R2 deterministic transfer",
      retainPreviousOwner: true,
      targetUserId: USERS.ownerB.id,
    },
  });
  const transferReplay = await commandOk(ownerMobile, "command_pachanga_club_foundation_v1", {
    action: "club.primary_owner.transfer",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: transferOperation,
    payload: {
      reason: "R2 deterministic transfer",
      retainPreviousOwner: true,
      targetUserId: USERS.ownerB.id,
    },
  });
  assert.deepEqual(transferReplay, transferred);
  const primaryMembership = membershipFrom(transferred.snapshot, USERS.ownerB.id);
  const revokePrimary = await command(ownerDesktop, "command_pachanga_club_foundation_v1", {
    action: "membership.revoke",
    aggregateId: primaryMembership.id,
    expectedRevision: primaryMembership.revision,
    payload: { reason: "R2 cannot revoke primary" },
  });
  expectRpcError(revokePrimary, /PRIMARY_OWNER_TRANSFER_REQUIRED/, "42501");

  // Club B has no grant. Partnership alone also does not grant creation.
  const noGrantOrganizer = await rpc(playerA, "get_my_pachanga_competition_foundation_v1");
  const clubBOrganizer = noGrantOrganizer.clubOrganizers.find((item) => item.clubId === clubBId);
  assert.ok(clubBOrganizer);
  assert.equal(clubBOrganizer.entitlement.canCreate, false);
  const noGrantCreate = await competitionCommand(playerA, {
    aggregateId: clubBId,
    expectedRevision: clubBOrganizer.entitlement.organizerRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "R2 Club B without grant",
      slug: `r2-club-b-no-grant-${runTag}`,
    },
  });
  expectRpcError(noGrantCreate, /COMPETITION_ENTITLEMENT_REQUIRED/, "42501");

  const clubBBeforePartnership = await clubSnapshot(playerA, clubBId);
  clubBPlatform = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.partnership.set",
    aggregateId: clubBId,
    expectedRevision: clubBBeforePartnership.club.revision,
    payload: { reason: "R2 activate Club B partnership", status: "active" },
  });
  assert.equal(clubBPlatform.snapshot.entitlements.canCreate, false);

  const expiredGrant = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.entitlement.grant",
    aggregateId: clubBId,
    expectedRevision: clubBPlatform.snapshot.club.revision,
    payload: {
      capability: "competition_create",
      expiresAt: "2026-01-02T00:00:00Z",
      reason: "R2 expired partnership grant",
      source: "partnership",
      validFrom: "2026-01-01T00:00:00Z",
    },
  });
  assert.equal(expiredGrant.snapshot.entitlements.canCreate, false);
  const expiredCreate = await competitionCommand(playerA, {
    aggregateId: clubBId,
    expectedRevision: expiredGrant.snapshot.entitlements.organizerRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "R2 expired grant reject",
      slug: `r2-expired-${runTag}`,
    },
  });
  expectRpcError(expiredCreate, /COMPETITION_ENTITLEMENT_REQUIRED/, "42501");

  const clubBGrantRaceRevision = expiredGrant.snapshot.club.revision;
  const grantRace = await Promise.all([
    command(platformOwner, "command_pachanga_club_platform_v1", {
      action: "club.entitlement.grant",
      aggregateId: clubBId,
      expectedRevision: clubBGrantRaceRevision,
      payload: {
        capability: "competition_create",
        reason: "R2 partnership grant race owner",
        source: "partnership",
      },
    }),
    command(platformAdmin, "command_pachanga_club_platform_v1", {
      action: "club.entitlement.grant",
      aggregateId: clubBId,
      expectedRevision: clubBGrantRaceRevision,
      payload: {
        capability: "competition_create",
        reason: "R2 partnership grant race admin",
        source: "partnership",
      },
    }),
  ]);
  assert.equal(grantRace.filter((result) => !result.error).length, 1);
  assert.equal(grantRace.filter((result) => result.error).length, 1);
  expectRpcError(grantRace.find((result) => result.error), /STALE_REVISION/, "PT409");
  const clubBGrantWinner = grantRace.find((result) => !result.error).data;
  assert.equal(clubBGrantWinner.snapshot.entitlements.canCreate, true);

  // Grant Club A explicitly; replay has one effect.
  clubASnapshot = await clubSnapshot(platformOwner, clubAId);
  const grantAOperation = randomUUID();
  const grantAInput = {
    action: "club.entitlement.grant",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    operationId: grantAOperation,
    payload: {
      capability: "competition_create",
      reason: "R2 Club A platform grant",
      source: "platform_grant",
    },
  };
  const grantA = await commandOk(platformOwner, "command_pachanga_club_platform_v1", grantAInput);
  const grantAReplay = await commandOk(platformOwner, "command_pachanga_club_platform_v1", grantAInput);
  assert.deepEqual(grantAReplay, grantA);
  assert.equal(grantA.snapshot.entitlements.canCreate, true);

  const adminCreate = await competitionCommand(adminA, {
    aggregateId: clubAId,
    expectedRevision: grantA.snapshot.entitlements.organizerRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "R2 Club admin forbidden",
      slug: `r2-admin-forbidden-${runTag}`,
    },
  });
  expectRpcError(adminCreate, /CLUB_COMPETITION_MANAGER_REQUIRED/, "42501");

  const competitionOperation = randomUUID();
  const competitionInput = {
    aggregateId: clubAId,
    expectedRevision: grantA.snapshot.entitlements.organizerRevision,
    operationId: competitionOperation,
    payload: {
      competitionType: "LEAGUE",
      editionName: "Edicion R2",
      name: `Liga Club R2 ${runTag}`,
      reason: "R2 Club manager creates Competition",
      ruleSetName: "Reglamento principal",
      seasonLabel: "2026/27",
      slug: `liga-club-r2-${runTag}`,
      visibility: "private",
    },
  };
  const createdCompetition = await competitionCommandOk(staffA, competitionInput);
  const createdCompetitionReplay = await competitionCommandOk(staffA, competitionInput);
  assert.deepEqual(createdCompetitionReplay, createdCompetition);
  assert.equal(createdCompetition.snapshot.competition.organizerKind, "CLUB");
  assert.equal(createdCompetition.snapshot.competition.organizerClubId, clubAId);
  assert.equal(createdCompetition.snapshot.editions.length, 1);
  assert.equal(createdCompetition.snapshot.ruleSets.length, 1);
  const createdDirectorAssignment = createdCompetition.snapshot.staff.find((assignment) => (
    assignment.userId === USERS.staffA.id
    && assignment.role === "competition_director"
    && assignment.status === "active"
  ));
  assert.ok(createdDirectorAssignment);
  fixtureCompetitionAssignments.push({
    competitionId: createdCompetition.snapshot.competition.id,
    staffAssignmentId: createdDirectorAssignment.id,
  });

  const platformCompetitions = await rpc(platformOwner, "get_pachanga_platform_competition_foundation_v2", {
    page_offset: 0,
    page_size: 200,
  });
  assert.ok(platformCompetitions.items.some((item) => (
    item.id === createdCompetition.snapshot.competition.id
    && item.organizerKind === "CLUB"
    && item.organizerClubId === clubAId
  )));

  const staffCrossClub = await staffA.rpc("get_pachanga_club_foundation_snapshot_v1", {
    target_club_id: clubBId,
  });
  expectRpcError(staffCrossClub, /CLUB_NOT_FOUND_OR_FORBIDDEN/, "42501");

  // Existing draft survives suspension; new creation is blocked.
  clubASnapshot = await clubSnapshot(platformOwner, clubAId);
  const suspended = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.status.set",
    aggregateId: clubAId,
    expectedRevision: clubASnapshot.club.revision,
    payload: { reason: "R2 suspension QA", status: "suspended" },
  });
  const suspendedCreate = await competitionCommand(staffA, {
    aggregateId: clubAId,
    expectedRevision: createdCompetition.confirmedRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "R2 suspended Club reject",
      slug: `r2-suspended-${runTag}`,
    },
  });
  expectRpcError(suspendedCreate, /CLUB_MUST_BE_ACTIVE/, "42501");
  assert.ok(suspended.snapshot.competitions.some((item) => (
    item.id === createdCompetition.snapshot.competition.id
  )));
  await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.status.set",
    aggregateId: clubAId,
    expectedRevision: suspended.snapshot.club.revision,
    payload: { reason: "R2 restore after suspension QA", status: "active" },
  });

  const activeGrantB = clubBGrantWinner.snapshot.entitlements.grants.find((grant) => grant.status === "active");
  assert.ok(activeGrantB);
  const revokeB = await commandOk(platformOwner, "command_pachanga_club_platform_v1", {
    action: "club.entitlement.revoke",
    aggregateId: clubBId,
    expectedRevision: clubBGrantWinner.snapshot.club.revision,
    payload: {
      entitlementId: activeGrantB.id,
      reason: "R2 explicit Club B revocation",
    },
  });
  assert.equal(revokeB.snapshot.entitlements.canCreate, false);
  const revokedCreate = await competitionCommand(playerA, {
    aggregateId: clubBId,
    expectedRevision: revokeB.snapshot.entitlements.organizerRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "R2 revoked Club B reject",
      slug: `r2-revoked-${runTag}`,
    },
  });
  expectRpcError(revokedCreate, /COMPETITION_ENTITLEMENT_REQUIRED/, "42501");

  const adminGlobalSearch = await rpc(platformAdmin, "search_pachanga_platform_v1", {
    result_limit: 50,
    search_text: `Club A R2 ${runTag}`,
  });
  assert.ok(adminGlobalSearch.some((item) => (
    item.type === "club" && item.id === clubAId
  )));

  const platformClub = await rpc(platformOwner, "get_pachanga_platform_club_v1", {
    target_club_id: clubAId,
  });
  assert.equal(platformClub.club.id, clubAId);
  assert.ok(platformClub.recentEvents.length > 0);
  assert.equal(JSON.stringify(platformClub).includes("oneTimeToken"), false);
  assert.equal(JSON.stringify(platformClub).includes(adminInvite.oneTimeToken), false);

  // The direct TEAM V2 adapter is still exactly the V1 path; the full R1 E2E runs separately.
  const teamReadBefore = await rpc(ownerDesktop, "get_my_pachanga_competition_foundation_v1");
  assert.ok(teamReadBefore.organizers.some((item) => item.groupId === GROUP_A));

  completed = true;
  console.log(JSON.stringify({
    clubA: clubAId,
    clubB: clubBId,
    competition: createdCompetition.snapshot.competition.id,
    idempotency: "confirmed",
    invitations: "registered_email_expired_revoked_reused",
    ownerTransfer: "concurrent_and_replay",
    privacy: "public_and_team_owner_minimized",
    realtime: "invalidation_then_refetch",
    relationships: "invite_request_reject_cancel_end_multiclub",
    status: "PASS",
  }));
} finally {
  if (platformOwner) {
    await bestEffort("enable-r2-for-cleanup", async () => {
      await setClubFlags(platformOwner, {
        competitionOrganizerEnabled: true,
        foundationEnabled: true,
        publicProfilesEnabled: false,
        selfServiceCreationEnabled: false,
        teamRelationshipsEnabled: true,
      }, "R2 staging cleanup window");
    });

    if (fixtureCompetitionAssignments.length > 0) {
      await bestEffort("enable-r1-for-cleanup", async () => {
        await setCompetitionFlags(platformOwner, {
          contextBindingEnabled: false,
          creationEnabled: true,
          foundationEnabled: true,
        }, "R2 staging Competition staff cleanup window");
      });
      for (const assignment of fixtureCompetitionAssignments) {
        await bestEffort(`revoke-competition-staff-${assignment.staffAssignmentId}`, async () => {
          const snapshot = await rpc(ownerDesktop, "get_pachanga_competition_foundation_snapshot_v1", {
            target_competition_id: assignment.competitionId,
          });
          const activeAssignment = snapshot.staff.find((item) => (
            item.id === assignment.staffAssignmentId && item.status === "active"
          ));
          if (!activeAssignment) return;
          await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
            action: "staff.revoke",
            aggregateId: assignment.competitionId,
            expectedRevision: snapshot.competition.revision,
            payload: {
              reason: "R2 staging Competition staff cleanup",
              staffAssignmentId: activeAssignment.id,
            },
            surface: "club-foundation-staging-cleanup",
          });
        });
      }
    }

    for (const clubId of fixtureClubs) {
      const ownerClient = fixtureOwners.get(clubId) === USERS.playerA.id ? playerA : ownerDesktop;
      if (ownerClient) {
        await bestEffort(`archive-${clubId}`, () => archiveFixtureClub(
          clubId,
          ownerClient,
          fixtureOwners.get(clubId),
        ));
      }
    }

    await bestEffort("disable-r2-flags", async () => {
      await setClubFlags(platformOwner, {
        competitionOrganizerEnabled: false,
        foundationEnabled: false,
        publicProfilesEnabled: false,
        selfServiceCreationEnabled: false,
        teamRelationshipsEnabled: false,
      }, "R2 staging QA complete");
    });
    await bestEffort("disable-r1-flags", async () => {
      await setCompetitionFlags(platformOwner, {
        contextBindingEnabled: false,
        creationEnabled: false,
        foundationEnabled: false,
      }, "R2 staging QA complete");
    });
  }

  for (const [supabase, channel] of channels) {
    await bestEffort("remove-channel", () => supabase.removeChannel(channel));
  }
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", async () => {
      await supabase.realtime.disconnect();
    });
  }
}

assert.equal(completed, true, "R2 staging story did not complete");
process.exit(0);
