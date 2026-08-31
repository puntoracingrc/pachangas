import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

import { createClient } from "@supabase/supabase-js";

const env = {
  confirmation: process.env.SEASON_VENUE_STAGING_CONFIRM,
  databasePassword: process.env.SEASON_VENUE_STAGING_DATABASE_PASSWORD,
  databaseUri: process.env.SEASON_VENUE_STAGING_DATABASE_URI,
  previewUrl: process.env.SEASON_VENUE_STAGING_PREVIEW_URL,
  projectRef: process.env.SEASON_VENUE_STAGING_PROJECT_REF,
  publishableKey: process.env.SEASON_VENUE_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.SEASON_VENUE_STAGING_SERVICE_ROLE_KEY,
  url: process.env.SEASON_VENUE_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (!value) throw new Error(`SEASON_VENUE_STAGING_${key.toUpperCase()}_REQUIRED`);
}

const productionRef = "qonbngfrnrqgmxbdfbea";
const actualRef = new URL(env.url).hostname.split(".")[0];
const databaseUri = new URL(env.databaseUri);
if (
  env.confirmation !== "SEASON_VENUE_STAGING_ONLY"
  || env.projectRef === productionRef
  || actualRef !== env.projectRef
  || databaseUri.password
  || databaseUri.hostname === `db.${productionRef}.supabase.co`
  || !databaseUri.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(databaseUri.username).endsWith(`.${env.projectRef}`)
  || /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)
) throw new Error("SEASON_VENUE_STAGING_PRODUCTION_TARGET_FORBIDDEN");
assert.notEqual(env.publishableKey, env.serviceRoleKey);

const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `Wave9B-${randomUUID()}-Qa!`;
const accounts = [];
const clients = [];
const channels = [];
const competitionId = "c4200000-0000-4000-8000-000000000001";
const editionId = "c4200000-0000-4000-8000-000000000004";
const stageId = "c4200000-0000-4000-8000-000000000006";
const ruleRevisionId = "e9050000-0000-4000-8000-000000000001";
const schedulePlanId = "e9070000-0000-4000-8000-000000000001";
const scheduleRevisionId = "e9070000-0000-4000-8000-000000000002";
const scheduleItemId = "e9070000-0000-4000-8000-000000000005";
const canonicalMatchId = "e9070000-0000-4000-8000-000000000006";
const matchContextId = "e9070000-0000-4000-8000-000000000008";
const clubId = "e9020000-0000-4000-8000-000000000001";
const teamId = "c4100000-0000-4000-8000-000000000002";
const venueId = "e9b20000-0000-4000-8000-000000000001";
const pitchAlphaId = "e9b20000-0000-4000-8000-000000000011";
const pitchBetaId = "e9b20000-0000-4000-8000-000000000012";
const refereeProfileId = "d6020000-0000-4000-8000-000000000001";
const originalRefereeUserId = "d6010000-0000-4000-8000-000000000001";
const assignmentId = "e9b30000-0000-4000-8000-000000000001";

function client(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
  });
}

const service = client(env.serviceRoleKey);

function metadata(surface) {
  return {
    clientVersion: "9.2.0+wave9b-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "9.2.0+wave9b-staging",
    sessionId: `wave9b-${runId}`,
    surface,
  };
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", env.databaseUri,
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      PGPASSWORD: env.databasePassword,
      PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=120s",
    },
    input: sql,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label}: ${result.stderr || result.stdout}`);
  return (result.stdout ?? "").trim();
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean).join(" ");
}

function allocationCommand(supabase, {
  action,
  aggregateId = null,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return supabase.rpc("command_pachanga_competition_venue_allocation_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("wave9b-staging-authenticated"),
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function allocationOk(supabase, input) {
  const result = await allocationCommand(supabase, input);
  if (result.error) throw new Error(`${input.action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function reservationCommand(supabase, {
  action,
  aggregateId = null,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return supabase.rpc("command_pachanga_venue_reservation_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("wave9b-staging-r4d"),
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function reservationOk(supabase, input) {
  const result = await reservationCommand(supabase, input);
  if (result.error) throw new Error(`${input.action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function assignmentCommand(supabase, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return supabase.rpc("command_pachanga_referee_assignment_beta_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("wave9b-staging-referee"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function assignmentOk(supabase, input) {
  const result = await assignmentCommand(supabase, input);
  if (result.error) throw new Error(`${input.action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

async function getFlags(supabase) {
  const result = await supabase.rpc("get_pachanga_venue_flags_v1");
  if (result.error) throw result.error;
  return result.data;
}

async function setFlags(supabase, expectedRevision, flagUpdates) {
  const result = await supabase.rpc("set_pachanga_venue_flags_v1", {
    client_metadata: metadata("wave9b-staging-flags"),
    expected_revision: expectedRevision,
    flag_updates: flagUpdates,
    operation_id: randomUUID(),
  });
  if (result.error) throw result.error;
  return result.data;
}

async function desk(supabase, planId) {
  const result = await supabase.rpc("get_pachanga_competition_venue_allocation_desk_v1", {
    target_plan_id: planId,
  });
  if (result.error) throw result.error;
  return result.data;
}

async function createAccount(label) {
  const account = {
    email: `wave9b-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const created = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "SEASON_VENUE_ALLOCATION_V1", runId },
  });
  if (created.error) throw created.error;
  accounts.push(account);
  return account;
}

async function signIn(account) {
  const supabase = client();
  const signedIn = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (signedIn.error) throw signedIn.error;
  assert.equal(signedIn.data.user.id, account.id);
  await supabase.realtime.setAuth(signedIn.data.session.access_token);
  clients.push(supabase);
  return { accessToken: signedIn.data.session.access_token, supabase };
}

function eventQueue() {
  const pending = [];
  const waiters = [];
  return {
    push(event) {
      const index = waiters.findIndex(({ predicate }) => predicate(event));
      if (index >= 0) {
        const [{ resolve, timeout }] = waiters.splice(index, 1);
        clearTimeout(timeout);
        resolve(event);
      } else pending.push(event);
    },
    wait(predicate, label) {
      const index = pending.findIndex(predicate);
      if (index >= 0) return Promise.resolve(pending.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          const waiter = waiters.findIndex((entry) => entry.timeout === timeout);
          if (waiter >= 0) waiters.splice(waiter, 1);
          reject(new Error(`WAVE9B_REALTIME_TIMEOUT:${label}`));
        }, 30_000);
        waiters.push({ predicate, resolve, reject, timeout });
      });
    },
  };
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("WAVE9B_REALTIME_SUBSCRIPTION_TIMEOUT")), 30_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`WAVE9B_REALTIME_${status}`));
      }
    });
  });
}

function postgresChangesBinding(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("WAVE9B_POSTGRES_CHANGES_BINDING_TIMEOUT")), 30_000);
    queue.binding = (payload) => {
      if (payload?.extension !== "postgres_changes") return;
      clearTimeout(timeout);
      if (payload.status === "ok") resolve(payload);
      else reject(new Error(`WAVE9B_POSTGRES_CHANGES_BINDING_${String(payload.status || "ERROR").toUpperCase()}`));
    };
  });
}

async function previewSmoke(accessToken, planId, expectedRevision) {
  const origin = new URL(env.previewUrl).origin;
  const assets = [
    "/manifest.webmanifest",
    "/sw.js",
    "/demo-world/v3-5/manifest.json",
    "/demo",
    `/competiciones/${competitionId}/gestion/campos`,
    `/competiciones/${competitionId}/gestion/campos/plan`,
    "/clubes/gestionar/campos/bloques",
    "/clubes/gestionar/campos/pools",
    "/reservas/recurrentes",
  ];
  for (const path of assets) {
    const response = await fetch(new URL(path, origin), { cache: "no-store", redirect: "follow" });
    assert.equal(response.ok, true, `${path} returned ${response.status}`);
    if (path === "/sw.js") {
      const body = await response.text();
      assert.match(response.headers.get("cache-control") ?? "", /no-store/);
      assert.match(body, /demo-world\/v3-5/);
      assert.doesNotMatch(body, /api\/season-venues/);
    }
  }

  const readUrl = new URL("/api/season-venues/read", origin);
  readUrl.searchParams.set("view", "desk");
  readUrl.searchParams.set("planId", planId);
  const read = await fetch(readUrl, {
    cache: "no-store",
    headers: { authorization: `Bearer ${accessToken}` },
  });
  assert.equal(read.status, 200);
  assert.match(read.headers.get("cache-control") ?? "", /no-store/);
  const readModel = await read.json();
  assert.equal(readModel.plan.planId, planId);

  const stale = await fetch(new URL("/api/season-venues/command", origin), {
    body: JSON.stringify({
      action: "allocation.cancel",
      aggregateId: planId,
      expectedRevision: expectedRevision - 1,
      operationId: randomUUID(),
      payload: { reasonCode: "STAGING_STALE_PREVIEW" },
    }),
    headers: {
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
      origin,
      "x-pachangas-client-version": "9.2.0+wave9b-staging",
      "x-pachangas-display-mode": "standalone",
      "x-pachangas-service-worker-version": "9.2.0+wave9b-staging",
    },
    method: "POST",
  });
  assert.equal(stale.status, 409);
  assert.equal((await stale.json()).error, "VENUE_OPERATION_REJECTED");

  const readAfter = await fetch(readUrl, {
    cache: "no-store",
    headers: { authorization: `Bearer ${accessToken}` },
  });
  assert.equal(readAfter.status, 200);
  assert.equal((await readAfter.json()).plan.revision, expectedRevision);
  return { authenticatedRead: "PASS", paths: assets.length, staleWrite: "REJECTED" };
}

const wave9bFlagKeys = [
  "venueRecurringSeriesEnabled",
  "venueRecurringMaterializationEnabled",
  "competitionVenuePoolEnabled",
  "competitionVenueAllocationFoundationEnabled",
  "competitionVenueAllocationAutomaticEnabled",
  "competitionVenueAllocationManualEnabled",
  "competitionVenueAllocationHybridEnabled",
  "competitionVenueAllocationHoldsEnabled",
  "competitionVenueAllocationPublishEnabled",
  "demoWorldV35Enabled",
];
const prerequisiteFlagKeys = [
  "venueFoundationEnabled",
  "venueManagementEnabled",
  "venueAvailabilityEnabled",
  "venueReservationRequestsEnabled",
  "venueCounteroffersEnabled",
  "venueReservationHoldsEnabled",
  "venueCanonicalReservationsEnabled",
  "venueMatchBindingEnabled",
  "venueR4dIntegrationEnabled",
];

let completed = false;
let deviceA;
let deviceB;
let originalFlags;
let flagsChanged = false;
let preview;
let report;
try {
  const topology = JSON.parse(runSql(`
select json_build_object(
  'ledger',(select count(*) from supabase_migrations.schema_migrations),
  'clubs',(select count(*) from public.pachanga_clubs),
  'teams',(select count(*) from public.pachanga_groups),
  'players',(select count(*) from public.pachanga_player_profiles),
  'referees',(select count(*) from public.pachanga_referee_profiles),
  'venues',(select count(*) from public.pachanga_club_venues),
  'pitches',(select count(*) from public.pachanga_venue_pitches),
  'leagues',(select count(*) from public.pachanga_competitions where competition_type='LEAGUE'),
  'tournaments',(select count(*) from public.pachanga_competitions where competition_type='TOURNAMENT'),
  'matches',(select count(*) from public.pachanga_canonical_matches)
)::text;
`, "inspect Wave 9B staging topology"));
  assert.deepEqual(topology, {
    ledger: 228,
    clubs: 3,
    teams: 12,
    players: 120,
    referees: 6,
    venues: 6,
    pitches: 12,
    leagues: 1,
    tournaments: 1,
    matches: 50,
  });

  const accountA = await createAccount("device-a");
  const accountB = await createAccount("device-b");
  runSql(`
insert into public.pachanga_club_memberships(club_id,user_id,role,status,accepted_at,invited_by)
values
  (${sqlLiteral(clubId)}::uuid,${sqlLiteral(accountA.id)}::uuid,'club_venue_manager','active',clock_timestamp(),'e9010000-0000-4000-8000-000000000001'),
  (${sqlLiteral(clubId)}::uuid,${sqlLiteral(accountB.id)}::uuid,'club_venue_manager','active',clock_timestamp(),'e9010000-0000-4000-8000-000000000001');
insert into public.pachanga_competition_staff_assignments(
  competition_id,user_id,staff_role,status,assigned_by
) values
  (${sqlLiteral(competitionId)}::uuid,${sqlLiteral(accountA.id)}::uuid,'competition_venue_manager','active','c4010000-0000-4000-8000-000000000002'),
  (${sqlLiteral(competitionId)}::uuid,${sqlLiteral(accountB.id)}::uuid,'competition_venue_manager','active','c4010000-0000-4000-8000-000000000002');
insert into public.pachanga_group_members(group_id,user_id,role,display_name)
values(${sqlLiteral(teamId)}::uuid,${sqlLiteral(accountA.id)}::uuid,'owner','Wave 9B Device A');
insert into private.pachanga_platform_admin_roles(user_id,role,active,granted_by)
values(${sqlLiteral(accountA.id)}::uuid,'platform_admin',true,'e9010000-0000-4000-8000-000000000001');
update public.pachanga_referee_profiles
set user_id=${sqlLiteral(accountB.id)}::uuid, updated_at=clock_timestamp()
where id=${sqlLiteral(refereeProfileId)}::uuid;
`, "grant Wave 9B authenticated synthetic roles");

  deviceA = await signIn(accountA);
  deviceB = await signIn(accountB);
  originalFlags = await getFlags(deviceA.supabase);
  const activation = Object.fromEntries(
    [...prerequisiteFlagKeys, ...wave9bFlagKeys].map((key) => [key, true]),
  );
  const activated = await setFlags(deviceA.supabase, originalFlags.revision, activation);
  flagsChanged = true;
  const activeFlags = activated.snapshot;
  for (const key of wave9bFlagKeys) assert.equal(activeFlags[key], true, `${key} did not activate in staging`);
  assert.equal(activeFlags.jointScheduleVenueOptimizationEnabled, false);
  assert.equal(activeFlags.venuePaymentsEnabled, false);
  assert.equal(activeFlags.venueExternalIntegrationsEnabled, false);

  let official = await assignmentOk(deviceA.supabase, {
    action: "assignment.propose",
    aggregateId: assignmentId,
    expectedRevision: 0,
    payload: {
      assignmentRole: "MAIN_REFEREE",
      currency: "EUR",
      feeMode: "FIXED",
      proposedFeeCents: 0,
      refereeProfileId,
      requesterId: competitionId,
      requesterKind: "COMPETITION",
      responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
      sourceId: scheduleItemId,
      sourceKind: "competition_generated",
    },
  });
  official = await assignmentOk(deviceB.supabase, {
    action: "assignment.accept",
    aggregateId: assignmentId,
    expectedRevision: official.confirmedRevision,
  });
  official = await assignmentOk(deviceA.supabase, {
    action: "assignment.confirm",
    aggregateId: assignmentId,
    expectedRevision: official.confirmedRevision,
  });
  assert.equal(official.snapshot.assignment.scheduleState, "CURRENT");

  let series = await allocationOk(deviceA.supabase, {
    action: "recurring_series.create",
    expectedRevision: 0,
    payload: {
      bufferMinutes: 5,
      competitionId,
      durationMinutes: 70,
      endDate: "2027-06-28",
      frequency: "WEEKLY",
      localStartTime: "20:00",
      modality: "F7",
      pitchId: pitchAlphaId,
      purpose: "COMPETITION_RECURRING_BLOCK",
      startDate: "2027-05-17",
      timezone: "Europe/Madrid",
      weekday: 1,
    },
  });
  const seriesId = series.aggregateId;
  for (const action of ["recurring_series.validate", "recurring_series.offer"]) {
    series = await allocationOk(deviceA.supabase, {
      action, aggregateId: seriesId, expectedRevision: series.confirmedRevision,
    });
  }
  series = await allocationOk(deviceB.supabase, {
    action: "recurring_series.accept",
    aggregateId: seriesId,
    expectedRevision: series.confirmedRevision,
  });
  for (const action of ["recurring_series.publish", "recurring_series.materialize"]) {
    series = await allocationOk(deviceA.supabase, {
      action, aggregateId: seriesId, expectedRevision: series.confirmedRevision,
    });
  }
  const materializeReplayOperation = randomUUID();
  const materialized = await allocationOk(deviceA.supabase, {
    action: "recurring_series.materialize",
    aggregateId: seriesId,
    expectedRevision: series.confirmedRevision,
    operationId: materializeReplayOperation,
  });
  const materializedReplay = await allocationOk(deviceA.supabase, {
    action: "recurring_series.materialize",
    aggregateId: seriesId,
    expectedRevision: series.confirmedRevision,
    operationId: materializeReplayOperation,
  });
  assert.deepEqual(materializedReplay, materialized);
  series = materialized;

  let pool = await allocationOk(deviceA.supabase, {
    action: "venue_pool.create",
    expectedRevision: 0,
    payload: { competitionId, editionId, name: "Wave 9B Staging Pool", visibility: "competition_staff" },
  });
  const poolId = pool.aggregateId;
  pool = await allocationOk(deviceA.supabase, {
    action: "venue_pool.offer",
    aggregateId: poolId,
    expectedRevision: pool.confirmedRevision,
    payload: {
      allowedWeekdays: [1],
      capacityPerSlot: 1,
      localEndTime: "23:00",
      localStartTime: "17:00",
      modalities: ["F7"],
      ownerClubId: clubId,
      pitchIds: [pitchAlphaId, pitchBetaId],
      priority: 10,
      recurringSeriesId: seriesId,
      sourceKind: "RECURRING_SERIES",
      validFrom: "2027-01-01",
      validUntil: "2027-12-31",
      venueId,
      visibility: "competition_staff",
    },
  });
  const authorizationId = runSql(`
select id from public.pachanga_competition_venue_authorizations
where pool_id=${sqlLiteral(poolId)}::uuid and status='offered'
order by server_sequence desc,id desc limit 1;
`, "read offered synthetic Venue authorization");
  await allocationOk(deviceB.supabase, {
    action: "venue_pool.accept",
    aggregateId: authorizationId,
    expectedRevision: 1,
  });
  pool = await allocationOk(deviceA.supabase, {
    action: "venue_pool.activate",
    aggregateId: poolId,
    expectedRevision: pool.confirmedRevision,
  });

  let plan = await allocationOk(deviceA.supabase, {
    action: "allocation_plan.create",
    expectedRevision: 0,
    payload: {
      competitionId,
      editionId,
      mode: "HYBRID",
      ruleRevisionId,
      schedulePlanId,
      scheduleRevisionId,
      stageId,
      venuePoolId: poolId,
      venueRequired: true,
    },
  });
  const planId = plan.aggregateId;

  const queue = eventQueue();
  const binding = postgresChangesBinding(queue);
  const channel = deviceB.supabase.channel(`wave9b-${runId}`)
    .on("system", {}, (payload) => queue.binding?.(payload))
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_venue_invalidations",
    }, (event) => queue.push(event));
  channels.push({ channel, supabase: deviceB.supabase });
  await waitForSubscribed(channel);
  await binding;

  plan = await allocationOk(deviceA.supabase, {
    action: "allocation_inputs.freeze",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
  });
  const generatedEvent = queue.wait(
    (event) => event.new?.entity_id === planId && event.new?.entity_type === "venue_allocation_plan",
    "allocation.generate",
  );
  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.generate",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: { searchBudget: 100, seed: "wave9b-staging-deterministic" },
  });
  await generatedEvent;
  let planner = await desk(deviceB.supabase, planId);
  assert.equal(planner.plan.revision, plan.confirmedRevision);
  assert.equal(planner.items.length, 1);
  assert.equal(planner.items[0].canonicalMatchId, canonicalMatchId);
  assert.equal(planner.items[0].pitchId, pitchAlphaId);

  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.item.remove",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: { canonicalMatchId },
  });
  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.item.assign",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: { canonicalMatchId, pitchId: pitchBetaId },
  });
  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.item.move",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: { canonicalMatchId, pitchId: pitchAlphaId },
  });
  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.lock.create",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: {
      canonicalMatchId,
      lockType: "MATCH_TO_PITCH",
      pitchId: pitchAlphaId,
      reason: "Wave 9B authenticated hybrid lock",
    },
  });
  plan = await allocationOk(deviceB.supabase, {
    action: "allocation.regenerate",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    payload: { searchBudget: 100, seed: "wave9b-staging-hybrid" },
  });
  planner = await desk(deviceA.supabase, planId);
  assert.equal(planner.plan.mode, "HYBRID");
  assert.equal(planner.items[0].pitchId, pitchAlphaId);
  assert.equal(planner.locks.length, 1);

  const holdInputs = [deviceA.supabase, deviceB.supabase].map((supabase) => ({
    supabase,
    input: {
      action: "allocation.hold",
      aggregateId: planId,
      expectedRevision: plan.confirmedRevision,
      operationId: randomUUID(),
      payload: { expiresInMinutes: 60 },
    },
  }));
  const holdRace = await Promise.all(holdInputs.map(({ supabase, input }) => allocationCommand(supabase, input)));
  const holdWinners = holdRace.filter((result) => !result.error);
  const holdLosers = holdRace.filter((result) => result.error);
  assert.equal(holdWinners.length, 1);
  assert.equal(holdLosers.length, 1);
  assert.match(diagnostic(holdLosers[0]), /STALE_REVISION|40001|PT409/);
  const holdWinnerIndex = holdRace.findIndex((result) => !result.error);
  plan = holdWinners[0].data;
  const holdReplay = await allocationOk(holdInputs[holdWinnerIndex].supabase, holdInputs[holdWinnerIndex].input);
  assert.deepEqual(holdReplay, plan);
  assert.equal(Number(runSql(`
select count(*) from public.pachanga_competition_venue_allocation_holds
where allocation_plan_id=${sqlLiteral(planId)}::uuid and status='active';
`, "count active Wave 9B staging holds")), 1);

  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.validate",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
  });
  assert.equal(plan.snapshot.result.status, "VALID");
  const publishOperation = randomUUID();
  plan = await allocationOk(deviceA.supabase, {
    action: "allocation.publish",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision,
    operationId: publishOperation,
  });
  const publishReplay = await allocationOk(deviceA.supabase, {
    action: "allocation.publish",
    aggregateId: planId,
    expectedRevision: plan.confirmedRevision - 1,
    operationId: publishOperation,
  });
  assert.deepEqual(publishReplay, plan);
  planner = await desk(deviceB.supabase, planId);
  assert.equal(planner.plan.status, "published");
  assert.ok(planner.items[0].reservationId);
  assert.ok(planner.items[0].bindingId);
  assert.equal(planner.revision.hardViolationCount, 0);

  const directWrite = await deviceA.supabase.from("pachanga_competition_venue_allocation_plans")
    .update({ status: "cancelled" }).eq("id", planId);
  assert.ok(directWrite.error);

  const scheduleBefore = runSql(`
select scheduled_start::text || '|' || scheduled_end::text
from public.pachanga_competition_match_contexts where id=${sqlLiteral(matchContextId)}::uuid;
`, "read schedule before R4D replacement");
  let replacement = await reservationOk(deviceA.supabase, {
    action: "reservation.request.create",
    expectedRevision: 0,
    payload: {
      canonicalMatchId,
      competitionId,
      localEnd: "2027-05-17 21:10",
      localStart: "2027-05-17 20:00",
      modality: "F7",
      offsetMinutes: 120,
      pitchId: pitchBetaId,
      purpose: "COMPETITION_MATCH",
      requesterKind: "TEAM",
      requesterTeamId: teamId,
      ruleRevisionId,
      timezone: "Europe/Madrid",
      venueId,
    },
  });
  const replacementRequestId = replacement.aggregateId;
  replacement = await reservationOk(deviceA.supabase, {
    action: "reservation.request.submit",
    aggregateId: replacementRequestId,
    expectedRevision: replacement.confirmedRevision,
  });
  replacement = await reservationOk(deviceB.supabase, {
    action: "reservation.accept",
    aggregateId: replacementRequestId,
    expectedRevision: replacement.confirmedRevision,
    payload: { terms: { kind: "CONTACT_CLUB" } },
  });
  const replacementReservationId = replacement.aggregateId;
  replacement = await reservationOk(deviceA.supabase, {
    action: "reservation.confirm",
    aggregateId: replacementReservationId,
    expectedRevision: replacement.confirmedRevision,
  });
  const contextRevision = Number(runSql(`
select revision from public.pachanga_competition_match_contexts
where id=${sqlLiteral(matchContextId)}::uuid;
`, "read context revision before R4D replacement"));
  replacement = await reservationOk(deviceA.supabase, {
    action: "reservation.replace_venue",
    aggregateId: replacementReservationId,
    expectedRevision: replacement.confirmedRevision,
    payload: {
      competitionMatchContextId: matchContextId,
      expectedContextRevision: contextRevision,
      publicSummary: "Synthetic Wave 9B staging field replacement.",
      reasonCode: "PITCH_UNAVAILABLE",
    },
  });
  const scheduleAfter = runSql(`
select scheduled_start::text || '|' || scheduled_end::text
from public.pachanga_competition_match_contexts where id=${sqlLiteral(matchContextId)}::uuid;
`, "read schedule after R4D replacement");
  assert.equal(scheduleAfter, scheduleBefore);

  const assignmentRead = await deviceB.supabase.rpc("get_pachanga_referee_assignment_beta_v1", {
    target_assignment_id: assignmentId,
  });
  if (assignmentRead.error) throw assignmentRead.error;
  assert.equal(assignmentRead.data.assignment.scheduleState, "RECONFIRMATION_REQUIRED");
  official = await assignmentOk(deviceB.supabase, {
    action: "assignment.reconfirm",
    aggregateId: assignmentId,
    expectedRevision: assignmentRead.data.assignment.revision,
  });
  assert.equal(official.snapshot.assignment.scheduleState, "CURRENT");

  replacement = await reservationOk(deviceA.supabase, {
    action: "reservation.cancel",
    aggregateId: replacementReservationId,
    expectedRevision: replacement.confirmedRevision,
    payload: { reasonCode: "SYNTHETIC_STAGING_CANCELLATION" },
  });
  assert.equal(JSON.parse(runSql(`
select json_build_object(
  'matchStatus',(select status from public.pachanga_canonical_matches where id=${sqlLiteral(canonicalMatchId)}::uuid),
  'actionRequired',(select count(*) from public.pachanga_venue_match_bindings
    where reservation_id=${sqlLiteral(replacementReservationId)}::uuid
      and status='ACTION_REQUIRED' and action_required_code='VENUE_ACTION_REQUIRED'),
  'activeBindings',(select count(*) from public.pachanga_venue_match_bindings
    where canonical_match_id=${sqlLiteral(canonicalMatchId)}::uuid and status='ACTIVE')
)::text;
`, "verify cancellation/R4D binding outcome")), {
    matchStatus: "active",
    actionRequired: 1,
    activeBindings: 0,
  });

  await deviceB.supabase.removeChannel(channel);
  const reconnect = deviceB.supabase.channel(`wave9b-reconnect-${runId}`).on("postgres_changes", {
    event: "INSERT", schema: "public", table: "pachanga_venue_invalidations",
  }, () => {});
  channels.push({ channel: reconnect, supabase: deviceB.supabase });
  await waitForSubscribed(reconnect);
  const converged = await desk(deviceB.supabase, planId);
  assert.equal(converged.plan.revision, plan.confirmedRevision);
  assert.equal(converged.plan.status, "published");

  preview = await previewSmoke(deviceB.accessToken, planId, plan.confirmedRevision);
  const finalReadback = JSON.parse(runSql(`
select json_build_object(
  'doubleReservations',(select count(*) from (
    select pitch_id,starts_at,ends_at from public.pachanga_venue_reservations
    where status='CONFIRMED' group by pitch_id,starts_at,ends_at having count(*)>1
  ) rows),
  'doubleBindings',(select count(*) from (
    select canonical_match_id from public.pachanga_venue_match_bindings
    where status='ACTIVE' group by canonical_match_id having count(*)>1
  ) rows),
  'matchTimesChanged',(select count(*) from public.pachanga_competition_match_contexts
    where id=${sqlLiteral(matchContextId)}::uuid
      and (scheduled_start<>'2027-05-17T18:00:00Z'::timestamptz
        or scheduled_end<>'2027-05-17T19:10:00Z'::timestamptz)),
  'wave9bReceipts',(select count(*) from private.pachanga_venue_operation_receipts
    where client_metadata->>'sessionId'=${sqlLiteral(`wave9b-${runId}`)}),
  'realRecipients',(select count(*)
    from public.pachanga_user_notifications notifications
    join auth.users recipients on recipients.id=notifications.recipient_user_id
    where (notifications.kind like 'venue_%' or notifications.kind like 'competition_venue_%')
      and lower(coalesce(recipients.email,'')) not like '%.test')
)::text;
`, "Wave 9B staging final authority readback"));
  assert.equal(finalReadback.doubleReservations, 0);
  assert.equal(finalReadback.doubleBindings, 0);
  assert.equal(finalReadback.matchTimesChanged, 0);
  assert.equal(finalReadback.realRecipients, 0);

  report = {
    auth: "2 synthetic accounts / 2 authenticated devices",
    cleanup: "EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED",
    concurrency: "1 hold winner / 1 STALE_REVISION",
    finalReadback,
    flow: [
      "pool:create/offer/accept/activate",
      "series:create/validate/offer/accept/publish/materialize",
      "freeze/automatic/manual/lock/hybrid/hold/validate/publish",
      "reservation/R4D/referee-reconfirm/cancel",
    ],
    preview,
    projectRef: env.projectRef,
    realtime: "SUBSCRIBED / invalidation / canonical refetch / reconnect PASS",
    topology,
  };
  completed = true;
} finally {
  if (flagsChanged && originalFlags && deviceA?.supabase) {
    try {
      const current = await getFlags(deviceA.supabase);
      const restore = {};
      for (const key of [...prerequisiteFlagKeys, ...wave9bFlagKeys]) restore[key] = originalFlags[key];
      await setFlags(deviceA.supabase, current.revision, restore);
      flagsChanged = false;
    } catch {}
  }
  for (const { channel, supabase } of channels) {
    try { await supabase.removeChannel(channel); } catch {}
  }
  for (const { supabase } of [deviceA, deviceB].filter(Boolean)) {
    try { await supabase.auth.signOut({ scope: "local" }); } catch {}
  }
  if (accounts.length) {
    const ids = accounts.map((account) => sqlLiteral(account.id)).join(",");
    try {
      runSql(`
update public.pachanga_referee_profiles
set user_id=${sqlLiteral(originalRefereeUserId)}::uuid, updated_at=clock_timestamp()
where id=${sqlLiteral(refereeProfileId)}::uuid;
delete from private.pachanga_platform_admin_roles where user_id in (${ids});
delete from public.pachanga_competition_staff_assignments where user_id in (${ids});
delete from public.pachanga_club_memberships where user_id in (${ids});
delete from public.pachanga_group_members where user_id in (${ids});
`, "revoke Wave 9B authenticated synthetic roles");
    } catch {}
    for (const account of accounts) {
      try { await service.auth.admin.deleteUser(account.id); } catch {}
    }
  }
}

assert.equal(flagsChanged, false, "Wave 9B staging flags were not restored");
assert.equal(completed, true);
process.stdout.write(`${JSON.stringify({ status: "SEASON_VENUE_ALLOCATION_V1_STAGING_PASS", ...report })}\n`);
