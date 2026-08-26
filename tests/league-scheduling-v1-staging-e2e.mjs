import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";
import {
  cleanupCompetitionConfigurationStaging,
  createCompetitionConfigurationStagingState,
  runCompetitionConfigurationAfterRegistration,
  runCompetitionConfigurationBeforeRegistration,
} from "./competition-configuration-center-v1-staging-extension.mjs";
import { runLeagueMatchOperationsStagingExtension } from "./league-match-operations-v1-staging-extension.mjs";
import { runLeagueOperationalExceptionsStagingExtension } from "./league-operational-exceptions-v1-staging-extension.mjs";
import { runRefereeAssignmentsPrivateBetaStagingExtension } from "./referee-assignments-private-beta-v1-staging-extension.mjs";

const R4C_EXTENSION = process.env.R4C_STAGING_EXTENSION === "1";
const R4D_EXTENSION = process.env.R4D_STAGING_EXTENSION === "1";
const REFEREE_ASSIGNMENTS_EXTENSION = process.env.REFEREE_ASSIGNMENTS_STAGING_EXTENSION === "1";
const PRIVATE_BETA_EXTENSION = process.env.LEAGUE_PRIVATE_BETA_STAGING_EXTENSION === "1";
const CONFIGURATION_EXTENSION = process.env.COMPETITION_CONFIGURATION_STAGING_EXTENSION === "1";
const MATCH_OPERATIONS_EXTENSION = R4C_EXTENSION || R4D_EXTENSION;

const env = {
  url: process.env.R4B_STAGING_URL,
  publishableKey: process.env.R4B_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.R4B_STAGING_SERVICE_ROLE_KEY,
  projectRef: process.env.R4B_STAGING_PROJECT_REF,
  confirmation: process.env.R4B_STAGING_CONFIRM,
  previewUrl: process.env.R4B_STAGING_PREVIEW_URL || null,
  protectionBypass: process.env.R4B_STAGING_PROTECTION_BYPASS || null,
};
for (const [key, value] of Object.entries(env)) {
  if (!["previewUrl", "protectionBypass"].includes(key) && !value) {
    throw new Error(`R4B_STAGING_${key.toUpperCase()} is required`);
  }
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
].map(([groupId, name, owner, profileId], teamIndex) => ({
  groupId,
  name,
  owner,
  profileId,
  supplementalMembers: Array.from({ length: 4 }, (_, memberIndex) => {
    const stableSuffix = String((teamIndex + 1) * 10 + memberIndex + 1).padStart(12, "0");
    return {
      email: `r4b-team-${teamIndex + 1}-member-${memberIndex + 2}@pachangasiq.test`,
      profileId: `f1740000-0000-4000-8000-${stableSuffix}`,
      userId: `f1730000-0000-4000-8000-${stableSuffix}`,
    };
  }),
}));

const IDS = {
  betaFlags: "00000000-0000-0000-0000-00000000b201",
  clubFlags: "00000000-0000-0000-0000-00000000c101",
  configurationFlags: "00000000-0000-0000-0000-00000000c5a1",
  competitionFlags: "00000000-0000-0000-0000-00000000c001",
  leagueFlags: "00000000-0000-0000-0000-00000000c4a1",
  matchOperationsFlags: "00000000-0000-0000-0000-00000000c4c1",
  operationalExceptionsFlags: "00000000-0000-0000-0000-00000000c4d1",
  scheduleFlags: "00000000-0000-0000-0000-00000000c4b1",
  refereeFlags: "00000000-0000-0000-0000-00000000a3f3",
};
const MATCH_OPERATIONS_FLAG_KEYS = [
  "foundationEnabled", "squadsEnabled", "attendanceEnabled",
  "sportingResultsEnabled", "resultConfirmationEnabled",
  "officialResultsEnabled", "standingsEnabled", "publicStandingsEnabled",
];
const OPERATIONAL_EXCEPTIONS_FLAG_KEYS = [
  "foundationEnabled", "postponementsEnabled", "reschedulingEnabled",
  "venueChangesEnabled", "lateArrivalEnabled", "noShowEnabled",
  "matchSuspensionsEnabled", "administrativeDecisionsEnabled",
  "publicExceptionStatusEnabled",
];
const REFEREE_FLAG_KEYS = [
  "assignmentsEnabled",
  "clubRelationshipsEnabled",
  "foundationEnabled",
  "marketplaceEnabled",
  "publicProfilesEnabled",
  "selfServiceEnabled",
];
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
].filter((table) => !R4C_EXTENSION || table !== "pachanga_match_participants");
const clients = [];
const channels = [];
const created = {
  betaBundleId: null,
  clubId: null,
  competitionId: null,
  expiredTeamBundleId: null,
  ephemeralUserIds: [],
  planId: null,
  publicationOperationId: null,
  supplementalUserIds: [],
  teamBundleId: null,
  wizardId: null,
};
const configurationStagingState = createCompetitionConfigurationStagingState();

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
async function signIn(account, role) {
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const supabase = client();
    const result = await supabase.auth.signInWithPassword({ email: account.email, password });
    if (!result.error) {
      assert.equal(result.data.user.id, account.id);
      clients.push(supabase);
      return supabase;
    }
    if (result.error.code !== "invalid_credentials" || attempt === 5) {
      throw new Error(`R4B_STAGING_SIGN_IN_FAILED:${role}:${result.error.code ?? result.error.status}`, {
        cause: result.error,
      });
    }
    await new Promise((resolve) => setTimeout(resolve, attempt * 300));
  }
  throw new Error(`R4B_STAGING_SIGN_IN_FAILED:${role}:retry_exhausted`);
}
async function prepareIdentities() {
  for (const account of Object.values(USERS)) {
    const existing = await fixtureAdmin.auth.admin.getUserById(account.id);
    if (existing.error && existing.error.status !== 404 && existing.error.code !== "user_not_found") {
      throw existing.error;
    }
    const result = existing.error
      ? await fixtureAdmin.auth.admin.createUser({
        email: account.email,
        email_confirm: true,
        id: account.id,
        password,
        user_metadata: { qaFixture: "R4B_STAGING_CORE" },
      })
      : await fixtureAdmin.auth.admin.updateUserById(account.id, {
        password,
        user_metadata: { qaFixture: "R4B_STAGING_CORE" },
      });
    if (result.error) throw result.error;
  }

  const access = await fixtureAdmin.rpc("get_pachanga_platform_access_service_v1", {
    target_user_id: USERS.platform.id,
  });
  if (access.error) throw access.error;
  if (!access.data) {
    const bootstrap = await fixtureAdmin.rpc("bootstrap_pachanga_platform_owner_v1", {
      operation_id: randomUUID(),
      reason: "Wave 4 isolated staging platform fixture",
      target_user_id: USERS.platform.id,
    });
    if (bootstrap.error) throw bootstrap.error;
    assert.equal(bootstrap.data.role, "platform_owner");
  }
}

function betaCommand(supabase, name, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
  surface = "league-private-beta-staging",
}) {
  return supabase.rpc(name, {
    aggregate_id: aggregateId,
    client_metadata: metadata(surface),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function betaCommandOk(supabase, name, input) {
  const result = await betaCommand(supabase, name, input);
  if (result.error) {
    throw new Error(
      `${name}:${input.action}@${input.expectedRevision} [${result.error.code}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
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

async function confirmClubPublication(supabase, clubId, expectedRevision) {
  return rpc(supabase, "command_pachanga_publication_consent_v1", {
    client_metadata: metadata("league-scheduling-staging"),
    confirmations: { informationCorrect: true, representationAuthorized: true },
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
    subject_id: clubId,
    subject_kind: "CLUB",
  });
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
  const diagnostic = [result.error.code, result.error.message, result.error.details, result.error.hint]
    .filter(Boolean)
    .join(" ");
  if (code) assert.equal(result.error.code, code, diagnostic);
  assert.match(diagnostic, pattern);
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
  if (PRIVATE_BETA_EXTENSION) {
    for (const team of TEAMS) {
      for (const member of team.supplementalMembers) {
        const existingUser = await fixtureAdmin.auth.admin.getUserById(member.userId);
        if (existingUser.error) {
          const createdUser = await fixtureAdmin.auth.admin.createUser({
            email: member.email,
            email_confirm: true,
            id: member.userId,
            password,
            user_metadata: { qaFixture: "LEAGUE_PRIVATE_BETA_V1" },
          });
          if (createdUser.error) throw createdUser.error;
          created.supplementalUserIds.push(member.userId);
        } else {
          const updatedUser = await fixtureAdmin.auth.admin.updateUserById(member.userId, {
            password,
            user_metadata: { qaFixture: "LEAGUE_PRIVATE_BETA_V1" },
          });
          if (updatedUser.error) throw updatedUser.error;
        }
      }
    }
  }
  const supplementalMemberships = PRIVATE_BETA_EXTENSION
    ? TEAMS.flatMap((team, teamIndex) => team.supplementalMembers.map((member, memberIndex) => ({
      display_name: `${team.name} Player`,
      group_id: team.groupId,
      role: teamIndex === 1 && memberIndex === 1 ? "admin" : "player",
      user_id: member.userId,
    })))
    : [];
  await upsertMissing("pachanga_group_members", TEAMS.map((team) => ({
    display_name: `${team.name} Owner`, group_id: team.groupId, role: "owner", user_id: team.owner.id,
  })).concat(supplementalMemberships), "group_id,user_id");
  if (PRIVATE_BETA_EXTENSION) {
    const teamAdmin = TEAMS[1].supplementalMembers[1];
    const ensuredAdmin = await fixtureAdmin.from("pachanga_group_members")
      .update({ role: "admin" })
      .eq("group_id", TEAMS[1].groupId)
      .eq("user_id", teamAdmin.userId);
    if (ensuredAdmin.error) throw ensuredAdmin.error;
  }
  const supplementalProfiles = PRIVATE_BETA_EXTENSION
    ? TEAMS.flatMap((team, teamIndex) => team.supplementalMembers.map((member, memberIndex) => ({
      birth_date: `199${(teamIndex + memberIndex) % 10}-0${(memberIndex % 4) + 1}-10`,
      display_name: `${team.name} Player ${memberIndex + 2}`,
      id: member.profileId,
      source_group_id: team.groupId,
      user_id: member.userId,
    })))
    : [];
  await upsertMissing("pachanga_player_profiles", TEAMS.map((team, index) => ({
    birth_date: `199${index}-0${index + 1}-10`,
    display_name: `${team.name} Owner`,
    id: team.profileId,
    source_group_id: team.groupId,
    user_id: team.owner.id,
  })).concat(supplementalProfiles), "user_id");
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

async function selectClubOwner(candidates) {
  const candidateIds = candidates.map(({ account }) => account.id);
  const result = await fixtureAdmin
    .from("pachanga_clubs")
    .select("created_at,created_by,operational_status")
    .in("created_by", candidateIds);
  if (result.error) throw result.error;

  const recentCutoff = Date.now() - (24 * 60 * 60 * 1000);
  const availability = candidates.map((candidate, stableOrder) => {
    const actorClubs = result.data.filter(({ created_by }) => created_by === candidate.account.id);
    return {
      ...candidate,
      activeDrafts: actorClubs.filter(({ operational_status }) => ["draft", "pending_review"].includes(operational_status)).length,
      recentCreations: actorClubs.filter(({ created_at }) => new Date(created_at).getTime() >= recentCutoff).length,
      stableOrder,
    };
  }).filter(({ activeDrafts, recentCreations }) => activeDrafts < 3 && recentCreations < 5)
    .sort((left, right) => (
      left.recentCreations - right.recentCreations
      || left.activeDrafts - right.activeDrafts
      || left.stableOrder - right.stableOrder
    ));

  if (!availability.length) throw new Error("R4B_STAGING_CLUB_CREATOR_POOL_EXHAUSTED");
  return availability[0];
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
async function configurationFlags(platform) {
  return (await rpc(platform, "get_pachanga_platform_competition_configuration_v1")).flags;
}
async function setConfigurationFlags(platform, next, reason) {
  const current = await configurationFlags(platform);
  if (
    current.configurationCenterEnabled === next.configurationCenterEnabled
    && current.wizardV2Enabled === next.wizardV2Enabled
  ) return { snapshot: current };
  return commandOk(platform, "command_pachanga_competition_configuration_platform_v1", {
    action: "configuration.flags.set",
    aggregateId: IDS.configurationFlags,
    expectedRevision: current.revision,
    payload: { ...next, reason },
    surface: "competition-configuration-staging-flags",
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
async function betaFlags(supabase) {
  return rpc(supabase, "get_pachanga_league_private_beta_flags_v1");
}
async function setBetaFlags(platform, next, reason) {
  const current = await betaFlags(platform);
  return betaCommandOk(platform, "command_pachanga_league_private_beta_platform_v1", {
    action: "beta.flags.set",
    aggregateId: IDS.betaFlags,
    expectedRevision: current.revision,
    payload: { ...next, reason },
    surface: "league-private-beta-staging-flags",
  });
}
async function organizerModel(supabase, kind, id) {
  const model = await rpc(supabase, "get_my_pachanga_league_private_beta_v1");
  const organizer = model.organizers.find((candidate) => (
    candidate.kind === kind && candidate.id === id
  ));
  assert.ok(organizer, `${kind} organizer ${id} must be present in the private beta read model`);
  return organizer;
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
async function setLeagueOperationFlags(platform, {
  aggregateId,
  currentRpc,
  commandRpc,
  next,
  reason,
  surface,
}) {
  const current = await rpc(platform, currentRpc);
  const result = await platform.rpc(commandRpc, {
    aggregate_id: aggregateId,
    client_metadata: metadata(surface),
    command_payload: { ...next, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}
const setMatchOperationsFlags = (platform, next, reason) => setLeagueOperationFlags(platform, {
  aggregateId: IDS.matchOperationsFlags,
  commandRpc: "command_pachanga_league_match_operations_platform_v1",
  currentRpc: "get_pachanga_league_match_operations_flags_v1",
  next,
  reason,
  surface: "league-private-beta-r4c-flags",
});
const setOperationalExceptionsFlags = (platform, next, reason) => setLeagueOperationFlags(platform, {
  aggregateId: IDS.operationalExceptionsFlags,
  commandRpc: "command_pachanga_league_operational_exceptions_platform_v1",
  currentRpc: "get_pachanga_league_operational_exceptions_flags_v1",
  next,
  reason,
  surface: "league-private-beta-r4d-flags",
});
async function setRefereeFlags(platform, next, reason) {
  const current = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  if (REFEREE_FLAG_KEYS.every((key) => current[key] === next[key])) return;
  const result = await platform.rpc("command_pachanga_referee_platform_admin_v1", {
    aggregate_id: IDS.refereeFlags,
    client_metadata: metadata("r4b-cleanup"),
    command_action: "referee_flags.set",
    command_payload: { ...Object.fromEntries(REFEREE_FLAG_KEYS.map((key) => [key, next[key]])), reason },
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
      const timer = setTimeout(() => { waiter = null; reject(new Error("R4B invalidation timed out")); }, 90_000);
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

async function grantBetaBundle(platform, organizerClient, organizerKind, organizerId, payload = {}) {
  const organizer = await organizerModel(organizerClient, organizerKind, organizerId);
  return betaCommandOk(platform, "command_pachanga_league_private_beta_platform_v1", {
    action: "beta.bundle.grant",
    aggregateId: organizerId,
    expectedRevision: organizer.organizerRevision,
    payload: {
      maxTeams: 6,
      organizerKind,
      reason: "League Private Beta authenticated staging grant",
      ...payload,
    },
    surface: "league-private-beta-staging-grant",
  });
}

async function revokeBetaBundle(platform, organizerClient, organizerKind, organizerId, bundleId) {
  const bundle = await fixtureAdmin
    .from("pachanga_competition_entitlement_grants")
    .select("status")
    .eq("bundle_id", bundleId)
    .eq("program_key", "LEAGUE_PRIVATE_BETA_V1")
    .limit(1)
    .maybeSingle();
  if (bundle.error) throw bundle.error;
  if (!bundle.data || bundle.data.status === "revoked") return;
  const organizer = await organizerModel(organizerClient, organizerKind, organizerId);
  await betaCommandOk(platform, "command_pachanga_league_private_beta_platform_v1", {
    action: "beta.bundle.revoke",
    aggregateId: organizerId,
    expectedRevision: organizer.organizerRevision,
    payload: {
      bundleId,
      organizerKind,
      reason: "League Private Beta authenticated staging cleanup",
    },
    surface: "league-private-beta-staging-cleanup",
  });
}

async function createPrivateBetaLeague(organizerClient, organizerKind, organizerId, tag) {
  const organizer = await organizerModel(organizerClient, organizerKind, organizerId);
  const createOperationId = randomUUID();
  const createInput = {
    action: "wizard.create",
    aggregateId: organizerId,
    expectedRevision: organizer.organizerRevision,
    operationId: createOperationId,
    payload: {
      authoringMode: "SIMPLE",
      organizerKind,
      presetKey: "LEAGUE_F5_QUICK",
      reason: "Authenticated League Private Beta Wizard V2",
    },
  };
  let receipt = await betaCommandOk(
    organizerClient,
    "command_pachanga_league_private_beta_v2",
    createInput,
  );
  assert.deepEqual(
    await betaCommandOk(organizerClient, "command_pachanga_league_private_beta_v2", createInput),
    receipt,
  );
  let wizard = receipt.snapshot.wizard;
  const presets = await rpc(organizerClient, "get_pachanga_competition_authoring_presets_v1");
  const preset = presets.presets.find(({ key }) => key === "LEAGUE_F5_QUICK");
  assert.ok(preset, "League Wizard V2 F5 preset must be available");
  const steps = [
    {
      description: "Liga privada beta integrada R1-R4D",
      generalArea: "Barcelona",
      imageUrl: "",
      name: `R4B QA League Private Beta ${tag}`,
      slug: `r4b-qa-private-beta-${tag}`,
    },
    { modality: "FUTBOL_5" },
    {
      editionName: "Edición privada 2027",
      endsAt: "2027-12-31",
      seasonLabel: "2027",
      startsAt: "2027-01-01",
      timezone: "Europe/Madrid",
    },
    {
      legs: 1,
      registrationClosesAt: "2027-11-30T23:00:00Z",
      registrationMode: "INVITE_ONLY",
      teamCap: 6,
    },
    {
      closeRequiresApprovedRosters: true,
      credentialRequired: false,
      jerseyRequired: false,
      maximumRosterSize: 5,
      minimumRosterSize: 5,
    },
    {
      autoOfficialAfterConfirmation: true,
      matchDurationMinutes: 70,
      pointsForDraw: 1,
      pointsForLoss: 0,
      pointsForWin: 3,
      requiredBufferMinutes: 10,
      responseDeadlineHours: 48,
    },
    {
      allowTbd: true,
      minimumRestMinutes: 0,
      useDivision: true,
      venueRequired: false,
      weeklyPattern: [{ dayOfWeek: 6, startTime: "20:00" }],
    },
    {
      allowSharedPositions: true,
      allowUnknownScorer: false,
      scorerDetailPolicy: "OPTIONAL",
      tieBreakCriteria: [
        "POINTS",
        "GOAL_DIFFERENCE",
        "GOALS_FOR",
        "WINS",
        "HEAD_TO_HEAD_POINTS",
        "HEAD_TO_HEAD_GOAL_DIFFERENCE",
        "HEAD_TO_HEAD_GOALS_FOR",
      ],
    },
    {
      gracePeriodMinutes: 10,
      maximumMatchDurationMinutes: 120,
      minimumRestHours: 0,
      noShowLoserScore: 0,
      noShowOutcome: "NO_SHOW",
      noShowWinnerScore: 3,
      postponementDeadlinePolicy: "EXPIRE",
      postponementResponseDeadlineHours: 48,
    },
    preset.steps["10"],
    preset.steps["11"],
    {
      ...preset.steps["12"],
      acknowledgeUnavailableFeatures: true,
      consent: true,
      paymentsAcknowledged: true,
      tournamentsAcknowledged: true,
    },
  ];
  for (let index = 0; index < steps.length; index += 1) {
    receipt = await betaCommandOk(
      organizerClient,
      "command_pachanga_league_private_beta_v2",
      {
        action: "wizard.step.save",
        aggregateId: wizard.id,
        expectedRevision: wizard.revision,
        payload: {
          data: steps[index],
          reason: `League Private Beta step ${index + 1}`,
          step: index + 1,
        },
      },
    );
    wizard = receipt.snapshot;
  }
  const finalized = await betaCommandOk(
    organizerClient,
    "command_pachanga_league_private_beta_v2",
    {
      action: "wizard.finalize",
      aggregateId: wizard.id,
      expectedRevision: wizard.revision,
      payload: { reason: "League Private Beta staging consent" },
    },
  );
  assert.equal(finalized.snapshot.canonical.registrationMode, "INVITE_ONLY");
  assert.equal(finalized.snapshot.canonical.editionStatus, "draft");
  assert.equal(finalized.snapshot.canonical.visibility, "private");
  assert.equal(finalized.snapshot.nextAction, "open_registration");
  assert.equal(finalized.snapshot.canonical.teamCap, 6);
  assert.deepEqual(finalized.snapshot.unavailable, [
    "payments",
    "tournaments",
    "manual_assisted_pairing",
    "hybrid_pairing",
  ]);
  assert.equal(finalized.snapshot.configurationHealth.complete, true);
  assert.equal(finalized.snapshot.wizard.wizardVersion, 2);
  assert.deepEqual(finalized.snapshot.wizard.completedSteps, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  return finalized;
}
async function verifyPreview(accessToken, competitionId, planId) {
  if (!env.previewUrl) return { checked: false };
  const origin = new URL(env.previewUrl);
  let previewCookie = "";
  if (origin.searchParams.has("_vercel_share")) {
    const access = await fetch(origin, { cache: "no-store", redirect: "manual" });
    previewCookie = access.headers.get("set-cookie")?.split(";", 1)[0] ?? "";
    assert.ok([302, 307, 308].includes(access.status), "Preview share access did not redirect safely");
    assert.ok(previewCookie, "Preview share access did not issue an ephemeral cookie");
    origin.search = "";
  }
  const previewHeaders = {
    Authorization: `Bearer ${accessToken}`,
    ...(env.protectionBypass ? { "x-vercel-protection-bypass": env.protectionBypass } : {}),
    ...(previewCookie ? { Cookie: previewCookie } : {}),
  };
  const productPaths = [
    "/laboratorio-league-scheduling?scenario=published",
    `/competiciones/${competitionId}/gestion/calendario`,
    `/competiciones/${competitionId}/calendario`,
  ];
  if (CONFIGURATION_EXTENSION) productPaths.push(
    `/competiciones/${competitionId}/configuracion`,
    "/admin/competitions",
    "/demo-world?surface=configuration",
  );
  if (REFEREE_ASSIGNMENTS_EXTENSION) productPaths.push(
    "/laboratorio-referee-platform?surface=confirmed",
    "/mis-asignaciones-arbitrales",
    `/competiciones/${competitionId}/gestion/arbitros`,
    "/mercado?market=referees",
  );
  for (const path of productPaths) {
    const response = await fetch(new URL(path, origin), {
      cache: "no-store",
      headers: previewHeaders,
      redirect: "manual",
    });
    assert.equal(response.ok, true, `${path} did not load in Preview`);
    assert.doesNotMatch(await response.text(), /SUPABASE_SERVICE_ROLE_KEY|qonbngfrnrqgmxbdfbea/i);
  }
  const response = await fetch(new URL(`/api/competitions/scheduling/workbench/${planId}`, origin), {
    cache: "no-store",
    headers: previewHeaders,
    redirect: "manual",
  });
  assert.equal(response.ok, true, await response.text());
  assert.equal(response.headers.get("cache-control")?.includes("no-store"), true);
  return { checked: true, origin: origin.origin };
}

let platform;
let clubOwner;
let ownerA;
let ownerADevice2;
let ownerB;
let ownerC;
let adminA;
let adminADevice2;
let playerA;
let staffA;
let completed = false;
let cleanupReadback = null;
let countsBefore;
let initialFlagState = null;
let storySummary = null;

try {
  await prepareIdentities();
  platform = await signIn(USERS.platform, "platform");
  ownerA = await signIn(USERS.ownerA, "owner-a");
  ownerADevice2 = await signIn(USERS.ownerA, "owner-a-device-2");
  ownerB = await signIn(USERS.ownerB, "owner-b");
  ownerC = await signIn(USERS.ownerC, "owner-c");
  adminA = await signIn(USERS.adminA, "admin-a");
  adminADevice2 = await signIn(USERS.adminA, "admin-a-device-2");
  playerA = await signIn(USERS.playerA, "player-a");
  staffA = await signIn(USERS.staffA, "staff-a");
  const teamClients = [ownerA, ownerB, ownerC, adminA, playerA, staffA];
  for (let index = 0; index < TEAMS.length; index += 1) {
    await ensureRegular(platform, teamClients[index], TEAMS[index].owner);
  }
  clubOwner = await selectClubOwner([
    { account: USERS.ownerA, client: ownerA },
    { account: USERS.ownerB, client: ownerB },
    { account: USERS.ownerC, client: ownerC },
    { account: USERS.adminA, client: adminA },
    { account: USERS.playerA, client: playerA },
  ]);
  const outsiderAccount = {
    email: `r4b-outsider-${randomUUID()}@pachangasiq.test`,
    id: randomUUID(),
  };
  const outsiderCreated = await fixtureAdmin.auth.admin.createUser({
    email: outsiderAccount.email,
    email_confirm: true,
    id: outsiderAccount.id,
    password,
    user_metadata: { qaFixture: "R4B_STAGING_OUTSIDER" },
  });
  if (outsiderCreated.error) throw outsiderCreated.error;
  created.ephemeralUserIds.push(outsiderAccount.id);
  const outsider = {
    account: outsiderAccount,
    client: await signIn(outsiderAccount, "outsider"),
  };
  await ensureTeams();
  if (PRIVATE_BETA_EXTENSION) {
    for (const team of TEAMS) {
      team.delegateClient = await signIn({
        email: team.supplementalMembers[0].email,
        id: team.supplementalMembers[0].userId,
      }, `${team.name}-delegate`);
      team.participantClient = await signIn({
        email: team.supplementalMembers[2].email,
        id: team.supplementalMembers[2].userId,
      }, `${team.name}-participant`);
    }
    TEAMS[1].adminClient = await signIn({
      email: TEAMS[1].supplementalMembers[1].email,
      id: TEAMS[1].supplementalMembers[1].userId,
    }, `${TEAMS[1].name}-admin`);
  }
  const queue = eventQueue();
  const channel = ownerADevice2.channel(`r4b-staging-${randomUUID()}`).on("postgres_changes", {
    event: "INSERT",
    schema: "public",
    table: "pachanga_competition_invalidations",
  }, (payload) => {
    if (payload.new?.entity_type !== "league_team_calendar") return;
    if (payload.new?.target_group_id !== TEAMS[0].groupId) return;
    queue.push(payload);
  });
  channels.push([ownerADevice2, channel]);
  await waitForSubscription(channel);
  countsBefore = await counts();
  const [
    initialBeta,
    initialCompetition,
    initialClub,
    initialParticipation,
    initialScheduling,
    initialMatchOperations,
    initialOperationalExceptions,
    initialReferee,
    initialDiscipline,
    initialConfiguration,
  ] = await Promise.all([
    betaFlags(platform),
    rpc(platform, "get_pachanga_platform_competition_foundation_v1", { page_offset: 0, page_size: 1 }),
    rpc(platform, "get_pachanga_club_foundation_flags_v1"),
    rpc(platform, "get_pachanga_league_participation_flags_v1"),
    scheduleFlags(platform),
    rpc(platform, "get_pachanga_league_match_operations_flags_v1"),
    rpc(platform, "get_pachanga_league_operational_exceptions_flags_v1"),
    rpc(platform, "get_pachanga_referee_foundation_flags_v1"),
    rpc(platform, "get_pachanga_competition_discipline_flags_v1"),
    CONFIGURATION_EXTENSION ? configurationFlags(platform) : Promise.resolve(null),
  ]);
  initialFlagState = {
    beta: initialBeta,
    clubFoundation: initialClub,
    competition: initialCompetition.flags,
    configuration: initialConfiguration,
    discipline: initialDiscipline,
    matchOperations: initialMatchOperations,
    operationalExceptions: initialOperationalExceptions,
    participation: initialParticipation,
    referee: initialReferee,
    scheduling: initialScheduling,
  };

  if (PRIVATE_BETA_EXTENSION) {
    const betaEnabled = await setBetaFlags(platform, {
      creationEnabled: false,
      enabled: true,
      publicDiscoveryEnabled: false,
    }, "League Private Beta gate enabled before dependencies");
    assert.equal(betaEnabled.snapshot.enabled, true);
    assert.equal(betaEnabled.snapshot.creationEnabled, false);
  }

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
    publicRegistrationEnabled: !PRIVATE_BETA_EXTENSION,
    registrationEnabled: true,
    rostersEnabled: true,
    schedulePreferencesEnabled: true,
  }, "R4B staging R4A dependency window");

  if (PRIVATE_BETA_EXTENSION) {
    await setScheduleFlags(platform, {
      canonicalFixtureCreationEnabled: true,
      editingEnabled: true,
      foundationEnabled: true,
      generationEnabled: true,
      publicCalendarEnabled: false,
      publicationEnabled: true,
    }, "League Private Beta R4B dependency window");
    await setMatchOperationsFlags(
      platform,
      Object.fromEntries(MATCH_OPERATIONS_FLAG_KEYS.map((key) => [
        key,
        key !== "publicStandingsEnabled",
      ])),
      "League Private Beta R4C dependency window",
    );
    await setOperationalExceptionsFlags(
      platform,
      Object.fromEntries(OPERATIONAL_EXCEPTIONS_FLAG_KEYS.map((key) => [
        key,
        key !== "publicExceptionStatusEnabled",
      ])),
      "League Private Beta R4D dependency window",
    );
    const betaCreationEnabled = await setBetaFlags(platform, {
      creationEnabled: true,
      enabled: true,
      publicDiscoveryEnabled: false,
    }, "League Private Beta creation enabled after dependencies");
    assert.equal(betaCreationEnabled.snapshot.creationEnabled, true);
    if (CONFIGURATION_EXTENSION) {
      const configurationEnabled = await setConfigurationFlags(platform, {
        configurationCenterEnabled: true,
        wizardV2Enabled: true,
      }, "Wave 5A staging activation after dependencies");
      assert.equal(configurationEnabled.snapshot.configurationCenterEnabled, true);
      assert.equal(configurationEnabled.snapshot.wizardV2Enabled, true);
      assert.equal(configurationEnabled.snapshot.publicSurfacesOff, true);
    }
    const noGrant = await betaCommand(ownerB, "command_pachanga_league_private_beta_v1", {
      action: "wizard.create",
      aggregateId: TEAMS[1].groupId,
      expectedRevision: (await organizerModel(ownerB, "TEAM", TEAMS[1].groupId)).organizerRevision,
      payload: { organizerKind: "TEAM", reason: "No grant negative case" },
    });
    expectError(noGrant, /LEAGUE_PRIVATE_BETA_GRANT_REQUIRED/, "42501");
    const teamAdminWithoutGrant = await betaCommand(TEAMS[1].adminClient, "command_pachanga_league_private_beta_v1", {
      action: "wizard.create",
      aggregateId: TEAMS[1].groupId,
      expectedRevision: (await organizerModel(ownerB, "TEAM", TEAMS[1].groupId)).organizerRevision,
      payload: { organizerKind: "TEAM", reason: "Team admin negative case" },
    });
    expectError(teamAdminWithoutGrant, /TEAM_OWNER_REQUIRED/, "42501");

    const expiringBundle = await grantBetaBundle(platform, ownerB, "TEAM", TEAMS[1].groupId, {
      expiresAt: "2027-12-31T23:59:59Z",
      reason: "League Private Beta expired grant negative fixture",
    });
    created.expiredTeamBundleId = expiringBundle.snapshot.bundle.bundleId;
    const expiredAt = new Date(Date.now() - 60_000);
    const expireFixture = await fixtureAdmin.from("pachanga_competition_entitlement_grants")
      .update({
        expires_at: expiredAt.toISOString(),
        valid_from: new Date(expiredAt.getTime() - 60_000).toISOString(),
      })
      .eq("bundle_id", created.expiredTeamBundleId)
      .eq("program_key", "LEAGUE_PRIVATE_BETA_V1");
    if (expireFixture.error) throw expireFixture.error;
    const expiredGrant = await betaCommand(ownerB, "command_pachanga_league_private_beta_v1", {
      action: "wizard.create",
      aggregateId: TEAMS[1].groupId,
      expectedRevision: (await organizerModel(ownerB, "TEAM", TEAMS[1].groupId)).organizerRevision,
      payload: { organizerKind: "TEAM", reason: "Expired grant negative case" },
    });
    expectError(expiredGrant, /LEAGUE_PRIVATE_BETA_GRANT_REQUIRED/, "42501");
    await revokeBetaBundle(
      platform,
      ownerB,
      "TEAM",
      TEAMS[1].groupId,
      created.expiredTeamBundleId,
    );
    created.expiredTeamBundleId = null;

    const invalidCapacity = await betaCommand(platform, "command_pachanga_league_private_beta_platform_v1", {
      action: "beta.bundle.grant",
      aggregateId: TEAMS[0].groupId,
      expectedRevision: (await organizerModel(ownerA, "TEAM", TEAMS[0].groupId)).organizerRevision,
      payload: {
        maxTeams: 21,
        organizerKind: "TEAM",
        reason: "Capacity negative case",
      },
    });
    expectError(invalidCapacity, /BETA_CAPACITY_LIMIT/, "22023");

    const teamBundle = await grantBetaBundle(platform, ownerA, "TEAM", TEAMS[0].groupId);
    created.teamBundleId = teamBundle.snapshot.bundle.bundleId;
    let teamWizard = await betaCommandOk(ownerA, "command_pachanga_league_private_beta_v2", {
      action: "wizard.create",
      aggregateId: TEAMS[0].groupId,
      expectedRevision: teamBundle.snapshot.organizerRevision,
      payload: {
        authoringMode: "SIMPLE",
        organizerKind: "TEAM",
        presetKey: "LEAGUE_F7_STANDARD",
        reason: "Team organizer standard configuration proof",
      },
    });
    if (CONFIGURATION_EXTENSION) {
      teamWizard = await betaCommandOk(ownerA, "command_pachanga_league_private_beta_v2", {
        action: "wizard.preset.apply",
        aggregateId: teamWizard.snapshot.wizard.id,
        expectedRevision: teamWizard.snapshot.wizard.revision,
        payload: { presetKey: "LEAGUE_F7_STANDARD", reason: "Wave 5A standard preset proof" },
      });
      assert.equal(teamWizard.snapshot.authoringMode, "SIMPLE");
      assert.equal(teamWizard.snapshot.presetKey, "LEAGUE_F7_STANDARD");
      assert.equal(Object.keys(teamWizard.snapshot.steps).length, 12);
    }
    await betaCommandOk(ownerA, "command_pachanga_league_private_beta_v2", {
      action: "wizard.cancel",
      aggregateId: teamWizard.snapshot.wizard?.id ?? teamWizard.snapshot.id,
      expectedRevision: teamWizard.snapshot.wizard?.revision ?? teamWizard.snapshot.revision,
      payload: { reason: "Team organizer beta proof cleanup" },
    });
    await revokeBetaBundle(platform, ownerA, "TEAM", TEAMS[0].groupId, created.teamBundleId);
    created.teamBundleId = null;
  }

  const tag = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  created.clubId = randomUUID();
  const clubCreated = await club(clubOwner.client, {
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
  const clubConsent = await confirmClubPublication(
    clubOwner.client,
    created.clubId,
    clubCreated.snapshot.club.revision,
  );
  const clubSubmitted = await club(clubOwner.client, {
    action: "club.review.submit",
    aggregateId: created.clubId,
    expectedRevision: clubConsent.confirmedRevision,
    payload: { reason: "R4B staging Club review" },
  });
  if (PRIVATE_BETA_EXTENSION) {
    const draftBundle = await grantBetaBundle(platform, clubOwner.client, "CLUB", created.clubId);
    const draftCreate = await betaCommand(
      clubOwner.client,
      "command_pachanga_league_private_beta_v1",
      {
        action: "wizard.create",
        aggregateId: created.clubId,
        expectedRevision: draftBundle.snapshot.organizerRevision,
        payload: { organizerKind: "CLUB", reason: "Draft Club negative case" },
      },
    );
    expectError(draftCreate, /CLUB_MUST_BE_ACTIVE/, "42501");
    await revokeBetaBundle(
      platform,
      clubOwner.client,
      "CLUB",
      created.clubId,
      draftBundle.snapshot.bundle.bundleId,
    );
  }
  await club(platform, {
    action: "club.status.set",
    aggregateId: created.clubId,
    expectedRevision: clubSubmitted.snapshot.club.revision,
    payload: { reason: "R4B staging Club activation", status: "active" },
  }, true);
  let clubState = await clubSnapshot(clubOwner.client, created.clubId);
  const managerInvitation = await club(clubOwner.client, {
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
  let structure;
  if (PRIVATE_BETA_EXTENSION) {
    const bundle = await grantBetaBundle(platform, clubOwner.client, "CLUB", created.clubId);
    created.betaBundleId = bundle.snapshot.bundle.bundleId;
    const betaLeague = await createPrivateBetaLeague(
      clubOwner.client,
      "CLUB",
      created.clubId,
      tag,
    );
    created.wizardId = betaLeague.snapshot.wizard.id;
    created.competitionId = betaLeague.snapshot.canonical.competitionId;
    let betaCompetitionState = await competitionSnapshot(clubOwner.client, created.competitionId);
    const director = await foundation(clubOwner.client, {
      action: "staff.grant",
      aggregateId: created.competitionId,
      expectedRevision: betaCompetitionState.competition.revision,
      payload: { staffRole: "competition_director", userId: USERS.staffA.id },
    });
    await foundation(staffA, {
      action: "staff.grant",
      aggregateId: created.competitionId,
      expectedRevision: director.confirmedRevision,
      payload: { staffRole: "competition_schedule_manager", userId: USERS.adminA.id },
    });
    betaCompetitionState = await competitionSnapshot(staffA, created.competitionId);
    let configurationBeforeRegistration = null;
    if (CONFIGURATION_EXTENSION) {
      configurationStagingState.competitionId = created.competitionId;
      configurationBeforeRegistration = await runCompetitionConfigurationBeforeRegistration({
        actor: staffA,
        competitionId: created.competitionId,
        fixtureAdmin,
        metadata,
        rpc,
        state: configurationStagingState,
      });
      betaCompetitionState = await competitionSnapshot(staffA, created.competitionId);
    }
    const edition = betaCompetitionState.editions.find(
      ({ id }) => id === betaLeague.snapshot.canonical.editionId,
    );
    const ruleRevision = betaCompetitionState.ruleSets
      .flatMap(({ revisions }) => revisions)
      .find(({ id }) => id === edition?.ruleRevisionId);
    const stage = betaCompetitionState.stages.find(
      ({ id }) => id === betaLeague.snapshot.canonical.stageId,
    );
    const division = stage.divisions.find(
      ({ id }) => id === betaLeague.snapshot.canonical.divisionId,
    );
    const competitionGroup = stage.groups.find(
      ({ id }) => id === betaLeague.snapshot.canonical.groupId,
    );
    const categoryReadback = await fixtureAdmin
      .from("pachanga_competition_categories")
      .select("id,revision,status,visibility")
      .eq("id", betaLeague.snapshot.canonical.categoryId)
      .single();
    if (categoryReadback.error) throw categoryReadback.error;
    const category = categoryReadback.data;
    assert.equal(category.status, "active");
    assert.equal(category.visibility, "private");
    assert.ok(edition && ruleRevision && stage && division && competitionGroup && category);
    assert.equal(edition.status, "draft");
    await participation(staffA, {
      action: "registration.open",
      aggregateId: edition.id,
      expectedRevision: edition.revision,
      payload: {
        closesAt: "2027-11-30T23:00:00Z",
        reason: "Open invite-only League Private Beta registration",
        registrationMode: "INVITE_ONLY",
        ruleRevisionId: ruleRevision.id,
      },
    });
    betaCompetitionState = await competitionSnapshot(staffA, created.competitionId);
    const openedEdition = betaCompetitionState.editions.find(({ id }) => id === edition.id);
    assert.equal(openedEdition?.status, "registration_open");
    const configurationAfterRegistration = CONFIGURATION_EXTENSION
      ? await runCompetitionConfigurationAfterRegistration({
        actor: staffA,
        competitionId: created.competitionId,
        editionId: edition.id,
        fixtureAdmin,
        metadata,
        rpc,
        state: configurationStagingState,
      })
      : null;
    structure = {
      activatedCategory: { snapshot: category },
      category,
      competitionGroup,
      division,
      edition: openedEdition,
      ruleRevision,
      stage,
    };
    if (CONFIGURATION_EXTENSION) {
      assert.equal(ruleRevision.id, configurationBeforeRegistration.advancedRuleRevisionId);
      assert.equal(configurationAfterRegistration.activeConfigurationDrafts, 0);
    }
  } else {
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
          ...(R4D_EXTENSION ? {
            exceptionPolicy: {
              gracePeriodMinutes: 10,
              maximumMatchDurationMinutes: 120,
              minimumRestHours: 0,
              noShowLoserScore: 0,
              noShowOutcome: "NO_SHOW",
              noShowWinnerScore: 3,
              organizerApprovalRequired: true,
              organizerCanInterveneAfterDeadline: true,
              postponementDeadlinePolicy: "EXPIRE",
              postponementResponseDeadlineHours: 48,
              resumptionEligibilityPolicy: {
                allowOriginalSquad: true,
                allowReplacementForDocumentedInjury: false,
                requireOriginalEligibility: true,
              },
              resumptionPolicy: "SAME_CANONICAL_MATCH",
              stageWindowEnd: "2027-12-31T23:59:59Z",
              stageWindowStart: "2027-01-01T00:00:00Z",
              venuePolicy: {
                allowSavedVenue: true,
                allowTbd: true,
                allowVenueLabel: true,
              },
            },
          } : {}),
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
          ...(MATCH_OPERATIONS_EXTENSION ? {
            matchSheetPolicy: {
              squadMin: 1,
              squadMax: 3,
              starterMin: 1,
              starterMax: 1,
              substituteMax: 2,
            },
          } : {}),
          registrationPolicy: { teamLimits: { maximum: 8, minimum: 2 } },
          rosterPolicy: {
            closeRequiresApprovedRosters: true,
            maximumSize: 4,
            minimumSize: 1,
            multiTeamPolicy: "FORBIDDEN_SAME_EDITION_CATEGORY",
          },
        },
        results: MATCH_OPERATIONS_EXTENSION ? {
          allowUnknownScorer: false,
          confirmationPolicy: {
            autoOfficialAfterConfirmation: true,
            mode: "BILATERAL",
            responseDeadlineHours: 48,
          },
          publicationPolicy: { resultsPublic: true, standingsPublic: true },
          scorerDetailPolicy: "OPTIONAL",
          scoringPolicy: { pointsForDraw: 1, pointsForLoss: 0, pointsForWin: 3 },
          standingsPolicy: { allowSharedPositions: true },
          tieBreakCriteria: [
            "POINTS",
            "GOAL_DIFFERENCE",
            "GOALS_FOR",
            "WINS",
            "HEAD_TO_HEAD_POINTS",
            "HEAD_TO_HEAD_GOAL_DIFFERENCE",
            "HEAD_TO_HEAD_GOALS_FOR",
          ],
        } : { scoringPolicy: {}, tieBreakCriteria: [] },
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
  structure = {
    activatedCategory,
    category,
    competitionGroup,
    division,
    edition,
    ruleRevision,
    stage,
  };
  }
  const {
    activatedCategory,
    category,
    competitionGroup,
    division,
    edition,
    ruleRevision,
    stage,
  } = structure;
  let competitionState = await competitionSnapshot(staffA, created.competitionId);

  const entries = [];
  for (let index = 0; index < TEAMS.length; index += 1) {
    const team = TEAMS[index];
    const teamClient = teamClients[index];
    let accepted;
    if (PRIVATE_BETA_EXTENSION) {
      if (index === 0) {
        const publicApplication = await command(
          teamClient,
          "command_pachanga_league_participation_v1",
          {
            action: "entry.submit",
            aggregateId: category.id,
            expectedRevision: activatedCategory.snapshot.revision,
            payload: { reason: "Public registration negative case", teamId: team.groupId },
          },
        );
        expectError(publicApplication, /LEAGUE_PUBLIC_REGISTRATION_DISABLED/, "42501");
      }
      const invitation = await participation(staffA, {
        action: "entry.invite",
        aggregateId: category.id,
        expectedRevision: activatedCategory.snapshot.revision,
        payload: {
          expiresAt: "2027-11-15T23:00:00Z",
          reason: `Private invitation ${team.name}`,
          teamId: team.groupId,
        },
      });
      accepted = await participation(teamClient, {
        action: "entry.accept",
        aggregateId: invitation.snapshot.entry.id,
        expectedRevision: invitation.snapshot.entry.revision,
        payload: { reason: `${team.name} owner accepts private invitation` },
      });
      const delegateInvitation = await participation(teamClient, {
        action: "delegate.invite",
        aggregateId: accepted.snapshot.entry.id,
        expectedRevision: accepted.snapshot.entry.revision,
        payload: {
          reason: `${team.name} appoints primary delegate`,
          role: "PRIMARY_DELEGATE",
          userId: team.supplementalMembers[0].userId,
        },
      });
      const invitedDelegate = delegateInvitation.snapshot.delegates.find((delegate) => (
        delegate.role === "PRIMARY_DELEGATE"
        && delegate.status === "invited"
      ));
      assert.ok(invitedDelegate);
      assert.equal("userId" in invitedDelegate, false);
      await participation(team.delegateClient, {
        action: "delegate.accept",
        aggregateId: invitedDelegate.id,
        expectedRevision: invitedDelegate.revision,
        payload: { reason: `${team.name} delegate accepts` },
      });
    } else {
      const submitted = await participation(teamClient, {
        action: "entry.submit",
        aggregateId: category.id,
        expectedRevision: activatedCategory.snapshot.revision,
        payload: { reason: `${team.name} application`, teamId: team.groupId },
      });
      accepted = await participation(staffA, {
        action: "entry.accept",
        aggregateId: submitted.snapshot.entry.id,
        expectedRevision: submitted.snapshot.entry.revision,
        payload: { reason: `Accept ${team.name}` },
      });
    }
    const entryId = accepted.snapshot.entry.id;
    const rosterId = accepted.snapshot.roster.id;
    let roster = await rosterSnapshot(teamClient, rosterId);
    const rosterProfiles = PRIVATE_BETA_EXTENSION
      ? [team.profileId, ...team.supplementalMembers.map(({ profileId }) => profileId)]
      : [team.profileId];
    for (const playerProfileId of rosterProfiles) {
      await participation(teamClient, {
        action: "roster.member.add",
        aggregateId: rosterId,
        expectedRevision: roster.roster.revision,
        payload: { playerProfileId, reason: `${team.name} roster` },
      });
      roster = await rosterSnapshot(teamClient, rosterId);
    }
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
    entries.push({
      entryId,
      participantClient: team.participantClient ?? teamClient,
      rosterId,
      team,
      teamClient,
    });
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

  if (!PRIVATE_BETA_EXTENSION) {
    await setScheduleFlags(platform, {
      canonicalFixtureCreationEnabled: true,
      editingEnabled: true,
      foundationEnabled: true,
      generationEnabled: true,
      publicCalendarEnabled: true,
      publicationEnabled: true,
    }, "R4B authenticated staging window");
  }

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

  const outsiderRead = await outsider.client.rpc("get_pachanga_league_schedule_workbench_v1", {
    page_offset: 0,
    page_size: 200,
    target_schedule_plan_id: created.planId,
  });
  expectError(outsiderRead, /COMPETITION_SCHEDULE_MANAGER_REQUIRED/, "42501");
  const directWrite = await ownerA.from("pachanga_competition_schedule_slots").insert({ id: randomUUID() });
  assert.ok(directWrite.error);

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
  assert.equal(published.snapshot.publication.notificationCount, PRIVATE_BETA_EXTENSION ? 12 : 6);
  assert.equal((await teamInvalidation).new.target_group_id, TEAMS[0].groupId);

  const teamCalendar = await rpc(ownerADevice2, "get_pachanga_my_league_schedule_v1", {
    target_entry_id: entries[0].entryId,
  });
  assert.equal(teamCalendar.fixtures.length, 5);
  const anonymous = client();
  const publicCalendarResult = await anonymous.rpc("get_pachanga_public_league_calendar_v1", {
    target_competition_id: created.competitionId,
    target_round_from: 1,
    target_round_limit: 20,
  });
  if (PRIVATE_BETA_EXTENSION) {
    expectError(publicCalendarResult, /PUBLIC_CALENDAR_DISABLED/, "42501");
  } else {
    if (publicCalendarResult.error) throw publicCalendarResult.error;
    const publicCalendar = publicCalendarResult.data;
    assert.equal(publicCalendar.rounds.length, 5);
    assert.equal(publicCalendar.rounds.reduce((total, round) => total + round.fixtures.length, 0), 15);
    const roundDetail = await rpc(anonymous, "get_pachanga_league_round_detail_v1", {
      target_round_id: publicCalendar.rounds[0].id,
    });
    assert.equal(roundDetail.fixtures.length, 3);
  }

  for (const team of TEAMS) {
    const notifications = await fixtureAdmin.from("pachanga_user_notifications")
      .select("id", { count: "exact", head: true })
      .eq("dedupe_key", `league-schedule:${created.publicationOperationId}:${team.owner.id}`);
    if (notifications.error) throw notifications.error;
  assert.equal(notifications.count, 1);
  }
  const r4c = R4C_EXTENSION ? await runLeagueMatchOperationsStagingExtension({
    adminADevice2,
    anonymousFactory: () => client(),
    channels,
    competitionGroup,
    created,
    division,
    entries,
    eventQueue,
    expectError,
    fixtureAdmin,
    metadata,
    ownerADevice2,
    outsiderClient: outsider.client,
    platform,
    privateBeta: PRIVATE_BETA_EXTENSION,
    rpc,
    stage,
    staffA,
    waitForSubscription,
  }) : null;
  const r4d = R4D_EXTENSION ? await runLeagueOperationalExceptionsStagingExtension({
    anonymousFactory: () => client(),
    channels,
    created,
    entries,
    expectError,
    fixtureAdmin,
    metadata,
    ownerADevice2,
    outsiderClient: outsider.client,
    platform,
    privateBeta: PRIVATE_BETA_EXTENSION,
    rpc,
    staffA,
    waitForSubscription,
  }) : null;
  const refereeAssignments = REFEREE_ASSIGNMENTS_EXTENSION
    ? await runRefereeAssignmentsPrivateBetaStagingExtension({
      adminA,
      adminADevice2,
      created,
      entries,
      expectError,
      fixtureAdmin,
      metadata,
      ownerA,
      ownerADevice2,
      ownerB,
      ownerC,
      platform,
      playerA,
      rpc,
      staffA,
      teams: TEAMS,
      waitForSubscription,
    })
    : null;
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
  storySummary = {
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
    r4c,
    r4d,
    refereeAssignments,
    rounds: 5,
    status: "PASS",
  };
} finally {
  if (platform) {
    if (CONFIGURATION_EXTENSION && staffA) {
      await bestEffort("cancel-active-wave5a-drafts", () => cleanupCompetitionConfigurationStaging({
        actor: staffA,
        metadata,
        rpc,
        state: configurationStagingState,
      }));
    }
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
    if (PRIVATE_BETA_EXTENSION) {
      await bestEffort("revoke-team-beta-bundle", async () => {
        if (!created.teamBundleId) return;
        await revokeBetaBundle(platform, ownerA, "TEAM", TEAMS[0].groupId, created.teamBundleId);
        created.teamBundleId = null;
      });
      await bestEffort("revoke-expired-team-beta-bundle", async () => {
        if (!created.expiredTeamBundleId) return;
        await revokeBetaBundle(platform, ownerB, "TEAM", TEAMS[1].groupId, created.expiredTeamBundleId);
        created.expiredTeamBundleId = null;
      });
      await bestEffort("revoke-club-beta-bundle", async () => {
        if (!created.betaBundleId || !created.clubId) return;
        await revokeBetaBundle(platform, clubOwner.client, "CLUB", created.clubId, created.betaBundleId);
        created.betaBundleId = null;
      });
      if (initialFlagState) {
        if (CONFIGURATION_EXTENSION && initialFlagState.configuration) {
          await bestEffort("restore-wave5a", () => setConfigurationFlags(platform, {
            configurationCenterEnabled: initialFlagState.configuration.configurationCenterEnabled,
            wizardV2Enabled: initialFlagState.configuration.wizardV2Enabled,
          }, "Wave 5A staging restore"));
        }
        await bestEffort("restore-private-beta", () => setBetaFlags(platform, {
          creationEnabled: initialFlagState.beta.creationEnabled,
          enabled: initialFlagState.beta.enabled,
          publicDiscoveryEnabled: initialFlagState.beta.publicDiscoveryEnabled,
        }, "League Private Beta staging restore"));
        await bestEffort("restore-r4d", () => setOperationalExceptionsFlags(
          platform,
          Object.fromEntries(OPERATIONAL_EXCEPTIONS_FLAG_KEYS.map((key) => [
            key,
            initialFlagState.operationalExceptions[key],
          ])),
          "League Private Beta staging restore",
        ));
        await bestEffort("restore-r4c", () => setMatchOperationsFlags(
          platform,
          Object.fromEntries(MATCH_OPERATIONS_FLAG_KEYS.map((key) => [
            key,
            initialFlagState.matchOperations[key],
          ])),
          "League Private Beta staging restore",
        ));
      }
    }
    if (initialFlagState) {
      await bestEffort("restore-r4b", () => setScheduleFlags(platform, {
        canonicalFixtureCreationEnabled: initialFlagState.scheduling.canonicalFixtureCreationEnabled,
        editingEnabled: initialFlagState.scheduling.editingEnabled,
        foundationEnabled: initialFlagState.scheduling.foundationEnabled,
        generationEnabled: initialFlagState.scheduling.generationEnabled,
        publicCalendarEnabled: initialFlagState.scheduling.publicCalendarEnabled,
        publicationEnabled: initialFlagState.scheduling.publicationEnabled,
      }, "R4B staging restore"));
      await bestEffort("restore-r4a", () => setParticipationFlags(platform, {
        delegatesEnabled: initialFlagState.participation.delegatesEnabled,
        foundationEnabled: initialFlagState.participation.foundationEnabled,
        publicRegistrationEnabled: initialFlagState.participation.publicRegistrationEnabled,
        registrationEnabled: initialFlagState.participation.registrationEnabled,
        rostersEnabled: initialFlagState.participation.rostersEnabled,
        schedulePreferencesEnabled: initialFlagState.participation.schedulePreferencesEnabled,
      }, "R4B staging restore"));
    }
    if (created.clubId) await bestEffort("archive-club", () => archiveClub(platform, created.clubId));
    if (initialFlagState) {
      await bestEffort("restore-r3", () => setRefereeFlags(
        platform,
        Object.fromEntries(REFEREE_FLAG_KEYS.map((key) => [key, initialFlagState.referee[key]])),
        "R4B staging restore",
      ));
      await bestEffort("restore-r2", () => setClubFlags(platform, {
        competitionOrganizerEnabled: initialFlagState.clubFoundation.competitionOrganizerEnabled,
        foundationEnabled: initialFlagState.clubFoundation.foundationEnabled,
        publicProfilesEnabled: initialFlagState.clubFoundation.publicProfilesEnabled,
        selfServiceCreationEnabled: initialFlagState.clubFoundation.selfServiceCreationEnabled,
        teamRelationshipsEnabled: initialFlagState.clubFoundation.teamRelationshipsEnabled,
      }, "R4B staging restore"));
      await bestEffort("restore-r1", () => setCompetitionFlags(platform, {
        contextBindingEnabled: initialFlagState.competition.contextBindingEnabled,
        creationEnabled: initialFlagState.competition.creationEnabled,
        foundationEnabled: initialFlagState.competition.foundationEnabled,
      }, "R4B staging restore"));
    }
    if (PRIVATE_BETA_EXTENSION) {
      await bestEffort("private-beta-cleanup-readback", async () => {
        const [
          beta,
          competition,
          clubFoundation,
          participationFlags,
          schedulingFlags,
          matchOperations,
          operationalExceptions,
          referee,
          discipline,
          configurationControl,
          activeBundles,
          competitionRow,
        ] = await Promise.all([
          betaFlags(platform),
          rpc(platform, "get_pachanga_platform_competition_foundation_v1", { page_offset: 0, page_size: 1 }),
          rpc(platform, "get_pachanga_club_foundation_flags_v1"),
          rpc(platform, "get_pachanga_league_participation_flags_v1"),
          scheduleFlags(platform),
          rpc(platform, "get_pachanga_league_match_operations_flags_v1"),
          rpc(platform, "get_pachanga_league_operational_exceptions_flags_v1"),
          rpc(platform, "get_pachanga_referee_foundation_flags_v1"),
          rpc(platform, "get_pachanga_competition_discipline_flags_v1"),
          CONFIGURATION_EXTENSION
            ? rpc(platform, "get_pachanga_platform_competition_configuration_v1")
            : Promise.resolve(null),
          fixtureAdmin.from("pachanga_competition_entitlement_grants")
            .select("bundle_id,organizer_group_id,organizer_club_id")
            .eq("program_key", "LEAGUE_PRIVATE_BETA_V1")
            .eq("status", "active"),
          created.competitionId
            ? fixtureAdmin.from("pachanga_competitions").select("status").eq("id", created.competitionId).single()
            : Promise.resolve({ data: null, error: null }),
        ]);
        if (activeBundles.error) throw activeBundles.error;
        if (competitionRow.error) throw competitionRow.error;
        const qaOrganizerIds = new Set([
          created.clubId,
          TEAMS[0].groupId,
          TEAMS[1].groupId,
        ].filter(Boolean));
        cleanupReadback = {
          activeQaBundles: activeBundles.data.filter((bundle) => (
            qaOrganizerIds.has(bundle.organizer_group_id) || qaOrganizerIds.has(bundle.organizer_club_id)
          )).length,
          activeQaConfigurationDrafts: CONFIGURATION_EXTENSION
            ? configurationControl.drafts.filter((draft) => (
              configurationStagingState.configurationDraftIds.includes(draft.id)
              && ["draft", "validated"].includes(draft.status)
            )).length
            : 0,
          beta,
          clubFoundation,
          competition: competition.flags,
          competitionStatus: competitionRow.data?.status ?? null,
          configuration: configurationControl?.flags ?? null,
          matchOperations,
          operationalExceptions,
          referee,
          discipline,
          participation: participationFlags,
          scheduling: schedulingFlags,
        };
      });
    }
  }
  for (const [supabase, channel] of channels) await bestEffort("remove-channel", () => supabase.removeChannel(channel));
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", () => supabase.realtime.disconnect());
  }
  for (const userId of created.ephemeralUserIds) {
    await bestEffort("delete-ephemeral-user", () => fixtureAdmin.auth.admin.deleteUser(userId));
  }
}

assert.equal(completed, true, "R4B staging story did not complete");
if (PRIVATE_BETA_EXTENSION) {
  assert.ok(cleanupReadback, "League Private Beta cleanup readback is required");
  assert.ok(initialFlagState, "League Private Beta initial flag snapshot is required");
  assert.equal(cleanupReadback.activeQaBundles, 0);
  if (CONFIGURATION_EXTENSION) assert.equal(cleanupReadback.activeQaConfigurationDrafts, 0);
  assert.equal(cleanupReadback.competitionStatus, "cancelled");
  for (const [label, actual, expected] of [
    ["beta", cleanupReadback.beta, initialFlagState.beta],
    ["competition", cleanupReadback.competition, initialFlagState.competition],
    ["clubFoundation", cleanupReadback.clubFoundation, initialFlagState.clubFoundation],
    ["participation", cleanupReadback.participation, initialFlagState.participation],
    ["scheduling", cleanupReadback.scheduling, initialFlagState.scheduling],
    ["matchOperations", cleanupReadback.matchOperations, initialFlagState.matchOperations],
    ["operationalExceptions", cleanupReadback.operationalExceptions, initialFlagState.operationalExceptions],
    ["referee", cleanupReadback.referee, initialFlagState.referee],
    ["discipline", cleanupReadback.discipline, initialFlagState.discipline],
    ...(CONFIGURATION_EXTENSION
      ? [["configuration", cleanupReadback.configuration, initialFlagState.configuration]]
      : []),
  ]) {
    for (const [key, value] of Object.entries(expected)) {
      if (typeof value === "boolean") {
        assert.equal(actual[key], value, `${label}.${key} must match the initial snapshot`);
      }
    }
  }
}
console.log(JSON.stringify({
  ...storySummary,
  cleanupReadback: PRIVATE_BETA_EXTENSION ? {
    activeQaBundles: cleanupReadback.activeQaBundles,
    activeQaConfigurationDrafts: cleanupReadback.activeQaConfigurationDrafts,
    competitionStatus: cleanupReadback.competitionStatus,
    flags: "restored_initial",
  } : null,
  competitionConfiguration: CONFIGURATION_EXTENSION ? {
    advancedRuleRevisionId: configurationStagingState.advancedRuleRevisionId,
    configurationDrafts: configurationStagingState.configurationDraftIds.length,
    futureRuleRevisionId: configurationStagingState.futureRuleRevisionId,
    status: "PASS",
  } : null,
}));
