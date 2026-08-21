import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.COMPETITION_FOUNDATION_STAGING_URL;
const publishableKey = process.env.COMPETITION_FOUNDATION_STAGING_PUBLISHABLE_KEY;
const password = process.env.COMPETITION_FOUNDATION_STAGING_PASSWORD;

const required = {
  COMPETITION_FOUNDATION_STAGING_PASSWORD: password,
  COMPETITION_FOUNDATION_STAGING_PUBLISHABLE_KEY: publishableKey,
  COMPETITION_FOUNDATION_STAGING_URL: url,
};

for (const [name, value] of Object.entries(required)) {
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
const FLAGS_AGGREGATE = "00000000-0000-0000-0000-00000000c001";
const CANONICAL_REGISTRY = "00000000-0000-0000-0000-00000000c002";
const CANONICAL_SOURCE_ID = process.env.COMPETITION_FOUNDATION_STAGING_SOURCE_ID
  ?? "r1-staging-canonical-match-20260821";
const EXISTING_CANONICAL_MATCH_ID = process.env.COMPETITION_FOUNDATION_STAGING_CANONICAL_ID
  ?? "af546825-5791-4f6a-b947-8ace313e9595";
const LINKED_OPEN_MATCH_ID = "f1900000-0000-4000-8000-000000000001";
const ORPHAN_OPEN_MATCH_ID = "f1900000-0000-4000-8000-000000000002";

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
  surface = "competition-foundation-staging",
}) {
  return supabase.rpc(name, {
    aggregate_id: aggregateId,
    client_metadata: {
      clientVersion: "1.0.0+r1-staging",
      installedMode: "browser",
      serviceWorkerVersion: "1.0.0+r1-staging",
      surface,
    },
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function commandOk(supabase, name, input) {
  const result = await command(supabase, name, input);
  if (result.error) throw result.error;
  return result.data;
}

function organizer(model, groupId) {
  const selected = model.organizers.find((item) => item.groupId === groupId);
  assert.ok(selected, `Organizer ${groupId} must be visible`);
  return selected;
}

function competitionFrom(receipt) {
  assert.ok(receipt.snapshot?.competition?.id);
  return receipt.snapshot.competition;
}

function itemById(items, id, label) {
  const selected = items.find((item) => item.id === id);
  assert.ok(selected, `${label} ${id} must exist in canonical snapshot`);
  return selected;
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

function createInvalidationQueue() {
  const queued = [];
  let waiter;
  return {
    clear() {
      queued.length = 0;
    },
    next() {
      if (queued.length > 0) return Promise.resolve(queued.shift());
      assert.equal(waiter, undefined, "Only one Realtime invalidation waiter may be active");
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          waiter = undefined;
          reject(new Error("Competition invalidation timed out"));
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

async function platformOverview(supabase) {
  return rpc(supabase, "get_pachanga_platform_competition_foundation_v1", {
    page_offset: 0,
    page_size: 200,
  });
}

async function normalizeFixtureControlState(platformOwner) {
  let overview = await platformOverview(platformOwner);
  for (;;) {
    const activeFixtureGrant = overview.entitlements.find((grant) => (
      [GROUP_A, GROUP_B].includes(grant.organizerGroupId)
      && grant.status !== "revoked"
    ));
    if (!activeFixtureGrant) break;
    await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
      action: "entitlement.revoke",
      aggregateId: activeFixtureGrant.organizerGroupId,
      expectedRevision: activeFixtureGrant.organizerRevision,
      payload: {
        entitlementId: activeFixtureGrant.id,
        reason: "Normalize previous R1 staging fixture",
      },
      surface: "competition-foundation-staging-cleanup",
    });
    overview = await platformOverview(platformOwner);
  }

  if (
    overview.flags.foundationEnabled
    || overview.flags.creationEnabled
    || overview.flags.contextBindingEnabled
  ) {
    await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
      action: "foundation_flags.set",
      aggregateId: FLAGS_AGGREGATE,
      expectedRevision: overview.flags.revision,
      payload: {
        contextBindingEnabled: false,
        creationEnabled: false,
        foundationEnabled: false,
        reason: "Normalize previous R1 staging fixture",
      },
      surface: "competition-foundation-staging-cleanup",
    });
    overview = await platformOverview(platformOwner);
  }
  return overview;
}

async function normalizeFixtureStaffAssignments(platformOwner) {
  let overview = await platformOverview(platformOwner);
  if (!overview.flags.foundationEnabled) return overview;
  for (const competition of overview.items) {
    let snapshot = await rpc(platformOwner, "get_pachanga_competition_foundation_snapshot_v1", {
      target_competition_id: competition.id,
    });
    for (;;) {
      const activeFixtureStaff = snapshot.staff.find((assignment) => (
        [USERS.ownerA.id, USERS.staffA.id].includes(assignment.userId)
        && assignment.status === "active"
      ));
      if (!activeFixtureStaff) break;
      const receipt = await commandOk(
        platformOwner,
        "command_pachanga_competition_foundation_v1",
        {
          action: "staff.revoke",
          aggregateId: competition.id,
          expectedRevision: snapshot.competition.revision,
          payload: { staffAssignmentId: activeFixtureStaff.id },
          surface: "competition-foundation-staging-cleanup",
        },
      );
      snapshot = receipt.snapshot;
    }
  }
  return platformOverview(platformOwner);
}

const clients = [];
let realtimeChannel;
let platformOwner;
let completed = false;

try {
  platformOwner = await signIn(USERS.platformOwner);
  clients.push(platformOwner);
  const ownerDesktop = await signIn(USERS.ownerA);
  const ownerMobile = await signIn(USERS.ownerA);
  const adminA = await signIn(USERS.adminA);
  const playerA = await signIn(USERS.playerA);
  const ownerB = await signIn(USERS.ownerB);
  const staffA = await signIn(USERS.staffA);
  const platformAdmin = await signIn(USERS.platformAdmin);
  clients.push(ownerDesktop, ownerMobile, adminA, playerA, ownerB, staffA, platformAdmin);
  const anonymous = client();

  let overview = await normalizeFixtureControlState(platformOwner);
  assert.equal(overview.flags.foundationEnabled, false);
  assert.equal(overview.flags.creationEnabled, false);

  const anonymousRead = await anonymous.rpc("get_my_pachanga_competition_foundation_v1");
  assert.ok(anonymousRead.error);

  const disabledOwnerModel = await rpc(ownerDesktop, "get_my_pachanga_competition_foundation_v1");
  const disabledCreate = await command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "competition.create",
    aggregateId: GROUP_A,
    expectedRevision: organizer(disabledOwnerModel, GROUP_A).entitlement.organizerRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "Disabled staging league",
      slug: `disabled-staging-${Date.now()}`,
    },
  });
  expectRpcError(disabledCreate, /COMPETITION_FOUNDATION_DISABLED/);

  let platformAdminOverviewResult = await platformAdmin.rpc(
    "get_pachanga_platform_competition_foundation_v1",
    { page_offset: 0, page_size: 10 },
  );
  if (platformAdminOverviewResult.error) {
    const roleAssignment = await rpc(platformOwner, "set_pachanga_platform_role_v1", {
      expected_revision: 0,
      next_active: true,
      next_role: "platform_admin",
      operation_id: randomUUID(),
      reason: "R1 staging platform admin fixture",
      target_user_id: USERS.platformAdmin.id,
    });
    assert.equal(roleAssignment.role, "platform_admin");
    platformAdminOverviewResult = await platformAdmin.rpc(
      "get_pachanga_platform_competition_foundation_v1",
      { page_offset: 0, page_size: 10 },
    );
  }
  assert.equal(platformAdminOverviewResult.error, null);
  const platformAdminOverview = platformAdminOverviewResult.data;
  assert.ok(platformAdminOverview.flags);

  const invalidations = createInvalidationQueue();
  realtimeChannel = ownerMobile
    .channel(`competition-foundation-staging-${randomUUID()}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `organizer_group_id=eq.${GROUP_A}`,
      schema: "public",
      table: "pachanga_competition_invalidations",
    }, (payload) => invalidations.push(payload));
  await waitForSubscription(realtimeChannel);

  const flagsOn = await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
    action: "foundation_flags.set",
    aggregateId: FLAGS_AGGREGATE,
    expectedRevision: overview.flags.revision,
    payload: {
      contextBindingEnabled: true,
      creationEnabled: true,
      foundationEnabled: true,
      reason: "R1 authenticated staging QA",
    },
  });
  assert.equal(flagsOn.snapshot.foundationEnabled, true);
  assert.equal(flagsOn.snapshot.creationEnabled, true);

  await normalizeFixtureStaffAssignments(platformOwner);
  const ordinaryRead = await rpc(staffA, "get_my_pachanga_competition_foundation_v1");
  assert.deepEqual(ordinaryRead.organizers, []);
  assert.deepEqual(ordinaryRead.competitions, []);
  const ordinaryPlatformRead = await staffA.rpc("get_pachanga_platform_competition_foundation_v1", {
    page_offset: 0,
    page_size: 10,
  });
  assert.ok(ordinaryPlatformRead.error);

  invalidations.clear();
  const ownerModelBeforeGrant = await rpc(ownerDesktop, "get_my_pachanga_competition_foundation_v1");
  const entitlementInvalidationPromise = invalidations.next();
  const entitlementA = await commandOk(platformAdmin, "command_pachanga_competition_platform_v1", {
    action: "entitlement.grant",
    aggregateId: GROUP_A,
    expectedRevision: organizer(ownerModelBeforeGrant, GROUP_A).entitlement.organizerRevision,
    payload: {
      capability: "competition_create",
      reason: "R1 Team A staging grant",
    },
  });
  assert.equal(entitlementA.snapshot.canCreate, true);
  const entitlementInvalidation = await entitlementInvalidationPromise;
  assert.equal(entitlementInvalidation.new.organizer_group_id, GROUP_A);
  assert.equal(entitlementInvalidation.new.revision, entitlementA.confirmedRevision);

  const ownerBModel = await rpc(ownerB, "get_my_pachanga_competition_foundation_v1");
  const expiredGrant = await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
    action: "entitlement.grant",
    aggregateId: GROUP_B,
    expectedRevision: organizer(ownerBModel, GROUP_B).entitlement.organizerRevision,
    payload: {
      capability: "competition_create",
      expiresAt: "2026-01-02T00:00:00Z",
      reason: "R1 expired staging grant",
      validFrom: "2026-01-01T00:00:00Z",
    },
  });
  assert.equal(expiredGrant.snapshot.canCreate, false);

  const ownerBCreate = await command(ownerB, "command_pachanga_competition_foundation_v1", {
    action: "competition.create",
    aggregateId: GROUP_B,
    expectedRevision: expiredGrant.confirmedRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "Expired grant league",
      slug: `expired-grant-${Date.now()}`,
    },
  });
  expectRpcError(ownerBCreate, /COMPETITION_ENTITLEMENT_REQUIRED/, "42501");

  let canonicalSnapshot;
  if (EXISTING_CANONICAL_MATCH_ID) {
    canonicalSnapshot = await rpc(platformOwner, "get_pachanga_platform_canonical_match_v1", {
      target_canonical_match_id: EXISTING_CANONICAL_MATCH_ID,
    });
  } else {
    const canonicalBind = await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
      action: "canonical.bind",
      aggregateId: CANONICAL_REGISTRY,
      expectedRevision: flagsOn.confirmedRevision,
      payload: {
        reason: "R1 staging canonical source",
        sourceGroupId: GROUP_A,
        sourceId: CANONICAL_SOURCE_ID,
        sourceKind: "group_match",
      },
    });
    canonicalSnapshot = canonicalBind.snapshot;
  }
  const canonicalMatchId = canonicalSnapshot.canonicalMatch.id;
  const canonicalRevision = canonicalSnapshot.canonicalMatch.revision;
  assert.ok(canonicalSnapshot.bindings.some((binding) => (
    binding.sourceKind === "group_match"
    && binding.sourceGroupId === GROUP_A
    && binding.sourceId === CANONICAL_SOURCE_ID
  )));

  await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
    action: "canonical.backfill",
    aggregateId: CANONICAL_REGISTRY,
    expectedRevision: flagsOn.confirmedRevision,
    payload: { reason: "R1 staging exact-source backfill" },
  });
  const repeatedBackfill = await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
    action: "canonical.backfill",
    aggregateId: CANONICAL_REGISTRY,
    expectedRevision: flagsOn.confirmedRevision,
    payload: { reason: "R1 repeated staging exact-source backfill" },
  });
  assert.deepEqual(repeatedBackfill.snapshot.backfill, {
    canonicalMatchesCreated: 0,
    challengeBindingsCreated: 0,
    externalBindingsCreated: 0,
    groupBindingsCreated: 0,
    openBindingsCreated: 0,
    reviewsCreated: 0,
  });
  const canonicalAfterBackfill = await rpc(platformOwner, "get_pachanga_platform_canonical_match_v1", {
    target_canonical_match_id: canonicalMatchId,
  });
  assert.ok(canonicalAfterBackfill.bindings.some((binding) => (
    binding.sourceKind === "open_match"
    && binding.sourceGroupId === GROUP_A
    && binding.sourceId === LINKED_OPEN_MATCH_ID
  )));
  const backfillOverview = await platformOverview(platformOwner);
  assert.ok(backfillOverview.reviews.some((review) => (
    review.leftSourceKind === "open_match"
    && review.leftSourceGroupId === GROUP_A
    && review.leftSourceId === ORPHAN_OPEN_MATCH_ID
    && review.reasonCode === "orphan_open_match_source"
    && review.status === "pending"
  )));

  const runTag = `${Date.now()}-${randomUUID().slice(0, 8)}`;
  const createOperationId = randomUUID();
  const createInput = {
    action: "competition.create",
    aggregateId: GROUP_A,
    expectedRevision: entitlementA.confirmedRevision,
    operationId: createOperationId,
    payload: {
      competitionType: "LEAGUE",
      name: `Liga staging R1 ${runTag}`,
      reason: "R1 main staging story",
      slug: `liga-staging-r1-${runTag}`,
      visibility: "private",
    },
  };
  const invalidationPromise = invalidations.next();
  const competitionReceipt = await commandOk(
    ownerDesktop,
    "command_pachanga_competition_foundation_v1",
    createInput,
  );
  const replay = await commandOk(ownerMobile, "command_pachanga_competition_foundation_v1", {
    ...createInput,
    surface: "competition-foundation-staging-mobile",
  });
  assert.deepEqual(replay, competitionReceipt);
  const reusedOperation = await command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    ...createInput,
    payload: { ...createInput.payload, name: "Different payload" },
  });
  expectRpcError(reusedOperation, /IDEMPOTENCY_KEY_REUSED/, "PT409");

  const competition = competitionFrom(competitionReceipt);
  const realtimeInvalidation = await invalidationPromise;
  assert.equal(realtimeInvalidation.new.competition_id, competition.id);
  assert.equal(realtimeInvalidation.new.revision, competitionReceipt.confirmedRevision);
  const mobileRefetch = await rpc(ownerMobile, "get_my_pachanga_competition_foundation_v1");
  assert.ok(mobileRefetch.competitions.some((item) => item.competition.id === competition.id));

  const adminCreate = await command(adminA, "command_pachanga_competition_foundation_v1", {
    action: "competition.create",
    aggregateId: GROUP_A,
    expectedRevision: competitionReceipt.confirmedRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "Admin must not create",
      slug: `admin-denied-${runTag}`,
    },
  });
  expectRpcError(adminCreate, /COMPETITION_OWNER_REQUIRED/, "42501");
  const playerCreate = await command(playerA, "command_pachanga_competition_foundation_v1", {
    action: "competition.create",
    aggregateId: GROUP_A,
    expectedRevision: competitionReceipt.confirmedRevision,
    payload: {
      competitionType: "LEAGUE",
      name: "Player must not create",
      slug: `player-denied-${runTag}`,
    },
  });
  expectRpcError(playerCreate, /COMPETITION_OWNER_REQUIRED/, "42501");

  const directInsert = await ownerDesktop.from("pachanga_competitions").insert({
    competition_type: "LEAGUE",
    name: "Forbidden direct insert",
    organizer_group_id: GROUP_A,
    slug: `forbidden-direct-${runTag}`,
  });
  assert.ok(directInsert.error);
  const directRead = await platformOwner.from("pachanga_competitions").select("id").limit(1);
  assert.ok(directRead.error);

  const concurrentExpectedRevision = competitionReceipt.confirmedRevision;
  const concurrentCreates = await Promise.all([
    command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
      action: "competition.create",
      aggregateId: GROUP_A,
      expectedRevision: concurrentExpectedRevision,
      payload: {
        competitionType: "TOURNAMENT",
        name: `Concurrent desktop ${runTag}`,
        slug: `concurrent-desktop-${runTag}`,
      },
    }),
    command(ownerMobile, "command_pachanga_competition_foundation_v1", {
      action: "competition.create",
      aggregateId: GROUP_A,
      expectedRevision: concurrentExpectedRevision,
      payload: {
        competitionType: "TOURNAMENT",
        name: `Concurrent mobile ${runTag}`,
        slug: `concurrent-mobile-${runTag}`,
      },
    }),
  ]);
  assert.equal(concurrentCreates.filter((result) => !result.error).length, 1);
  assert.equal(concurrentCreates.filter((result) => result.error).length, 1);
  const staleCreate = concurrentCreates.find((result) => result.error);
  expectRpcError(staleCreate, /STALE_REVISION/, "PT409");
  const concurrentWinner = concurrentCreates.find((result) => !result.error).data;
  const unrelatedCompetitionId = competitionFrom(concurrentWinner).id;

  let competitionRevision = competition.revision;
  const editionReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "edition.create",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: {
      endsAt: "2027-06-30",
      name: "Edicion 2026/27",
      seasonLabel: "2026/27",
      startsAt: "2026-09-01",
    },
  });
  competitionRevision = editionReceipt.confirmedRevision;
  const edition = editionReceipt.snapshot.editions.find((item) => item.name === "Edicion 2026/27");
  assert.ok(edition);

  const ruleSetReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "rule_set.create",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { name: "Reglamento Liga F7" },
  });
  competitionRevision = ruleSetReceipt.confirmedRevision;
  const ruleSet = ruleSetReceipt.snapshot.ruleSets.find((item) => item.name === "Reglamento Liga F7");
  assert.ok(ruleSet);

  const staffGrantReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "staff.grant",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { staffRole: "competition_admin", userId: USERS.staffA.id },
  });
  competitionRevision = staffGrantReceipt.confirmedRevision;
  const staffAssignment = staffGrantReceipt.snapshot.staff.find((item) => item.userId === USERS.staffA.id);
  assert.ok(staffAssignment);

  const oldOwnerStaffReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "staff.grant",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { staffRole: "rules_manager", userId: USERS.ownerA.id },
  });
  competitionRevision = oldOwnerStaffReceipt.confirmedRevision;

  const staffRead = await rpc(staffA, "get_pachanga_competition_foundation_snapshot_v1", {
    target_competition_id: competition.id,
  });
  assert.equal(staffRead.competition.id, competition.id);
  const staffCrossRead = await staffA.rpc("get_pachanga_competition_foundation_snapshot_v1", {
    target_competition_id: unrelatedCompetitionId,
  });
  expectRpcError(staffCrossRead, /COMPETITION_ACCESS_DENIED/, "42501");
  const groupAdminRead = await adminA.rpc("get_pachanga_competition_foundation_snapshot_v1", {
    target_competition_id: competition.id,
  });
  expectRpcError(groupAdminRead, /COMPETITION_ACCESS_DENIED/, "42501");

  const staffEdition = await commandOk(staffA, "command_pachanga_competition_foundation_v1", {
    action: "edition.create",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { name: "Edicion auxiliar QA", seasonLabel: "QA" },
  });
  competitionRevision = staffEdition.confirmedRevision;

  let ruleSetRevision = ruleSet.revision;
  const ruleRevisionReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "rule_revision.create",
    aggregateId: ruleSet.id,
    expectedRevision: ruleSetRevision,
    payload: {
      effectiveFrom: "2026-09-01T00:00:00Z",
      effectiveScope: "future_only",
      reason: "Initial R1 staging rules",
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
        registration: { maximumPlayers: 25, minimumPlayers: 7 },
        results: { scoringPolicy: {}, tieBreakCriteria: [] },
        structure: {
          stageGraph: {
            edges: [{ from: "split-1", order: 0, to: "finals" }],
            nodes: [{ id: "split-1", root: true }, { id: "finals", optional: true }],
          },
        },
      },
      schemaVersion: "competition_rules.v1",
    },
  });
  ruleSetRevision = ruleRevisionReceipt.confirmedRevision;
  const ruleRevision = itemById(
    itemById(ruleRevisionReceipt.snapshot.ruleSets, ruleSet.id, "Rule set").revisions,
    ruleRevisionReceipt.snapshot.ruleSets
      .find((item) => item.id === ruleSet.id).revisions[0].id,
    "Rule revision",
  );

  const validatedReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "rule_revision.validate",
    aggregateId: ruleRevision.id,
    expectedRevision: ruleRevision.revision,
  });
  assert.equal(validatedReceipt.snapshot.ruleSets
    .find((item) => item.id === ruleSet.id).revisions
    .find((item) => item.id === ruleRevision.id).status, "validated");
  const publishedReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "rule_revision.publish",
    aggregateId: ruleSet.id,
    expectedRevision: ruleSetRevision,
    payload: { ruleRevisionId: ruleRevision.id },
  });
  ruleSetRevision = publishedReceipt.confirmedRevision;
  assert.ok(ruleSetRevision > ruleSet.revision);

  const editionRuleReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "edition.assign_rule_revision",
    aggregateId: edition.id,
    expectedRevision: edition.revision,
    payload: { ruleRevisionId: ruleRevision.id },
  });
  let editionRevision = editionRuleReceipt.confirmedRevision;
  const publishedRuleRevision = itemById(
    itemById(publishedReceipt.snapshot.ruleSets, ruleSet.id, "Rule set").revisions,
    ruleRevision.id,
    "Rule revision",
  );
  const frozenReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "rule_revision.freeze",
    aggregateId: ruleRevision.id,
    expectedRevision: publishedRuleRevision.revision,
  });
  assert.equal(frozenReceipt.snapshot.ruleSets
    .find((item) => item.id === ruleSet.id).revisions
    .find((item) => item.id === ruleRevision.id).status, "frozen");

  const splitReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "stage.create",
    aggregateId: edition.id,
    expectedRevision: editionRevision,
    payload: {
      name: "Split 1",
      optional: false,
      ruleRevisionId: ruleRevision.id,
      stageOrder: 0,
      stageType: "SPLIT",
    },
  });
  editionRevision = splitReceipt.confirmedRevision;
  const split = splitReceipt.snapshot.stages.find((item) => item.name === "Split 1");
  assert.ok(split);

  const finalsReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "stage.create",
    aggregateId: edition.id,
    expectedRevision: editionRevision,
    payload: {
      name: "Finals",
      optional: true,
      ruleRevisionId: ruleRevision.id,
      stageOrder: 1,
      stageType: "FINALS",
    },
  });
  editionRevision = finalsReceipt.confirmedRevision;
  const finals = finalsReceipt.snapshot.stages.find((item) => item.name === "Finals");
  assert.ok(finals);

  const edgeReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "stage_edge.create",
    aggregateId: edition.id,
    expectedRevision: editionRevision,
    payload: { edgeOrder: 0, fromStageId: split.id, toStageId: finals.id },
  });
  editionRevision = edgeReceipt.confirmedRevision;
  const cycle = await command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "stage_edge.create",
    aggregateId: edition.id,
    expectedRevision: editionRevision,
    payload: { edgeOrder: 1, fromStageId: finals.id, toStageId: split.id },
  });
  expectRpcError(cycle, /STAGE_GRAPH_CYCLE/, "22023");

  let splitRevision = split.revision;
  const divisionReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "division.create",
    aggregateId: split.id,
    expectedRevision: splitRevision,
    payload: { levelLabel: "Nivel 1", name: "Division 1", order: 0 },
  });
  splitRevision = divisionReceipt.confirmedRevision;
  const division = divisionReceipt.snapshot.stages
    .find((item) => item.id === split.id).divisions
    .find((item) => item.name === "Division 1");
  assert.ok(division);

  const groupReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "group.create",
    aggregateId: split.id,
    expectedRevision: splitRevision,
    payload: { divisionId: division.id, name: "Grupo A", order: 0 },
  });
  const competitionGroup = groupReceipt.snapshot.stages
    .find((item) => item.id === split.id).groups
    .find((item) => item.name === "Grupo A");
  assert.ok(competitionGroup);

  const unavailableTransition = await command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "edition.active",
    aggregateId: edition.id,
    expectedRevision: editionRevision,
  });
  expectRpcError(unavailableTransition, /FEATURE_NOT_AVAILABLE/, "0A000");

  if (canonicalAfterBackfill.contexts.length === 0) {
    const contextReceipt = await commandOk(platformOwner, "command_pachanga_competition_platform_v1", {
      action: "competition_match_context.bind",
      aggregateId: canonicalMatchId,
      expectedRevision: canonicalRevision,
      payload: {
        competitionId: competition.id,
        divisionId: division.id,
        editionId: edition.id,
        groupId: competitionGroup.id,
        reason: "R1 staging laboratory context",
        ruleRevisionId: ruleRevision.id,
        stageId: split.id,
      },
    });
    assert.equal(contextReceipt.snapshot.canonical.contexts[0].competitionId, competition.id);
  } else {
    assert.equal(canonicalAfterBackfill.contexts.length, 1);
    const [persistedContext] = canonicalAfterBackfill.contexts;
    assert.ok(persistedContext.competitionId);
    assert.ok(persistedContext.editionId);
    assert.ok(persistedContext.ruleRevisionId);
    assert.ok(persistedContext.stageId);
  }

  const forbiddenFrozenUpdate = await platformOwner
    .from("pachanga_competition_rule_revisions")
    .update({ rule_document: { tampered: true } })
    .eq("id", ruleRevision.id);
  assert.ok(forbiddenFrozenUpdate.error);

  const groupRevisionRead = await ownerDesktop
    .from("pachanga_groups")
    .select("payload_revision")
    .eq("id", GROUP_A)
    .single();
  assert.equal(groupRevisionRead.error, null);
  const transferToPlayer = await rpc(ownerDesktop, "transfer_pachanga_group_ownership_authoritative_v1", {
    client_metadata: {
      clientVersion: "1.0.0+r1-staging",
      installedMode: "browser",
      surface: "competition-owner-transfer-staging",
    },
    expected_revision: Number(groupRevisionRead.data.payload_revision),
    operation_id: randomUUID(),
    target_group_id: GROUP_A,
    target_user_id: USERS.playerA.id,
  });
  assert.equal(transferToPlayer.membershipStatus, "owner");
  const newOwnerModel = await rpc(playerA, "get_my_pachanga_competition_foundation_v1");
  const newOwnerOrganizer = organizer(newOwnerModel, GROUP_A);
  assert.equal(newOwnerOrganizer.owner, true);
  assert.equal(newOwnerOrganizer.entitlement.canCreate, true);
  assert.ok(newOwnerModel.competitions.some((item) => item.competition.id === competition.id));

  const previousOwnerModel = await rpc(ownerDesktop, "get_my_pachanga_competition_foundation_v1");
  assert.ok(previousOwnerModel.competitions.some((item) => item.competition.id === competition.id));
  const previousOwnerManage = await command(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "edition.create",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { name: "Old owner must not manage", seasonLabel: "denied" },
  });
  expectRpcError(previousOwnerManage, /COMPETITION_ACCESS_DENIED/, "42501");

  const newOwnerCompetition = await commandOk(playerA, "command_pachanga_competition_foundation_v1", {
    action: "competition.create",
    aggregateId: GROUP_A,
    expectedRevision: newOwnerOrganizer.entitlement.organizerRevision,
    payload: {
      competitionType: "TOURNAMENT",
      name: `New owner authority ${runTag}`,
      slug: `new-owner-authority-${runTag}`,
    },
  });
  assert.ok(newOwnerCompetition.snapshot.competition.id);

  const transferBack = await rpc(playerA, "transfer_pachanga_group_ownership_authoritative_v1", {
    client_metadata: {
      clientVersion: "1.0.0+r1-staging",
      installedMode: "browser",
      surface: "competition-owner-transfer-staging",
    },
    expected_revision: transferToPlayer.confirmedRevision,
    operation_id: randomUUID(),
    target_group_id: GROUP_A,
    target_user_id: USERS.ownerA.id,
  });
  assert.equal(transferBack.membershipStatus, "owner");

  const staffRevokeReceipt = await commandOk(ownerDesktop, "command_pachanga_competition_foundation_v1", {
    action: "staff.revoke",
    aggregateId: competition.id,
    expectedRevision: competitionRevision,
    payload: { staffAssignmentId: staffAssignment.id },
  });
  competitionRevision = staffRevokeReceipt.confirmedRevision;
  const revokedStaffRead = await staffA.rpc("get_pachanga_competition_foundation_snapshot_v1", {
    target_competition_id: competition.id,
  });
  expectRpcError(revokedStaffRead, /COMPETITION_ACCESS_DENIED/, "42501");

  await normalizeFixtureStaffAssignments(platformOwner);
  overview = await normalizeFixtureControlState(platformOwner);
  assert.equal(overview.flags.foundationEnabled, false);
  assert.equal(overview.flags.creationEnabled, false);
  assert.equal(overview.flags.contextBindingEnabled, false);
  const historyAfterRevocation = await rpc(ownerDesktop, "get_my_pachanga_competition_foundation_v1");
  assert.ok(historyAfterRevocation.competitions.some((item) => item.competition.id === competition.id));
  assert.equal(organizer(historyAfterRevocation, GROUP_A).entitlement.canCreate, false);

  const finalHealth = await platformOverview(platformOwner);
  assert.equal(finalHealth.bindingHealth.stale, false);
  assert.ok(finalHealth.metrics.events >= finalHealth.metrics.receipts);
  assert.equal(finalHealth.flags.foundationEnabled, false);

  completed = true;
  console.log(JSON.stringify({
    canonicalBackfillIdempotent: true,
    canonicalContextBound: true,
    competitionId: competition.id,
    concurrency: "one_winner_one_stale",
    entitlementExpiryRejected: true,
    entitlementRevocationPreservedHistory: true,
    featureFlagsRestoredOff: true,
    frozenHistoryProtected: true,
    idempotentReplayConverged: true,
    ownerTransferVerified: true,
    platformAdminVerified: true,
    realtimeInvalidationRefetched: true,
    staffScopeAndRevocationVerified: true,
  }));
} finally {
  if (platformOwner && !completed) {
    try {
      await normalizeFixtureStaffAssignments(platformOwner);
      await normalizeFixtureControlState(platformOwner);
    } catch (error) {
      console.error("R1_STAGING_CLEANUP_FAILED", error instanceof Error ? error.message : String(error));
    }
  }
  if (realtimeChannel && clients[2]) await clients[2].removeChannel(realtimeChannel);
  for (const supabase of clients) {
    await supabase.auth.signOut({ scope: "local" }).catch(() => undefined);
    await supabase.realtime.disconnect();
  }
}
process.exit(0);
