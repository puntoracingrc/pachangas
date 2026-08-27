import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createClient } from "@supabase/supabase-js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const productionRef = "qonbngfrnrqgmxbdfbea";
const env = {
  confirmation: process.env.TOURNAMENT_GROUP_STAGING_CONFIRM,
  databaseUrl: process.env.TOURNAMENT_GROUP_STAGING_DATABASE_URL,
  projectRef: process.env.TOURNAMENT_GROUP_STAGING_PROJECT_REF,
  publishableKey: process.env.TOURNAMENT_GROUP_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.TOURNAMENT_GROUP_STAGING_SERVICE_ROLE_KEY,
  url: process.env.TOURNAMENT_GROUP_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (!value) throw new Error(`TOURNAMENT_GROUP_STAGING_${key.toUpperCase()}_REQUIRED`);
}

const apiRef = new URL(env.url).hostname.split(".")[0];
const databaseIdentity = decodeURIComponent(new URL(env.databaseUrl).username);
if (
  env.confirmation !== "TOURNAMENT_GROUP_STAGING_ONLY"
  || apiRef !== env.projectRef
  || apiRef === productionRef
  || databaseIdentity.includes(productionRef)
) throw new Error("TOURNAMENT_GROUP_STAGING_PRODUCTION_TARGET_FORBIDDEN");

const runId = randomUUID().slice(0, 8);
const resumeExistingFixture = process.env.TOURNAMENT_GROUP_STAGING_RESUME === "1";
const ownerId = "64010000-0000-4000-8000-000000000001";
const ownerEmail = "demo-tournament-team-1@example.test";
const ownerPassword = `R6b-${randomUUID()}-Qa!`;
const clients = [];
const channels = [];

function client(key = env.publishableKey) {
  const value = createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 40 } },
  });
  clients.push(value);
  return value;
}

const fixtureAdmin = client(env.serviceRoleKey);

function redact(value) {
  return String(value)
    .replaceAll(env.databaseUrl, "[DATABASE_URL_REDACTED]")
    .replaceAll(env.serviceRoleKey, "[SERVICE_ROLE_REDACTED]");
}

function psql(args, label, input) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", env.databaseUrl, ...args,
  ], {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${redact(`${result.stdout ?? ""}${result.stderr ?? ""}`)}`);
  }
  return (result.stdout ?? "").trim();
}

function queryJson(sql, label) {
  return JSON.parse(psql(["-At", "-c", sql], label));
}

function replaceExactlyOnce(source, from, to, label) {
  assert.equal(source.split(from).length - 1, 1, `R6B_STAGING_MARKER_DRIFT:${label}`);
  return source.replace(from, to);
}

function tournamentFixtureSql() {
  const source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-tournament-operations.sql"),
    "utf8",
  );
  return replaceExactlyOnce(
    source,
    "from generate_series(1, 16) team_number;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    "from generate_series(1, 16) team_number\non conflict (id) do nothing;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    "precreated-owner",
  );
}

function refereeFixtureSql() {
  const source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-referee-assignment-operations.sql"),
    "utf8",
  );
  const boundary = "do $demo_assignments$";
  const boundaryIndex = source.indexOf(boundary);
  assert.notEqual(boundaryIndex, -1, "R6B_STAGING_REFEREE_BOUNDARY_DRIFT");
  const refereeOnly = source
    .slice(0, boundaryIndex)
    .replaceAll("e4010000-0000-4000-8000-000000000001", "64010000-0000-4000-8000-000000000090");
  return `
\\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.demo_v2_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;
${refereeOnly}
commit;
`;
}

const prerequisiteFlagsSql = `
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
update private.pachanga_competition_foundation_settings settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = true,
  competition_discipline_foundation_enabled = true,
  competition_disciplinary_events_enabled = true,
  competition_disciplinary_counters_enabled = true,
  competition_sanctions_enabled = true,
  competition_sanction_service_enabled = true,
  competition_discipline_appeals_enabled = true,
  league_public_registration_enabled = false,
  league_public_calendar_enabled = false,
  league_public_standings_enabled = false,
  league_public_exception_status_enabled = false,
  league_private_beta_public_discovery_enabled = false,
  competition_public_discipline_enabled = false,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '64010000-0000-4000-8000-000000000090',
  updated_at = clock_timestamp()
where settings.singleton;
commit;
`;

function subscribeToTournamentInvalidations(supabase, competitionId, label, expectedEntityType) {
  let resolveEvent;
  let rejectEvent;
  const event = new Promise((resolvePromise, rejectPromise) => {
    resolveEvent = resolvePromise;
    rejectEvent = rejectPromise;
  });
  const timeout = setTimeout(() => rejectEvent(new Error(`R6B_STAGING_REALTIME_TIMEOUT:${label}`)), 45_000);
  const channel = supabase
    .channel(`r6b-${label}-${runId}`)
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
    table: "pachanga_tournament_invalidations",
    filter: `competition_id=eq.${competitionId}`,
  }, (payload) => {
      if (payload.new?.entity_type !== expectedEntityType) return;
      clearTimeout(timeout);
      resolveEvent(payload);
    });
  channels.push([supabase, channel]);
  const subscribed = new Promise((resolvePromise, rejectPromise) => {
    const subscriptionTimeout = setTimeout(
      () => rejectPromise(new Error(`R6B_STAGING_SUBSCRIPTION_TIMEOUT:${label}`)),
      45_000,
    );
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(subscriptionTimeout);
        resolvePromise(status);
      } else if (["CHANNEL_ERROR", "TIMED_OUT"].includes(status)) {
        clearTimeout(subscriptionTimeout);
        rejectPromise(new Error(`R6B_STAGING_SUBSCRIPTION_FAILED:${label}:${status}`));
      }
    });
  });
  return { event, subscribed };
}

function insertRealtimeReadinessProbe(competitionId) {
  assert.match(competitionId, /^[0-9a-f-]{36}$/i);
  return queryJson(`
    with inserted as (
      insert into public.pachanga_tournament_invalidations(
        server_sequence, competition_id, target_user_id,
        entity_type, entity_id, revision
      ) values (
        nextval('private.pachanga_competition_sequence'),
        '${competitionId}'::uuid,
        null,
        'realtime_probe',
        '${runId}',
        0
      )
      returning server_sequence, entity_type, entity_id
    )
    select to_jsonb(inserted)::text from inserted;
  `, "publish isolated Realtime readiness probe");
}

async function signInDevice(label) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({
    email: ownerEmail,
    password: ownerPassword,
  });
  if (result.error) throw new Error(`R6B_STAGING_SIGN_IN_FAILED:${label}`, { cause: result.error });
  assert.equal(result.data.user.id, ownerId);
  return supabase;
}

async function hub(supabase, competitionId) {
  const result = await supabase.rpc("get_pachanga_tournament_group_hub_v1", {
    competition_id: competitionId,
  });
  if (result.error) throw result.error;
  const snapshot = result.data;
  assert.equal(snapshot?.kind, "TournamentGroupStageHub");
  assert.equal(snapshot?.competition?.id, competitionId);
  assert.ok(Number.isSafeInteger(snapshot?.groupStage?.revision));
  return snapshot;
}

async function main() {
  const initial = queryJson(`
    select jsonb_build_object(
      'ledger', (select count(*) from supabase_migrations.schema_migrations),
      'lastMigration', (select max(version) from supabase_migrations.schema_migrations),
      'competitions', (select count(*) from public.pachanga_competitions)
    )::text;
  `, "inspect isolated staging baseline");
  assert.equal(initial.ledger, 169);
  assert.equal(initial.lastMigration, "20260827105036");
  if (!resumeExistingFixture) assert.equal(initial.competitions, 0);
  if (resumeExistingFixture) assert.equal(initial.competitions, 1);

  if (resumeExistingFixture) {
    const account = await fixtureAdmin.auth.admin.updateUserById(ownerId, {
      email_confirm: true,
      password: ownerPassword,
      user_metadata: { qaFixture: "TOURNAMENT_GROUP_STAGE_V1", runId },
    });
    if (account.error) throw account.error;
  } else {
    const account = await fixtureAdmin.auth.admin.createUser({
      id: ownerId,
      email: ownerEmail,
      email_confirm: true,
      password: ownerPassword,
      user_metadata: { qaFixture: "TOURNAMENT_GROUP_STAGE_V1", runId },
    });
    if (account.error) throw account.error;

    psql(["-v", "DEMO_WORLD_V2_PERSIST=1"], "create canonical R6A Tournament fixture", tournamentFixtureSql());
    psql([], "activate isolated R4A-R5 prerequisites", prerequisiteFlagsSql);
    psql([], "create canonical referee fixtures", refereeFixtureSql());
    psql([
      "-v", "DEMO_WORLD_V2_PERSIST=1",
      "-f", resolve(root, "scripts/demo-world/demo-world-v2-tournament-group-stage-operations.sql"),
    ], "operate R6B through R4B-R5 and Referee Assignments");
  }

  const proof = queryJson(`
    with target as (
      select competitions.id
      from public.pachanga_competitions competitions
      where competitions.slug='copa-barrios-iq-2027'
    ), contexts as (
      select match_contexts.*
      from target
      join public.pachanga_competition_match_contexts match_contexts
        on match_contexts.competition_id=target.id
    )
    select jsonb_build_object(
      'competitionId', (select id from target),
      'groups', (select count(*) from target
        join public.pachanga_competition_editions editions on editions.competition_id=target.id
        join public.pachanga_competition_stages stages on stages.edition_id=editions.id
        join public.pachanga_competition_groups groups on groups.stage_id=stages.id),
      'entries', (select count(*) from target join public.pachanga_competition_entries entries
        on entries.competition_id=target.id),
      'rounds', (select count(*) from target
        join public.pachanga_competition_rounds rounds on rounds.competition_id=target.id),
      'canonicalMatches', (select count(*) from contexts),
      'officialResults', (select count(*) from contexts where status='official'),
      'lockedSquads', (select count(*) from contexts
        join public.pachanga_competition_match_squads squads
          on squads.competition_match_context_id=contexts.id
        where squads.status='locked'),
      'attendanceClosedSides', (select coalesce(sum(
        (sheets.home_attendance_closed_at is not null)::integer
        + (sheets.away_attendance_closed_at is not null)::integer
      ), 0) from contexts
        join public.pachanga_competition_match_sheets sheets
          on sheets.competition_match_context_id=contexts.id),
      'postponements', (select count(*) from contexts
        join public.pachanga_competition_postponement_requests requests
          on requests.competition_match_context_id=contexts.id),
      'noShows', (select count(*) from contexts
        join public.pachanga_competition_no_show_incidents incidents
          on incidents.competition_match_context_id=contexts.id),
      'suspensions', (select count(*) from contexts
        join public.pachanga_competition_match_suspensions suspensions
          on suspensions.competition_match_context_id=contexts.id),
      'disciplinaryEvents', (select count(*) from target
        join public.pachanga_competition_disciplinary_events events on events.competition_id=target.id),
      'confirmedReferees', (select count(*) from contexts
        join public.pachanga_referee_assignments assignments on assignments.canonical_match_id=contexts.canonical_match_id
        where assignments.status='confirmed'),
      'standingSnapshots', (select count(*) from target
        join public.pachanga_competition_standing_states states on states.competition_id=target.id
        where states.current_snapshot_id is not null),
      'qualificationStatus', (select snapshots.status from target
        join public.pachanga_tournament_group_stage_states states on states.competition_id=target.id
        join public.pachanga_tournament_qualification_snapshots snapshots
          on snapshots.id=states.current_qualification_snapshot_id),
      'bracketStatus', (select templates.status from target
        join public.pachanga_tournament_group_stage_states states on states.competition_id=target.id
        join public.pachanga_tournament_bracket_templates templates
          on templates.id=states.current_bracket_template_id),
      'bracketSlots', (select count(*) from target
        join public.pachanga_tournament_group_stage_states states on states.competition_id=target.id
        join public.pachanga_tournament_bracket_slots slots
          on slots.bracket_template_id=states.current_bracket_template_id),
      'knockoutMatches', (select count(*) from contexts
        join public.pachanga_competition_stages stages on stages.id=contexts.stage_id
        where stages.stage_type='KNOCKOUT')
    )::text;
  `, "read canonical hosted R6B proof");

  assert.equal(proof.groups, 4);
  assert.equal(proof.entries, 16);
  assert.equal(proof.rounds, 12);
  assert.equal(proof.canonicalMatches, 24);
  assert.equal(proof.officialResults, 24);
  assert.equal(proof.lockedSquads, 30);
  assert.equal(proof.attendanceClosedSides, 30);
  assert.equal(proof.postponements, 1);
  assert.equal(proof.noShows, 1);
  assert.equal(proof.suspensions, 1);
  assert.equal(proof.disciplinaryEvents, 4);
  assert.equal(proof.confirmedReferees, 12);
  assert.equal(proof.standingSnapshots, 4);
  assert.equal(proof.qualificationStatus, "PUBLISHED");
  assert.equal(proof.bracketStatus, "PUBLISHED");
  assert.equal(proof.bracketSlots, 8);
  assert.equal(proof.knockoutMatches, 0);

  const deviceA = await signInDevice("device-a");
  const deviceB = await signInDevice("device-b");
  const beforeA = await hub(deviceA, proof.competitionId);
  const beforeB = await hub(deviceB, proof.competitionId);
  const expectedRevision = beforeA.groupStage.revision;
  assert.equal(expectedRevision, beforeB.groupStage.revision);

  const readinessA = subscribeToTournamentInvalidations(
    deviceA, proof.competitionId, "readiness-device-a", "realtime_probe",
  );
  const readinessB = subscribeToTournamentInvalidations(
    deviceB, proof.competitionId, "readiness-device-b", "realtime_probe",
  );
  await Promise.all([readinessA.subscribed, readinessB.subscribed]);
  const readiness = insertRealtimeReadinessProbe(proof.competitionId);
  const [readinessEventA, readinessEventB] = await Promise.all([readinessA.event, readinessB.event]);
  assert.equal(String(readinessEventA.new.server_sequence), String(readiness.server_sequence));
  assert.equal(String(readinessEventB.new.server_sequence), String(readiness.server_sequence));

  const realtimeA = subscribeToTournamentInvalidations(
    deviceA, proof.competitionId, "device-a", "tournament",
  );
  const realtimeB = subscribeToTournamentInvalidations(
    deviceB, proof.competitionId, "device-b", "tournament",
  );
  await Promise.all([realtimeA.subscribed, realtimeB.subscribed]);

  const operationA = randomUUID();
  const operationB = randomUUID();
  const commandArgs = (operationId) => ({
    aggregate_id: proof.competitionId,
    client_metadata: {
      clientVersion: "6.1.0+r6b-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "6.1.0+r6b-staging",
      sessionId: `r6b-${runId}`,
      surface: "tournament-group-stage-staging",
    },
    command_action: "group_stage.complete",
    command_payload: { reason: "R6B hosted two-device completion" },
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
  const [writeA, writeB] = await Promise.all([
    deviceA.rpc("command_pachanga_tournament_group_stage_v1", commandArgs(operationA)),
    deviceB.rpc("command_pachanga_tournament_group_stage_v1", commandArgs(operationB)),
  ]);
  const successes = [writeA, writeB].filter((result) => !result.error);
  const conflicts = [writeA, writeB].filter((result) => result.error);
  const conflictDiagnostics = conflicts.map((result) => ({
    code: result.error.code,
    message: result.error.message,
  }));
  assert.equal(successes.length, 1, JSON.stringify(conflictDiagnostics));
  assert.equal(conflicts.length, 1);
  assert.match(`${conflicts[0].error.code} ${conflicts[0].error.message}`, /PT409|STALE_REVISION/);

  const [eventA, eventB] = await Promise.all([realtimeA.event, realtimeB.event]);
  assert.equal(eventA.eventType, "INSERT");
  assert.equal(eventB.eventType, "INSERT");
  const afterA = await hub(deviceA, proof.competitionId);
  const afterB = await hub(deviceB, proof.competitionId);
  assert.equal(afterA.groupStage.revision, afterB.groupStage.revision);
  assert.equal(afterA.groupStage.revision, expectedRevision + 1);
  assert.equal(afterA.groupStage.status, "complete");
  assert.ok(afterA.groupStage.completedAt);

  const winningOperation = successes[0] === writeA ? operationA : operationB;
  const replayClient = successes[0] === writeA ? deviceA : deviceB;
  const replay = await replayClient.rpc(
    "command_pachanga_tournament_group_stage_v1",
    commandArgs(winningOperation),
  );
  if (replay.error) throw replay.error;
  assert.deepEqual(replay.data, successes[0].data);

  process.stdout.write(`${JSON.stringify({
    branch: env.projectRef,
    canonicalMatches: proof.canonicalMatches,
    devices: 2,
    groups: proof.groups,
    knockoutMatches: proof.knockoutMatches,
    realtime: "POSTGRES_CHANGES_RECEIVED_AND_REFETCHED",
    revisionConflict: "ONE_WINNER_ONE_STALE",
    stories: 17,
  })}\n`);
}

try {
  await main();
} finally {
  await Promise.all(channels.map(([supabase, channel]) => supabase.removeChannel(channel)));
  await Promise.all(clients.map((supabase) => supabase.auth.signOut({ scope: "local" })));
}
