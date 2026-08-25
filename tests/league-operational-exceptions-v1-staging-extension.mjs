import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const R4C_FLAGS_ID = "00000000-0000-0000-0000-00000000c4c1";
const R4D_FLAGS_ID = "00000000-0000-0000-0000-00000000c4d1";
const R4C_FLAG_KEYS = [
  "foundationEnabled", "squadsEnabled", "attendanceEnabled",
  "sportingResultsEnabled", "resultConfirmationEnabled",
  "officialResultsEnabled", "standingsEnabled", "publicStandingsEnabled",
];
const R4D_FLAG_KEYS = [
  "foundationEnabled", "postponementsEnabled", "reschedulingEnabled",
  "venueChangesEnabled", "lateArrivalEnabled", "noShowEnabled",
  "matchSuspensionsEnabled", "administrativeDecisionsEnabled",
  "publicExceptionStatusEnabled",
];
const PROTECTED_TABLES = [
  "pachanga_individual_rating_evidence",
  "pachanga_player_rating_snapshots",
  "pachanga_achievement_grants",
  "pachanga_reward_grants",
  "pachanga_conduct_reports",
  "pachanga_conduct_subject_state",
  "pachanga_competition_discipline_cases",
  "pachanga_stripe_webhook_events",
];

function operation(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return client.rpc("command_pachanga_league_operational_exceptions_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("league-operational-exceptions-staging"),
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function operationOk(client, metadata, input) {
  const result = await operation(client, metadata, input);
  if (result.error) {
    throw new Error(
      `${input.action}@${input.expectedRevision} [${result.error.code}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

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
          reject(new Error(`R4D Realtime timeout: ${label}`));
        }, 90_000);
        waiters.push({ predicate, resolve, reject, timer });
      });
    },
  };
}

export async function runLeagueOperationalExceptionsStagingExtension({
  anonymousFactory,
  channels,
  created,
  entries,
  expectError,
  fixtureAdmin,
  metadata,
  ownerADevice2,
  outsiderClient,
  platform,
  privateBeta = false,
  rpc,
  staffA,
  waitForSubscription,
}) {
  const initialR4c = await rpc(platform, "get_pachanga_league_match_operations_flags_v1");
  const initialR4d = await rpc(platform, "get_pachanga_league_operational_exceptions_flags_v1");
  const expectedR4c = Object.fromEntries(R4C_FLAG_KEYS.map((key) => [
    key,
    privateBeta ? key !== "publicStandingsEnabled" : false,
  ]));
  const expectedR4d = Object.fromEntries(R4D_FLAG_KEYS.map((key) => [
    key,
    privateBeta ? key !== "publicExceptionStatusEnabled" : false,
  ]));
  for (const key of R4C_FLAG_KEYS) assert.equal(initialR4c[key], expectedR4c[key], `R4C ${key} initial gate mismatch`);
  for (const key of R4D_FLAG_KEYS) assert.equal(initialR4d[key], expectedR4d[key], `R4D ${key} initial gate mismatch`);

  async function setFlags(rpcName, aggregateId, currentName, values, reason) {
    const current = await rpc(platform, currentName);
    const result = await platform.rpc(rpcName, {
      aggregate_id: aggregateId,
      client_metadata: metadata("league-operational-exceptions-flags-staging"),
      command_payload: { ...values, reason },
      expected_revision: current.revision,
      operation_id: randomUUID(),
    });
    if (result.error) throw result.error;
    return result.data;
  }
  const setR4c = (values, reason) => setFlags(
    "command_pachanga_league_match_operations_platform_v1",
    R4C_FLAGS_ID,
    "get_pachanga_league_match_operations_flags_v1",
    values,
    reason,
  );
  const setR4d = (values, reason) => setFlags(
    "command_pachanga_league_operational_exceptions_platform_v1",
    R4D_FLAGS_ID,
    "get_pachanga_league_operational_exceptions_flags_v1",
    values,
    reason,
  );

  async function countRows(table) {
    const result = await fixtureAdmin.from(table).select("*", { count: "exact", head: true });
    if (result.error) {
      if (/could not find|does not exist|relation/i.test(result.error.message ?? "")) return null;
      throw result.error;
    }
    return result.count ?? 0;
  }
  async function protectedCounts() {
    return Object.fromEntries(await Promise.all(PROTECTED_TABLES.map(async (table) => [table, await countRows(table)])));
  }
  async function matchSnapshot(client, fixture) {
    return rpc(client, "get_pachanga_league_operational_match_v1", {
      target_canonical_match_id: fixture.canonical_match_id,
      target_competition_id: created.competitionId,
    });
  }
  async function stageContext(fixture, status, start = null) {
    const selected = await fixtureAdmin.from("pachanga_competition_match_contexts")
      .select("id,revision").eq("id", fixture.id).single();
    if (selected.error) throw selected.error;
    const patch = { revision: selected.data.revision + 1, status };
    if (start) {
      patch.scheduled_start = start.toISOString();
      patch.scheduled_end = new Date(start.getTime() + 70 * 60_000).toISOString();
    }
    const updated = await fixtureAdmin.from("pachanga_competition_match_contexts")
      .update(patch).eq("id", fixture.id).eq("revision", selected.data.revision).select("id").single();
    if (updated.error) throw updated.error;
  }
  async function ensureMatchSheet(fixture, actorId) {
    const result = await fixtureAdmin.from("pachanga_competition_match_sheets").upsert({
      canonical_match_id: fixture.canonical_match_id,
      competition_match_context_id: fixture.id,
      created_by: actorId,
    }, { ignoreDuplicates: true, onConflict: "competition_match_context_id" });
    if (result.error) throw result.error;
  }
  async function currentSportingScore(fixture) {
    const result = await fixtureAdmin
      .from("pachanga_competition_sporting_results")
      .select("current_revision_id")
      .eq("competition_match_context_id", fixture.id)
      .single();
    if (result.error) throw result.error;
    const revision = await fixtureAdmin
      .from("pachanga_competition_sporting_result_revisions")
      .select("score_home,score_away")
      .eq("id", result.data.current_revision_id)
      .single();
    if (revision.error) throw revision.error;
    return {
      scoreAway: revision.data.score_away,
      scoreHome: revision.data.score_home,
    };
  }
  async function directUpdate(table, values, filters = []) {
    let query = fixtureAdmin.from(table).update(values).eq("competition_id", created.competitionId);
    for (const [kind, column, value] of filters) {
      query = kind === "in" ? query.in(column, value) : query.eq(column, value);
    }
    const result = await query;
    if (result.error) throw result.error;
  }

  let r4cEnabled = false;
  let r4dEnabled = false;
  const protectedBefore = await protectedCounts();
  const stories = [];
  try {
    if (!privateBeta) {
      await setR4c(Object.fromEntries(R4C_FLAG_KEYS.map((key) => [key, true])), "R4D staging dependency window");
      r4cEnabled = true;
      await setR4d(Object.fromEntries(R4D_FLAG_KEYS.map((key) => [key, true])), "R4D authenticated staging window");
      r4dEnabled = true;
    }

    const contexts = await fixtureAdmin.from("pachanga_competition_match_contexts")
      .select("id,canonical_match_id,round_id,schedule_item_id,home_entry_id,away_entry_id,status,revision,scheduled_start")
      .eq("competition_id", created.competitionId)
      .eq("source_kind", "COMPETITION_GENERATED")
      .order("scheduled_start", { ascending: true })
      .order("id", { ascending: true });
    if (contexts.error) throw contexts.error;
    assert.equal(contexts.data.length, 15);
    const entryById = new Map(entries.map((entry) => [entry.entryId, entry]));
    const teamZero = contexts.data.find((fixture) => [fixture.home_entry_id, fixture.away_entry_id].includes(entries[0].entryId));
    assert.ok(teamZero);
    const fixtures = [teamZero, ...contexts.data.filter(({ id }) => id !== teamZero.id)];
    const directorUser = await staffA.auth.getUser();
    if (directorUser.error || !directorUser.data.user) throw directorUser.error ?? new Error("R4D_STAGING_DIRECTOR_REQUIRED");

    const directWrite = await entries[0].teamClient.from("pachanga_competition_fixture_changes").insert({ id: randomUUID() });
    assert.ok(directWrite.error, "Authenticated R4D direct write must be rejected");
    let outsiderSnapshot = await matchSnapshot(staffA, fixtures[14]);
    const outsiderWrite = await operation(outsiderClient, metadata, {
      action: "fixture.reschedule",
      aggregateId: fixtures[14].id,
      expectedRevision: outsiderSnapshot.revision,
      payload: { reasonCode: "OUTSIDER", scheduledEnd: "2027-12-01T20:10:00Z", scheduledStart: "2027-12-01T19:00:00Z", timezone: "Europe/Madrid" },
    });
    expectError(outsiderWrite, /COMPETITION_OPERATIONS_MANAGER_REQUIRED|COMPETITION_OPERATION_NOT_ALLOWED/, "42501");

    const realtime = invalidationQueue();
    const channel = ownerADevice2.channel(`r4d-staging-${randomUUID()}`).on("postgres_changes", {
      event: "INSERT",
      filter: `competition_id=eq.${created.competitionId}`,
      schema: "public",
      table: "pachanga_competition_invalidations",
    }, ({ new: row }) => realtime.push(row));
    channels.push([ownerADevice2, channel]);
    await waitForSubscription(channel);

    const accepted = fixtures[0];
    await stageContext(accepted, "scheduled", new Date("2027-12-01T19:00:00Z"));
    const acceptedRequester = entryById.get(entries[0].entryId);
    const acceptedResponder = entryById.get(accepted.home_entry_id === acceptedRequester.entryId ? accepted.away_entry_id : accepted.home_entry_id);
    const originalItem = await fixtureAdmin.from("pachanga_competition_schedule_items")
      .select("scheduled_start,scheduled_end,venue_id,venue_label,revision").eq("id", accepted.schedule_item_id).single();
    if (originalItem.error) throw originalItem.error;
    let snapshot = await matchSnapshot(acceptedRequester.teamClient, accepted);
    const requestOperation = randomUUID();
    const requestInput = {
      action: "postponement.request",
      aggregateId: accepted.id,
      expectedRevision: snapshot.revision,
      operationId: requestOperation,
      payload: {
        proposedEnd: "2027-12-15T20:10:00Z",
        proposedStart: "2027-12-15T19:00:00Z",
        proposedTimezone: "Europe/Madrid",
        publicSummary: "Aplazamiento QA acordado.",
        reasonCode: "PITCH_UNAVAILABLE",
        requestingEntryId: acceptedRequester.entryId,
      },
    };
    const requestReceipt = await operationOk(acceptedRequester.teamClient, metadata, requestInput);
    assert.deepEqual(await operationOk(ownerADevice2, metadata, requestInput), requestReceipt);
    const requestEvent = await realtime.wait((event) => event.entity_type === "operational_request", "postponement request");
    assert.equal(requestEvent.competition_id, created.competitionId);
    const request = requestReceipt.snapshot.postponementRequests.find(({ status }) => status === "awaiting_response");
    let response = await operationOk(acceptedResponder.teamClient, metadata, {
      action: "postponement.respond", aggregateId: accepted.id,
      expectedRevision: requestReceipt.confirmedRevision,
      payload: { publicSummary: "Aceptado por el rival.", reasonCode: "TEAM_ACCEPT", requestId: request.id, responseKind: "ACCEPT" },
    });
    response = await operationOk(staffA, metadata, {
      action: "postponement.respond", aggregateId: accepted.id,
      expectedRevision: response.confirmedRevision,
      payload: { publicSummary: "Validado por competición.", reasonCode: "ORGANIZER_APPROVAL", requestId: request.id, responseKind: "APPROVE" },
    });
    assert.equal(response.snapshot.context.status, "scheduled");
    assert.equal(new Date(response.snapshot.context.scheduledStart).toISOString(), "2027-12-15T19:00:00.000Z");
    const originalAfter = await fixtureAdmin.from("pachanga_competition_schedule_items")
      .select("scheduled_start,scheduled_end,venue_id,venue_label,revision").eq("id", accepted.schedule_item_id).single();
    if (originalAfter.error) throw originalAfter.error;
    assert.deepEqual(originalAfter.data, originalItem.data);
    stories.push("postponement_approved");

    const rejected = fixtures[1];
    await stageContext(rejected, "scheduled");
    const rejectedHome = entryById.get(rejected.home_entry_id);
    const rejectedAway = entryById.get(rejected.away_entry_id);
    snapshot = await matchSnapshot(rejectedHome.teamClient, rejected);
    let receipt = await operationOk(rejectedHome.teamClient, metadata, {
      action: "postponement.request", aggregateId: rejected.id, expectedRevision: snapshot.revision,
      payload: { reasonCode: "TEAM_REQUEST", requestingEntryId: rejectedHome.entryId },
    });
    const rejectedRequest = receipt.snapshot.postponementRequests[0];
    receipt = await operationOk(rejectedAway.teamClient, metadata, {
      action: "postponement.respond", aggregateId: rejected.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "TEAM_REJECT", requestId: rejectedRequest.id, responseKind: "REJECT" },
    });
    assert.equal(receipt.snapshot.postponementRequests[0].status, "denied");
    stories.push("postponement_denied");

    const deadline = fixtures[2];
    await stageContext(deadline, "scheduled");
    const deadlineHome = entryById.get(deadline.home_entry_id);
    snapshot = await matchSnapshot(deadlineHome.teamClient, deadline);
    receipt = await operationOk(deadlineHome.teamClient, metadata, {
      action: "postponement.request", aggregateId: deadline.id, expectedRevision: snapshot.revision,
      payload: { reasonCode: "DEADLINE_REQUEST", requestingEntryId: deadlineHome.entryId },
    });
    const deadlineRequest = receipt.snapshot.postponementRequests[0];
    const deadlinePatch = await fixtureAdmin.from("pachanga_competition_postponement_requests")
      .update({ response_deadline: new Date(Date.now() - 60_000).toISOString() }).eq("id", deadlineRequest.id);
    if (deadlinePatch.error) throw deadlinePatch.error;
    receipt = await operationOk(fixtureAdmin, metadata, {
      action: "postponement.expire", aggregateId: deadline.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "DEADLINE_EXPIRED", requestId: deadlineRequest.id },
    });
    assert.equal(receipt.snapshot.postponementRequests[0].status, "expired");
    stories.push("deadline_expired");

    const venue = fixtures[3];
    await stageContext(venue, "scheduled");
    snapshot = await matchSnapshot(staffA, venue);
    receipt = await operationOk(staffA, metadata, {
      action: "fixture.change_venue", aggregateId: venue.id, expectedRevision: snapshot.revision,
      payload: { publicSummary: "Sede alternativa confirmada.", reasonCode: "PITCH_UNAVAILABLE", venueLabel: "R4D QA Venue", venueStatus: "LABEL" },
    });
    assert.equal(receipt.snapshot.context.venueLabel, "R4D QA Venue");
    const publicVenueResult = await anonymousFactory().rpc("get_pachanga_public_league_fixture_status_v1", {
      target_canonical_match_id: venue.canonical_match_id,
      target_competition_id: created.competitionId,
    });
    if (privateBeta) {
      expectError(publicVenueResult, /LEAGUE_PUBLIC_EXCEPTION_STATUS_DISABLED/, "42501");
    } else {
      if (publicVenueResult.error) throw publicVenueResult.error;
      assert.equal(publicVenueResult.data.effectiveSchedule.venueLabel, "R4D QA Venue");
      assert.doesNotMatch(
        JSON.stringify(publicVenueResult.data),
        /reasonText|evidence|reportedBy|decidedBy/i,
      );
    }
    stories.push("venue_change");

    const late = fixtures[4];
    await stageContext(late, "ready", new Date(Date.now() - 60_000));
    const lateHome = entryById.get(late.home_entry_id);
    const lateAway = entryById.get(late.away_entry_id);
    snapshot = await matchSnapshot(lateHome.teamClient, late);
    receipt = await operationOk(lateHome.teamClient, metadata, {
      action: "late_arrival.report", aggregateId: late.id, expectedRevision: snapshot.revision,
      payload: { reasonCode: "TEAM_LATE", responsibleEntryId: lateAway.entryId },
    });
    const lateIncident = receipt.snapshot.lateArrivalIncidents[0];
    receipt = await operationOk(lateAway.teamClient, metadata, {
      action: "late_arrival.confirm_arrival", aggregateId: late.id, expectedRevision: receipt.confirmedRevision,
      payload: { incidentId: lateIncident.id, reasonCode: "ARRIVAL_CONFIRMED" },
    });
    assert.equal(receipt.snapshot.lateArrivalIncidents[0].status, "arrived_within_policy");
    assert.equal(receipt.snapshot.noShowIncidents.length, 0);
    stories.push("late_arrival_within_policy");

    const noShow = fixtures[5];
    await stageContext(noShow, "ready", new Date(Date.now() - 20 * 60_000));
    await ensureMatchSheet(noShow, directorUser.data.user.id);
    const noShowHome = entryById.get(noShow.home_entry_id);
    const noShowAway = entryById.get(noShow.away_entry_id);
    snapshot = await matchSnapshot(noShowHome.teamClient, noShow);
    receipt = await operationOk(noShowHome.teamClient, metadata, {
      action: "no_show.report", aggregateId: noShow.id, expectedRevision: snapshot.revision,
      payload: { publicSummary: "Incomparecencia en revisión.", reasonCode: "GRACE_EXPIRED", reasonText: "No compareció tras el margen.", responsibleEntryId: noShowAway.entryId },
    });
    const noShowIncident = receipt.snapshot.noShowIncidents[0];
    receipt = await operationOk(staffA, metadata, {
      action: "no_show.confirm", aggregateId: noShow.id, expectedRevision: receipt.confirmedRevision,
      payload: { incidentId: noShowIncident.id, publicSummary: "Incomparecencia confirmada.", reasonCode: "NO_SHOW_CONFIRMED", reasonText: "Evidencia QA revisada." },
    });
    assert.equal(receipt.snapshot.context.status, "official");
    const noShowDecision = await fixtureAdmin.from("pachanga_competition_official_result_decisions")
      .select("effective_score_home,effective_score_away,outcome,operational_source_id").eq("id", receipt.snapshot.noShowIncidents[0].officialResultDecisionId).single();
    if (noShowDecision.error) throw noShowDecision.error;
    assert.deepEqual([noShowDecision.data.effective_score_home, noShowDecision.data.effective_score_away], [3, 0]);
    assert.equal(noShowDecision.data.outcome, "NO_SHOW");
    receipt = await operationOk(staffA, metadata, {
      action: "no_show.resolve", aggregateId: noShow.id, expectedRevision: receipt.confirmedRevision,
      payload: { incidentId: noShowIncident.id, reasonCode: "CASE_RESOLVED" },
    });
    stories.push("no_show_official_result");

    const rejectedNoShow = fixtures[6];
    await stageContext(rejectedNoShow, "ready", new Date(Date.now() - 20 * 60_000));
    await ensureMatchSheet(rejectedNoShow, directorUser.data.user.id);
    const rejectedNoShowHome = entryById.get(rejectedNoShow.home_entry_id);
    snapshot = await matchSnapshot(rejectedNoShowHome.teamClient, rejectedNoShow);
    receipt = await operationOk(rejectedNoShowHome.teamClient, metadata, {
      action: "no_show.report", aggregateId: rejectedNoShow.id, expectedRevision: snapshot.revision,
      payload: { reasonCode: "GRACE_EXPIRED", reasonText: "Evidencia insuficiente QA.", responsibleEntryId: rejectedNoShow.away_entry_id },
    });
    const rejectedNoShowIncident = receipt.snapshot.noShowIncidents[0];
    receipt = await operationOk(staffA, metadata, {
      action: "no_show.reject", aggregateId: rejectedNoShow.id, expectedRevision: receipt.confirmedRevision,
      payload: { incidentId: rejectedNoShowIncident.id, reasonCode: "EVIDENCE_INSUFFICIENT" },
    });
    assert.equal(receipt.snapshot.noShowIncidents[0].status, "rejected");
    stories.push("no_show_rejected");

    const resumed = fixtures[7];
    await stageContext(resumed, "in_progress");
    await ensureMatchSheet(resumed, directorUser.data.user.id);
    const resumedHome = entryById.get(resumed.home_entry_id);
    const resumedScore = await currentSportingScore(resumed);
    snapshot = await matchSnapshot(resumedHome.teamClient, resumed);
    receipt = await operationOk(resumedHome.teamClient, metadata, {
      action: "suspension.report", aggregateId: resumed.id, expectedRevision: snapshot.revision,
      payload: { partialScoreAway: resumedScore.scoreAway, partialScoreHome: resumedScore.scoreHome, publicSummary: "Suspendido en el minuto 37.", reasonCode: "SAFETY", reasonText: "Incidencia de seguridad QA.", reportedMinute: 37, reportingEntryId: resumedHome.entryId },
    });
    const resumedSuspension = receipt.snapshot.suspensions[0];
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.confirm", aggregateId: resumed.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "SUSPENSION_CONFIRMED", suspensionId: resumedSuspension.id },
    });
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.schedule_resume", aggregateId: resumed.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "RESUME_SCHEDULED", resumeMinute: 37, scheduledEnd: "2027-12-18T20:10:00Z", scheduledStart: "2027-12-18T19:00:00Z", suspensionId: resumedSuspension.id, timezone: "Europe/Madrid", venueStatus: "TBD" },
    });
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.resume", aggregateId: resumed.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "MATCH_RESUMED", suspensionId: resumedSuspension.id },
    });
    assert.equal(receipt.snapshot.context.canonicalMatchId, resumed.canonical_match_id);
    assert.equal(receipt.snapshot.suspensions[0].status, "resumed");
    assert.deepEqual(
      [receipt.snapshot.suspensions[0].sportingScoreHome, receipt.snapshot.suspensions[0].sportingScoreAway],
      [resumedScore.scoreHome, resumedScore.scoreAway],
    );
    stories.push("suspension_resumed_same_match");

    const replay = fixtures[8];
    await stageContext(replay, "in_progress");
    await ensureMatchSheet(replay, directorUser.data.user.id);
    const replayHome = entryById.get(replay.home_entry_id);
    const replayScore = await currentSportingScore(replay);
    snapshot = await matchSnapshot(replayHome.teamClient, replay);
    receipt = await operationOk(replayHome.teamClient, metadata, {
      action: "suspension.report", aggregateId: replay.id, expectedRevision: snapshot.revision,
      payload: { partialScoreAway: replayScore.scoreAway, partialScoreHome: replayScore.scoreHome, reasonCode: "SAFETY", reasonText: "Repetición QA.", reportedMinute: 24, reportingEntryId: replayHome.entryId },
    });
    const replaySuspension = receipt.snapshot.suspensions[0];
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.confirm", aggregateId: replay.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "SUSPENSION_CONFIRMED", suspensionId: replaySuspension.id },
    });
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.order_replay", aggregateId: replay.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "REPLAY_ORDERED", scheduledEnd: "2027-12-20T20:10:00Z", scheduledStart: "2027-12-20T19:00:00Z", suspensionId: replaySuspension.id, timezone: "Europe/Madrid", venueStatus: "TBD" },
    });
    assert.equal(receipt.snapshot.context.canonicalMatchId, replay.canonical_match_id);
    assert.equal(receipt.snapshot.suspensions[0].status, "replay_ordered");
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.cancel", aggregateId: replay.id, expectedRevision: receipt.confirmedRevision,
      payload: { cancellationOutcome: "NO_RESULT", reasonCode: "QA_REPLAY_ARCHIVE", suspensionId: replaySuspension.id },
    });
    stories.push("replay_same_match");

    const administrative = fixtures[9];
    await stageContext(administrative, "in_progress");
    await ensureMatchSheet(administrative, directorUser.data.user.id);
    const administrativeHome = entryById.get(administrative.home_entry_id);
    const administrativeScore = await currentSportingScore(administrative);
    snapshot = await matchSnapshot(administrativeHome.teamClient, administrative);
    receipt = await operationOk(administrativeHome.teamClient, metadata, {
      action: "suspension.report", aggregateId: administrative.id, expectedRevision: snapshot.revision,
      payload: { partialScoreAway: administrativeScore.scoreAway, partialScoreHome: administrativeScore.scoreHome, reasonCode: "SAFETY", reasonText: "Resolución administrativa QA.", reportedMinute: 37, reportingEntryId: administrativeHome.entryId },
    });
    const administrativeSuspension = receipt.snapshot.suspensions[0];
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.confirm", aggregateId: administrative.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "SUSPENSION_CONFIRMED", suspensionId: administrativeSuspension.id },
    });
    receipt = await operationOk(staffA, metadata, {
      action: "suspension.resolve", aggregateId: administrative.id, expectedRevision: receipt.confirmedRevision,
      payload: { reasonCode: "ADMIN_REVIEW", resolutionType: "PENDING_ADMINISTRATIVE_DECISION", suspensionId: administrativeSuspension.id },
    });
    const administrativeResultInput = {
      action: "administrative_decision.publish", aggregateId: administrative.id, expectedRevision: receipt.confirmedRevision,
      payload: { decisionType: "SET_OFFICIAL_RESULT", publicSummary: "Resultado parcial declarado oficial.", reasonCode: "PARTIAL_RESULT_CONFIRMED", suspensionId: administrativeSuspension.id },
    };
    if (privateBeta) {
      const conflict = await operation(staffA, metadata, administrativeResultInput);
      expectError(conflict, /R4D_SUSPENSION_RESULT_CONFLICT/, "PT409");
      stories.push("administrative_result_conflict_blocked");
    } else {
      receipt = await operationOk(staffA, metadata, administrativeResultInput);
      assert.equal(receipt.snapshot.context.status, "official");
      stories.push("administrative_partial_result");
    }

    const raceFixture = fixtures[10];
    await stageContext(raceFixture, "scheduled");
    snapshot = await matchSnapshot(staffA, raceFixture);
    const raceInput = {
      action: "fixture.reschedule", aggregateId: raceFixture.id, expectedRevision: snapshot.revision,
      payload: { reasonCode: "CONCURRENT_RESCHEDULE", scheduledEnd: "2027-12-22T20:10:00Z", scheduledStart: "2027-12-22T19:00:00Z", timezone: "Europe/Madrid" },
    };
    const race = await Promise.all([
      operation(staffA, metadata, { ...raceInput, operationId: randomUUID() }),
      operation(staffA, metadata, { ...raceInput, operationId: randomUUID() }),
    ]);
    const raceDiagnostic = race.map(({ error }) => error
      ? `${error.code ?? "UNKNOWN"}:${error.message ?? "unknown error"}`
      : "OK").join(" | ");
    assert.equal(race.filter(({ error }) => !error).length, 1, raceDiagnostic);
    assert.equal(race.filter(({ error }) => error).length, 1, raceDiagnostic);
    expectError(race.find(({ error }) => error), /STALE_REVISION/, "PT409");

    const canonicalIds = contexts.data.map(({ canonical_match_id: canonicalMatchId }) => canonicalMatchId);
    assert.equal(new Set(canonicalIds).size, 15, "Each fixture must retain one unique CanonicalMatch");
    const canonicalCount = await fixtureAdmin.from("pachanga_canonical_matches")
      .select("id", { count: "exact", head: true }).in("id", canonicalIds);
    if (canonicalCount.error) throw canonicalCount.error;
    assert.equal(canonicalCount.count, 15);
    const standings = await fixtureAdmin.from("pachanga_competition_standing_states")
      .select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId);
    if (standings.error) throw standings.error;
    assert.ok((standings.count ?? 0) >= 1);
    assert.deepEqual(await protectedCounts(), protectedBefore, "R4D modified a protected adjacent domain");

    await directUpdate("pachanga_competition_fixture_changes", { status: "superseded" }, [["eq", "status", "active"]]);
    await directUpdate("pachanga_competition_venue_change_requests", { status: "superseded" }, [["in", "status", ["requested", "approved"]]]);
    const suspensionIds = await fixtureAdmin.from("pachanga_competition_match_suspensions")
      .select("id").eq("competition_id", created.competitionId);
    if (suspensionIds.error) throw suspensionIds.error;
    if (suspensionIds.data.length > 0) {
      const resumptionCleanup = await fixtureAdmin.from("pachanga_competition_match_resumption_decisions")
        .update({ status: "superseded" })
        .in("match_suspension_id", suspensionIds.data.map(({ id }) => id))
        .eq("status", "published");
      if (resumptionCleanup.error) throw resumptionCleanup.error;
    }
    await directUpdate("pachanga_competition_administrative_decisions", { status: "superseded" }, [["eq", "status", "published"]]);

    const activeChecks = await Promise.all([
      fixtureAdmin.from("pachanga_competition_fixture_changes").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).eq("status", "active"),
      fixtureAdmin.from("pachanga_competition_postponement_requests").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).in("status", ["requested", "awaiting_response"]),
      fixtureAdmin.from("pachanga_competition_late_arrival_incidents").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).eq("status", "reported"),
      fixtureAdmin.from("pachanga_competition_no_show_incidents").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).in("status", ["reported", "under_review", "confirmed"]),
      fixtureAdmin.from("pachanga_competition_match_suspensions").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).in("status", ["reported", "confirmed", "resume_scheduled", "replay_ordered"]),
      fixtureAdmin.from("pachanga_competition_administrative_decisions").select("id", { count: "exact", head: true }).eq("competition_id", created.competitionId).eq("status", "published"),
    ]);
    for (const result of activeChecks) {
      if (result.error) throw result.error;
      assert.equal(result.count, 0);
    }

    return {
      canonicalMatches: canonicalCount.count,
      concurrency: "one_winner_one_stale",
      flagsRestored: true,
      protectedDomains: "unchanged",
      realtime: "invalidation_then_canonical_refetch",
      stagingActiveRows: 0,
      status: "PASS",
      stories,
    };
  } finally {
    if (r4dEnabled) {
      await setR4d(Object.fromEntries(R4D_FLAG_KEYS.map((key) => [key, initialR4d[key]])), "R4D staging restore")
        .catch((error) => console.error("[cleanup:r4d-flags]", error instanceof Error ? error.message : error));
      r4dEnabled = false;
    }
    if (r4cEnabled) {
      await setR4c(Object.fromEntries(R4C_FLAG_KEYS.map((key) => [key, initialR4c[key]])), "R4D staging dependency restore")
        .catch((error) => console.error("[cleanup:r4c-flags]", error instanceof Error ? error.message : error));
      r4cEnabled = false;
    }
  }
}
