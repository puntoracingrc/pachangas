import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const envSpec = {
  confirmation: ["TOURNAMENT_STAGING_CONFIRM", process.env.TOURNAMENT_STAGING_CONFIRM],
  previewUrl: ["TOURNAMENT_STAGING_PREVIEW_URL", process.env.TOURNAMENT_STAGING_PREVIEW_URL || null],
  projectRef: ["TOURNAMENT_STAGING_PROJECT_REF", process.env.TOURNAMENT_STAGING_PROJECT_REF],
  publishableKey: ["TOURNAMENT_STAGING_PUBLISHABLE_KEY", process.env.TOURNAMENT_STAGING_PUBLISHABLE_KEY],
  serviceRoleKey: ["TOURNAMENT_STAGING_SERVICE_ROLE_KEY", process.env.TOURNAMENT_STAGING_SERVICE_ROLE_KEY],
  url: ["TOURNAMENT_STAGING_URL", process.env.TOURNAMENT_STAGING_URL],
};

for (const [key, [variableName, value]] of Object.entries(envSpec)) {
  if (key !== "previewUrl" && !value) throw new Error(`${variableName} is required`);
}

const env = Object.fromEntries(
  Object.entries(envSpec).map(([key, [, value]]) => [key, value]),
);

function isBrowserPublicKey(value) {
  if (/^sb_publishable_/i.test(value)) return true;
  if (!/^eyJ/i.test(value)) return false;
  try {
    const payload = JSON.parse(Buffer.from(value.split(".")[1], "base64url").toString("utf8"));
    return payload.role === "anon";
  } catch {
    return false;
  }
}

if (!isBrowserPublicKey(env.publishableKey)
    || /^sb_secret_/i.test(env.publishableKey)
    || env.publishableKey === env.serviceRoleKey) {
  throw new Error("TOURNAMENT_STAGING_BROWSER_KEY_REQUIRED");
}

const productionRef = "qonbngfrnrqgmxbdfbea";
const actualRef = new URL(env.url).hostname.split(".")[0];
if (
  env.confirmation !== "TOURNAMENT_STAGING_ONLY"
  || actualRef !== env.projectRef
  || actualRef === productionRef
) throw new Error("TOURNAMENT_STAGING_PRODUCTION_TARGET_FORBIDDEN");
if (env.previewUrl && /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)) {
  throw new Error("TOURNAMENT_STAGING_PREVIEW_PRODUCTION_TARGET_FORBIDDEN");
}

const runId = randomUUID().slice(0, 8);
const password = `R6a-${randomUUID()}-Qa!`;
let fixtureServerSequence = Date.now() * 1000;
const clients = [];
const channels = [];
const created = {
  bundles: [],
  competitions: [],
  users: [],
};
const report = {
  cleanup: "EPHEMERAL_BRANCH_TEARDOWN_REQUIRED",
  histories: {},
  negatives: {},
  projectRef: env.projectRef,
  realtime: null,
  tournamentMatches: null,
};

const FLAGS_ID = "00000000-0000-0000-0000-00000000c6a1";
const FOUNDATION_FLAGS_ID = "00000000-0000-0000-0000-00000000c001";
const CLUB_FLAGS_ID = "00000000-0000-0000-0000-00000000c101";
const TOURNAMENT_FLAG_KEYS = [
  "foundationEnabled",
  "privateBetaEnabled",
  "creationEnabled",
  "drawEnabled",
  "automaticEnabled",
  "manualEnabled",
  "hybridEnabled",
  "publishEnabled",
];
const FOUNDATION_FLAG_KEYS = [
  "foundationEnabled",
  "creationEnabled",
  "contextBindingEnabled",
];
const CLUB_FLAG_KEYS = [
  "competitionOrganizerEnabled",
  "foundationEnabled",
  "publicProfilesEnabled",
  "selfServiceCreationEnabled",
  "teamRelationshipsEnabled",
];
const UNTOUCHED_TABLES = [
  "pachanga_individual_rating_evidence",
  "pachanga_player_rating_snapshots",
  "pachanga_achievement_grants",
  "pachanga_reward_grants",
  "pachanga_team_cosmetic_inventory",
  "pachanga_competition_late_arrival_incidents",
  "pachanga_competition_no_show_incidents",
  "pachanga_stripe_webhook_events",
];

function client(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 40 } },
  });
}

const fixtureAdmin = client(env.serviceRoleKey);
const nextFixtureServerSequence = () => {
  fixtureServerSequence += 1;
  return fixtureServerSequence;
};
const metadata = (surface = "tournament-staging") => ({
  clientVersion: "6.0.0+r6a-staging",
  installedMode: "standalone",
  serviceWorkerVersion: "6.0.0+r6a-staging",
  sessionId: `r6a-${runId}`,
  surface,
});

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw new Error(`${name} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  return result.data;
}

function rawCommand(supabase, aggregateId, expectedRevision, action, payload = {}, operationId = randomUUID(), surface = "tournament-staging") {
  return supabase.rpc("command_pachanga_tournament_draw_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata(surface),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function command(supabase, state, action, payload = {}, options = {}) {
  const result = await rawCommand(
    supabase,
    state.id,
    state.revision,
    action,
    payload,
    options.operationId,
    options.surface,
  );
  if (result.error) {
    throw new Error(`${action}@${state.revision} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  }
  state.revision = result.data.confirmedRevision;
  return result.data;
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean)
    .join(" ");
}

function expectError(result, pattern, label) {
  assert.ok(result.error, `${label}: expected an error`);
  assert.match(diagnostic(result), pattern, `${label}: ${diagnostic(result)}`);
  return diagnostic(result);
}

async function bestEffort(label, action) {
  try {
    await action();
  } catch (error) {
    console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error);
  }
}

async function createAccount(label) {
  const account = {
    email: `r6a-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
  };
  const result = await fixtureAdmin.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "TOURNAMENT_FOUNDATION_DRAW_V1", runId },
  });
  if (result.error) throw result.error;
  created.users.push(account.id);
  return account;
}

async function signIn(account, label) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`R6A_STAGING_SIGN_IN_FAILED:${label}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  clients.push(supabase);
  return supabase;
}

async function ensurePlatformOwner(account) {
  const access = await fixtureAdmin.rpc("get_pachanga_platform_access_service_v1", {
    target_user_id: account.id,
  });
  if (access.error) throw access.error;
  if (access.data) return;
  const result = await fixtureAdmin.rpc("bootstrap_pachanga_platform_owner_v1", {
    operation_id: randomUUID(),
    reason: "R6A isolated staging platform fixture",
    target_user_id: account.id,
  });
  if (result.error) throw result.error;
  assert.equal(result.data.role, "platform_owner");
}

async function createGroup(owner, name, suffix) {
  const row = {
    id: randomUUID(),
    name: `${name} ${runId}`,
    owner_id: owner.id,
    payload: { matches: [], players: [], qaFixture: "R6A_STAGING", runId },
    team_code: `R6A-${runId}-${suffix}`.toUpperCase(),
  };
  const insert = await fixtureAdmin.from("pachanga_groups").insert(row);
  if (insert.error) throw insert.error;
  const membership = await fixtureAdmin.from("pachanga_group_members").insert({
    display_name: `${name} Owner`,
    group_id: row.id,
    role: "owner",
    user_id: owner.id,
  });
  if (membership.error) throw membership.error;
  return row;
}

async function createClub(ownerClient, platformClient, name) {
  const id = randomUUID();
  const createdClub = await ownerClient.rpc("command_pachanga_club_foundation_v1", {
    aggregate_id: id,
    client_metadata: metadata("tournament-staging-club-fixture"),
    command_action: "club.create",
    command_payload: {
      clubType: "INDEPENDENT_ORGANIZER",
      countryCode: "ES",
      municipality: "Barcelona",
      name: `${name} ${runId}`,
      province: "Barcelona",
      reason: `R6A canonical Club fixture ${runId}`,
      slug: `${name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${runId}`,
      visibility: "private",
    },
    expected_revision: 0,
    operation_id: randomUUID(),
  });
  if (createdClub.error) throw createdClub.error;
  assert.equal(createdClub.data.snapshot.club.id, id);
  assert.equal(createdClub.data.snapshot.club.operationalStatus, "draft");

  const consentedClub = await ownerClient.rpc("command_pachanga_publication_consent_v1", {
    client_metadata: metadata("tournament-staging-club-consent"),
    confirmations: {
      informationCorrect: true,
      representationAuthorized: true,
    },
    expected_revision: createdClub.data.confirmedRevision,
    operation_id: randomUUID(),
    subject_id: id,
    subject_kind: "CLUB",
  });
  if (consentedClub.error) throw consentedClub.error;
  assert.ok(consentedClub.data.confirmedRevision > createdClub.data.confirmedRevision);

  const submittedClub = await ownerClient.rpc("command_pachanga_club_foundation_v1", {
    aggregate_id: id,
    client_metadata: metadata("tournament-staging-club-review"),
    command_action: "club.review.submit",
    command_payload: {
      reason: `R6A canonical Club review ${runId}`,
    },
    expected_revision: consentedClub.data.confirmedRevision,
    operation_id: randomUUID(),
  });
  if (submittedClub.error) throw submittedClub.error;
  assert.equal(submittedClub.data.snapshot.club.id, id);
  assert.equal(submittedClub.data.snapshot.club.operationalStatus, "pending_review");

  const activatedClub = await platformClient.rpc("command_pachanga_club_platform_v1", {
    aggregate_id: id,
    client_metadata: metadata("tournament-staging-club-activation"),
    command_action: "club.status.set",
    command_payload: {
      reason: `R6A canonical Club activation ${runId}`,
      status: "active",
    },
    expected_revision: submittedClub.data.confirmedRevision,
    operation_id: randomUUID(),
  });
  if (activatedClub.error) throw activatedClub.error;
  assert.equal(activatedClub.data.snapshot.club.id, id);
  assert.equal(activatedClub.data.snapshot.club.operationalStatus, "active");
  return { id };
}

async function relateClubTeams(clubId, teams, actorId) {
  const now = new Date().toISOString();
  const rows = teams.map((team) => ({
    club_id: clubId,
    created_by: actorId,
    group_id: team.id,
    initiated_by: "CLUB",
    reason: `R6A staging ${runId}`,
    relationship_type: "AFFILIATED",
    server_sequence: nextFixtureServerSequence(),
    started_at: now,
    status: "active",
  }));
  const result = await fixtureAdmin.from("pachanga_club_team_relationships").insert(rows);
  if (result.error) throw result.error;
}

async function tournamentFlags(supabase) {
  return (await rpc(supabase, "get_pachanga_tournament_flags_v1")).flags;
}

async function clubFlags(supabase) {
  return rpc(supabase, "get_pachanga_club_foundation_flags_v1");
}

async function setClubFlags(platformClient, values, reason) {
  const current = await clubFlags(platformClient);
  const result = await platformClient.rpc("command_pachanga_club_platform_v1", {
    aggregate_id: CLUB_FLAGS_ID,
    client_metadata: metadata("tournament-staging-club-flags"),
    command_action: "club_flags.set",
    command_payload: { ...values, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function setTournamentFlags(platform, values, reason) {
  const current = await tournamentFlags(platform);
  const result = await platform.rpc("command_pachanga_tournament_platform_v1", {
    aggregate_id: FLAGS_ID,
    client_metadata: metadata("tournament-staging-flags"),
    command_action: "tournament.flags.set",
    command_payload: { ...values, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data.snapshot;
}

async function foundationFlags(platform) {
  return (await rpc(platform, "get_pachanga_platform_competition_foundation_v1", {
    page_offset: 0,
    page_size: 1,
  })).flags;
}

async function setFoundationFlags(platform, values, reason) {
  const current = await foundationFlags(platform);
  const result = await platform.rpc("command_pachanga_competition_platform_v1", {
    aggregate_id: FOUNDATION_FLAGS_ID,
    client_metadata: metadata("tournament-staging-foundation-flags"),
    command_action: "foundation_flags.set",
    command_payload: { ...values, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function organizerModel(ownerClient, kind, organizerId) {
  const model = await rpc(ownerClient, "get_pachanga_tournament_flags_v1");
  const organizer = model.organizers.find((candidate) => (
    candidate.kind === kind && candidate.id === organizerId
  ));
  assert.ok(organizer, `${kind} organizer ${organizerId} is missing`);
  return organizer;
}

async function grantBundle(platform, ownerClient, kind, organizerId, maxTeams = 16) {
  const organizer = await organizerModel(ownerClient, kind, organizerId);
  const result = await platform.rpc("command_pachanga_tournament_platform_v1", {
    aggregate_id: organizerId,
    client_metadata: metadata("tournament-staging-grant"),
    command_action: "tournament.beta_bundle.grant",
    command_payload: {
      expiresAt: "2027-12-31T23:59:59Z",
      maxTeams,
      organizerKind: kind,
      reason: `R6A staging grant ${runId}`,
    },
    expected_revision: organizer.organizerRevision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  const bundle = { bundleId: result.data.snapshot.bundleId, kind, organizerId, ownerClient };
  created.bundles.push(bundle);
  return bundle;
}

async function revokeBundle(platform, bundle) {
  const organizer = await organizerModel(bundle.ownerClient, bundle.kind, bundle.organizerId);
  const result = await platform.rpc("command_pachanga_tournament_platform_v1", {
    aggregate_id: bundle.organizerId,
    client_metadata: metadata("tournament-staging-cleanup"),
    command_action: "tournament.beta_bundle.revoke",
    command_payload: {
      bundleId: bundle.bundleId,
      organizerKind: bundle.kind,
      reason: `R6A staging cleanup ${runId}`,
    },
    expected_revision: organizer.organizerRevision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
}

async function createTournament(ownerClient, kind, organizerId, options) {
  const organizer = await organizerModel(ownerClient, kind, organizerId);
  const result = await rawCommand(
    ownerClient,
    organizerId,
    organizer.organizerRevision,
    "tournament.create",
    {
      description: `R6A authenticated staging ${runId}`,
      drawMode: options.mode,
      drawTarget: options.target,
      groupCount: options.groupCount,
      modality: "FUTBOL_7",
      name: `${options.name} ${runId}`,
      organizerKind: kind,
      participantCap: options.cap,
      qualifiersPerGroup: options.qualifiers ?? 2,
      reason: `R6A staging create ${runId}`,
      slug: `${options.slug}-${runId}`,
    },
    randomUUID(),
    "tournament-staging-create",
  );
  if (result.error) throw result.error;
  const state = {
    id: result.data.snapshot.competition.id,
    ownerClient,
    published: false,
    revision: result.data.confirmedRevision,
  };
  created.competitions.push(state);
  return state;
}

async function readSnapshot(supabase, competitionId) {
  return rpc(supabase, "get_pachanga_tournament_snapshot_v1", { competition_id: competitionId });
}

async function readDesk(supabase, competitionId, planId) {
  return rpc(supabase, "get_pachanga_tournament_draw_desk_v1", {
    competition_id: competitionId,
    draw_plan_id: planId,
  });
}

async function inviteTeams(state, teams, teamClients, { duplicateFirst = false } = {}) {
  const entries = [];
  for (const team of teams) {
    const response = await command(state.ownerClient, state, "participant.invite", {
      reason: `R6A staging invitation ${runId}`,
      teamId: team.id,
    });
    entries.push(response.snapshot.entries.find((entry) => entry.teamId === team.id && entry.status === "invited"));
  }
  assert.ok(entries.every(Boolean));
  if (duplicateFirst) {
    const duplicate = await rawCommand(state.ownerClient, state.id, state.revision, "participant.invite", {
      reason: "R6A duplicate participant negative",
      teamId: teams[0].id,
    });
    expectError(duplicate, /TOURNAMENT_CONFLICT|duplicate|unique/i, "duplicate participant");
    report.negatives.duplicateParticipant = true;
  }
  return async () => {
    for (let index = 0; index < entries.length; index += 1) {
      const response = await command(teamClients[index], state, "participant.accept", {
        entryId: entries[index].id,
        reason: `R6A staging accepted ${runId}`,
      });
      if (index === 0 && entries.length > 1) {
        assert.equal(response.snapshot.entries.some((entry) => entry.status === "invited"), false);
      }
    }
    return entries;
  };
}

async function createPlan(state, options, invalidRuleRevision = false) {
  const snapshot = await readSnapshot(state.ownerClient, state.id);
  const context = snapshot.authoringContext;
  assert.ok(context?.editionId && context.stageId && context.ruleRevisionId);
  if (invalidRuleRevision) {
    const invalid = await rawCommand(state.ownerClient, state.id, state.revision, "draw_plan.create", {
      editionId: context.editionId,
      groupCount: options.groupCount,
      mode: options.mode,
      qualifiersPerGroup: 2,
      reason: "R6A stale rule negative",
      ruleRevisionId: randomUUID(),
      slotCount: options.slotCount,
      stageId: context.stageId,
      targetType: options.target,
    });
    expectError(invalid, /DRAW_PLAN_SCOPE_INVALID/i, "stale RuleRevision");
    report.negatives.ruleRevisionStale = true;
  }
  const response = await command(state.ownerClient, state, "draw_plan.create", {
    editionId: context.editionId,
    groupCount: options.groupCount,
    mode: options.mode,
    qualifiersPerGroup: 2,
    reason: `R6A staging plan ${runId}`,
    ruleRevisionId: context.ruleRevisionId,
    slotCount: options.slotCount,
    stageId: context.stageId,
    targetType: options.target,
  });
  const plan = response.snapshot.drawPlans.at(-1);
  assert.ok(plan?.id);
  return plan.id;
}

async function freeze(state, planId) {
  return command(state.ownerClient, state, "participants.freeze", {
    planId,
    reason: `R6A staging freeze ${runId}`,
  });
}

async function addPots(state, planId, entryIds, potCount = 4) {
  const pots = Array.from({ length: potCount }, () => []);
  entryIds.forEach((entryId, index) => pots[index % potCount].push(entryId));
  for (let index = 0; index < pots.length; index += 1) {
    await command(state.ownerClient, state, "draw_pot.create", {
      capacity: pots[index].length,
      entryIds: pots[index],
      label: `Bombo ${index + 1}`,
      planId,
      potNumber: index + 1,
      reason: `R6A staging pots ${runId}`,
      seedingPolicy: "MANUAL",
    });
  }
}

async function generate(state, planId, seed, action = "draw.generate") {
  return command(state.ownerClient, state, action, {
    planId,
    publicSeed: seed,
    reason: `R6A staging deterministic draw ${runId}`,
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
}

async function invariantCounts() {
  const result = {};
  for (const table of UNTOUCHED_TABLES) {
    const query = await fixtureAdmin.from(table).select("*", { count: "exact", head: true });
    if (query.error) throw query.error;
    result[table] = query.count;
  }
  return result;
}

async function waitForRealtime(organizerClient, competitionId) {
  const channel = organizerClient.channel(`r6a-${runId}-${competitionId}`);
  channels.push(channel);
  let rejectEvent;
  const eventPromise = new Promise((resolve, reject) => {
    rejectEvent = reject;
    channel.on("postgres_changes", {
      event: "INSERT",
      filter: `competition_id=eq.${competitionId}`,
      schema: "public",
      table: "pachanga_tournament_invalidations",
    }, (payload) => resolve(payload.new));
  });
  const readyPromise = new Promise((resolve, reject) => {
    const readyTimer = setTimeout(() => {
      const error = new Error("R6A_REALTIME_SUBSCRIBE_TIMEOUT");
      rejectEvent(error);
      reject(error);
    }, 15_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(readyTimer);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(readyTimer);
        const error = new Error(`R6A_REALTIME_${status}`);
        rejectEvent(error);
        reject(error);
      }
    });
  });
  await readyPromise;
  return {
    event: async () => {
      let timeout;
      try {
        return await Promise.race([
          eventPromise,
          new Promise((_, reject) => {
            timeout = setTimeout(() => reject(new Error("R6A_REALTIME_TIMEOUT")), 15_000);
          }),
        ]);
      } finally {
        clearTimeout(timeout);
      }
    },
  };
}

let platform;
let organizerOwner;
let clubOwner;
let initialTournamentFlags;
let initialFoundationFlags;
let initialClubFlags;
let tournamentFlagsChanged = false;
let foundationFlagsChanged = false;
let clubFlagsChanged = false;

try {
  const platformAccount = await createAccount("platform");
  const organizerAccount = await createAccount("organizer");
  const clubAccount = await createAccount("club-owner");
  const outsiderAccount = await createAccount("outsider");
  const teamAccounts = [];
  for (let index = 0; index < 16; index += 1) teamAccounts.push(await createAccount(`team-${index + 1}`));

  await ensurePlatformOwner(platformAccount);
  platform = await signIn(platformAccount, "platform");
  organizerOwner = await signIn(organizerAccount, "organizer");
  const organizerDevice2 = await signIn(organizerAccount, "organizer-device-2");
  clubOwner = await signIn(clubAccount, "club-owner");
  const outsider = await signIn(outsiderAccount, "outsider");
  const teamClients = [];
  for (let index = 0; index < teamAccounts.length; index += 1) {
    teamClients.push(await signIn(teamAccounts[index], `team-${index + 1}`));
  }

  initialClubFlags = await clubFlags(platform);
  const requiredClub = {
    competitionOrganizerEnabled: initialClubFlags.competitionOrganizerEnabled,
    foundationEnabled: true,
    publicProfilesEnabled: initialClubFlags.publicProfilesEnabled,
    selfServiceCreationEnabled: true,
    teamRelationshipsEnabled: true,
  };
  if (CLUB_FLAG_KEYS.some((key) => initialClubFlags[key] !== requiredClub[key])) {
    await setClubFlags(platform, requiredClub, `R6A staging Club prerequisite ${runId}`);
    clubFlagsChanged = true;
  }

  const organizerTeam = await createGroup(organizerAccount, "R6A Organizer", "ORG");
  const outsiderTeam = await createGroup(outsiderAccount, "R6A No Grant", "OUT");
  const teams = [];
  for (let index = 0; index < teamAccounts.length; index += 1) {
    teams.push(await createGroup(teamAccounts[index], `R6A Team ${index + 1}`, `T${String(index + 1).padStart(2, "0")}`));
  }
  const organizerClub = await createClub(clubOwner, platform, "R6A Organizer Club");
  const sharedClub = await createClub(clubOwner, platform, "R6A Shared Club");
  await relateClubTeams(sharedClub.id, teams.slice(0, 2), clubAccount.id);

  initialFoundationFlags = await foundationFlags(platform);
  const requiredFoundation = {
    contextBindingEnabled: true,
    creationEnabled: true,
    foundationEnabled: true,
  };
  if (FOUNDATION_FLAG_KEYS.some((key) => initialFoundationFlags[key] !== requiredFoundation[key])) {
    await setFoundationFlags(platform, requiredFoundation, `R6A staging prerequisite ${runId}`);
    foundationFlagsChanged = true;
  }

  initialTournamentFlags = await tournamentFlags(platform);
  await setTournamentFlags(platform, Object.fromEntries(TOURNAMENT_FLAG_KEYS.map((key) => [key, true])), `R6A staging private beta ${runId}`);
  tournamentFlagsChanged = true;

  const enabledFlags = await tournamentFlags(platform);
  for (const key of TOURNAMENT_FLAG_KEYS) assert.equal(enabledFlags[key], true, key);
  assert.equal(enabledFlags.publicDiscoveryEnabled, false);
  assert.equal(enabledFlags.matchGenerationEnabled, false);
  assert.equal(enabledFlags.bracketProgressionEnabled, false);

  const noGrantOrganizer = await organizerModel(outsider, "TEAM", outsiderTeam.id);
  const noGrant = await rawCommand(outsider, outsiderTeam.id, noGrantOrganizer.organizerRevision, "tournament.create", {
    drawMode: "PURE_RANDOM",
    drawTarget: "GROUP_ASSIGNMENT",
    groupCount: 2,
    name: `R6A Forbidden ${runId}`,
    organizerKind: "TEAM",
    participantCap: 4,
    reason: "R6A no grant negative",
    slug: `r6a-forbidden-${runId}`,
  });
  expectError(noGrant, /TOURNAMENT_PRIVATE_BETA_GRANT_REQUIRED/i, "organizer without grant");
  report.negatives.organizerWithoutGrant = true;

  const beforeInvariants = await invariantCounts();
  await grantBundle(platform, organizerOwner, "TEAM", organizerTeam.id, 16);
  await grantBundle(platform, clubOwner, "CLUB", organizerClub.id, 16);

  const clubTournament = await createTournament(clubOwner, "CLUB", organizerClub.id, {
    cap: 8,
    groupCount: 2,
    mode: "PURE_RANDOM",
    name: "R6A Club Tournament",
    slug: "r6a-club-tournament",
    target: "GROUP_ASSIGNMENT",
  });
  await command(clubOwner, clubTournament, "tournament.cancel", { reason: `R6A Club cleanup ${runId}` });
  report.histories.clubOrganizer = true;

  const main = await createTournament(organizerOwner, "TEAM", organizerTeam.id, {
    cap: 16,
    groupCount: 4,
    mode: "SEEDED_POTS",
    name: "R6A Automatic",
    slug: "r6a-automatic",
    target: "GROUP_ASSIGNMENT",
  });
  const foreignRead = await outsider.rpc("get_pachanga_tournament_snapshot_v1", { competition_id: main.id });
  expectError(foreignRead, /TOURNAMENT_READ_FORBIDDEN/i, "foreign Tournament read");
  report.negatives.foreignDraft = true;

  const acceptMain = await inviteTeams(main, teams, teamClients);
  const realtime = await waitForRealtime(organizerOwner, main.id);
  const mainEntries = await acceptMain();
  const invalidation = await realtime.event();
  const converged = await readSnapshot(organizerDevice2, main.id);
  assert.ok(converged.revision >= Number(invalidation.revision));
  report.realtime = { canonicalRefetch: true, invalidationOnly: true, revision: Number(invalidation.revision) };

  const mainPlanId = await createPlan(main, {
    groupCount: 4,
    mode: "SEEDED_POTS",
    target: "GROUP_ASSIGNMENT",
  });
  await freeze(main, mainPlanId);

  const absentPot = await rawCommand(organizerOwner, main.id, main.revision, "draw_pot.create", {
    capacity: 1,
    entryIds: [randomUUID()],
    label: "Invalid",
    planId: mainPlanId,
    potNumber: 63,
    reason: "R6A absent participant negative",
    seedingPolicy: "MANUAL",
  });
  expectError(absentPot, /DRAW_POT_ENTRY_INVALID/i, "participant absent from freeze");
  report.negatives.participantAbsent = true;

  const overCapacity = await rawCommand(organizerOwner, main.id, main.revision, "draw_pot.create", {
    capacity: 1,
    entryIds: mainEntries.slice(0, 2).map((entry) => entry.id),
    label: "Over capacity",
    planId: mainPlanId,
    potNumber: 62,
    reason: "R6A pot capacity negative",
    seedingPolicy: "MANUAL",
  });
  expectError(overCapacity, /capacity|check constraint|pachanga_competition_draw_pots/i, "pot overcapacity");
  report.negatives.potOvercapacity = true;

  await addPots(main, mainPlanId, mainEntries.map((entry) => entry.id));
  await command(organizerOwner, main, "draw_constraint.create", {
    constraintType: "SAME_CLUB_AVOIDANCE",
    parameters: {},
    planId: mainPlanId,
    publicAttribution: true,
    reason: "R6A same Club hard avoid",
    scope: "DRAW",
    strength: "HARD",
    weight: 100,
  });

  const invalidSeed = await rawCommand(organizerOwner, main.id, main.revision, "draw.generate", {
    planId: mainPlanId,
    publicSeed: "bad seed with spaces",
    reason: "R6A invalid seed negative",
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
  expectError(invalidSeed, /DRAW_SEED_INVALID/i, "invalid public seed");
  report.negatives.invalidSeed = true;

  const forged = await rawCommand(organizerOwner, main.id, main.revision, "draw.generate", {
    placements: [],
    planId: mainPlanId,
    publicSeed: "R6A-STAGING-FORGED-2026",
    reason: "R6A forged result negative",
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
  expectError(forged, /TOURNAMENT_SERVER_FIELDS_FORBIDDEN/i, "forged client result");
  report.negatives.clientResultForged = true;

  const seedA = "R6A-STAGING-CANONICAL-2026";
  await generate(main, mainPlanId, seedA);
  let desk = await readDesk(organizerOwner, main.id, mainPlanId);
  const firstChecksum = desk.plan.revisionSnapshot.resultChecksum;
  const firstGroups = new Map(desk.plan.placements.map((placement) => [placement.entryId, placement.groupNumber]));
  assert.notEqual(firstGroups.get(mainEntries[0].id), firstGroups.get(mainEntries[1].id));

  await generate(main, mainPlanId, seedA, "draw.regenerate");
  desk = await readDesk(organizerOwner, main.id, mainPlanId);
  assert.equal(desk.plan.revisionSnapshot.resultChecksum, firstChecksum);
  report.histories.sameSeed = true;

  await generate(main, mainPlanId, "R6A-STAGING-DIFFERENT-2026", "draw.regenerate");
  desk = await readDesk(organizerOwner, main.id, mainPlanId);
  assert.notEqual(desk.plan.revisionSnapshot.resultChecksum, firstChecksum);
  report.histories.differentSeed = true;

  const samePotPair = desk.plan.placements.find((left) => desk.plan.placements.some((right) => (
    right.entryId !== left.entryId && right.potNumber === left.potNumber && right.groupNumber !== left.groupNumber
  )));
  const samePotOther = desk.plan.placements.find((right) => (
    right.entryId !== samePotPair.entryId
    && right.potNumber === samePotPair.potNumber
    && right.groupNumber !== samePotPair.groupNumber
  ));
  await command(organizerOwner, main, "draw.entry.swap", {
    entryId: samePotPair.entryId,
    otherEntryId: samePotOther.entryId,
    planId: mainPlanId,
    reason: "R6A manual swap staging",
  });
  const swappedDesk = await readDesk(organizerOwner, main.id, mainPlanId);
  assert.equal(swappedDesk.plan.placements.find((item) => item.entryId === samePotPair.entryId).groupNumber, samePotOther.groupNumber);
  report.histories.manualSwap = true;

  await generate(main, mainPlanId, seedA, "draw.regenerate");
  await command(organizerOwner, main, "draw.validate", { planId: mainPlanId, reason: "R6A staging validate" });
  const publishRevision = main.revision;
  const [publishA, publishB] = await Promise.all([
    rawCommand(organizerOwner, main.id, publishRevision, "draw.publish", { planId: mainPlanId, reason: "R6A publish device A" }),
    rawCommand(organizerDevice2, main.id, publishRevision, "draw.publish", { planId: mainPlanId, reason: "R6A publish device B" }),
  ]);
  const publishResults = [publishA, publishB];
  assert.equal(publishResults.filter((result) => !result.error).length, 1);
  assert.equal(publishResults.filter((result) => result.error && /STALE_REVISION/i.test(diagnostic(result))).length, 1);
  const winner = publishResults.find((result) => !result.error);
  main.revision = winner.data.confirmedRevision;
  main.published = true;
  report.histories.concurrentPublish = { stale: 1, winner: 1 };
  report.histories.automaticPublication = true;
  report.histories.sameClubHardAvoid = true;

  const audit = await rpc(organizerOwner, "get_pachanga_tournament_draw_audit_v1", {
    competition_id: main.id,
    draw_plan_id: mainPlanId,
  });
  assert.equal(audit.seed, seedA);
  assert.equal(audit.placements.length, 16);
  assert.equal(audit.quality.hardViolations, 0);

  const publishedEdit = await rawCommand(organizerOwner, main.id, main.revision, "draw.entry.swap", {
    entryId: audit.placements[0].entryId,
    otherEntryId: audit.placements[1].entryId,
    planId: mainPlanId,
    reason: "R6A published edit negative",
  });
  expectError(publishedEdit, /DRAW_REVISION_NOT_EDITABLE|DRAW_PLAN_NOT_EDITABLE/i, "published draw edit");
  report.negatives.publishedDrawEdit = true;

  const directWrite = await organizerOwner.from("pachanga_competition_draw_placements").insert({
    draw_revision_id: randomUUID(),
    entry_id: randomUUID(),
    group_number: 1,
    placement_source: "ENGINE",
    slot_number: 1,
  });
  expectError(directWrite, /permission denied|row-level security/i, "direct table write");
  report.negatives.directWrite = true;

  for (const [action, key] of [
    ["match.generate", "matchGeneration"],
    ["bracket.advance", "bracketProgression"],
    ["payment.intent.create", "paymentIntent"],
  ]) {
    const unavailable = await rawCommand(organizerOwner, main.id, main.revision, action, { reason: "R6A unavailable action" });
    expectError(unavailable, /TOURNAMENT_ACTION_NOT_AVAILABLE/i, action);
    report.negatives[key] = true;
  }
  const aiPublish = await rawCommand(outsider, main.id, main.revision, "draw.publish", {
    planId: mainPlanId,
    reason: "R6A AI unauthorized publish",
  }, randomUUID(), "ai-agent");
  expectError(aiPublish, /TOURNAMENT_DRAW_PUBLISH_FORBIDDEN/i, "AI publish");
  report.negatives.aiPublish = true;

  const notifications = await fixtureAdmin
    .from("pachanga_user_notifications")
    .select("kind")
    .in("recipient_user_id", teamAccounts.map((account) => account.id))
    .in("kind", ["tournament_draw_published", "tournament_draw_assignment"]);
  if (notifications.error) throw notifications.error;
  assert.equal(notifications.data.length, 32);
  report.histories.notifications = 32;

  await relateClubTeams(sharedClub.id, teams.slice(2, 5), clubAccount.id);
  const impossible = await createTournament(organizerOwner, "TEAM", organizerTeam.id, {
    cap: 16,
    groupCount: 4,
    mode: "CONSTRAINT_OPTIMIZED",
    name: "R6A Unsatisfiable",
    slug: "r6a-unsatisfiable",
    target: "GROUP_ASSIGNMENT",
  });
  const acceptImpossible = await inviteTeams(impossible, teams.slice(0, 5), teamClients.slice(0, 5), { duplicateFirst: true });
  const impossiblePlanId = await createPlan(impossible, {
    groupCount: 4,
    mode: "CONSTRAINT_OPTIMIZED",
    target: "GROUP_ASSIGNMENT",
  }, true);
  const unacceptedFreeze = await rawCommand(organizerOwner, impossible.id, impossible.revision, "participants.freeze", {
    planId: impossiblePlanId,
    reason: "R6A unaccepted participants negative",
  });
  expectError(unacceptedFreeze, /BETA_CAPACITY_LIMIT/i, "entries not accepted");
  report.negatives.entryNotAccepted = true;
  const impossibleEntries = await acceptImpossible();
  await freeze(impossible, impossiblePlanId);
  await command(organizerOwner, impossible, "draw_constraint.create", {
    constraintType: "SAME_CLUB_AVOIDANCE",
    parameters: {},
    planId: impossiblePlanId,
    publicAttribution: true,
    reason: "Five teams from one Club cannot fit four groups",
    scope: "DRAW",
    strength: "HARD",
    weight: 100,
  });
  const unsatisfiable = await rawCommand(organizerOwner, impossible.id, impossible.revision, "draw.generate", {
    planId: impossiblePlanId,
    publicSeed: "R6A-STAGING-UNSAT-2026",
    reason: "R6A impossible constraint",
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
  expectError(unsatisfiable, /DRAW_UNSATISFIABLE/i, "impossible constraint");
  report.histories.impossibleConstraint = true;
  await command(teamClients[0], impossible, "participant.withdraw", {
    entryId: impossibleEntries[0].id,
    reason: "R6A withdrawal after freeze",
  });
  const staleFreeze = await rawCommand(organizerOwner, impossible.id, impossible.revision, "draw.generate", {
    planId: impossiblePlanId,
    publicSeed: "R6A-STAGING-STALE-2026",
    reason: "R6A stale freeze negative",
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
  expectError(staleFreeze, /DRAW_INPUT_STALE/i, "participant freeze stale");
  report.histories.withdrawalMakesFreezeStale = true;

  const hybrid = await createTournament(organizerOwner, "TEAM", organizerTeam.id, {
    cap: 16,
    groupCount: 4,
    mode: "HYBRID",
    name: "R6A Hybrid",
    slug: "r6a-hybrid",
    target: "GROUP_ASSIGNMENT",
  });
  const acceptHybrid = await inviteTeams(hybrid, teams, teamClients);
  const hybridEntries = await acceptHybrid();
  const hybridPlanId = await createPlan(hybrid, {
    groupCount: 4,
    mode: "HYBRID",
    target: "GROUP_ASSIGNMENT",
  });
  await freeze(hybrid, hybridPlanId);
  for (const [entryId, groupNumber] of [[hybridEntries[0].id, 1], [hybridEntries[1].id, 2]]) {
    await command(organizerOwner, hybrid, "draw.lock.create", {
      entryId,
      groupNumber,
      lockType: "ENTRY_TO_GROUP",
      planId: hybridPlanId,
      reason: `R6A canonical hybrid lock ${groupNumber}`,
    });
  }
  for (const entryId of [hybridEntries[2].id, hybridEntries[3].id]) {
    await command(organizerOwner, hybrid, "draw.lock.create", {
      entryId,
      groupNumber: 3,
      lockType: "ENTRY_TO_SLOT",
      planId: hybridPlanId,
      reason: "R6A contradictory lock negative",
      slotNumber: 1,
    });
  }
  const lockConflict = await rawCommand(organizerOwner, hybrid.id, hybrid.revision, "draw.generate", {
    planId: hybridPlanId,
    publicSeed: "R6A-STAGING-LOCK-CONFLICT",
    reason: "R6A contradictory locks",
    seedMode: "CUSTOM_PUBLIC_SEED",
  });
  expectError(lockConflict, /DRAW_UNSATISFIABLE/i, "contradictory locks");
  report.negatives.contradictoryLocks = true;
  let hybridDesk = await readDesk(organizerOwner, hybrid.id, hybridPlanId);
  for (const lock of hybridDesk.plan.manualLocks.filter((candidate) => [hybridEntries[2].id, hybridEntries[3].id].includes(candidate.entryId))) {
    await command(organizerOwner, hybrid, "draw.lock.remove", {
      lockId: lock.id,
      planId: hybridPlanId,
      reason: "R6A remove contradictory lock",
    });
  }
  await generate(hybrid, hybridPlanId, "R6A-STAGING-HYBRID-2026");
  hybridDesk = await readDesk(organizerOwner, hybrid.id, hybridPlanId);
  assert.equal(hybridDesk.plan.placements.find((item) => item.entryId === hybridEntries[0].id).groupNumber, 1);
  assert.equal(hybridDesk.plan.placements.find((item) => item.entryId === hybridEntries[1].id).groupNumber, 2);
  assert.equal(hybridDesk.plan.manualLocks.length, 2);

  const occupied = hybridDesk.plan.placements.find((item) => item.entryId !== hybridEntries[0].id);
  const positionConflict = await rawCommand(organizerOwner, hybrid.id, hybrid.revision, "draw.entry.move", {
    entryId: hybridEntries[0].id,
    groupNumber: occupied.groupNumber,
    planId: hybridPlanId,
    reason: "R6A occupied position negative",
    slotNumber: occupied.slotNumber,
  });
  expectError(positionConflict, /DRAW_POSITION_OCCUPIED/i, "two teams in one position");
  report.negatives.duplicatePosition = true;
  report.histories.hybridTwoLocks = true;

  const knockout = await createTournament(organizerOwner, "TEAM", organizerTeam.id, {
    cap: 16,
    groupCount: undefined,
    mode: "SEEDED_POTS",
    name: "R6A Knockout",
    slug: "r6a-knockout",
    target: "KNOCKOUT_INITIAL_SEEDING",
  });
  const acceptKnockout = await inviteTeams(knockout, teams.slice(0, 14), teamClients.slice(0, 14));
  await acceptKnockout();
  const knockoutPlanId = await createPlan(knockout, {
    mode: "SEEDED_POTS",
    slotCount: 16,
    target: "KNOCKOUT_INITIAL_SEEDING",
  });
  await freeze(knockout, knockoutPlanId);
  await generate(knockout, knockoutPlanId, "R6A-STAGING-KNOCKOUT-2026");
  const knockoutDesk = await readDesk(organizerOwner, knockout.id, knockoutPlanId);
  assert.equal(knockoutDesk.plan.placements.length, 14);
  assert.equal(knockoutDesk.plan.byes.length, 2);
  report.histories.knockout14Of16 = { byes: 2, placements: 14 };

  const matches = await fixtureAdmin
    .from("pachanga_competition_match_contexts")
    .select("id", { count: "exact", head: true })
    .in("competition_id", created.competitions.map((competition) => competition.id));
  if (matches.error) throw matches.error;
  assert.equal(matches.count, 0);
  report.tournamentMatches = 0;

  const afterInvariants = await invariantCounts();
  assert.deepEqual(afterInvariants, beforeInvariants);
  report.invariants = { billing: true, conduct: true, cosmetics: true, rating: true, rewards: true };

  if (env.previewUrl) {
    for (const path of ["/torneos", "/torneos/crear", "/laboratorio-tournament-draw", "/demo?demo=1&world=tournament"]) {
      const response = await fetch(new URL(path, env.previewUrl), { redirect: "manual" });
      assert.ok(response.status < 500, `${path} returned ${response.status}`);
    }
    const manifest = await fetch(new URL("/manifest.webmanifest", env.previewUrl), { cache: "no-store" });
    assert.equal(manifest.status, 200);
    const worker = await fetch(new URL("/sw.js", env.previewUrl), { cache: "no-store" });
    assert.equal(worker.status, 200);
    report.preview = true;
  }

  console.log(JSON.stringify(report));
} finally {
  for (const state of created.competitions.filter((competition) => !competition.published).reverse()) {
    await bestEffort(`cancel-${state.id}`, async () => {
      const snapshot = await readSnapshot(state.ownerClient, state.id);
      state.revision = snapshot.revision;
      if (snapshot.competition.status !== "cancelled") {
        await command(state.ownerClient, state, "tournament.cancel", { reason: `R6A staging cleanup ${runId}` });
      }
    });
  }
  if (platform) {
    for (const bundle of created.bundles.reverse()) {
      await bestEffort(`revoke-${bundle.bundleId}`, () => revokeBundle(platform, bundle));
    }
    if (tournamentFlagsChanged && initialTournamentFlags) {
      await bestEffort("restore-tournament-flags", () => setTournamentFlags(
        platform,
        Object.fromEntries(TOURNAMENT_FLAG_KEYS.map((key) => [key, initialTournamentFlags[key]])),
        `R6A staging flag restore ${runId}`,
      ));
    }
    if (foundationFlagsChanged && initialFoundationFlags) {
      await bestEffort("restore-foundation-flags", () => setFoundationFlags(
        platform,
        Object.fromEntries(FOUNDATION_FLAG_KEYS.map((key) => [key, initialFoundationFlags[key]])),
        `R6A staging foundation restore ${runId}`,
      ));
    }
    if (clubFlagsChanged && initialClubFlags) {
      await bestEffort("restore-club-flags", () => setClubFlags(
        platform,
        Object.fromEntries(CLUB_FLAG_KEYS.map((key) => [key, initialClubFlags[key]])),
        `R6A staging Club restore ${runId}`,
      ));
    }
  }
  for (const channel of channels) await bestEffort("remove-channel", () => channel.unsubscribe());
  for (const supabase of clients) await bestEffort("sign-out", () => supabase.auth.signOut());
}
