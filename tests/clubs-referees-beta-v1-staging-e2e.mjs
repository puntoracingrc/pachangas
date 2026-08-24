import assert from "node:assert/strict";
import { createHmac, randomBytes, randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.CLUBS_REFEREES_BETA_STAGING_URL;
const publishableKey = process.env.CLUBS_REFEREES_BETA_STAGING_PUBLISHABLE_KEY;
const serviceRoleKey = process.env.CLUBS_REFEREES_BETA_STAGING_SERVICE_ROLE_KEY;
const jwtSecret = process.env.CLUBS_REFEREES_BETA_STAGING_JWT_SECRET;

for (const [name, value] of Object.entries({
  CLUBS_REFEREES_BETA_STAGING_JWT_SECRET: jwtSecret,
  CLUBS_REFEREES_BETA_STAGING_PUBLISHABLE_KEY: publishableKey,
  CLUBS_REFEREES_BETA_STAGING_SERVICE_ROLE_KEY: serviceRoleKey,
  CLUBS_REFEREES_BETA_STAGING_URL: url,
})) {
  if (!value) throw new Error(`${name} is required`);
}

const USERS = {
  clubPlatform: {
    id: "f1700000-0000-4000-8000-000000000001",
    email: "r1-platform-owner-20260821@pachangasiq.test",
  },
  teamOwner: {
    id: "f1700000-0000-4000-8000-000000000002",
    email: "r1-owner-a-20260821@pachangasiq.test",
  },
  teamAdmin: {
    id: "f1700000-0000-4000-8000-000000000003",
    email: "r1-admin-a-20260821@pachangasiq.test",
  },
  refereePlatform: {
    id: "a3200000-0000-4000-8000-000000000001",
    email: "r3-platform-owner-20260821@pachangasiq.test",
  },
};

const TEAM_ID = "f1800000-0000-4000-8000-000000000001";
const CLUB_FLAGS_ID = "00000000-0000-0000-0000-00000000c101";
const REFEREE_FLAGS_ID = "00000000-0000-0000-0000-00000000a3f3";
const FIXED_USERS = Object.values(USERS);

const service = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const clients = [];
const channels = [];
const password = process.env.CLUBS_REFEREES_BETA_STAGING_PASSWORD
  || randomBytes(30).toString("base64url");
const visualHold = process.env.CLUBS_REFEREES_BETA_STAGING_VISUAL_HOLD === "1";
const cleanupPassword = randomBytes(30).toString("base64url");
const runTag = `${Date.now().toString(36)}-${randomUUID().slice(0, 8)}`;
const unverifiedEmail = `wave1-unverified-${runTag}@pachangasiq.test`;

let unverifiedUserId;
let clubCreatorAccount;
let refereeAccount;
let clubPlatform;
let clubOwnerDesktop;
let clubOwnerMobile;
let teamOwner;
let teamAdmin;
let refereePlatform;
let refereeDesktop;
let refereeMobile;
let clubId;
let refereeProfileId;
let teamRelationshipId;
let refereeRelationshipId;
let staffMembershipId;
let initialClubFlags;
let initialRefereeFlags;
let completed = false;

function browserClient(accessToken) {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: accessToken ? { headers: { Authorization: `Bearer ${accessToken}` } } : undefined,
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(account) {
  const supabase = browserClient();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw result.error;
  assert.equal(result.data.user?.id, account.id);
  await supabase.realtime.setAuth(result.data.session.access_token);
  clients.push(supabase);
  return supabase;
}

function commandArgs({ action, aggregateId, expectedRevision, operationId = randomUUID(), payload = {}, surface }) {
  return {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+wave1-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+wave1-staging",
      surface,
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  };
}

function clubCommand(supabase, input, platform = false) {
  return supabase.rpc(
    platform ? "command_pachanga_club_platform_v1" : "command_pachanga_club_foundation_v1",
    commandArgs({ ...input, surface: input.surface ?? "clubs-referees-wave1-staging" }),
  );
}

function refereeCommand(supabase, input, platform = false) {
  return supabase.rpc(
    platform ? "command_pachanga_referee_platform_admin_v1" : "command_pachanga_referee_platform_v1",
    commandArgs({ ...input, surface: input.surface ?? "clubs-referees-wave1-staging" }),
  );
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

async function commandOk(executor, label) {
  const result = await executor;
  if (result.error) {
    throw new Error(`${label} failed [${result.error.code ?? "UNKNOWN"}] ${result.error.message}`);
  }
  return result.data;
}

function expectRpcError(result, pattern, code) {
  assert.ok(result.error, `Expected RPC error matching ${pattern}`);
  if (code) assert.equal(result.error.code, code);
  assert.match(
    [result.error.message, result.error.details, result.error.hint].filter(Boolean).join(" "),
    pattern,
  );
}

function base64url(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function unverifiedJwt(userId, email) {
  const now = Math.floor(Date.now() / 1_000);
  const header = base64url({ alg: "HS256", typ: "JWT" });
  const payload = base64url({
    app_metadata: { provider: "email", providers: ["email"] },
    aud: "authenticated",
    email,
    exp: now + 900,
    iat: now,
    iss: `${url}/auth/v1`,
    role: "authenticated",
    sub: userId,
    user_metadata: {},
  });
  const signature = createHmac("sha256", jwtSecret).update(`${header}.${payload}`).digest("base64url");
  return `${header}.${payload}.${signature}`;
}

async function clubFlags(supabase) {
  return rpc(supabase, "get_pachanga_club_foundation_flags_v1");
}

async function refereeFlags(supabase) {
  return rpc(supabase, "get_pachanga_referee_foundation_flags_v1");
}

async function setClubFlags(next, reason) {
  const current = await clubFlags(clubPlatform);
  return commandOk(clubCommand(clubPlatform, {
    action: "club_flags.set",
    aggregateId: CLUB_FLAGS_ID,
    expectedRevision: current.revision,
    payload: { ...next, reason },
  }, true), "club flags");
}

async function setRefereeFlags(next, reason) {
  const current = await refereeFlags(refereePlatform);
  return commandOk(refereeCommand(refereePlatform, {
    action: "referee_flags.set",
    aggregateId: REFEREE_FLAGS_ID,
    expectedRevision: current.revision,
    payload: { ...next, reason },
  }, true), "referee flags");
}

function clubFrom(receipt) {
  const club = receipt?.snapshot?.club;
  assert.ok(club?.id, "Club receipt must contain the canonical Club snapshot");
  return club;
}

function profileFrom(receipt) {
  const profile = receipt?.snapshot?.profile;
  assert.ok(profile?.id, "Referee receipt must contain the canonical profile snapshot");
  return profile;
}

async function clubSnapshot(supabase = clubOwnerDesktop) {
  return rpc(supabase, "get_pachanga_club_foundation_snapshot_v1", { target_club_id: clubId });
}

async function refereeSnapshot(supabase = refereeDesktop) {
  const snapshot = await rpc(supabase, "get_my_pachanga_referee_platform_v1");
  return snapshot?.profile ?? null;
}

async function confirmPublication(supabase, subjectKind, subjectId, expectedRevision) {
  return rpc(supabase, "command_pachanga_publication_consent_v1", {
    client_metadata: {
      clientVersion: "1.0.0+wave1-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+wave1-staging",
      surface: "clubs-referees-wave1-staging",
    },
    confirmations: subjectKind === "CLUB"
      ? { informationCorrect: true, representationAuthorized: true }
      : {
          informationCorrect: true,
          publicZonesAvailability: true,
          unverifiedNotCertification: true,
        },
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
    subject_id: subjectId,
    subject_kind: subjectKind,
  });
}

function invalidationQueue(label) {
  const queued = [];
  let waiter;
  return {
    clear() { queued.length = 0; },
    next() {
      if (queued.length) return Promise.resolve(queued.shift());
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          waiter = undefined;
          reject(new Error(`${label} Realtime invalidation timed out`));
        }, 45_000);
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

async function seedAuth() {
  for (const account of FIXED_USERS) {
    const result = await service.auth.admin.updateUserById(account.id, { password });
    if (result.error) throw result.error;
  }
  const unverified = await service.auth.admin.createUser({
    email: unverifiedEmail,
    email_confirm: false,
    password,
  });
  if (unverified.error) throw unverified.error;
  unverifiedUserId = unverified.data.user.id;

  const clubCreatorEmail = `wave1-club-owner-${runTag}@pachangasiq.test`;
  const clubCreator = await service.auth.admin.createUser({
    email: clubCreatorEmail,
    email_confirm: true,
    password,
    user_metadata: { name: "Wave 1 Club Owner" },
  });
  if (clubCreator.error) throw clubCreator.error;
  clubCreatorAccount = { id: clubCreator.data.user.id, email: clubCreatorEmail };

  const refereeEmail = `wave1-referee-${runTag}@pachangasiq.test`;
  const referee = await service.auth.admin.createUser({
    email: refereeEmail,
    email_confirm: true,
    password,
    user_metadata: { name: "Wave 1 Referee" },
  });
  if (referee.error) throw referee.error;
  refereeAccount = { id: referee.data.user.id, email: refereeEmail };
}

async function restoreAuth() {
  for (const account of FIXED_USERS) {
    await bestEffort(`rotate-${account.id}`, async () => {
      const result = await service.auth.admin.updateUserById(account.id, { password: cleanupPassword });
      if (result.error) throw result.error;
    });
  }
  if (unverifiedUserId) {
    await bestEffort("delete-unverified", async () => {
      const result = await service.auth.admin.deleteUser(unverifiedUserId);
      if (result.error) throw result.error;
    });
  }
  for (const account of [clubCreatorAccount, refereeAccount].filter(Boolean)) {
    await bestEffort(`disable-${account.id}`, async () => {
      const result = await service.auth.admin.updateUserById(account.id, {
        ban_duration: "876000h",
        password: cleanupPassword,
        user_metadata: { name: "Archived Wave 1 QA fixture", qa_fixture_archived: true },
      });
      if (result.error) throw result.error;
    });
  }
}

async function archiveStaleWave1Fixtures() {
  const profilesResult = await service
    .from("pachanga_referee_profiles")
    .select("id,user_id,revision,operational_status")
    .like("slug", "wave1-referee-%")
    .neq("operational_status", "archived");
  if (profilesResult.error) throw profilesResult.error;

  for (const profile of profilesResult.data) {
    const fixturePassword = randomBytes(30).toString("base64url");
    const userResult = await service.auth.admin.getUserById(profile.user_id);
    if (userResult.error || !userResult.data.user.email) throw userResult.error ?? new Error("QA user missing");
    const enableResult = await service.auth.admin.updateUserById(profile.user_id, {
      ban_duration: "none",
      password: fixturePassword,
    });
    if (enableResult.error) throw enableResult.error;
    const fixtureClient = browserClient();
    const signInResult = await fixtureClient.auth.signInWithPassword({
      email: userResult.data.user.email,
      password: fixturePassword,
    });
    if (signInResult.error) throw signInResult.error;
    let revision = profile.revision;
    if (profile.operational_status === "suspended") {
      const restored = await commandOk(refereeCommand(refereePlatform, {
        action: "profile.restore",
        aggregateId: profile.id,
        expectedRevision: revision,
        payload: { reason: "Wave 1 stale fixture restore" },
      }, true), "restore stale referee fixture");
      revision = restored.confirmedRevision;
    }
    await commandOk(refereeCommand(fixtureClient, {
      action: "profile.archive",
      aggregateId: profile.id,
      expectedRevision: revision,
      payload: { reason: "Wave 1 stale fixture cleanup" },
    }), "archive stale referee fixture");
    await fixtureClient.auth.signOut();
    const disableResult = await service.auth.admin.updateUserById(profile.user_id, {
      ban_duration: "876000h",
      password: cleanupPassword,
      user_metadata: { name: "Archived Wave 1 QA fixture", qa_fixture_archived: true },
    });
    if (disableResult.error) throw disableResult.error;
  }
}

try {
  await seedAuth();
  [
    clubPlatform,
    clubOwnerDesktop,
    clubOwnerMobile,
    teamOwner,
    teamAdmin,
    refereePlatform,
    refereeDesktop,
    refereeMobile,
  ] = await Promise.all([
    signIn(USERS.clubPlatform),
    signIn(clubCreatorAccount),
    signIn(clubCreatorAccount),
    signIn(USERS.teamOwner),
    signIn(USERS.teamAdmin),
    signIn(USERS.refereePlatform),
    signIn(refereeAccount),
    signIn(refereeAccount),
  ]);

  initialClubFlags = await clubFlags(clubPlatform);
  initialRefereeFlags = await refereeFlags(refereePlatform);
  await setClubFlags({
    competitionOrganizerEnabled: false,
    foundationEnabled: true,
    publicProfilesEnabled: true,
    selfServiceCreationEnabled: true,
    teamRelationshipsEnabled: true,
  }, "Wave 1 staging Club window");
  await setRefereeFlags({
    assignmentsEnabled: false,
    clubRelationshipsEnabled: true,
    foundationEnabled: true,
    marketplaceEnabled: true,
    publicProfilesEnabled: true,
    selfServiceEnabled: true,
  }, "Wave 1 staging referee window");

  await archiveStaleWave1Fixtures();

  assert.equal((await clubFlags(clubPlatform)).competitionOrganizerEnabled, false);
  assert.equal((await refereeFlags(refereePlatform)).assignmentsEnabled, false);

  const anonymous = browserClient();
  const anonymousCreate = await clubCommand(anonymous, {
    action: "club.create",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: { clubType: "FOOTBALL_CLUB", name: "Anonymous Club", slug: `anon-${runTag}` },
  });
  expectRpcError(
    anonymousCreate,
    /Authentication required|permission denied for function command_pachanga_club_foundation_v1/,
    "42501",
  );

  const unverified = browserClient(unverifiedJwt(unverifiedUserId, unverifiedEmail));
  const unverifiedCreate = await clubCommand(unverified, {
    action: "club.create",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: { clubType: "FOOTBALL_CLUB", name: "Unverified Club", slug: `unverified-${runTag}` },
  });
  expectRpcError(unverifiedCreate, /VERIFIED_EMAIL_REQUIRED/, "42501");

  const createdClubId = randomUUID();
  const clubCreateOperation = randomUUID();
  const clubCreateInput = {
    action: "club.create",
    aggregateId: createdClubId,
    expectedRevision: 0,
    operationId: clubCreateOperation,
    payload: {
      clubType: "FOOTBALL_CLUB",
      countryCode: "ES",
      description: "Club privado de QA para Wave 1.",
      generalArea: "Eixample",
      municipality: "Barcelona",
      name: `Wave 1 Club ${runTag}`,
      province: "Barcelona",
      reason: "Wave 1 staging create",
      slug: `wave1-club-${runTag}`,
      visibility: "public",
    },
  };
  const createdClub = await commandOk(clubCommand(clubOwnerDesktop, clubCreateInput), "create Club");
  clubId = createdClubId;
  const clubReplay = await commandOk(clubCommand(clubOwnerMobile, clubCreateInput), "replay Club create");
  assert.equal(clubReplay.serverSequence, createdClub.serverSequence);
  assert.equal(clubFrom(createdClub).operationalStatus, "draft");
  assert.equal(await rpc(anonymous, "get_pachanga_public_club_v1", {
    target_slug: clubFrom(createdClub).slug,
  }), null);

  const clubQueue = invalidationQueue("Club");
  const clubChannel = clubOwnerMobile
    .channel(`wave1-club-${runTag}`)
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_club_invalidations",
    }, (payload) => {
      if (payload.new.club_id === clubId) clubQueue.push(payload);
    });
  channels.push([clubOwnerMobile, clubChannel]);
  await waitForSubscription(clubChannel);
  clubQueue.clear();
  const clubInvalidation = clubQueue.next();
  const updatedClub = await commandOk(clubCommand(clubOwnerDesktop, {
    action: "club.profile.update",
    aggregateId: clubId,
    expectedRevision: clubFrom(createdClub).revision,
    payload: { description: "Perfil canonico actualizado desde desktop.", reason: "Wave 1 Realtime" },
  }), "update Club");
  const clubInvalidationPayload = await clubInvalidation;
  assert.equal(clubInvalidationPayload.new.club_id, clubId);
  assert.equal((await clubSnapshot(clubOwnerMobile)).club.revision, updatedClub.confirmedRevision);

  const staleClub = await clubCommand(clubOwnerMobile, {
    action: "club.profile.update",
    aggregateId: clubId,
    expectedRevision: clubFrom(createdClub).revision,
    payload: { description: "Stale mobile state", reason: "Wave 1 stale revision" },
  });
  expectRpcError(staleClub, /STALE_REVISION/, "PT409");

  const clubConsent = await confirmPublication(
    clubOwnerDesktop,
    "CLUB",
    clubId,
    updatedClub.confirmedRevision,
  );
  const review = await commandOk(clubCommand(clubOwnerDesktop, {
    action: "club.review.submit",
    aggregateId: clubId,
    expectedRevision: clubConsent.confirmedRevision,
    payload: { reason: "Wave 1 review" },
  }), "submit Club review");
  let platformClub = await commandOk(clubCommand(clubPlatform, {
    action: "club.status.set",
    aggregateId: clubId,
    expectedRevision: review.confirmedRevision,
    payload: { reason: "Wave 1 approve Club", status: "active" },
  }, true), "approve Club");
  platformClub = await commandOk(clubCommand(clubPlatform, {
    action: "club.verification.set",
    aggregateId: clubId,
    expectedRevision: platformClub.confirmedRevision,
    payload: { reason: "Wave 1 verify Club", status: "verified" },
  }, true), "verify Club");

  const publicClub = await rpc(anonymous, "get_pachanga_public_club_v1", {
    target_slug: platformClub.snapshot.club.slug,
  });
  assert.equal(publicClub.slug, platformClub.snapshot.club.slug);
  assert.equal(publicClub.verified, true);
  const publicClubText = JSON.stringify(publicClub);
  for (const privateField of ["primaryOwnerId", "memberships", "placeId", "@pachangasiq.test"]) {
    assert.equal(publicClubText.includes(privateField), false, `Club public model leaked ${privateField}`);
  }
  const directory = await rpc(anonymous, "search_pachanga_public_clubs_v1", {
    target_filters: { query: platformClub.snapshot.club.name },
    target_page: 1,
    target_page_size: 12,
  });
  assert.ok(directory.items.some((item) => item.slug === platformClub.snapshot.club.slug));

  let ownerSnapshot = await clubSnapshot();
  const staffInviteOperation = randomUUID();
  const staffInvite = await commandOk(clubCommand(clubOwnerDesktop, {
    action: "membership.invite",
    aggregateId: clubId,
    expectedRevision: ownerSnapshot.club.revision,
    operationId: staffInviteOperation,
    payload: {
      reason: "Wave 1 Club staff invite",
      role: "club_admin",
      targetKind: "registered_user",
      targetUserId: USERS.teamAdmin.id,
    },
  }), "invite Club staff");
  const staffAccepted = await commandOk(clubCommand(teamAdmin, {
    action: "membership.accept",
    aggregateId: staffInvite.invitationId,
    expectedRevision: 1,
    payload: { reason: "Wave 1 Club staff accept", token: staffInvite.oneTimeToken },
  }), "accept Club staff");
  const staffMembership = staffAccepted.snapshot.memberships.find((item) => (
    item.userId === USERS.teamAdmin.id && item.status === "active"
  ));
  assert.equal(staffMembership.role, "club_admin");
  staffMembershipId = staffMembership.id;
  assert.equal(await notificationCount(
    teamAdmin,
    `club-staff-invitation:${staffInviteOperation}:${USERS.teamAdmin.id}`,
  ), 1);

  ownerSnapshot = await clubSnapshot();
  const teamInvite = await commandOk(clubCommand(clubOwnerDesktop, {
    action: "team_relationship.invite",
    aggregateId: clubId,
    expectedRevision: ownerSnapshot.club.revision,
    payload: { groupId: TEAM_ID, reason: "Wave 1 Team invite", relationshipType: "AFFILIATED" },
  }), "invite Team");
  const invitedTeam = teamInvite.snapshot.teamRelationships.find((item) => (
    item.groupId === TEAM_ID && item.status === "invited"
  ));
  assert.ok(invitedTeam?.id);
  teamRelationshipId = invitedTeam.id;
  const adminAccept = await clubCommand(teamAdmin, {
    action: "team_relationship.accept",
    aggregateId: invitedTeam.id,
    expectedRevision: invitedTeam.revision,
    payload: { reason: "Team admin must not accept" },
  });
  expectRpcError(adminAccept, /TEAM_OWNER_REQUIRED/, "42501");
  const teamAccepted = await commandOk(clubCommand(teamOwner, {
    action: "team_relationship.accept",
    aggregateId: invitedTeam.id,
    expectedRevision: invitedTeam.revision,
    payload: { reason: "Team owner accepts" },
  }), "Team owner accept");
  assert.equal(
    teamAccepted.snapshot.teamRelationships.find((item) => item.id === invitedTeam.id).status,
    "active",
  );

  const createdRefereeProfileId = randomUUID();
  let refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.create",
    aggregateId: createdRefereeProfileId,
    expectedRevision: 0,
    payload: {
      availabilityStatus: "AVAILABLE",
      bio: "Perfil arbitral privado para QA Wave 1.",
      experienceSinceYear: 2020,
      experienceSummary: "Experiencia declarada en futbol amateur.",
      reason: "Wave 1 referee create",
      slug: `wave1-referee-${runTag}`,
    },
  }), "create referee");
  refereeProfileId = createdRefereeProfileId;
  const duplicateProfile = await refereeCommand(refereeDesktop, {
    action: "profile.create",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: { reason: "Duplicate referee", slug: `wave1-referee-duplicate-${runTag}` },
  });
  expectRpcError(duplicateProfile, /REFEREE_PROFILE_ALREADY_EXISTS/, "PT409");
  let privateMarket = await rpc(teamAdmin, "search_pachanga_referee_market_v1", {
    target_filters: { zone: "Barcelona" },
    target_page: 1,
    target_page_size: 12,
  });
  assert.equal(privateMarket.items.some((item) => item.refereeProfileId === refereeProfileId), false);

  const refereeQueue = invalidationQueue("Referee");
  const refereeChannel = refereeMobile
    .channel(`wave1-referee-${runTag}`)
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_referee_invalidations",
    }, (payload) => {
      if (payload.new.target_user_id === refereeAccount.id) refereeQueue.push(payload);
    });
  channels.push([refereeMobile, refereeChannel]);
  await waitForSubscription(refereeChannel);
  refereeQueue.clear();
  const refereeInvalidation = refereeQueue.next();
  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.update",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: { bio: "Perfil canonico actualizado desde desktop.", reason: "Wave 1 Realtime" },
  }), "update referee");
  const refereeInvalidationPayload = await refereeInvalidation;
  assert.equal(refereeInvalidationPayload.new.referee_profile_id, refereeProfileId);
  assert.equal((await refereeSnapshot(refereeMobile)).profile.revision, refereeReceipt.confirmedRevision);

  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.modalities.replace",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: {
      modalities: [{ experienceSinceYear: 2020, modality: "FOOTBALL_7" }],
      reason: "Wave 1 referee modalities",
    },
  }), "referee modalities");
  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.areas.replace",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: {
      areas: [{
        countryCode: "ES",
        generalArea: "Barcelona",
        municipality: "Barcelona",
        province: "Barcelona",
        travelRadiusKm: 30,
      }],
      reason: "Wave 1 referee zones",
    },
  }), "referee areas");
  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.availability.replace",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: {
      exceptions: [{
        reason: "Private staging exception",
        unavailableFrom: "2026-10-01T08:00:00Z",
        unavailableUntil: "2026-10-01T12:00:00Z",
      }],
      reason: "Wave 1 referee availability",
      windows: [{
        endLocalTime: "21:00",
        publicVisible: true,
        startLocalTime: "17:00",
        timezone: "Europe/Madrid",
        weekday: 6,
      }],
    },
  }), "referee availability");
  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.update",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: {
      availabilityStatus: "AVAILABLE",
      availableForAssignments: true,
      reason: "Wave 1 public referee settings",
      shareRecurringAvailability: true,
      visibility: "public",
    },
  }), "referee public settings");
  const refereeConsent = await confirmPublication(
    refereeDesktop,
    "REFEREE_PROFILE",
    refereeProfileId,
    refereeReceipt.confirmedRevision,
  );
  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "profile.activate",
    aggregateId: refereeProfileId,
    expectedRevision: refereeConsent.confirmedRevision,
    payload: { reason: "Wave 1 activate referee" },
  }), "activate referee");

  const publicRefereeBeforeApproval = await rpc(anonymous, "get_pachanga_public_referee_v1", {
    target_slug: profileFrom(refereeReceipt).slug,
  });
  assert.equal(publicRefereeBeforeApproval.verificationStatus, "unverified");
  const userVerify = await refereeCommand(refereeDesktop, {
    action: "verification.approve",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: { reason: "User cannot verify self" },
  }, true);
  expectRpcError(
    userVerify,
    /PLATFORM_CAPABILITY_REQUIRED|Platform access required|Authentication required/,
    "42501",
  );

  refereeReceipt = await commandOk(refereeCommand(refereeDesktop, {
    action: "marketplace.list",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: { reason: "Wave 1 list referee" },
  }), "list referee");
  let market = await rpc(teamAdmin, "search_pachanga_referee_market_v1", {
    target_filters: { modality: "FOOTBALL_7", zone: "Barcelona" },
    target_page: 1,
    target_page_size: 12,
  });
  assert.ok(market.items.some((item) => item.refereeProfileId === refereeProfileId));
  const publicRefereeText = JSON.stringify(publicRefereeBeforeApproval);
  for (const privateField of ["@pachangasiq.test", "Private staging exception", "rating", "stars", "grl"]) {
    assert.equal(publicRefereeText.toLowerCase().includes(privateField.toLowerCase()), false);
  }

  let verifiedReferee = await commandOk(refereeCommand(refereePlatform, {
    action: "verification.pending",
    aggregateId: refereeProfileId,
    expectedRevision: refereeReceipt.confirmedRevision,
    payload: { reason: "Wave 1 verification review" },
  }, true), "verification pending");
  verifiedReferee = await commandOk(refereeCommand(refereePlatform, {
    action: "verification.approve",
    aggregateId: refereeProfileId,
    expectedRevision: verifiedReferee.confirmedRevision,
    payload: { reason: "Wave 1 verification approve" },
  }, true), "verification approve");
  assert.equal((await rpc(anonymous, "get_pachanga_public_referee_v1", {
    target_slug: profileFrom(verifiedReferee).slug,
  })).verificationStatus, "verified");

  refereeRelationshipId = randomUUID();
  const refereeInviteOperation = randomUUID();
  const refereeInvite = await commandOk(refereeCommand(clubOwnerDesktop, {
    action: "relationship.invite",
    aggregateId: refereeRelationshipId,
    expectedRevision: 0,
    operationId: refereeInviteOperation,
    payload: {
      clubId,
      reason: "Wave 1 Club referee invite",
      relationshipType: "REGULAR",
      targetKind: "registered_user",
      targetUserId: refereeAccount.id,
    },
  }), "invite referee");
  const refereeInviteReplay = await commandOk(refereeCommand(clubOwnerMobile, {
    action: "relationship.invite",
    aggregateId: refereeRelationshipId,
    expectedRevision: 0,
    operationId: refereeInviteOperation,
    payload: {
      clubId,
      reason: "Wave 1 Club referee invite",
      relationshipType: "REGULAR",
      targetKind: "registered_user",
      targetUserId: refereeAccount.id,
    },
  }), "replay referee invite");
  assert.equal(refereeInviteReplay.serverSequence, refereeInvite.serverSequence);
  assert.equal("oneTimeToken" in refereeInviteReplay, false);
  assert.equal(await notificationCount(
    refereeDesktop,
    `referee-club-invite:${refereeInviteOperation}:${refereeAccount.id}`,
  ), 1);
  const acceptedReferee = await commandOk(refereeCommand(refereeMobile, {
    action: "relationship.accept",
    aggregateId: refereeRelationshipId,
    expectedRevision: 1,
    payload: { reason: "Wave 1 referee accepts" },
  }), "accept referee relationship");
  assert.equal(acceptedReferee.snapshot.relationship.status, "active");

  if (visualHold) {
    console.log(JSON.stringify({
      clubOwnerEmail: clubCreatorAccount.email,
      clubSlug: platformClub.snapshot.club.slug,
      refereeEmail: refereeAccount.email,
      refereeSlug: profileFrom(verifiedReferee).slug,
      visualHold: "READY",
    }));
    await new Promise((resolve) => {
      process.stdin.resume();
      process.stdin.once("data", resolve);
    });
  }

  let latestClub = await clubSnapshot(clubPlatform);
  const suspendedClub = await commandOk(clubCommand(clubPlatform, {
    action: "club.status.set",
    aggregateId: clubId,
    expectedRevision: latestClub.club.revision,
    payload: { reason: "Wave 1 suspended Club negative", status: "suspended" },
  }, true), "suspend Club");
  const suspendedClubInvite = await refereeCommand(clubOwnerDesktop, {
    action: "relationship.invite",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: {
      clubId,
      reason: "Suspended Club cannot invite",
      relationshipType: "REGULAR",
      targetKind: "registered_user",
      targetUserId: refereeAccount.id,
    },
  });
  expectRpcError(suspendedClubInvite, /REFEREE_RELATIONSHIP_CLUB_NOT_ACTIVE/, "42501");
  await commandOk(clubCommand(clubPlatform, {
    action: "club.status.set",
    aggregateId: clubId,
    expectedRevision: suspendedClub.confirmedRevision,
    payload: { reason: "Wave 1 restore Club", status: "active" },
  }, true), "restore Club");

  let latestReferee = await rpc(refereePlatform, "get_pachanga_platform_referee_v1", {
    target_profile_id: refereeProfileId,
  });
  const suspendedReferee = await commandOk(refereeCommand(refereePlatform, {
    action: "profile.suspend",
    aggregateId: refereeProfileId,
    expectedRevision: latestReferee.profile.revision,
    payload: { reason: "Wave 1 suspended referee negative" },
  }, true), "suspend referee");
  market = await rpc(teamAdmin, "search_pachanga_referee_market_v1", {
    target_filters: { zone: "Barcelona" },
    target_page: 1,
    target_page_size: 12,
  });
  assert.equal(market.items.some((item) => item.refereeProfileId === refereeProfileId), false);
  const suspendedList = await refereeCommand(refereeDesktop, {
    action: "marketplace.list",
    aggregateId: refereeProfileId,
    expectedRevision: suspendedReferee.confirmedRevision,
    payload: { reason: "Suspended referee cannot list" },
  });
  expectRpcError(suspendedList, /REFEREE_PROFILE_NOT_MUTABLE|MARKETPLACE_PROFILE_NOT_ELIGIBLE/, "42501");
  const restoredReferee = await commandOk(refereeCommand(refereePlatform, {
    action: "profile.restore",
    aggregateId: refereeProfileId,
    expectedRevision: suspendedReferee.confirmedRevision,
    payload: { reason: "Wave 1 restore referee" },
  }, true), "restore referee");
  assert.equal(profileFrom(restoredReferee).visibility, "private");
  assert.equal(profileFrom(restoredReferee).marketplaceStatus, "not_listed");
  assert.equal(profileFrom(restoredReferee).availableForAssignments, false);

  const assignmentOff = await refereeCommand(clubOwnerDesktop, {
    action: "assignment.propose",
    aggregateId: randomUUID(),
    expectedRevision: 0,
    payload: {
      refereeProfileId,
      requesterId: TEAM_ID,
      requesterKind: "TEAM",
      sourceGroupId: TEAM_ID,
      sourceId: "wave1-no-canonical-match",
      sourceKind: "group_match",
    },
  });
  expectRpcError(assignmentOff, /REFEREE_ASSIGNMENTS_DISABLED/, "0A000");

  const organizerOff = await clubOwnerDesktop.rpc("command_pachanga_competition_foundation_v2", {
    aggregate_id: randomUUID(),
    client_metadata: {
      clientVersion: "1.0.0+wave1-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "1.0.0+wave1-staging",
      surface: "clubs-referees-wave1-staging",
    },
    command_action: "competition.create",
    command_payload: {
      competitionType: "LEAGUE",
      name: "Forbidden Wave 1 League",
      organizerId: clubId,
      reason: "Club organizer remains off",
      slug: `forbidden-wave1-${runTag}`,
    },
    expected_revision: 0,
    operation_id: randomUUID(),
    organizer_kind: "CLUB",
  });
  expectRpcError(
    organizerOff,
    /COMPETITION_FOUNDATION_DISABLED|COMPETITION_CREATION_DISABLED|CLUB_COMPETITION_ORGANIZER_DISABLED/,
  );
  assert.ok(["0A000", "42501"].includes(organizerOff.error.code));

  completed = true;
  console.log(JSON.stringify({
    club: "create_review_approve_publish_staff_team",
    idempotency: "club_create_and_referee_invite",
    negatives: "auth_email_roles_privacy_suspend_assignments_organizer",
    privacy: "public_models_minimized",
    realtime: "invalidate_then_canonical_refetch",
    referee: "create_publish_market_club_relation_verify",
    status: "PASS",
    twoDevices: "club_owner_and_referee",
  }));
} finally {
  if (refereePlatform && refereeProfileId) {
    if (refereeRelationshipId) {
      await bestEffort("end-referee-relationship", async () => {
        const snapshot = await refereeSnapshot(refereeDesktop);
        const relationship = snapshot.relationships.find((item) => (
          item.id === refereeRelationshipId && item.status === "active"
        ));
        if (!relationship) return;
        await commandOk(refereeCommand(refereeDesktop, {
          action: "relationship.end",
          aggregateId: relationship.id,
          expectedRevision: relationship.revision,
          payload: { reason: "Wave 1 staging cleanup" },
        }), "end referee relationship");
      });
    }
    await bestEffort("archive-referee", async () => {
      let snapshot = await refereeSnapshot(refereeDesktop);
      if (snapshot.profile.operationalStatus === "suspended") {
        await commandOk(refereeCommand(refereePlatform, {
          action: "profile.restore",
          aggregateId: refereeProfileId,
          expectedRevision: snapshot.profile.revision,
          payload: { reason: "Wave 1 cleanup restore" },
        }, true), "cleanup restore referee");
        snapshot = await refereeSnapshot(refereeDesktop);
      }
      if (snapshot.profile.operationalStatus !== "archived") {
        await commandOk(refereeCommand(refereeDesktop, {
          action: "profile.archive",
          aggregateId: refereeProfileId,
          expectedRevision: snapshot.profile.revision,
          payload: { reason: "Wave 1 staging cleanup" },
        }), "archive referee");
      }
    });
  }

  if (clubPlatform && clubId) {
    await bestEffort("end-team-relationship", async () => {
      const snapshot = await clubSnapshot();
      const relationship = snapshot.teamRelationships.find((item) => (
        item.id === teamRelationshipId && item.status === "active"
      ));
      if (!relationship) return;
      await commandOk(clubCommand(clubOwnerDesktop, {
        action: "team_relationship.end",
        aggregateId: relationship.id,
        expectedRevision: relationship.revision,
        payload: { reason: "Wave 1 staging cleanup" },
      }), "end Team relationship");
    });
    await bestEffort("revoke-staff", async () => {
      const snapshot = await clubSnapshot();
      const membership = snapshot.memberships.find((item) => (
        item.id === staffMembershipId && item.status === "active"
      ));
      if (!membership) return;
      await commandOk(clubCommand(clubOwnerDesktop, {
        action: "membership.revoke",
        aggregateId: membership.id,
        expectedRevision: membership.revision,
        payload: { reason: "Wave 1 staging cleanup" },
      }), "revoke Club staff");
    });
    await bestEffort("archive-club", async () => {
      const snapshot = await clubSnapshot(clubPlatform);
      if (snapshot.club.operationalStatus === "archived") return;
      await commandOk(clubCommand(clubPlatform, {
        action: "club.status.set",
        aggregateId: clubId,
        expectedRevision: snapshot.club.revision,
        payload: { reason: "Wave 1 staging cleanup", status: "archived" },
      }, true), "archive Club");
    });
  }

  if (clubPlatform && initialClubFlags) {
    await bestEffort("restore-club-flags", () => setClubFlags({
      competitionOrganizerEnabled: initialClubFlags.competitionOrganizerEnabled,
      foundationEnabled: initialClubFlags.foundationEnabled,
      publicProfilesEnabled: initialClubFlags.publicProfilesEnabled,
      selfServiceCreationEnabled: initialClubFlags.selfServiceCreationEnabled,
      teamRelationshipsEnabled: initialClubFlags.teamRelationshipsEnabled,
    }, "Wave 1 staging restore"));
  }
  if (refereePlatform && initialRefereeFlags) {
    await bestEffort("restore-referee-flags", () => setRefereeFlags({
      assignmentsEnabled: initialRefereeFlags.assignmentsEnabled,
      clubRelationshipsEnabled: initialRefereeFlags.clubRelationshipsEnabled,
      foundationEnabled: initialRefereeFlags.foundationEnabled,
      marketplaceEnabled: initialRefereeFlags.marketplaceEnabled,
      publicProfilesEnabled: initialRefereeFlags.publicProfilesEnabled,
      selfServiceEnabled: initialRefereeFlags.selfServiceEnabled,
    }, "Wave 1 staging restore"));
  }

  for (const [supabase, channel] of channels) {
    await bestEffort("remove-channel", () => supabase.removeChannel(channel));
  }
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", () => supabase.realtime.disconnect());
  }
  await restoreAuth();
}

assert.equal(completed, true, "Wave 1 staging story did not complete");

// Realtime can retain an idle transport handle in Node after every channel is closed.
await new Promise((resolve) => setImmediate(resolve));
process.exit(0);
