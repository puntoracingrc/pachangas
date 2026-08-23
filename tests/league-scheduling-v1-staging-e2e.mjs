import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const env = {
  url: process.env.R4B_STAGING_URL,
  publishableKey: process.env.R4B_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.R4B_STAGING_SERVICE_ROLE_KEY,
  projectRef: process.env.R4B_STAGING_PROJECT_REF,
  confirmation: process.env.R4B_STAGING_CONFIRM,
  previewUrl: process.env.R4B_STAGING_PREVIEW_URL || null,
};
for (const [key, value] of Object.entries(env)) {
  if (key !== "previewUrl" && !value) throw new Error(`R4B_STAGING_${key.toUpperCase()} is required`);
}
const actualProjectRef = new URL(env.url).hostname.split(".")[0];
if (
  env.confirmation !== "R4B_STAGING_ONLY"
  || actualProjectRef !== env.projectRef
  || actualProjectRef === "qonbngfrnrqgmxbdfbea"
) throw new Error("R4B_STAGING_PRODUCTION_TARGET_FORBIDDEN");
if (env.previewUrl && /pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)) {
  throw new Error("R4B_PREVIEW_PRODUCTION_TARGET_FORBIDDEN");
}

const USERS = {
  platform: { id: "f1700000-0000-4000-8000-000000000001", email: "r1-platform-owner-20260821@pachangasiq.test" },
  ownerA: { id: "f1700000-0000-4000-8000-000000000002", email: "r1-owner-a-20260821@pachangasiq.test" },
  adminA: { id: "f1700000-0000-4000-8000-000000000003", email: "r1-admin-a-20260821@pachangasiq.test" },
  playerA: { id: "f1700000-0000-4000-8000-000000000004", email: "r1-player-a-20260821@pachangasiq.test" },
  ownerB: { id: "f1700000-0000-4000-8000-000000000005", email: "r1-owner-b-20260821@pachangasiq.test" },
  staffA: { id: "f1700000-0000-4000-8000-000000000006", email: "r1-staff-a-20260821@pachangasiq.test" },
  ownerC: { id: "f1700000-0000-4000-8000-000000000007", email: "r1-normal-20260821@pachangasiq.test" },
};
const TEAMS = [
  ["f1820000-0000-4000-8000-000000000001", "R4B Team A", USERS.ownerA, "f1710000-0000-4000-8000-000000000002"],
  ["f1820000-0000-4000-8000-000000000002", "R4B Team B", USERS.ownerB, "f1710000-0000-4000-8000-000000000005"],
  ["f1820000-0000-4000-8000-000000000003", "R4B Team C", USERS.ownerC, "f1710000-0000-4000-8000-000000000007"],
  ["f1820000-0000-4000-8000-000000000004", "R4B Team D", USERS.adminA, "f1710000-0000-4000-8000-000000000003"],
  ["f1820000-0000-4000-8000-000000000005", "R4B Team E", USERS.playerA, "f1710000-0000-4000-8000-000000000004"],
  ["f1820000-0000-4000-8000-000000000006", "R4B Team F", USERS.staffA, "f1710000-0000-4000-8000-000000000006"],
].map(([groupId, name, owner, profileId]) => ({ groupId, name, owner, profileId }));

const IDS = {
  clubFlags: "00000000-0000-0000-0000-00000000c101",
  competitionFlags: "00000000-0000-0000-0000-00000000c001",
  leagueFlags: "00000000-0000-0000-0000-00000000c4a1",
  scheduleFlags: "00000000-0000-0000-0000-00000000c4b1",
  refereeFlags: "00000000-0000-0000-0000-00000000a3f3",
};
const UNTOUCHED_TABLES = [
  "pachanga_individual_rating_evidence",
  "pachanga_player_rating_snapshots",
  "pachanga_match_participants",
  "pachanga_match_scorers",
  "pachanga_achievement_grants",
  "pachanga_reward_grants",
  "pachanga_team_cosmetic_inventory",
  "pachanga_provincial_ranking_entries",
  "pachanga_stripe_webhook_events",
];
const clients = [];
const channels = [];
const created = { clubId: null, competitionId: null, planId: null, publicationOperationId: null };

function client(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}
const fixtureAdmin = client(env.serviceRoleKey);
const password = `R4b-${randomUUID()}-Qa!`;
const metadata = (surface = "league-scheduling-staging") => ({
  clientVersion: "1.0.0+r4b-staging",
  installedMode: "standalone",
  serviceWorkerVersion: "1.0.0+r4b-staging",
  surface,
});

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}
async function signIn(account) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw result.error;
  assert.equal(result.data.user.id, account.id);
  clients.push(supabase);
  return supabase;
}
async function prepareIdentities() {
  for (const account of Object.values(USERS)) {
    const result = await fixtureAdmin.auth.admin.updateUserById(account.id, { password });
    if (result.error) throw result.error;
  }
}
async function command(supabase, name, { action, aggregateId, expectedRevision, operationId = randomUUID(), payload = {}, organizerKind, surface }) {
  const args = {
    aggregate_id: aggregateId,
    client_metadata: metadata(surface),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  };
  if (organizerKind) args.organizer_kind = organizerKind;
  return supabase.rpc(name, args);
}
async function commandOk(supabase, name, input) {
  const result = await command(supabase, name, input);
  if (result.error) throw new Error(`${name}:${input.action}@${input.expectedRevision} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  return result.data;
}
const foundation = (supabase, input, v2 = false) => commandOk(
  supabase,
  v2 ? "command_pachanga_competition_foundation_v2" : "command_pachanga_competition_foundation_v1",
  input,
);
const club = (supabase, input, platform = false) => commandOk(
  supabase,
  platform ? "command_pachanga_club_platform_v1" : "command_pachanga_club_foundation_v1",
  input,
);
const participation = (supabase, input) => commandOk(supabase, "command_pachanga_league_participation_v1", input);
const scheduling = (supabase, input) => commandOk(supabase, "command_pachanga_league_scheduling_v1", input);

function expectError(result, pattern, code) {
  assert.ok(result.error, `Expected error matching ${pattern}`);
  if (code) assert.equal(result.error.code, code);
  assert.match([result.error.message, result.error.details, result.error.hint].filter(Boolean).join(" "), pattern);
}
async function bestEffort(label, action) {
  try { await action(); } catch (error) { console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error); }
}
async function upsertMissing(table, rows, onConflict) {
  const result = await fixtureAdmin.from(table).upsert(rows, { ignoreDuplicates: true, onConflict });
  if (result.error) throw result.error;
}
async function ensureTeams() {
  const existing = await fixtureAdmin.from("pachanga_groups").select("id").in("id", TEAMS.map((team) => team.groupId));
  if (existing.error) throw existing.error;
  const present = new Set(existing.data.map(({ id }) => id));
  const missing = TEAMS.filter((team) => !present.has(team.groupId)).map((team, index) => ({
    id: team.groupId,
    name: team.name,
    owner_id: team.owner.id,
    payload: { matches: [], players: [], qaFixture: "R4B_STAGING" },
    team_code: `R4B-QA-${index + 1}`,
  }));
  if (missing.length) {
    const result = await fixtureAdmin.from("pachanga_groups").insert(missing);
    if (result.error) throw result.error;
  }
  await upsertMissing("pachanga_group_members", TEAMS.map((team) => ({
    display_name: `${team.name} Owner`, group_id: team.groupId, role: "owner", user_id: team.owner.id,
  })), "group_id,user_id");
  await upsertMissing("pachanga_player_profiles", TEAMS.map((team, index) => ({
    birth_date: `199${index}-0${index + 1}-10`,
    display_name: `${team.name} Owner`,
    id: team.profileId,
    source_group_id: team.groupId,
    user_id: team.owner.id,
  })), "user_id");
}
async function ensureRegular(platform, regular, account) {
  const access = await regular.rpc("get_my_pachanga_platform_access_v1");
  if (access.error || !access.data.active) return;
  await rpc(platform, "set_pachanga_platform_role_v1", {
    expected_revision: access.data.revision,
    next_active: false,
    next_role: access.data.role,
    operation_id: randomUUID(),
    reason: "R4B staging regular user",
    target_user_id: account.id,
  });
}

const clubSnapshot = (supabase, id) => rpc(supabase, "get_pachanga_club_foundation_snapshot_v1", { target_club_id: id });
const competitionSnapshot = (supabase, id) => rpc(supabase, "get_pachanga_competition_foundation_snapshot_v1", { target_competition_id: id });
const entrySnapshot = (supabase, id) => rpc(supabase, "get_pachanga_competition_entry_v1", { target_entry_id: id });
const rosterSnapshot = (supabase, id) => rpc(supabase, "get_pachanga_competition_roster_v1", { page_offset: 0, page_size: 50, target_roster_id: id });

async function setClubFlags(platform, next, reason) {
  const current = await rpc(platform, "get_pachanga_club_foundation_flags_v1");
  return club(platform, { action: "club_flags.set", aggregateId: IDS.clubFlags, expectedRevision: current.revision, payload: { ...next, reason } }, true);
}
async function setCompetitionFlags(platform, next, reason) {
  const current = await rpc(platform, "get_pachanga_platform_competition_foundation_v1", { page_offset: 0, page_size: 200 });
  return commandOk(platform, "command_pachanga_competition_platform_v1", {
    action: "foundation_flags.set",
    aggregateId: IDS.competitionFlags,
    expectedRevision: current.flags.revision,
    payload: { ...next, reason },
  });
}
async function setParticipationFlags(platform, next, reason) {
  const current = await rpc(platform, "get_pachanga_league_participation_flags_v1");
  const result = await platform.rpc("command_pachanga_league_participation_platform_v1", {
    aggregate_id: IDS.leagueFlags,
    client_metadata: metadata("r4b-r4a-flags"),
    command_payload: { ...next, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}
async function scheduleFlags(platform) {
  return (await rpc(platform, "get_pachanga_platform_league_scheduling_v1", { page_offset: 0, page_size: 50 })).flags;
}
async function setScheduleFlags(platform, next, reason) {
  const current = await scheduleFlags(platform);
  const result = await platform.rpc("command_pachanga_league_scheduling_platform_v1", {
    aggregate_id: IDS.scheduleFlags,
    client_metadata: metadata("r4b-flags"),
    command_payload: { ...next, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}
async function setRefereeFlagsOff(platform) {
  const current = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  const keys = ["assignmentsEnabled", "clubRelationshipsEnabled", "foundationEnabled", "marketplaceEnabled", "publicProfilesEnabled", "selfServiceEnabled"];
  if (keys.every((key) => !current[key])) return;
  const result = await platform.rpc("command_pachanga_referee_platform_admin_v1", {
    aggregate_id: IDS.refereeFlags,
    client_metadata: metadata("r4b-cleanup"),
    command_action: "referee_flags.set",
    command_payload: { ...Object.fromEntries(keys.map((key) => [key, false])), reason: "R4B staging cleanup" },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
}
async function counts() {
  return Object.fromEntries(await Promise.all(UNTOUCHED_TABLES.map(async (table) => {
    const result = await fixtureAdmin.from(table).select("*", { count: "exact", head: true });
    if (result.error) throw result.error;
    return [table, result.count ?? 0];
  })));
}
function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("R4B Realtime subscription timed out")), 30_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") { clearTimeout(timer); resolve(); }
      else if (["CHANNEL_ERROR", "TIMED_OUT", "CLOSED"].includes(status)) { clearTimeout(timer); reject(new Error(status)); }
    });
  });
}
function eventQueue() {
  const queued = [];
  let waiter;
  return {
    clear: () => { queued.length = 0; },
    push: (value) => { if (waiter) waiter(value); else queued.push(value); },
    next: () => queued.length ? Promise.resolve(queued.shift()) : new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiter = null; reject(new Error("R4B invalidation timed out")); }, 60_000);
      waiter = (value) => { clearTimeout(timer); waiter = null; resolve(value); };
    }),
  };
}
async function archiveClub(platform, clubId) {
  let snapshot = await clubSnapshot(platform, clubId);
  for (const grant of snapshot.entitlements.grants ?? []) {
    if (grant.status !== "active") continue;
    snapshot = await clubSnapshot(platform, clubId);
    await club(platform, {
      action: "club.entitlement.revoke",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: { entitlementId: grant.id, reason: "R4B staging cleanup" },
      surface: "r4b-cleanup",
    }, true);
  }
  snapshot = await clubSnapshot(platform, clubId);
  if (snapshot.club.operationalStatus !== "archived") {
    await club(platform, {
      action: "club.status.set",
      aggregateId: clubId,
      expectedRevision: snapshot.club.revision,
      payload: { reason: "R4B staging cleanup", status: "archived" },
      surface: "r4b-cleanup",
    }, true);
  }
}
async function verifyPreview(accessToken, competitionId, planId) {
  if (!env.previewUrl) return { checked: false };
  const origin = new URL(env.previewUrl);
  for (const path of [
    "/laboratorio-league-scheduling?scenario=published",
    `/competiciones/${competitionId}/gestion/calendario`,
    `/competiciones/${competitionId}/calendario`,
  ]) {
    const response = await fetch(new URL(path, origin), {
      cache: "no-store",
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    assert.equal(response.ok, true, `${path} did not load in Preview`);
    assert.doesNotMatch(await response.text(), /SUPABASE_SERVICE_ROLE_KEY|qonbngfrnrqgmxbdfbea/i);
  }
  const response = await fetch(new URL(`/api/competitions/scheduling/workbench/${planId}`, origin), {
    cache: "no-store",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  assert.equal(response.headers.get("cache-control")?.includes("no-store"), true);
  assert.equal(response.ok, true, await response.text());
  return { checked: true, origin: origin.origin };
}

let platform;
let ownerA;
let ownerADevice2;
let ownerB;
let ownerC;
let adminA;
let adminADevice2;
let playerA;
let staffA;
let completed = false;
let countsBefore;

try {
  await prepareIdentities();
  [platform, ownerA, ownerADevice2, ownerB, ownerC, adminA, adminADevice2, playerA, staffA] = await Promise.all([
    signIn(USERS.platform),
    signIn(USERS.ownerA),
    signIn(USERS.ownerA),
    signIn(USERS.ownerB),
    signIn(USERS.ownerC),
    signIn(USERS.adminA),
    signIn(USERS.adminA),
    signIn(USERS.playerA),
    signIn(USERS.staffA),
  ]);
  const teamClients = [ownerA, ownerB, ownerC, adminA, playerA, staffA];
  for (let index = 0; index < TEAMS.length; index += 1) {
    await ensureRegular(platform, teamClients[index], TEAMS[index].owner);
  }
  await ensureTeams();
  countsBefore = await counts();
  const initialFlags = await scheduleFlags(platform);
  for (const key of [
    "foundationEnabled",
    "generationEnabled",
    "editingEnabled",
    "publicationEnabled",
    "publicCalendarEnabled",
    "canonicalFixtureCreationEnabled",
  ]) assert.equal(initialFlags[key], false, `${key} must begin OFF`);

  await setClubFlags(platform, {
    competitionOrganizerEnabled: true,
    foundationEnabled: true,
    publicProfilesEnabled: false,
    selfServiceCreationEnabled: true,
    teamRelationshipsEnabled: false,
  }, "R4B staging Club window");
  await setCompetitionFlags(platform, {
    contextBindingEnabled: false,
    creationEnabled: true,
    foundationEnabled: true,
  }, "R4B staging Competition window");
  await setParticipationFlags(platform, {
    delegatesEnabled: true,
    foundationEnabled: true,
    publicRegistrationEnabled: true,
    registrationEnabled: true,
    rostersEnabled: true,
    schedulePreferencesEnabled: true,
  }, "R4B staging R4A dependency window");

  const tag = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  created.clubId = randomUUID();
  const clubCreated = await club(ownerA, {
    action: "club.create",
    aggregateId: created.clubId,
    expectedRevision: 0,
    payload: {
      clubType: "FOOTBALL_CLUB",
      countryCode: "ES",
      municipality: "Barcelona",
      name: `R4B Organizer ${tag}`,
      province: "Barcelona",
      reason: "R4B staging organizer",
      slug: `r4b-organizer-${tag}`,
      visibility: "private",
    },
  });
  const clubSubmitted = await club(ownerA, {
    action: "club.review.submit",
    aggregateId: created.clubId,
    expectedRevision: clubCreated.snapshot.club.revision,
    payload: { reason: "R4B staging Club review" },
  });
  await club(platform, {
    action: "club.status.set",
    aggregateId: created.clubId,
    expectedRevision: clubSubmitted.snapshot.club.revision,
    payload: { reason: "R4B staging Club activation", status: "active" },
  }, true);
  let clubState = await clubSnapshot(ownerA, created.clubId);
  const managerInvitation = await club(ownerA, {
    action: "membership.invite",
    aggregateId: created.clubId,
    expectedRevision: clubState.club.revision,
    payload: {
      reason: "R4B Competition Director",
      role: "club_competition_manager",
      targetKind: "registered_user",
      targetUserId: USERS.staffA.id,
    },
  });
  await club(staffA, {
    action: "membership.accept",
    aggregateId: managerInvitation.invitationId,
    expectedRevision: 1,
    payload: { reason: "R4B manager accepts", token: managerInvitation.oneTimeToken },
  });
  clubState = await clubSnapshot(platform, created.clubId);
  const createGrant = await club(platform, {
    action: "club.entitlement.grant",
    aggregateId: created.clubId,
    expectedRevision: clubState.club.revision,
    payload: { capability: "competition_create", reason: "R4B creation", source: "platform_grant" },
  }, true);
  const manageGrant = await club(platform, {
    action: "club.entitlement.grant",
    aggregateId: created.clubId,
    expectedRevision: createGrant.snapshot.club.revision,
    payload: { capability: "competition_manage", reason: "R4B scheduling", source: "platform_grant" },
  }, true);

  const createCompetitionOperation = randomUUID();
  const competitionInput = {
    action: "competition.create",
    aggregateId: created.clubId,
    expectedRevision: manageGrant.snapshot.entitlements.organizerRevision,
    operationId: createCompetitionOperation,
    organizerKind: "CLUB",
    payload: {
      competitionType: "LEAGUE",
      editionName: "Edition 2027",
      endsAt: "2027-12-31",
      name: `R4B QA League ${tag}`,
      reason: "R4B staging canonical League",
      ruleSetName: "R4B explicit scheduling rules",
      seasonLabel: "2027",
      slug: `r4b-qa-league-${tag}`,
      startsAt: "2027-01-01",
      visibility: "public",
    },
  };
  const competitionCreated = await foundation(staffA, competitionInput, true);
  assert.deepEqual(await foundation(staffA, competitionInput, true), competitionCreated);
  created.competitionId = competitionCreated.snapshot.competition.id;
  const edition = competitionCreated.snapshot.editions[0];
  const ruleSet = competitionCreated.snapshot.ruleSets[0];

  let competitionState = await competitionSnapshot(staffA, created.competitionId);
  const director = await foundation(staffA, {
    action: "staff.grant",
    aggregateId: created.competitionId,
    expectedRevision: competitionState.competition.revision,
    payload: { staffRole: "competition_director", userId: USERS.staffA.id },
  });
  await foundation(staffA, {
    action: "staff.grant",
    aggregateId: created.competitionId,
    expectedRevision: director.confirmedRevision,
    payload: { staffRole: "competition_schedule_manager", userId: USERS.adminA.id },
  });

  const ruleCreated = await foundation(staffA, {
    action: "rule_revision.create",
    aggregateId: ruleSet.id,
    expectedRevision: ruleSet.revision,
    payload: {
      effectiveFrom: "2027-01-01T00:00:00Z",
      effectiveScope: "future_only",
      reason: "R4B explicit isolated QA revision",
      schemaVersion: "competition_rules.v1",
      ruleDocument: {
        discipline: {},
        format: { modality: "futbol7" },
        futureCapabilities: {},
        governance: {},
        operations: {
          hardAvailabilityPolicy: { mode: "required" },
          schedulePreferencePolicy: { mode: "preferred" },
          schedulePolicy: {
            format: "ROUND_ROBIN",
            legs: 1,
            matchDurationMinutes: 70,
            requiredBufferMinutes: 10,
            minimumRestMinutes: 0,
            homeAwayPolicy: "BALANCED",
            venueRequired: false,
            maximumHomeAwayStreak: 3,
            hardHomeAwayStreak: false,
            windowStartsAt: "2027-01-15T00:00:00Z",
            windowEndsAt: "2027-11-30T23:59:59Z",
            rosterStatuses: ["approved", "locked"],
            softPreferenceWeights: { day: 60, time: 30, homeAway: 10 },
          },
        },
        publication: {},
        registration: {
          identityRequirements: { credentialRequired: false },
          kitPolicy: { jerseyRequired: false },
          registrationPolicy: { teamLimits: { maximum: 8, minimum: 2 } },
          rosterPolicy: {
            closeRequiresApprovedRosters: true,
            maximumSize: 4,
            minimumSize: 1,
            multiTeamPolicy: "FORBIDDEN_SAME_EDITION_CATEGORY",
          },
        },
        results: { scoringPolicy: {}, tieBreakCriteria: [] },
        structure: { stageGraph: { edges: [], nodes: [{ id: "league-stage", root: true }] } },
      },
    },
  });
  const ruleRevision = ruleCreated.snapshot.ruleSets.find(({ id }) => id === ruleSet.id).revisions[0];
  const validatedRuleReceipt = await foundation(staffA, {
    action: "rule_revision.validate",
    aggregateId: ruleRevision.id,
    expectedRevision: ruleRevision.revision,
  });
  const validatedRule = validatedRuleReceipt.snapshot.ruleSets
    .find(({ id }) => id === ruleSet.id).revisions.find(({ id }) => id === ruleRevision.id);
  const publishedRuleReceipt = await foundation(staffA, {
    action: "rule_revision.publish",
    aggregateId: ruleSet.id,
    expectedRevision: ruleCreated.confirmedRevision,
    payload: { ruleRevisionId: ruleRevision.id },
  });
  competitionState = await competitionSnapshot(staffA, created.competitionId);
  const assignedRule = await foundation(staffA, {
    action: "edition.assign_rule_revision",
    aggregateId: edition.id,
    expectedRevision: competitionState.editions.find(({ id }) => id === edition.id).revision,
    payload: { ruleRevisionId: ruleRevision.id },
  });
  const publishedRule = publishedRuleReceipt.snapshot.ruleSets
    .find(({ id }) => id === ruleSet.id).revisions.find(({ id }) => id === ruleRevision.id);
  assert.ok(publishedRule.revision >= validatedRule.revision);
  await foundation(staffA, {
    action: "rule_revision.freeze",
    aggregateId: ruleRevision.id,
    expectedRevision: publishedRule.revision,
  });

  const stageReceipt = await foundation(staffA, {
    action: "stage.create",
    aggregateId: edition.id,
    expectedRevision: assignedRule.confirmedRevision,
    payload: { name: "League Stage", optional: false, ruleRevisionId: ruleRevision.id, stageOrder: 0, stageType: "LEAGUE_STAGE" },
  });
  const stage = stageReceipt.snapshot.stages.find(({ name }) => name === "League Stage");
  const divisionReceipt = await foundation(staffA, {
    action: "division.create",
    aggregateId: stage.id,
    expectedRevision: stage.revision,
    payload: { levelLabel: "Open", name: "Division 1", order: 0 },
  });
  const division = divisionReceipt.snapshot.stages.find(({ id }) => id === stage.id).divisions.find(({ name }) => name === "Division 1");
  const groupReceipt = await foundation(staffA, {
    action: "group.create",
    aggregateId: stage.id,
    expectedRevision: divisionReceipt.confirmedRevision,
    payload: { divisionId: division.id, name: "Group A", order: 0 },
  });
  const competitionGroup = groupReceipt.snapshot.stages.find(({ id }) => id === stage.id).groups.find(({ name }) => name === "Group A");
  competitionState = await competitionSnapshot(staffA, created.competitionId);
  const categoryReceipt = await participation(staffA, {
    action: "category.create",
    aggregateId: edition.id,
    expectedRevision: competitionState.editions.find(({ id }) => id === edition.id).revision,
    payload: {
      ageReferenceDate: "2027-01-01",
      eligibilityPolicy: { age: "adult" },
      levelLabel: "Open",
      minimumAge: 18,
      name: "Open",
      reason: "R4B open category",
      ruleRevisionId: ruleRevision.id,
      slug: `open-${tag}`,
      sportFormat: "FOOTBALL_7",
      visibility: "public",
    },
  });
  const category = categoryReceipt.snapshot;
  const activatedCategory = await participation(staffA, {
    action: "category.activate",
    aggregateId: category.id,
    expectedRevision: category.revision,
    payload: { reason: "Activate R4B Open" },
  });
  competitionState = await competitionSnapshot(staffA, created.competitionId);
  await participation(staffA, {
    action: "registration.open",
    aggregateId: edition.id,
    expectedRevision: competitionState.editions.find(({ id }) => id === edition.id).revision,
    payload: {
      closesAt: "2027-11-30T23:00:00Z",
      reason: "Open R4B registration",
      registrationMode: "PUBLIC_APPROVAL",
      ruleRevisionId: ruleRevision.id,
    },
  });

  const entries = [];
  for (let index = 0; index < TEAMS.length; index += 1) {
    const team = TEAMS[index];
    const teamClient = teamClients[index];
    const submitted = await participation(teamClient, {
      action: "entry.submit",
      aggregateId: category.id,
      expectedRevision: activatedCategory.snapshot.revision,
      payload: { reason: `${team.name} application`, teamId: team.groupId },
    });
    const accepted = await participation(staffA, {
      action: "entry.accept",
      aggregateId: submitted.snapshot.entry.id,
      expectedRevision: submitted.snapshot.entry.revision,
      payload: { reason: `Accept ${team.name}` },
    });
    const entryId = accepted.snapshot.entry.id;
    const rosterId = accepted.snapshot.roster.id;
    let roster = await rosterSnapshot(teamClient, rosterId);
    await participation(teamClient, {
      action: "roster.member.add",
      aggregateId: rosterId,
      expectedRevision: roster.roster.revision,
      payload: { playerProfileId: team.profileId, reason: `${team.name} roster` },
    });
    roster = await rosterSnapshot(teamClient, rosterId);
    await participation(teamClient, {
      action: "roster.submit",
      aggregateId: rosterId,
      expectedRevision: roster.roster.revision,
      payload: { reason: `Submit ${team.name} roster` },
    });
    roster = await rosterSnapshot(staffA, rosterId);
    const approved = await participation(staffA, {
      action: "roster.approve",
      aggregateId: rosterId,
      expectedRevision: roster.roster.revision,
      payload: { reason: `Approve ${team.name} roster` },
    });
    const locked = await participation(staffA, {
      action: "roster.lock",
      aggregateId: rosterId,
      expectedRevision: approved.confirmedRevision,
      payload: { reason: `Lock ${team.name} roster` },
    });
    assert.equal(locked.snapshot.roster.status, "locked");
    entries.push({ entryId, rosterId, team, teamClient });
  }

  let teamAEntry = await entrySnapshot(ownerA, entries[0].entryId);
  await participation(ownerA, {
    action: "availability.set",
    aggregateId: teamAEntry.entry.id,
    expectedRevision: teamAEntry.entry.revision,
    payload: {
      endLocalTime: "23:00",
      reason: "R4B Team A unavailable Monday",
      startLocalTime: "19:00",
      timezone: "Europe/Madrid",
      validFromDate: "2027-01-01",
      validUntilDate: "2027-12-31",
      weekday: 1,
    },
  });
  teamAEntry = await entrySnapshot(ownerA, entries[0].entryId);
  await participation(ownerA, {
    action: "preference.set",
    aggregateId: teamAEntry.entry.id,
    expectedRevision: teamAEntry.entry.revision,
    payload: {
      endLocalTime: "22:00",
      preferredArea: "Barcelona",
      reason: "R4B Team A prefers Saturday",
      startLocalTime: "16:00",
      timezone: "Europe/Madrid",
      weekday: 6,
      weight: 80,
    },
  });
  for (const entry of entries) {
    const current = await entrySnapshot(staffA, entry.entryId);
    const membership = await participation(staffA, {
      action: "stage_membership.assign",
      aggregateId: entry.entryId,
      expectedRevision: current.entry.revision,
      payload: {
        divisionId: division.id,
        groupId: competitionGroup.id,
        reason: `Assign ${entry.team.name} to Group A`,
        stageId: stage.id,
      },
    });
    assert.equal(membership.snapshot.stageMembership.groupId, competitionGroup.id);
  }
  competitionState = await competitionSnapshot(staffA, created.competitionId);
  const closed = await participation(staffA, {
    action: "registration.close",
    aggregateId: edition.id,
    expectedRevision: competitionState.editions.find(({ id }) => id === edition.id).revision,
    payload: { reason: "Close R4B registration with six locked rosters" },
  });
  assert.equal(closed.snapshot.status, "registration_closed");

  await setScheduleFlags(platform, {
    canonicalFixtureCreationEnabled: true,
    editingEnabled: true,
    foundationEnabled: true,
    generationEnabled: true,
    publicCalendarEnabled: true,
    publicationEnabled: true,
  }, "R4B authenticated staging window");

  competitionState = await competitionSnapshot(staffA, created.competitionId);
  const currentStage = competitionState.stages.find(({ id }) => id === stage.id);
  const plan = await scheduling(adminA, {
    action: "schedule_plan.create",
    aggregateId: stage.id,
    expectedRevision: currentStage.revision,
    payload: {
      categoryId: category.id,
      divisionId: division.id,
      groupId: competitionGroup.id,
      legs: 1,
      reason: "R4B staging schedule plan",
      ruleRevisionId: ruleRevision.id,
    },
  });
  created.planId = plan.snapshot.plan.id;
  assert.equal(plan.snapshot.plan.entryCount, 6);
  assert.equal(plan.snapshot.plan.engineVersion, "league-round-robin-v1");

  const slotOperation = randomUUID();
  const slotInput = {
    action: "schedule_slot.bulk_create",
    aggregateId: created.planId,
    expectedRevision: plan.confirmedRevision,
    operationId: slotOperation,
    payload: {
      durationMinutes: 90,
      endDate: "2027-02-21",
      localTime: "20:00",
      resourceKey: "r4b-pitch-1",
      startDate: "2027-02-01",
      timezone: "Europe/Madrid",
      venueLabel: "Pista R4B QA",
      weekdays: [1, 2, 3, 4, 5, 6, 7],
    },
  };
  const slots = await scheduling(adminA, slotInput);
  assert.equal(slots.snapshot.affectedSlotIds.length, 21);
  assert.deepEqual(await scheduling(adminA, slotInput), slots);

  const generationOperation = randomUUID();
  const generationResults = await Promise.all([
    command(adminA, "command_pachanga_league_scheduling_v1", {
      action: "schedule.generate",
      aggregateId: created.planId,
      expectedRevision: slots.confirmedRevision,
      operationId: generationOperation,
      payload: { seed: "r4b-staging-reproducible" },
    }),
    command(adminADevice2, "command_pachanga_league_scheduling_v1", {
      action: "schedule.generate",
      aggregateId: created.planId,
      expectedRevision: slots.confirmedRevision,
      payload: { seed: "r4b-staging-concurrent" },
    }),
  ]);
  assert.equal(generationResults.filter(({ error }) => !error).length, 1);
  assert.equal(generationResults.filter(({ error }) => error).length, 1);
  expectError(generationResults.find(({ error }) => error), /STALE_REVISION/, "PT409");
  const generated = generationResults.find(({ error }) => !error).data;
  const generationReplay = await scheduling(adminA, {
    action: "schedule.generate",
    aggregateId: created.planId,
    expectedRevision: slots.confirmedRevision,
    operationId: generationOperation,
    payload: { seed: "r4b-staging-reproducible" },
  });
  assert.deepEqual(generationReplay, generated);
  assert.deepEqual(generated.snapshot.counts, {
    byes: 0,
    items: 15,
    published: 0,
    rounds: 5,
    unassigned: 0,
  });

  let workbench = await rpc(adminA, "get_pachanga_league_schedule_workbench_v1", {
    page_offset: 0,
    page_size: 200,
    target_schedule_plan_id: created.planId,
  });
  assert.equal(workbench.items.length, 15);
  assert.equal(workbench.rounds.length, 5);
  assert.equal(workbench.conflicts.filter(({ severity, status }) => severity === "hard" && status === "active").length, 0);
  assert.ok(Number(workbench.quality.softScore) >= 0);
  assert.ok(workbench.quality.explanation);
  const renamed = await scheduling(adminA, {
    action: "round.rename",
    aggregateId: created.planId,
    expectedRevision: generated.confirmedRevision,
    payload: { displayName: "Jornada inaugural", roundId: workbench.rounds[0].id },
  });
  assert.equal(renamed.snapshot.revision.kind, "round_rename");
  const validatedSchedule = await scheduling(adminA, {
    action: "schedule.validate",
    aggregateId: created.planId,
    expectedRevision: renamed.confirmedRevision,
    payload: { reason: "R4B full staging validation" },
  });
  assert.equal(validatedSchedule.snapshot.validation.status, "VALID");
  assert.equal(validatedSchedule.snapshot.validation.hardViolations, 0);

  const outsiderRead = await ownerB.rpc("get_pachanga_league_schedule_workbench_v1", {
    page_offset: 0,
    page_size: 200,
    target_schedule_plan_id: created.planId,
  });
  expectError(outsiderRead, /COMPETITION_SCHEDULE_MANAGER_REQUIRED/, "42501");
  const directWrite = await ownerA.from("pachanga_competition_schedule_slots").insert({ id: randomUUID() });
  assert.ok(directWrite.error);

  const queue = eventQueue();
  const channel = ownerADevice2.channel(`r4b-staging-${randomUUID()}`).on("postgres_changes", {
    event: "INSERT",
    filter: `target_group_id=eq.${TEAMS[0].groupId}`,
    schema: "public",
    table: "pachanga_competition_invalidations",
  }, (payload) => queue.push(payload));
  channels.push([ownerADevice2, channel]);
  await waitForSubscription(channel);
  queue.clear();
  const teamInvalidation = queue.next();

  created.publicationOperationId = randomUUID();
  const publicationInput = {
    action: "schedule.publish",
    aggregateId: created.planId,
    expectedRevision: validatedSchedule.confirmedRevision,
    operationId: created.publicationOperationId,
    payload: { reason: "Publish R4B canonical staging fixtures" },
  };
  const published = await scheduling(adminA, publicationInput);
  assert.deepEqual(await scheduling(adminADevice2, publicationInput), published);
  assert.equal(published.snapshot.publication.canonicalMatchCount, 15);
  assert.equal(published.snapshot.publication.contextCount, 15);
  assert.equal(published.snapshot.publication.notificationCount, 6);
  assert.equal((await teamInvalidation).new.target_group_id, TEAMS[0].groupId);

  const teamCalendar = await rpc(ownerADevice2, "get_pachanga_my_league_schedule_v1", {
    target_entry_id: entries[0].entryId,
  });
  assert.equal(teamCalendar.fixtures.length, 5);
  const anonymous = client();
  const publicCalendar = await rpc(anonymous, "get_pachanga_public_league_calendar_v1", {
    target_competition_id: created.competitionId,
    target_round_from: 1,
    target_round_limit: 20,
  });
  assert.equal(publicCalendar.rounds.length, 5);
  assert.equal(publicCalendar.rounds.reduce((total, round) => total + round.fixtures.length, 0), 15);
  const roundDetail = await rpc(anonymous, "get_pachanga_league_round_detail_v1", {
    target_round_id: publicCalendar.rounds[0].id,
  });
  assert.equal(roundDetail.fixtures.length, 3);

  for (const team of TEAMS) {
    const notifications = await fixtureAdmin.from("pachanga_user_notifications")
      .select("id", { count: "exact", head: true })
      .eq("dedupe_key", `league-schedule:${created.publicationOperationId}:${team.owner.id}`);
    if (notifications.error) throw notifications.error;
    assert.equal(notifications.count, 1);
  }
  const forbiddenMutation = await command(adminA, "command_pachanga_league_scheduling_v1", {
    action: "schedule.regenerate",
    aggregateId: created.planId,
    expectedRevision: published.confirmedRevision,
    payload: { seed: "forbidden-after-publish" },
  });
  expectError(forbiddenMutation, /POST_PUBLICATION_CHANGE_REQUIRES_R4C/, "0A000");
  const unauthorizedArchive = await adminA.rpc("archive_pachanga_league_schedule_qa_v1", {
    client_metadata: metadata("r4b-unauthorized-cleanup"),
    expected_revision: published.confirmedRevision,
    operation_id: randomUUID(),
    reason: "R4B_STAGING_QA_ARCHIVE: unauthorized",
    target_schedule_plan_id: created.planId,
  });
  assert.ok(unauthorizedArchive.error);

  const session = await adminA.auth.getSession();
  const preview = await verifyPreview(session.data.session.access_token, created.competitionId, created.planId);
  const archiveOperation = randomUUID();
  const archiveArgs = {
    client_metadata: metadata("r4b-cleanup"),
    expected_revision: published.confirmedRevision,
    operation_id: archiveOperation,
    reason: "R4B_STAGING_QA_ARCHIVE: authenticated end-to-end cleanup",
    target_schedule_plan_id: created.planId,
  };
  const archived = await rpc(fixtureAdmin, "archive_pachanga_league_schedule_qa_v1", archiveArgs);
  assert.deepEqual(await rpc(fixtureAdmin, "archive_pachanga_league_schedule_qa_v1", archiveArgs), archived);
  assert.deepEqual(
    {
      status: archived.snapshot.status,
      contexts: archived.snapshot.retiredContexts,
      bindings: archived.snapshot.retiredBindings,
      matches: archived.snapshot.retiredCanonicalMatches,
      rounds: archived.snapshot.cancelledRounds,
    },
    { status: "cancelled", contexts: 15, bindings: 15, matches: 15, rounds: 5 },
  );

  const active = await Promise.all([
    fixtureAdmin.from("pachanga_competition_schedule_plans").select("id", { count: "exact", head: true }).eq("id", created.planId).neq("status", "cancelled"),
    fixtureAdmin.from("pachanga_competition_schedule_revisions").select("id", { count: "exact", head: true }).eq("schedule_plan_id", created.planId).in("status", ["generated", "validated", "published"]),
    fixtureAdmin.from("pachanga_competition_schedule_slots").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).neq("status", "retired"),
    fixtureAdmin.from("pachanga_competition_rounds").select("id", { count: "exact", head: true }).eq("schedule_revision_id", published.snapshot.revision.id).neq("status", "cancelled"),
    fixtureAdmin.from("pachanga_competition_match_contexts").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).eq("source_kind", "COMPETITION_GENERATED").neq("status", "retired"),
  ]);
  for (const result of active) {
    if (result.error) throw result.error;
    assert.equal(result.count, 0);
  }
  assert.deepEqual(await counts(), countsBefore, "R4B modified Rating, results, rewards, cosmetics, ranking or billing");
  workbench = await rpc(adminA, "get_pachanga_league_schedule_workbench_v1", {
    page_offset: 0,
    page_size: 200,
    target_schedule_plan_id: created.planId,
  });
  assert.equal(workbench.plan.status, "cancelled");
  completed = true;
  console.log(JSON.stringify({
    canonicalMatches: 15,
    cleanup: "service_authority_archived_with_history",
    competitionId: created.competitionId,
    concurrency: "one_generation_winner_one_stale",
    contexts: 15,
    entries: 6,
    notifications: 6,
    planId: created.planId,
    preview,
    projectRef: actualProjectRef,
    realtime: "invalidation_then_canonical_refetch",
    rounds: 5,
    status: "PASS",
  }));
} finally {
  if (platform) {
    await bestEffort("archive-active-schedule", async () => {
      if (!created.planId) return;
      const selected = await fixtureAdmin.from("pachanga_competition_schedule_plans")
        .select("id,status,revision").eq("id", created.planId).maybeSingle();
      if (selected.error || !selected.data || selected.data.status === "cancelled") return;
      await rpc(fixtureAdmin, "archive_pachanga_league_schedule_qa_v1", {
        client_metadata: metadata("r4b-failure-cleanup"),
        expected_revision: selected.data.revision,
        operation_id: randomUUID(),
        reason: "R4B_STAGING_QA_ARCHIVE: failure cleanup",
        target_schedule_plan_id: created.planId,
      });
    });
    await bestEffort("cancel-competition", async () => {
      if (!created.competitionId || !staffA) return;
      const snapshot = await competitionSnapshot(staffA, created.competitionId);
      if (snapshot.competition.status === "cancelled") return;
      await foundation(staffA, {
        action: "competition.cancel",
        aggregateId: created.competitionId,
        expectedRevision: snapshot.competition.revision,
        payload: { reason: "R4B staging cleanup" },
      });
    });
    await bestEffort("disable-r4b", () => setScheduleFlags(platform, {
      canonicalFixtureCreationEnabled: false,
      editingEnabled: false,
      foundationEnabled: false,
      generationEnabled: false,
      publicCalendarEnabled: false,
      publicationEnabled: false,
    }, "R4B staging complete"));
    await bestEffort("disable-r4a", () => setParticipationFlags(platform, {
      delegatesEnabled: false,
      foundationEnabled: false,
      publicRegistrationEnabled: false,
      registrationEnabled: false,
      rostersEnabled: false,
      schedulePreferencesEnabled: false,
    }, "R4B staging complete"));
    if (created.clubId) await bestEffort("archive-club", () => archiveClub(platform, created.clubId));
    await bestEffort("disable-r3", () => setRefereeFlagsOff(platform));
    await bestEffort("disable-r2", () => setClubFlags(platform, {
      competitionOrganizerEnabled: false,
      foundationEnabled: false,
      publicProfilesEnabled: false,
      selfServiceCreationEnabled: false,
      teamRelationshipsEnabled: false,
    }, "R4B staging complete"));
    await bestEffort("disable-r1", () => setCompetitionFlags(platform, {
      contextBindingEnabled: false,
      creationEnabled: false,
      foundationEnabled: false,
    }, "R4B staging complete"));
  }
  for (const [supabase, channel] of channels) await bestEffort("remove-channel", () => supabase.removeChannel(channel));
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", () => supabase.realtime.disconnect());
  }
}

assert.equal(completed, true, "R4B staging story did not complete");
