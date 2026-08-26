import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const REFEREE_FLAGS_ID = "00000000-0000-0000-0000-00000000a3f3";
const DISCIPLINE_FLAGS_ID = "00000000-0000-0000-0000-00000000d501";
const ACTIVE_ASSIGNMENT_STATUSES = ["proposed", "accepted", "confirmed"];
const R3_FLAG_KEYS = [
  "foundationEnabled", "selfServiceEnabled", "publicProfilesEnabled",
  "marketplaceEnabled", "clubRelationshipsEnabled", "assignmentsEnabled",
];
const R5_FLAG_KEYS = [
  "foundationEnabled", "eventsEnabled", "countersEnabled", "sanctionsEnabled",
  "serviceEnabled", "appealsEnabled", "publicEnabled",
];

function invalidationQueue() {
  const events = [];
  const waiters = [];
  return {
    push(event) {
      const index = waiters.findIndex(({ predicate }) => predicate(event));
      if (index >= 0) {
        const [{ resolve, timer }] = waiters.splice(index, 1);
        clearTimeout(timer);
        resolve(event);
      } else events.push(event);
    },
    wait(predicate, label) {
      const index = events.findIndex(predicate);
      if (index >= 0) return Promise.resolve(events.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const waiter = waiters.findIndex((candidate) => candidate.timer === timer);
          if (waiter >= 0) waiters.splice(waiter, 1);
          reject(new Error(`Wave 4 Realtime timeout: ${label}`));
        }, 90_000);
        waiters.push({ predicate, resolve, reject, timer });
      });
    },
  };
}

function assignmentCommand(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return client.rpc("command_pachanga_referee_assignment_beta_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("referee-assignments-private-beta-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function assignmentOk(client, metadata, input) {
  const result = await assignmentCommand(client, metadata, input);
  if (result.error) {
    throw new Error(
      `${input.action}:${input.aggregateId}@${input.expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function profileCommand(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return client.rpc("command_pachanga_referee_platform_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("referee-assignments-profile-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function profileOk(client, metadata, input) {
  const result = await profileCommand(client, metadata, input);
  if (result.error) {
    throw new Error(
      `profile:${input.action}:${input.aggregateId}@${input.expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function adminRefereeOk(platform, metadata, {
  action,
  aggregateId,
  expectedRevision,
  payload,
}) {
  const result = await platform.rpc("command_pachanga_referee_platform_admin_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("referee-assignments-admin-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
  });
  if (result.error) {
    throw new Error(
      `admin:${action}:${aggregateId}@${expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function setR3Flags(platform, metadata, rpc, values, reason) {
  const current = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  return adminRefereeOk(platform, metadata, {
    action: "referee_flags.set",
    aggregateId: REFEREE_FLAGS_ID,
    expectedRevision: current.revision,
    payload: { ...values, reason },
  });
}

async function setAssignmentFlags(platform, metadata, rpc, values, reason) {
  const current = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  const result = await platform.rpc("command_pachanga_referee_assignment_beta_admin_v1", {
    client_metadata: metadata("referee-assignments-flags-staging"),
    command_action: "assignment_beta.flags.set",
    command_payload: { ...values, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function setDisciplineFlags(platform, metadata, rpc, values, reason) {
  const current = await rpc(platform, "get_pachanga_competition_discipline_flags_v1");
  const result = await platform.rpc("command_pachanga_competition_discipline_platform_v1", {
    aggregate_id: DISCIPLINE_FLAGS_ID,
    client_metadata: metadata("referee-assignments-r5-flags-staging"),
    command_payload: { ...values, reason },
    expected_revision: current.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function upgradeR5Bundle({ bundleId, fixtureAdmin, metadata, platform }) {
  const grant = await fixtureAdmin
    .from("pachanga_competition_entitlement_grants")
    .select("organizer_kind,organizer_group_id,organizer_club_id")
    .eq("bundle_id", bundleId)
    .eq("program_key", "LEAGUE_PRIVATE_BETA_V1")
    .eq("status", "active")
    .limit(1)
    .single();
  if (grant.error) throw grant.error;
  let stateQuery = fixtureAdmin
    .from("pachanga_competition_organizer_states")
    .select("revision")
    .eq("organizer_kind", grant.data.organizer_kind);
  stateQuery = grant.data.organizer_kind === "TEAM"
    ? stateQuery.eq("organizer_group_id", grant.data.organizer_group_id)
    : stateQuery.eq("organizer_club_id", grant.data.organizer_club_id);
  const state = await stateQuery.single();
  if (state.error) throw state.error;
  const upgraded = await platform.rpc("command_pachanga_league_private_beta_r5_bundle_upgrade_v1", {
    bundle_id: bundleId,
    client_metadata: metadata("referee-assignments-r5-bundle-staging"),
    expected_revision: state.data.revision,
    operation_id: randomUUID(),
  });
  if (upgraded.error) throw upgraded.error;
  assert.equal(upgraded.data.snapshot.r5CapabilityCount, 3);
  assert.equal(upgraded.data.snapshot.status, "active");
  return upgraded.data;
}

async function createOrRestoreProfile({
  actor,
  fixtureAdmin,
  index,
  metadata,
  platform,
}) {
  const userResult = await actor.client.auth.getUser();
  if (userResult.error || !userResult.data.user) {
    throw userResult.error ?? new Error(`W4_STAGING_ACTOR_${index}_REQUIRED`);
  }
  const userId = userResult.data.user.id;
  const profileId = `f1900000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`;
  const slug = `w4-staging-referee-${index + 1}`;
  const existing = await fixtureAdmin
    .from("pachanga_referee_profiles")
    .select("id,user_id,revision,operational_status,marketplace_status")
    .eq("user_id", userId)
    .maybeSingle();
  if (existing.error) throw existing.error;
  if (existing.data && existing.data.id !== profileId) {
    throw new Error(`W4_STAGING_PROFILE_COLLISION:${userId}`);
  }

  let receipt;
  let revision;
  if (!existing.data) {
    receipt = await profileOk(actor.client, metadata, {
      action: "profile.create",
      aggregateId: profileId,
      expectedRevision: 0,
      payload: {
        availabilityStatus: "AVAILABLE",
        bio: `Perfil arbitral Wave 4 QA ${index + 1}.`,
        experienceSinceYear: 2018 + (index % 5),
        experienceSummary: "Experiencia declarada para staging autenticado.",
        reason: "Wave 4 staging profile",
        slug,
      },
    });
    revision = receipt.confirmedRevision;
  } else {
    revision = existing.data.revision;
    if (existing.data.operational_status === "archived") {
      throw new Error(`W4_STAGING_PROFILE_ARCHIVED_TERMINAL:${profileId}`);
    }
    if (existing.data.operational_status === "suspended") {
      receipt = await adminRefereeOk(platform, metadata, {
        action: "profile.restore",
        aggregateId: profileId,
        expectedRevision: revision,
        payload: { reason: "Wave 4 staging profile restore" },
      });
      revision = receipt.confirmedRevision;
    }
    if (existing.data.marketplace_status === "listed") {
      receipt = await profileOk(actor.client, metadata, {
        action: "marketplace.unlist",
        aggregateId: profileId,
        expectedRevision: revision,
        payload: { reason: "Wave 4 staging profile privacy" },
      });
      revision = receipt.confirmedRevision;
    }
  }

  receipt = await profileOk(actor.client, metadata, {
    action: "profile.modalities.replace",
    aggregateId: profileId,
    expectedRevision: revision,
    payload: {
      modalities: [
        { experienceSinceYear: 2018 + (index % 5), modality: "FOOTBALL_5" },
        { experienceSinceYear: 2018 + (index % 5), modality: "FOOTBALL_7" },
      ],
      reason: "Wave 4 staging modalities",
    },
  });
  receipt = await profileOk(actor.client, metadata, {
    action: "profile.areas.replace",
    aggregateId: profileId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      areas: [{
        countryCode: "ES",
        generalArea: "Barcelona",
        municipality: "Barcelona",
        province: "Barcelona",
        travelRadiusKm: 100,
      }],
      reason: "Wave 4 staging service area",
    },
  });
  receipt = await profileOk(actor.client, metadata, {
    action: "profile.availability.replace",
    aggregateId: profileId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      exceptions: [],
      reason: "Wave 4 staging availability",
      windows: Array.from({ length: 7 }, (_, weekday) => ({
        endLocalTime: "23:59",
        publicVisible: false,
        startLocalTime: "00:00",
        timezone: "Europe/Madrid",
        weekday: weekday + 1,
      })),
    },
  });
  receipt = await profileOk(actor.client, metadata, {
    action: "profile.update",
    aggregateId: profileId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      availabilityStatus: "AVAILABLE",
      availableForAssignments: true,
      reason: "Wave 4 staging private settings",
      shareRecurringAvailability: true,
      visibility: "private",
    },
  });
  const afterUpdate = await fixtureAdmin
    .from("pachanga_referee_profiles")
    .select("operational_status")
    .eq("id", profileId)
    .single();
  if (afterUpdate.error) throw afterUpdate.error;
  if (afterUpdate.data.operational_status !== "active") {
    const consent = await actor.client.rpc("command_pachanga_publication_consent_v1", {
      client_metadata: metadata("referee-assignments-profile-consent-staging"),
      confirmations: {
        informationCorrect: true,
        publicZonesAvailability: true,
        unverifiedNotCertification: true,
      },
      expected_revision: receipt.confirmedRevision,
      operation_id: randomUUID(),
      subject_id: profileId,
      subject_kind: "REFEREE_PROFILE",
    });
    if (consent.error) throw consent.error;
    receipt = await profileOk(actor.client, metadata, {
      action: "profile.activate",
      aggregateId: profileId,
      expectedRevision: consent.data.confirmedRevision,
      payload: { reason: "Wave 4 staging activate" },
    });
  }
  return { ...actor, profileId, userId };
}

function proposalPayload({ competitionId, fixture, profileId, terms = {} }) {
  return {
    assignmentRole: "MAIN_REFEREE",
    feeMode: "VOLUNTEER",
    refereeProfileId: profileId,
    requesterId: competitionId,
    requesterKind: "COMPETITION",
    sourceId: fixture.schedule_item_id,
    sourceKind: "competition_generated",
    ...terms,
  };
}

async function stageFixture(fixtureAdmin, fixture, start, status = "scheduled") {
  const selected = await fixtureAdmin
    .from("pachanga_competition_match_contexts")
    .select("id,revision")
    .eq("id", fixture.id)
    .single();
  if (selected.error) throw selected.error;
  const updated = await fixtureAdmin
    .from("pachanga_competition_match_contexts")
    .update({
      revision: selected.data.revision + 1,
      scheduled_end: new Date(start.getTime() + 70 * 60_000).toISOString(),
      scheduled_start: start.toISOString(),
      status,
      timezone: "Europe/Madrid",
      venue_label: "Camp Municipal Wave 4 · Barcelona",
      venue_status: "CONFIRMED",
    })
    .eq("id", fixture.id)
    .eq("revision", selected.data.revision)
    .select("id")
    .single();
  if (updated.error) throw updated.error;
}

async function createDraftClub(client, metadata, index) {
  const id = randomUUID();
  const tag = `${Date.now()}-${index}-${randomUUID().slice(0, 8)}`;
  const result = await client.rpc("command_pachanga_club_foundation_v1", {
    aggregate_id: id,
    client_metadata: metadata("referee-assignments-club-staging"),
    command_action: "club.create",
    command_payload: {
      clubType: "FOOTBALL_CLUB",
      countryCode: "ES",
      municipality: "Barcelona",
      name: `Wave 4 Referee Club ${tag}`,
      province: "Barcelona",
      reason: "Wave 4 staging Club",
      slug: `wave4-referee-club-${tag}`,
      visibility: "private",
    },
    expected_revision: 0,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return id;
}

async function archiveClub(platform, fixtureAdmin, metadata, clubId) {
  const selected = await fixtureAdmin
    .from("pachanga_clubs")
    .select("id,operational_status,revision")
    .eq("id", clubId)
    .maybeSingle();
  if (selected.error) throw selected.error;
  if (!selected.data || selected.data.operational_status === "archived") return;
  const result = await platform.rpc("command_pachanga_club_platform_v1", {
    aggregate_id: clubId,
    client_metadata: metadata("referee-assignments-club-cleanup"),
    command_action: "club.status.set",
    command_payload: { reason: "Wave 4 staging cleanup", status: "archived" },
    expected_revision: selected.data.revision,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
}

async function officiateOk(client, metadata, {
  action,
  assignmentId,
  expectedRevision,
  operationId = randomUUID(),
  payload,
}) {
  const result = await client.rpc("command_pachanga_referee_officiating_v1", {
    client_metadata: metadata("referee-officiating-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
    target_assignment_id: assignmentId,
  });
  if (result.error) {
    throw new Error(
      `officiating:${action}:${assignmentId}@${expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function disciplineOk(client, metadata, {
  action,
  aggregateId,
  competitionId,
  expectedRevision,
  payload,
}) {
  const result = await client.rpc("command_pachanga_competition_discipline_v1", {
    client_metadata: metadata("referee-officiating-cleanup"),
    command_action: action,
    command_payload: payload,
    competition_id: competitionId,
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
    aggregate_id: aggregateId,
  });
  if (result.error) {
    throw new Error(
      `discipline:${action}:${aggregateId}@${expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function operationalOk(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  payload,
}) {
  const result = await client.rpc("command_pachanga_league_operational_exceptions_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("referee-assignments-r4d-staging"),
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
  });
  if (result.error) {
    throw new Error(
      `operational:${action}:${aggregateId}@${expectedRevision} `
      + `[${result.error.code ?? "UNKNOWN"}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

async function bestEffort(label, action) {
  try {
    await action();
  } catch (error) {
    console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error);
  }
}

export async function runRefereeAssignmentsPrivateBetaStagingExtension({
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
  teams,
  waitForSubscription,
}) {
  const initialR3 = await rpc(platform, "get_pachanga_referee_foundation_flags_v1");
  const initialR5 = await rpc(platform, "get_pachanga_competition_discipline_flags_v1");
  const actors = [
    { client: ownerA, device2: ownerADevice2, label: "owner-a" },
    { client: ownerB, label: "owner-b" },
    { client: ownerC, label: "owner-c" },
    { client: adminA, device2: adminADevice2, label: "admin-a" },
    { client: playerA, label: "player-a" },
    { client: staffA, label: "staff-a" },
    { client: teams[0].delegateClient, label: "team-a-delegate" },
    { client: teams[1].delegateClient, label: "team-b-delegate" },
  ];
  const assignmentIds = [];
  const extraClubIds = [];
  const profileActors = [];
  const localChannels = [];
  const eventIds = [];
  let r3Enabled = false;
  let assignmentFlagsEnabled = false;
  let disciplineFlagsChanged = false;
  let completed = false;
  let result;

  try {
    await setR3Flags(platform, metadata, rpc, {
      assignmentsEnabled: false,
      clubRelationshipsEnabled: true,
      foundationEnabled: true,
      marketplaceEnabled: true,
      publicProfilesEnabled: true,
      selfServiceEnabled: true,
    }, "Wave 4 staging R3 window");
    r3Enabled = true;
    await setAssignmentFlags(platform, metadata, rpc, {
      assignmentPrivateBetaEnabled: true,
      assignmentsEnabled: true,
    }, "Wave 4 authenticated staging window");
    assignmentFlagsEnabled = true;
    await upgradeR5Bundle({
      bundleId: created.betaBundleId,
      fixtureAdmin,
      metadata,
      platform,
    });
    await setDisciplineFlags(platform, metadata, rpc, {
      appealsEnabled: true,
      countersEnabled: true,
      eventsEnabled: true,
      foundationEnabled: true,
      publicEnabled: false,
      sanctionsEnabled: true,
      serviceEnabled: true,
    }, "Wave 4 authenticated R5 window");
    disciplineFlagsChanged = true;

    for (let index = 0; index < actors.length; index += 1) {
      profileActors.push(await createOrRestoreProfile({
        actor: actors[index],
        fixtureAdmin,
        index,
        metadata,
        platform,
      }));
    }
    assert.equal(profileActors.length, 8);

    extraClubIds.push(
      await createDraftClub(profileActors[6].client, metadata, 1),
      await createDraftClub(profileActors[7].client, metadata, 2),
    );
    const clubs = await fixtureAdmin
      .from("pachanga_clubs")
      .select("id")
      .in("id", [created.clubId, ...extraClubIds]);
    if (clubs.error) throw clubs.error;
    assert.equal(clubs.data.length, 3, "Wave 4 staging must create exactly three QA Clubs");

    const contexts = await fixtureAdmin
      .from("pachanga_competition_match_contexts")
      .select("id,canonical_match_id,competition_id,home_entry_id,away_entry_id,rule_revision_id,schedule_item_id,scheduled_start,status")
      .eq("competition_id", created.competitionId)
      .eq("source_kind", "COMPETITION_GENERATED")
      .order("scheduled_start", { ascending: true })
      .order("id", { ascending: true });
    if (contexts.error) throw contexts.error;
    assert.equal(contexts.data.length, 15);
    const [declineFixture, raceFixture, replacementFixture, conflictA, conflictB, lifecycleFixture] = contexts.data.slice(-6);
    await stageFixture(fixtureAdmin, declineFixture, new Date("2027-09-24T18:00:00Z"));
    await stageFixture(fixtureAdmin, raceFixture, new Date("2027-10-01T18:00:00Z"));
    await stageFixture(fixtureAdmin, replacementFixture, new Date("2027-10-08T18:00:00Z"));
    await stageFixture(fixtureAdmin, conflictA, new Date("2027-10-15T18:00:00Z"));
    await stageFixture(fixtureAdmin, conflictB, new Date("2027-10-15T18:20:00Z"));
    await stageFixture(fixtureAdmin, lifecycleFixture, new Date("2027-10-22T18:00:00Z"));

    const queue = invalidationQueue();
    const realtimeChannel = ownerADevice2
      .channel(`wave4-staging-${randomUUID()}`)
      .on("postgres_changes", {
        event: "INSERT",
        schema: "public",
        table: "pachanga_referee_invalidations",
      }, ({ new: row }) => queue.push(row));
    localChannels.push([ownerADevice2, realtimeChannel]);
    await waitForSubscription(realtimeChannel);

    const raceAssignmentId = randomUUID();
    assignmentIds.push(raceAssignmentId);
    const proposalOperation = randomUUID();
    const proposalInput = {
      action: "assignment.propose",
      aggregateId: raceAssignmentId,
      expectedRevision: 0,
      operationId: proposalOperation,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: raceFixture,
        profileId: profileActors[0].profileId,
        terms: { feeMode: "VOLUNTEER" },
      }),
    };
    const proposal = await assignmentOk(staffA, metadata, proposalInput);
    assert.deepEqual(await assignmentOk(staffA, metadata, proposalInput), proposal);
    const refereeInvalidation = await queue.wait((event) => (
      event.entity_type === "referee_assignment"
      && event.entity_id === raceAssignmentId
      && event.target_user_id === profileActors[0].userId
    ), "assignment proposal for referee");
    const proposerInvalidation = await queue.wait((event) => (
      event.entity_type === "referee_assignment"
      && event.entity_id === raceAssignmentId
      && event.target_user_id === profileActors[5].userId
    ), "assignment proposal for requester");
    assert.equal(refereeInvalidation.server_sequence, proposerInvalidation.server_sequence);
    const ownerRead = await rpc(ownerADevice2, "get_my_pachanga_referee_assignments_v1");
    assert.ok(ownerRead.items.some(({ id, status }) => id === raceAssignmentId && status === "proposed"));

    const race = await Promise.all([
      assignmentCommand(ownerA, metadata, {
        action: "assignment.accept",
        aggregateId: raceAssignmentId,
        expectedRevision: 1,
      }),
      assignmentCommand(ownerADevice2, metadata, {
        action: "assignment.decline",
        aggregateId: raceAssignmentId,
        expectedRevision: 1,
      }),
    ]);
    assert.equal(race.filter(({ error }) => !error).length, 1);
    assert.equal(race.filter(({ error }) => error).length, 1);
    expectError(race.find(({ error }) => error), /STALE_REVISION|NOT_PROPOSED/, "PT409");

    const originalId = randomUUID();
    assignmentIds.push(originalId);
    let original = await assignmentOk(staffA, metadata, {
      action: "assignment.propose",
      aggregateId: originalId,
      expectedRevision: 0,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: replacementFixture,
        profileId: profileActors[1].profileId,
        terms: { feeMode: "FIXED", proposedFeeCents: 6500, currency: "EUR" },
      }),
    });
    original = await assignmentOk(ownerB, metadata, {
      action: "assignment.accept",
      aggregateId: originalId,
      expectedRevision: original.confirmedRevision,
    });
    original = await assignmentOk(staffA, metadata, {
      action: "assignment.confirm",
      aggregateId: originalId,
      expectedRevision: original.confirmedRevision,
    });
    assert.equal(original.snapshot.assignment.status, "confirmed");

    const replacementId = randomUUID();
    assignmentIds.push(replacementId);
    let replacement = await assignmentOk(staffA, metadata, {
      action: "assignment.replace",
      aggregateId: originalId,
      expectedRevision: original.confirmedRevision,
      payload: {
        currency: "EUR",
        feeMode: "NEGOTIABLE",
        newAssignmentId: replacementId,
        newRefereeProfileId: profileActors[2].profileId,
        privateTermsNote: "Condiciones privadas de sustitución QA",
        proposedFeeCents: 7000,
      },
    });
    replacement = await assignmentOk(ownerC, metadata, {
      action: "assignment.accept",
      aggregateId: replacementId,
      expectedRevision: replacement.snapshot.replacement.revision,
    });
    const originalBeforeHandover = await rpc(staffA, "get_pachanga_referee_assignment_beta_v1", {
      target_assignment_id: originalId,
    });
    assert.equal(originalBeforeHandover.assignment.status, "confirmed");
    replacement = await assignmentOk(staffA, metadata, {
      action: "assignment.confirm",
      aggregateId: replacementId,
      expectedRevision: replacement.confirmedRevision,
    });
    assert.equal(replacement.snapshot.assignment.status, "confirmed");
    const replacedOriginal = await rpc(staffA, "get_pachanga_referee_assignment_beta_v1", {
      target_assignment_id: originalId,
    });
    assert.equal(replacedOriginal.assignment.status, "replaced");

    const declinedId = randomUUID();
    assignmentIds.push(declinedId);
    let declined = await assignmentOk(staffA, metadata, {
      action: "assignment.propose",
      aggregateId: declinedId,
      expectedRevision: 0,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: declineFixture,
        profileId: profileActors[3].profileId,
      }),
    });
    declined = await assignmentOk(adminA, metadata, {
      action: "assignment.decline",
      aggregateId: declinedId,
      expectedRevision: declined.confirmedRevision,
    });
    assert.equal(declined.snapshot.assignment.status, "declined");

    const conflictAcceptedId = randomUUID();
    assignmentIds.push(conflictAcceptedId);
    let conflictAccepted = await assignmentOk(staffA, metadata, {
      action: "assignment.propose",
      aggregateId: conflictAcceptedId,
      expectedRevision: 0,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: conflictA,
        profileId: profileActors[4].profileId,
      }),
    });
    conflictAccepted = await assignmentOk(playerA, metadata, {
      action: "assignment.accept",
      aggregateId: conflictAcceptedId,
      expectedRevision: conflictAccepted.confirmedRevision,
    });
    conflictAccepted = await assignmentOk(staffA, metadata, {
      action: "assignment.confirm",
      aggregateId: conflictAcceptedId,
      expectedRevision: conflictAccepted.confirmedRevision,
    });
    assert.equal(conflictAccepted.snapshot.assignment.status, "confirmed");
    const conflictRejectedId = randomUUID();
    assignmentIds.push(conflictRejectedId);
    const conflictProposal = await assignmentOk(staffA, metadata, {
      action: "assignment.propose",
      aggregateId: conflictRejectedId,
      expectedRevision: 0,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: conflictB,
        profileId: profileActors[4].profileId,
      }),
    });
    const conflictResult = await assignmentCommand(playerA, metadata, {
      action: "assignment.accept",
      aggregateId: conflictRejectedId,
      expectedRevision: conflictProposal.confirmedRevision,
    });
    expectError(conflictResult, /REFEREE_ASSIGNMENT_TIME_CONFLICT|REFEREE_ASSIGNMENT_CONFLICT/, "PT409");
    await assignmentOk(playerA, metadata, {
      action: "assignment.decline",
      aggregateId: conflictRejectedId,
      expectedRevision: conflictProposal.confirmedRevision,
    });

    const lifecycleId = randomUUID();
    assignmentIds.push(lifecycleId);
    let lifecycle = await assignmentOk(staffA, metadata, {
      action: "assignment.propose",
      aggregateId: lifecycleId,
      expectedRevision: 0,
      payload: proposalPayload({
        competitionId: created.competitionId,
        fixture: lifecycleFixture,
        profileId: profileActors[6].profileId,
        terms: {
          currency: "EUR",
          feeMode: "NEGOTIABLE",
          privateTermsNote: "Oferta privada staging",
          proposedFeeCents: 5500,
        },
      }),
    });
    lifecycle = await assignmentOk(profileActors[6].client, metadata, {
      action: "terms.counter",
      aggregateId: lifecycleId,
      expectedRevision: lifecycle.confirmedRevision,
      payload: { counterFeeCents: 6200, privateTermsNote: "Contraoferta privada staging" },
    });
    lifecycle = await assignmentOk(staffA, metadata, {
      action: "terms.accept",
      aggregateId: lifecycleId,
      expectedRevision: lifecycle.confirmedRevision,
    });
    lifecycle = await assignmentOk(staffA, metadata, {
      action: "assignment.confirm",
      aggregateId: lifecycleId,
      expectedRevision: lifecycle.confirmedRevision,
    });
    const operationalBefore = await rpc(staffA, "get_pachanga_league_operational_match_v1", {
      target_canonical_match_id: lifecycleFixture.canonical_match_id,
      target_competition_id: created.competitionId,
    });
    await operationalOk(staffA, metadata, {
      action: "fixture.reschedule",
      aggregateId: lifecycleFixture.id,
      expectedRevision: operationalBefore.revision,
      payload: {
        reasonCode: "REFEREE_RECONFIRMATION_QA",
        scheduledEnd: "2027-10-29T19:10:00Z",
        scheduledStart: "2027-10-29T18:00:00Z",
        timezone: "Europe/Madrid",
      },
    });
    let lifecycleRead = await rpc(staffA, "get_pachanga_referee_assignment_beta_v1", {
      target_assignment_id: lifecycleId,
    });
    assert.equal(lifecycleRead.assignment.scheduleState, "RECONFIRMATION_REQUIRED");
    lifecycle = await assignmentOk(profileActors[6].client, metadata, {
      action: "assignment.reconfirm",
      aggregateId: lifecycleId,
      expectedRevision: lifecycleRead.assignment.revision,
    });
    assert.equal(lifecycle.snapshot.assignment.scheduleState, "CURRENT");

    await stageFixture(fixtureAdmin, lifecycleFixture, new Date("2027-10-29T18:00:00Z"), "ready");
    const matchSheet = await fixtureAdmin.from("pachanga_competition_match_sheets").upsert({
      canonical_match_id: lifecycleFixture.canonical_match_id,
      competition_match_context_id: lifecycleFixture.id,
      created_by: profileActors[6].userId,
    }, { ignoreDuplicates: true, onConflict: "competition_match_context_id" });
    if (matchSheet.error) throw matchSheet.error;
    const rosterMember = await fixtureAdmin
      .from("pachanga_competition_roster_members")
      .select("player_profile_id")
      .in("entry_id", [lifecycleFixture.home_entry_id, lifecycleFixture.away_entry_id])
      .limit(1)
      .single();
    if (rosterMember.error) throw rosterMember.error;
    const r4cBefore = await fixtureAdmin
      .from("pachanga_competition_sporting_results")
      .select("id,current_revision_id")
      .eq("competition_match_context_id", lifecycleFixture.id)
      .maybeSingle();
    if (r4cBefore.error) throw r4cBefore.error;
    const disciplineReceipt = await officiateOk(profileActors[6].client, metadata, {
      action: "discipline.record",
      assignmentId: lifecycleId,
      expectedRevision: lifecycle.confirmedRevision,
      payload: {
        cardTypeCode: "YELLOW",
        context: "in_match",
        minute: 18,
        period: "FIRST_HALF",
        playerProfileId: rosterMember.data.player_profile_id,
        publicSummary: "Amonestación QA registrada por árbitro confirmado",
      },
    });
    const eventId = disciplineReceipt.snapshot.discipline.event.id;
    eventIds.push(eventId);
    lifecycle = disciplineReceipt;
    const r4cAfter = await fixtureAdmin
      .from("pachanga_competition_sporting_results")
      .select("id,current_revision_id")
      .eq("competition_match_context_id", lifecycleFixture.id)
      .maybeSingle();
    if (r4cAfter.error) throw r4cAfter.error;
    assert.deepEqual(r4cAfter.data, r4cBefore.data, "Referee evidence must not mutate R4C authority");
    const eventRead = await fixtureAdmin
      .from("pachanga_competition_disciplinary_events")
      .select("id,referee_assignment_id,reporting_referee_profile_id,status")
      .eq("id", eventId)
      .single();
    if (eventRead.error) throw eventRead.error;
    assert.equal(eventRead.data.referee_assignment_id, lifecycleId);
    assert.equal(eventRead.data.reporting_referee_profile_id, profileActors[6].profileId);

    const incrementalStats = await fixtureAdmin
      .from("pachanga_referee_statistics_snapshots")
      .select("checksum,revision,yellow_cards_shown")
      .eq("referee_profile_id", profileActors[6].profileId)
      .single();
    if (incrementalStats.error) throw incrementalStats.error;
    assert.equal(incrementalStats.data.yellow_cards_shown, 1);
    const rebuilt = await adminRefereeOk(platform, metadata, {
      action: "stats.rebuild",
      aggregateId: profileActors[6].profileId,
      expectedRevision: incrementalStats.data.revision,
      payload: { reason: "Wave 4 staging full stats rebuild" },
    });
    assert.equal(rebuilt.snapshot.statistics.checksum, incrementalStats.data.checksum);

    const disciplineFlags = await rpc(staffA, "get_pachanga_competition_discipline_flags_v1");
    const competitionRead = await fixtureAdmin
      .from("pachanga_competitions")
      .select("discipline_revision")
      .eq("id", created.competitionId)
      .single();
    if (competitionRead.error) throw competitionRead.error;
    assert.equal(disciplineFlags.publicEnabled, false);
    await disciplineOk(staffA, metadata, {
      action: "event.annul",
      aggregateId: eventId,
      competitionId: created.competitionId,
      expectedRevision: competitionRead.data.discipline_revision,
      payload: { correctionReason: "Wave 4 staging event cleanup" },
    });

    const statsAfterAnnul = await fixtureAdmin
      .from("pachanga_referee_statistics_snapshots")
      .select("revision")
      .eq("referee_profile_id", profileActors[6].profileId)
      .single();
    if (statsAfterAnnul.error) throw statsAfterAnnul.error;
    const cleanedStats = await adminRefereeOk(platform, metadata, {
      action: "stats.rebuild",
      aggregateId: profileActors[6].profileId,
      expectedRevision: statsAfterAnnul.data.revision,
      payload: { reason: "Wave 4 staging stats cleanup" },
    });
    assert.equal(cleanedStats.snapshot.statistics.yellow_cards_shown, 0);

    await stageFixture(fixtureAdmin, lifecycleFixture, new Date("2027-10-29T18:00:00Z"), "official");
    lifecycleRead = await rpc(staffA, "get_pachanga_referee_assignment_beta_v1", {
      target_assignment_id: lifecycleId,
    });
    const reconcileOperation = randomUUID();
    const reconcileArgs = {
      client_metadata: metadata("referee-assignments-reconcile-staging"),
      expected_revision: lifecycleRead.assignment.revision,
      operation_id: reconcileOperation,
      target_assignment_id: lifecycleId,
    };
    const reconciled = await rpc(platform, "reconcile_pachanga_referee_assignment_v1", reconcileArgs);
    assert.deepEqual(
      await rpc(platform, "reconcile_pachanga_referee_assignment_v1", reconcileArgs),
      reconciled,
    );
    assert.equal(reconciled.snapshot.assignment.status, "completed");
    const voided = await adminRefereeOk(platform, metadata, {
      action: "assignment.completion.void",
      aggregateId: lifecycleId,
      expectedRevision: reconciled.confirmedRevision,
      payload: { reason: "Wave 4 staging completion cleanup" },
    });
    assert.equal(voided.snapshot.assignment.status, "cancelled");

    const participantEntry = entries.find(({ entryId }) => (
      entryId === replacementFixture.home_entry_id || entryId === replacementFixture.away_entry_id
    ));
    assert.ok(participantEntry);
    const participantRead = await rpc(
      participantEntry.participantClient,
      "get_pachanga_referee_match_assignment_v1",
      { target_canonical_match_id: replacementFixture.canonical_match_id },
    );
    assert.doesNotMatch(JSON.stringify(participantRead), /privateTerms|counterFeeCents|agreedFeeCents/i);
    const managerRead = await rpc(
      staffA,
      "get_pachanga_referee_match_assignment_v1",
      { target_canonical_match_id: replacementFixture.canonical_match_id },
    );
    assert.match(JSON.stringify(managerRead), /privateTerms|agreedFeeCents/i);
    assert.equal(managerRead.canonicalMatchId, participantRead.canonicalMatchId);
    const directWrite = await ownerA.from("pachanga_referee_assignments").insert({ id: randomUUID() });
    assert.ok(directWrite.error, "Authenticated Assignment direct write must remain closed");

    const health = await rpc(platform, "get_pachanga_platform_referee_health_v1");
    assert.equal(health.assignments.activeSlotConflicts, 0);
    assert.equal(health.assignments.timeOverlapConflicts, 0);
    completed = true;
    result = {
      assignments: assignmentIds.length,
      canonicalMatches: contexts.data.length,
      clubs: 3,
      concurrency: "accept_vs_decline_one_winner_one_conflict",
      discipline: "r5_assignment_lineage_and_cleanup",
      profiles: profileActors.length,
      realtime: "invalidation_then_second_device_refetch",
      replacement: "requester_confirmed_atomic_handover",
      schedule: "r4d_reconfirmation_completed",
      status: "PASS",
      terms: "private_counterproposal_confirmed",
    };
  } finally {
    await bestEffort("wave4-active-events", async () => {
      if (!created.competitionId || eventIds.length === 0) return;
      const active = await fixtureAdmin
        .from("pachanga_competition_disciplinary_events")
        .select("id")
        .in("id", eventIds)
        .eq("status", "active");
      if (active.error) throw active.error;
      for (const event of active.data) {
        const competition = await fixtureAdmin
          .from("pachanga_competitions")
          .select("discipline_revision")
          .eq("id", created.competitionId)
          .single();
        if (competition.error) throw competition.error;
        await disciplineOk(staffA, metadata, {
          action: "event.annul",
          aggregateId: event.id,
          competitionId: created.competitionId,
          expectedRevision: competition.data.discipline_revision,
          payload: { correctionReason: "Wave 4 staging failure cleanup" },
        });
      }
    });
    await bestEffort("wave4-active-assignments", async () => {
      if (assignmentIds.length === 0) return;
      const active = await fixtureAdmin
        .from("pachanga_referee_assignments")
        .select("id,status,revision")
        .in("id", assignmentIds)
        .in("status", [...ACTIVE_ASSIGNMENT_STATUSES, "completed"]);
      if (active.error) throw active.error;
      for (const assignment of active.data) {
        if (assignment.status === "completed") {
          await adminRefereeOk(platform, metadata, {
            action: "assignment.completion.void",
            aggregateId: assignment.id,
            expectedRevision: assignment.revision,
            payload: { reason: "Wave 4 staging failure cleanup" },
          });
        } else {
          await assignmentOk(staffA, metadata, {
            action: "assignment.cancel",
            aggregateId: assignment.id,
            expectedRevision: assignment.revision,
            payload: {
              reasonCode: "staging_cleanup",
              reasonText: "Wave 4 authenticated staging cleanup",
            },
          });
        }
      }
    });
    for (const actor of profileActors) {
      await bestEffort(`wave4-profile-${actor.label}`, async () => {
        const profile = await fixtureAdmin
          .from("pachanga_referee_profiles")
          .select("id,operational_status,revision")
          .eq("id", actor.profileId)
          .single();
        if (profile.error) throw profile.error;
        if (profile.data.operational_status !== "active") return;
        await adminRefereeOk(platform, metadata, {
          action: "profile.suspend",
          aggregateId: actor.profileId,
          expectedRevision: profile.data.revision,
          payload: { reason: "Wave 4 staging reusable cleanup" },
        });
      });
    }
    for (const clubId of extraClubIds) {
      await bestEffort(`wave4-club-${clubId}`, () => archiveClub(platform, fixtureAdmin, metadata, clubId));
    }
    if (disciplineFlagsChanged) {
      await bestEffort("wave4-r5-flags", async () => {
        await setDisciplineFlags(
          platform,
          metadata,
          rpc,
          Object.fromEntries(R5_FLAG_KEYS.map((key) => [key, initialR5[key]])),
          "Wave 4 staging R5 restore",
        );
        disciplineFlagsChanged = false;
      });
    }
    if (assignmentFlagsEnabled) {
      await bestEffort("wave4-assignment-flags", async () => {
        await setAssignmentFlags(platform, metadata, rpc, {
          assignmentPrivateBetaEnabled: initialR3.assignmentPrivateBetaEnabled,
          assignmentsEnabled: initialR3.assignmentsEnabled,
        }, "Wave 4 staging Assignment restore");
        assignmentFlagsEnabled = false;
      });
    }
    if (r3Enabled) {
      await bestEffort("wave4-r3-flags", async () => {
        await setR3Flags(
          platform,
          metadata,
          rpc,
          Object.fromEntries(R3_FLAG_KEYS.map((key) => [key, initialR3[key]])),
          "Wave 4 staging R3 restore",
        );
        r3Enabled = false;
      });
    }
    for (const [client, channel] of localChannels) {
      await bestEffort("wave4-realtime-channel", () => client.removeChannel(channel));
    }

    if (profileActors.length > 0) {
      const [activeAssignments, activeEvents, activeRelationships, listedProfiles] = await Promise.all([
        fixtureAdmin.from("pachanga_referee_assignments")
          .select("id", { count: "exact", head: true })
          .in("id", assignmentIds.length ? assignmentIds : ["00000000-0000-0000-0000-000000000000"])
          .in("status", ACTIVE_ASSIGNMENT_STATUSES),
        fixtureAdmin.from("pachanga_competition_disciplinary_events")
          .select("id", { count: "exact", head: true })
          .in("id", eventIds.length ? eventIds : ["00000000-0000-0000-0000-000000000000"])
          .eq("status", "active"),
        fixtureAdmin.from("pachanga_club_referee_relationships")
          .select("id", { count: "exact", head: true })
          .in("referee_profile_id", profileActors.map(({ profileId }) => profileId))
          .eq("status", "active"),
        fixtureAdmin.from("pachanga_referee_profiles")
          .select("id", { count: "exact", head: true })
          .in("id", profileActors.map(({ profileId }) => profileId))
          .eq("marketplace_status", "listed"),
      ]);
      for (const readback of [activeAssignments, activeEvents, activeRelationships, listedProfiles]) {
        if (readback.error) throw readback.error;
        assert.equal(readback.count, 0);
      }
    }
  }

  assert.equal(completed, true, "Wave 4 staging story did not complete");
  return result;
}
