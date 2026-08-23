import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.LEAGUE_PARTICIPATION_STAGING_URL;
const publishableKey = process.env.LEAGUE_PARTICIPATION_STAGING_PUBLISHABLE_KEY;
const serviceRoleKey = process.env.LEAGUE_PARTICIPATION_STAGING_SERVICE_ROLE_KEY;
const password = process.env.LEAGUE_PARTICIPATION_STAGING_PASSWORD;
const expectedProjectRef = process.env.LEAGUE_PARTICIPATION_STAGING_PROJECT_REF;
const confirmation = process.env.LEAGUE_PARTICIPATION_STAGING_CONFIRM;

for (const [name, value] of Object.entries({
  LEAGUE_PARTICIPATION_STAGING_CONFIRM: confirmation,
  LEAGUE_PARTICIPATION_STAGING_PASSWORD: password,
  LEAGUE_PARTICIPATION_STAGING_PROJECT_REF: expectedProjectRef,
  LEAGUE_PARTICIPATION_STAGING_PUBLISHABLE_KEY: publishableKey,
  LEAGUE_PARTICIPATION_STAGING_SERVICE_ROLE_KEY: serviceRoleKey,
  LEAGUE_PARTICIPATION_STAGING_URL: url,
})) {
  if (!value) throw new Error(`${name} is required`);
}

const parsedUrl = new URL(url);
const actualProjectRef = parsedUrl.hostname.split(".")[0];
const productionProjectRef = "qonbngfrnrqgmxbdfbea";
if (
  confirmation !== "R4A_STAGING_ONLY"
  || expectedProjectRef === productionProjectRef
  || actualProjectRef === productionProjectRef
  || actualProjectRef !== expectedProjectRef
) {
  throw new Error("R4A_STAGING_PRODUCTION_TARGET_FORBIDDEN");
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
  ownerC: {
    id: "f1700000-0000-4000-8000-000000000007",
    email: "r1-normal-20260821@pachangasiq.test",
  },
};

const GROUP_A = "f1800000-0000-4000-8000-000000000001";
const GROUP_B = "f1800000-0000-4000-8000-000000000002";
const GROUP_C = "f1800000-0000-4000-8000-000000000003";
const CLUB_FLAGS_ID = "00000000-0000-0000-0000-00000000c101";
const COMPETITION_FLAGS_ID = "00000000-0000-0000-0000-00000000c001";
const LEAGUE_FLAGS_ID = "00000000-0000-0000-0000-00000000c4a1";
const REFEREE_FLAGS_ID = "00000000-0000-0000-0000-00000000a3f3";
const UNTOUCHED_DOMAIN_TABLES = [
  "pachanga_canonical_matches",
  "pachanga_competition_match_contexts",
  "pachanga_conduct_subject_state",
  "pachanga_external_match_participants",
  "pachanga_external_match_scorers",
  "pachanga_external_matches",
  "pachanga_individual_rating_evidence",
  "pachanga_match_rating_participants",
  "pachanga_player_rating_snapshots",
  "pachanga_provincial_ranking_entries",
  "pachanga_reward_grants",
  "pachanga_team_cosmetic_inventory",
];

const clients = [];
const channels = [];
const created = {
  acceptedEntries: [],
  clubId: null,
  competitionId: null,
  credentialIds: [],
  delegateIds: [],
  entitlementId: null,
  entryIds: [],
  rosterIds: [],
  stageMembershipIds: [],
};

function client(key = publishableKey) {
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

const fixtureAdmin = client(serviceRoleKey);

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function signIn(account) {
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    const supabase = client();
    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email: account.email,
        password,
      });
      if (error) throw error;
      assert.equal(data.user?.id, account.id);
      clients.push(supabase);
      return supabase;
    } catch (error) {
      const transient = error?.status === 0 || /fetch failed|network/i.test(error?.message ?? "");
      if (!transient || attempt === 4) throw error;
      await sleep(attempt * 500);
    }
  }
  throw new Error(`Unable to authenticate staging fixture ${account.id}`);
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

function clientMetadata(surface = "league-participation-staging") {
  return {
    clientVersion: "1.0.0+r4a-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "1.0.0+r4a-staging",
    surface,
  };
}

function foundationCommand(supabase, name, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  organizerKind,
  payload = {},
  surface = "league-participation-staging-foundation",
}) {
  const args = {
    aggregate_id: aggregateId,
    client_metadata: clientMetadata(surface),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  };
  if (organizerKind) args.organizer_kind = organizerKind;
  return supabase.rpc(name, args);
}

async function foundationCommandOk(supabase, name, input) {
  const result = await foundationCommand(supabase, name, input);
  if (result.error) {
    throw new Error(
      `${name}:${input.action}:${input.aggregateId}@${input.expectedRevision} failed `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function leagueCommand(supabase, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
  surface = "league-participation-staging",
}) {
  return supabase.rpc("command_pachanga_league_participation_v1", {
    aggregate_id: aggregateId,
    client_metadata: clientMetadata(surface),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function leagueCommandOk(supabase, input) {
  const result = await leagueCommand(supabase, input);
  if (result.error) {
    throw new Error(
      `league:${input.action}:${input.aggregateId}@${input.expectedRevision} failed `
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

async function bestEffort(label, action) {
  try {
    await action();
  } catch (error) {
    console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error);
  }
}

async function ensureRegularUser(platformOwner, regularUser, account) {
  const probe = await regularUser.rpc("get_my_pachanga_platform_access_v1");
  if (probe.error) return;
  await rpc(platformOwner, "set_pachanga_platform_role_v1", {
    expected_revision: probe.data.revision,
    next_active: false,
    next_role: probe.data.role,
    operation_id: randomUUID(),
    reason: "R4A staging regular user fixture",
    target_user_id: account.id,
  });
}

async function insertMissing(table, rows, conflictColumn) {
  const result = await fixtureAdmin
    .from(table)
    .upsert(rows, { ignoreDuplicates: true, onConflict: conflictColumn });
  if (result.error) throw result.error;
}

async function ensureFixtureTeams() {
  const existingGroups = await fixtureAdmin
    .from("pachanga_groups")
    .select("id")
    .in("id", [GROUP_A, GROUP_B, GROUP_C]);
  if (existingGroups.error) throw existingGroups.error;
  const present = new Set(existingGroups.data.map((item) => item.id));
  const groups = [
    [GROUP_A, USERS.ownerA.id, "R4A Team A", "R4A-TEAM-A"],
    [GROUP_B, USERS.ownerB.id, "R4A Team B", "R4A-TEAM-B"],
    [GROUP_C, USERS.ownerC.id, "R4A Team C", "R4A-TEAM-C"],
  ].filter(([id]) => !present.has(id)).map(([id, ownerId, name, teamCode]) => ({
    id,
    name,
    owner_id: ownerId,
    payload: { matches: [], players: [], qaFixture: "R4A_STAGING" },
    team_code: teamCode,
  }));
  if (groups.length > 0) {
    const inserted = await fixtureAdmin.from("pachanga_groups").insert(groups);
    if (inserted.error) throw inserted.error;
  }

  await insertMissing("pachanga_group_members", [
    { display_name: "Owner A QA", group_id: GROUP_A, role: "owner", user_id: USERS.ownerA.id },
    { display_name: "Admin A QA", group_id: GROUP_A, role: "admin", user_id: USERS.adminA.id },
    { display_name: "Player A QA", group_id: GROUP_A, role: "player", user_id: USERS.playerA.id },
    { display_name: "Owner B QA", group_id: GROUP_B, role: "owner", user_id: USERS.ownerB.id },
    { display_name: "Staff A QA", group_id: GROUP_B, role: "player", user_id: USERS.staffA.id },
    { display_name: "Shared Player QA", group_id: GROUP_B, role: "player", user_id: USERS.playerA.id },
    { display_name: "Owner C QA", group_id: GROUP_C, role: "owner", user_id: USERS.ownerC.id },
  ], "group_id,user_id");

  await insertMissing("pachanga_player_profiles", [
    {
      birth_date: "1990-01-10",
      display_name: "Owner A QA",
      id: "f1710000-0000-4000-8000-000000000002",
      source_group_id: GROUP_A,
      user_id: USERS.ownerA.id,
    },
    {
      birth_date: "1992-02-11",
      display_name: "Admin A QA",
      id: "f1710000-0000-4000-8000-000000000003",
      source_group_id: GROUP_A,
      user_id: USERS.adminA.id,
    },
    {
      birth_date: "1988-03-12",
      display_name: "Player A QA",
      id: "f1710000-0000-4000-8000-000000000004",
      source_group_id: GROUP_A,
      user_id: USERS.playerA.id,
    },
    {
      birth_date: "1985-04-13",
      display_name: "Owner B QA",
      id: "f1710000-0000-4000-8000-000000000005",
      source_group_id: GROUP_B,
      user_id: USERS.ownerB.id,
    },
    {
      birth_date: "1987-05-14",
      display_name: "Staff A QA",
      id: "f1710000-0000-4000-8000-000000000006",
      source_group_id: GROUP_B,
      user_id: USERS.staffA.id,
    },
    {
      birth_date: "1991-06-15",
      display_name: "Owner C QA",
      id: "f1710000-0000-4000-8000-000000000007",
      source_group_id: GROUP_C,
      user_id: USERS.ownerC.id,
    },
  ], "user_id");
}

async function findReusableFixtureClub() {
  const result = await fixtureAdmin
    .from("pachanga_clubs")
    .select("id, operational_status, revision")
    .eq("created_by", USERS.ownerA.id)
    .like("name", "R4A Organizer %")
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (result.error) throw result.error;
  return result.data;
}

async function clubFlags(supabase) {
  return rpc(supabase, "get_pachanga_club_foundation_flags_v1");
}

async function setClubFlags(platform, next, reason) {
  const current = await clubFlags(platform);
  return foundationCommandOk(platform, "command_pachanga_club_platform_v1", {
    action: "club_flags.set",
    aggregateId: CLUB_FLAGS_ID,
    expectedRevision: current.revision,
    payload: { ...next, reason },
  });
}

async function competitionOverview(supabase) {
  return rpc(supabase, "get_pachanga_platform_competition_foundation_v1", {
    page_offset: 0,
    page_size: 200,
  });
}

async function setCompetitionFlags(platform, next, reason) {
  const current = await competitionOverview(platform);
  return foundationCommandOk(platform, "command_pachanga_competition_platform_v1", {
    action: "foundation_flags.set",
    aggregateId: COMPETITION_FLAGS_ID,
    expectedRevision: current.flags.revision,
    payload: { ...next, reason },
  });
}

async function leagueFlags(supabase) {
  return rpc(supabase, "get_pachanga_league_participation_flags_v1");
}

async function setLeagueFlags(platform, next, reason) {
  const current = await leagueFlags(platform);
  const result = await platform.rpc("command_pachanga_league_participation_platform_v1", {
    aggregate_id: LEAGUE_FLAGS_ID,
    client_metadata: clientMetadata("league-participation-staging-control"),
    command_payload: { ...next, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function setRefereeFlagsOff(platform) {
  const current = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  if (
    !current.assignmentsEnabled
    && !current.clubRelationshipsEnabled
    && !current.foundationEnabled
    && !current.marketplaceEnabled
    && !current.publicProfilesEnabled
    && !current.selfServiceEnabled
  ) return current;
  const result = await platform.rpc("command_pachanga_referee_platform_admin_v1", {
    aggregate_id: REFEREE_FLAGS_ID,
    client_metadata: clientMetadata("league-participation-staging-cleanup"),
    command_action: "referee_flags.set",
    command_payload: {
      assignmentsEnabled: false,
      clubRelationshipsEnabled: false,
      foundationEnabled: false,
      marketplaceEnabled: false,
      publicProfilesEnabled: false,
      reason: "R4A staging cleanup",
      selfServiceEnabled: false,
    },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function clubSnapshot(supabase, clubId) {
  return rpc(supabase, "get_pachanga_club_foundation_snapshot_v1", {
    target_club_id: clubId,
  });
}

async function competitionSnapshot(supabase, competitionId) {
  return rpc(supabase, "get_pachanga_competition_foundation_snapshot_v1", {
    target_competition_id: competitionId,
  });
}

async function taggedQaCompetitions() {
  const result = await fixtureAdmin
    .from("pachanga_competitions")
    .select("id, revision, status")
    .like("name", "R4A %")
    .order("created_at", { ascending: true });
  if (result.error) throw result.error;
  return result.data ?? [];
}

async function revokeTaggedQaCredentials(platformOwner, competitions) {
  const competitionIds = competitions.map((competition) => competition.id);
  if (competitionIds.length === 0) return;
  const result = await fixtureAdmin
    .from("pachanga_player_competition_credentials")
    .select("id, revision, status")
    .in("competition_id", competitionIds)
    .neq("status", "revoked")
    .order("server_sequence", { ascending: true });
  if (result.error) throw result.error;
  for (const credential of result.data ?? []) {
    await leagueCommandOk(platformOwner, {
      action: "credential.review",
      aggregateId: credential.id,
      expectedRevision: credential.revision,
      payload: {
        reason: "R4A staging fixture cleanup",
        reasonCode: "credential.qa_cleanup",
        status: "revoked",
        verificationMethod: "QA_CLEANUP",
      },
      surface: "league-participation-staging-cleanup",
    });
  }
}

async function cancelTaggedQaCompetitions(platformOwner, competitions) {
  for (const competition of competitions) {
    if (competition.status !== "draft") continue;
    await foundationCommandOk(
      platformOwner,
      "command_pachanga_competition_foundation_v1",
      {
        action: "competition.cancel",
        aggregateId: competition.id,
        expectedRevision: competition.revision,
        payload: { reason: "R4A staging fixture cleanup" },
        surface: "league-participation-staging-cleanup",
      },
    );
  }
}

async function entrySnapshot(supabase, entryId) {
  return rpc(supabase, "get_pachanga_competition_entry_v1", {
    target_entry_id: entryId,
  });
}

async function rosterSnapshot(supabase, rosterId) {
  return rpc(supabase, "get_pachanga_competition_roster_v1", {
    page_offset: 0,
    page_size: 50,
    target_roster_id: rosterId,
  });
}

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("R4A Realtime subscription timed out")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`R4A Realtime subscription failed: ${status}`));
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
          reject(new Error("R4A invalidation timed out"));
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

async function captureUntouchedDomainCounts() {
  const entries = await Promise.all(UNTOUCHED_DOMAIN_TABLES.map(async (table) => {
    const result = await fixtureAdmin.from(table).select("*", { count: "exact", head: true });
    if (result.error) throw new Error(`Unable to count ${table}: ${result.error.message}`);
    return [table, result.count ?? 0];
  }));
  return Object.fromEntries(entries);
}

function snapshotItem(snapshot, key, predicate, label) {
  const selected = snapshot[key].find(predicate);
  assert.ok(selected, `${label} must exist in the canonical snapshot`);
  return selected;
}

async function archiveFixtureClub(platformOwner, clubId) {
  let snapshot = await clubSnapshot(platformOwner, clubId);
  for (const grant of snapshot.entitlements.grants ?? []) {
    if (grant.status !== "active") continue;
    snapshot = await clubSnapshot(platformOwner, clubId);
    await foundationCommandOk(platformOwner, "command_pachanga_club_platform_v1", {
      action: "club.entitlement.revoke",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: { entitlementId: grant.id, reason: "R4A staging cleanup" },
      surface: "league-participation-staging-cleanup",
    });
  }
  snapshot = await clubSnapshot(platformOwner, clubId);
  if (snapshot.club.operationalStatus !== "archived") {
    await foundationCommandOk(platformOwner, "command_pachanga_club_platform_v1", {
      action: "club.status.set",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: { reason: "R4A staging cleanup", status: "archived" },
      surface: "league-participation-staging-cleanup",
    });
  }
}

let platformOwner;
let ownerADesktop;
let ownerAMobile;
let adminA;
let playerA;
let ownerB;
let staffA;
let ownerC;
let completed = false;
let untouchedDomainCountsBefore;

try {
  [
    platformOwner,
    ownerADesktop,
    ownerAMobile,
    adminA,
    playerA,
    ownerB,
    staffA,
    ownerC,
  ] = await Promise.all([
    signIn(USERS.platformOwner),
    signIn(USERS.ownerA),
    signIn(USERS.ownerA),
    signIn(USERS.adminA),
    signIn(USERS.playerA),
    signIn(USERS.ownerB),
    signIn(USERS.staffA),
    signIn(USERS.ownerC),
  ]);
  await ensureRegularUser(platformOwner, ownerC, USERS.ownerC);
  await ensureFixtureTeams();
  untouchedDomainCountsBefore = await captureUntouchedDomainCounts();

  const initialLeagueFlags = await leagueFlags(platformOwner);
  assert.equal(initialLeagueFlags.foundationEnabled, false);
  assert.equal(initialLeagueFlags.registrationEnabled, false);
  assert.equal(initialLeagueFlags.publicRegistrationEnabled, false);
  assert.equal(initialLeagueFlags.delegatesEnabled, false);
  assert.equal(initialLeagueFlags.rostersEnabled, false);
  assert.equal(initialLeagueFlags.schedulePreferencesEnabled, false);

  await setClubFlags(platformOwner, {
    competitionOrganizerEnabled: true,
    foundationEnabled: true,
    publicProfilesEnabled: false,
    selfServiceCreationEnabled: true,
    teamRelationshipsEnabled: false,
  }, "R4A staging Club window");
  await setCompetitionFlags(platformOwner, {
    contextBindingEnabled: false,
    creationEnabled: true,
    foundationEnabled: true,
  }, "R4A staging Competition window");
  await setLeagueFlags(platformOwner, {
    delegatesEnabled: true,
    foundationEnabled: true,
    publicRegistrationEnabled: true,
    registrationEnabled: true,
    rostersEnabled: true,
    schedulePreferencesEnabled: true,
  }, "R4A authenticated staging QA");

  const runTag = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  const reusableClub = await findReusableFixtureClub();
  if (reusableClub) {
    created.clubId = reusableClub.id;
    if (reusableClub.operational_status !== "active") {
      await foundationCommandOk(
        platformOwner,
        "command_pachanga_club_platform_v1",
        {
          action: "club.status.set",
          aggregateId: created.clubId,
          expectedRevision: reusableClub.revision,
          payload: { reason: "R4A staging Club reuse", status: "active" },
        },
      );
    }
  } else {
    const clubId = randomUUID();
    const clubCreated = await foundationCommandOk(
      ownerADesktop,
      "command_pachanga_club_foundation_v1",
      {
        action: "club.create",
        aggregateId: clubId,
        expectedRevision: 0,
        payload: {
          clubType: "FOOTBALL_CLUB",
          countryCode: "ES",
          municipality: "Barcelona",
          name: `R4A Organizer ${runTag}`,
          province: "Barcelona",
          reason: "R4A staging Club organizer",
          slug: `r4a-organizer-${runTag}`,
          visibility: "private",
        },
      },
    );
    created.clubId = clubId;
    const clubSubmitted = await foundationCommandOk(
      ownerADesktop,
      "command_pachanga_club_foundation_v1",
      {
        action: "club.review.submit",
        aggregateId: created.clubId,
        expectedRevision: clubCreated.snapshot.club.revision,
        payload: { reason: "R4A staging Club review" },
      },
    );
    await foundationCommandOk(
      platformOwner,
      "command_pachanga_club_platform_v1",
      {
        action: "club.status.set",
        aggregateId: created.clubId,
        expectedRevision: clubSubmitted.snapshot.club.revision,
        payload: { reason: "R4A staging Club activation", status: "active" },
      },
    );
  }

  let club = await clubSnapshot(ownerADesktop, created.clubId);
  if (!club.memberships.some((item) => (
    item.userId === USERS.staffA.id
    && item.role === "club_competition_manager"
    && item.status === "active"
  ))) {
    const managerInvite = await foundationCommandOk(
      ownerADesktop,
      "command_pachanga_club_foundation_v1",
      {
        action: "membership.invite",
        aggregateId: created.clubId,
        expectedRevision: club.club.revision,
        payload: {
          reason: "R4A staging Competition manager",
          role: "club_competition_manager",
          targetKind: "registered_user",
          targetUserId: USERS.staffA.id,
        },
      },
    );
    const managerAccepted = await foundationCommandOk(
      staffA,
      "command_pachanga_club_foundation_v1",
      {
        action: "membership.accept",
        aggregateId: managerInvite.invitationId,
        expectedRevision: 1,
        payload: { reason: "R4A manager accepts", token: managerInvite.oneTimeToken },
      },
    );
    assert.ok(managerAccepted.snapshot.memberships.some((item) => (
      item.userId === USERS.staffA.id && item.role === "club_competition_manager"
    )));
  }

  club = await clubSnapshot(platformOwner, created.clubId);
  const entitlement = await foundationCommandOk(
    platformOwner,
    "command_pachanga_club_platform_v1",
    {
      action: "club.entitlement.grant",
      aggregateId: created.clubId,
      expectedRevision: club.club.revision,
      payload: {
        capability: "competition_create",
        reason: "R4A staging League entitlement",
        source: "platform_grant",
      },
    },
  );
  created.entitlementId = entitlement.snapshot.entitlements.grants.find((grant) => (
    grant.status === "active" && grant.capability === "competition_create"
  ))?.id ?? null;
  const manageEntitlement = await foundationCommandOk(
    platformOwner,
    "command_pachanga_club_platform_v1",
    {
      action: "club.entitlement.grant",
      aggregateId: created.clubId,
      expectedRevision: entitlement.snapshot.club.revision,
      payload: {
        capability: "competition_manage",
        reason: "R4A staging League management entitlement",
        source: "platform_grant",
      },
    },
  );

  const competitionCreateOperation = randomUUID();
  const competitionCreateInput = {
    action: "competition.create",
    aggregateId: created.clubId,
    expectedRevision: manageEntitlement.snapshot.entitlements.organizerRevision,
    operationId: competitionCreateOperation,
    organizerKind: "CLUB",
    payload: {
      competitionType: "LEAGUE",
      editionName: "Edition 2027",
      endsAt: "2027-12-31",
      name: `R4A League ${runTag}`,
      reason: "R4A Club manager creates League",
      ruleSetName: "R4A explicit QA rules",
      seasonLabel: "2027",
      slug: `r4a-league-${runTag}`,
      startsAt: "2027-01-01",
      visibility: "public",
    },
  };
  const competitionCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v2",
    competitionCreateInput,
  );
  const competitionReplay = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v2",
    competitionCreateInput,
  );
  assert.deepEqual(competitionReplay, competitionCreated);
  created.competitionId = competitionCreated.snapshot.competition.id;
  const edition = competitionCreated.snapshot.editions[0];
  const ruleSet = competitionCreated.snapshot.ruleSets[0];
  assert.equal(competitionCreated.snapshot.competition.organizerKind, "CLUB");

  const ruleCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "rule_revision.create",
      aggregateId: ruleSet.id,
      expectedRevision: ruleSet.revision,
      payload: {
        effectiveFrom: "2027-01-01T00:00:00Z",
        effectiveScope: "future_only",
        reason: "R4A explicit isolated QA revision",
        ruleDocument: {
          discipline: {},
          format: { modality: "futbol7" },
          futureCapabilities: {},
          governance: {},
          operations: {
            hardAvailabilityPolicy: { mode: "required" },
            schedulePreferencePolicy: { mode: "preferred" },
          },
          publication: {},
          registration: {
            identityRequirements: { credentialRequired: true },
            kitPolicy: {
              jerseyNumberMaximum: 99,
              jerseyNumberMinimum: 1,
              jerseyRequired: true,
            },
            publicSummary: { roster: "2-4 players", verification: "required" },
            registrationPolicy: { teamLimits: { maximum: 8, minimum: 2 } },
            rosterPolicy: {
              closeRequiresApprovedRosters: false,
              maximumSize: 4,
              minimumSize: 2,
              multiTeamPolicy: "FORBIDDEN_SAME_EDITION_CATEGORY",
            },
          },
          results: { scoringPolicy: {}, tieBreakCriteria: [] },
          structure: {
            stageGraph: { edges: [], nodes: [{ id: "league-stage", root: true }] },
          },
        },
        schemaVersion: "competition_rules.v1",
      },
    },
  );
  const ruleRevision = ruleCreated.snapshot.ruleSets
    .find((item) => item.id === ruleSet.id).revisions[0];
  const validated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "rule_revision.validate",
      aggregateId: ruleRevision.id,
      expectedRevision: ruleRevision.revision,
    },
  );
  const validatedRule = validated.snapshot.ruleSets
    .find((item) => item.id === ruleSet.id).revisions
    .find((item) => item.id === ruleRevision.id);
  const published = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "rule_revision.publish",
      aggregateId: ruleSet.id,
      expectedRevision: ruleCreated.confirmedRevision,
      payload: { ruleRevisionId: ruleRevision.id },
    },
  );
  let foundationSnapshot = await competitionSnapshot(staffA, created.competitionId);
  const assignedRule = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "edition.assign_rule_revision",
      aggregateId: edition.id,
      expectedRevision: foundationSnapshot.editions.find((item) => item.id === edition.id).revision,
      payload: { ruleRevisionId: ruleRevision.id },
    },
  );
  const publishedRule = published.snapshot.ruleSets
    .find((item) => item.id === ruleSet.id).revisions
    .find((item) => item.id === ruleRevision.id);
  assert.ok(publishedRule.revision >= validatedRule.revision);
  await foundationCommandOk(staffA, "command_pachanga_competition_foundation_v1", {
    action: "rule_revision.freeze",
    aggregateId: ruleRevision.id,
    expectedRevision: publishedRule.revision,
  });

  const stageCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "stage.create",
      aggregateId: edition.id,
      expectedRevision: assignedRule.confirmedRevision,
      payload: {
        name: "League Stage",
        optional: false,
        ruleRevisionId: ruleRevision.id,
        stageOrder: 0,
        stageType: "LEAGUE_STAGE",
      },
    },
  );
  const stage = snapshotItem(stageCreated.snapshot, "stages", (item) => item.name === "League Stage", "League Stage");
  const divisionCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "division.create",
      aggregateId: stage.id,
      expectedRevision: stage.revision,
      payload: { levelLabel: "Open", name: "Division 1", order: 0 },
    },
  );
  const stageAfterDivision = divisionCreated.snapshot.stages.find((item) => item.id === stage.id);
  const division = stageAfterDivision.divisions.find((item) => item.name === "Division 1");
  const groupACreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "group.create",
      aggregateId: stage.id,
      expectedRevision: divisionCreated.confirmedRevision,
      payload: { divisionId: division.id, name: "Group A", order: 0 },
    },
  );
  const groupA = groupACreated.snapshot.stages.find((item) => item.id === stage.id)
    .groups.find((item) => item.name === "Group A");
  const groupBCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v1",
    {
      action: "group.create",
      aggregateId: stage.id,
      expectedRevision: groupACreated.confirmedRevision,
      payload: { divisionId: division.id, name: "Group B", order: 1 },
    },
  );
  const groupB = groupBCreated.snapshot.stages.find((item) => item.id === stage.id)
    .groups.find((item) => item.name === "Group B");

  foundationSnapshot = await competitionSnapshot(staffA, created.competitionId);
  const currentEdition = foundationSnapshot.editions.find((item) => item.id === edition.id);
  const openCategoryOperation = randomUUID();
  const openCategoryInput = {
    action: "category.create",
    aggregateId: edition.id,
    expectedRevision: currentEdition.revision,
    operationId: openCategoryOperation,
    payload: {
      ageReferenceDate: "2027-01-01",
      description: "Open R4A staging category",
      eligibilityPolicy: { age: "adult" },
      levelLabel: "Open",
      minimumAge: 18,
      name: "Open",
      reason: "R4A open category",
      ruleRevisionId: ruleRevision.id,
      slug: `open-${runTag}`,
      sportFormat: "FOOTBALL_7",
      visibility: "public",
    },
  };
  const openCreated = await leagueCommandOk(staffA, openCategoryInput);
  const openReplay = await leagueCommandOk(staffA, openCategoryInput);
  assert.deepEqual(openReplay, openCreated);
  const openCategory = openCreated.snapshot;
  foundationSnapshot = await competitionSnapshot(staffA, created.competitionId);
  const veteransCreated = await leagueCommandOk(staffA, {
    action: "category.create",
    aggregateId: edition.id,
    expectedRevision: foundationSnapshot.editions.find((item) => item.id === edition.id).revision,
    payload: {
      ageReferenceDate: "2027-01-01",
      eligibilityPolicy: { minimumAge: 35 },
      levelLabel: "Veterans",
      minimumAge: 35,
      name: "Veterans",
      reason: "R4A veterans category",
      ruleRevisionId: ruleRevision.id,
      slug: `veterans-${runTag}`,
      sportFormat: "FOOTBALL_7",
      visibility: "public",
    },
  });
  const veteransCategory = veteransCreated.snapshot;
  await leagueCommandOk(staffA, {
    action: "category.activate",
    aggregateId: openCategory.id,
    expectedRevision: openCategory.revision,
    payload: { reason: "Activate Open" },
  });
  await leagueCommandOk(staffA, {
    action: "category.activate",
    aggregateId: veteransCategory.id,
    expectedRevision: veteransCategory.revision,
    payload: { reason: "Activate Veterans" },
  });

  foundationSnapshot = await competitionSnapshot(staffA, created.competitionId);
  const registrationOpened = await leagueCommandOk(staffA, {
    action: "registration.open",
    aggregateId: edition.id,
    expectedRevision: foundationSnapshot.editions.find((item) => item.id === edition.id).revision,
    payload: {
      closesAt: "2027-11-30T23:00:00Z",
      reason: "Open R4A public registration",
      registrationMode: "PUBLIC_APPROVAL",
      ruleRevisionId: ruleRevision.id,
    },
  });
  assert.equal(registrationOpened.snapshot.status, "registration_open");

  const queue = invalidationQueue();
  const channel = ownerAMobile
    .channel(`league-participation-staging-${randomUUID()}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `target_group_id=eq.${GROUP_A}`,
      schema: "public",
      table: "pachanga_competition_invalidations",
    }, (payload) => queue.push(payload));
  channels.push([ownerAMobile, channel]);
  await waitForSubscription(channel);
  queue.clear();

  const adminSubmit = await leagueCommand(adminA, {
    action: "entry.submit",
    aggregateId: openCategory.id,
    expectedRevision: 2,
    payload: { reason: "Team admin must fail", teamId: GROUP_A },
  });
  expectRpcError(adminSubmit, /TEAM_OWNER_REQUIRED/, "42501");

  const teamAInvalidation = queue.next();
  const entryOperation = randomUUID();
  const concurrentSubmissions = await Promise.all([
    leagueCommand(ownerADesktop, {
      action: "entry.submit",
      aggregateId: openCategory.id,
      expectedRevision: 2,
      operationId: entryOperation,
      payload: { reason: "Team A public application", teamId: GROUP_A },
    }),
    leagueCommand(ownerAMobile, {
      action: "entry.submit",
      aggregateId: openCategory.id,
      expectedRevision: 2,
      payload: { reason: "Team A duplicate application", teamId: GROUP_A },
    }),
  ]);
  assert.equal(concurrentSubmissions.filter((result) => !result.error).length, 1);
  assert.equal(concurrentSubmissions.filter((result) => result.error).length, 1);
  const entryASubmitted = concurrentSubmissions.find((result) => !result.error).data;
  const entryA = entryASubmitted.snapshot.entry;
  created.entryIds.push(entryA.id);
  created.acceptedEntries.push({ client: ownerADesktop, id: entryA.id });
  expectRpcError(
    concurrentSubmissions.find((result) => result.error),
    /ENTRY_ALREADY_ACTIVE|LEAGUE_PARTICIPATION_CONFLICT/,
    "PT409",
  );
  const entryAReplay = await leagueCommandOk(ownerAMobile, {
    action: "entry.submit",
    aggregateId: openCategory.id,
    expectedRevision: 2,
    operationId: entryOperation,
    payload: { reason: "Team A public application", teamId: GROUP_A },
  });
  assert.deepEqual(entryAReplay, entryASubmitted);
  const invalidation = await teamAInvalidation;
  assert.equal(invalidation.new.target_group_id, GROUP_A);
  const mobileEntries = await rpc(ownerAMobile, "get_my_pachanga_competition_entries_v1", {
    page_offset: 0,
    page_size: 10,
  });
  assert.ok(mobileEntries.items.some((item) => item.id === entryA.id));

  const acceptAOperation = randomUUID();
  const acceptedA = await leagueCommandOk(staffA, {
    action: "entry.accept",
    aggregateId: entryA.id,
    expectedRevision: entryA.revision,
    operationId: acceptAOperation,
    payload: { reason: "Organizer accepts Team A" },
  });
  const acceptedAReplay = await leagueCommandOk(staffA, {
    action: "entry.accept",
    aggregateId: entryA.id,
    expectedRevision: entryA.revision,
    operationId: acceptAOperation,
    payload: { reason: "Organizer accepts Team A" },
  });
  assert.deepEqual(acceptedAReplay, acceptedA);
  assert.equal(await notificationCount(
    ownerADesktop,
    `league:${acceptAOperation}:${USERS.ownerA.id}`,
  ), 1);
  created.rosterIds.push(acceptedA.snapshot.roster.id);

  const invitedB = await leagueCommandOk(staffA, {
    action: "entry.invite",
    aggregateId: openCategory.id,
    expectedRevision: 2,
    payload: {
      expiresAt: "2027-11-15T23:00:00Z",
      reason: "Private invitation Team B",
      teamId: GROUP_B,
    },
  });
  const entryB = invitedB.snapshot.entry;
  created.entryIds.push(entryB.id);
  created.acceptedEntries.push({ client: ownerB, id: entryB.id });
  const acceptedB = await leagueCommandOk(ownerB, {
    action: "entry.accept",
    aggregateId: entryB.id,
    expectedRevision: entryB.revision,
    payload: { reason: "Owner B accepts" },
  });
  created.rosterIds.push(acceptedB.snapshot.roster.id);

  const submittedC = await leagueCommandOk(ownerC, {
    action: "entry.submit",
    aggregateId: openCategory.id,
    expectedRevision: 2,
    payload: { reason: "Team C public application", teamId: GROUP_C },
  });
  const entryC = submittedC.snapshot.entry;
  created.entryIds.push(entryC.id);
  created.acceptedEntries.push({ client: ownerC, id: entryC.id });
  await leagueCommandOk(staffA, {
    action: "entry.reject",
    aggregateId: entryC.id,
    expectedRevision: entryC.revision,
    payload: {
      reason: "Private organizer QA reason",
      reasonCode: "entry.qa_rejected",
    },
  });
  const teamCRead = await entrySnapshot(ownerC, entryC.id);
  assert.equal("privateReason" in teamCRead.entry, false);
  assert.equal(JSON.stringify(teamCRead).includes("Private organizer QA reason"), false);

  const invitedBVeterans = await leagueCommandOk(staffA, {
    action: "entry.invite",
    aggregateId: veteransCategory.id,
    expectedRevision: 2,
    payload: { reason: "Team B Veterans invitation", teamId: GROUP_B },
  });
  const entryBVeterans = invitedBVeterans.snapshot.entry;
  created.entryIds.push(entryBVeterans.id);
  created.acceptedEntries.push({ client: ownerB, id: entryBVeterans.id });
  const acceptedBVeterans = await leagueCommandOk(ownerB, {
    action: "entry.accept",
    aggregateId: entryBVeterans.id,
    expectedRevision: entryBVeterans.revision,
    payload: { reason: "Owner B accepts Veterans" },
  });
  created.rosterIds.push(acceptedBVeterans.snapshot.roster.id);

  const pendingC = await leagueCommandOk(staffA, {
    action: "entry.invite",
    aggregateId: veteransCategory.id,
    expectedRevision: 2,
    payload: { reason: "Pending close guard", teamId: GROUP_C },
  });
  created.entryIds.push(pendingC.snapshot.entry.id);
  created.acceptedEntries.push({ client: ownerC, id: pendingC.snapshot.entry.id });

  let entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  const delegateAInvite = await leagueCommandOk(ownerADesktop, {
    action: "delegate.invite",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      reason: "Invite external primary delegate",
      role: "PRIMARY_DELEGATE",
      userId: USERS.ownerB.id,
    },
  });
  const delegateA = delegateAInvite.snapshot.delegates.find((item) => (
    item.status === "invited" && item.role === "PRIMARY_DELEGATE"
  ));
  created.delegateIds.push(delegateA.id);
  await leagueCommandOk(ownerB, {
    action: "delegate.accept",
    aggregateId: delegateA.id,
    expectedRevision: delegateA.revision,
    payload: { reason: "Delegate A accepts" },
  });
  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  const delegateBInvite = await leagueCommandOk(ownerADesktop, {
    action: "delegate.invite",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      reason: "Invite roster manager",
      role: "ROSTER_MANAGER",
      userId: USERS.playerA.id,
    },
  });
  const delegateB = delegateBInvite.snapshot.delegates.find((item) => (
    item.status === "invited" && item.role === "ROSTER_MANAGER"
  ));
  created.delegateIds.push(delegateB.id);
  await leagueCommandOk(playerA, {
    action: "delegate.accept",
    aggregateId: delegateB.id,
    expectedRevision: delegateB.revision,
    payload: { reason: "Delegate B accepts" },
  });
  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  const transferred = await leagueCommandOk(ownerADesktop, {
    action: "delegate.primary.transfer",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: { reason: "Transfer primary delegate", targetDelegateId: delegateB.id },
  });
  assert.equal(transferred.snapshot.actorScope, "TEAM_OWNER");
  assert.equal(transferred.snapshot.delegates.filter((item) => (
    item.role === "PRIMARY_DELEGATE" && item.status === "active"
  )).length, 1);
  created.delegateIds.push(transferred.snapshot.delegates.find((item) => (
    item.role === "PRIMARY_DELEGATE" && item.status === "active"
  )).id);

  const rosterAId = acceptedA.snapshot.roster.id;
  const rosterBId = acceptedB.snapshot.roster.id;
  const rosterBVeteransId = acceptedBVeterans.snapshot.roster.id;
  const profiles = {
    adminA: "f1710000-0000-4000-8000-000000000003",
    ownerA: "f1710000-0000-4000-8000-000000000002",
    playerA: "f1710000-0000-4000-8000-000000000004",
  };

  for (const profileId of [profiles.ownerA, profiles.adminA, profiles.playerA]) {
    const roster = await rosterSnapshot(playerA, rosterAId);
    await leagueCommandOk(playerA, {
      action: "roster.member.add",
      aggregateId: rosterAId,
      expectedRevision: roster.roster.revision,
      payload: { playerProfileId: profileId, reason: "R4A staging roster member" },
    });
  }
  let rosterA = await rosterSnapshot(playerA, rosterAId);
  for (const [profileId, number] of [
    [profiles.ownerA, 7],
    [profiles.adminA, 8],
    [profiles.playerA, 9],
  ]) {
    await leagueCommandOk(playerA, {
      action: "jersey.assign",
      aggregateId: rosterAId,
      expectedRevision: rosterA.roster.revision,
      payload: { number, playerProfileId: profileId, reason: "R4A staging jersey" },
    });
    rosterA = await rosterSnapshot(playerA, rosterAId);
  }
  const duplicateJersey = await leagueCommand(playerA, {
    action: "jersey.assign",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { number: 7, playerProfileId: profiles.adminA, reason: "Duplicate jersey" },
  });
  expectRpcError(duplicateJersey, /LEAGUE_PARTICIPATION_CONFLICT/, "PT409");

  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  await leagueCommandOk(ownerADesktop, {
    action: "kit.set",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      assetReference: "team-kit://r4a-staging/home",
      kitType: "HOME",
      pattern: "SOLID",
      primaryColor: "#0E5BD8",
      reason: "R4A staging HOME kit",
      secondaryColor: "#FFFFFF",
    },
  });
  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  await leagueCommandOk(playerA, {
    action: "availability.set",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      endLocalTime: "23:00",
      reason: "NO PUEDO JUGAR lunes noche",
      startLocalTime: "19:00",
      timezone: "Europe/Madrid",
      validFromDate: "2027-01-01",
      validUntilDate: "2027-12-31",
      weekday: 1,
    },
  });
  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  await leagueCommandOk(playerA, {
    action: "preference.set",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      endLocalTime: "20:00",
      preferredArea: "Barcelona",
      reason: "PREFERIRIA JUGAR sabado tarde",
      startLocalTime: "16:00",
      timezone: "Europe/Madrid",
      venueReference: "venue://r4a-future",
      weekday: 6,
      weight: 80,
    },
  });
  entryAState = await entrySnapshot(ownerADesktop, entryA.id);
  assert.equal(entryAState.availabilityConstraints.length, 1);
  assert.equal(entryAState.schedulePreferences.length, 1);

  rosterA = await rosterSnapshot(playerA, rosterAId);
  await leagueCommandOk(playerA, {
    action: "roster.submit",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { reason: "Initial R4A roster submission" },
  });
  rosterA = await rosterSnapshot(staffA, rosterAId);
  await leagueCommandOk(staffA, {
    action: "roster.request_changes",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { reason: "Resolve credentials" },
  });
  rosterA = await rosterSnapshot(playerA, rosterAId);
  await leagueCommandOk(playerA, {
    action: "roster.reopen",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { reason: "Apply requested changes" },
  });
  rosterA = await rosterSnapshot(playerA, rosterAId);
  await leagueCommandOk(playerA, {
    action: "roster.submit",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { reason: "Corrected R4A roster" },
  });

  rosterA = await rosterSnapshot(staffA, rosterAId);
  const credentials = Object.fromEntries(rosterA.members.map((member) => [
    member.playerProfileId,
    member.credential,
  ]));
  created.credentialIds.push(...Object.values(credentials).map((item) => item.id));
  let credential = credentials[profiles.ownerA];
  await leagueCommandOk(staffA, {
    action: "credential.review",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      reason: "Pending manual review",
      reasonCode: "credential.pending_review",
      status: "pending",
      verificationMethod: "MANUAL_REVIEW",
    },
  });
  rosterA = await rosterSnapshot(staffA, rosterAId);
  credential = rosterA.members.find((item) => item.playerProfileId === profiles.ownerA).credential;
  const verifiedCredential = await leagueCommandOk(staffA, {
    action: "credential.review",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      evidenceReference: "vault://r4a-staging/opaque-owner-a",
      expiresAt: "2029-12-31T23:00:00Z",
      reason: "Identity verified",
      reasonCode: "credential.verified",
      status: "verified",
      verificationMethod: "MANUAL_REVIEW",
    },
  });
  assert.equal(JSON.stringify(verifiedCredential).includes("vault://r4a-staging"), false);

  credential = rosterA.members.find((item) => item.playerProfileId === profiles.adminA).credential;
  await leagueCommandOk(staffA, {
    action: "credential.review",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      reason: "Rejected credential",
      reasonCode: "credential.insufficient",
      status: "rejected",
      verificationMethod: "MANUAL_REVIEW",
    },
  });
  rosterA = await rosterSnapshot(staffA, rosterAId);
  credential = rosterA.members.find((item) => item.playerProfileId === profiles.adminA).credential;
  await leagueCommandOk(staffA, {
    action: "eligibility.waive",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      reason: "Explicit organizer waiver",
      reasonCode: "eligibility.organizer_waiver",
      validUntil: "2028-12-31T23:00:00Z",
    },
  });

  rosterA = await rosterSnapshot(staffA, rosterAId);
  credential = rosterA.members.find((item) => item.playerProfileId === profiles.playerA).credential;
  await leagueCommandOk(staffA, {
    action: "credential.review",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      reason: "Expired credential path",
      reasonCode: "credential.expired",
      status: "expired",
      verificationMethod: "MANUAL_REVIEW",
    },
  });
  rosterA = await rosterSnapshot(staffA, rosterAId);
  credential = rosterA.members.find((item) => item.playerProfileId === profiles.playerA).credential;
  await leagueCommandOk(staffA, {
    action: "credential.review",
    aggregateId: credential.id,
    expectedRevision: credential.revision,
    payload: {
      expiresAt: "2029-12-31T23:00:00Z",
      reason: "Renewed credential",
      reasonCode: "credential.verified",
      status: "verified",
      verificationMethod: "MANUAL_REVIEW",
    },
  });
  rosterA = await rosterSnapshot(staffA, rosterAId);
  const approvedA = await leagueCommandOk(staffA, {
    action: "roster.approve",
    aggregateId: rosterAId,
    expectedRevision: rosterA.roster.revision,
    payload: { reason: "All R4A eligibility resolved" },
  });
  const lockedA = await leagueCommandOk(staffA, {
    action: "roster.lock",
    aggregateId: rosterAId,
    expectedRevision: approvedA.confirmedRevision,
    payload: { reason: "Lock R4A roster" },
  });
  assert.equal(lockedA.snapshot.roster.status, "locked");

  let rosterB = await rosterSnapshot(ownerB, rosterBId);
  const sameCategoryConflict = await leagueCommand(ownerB, {
    action: "roster.member.add",
    aggregateId: rosterBId,
    expectedRevision: rosterB.roster.revision,
    payload: { playerProfileId: profiles.playerA, reason: "Same category conflict" },
  });
  expectRpcError(sameCategoryConflict, /PLAYER_MULTI_TEAM_CONFLICT/, "PT409");
  const crossDelegate = await leagueCommand(playerA, {
    action: "roster.member.add",
    aggregateId: rosterBId,
    expectedRevision: rosterB.roster.revision,
    payload: { playerProfileId: profiles.ownerA, reason: "Cross Entry delegate" },
  });
  expectRpcError(crossDelegate, /ROSTER_MANAGER_REQUIRED/, "42501");

  let rosterBVeterans = await rosterSnapshot(ownerB, rosterBVeteransId);
  await leagueCommandOk(ownerB, {
    action: "roster.member.add",
    aggregateId: rosterBVeteransId,
    expectedRevision: rosterBVeterans.roster.revision,
    payload: { playerProfileId: profiles.playerA, reason: "Different category allowed" },
  });
  rosterBVeterans = await rosterSnapshot(ownerB, rosterBVeteransId);
  const belowMinimum = await leagueCommand(ownerB, {
    action: "roster.submit",
    aggregateId: rosterBVeteransId,
    expectedRevision: rosterBVeterans.roster.revision,
    payload: { reason: "Below minimum roster" },
  });
  expectRpcError(belowMinimum, /ROSTER_BELOW_MINIMUM/, "22023");

  entryAState = await entrySnapshot(staffA, entryA.id);
  const stageA = await leagueCommandOk(staffA, {
    action: "stage_membership.assign",
    aggregateId: entryA.id,
    expectedRevision: entryAState.entry.revision,
    payload: {
      divisionId: division.id,
      groupId: groupA.id,
      reason: "Assign Team A Group A",
      stageId: stage.id,
    },
  });
  created.stageMembershipIds.push(stageA.snapshot.stageMembership.id);
  let entryBState = await entrySnapshot(staffA, entryB.id);
  const stageB = await leagueCommandOk(staffA, {
    action: "stage_membership.assign",
    aggregateId: entryB.id,
    expectedRevision: entryBState.entry.revision,
    payload: {
      divisionId: division.id,
      groupId: groupA.id,
      reason: "Assign Team B Group A",
      stageId: stage.id,
    },
  });
  created.stageMembershipIds.push(stageB.snapshot.stageMembership.id);
  entryBState = await entrySnapshot(staffA, entryB.id);
  const stageBReassigned = await leagueCommandOk(staffA, {
    action: "stage_membership.assign",
    aggregateId: entryB.id,
    expectedRevision: entryBState.entry.revision,
    payload: {
      divisionId: division.id,
      groupId: groupB.id,
      reason: "Reassign Team B before fixtures",
      stageId: stage.id,
    },
  });
  created.stageMembershipIds.push(stageBReassigned.snapshot.stageMembership.id);
  assert.equal(stageBReassigned.snapshot.stageMembership.groupId, groupB.id);

  const publicRead = await rpc(client(), "get_pachanga_league_public_registration_v1", {
    target_competition_id: created.competitionId,
  });
  assert.equal(publicRead.competition.type, "LEAGUE");
  assert.equal(publicRead.categories.length, 2);
  assert.equal(JSON.stringify(publicRead).includes("Private organizer QA reason"), false);
  const desk = await rpc(staffA, "get_pachanga_competition_registration_desk_v1", {
    category_filter: null,
    page_offset: 0,
    page_size: 20,
    status_filter: null,
    target_competition_id: created.competitionId,
  });
  assert.ok(desk.total >= 5);
  assert.ok(desk.items.some((item) => item.id === entryA.id && item.rosterStatus === "locked"));
  const pagedRoster = await rpc(staffA, "get_pachanga_competition_roster_v1", {
    page_offset: 0,
    page_size: 2,
    target_roster_id: rosterAId,
  });
  assert.equal(pagedRoster.members.length, 2);
  assert.equal(pagedRoster.memberPagination.total, 3);

  const outsiderRead = await adminA.rpc("get_pachanga_competition_entry_v1", {
    target_entry_id: entryB.id,
  });
  expectRpcError(outsiderRead, /ENTRY_READ_FORBIDDEN/, "42501");
  const forbiddenDirectWrite = await ownerADesktop.from("pachanga_competition_entries").insert({
    id: randomUUID(),
  });
  assert.ok(forbiddenDirectWrite.error);

  foundationSnapshot = await competitionSnapshot(staffA, created.competitionId);
  const editionBeforeClose = foundationSnapshot.editions.find((item) => item.id === edition.id);
  const closeBlocked = await leagueCommand(staffA, {
    action: "registration.close",
    aggregateId: edition.id,
    expectedRevision: editionBeforeClose.revision,
    payload: { reason: "Pending invitation must block close" },
  });
  expectRpcError(closeBlocked, /REGISTRATION_PENDING_ENTRIES/, "PT409");
  const closed = await leagueCommandOk(staffA, {
    action: "registration.close_and_expire_pending",
    aggregateId: edition.id,
    expectedRevision: editionBeforeClose.revision,
    payload: { reason: "Resolve pending and close R4A registration" },
  });
  assert.equal(closed.snapshot.status, "registration_closed");
  assert.equal(closed.snapshot.expiredPendingCount, 1);

  const closedSubmit = await leagueCommand(ownerC, {
    action: "entry.submit",
    aggregateId: openCategory.id,
    expectedRevision: 2,
    payload: { reason: "Registration is closed", teamId: GROUP_C },
  });
  expectRpcError(closedSubmit, /REGISTRATION_NOT_OPEN/, "22023");

  const platformRead = await rpc(platformOwner, "get_pachanga_platform_league_participation_v1", {
    page_offset: 0,
    page_size: 20,
  });
  assert.equal(platformRead.metrics.duplicateConflicts, 0);
  assert.equal(platformRead.errors.length, 0);

  const tournamentCreated = await foundationCommandOk(
    staffA,
    "command_pachanga_competition_foundation_v2",
    {
      action: "competition.create",
      aggregateId: created.clubId,
      expectedRevision: competitionCreated.confirmedRevision,
      organizerKind: "CLUB",
      payload: {
        competitionType: "TOURNAMENT",
        editionName: "Tournament guard edition",
        name: `R4A Tournament guard ${runTag}`,
        reason: "R4A must reject Tournament operations",
        ruleSetName: "Tournament guard rules",
        seasonLabel: "2027",
        slug: `r4a-tournament-${runTag}`,
        visibility: "private",
      },
    },
  );
  const tournamentCategory = await leagueCommand(staffA, {
    action: "category.create",
    aggregateId: tournamentCreated.snapshot.editions[0].id,
    expectedRevision: tournamentCreated.snapshot.editions[0].revision,
    payload: {
      name: "Unavailable",
      reason: "Tournament must remain unavailable in R4A",
      ruleRevisionId: ruleRevision.id,
      slug: `unavailable-${runTag}`,
      sportFormat: "FOOTBALL_7",
    },
  });
  expectRpcError(tournamentCategory, /FEATURE_NOT_AVAILABLE/, "0A000");

  const forbiddenTables = [
    "pachanga_competition_rounds",
    "pachanga_league_fixtures",
    "pachanga_competition_standings",
  ];
  for (const table of forbiddenTables) {
    const result = await fixtureAdmin.from(table).select("id").limit(1);
    assert.equal(result.error?.code, "PGRST205", `${table} must not exist in R4A`);
  }

  const untouchedDomainCountsAfter = await captureUntouchedDomainCounts();
  assert.deepEqual(
    untouchedDomainCountsAfter,
    untouchedDomainCountsBefore,
    "R4A must not mutate matches, results, Rating V2, conduct, rewards, cosmetics or rankings",
  );

  completed = true;
  console.log(JSON.stringify({
    canonicalMatchesCreated:
      untouchedDomainCountsAfter.pachanga_canonical_matches
      - untouchedDomainCountsBefore.pachanga_canonical_matches,
    clubOrganizer: "created_and_authorized",
    competitionType: "LEAGUE",
    concurrency: "duplicate_team_application_one_winner",
    credentials: "pending_verified_rejected_expired_waived",
    entries: "public_private_rejected_expired",
    fixturesCreated: 0,
    projectRef: actualProjectRef,
    realtime: "scoped_invalidation_then_canonical_refetch",
    rosters: "submitted_changes_approved_locked",
    roundsCreated: 0,
    stageMembership: "assigned_and_reassigned",
    standingsCreated: 0,
    status: "PASS",
    untouchedDomainCounts: untouchedDomainCountsAfter,
  }));
} finally {
  if (platformOwner) {
    for (const delegateId of created.delegateIds) {
      if (!ownerADesktop) break;
      await bestEffort(`revoke-delegate-${delegateId}`, async () => {
        const snapshot = await entrySnapshot(ownerADesktop, created.entryIds[0]);
        const delegate = snapshot.delegates.find((item) => item.id === delegateId);
        if (!delegate || !["active", "invited"].includes(delegate.status)) return;
        await leagueCommandOk(ownerADesktop, {
          action: "delegate.revoke",
          aggregateId: delegateId,
          expectedRevision: delegate.revision,
          payload: { reason: "R4A staging cleanup" },
          surface: "league-participation-staging-cleanup",
        });
      });
    }

    for (const entry of created.acceptedEntries) {
      await bestEffort(`withdraw-entry-${entry.id}`, async () => {
        const snapshot = await entrySnapshot(entry.client, entry.id);
        const cleanupAction = snapshot.entry.status === "invited"
          ? "entry.decline"
          : "entry.withdraw";
        if (!new Set(["accepted", "invited", "submitted"]).has(snapshot.entry.status)) return;
        await leagueCommandOk(entry.client, {
          action: cleanupAction,
          aggregateId: entry.id,
          expectedRevision: snapshot.entry.revision,
          payload: { reason: "R4A staging cleanup" },
          surface: "league-participation-staging-cleanup",
        });
      });
    }

    if (created.stageMembershipIds.length > 0) {
      await bestEffort("close-stage-memberships", async () => {
        const result = await fixtureAdmin
          .from("pachanga_competition_stage_memberships")
          .update({ status: "closed", valid_until: new Date().toISOString() })
          .in("id", created.stageMembershipIds)
          .eq("status", "active");
        if (result.error) throw result.error;
      });
    }
    const qaCompetitions = await taggedQaCompetitions().catch((error) => {
      console.error("[cleanup:list-r4a-competitions]", error instanceof Error ? error.message : error);
      return [];
    });
    await bestEffort("revoke-fixture-credentials", () => revokeTaggedQaCredentials(platformOwner, qaCompetitions));
    await bestEffort("cancel-r4a-competitions", () => cancelTaggedQaCompetitions(platformOwner, qaCompetitions));

    await bestEffort("disable-r4a-flags", () => setLeagueFlags(platformOwner, {
      delegatesEnabled: false,
      foundationEnabled: false,
      publicRegistrationEnabled: false,
      registrationEnabled: false,
      rostersEnabled: false,
      schedulePreferencesEnabled: false,
    }, "R4A staging QA complete"));

    if (created.clubId) {
      await bestEffort("archive-r4a-club", () => archiveFixtureClub(platformOwner, created.clubId));
    }
    await bestEffort("disable-r3-flags", () => setRefereeFlagsOff(platformOwner));
    await bestEffort("disable-r2-flags", () => setClubFlags(platformOwner, {
      competitionOrganizerEnabled: false,
      foundationEnabled: false,
      publicProfilesEnabled: false,
      selfServiceCreationEnabled: false,
      teamRelationshipsEnabled: false,
    }, "R4A staging QA complete"));
    await bestEffort("disable-r1-flags", () => setCompetitionFlags(platformOwner, {
      contextBindingEnabled: false,
      creationEnabled: false,
      foundationEnabled: false,
    }, "R4A staging QA complete"));
  }

  for (const [supabase, channel] of channels) {
    await bestEffort("remove-r4a-channel", () => supabase.removeChannel(channel));
  }
  for (const supabase of clients) {
    await bestEffort("r4a-sign-out", () => supabase.auth.signOut());
    await bestEffort("r4a-disconnect-realtime", () => supabase.realtime.disconnect());
  }
}

assert.equal(completed, true, "R4A staging story did not complete");
