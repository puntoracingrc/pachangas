import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const FLAG_AGGREGATE_ID = "00000000-0000-0000-0000-00000000c4c1";
const FLAG_KEYS = [
  "foundationEnabled",
  "squadsEnabled",
  "attendanceEnabled",
  "sportingResultsEnabled",
  "resultConfirmationEnabled",
  "officialResultsEnabled",
  "standingsEnabled",
  "publicStandingsEnabled",
];

function operation(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return client.rpc("command_pachanga_league_match_operations_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("league-match-operations-staging"),
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

function scorer(rosterMemberId, goals) {
  return goals > 0 ? [{ goals, rosterMemberId }] : [];
}

function scoreForFixture(fixture, entryOrder) {
  const home = entryOrder.get(fixture.home_entry_id);
  const away = entryOrder.get(fixture.away_entry_id);
  const homeTop = home < 3;
  const awayTop = away < 3;
  if (homeTop && awayTop) return { scoreAway: 1, scoreHome: 1 };
  if (homeTop !== awayTop) {
    return homeTop ? { scoreAway: 0, scoreHome: 2 } : { scoreAway: 2, scoreHome: 0 };
  }
  return home < away ? { scoreAway: 0, scoreHome: 1 } : { scoreAway: 1, scoreHome: 0 };
}

function createInvalidationQueue() {
  const events = [];
  const waiters = [];
  return {
    push(event) {
      const waiterIndex = waiters.findIndex(({ predicate }) => predicate(event));
      if (waiterIndex >= 0) {
        const [{ resolve, timer }] = waiters.splice(waiterIndex, 1);
        clearTimeout(timer);
        resolve(event);
        return;
      }
      events.push(event);
    },
    wait(predicate, label) {
      const eventIndex = events.findIndex(predicate);
      if (eventIndex >= 0) return Promise.resolve(events.splice(eventIndex, 1)[0]);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const index = waiters.findIndex((waiter) => waiter.timer === timer);
          if (index >= 0) waiters.splice(index, 1);
          reject(new Error(`R4C Realtime timeout: ${label}`));
        }, 90_000);
        waiters.push({ predicate, reject, resolve, timer });
      });
    },
  };
}

export async function runLeagueMatchOperationsStagingExtension({
  anonymousFactory,
  channels,
  competitionGroup,
  created,
  division,
  entries,
  expectError,
  fixtureAdmin,
  metadata,
  ownerADevice2,
  outsiderClient,
  platform,
  privateBeta = false,
  rpc,
  stage,
  staffA,
  waitForSubscription,
}) {
  const initialFlags = await rpc(platform, "get_pachanga_league_match_operations_flags_v1");
  for (const key of FLAG_KEYS) assert.equal(initialFlags[key], false, `${key} must begin OFF`);

  async function setFlags(values, reason) {
    const current = await rpc(platform, "get_pachanga_league_match_operations_flags_v1");
    const result = await platform.rpc("command_pachanga_league_match_operations_platform_v1", {
      aggregate_id: FLAG_AGGREGATE_ID,
      client_metadata: metadata("league-match-operations-flags-staging"),
      command_payload: { ...values, reason },
      expected_revision: current.revision,
      operation_id: randomUUID(),
    });
    if (result.error) throw result.error;
    return result.data;
  }

  const allEnabled = Object.fromEntries(FLAG_KEYS.map((key) => [
    key,
    privateBeta && key === "publicStandingsEnabled" ? false : true,
  ]));
  let flagsEnabled = false;
  try {
    const enabled = await setFlags(allEnabled, "R4C authenticated staging window");
    flagsEnabled = true;
    for (const key of FLAG_KEYS) assert.equal(enabled.snapshot[key], allEnabled[key]);

    const contextsResult = await fixtureAdmin
      .from("pachanga_competition_match_contexts")
      .select("id,canonical_match_id,round_id,home_entry_id,away_entry_id,status,revision,scheduled_start")
      .eq("competition_id", created.competitionId)
      .eq("source_kind", "COMPETITION_GENERATED")
      .order("scheduled_start", { ascending: true })
      .order("id", { ascending: true });
    if (contextsResult.error) throw contextsResult.error;
    assert.equal(contextsResult.data.length, 15);

    const entryById = new Map(entries.map((entry) => [entry.entryId, entry]));
    const entryOrder = new Map(entries.map((entry, index) => [entry.entryId, index]));
    const teamZeroFixture = contextsResult.data.find((fixture) => (
      fixture.home_entry_id === entries[0].entryId || fixture.away_entry_id === entries[0].entryId
    ));
    assert.ok(teamZeroFixture);
    const fixtures = [
      teamZeroFixture,
      ...contextsResult.data.filter(({ id }) => id !== teamZeroFixture.id),
    ];
    const changeFixture = fixtures.slice(1).find((fixture) => (
      scoreForFixture(fixture, entryOrder).scoreAway > 0
    ));
    assert.ok(changeFixture, "R4C staging requires an away-side change proposal fixture");
    const changeFixtureId = changeFixture.id;
    const remainingSpecialFixtures = fixtures.filter((fixture) => (
      fixture.id !== teamZeroFixture.id && fixture.id !== changeFixtureId
    ));
    const disputeFixtureId = remainingSpecialFixtures[0].id;
    const correctionFixtureId = remainingSpecialFixtures[1].id;

    async function matchSnapshot(client, fixture) {
      return rpc(client, "get_pachanga_league_canonical_match_v1", {
        target_canonical_match_id: fixture.canonical_match_id,
        target_competition_id: created.competitionId,
      });
    }

    const missingContext = await operation(entries[0].teamClient, metadata, {
      action: "squad.create",
      aggregateId: randomUUID(),
      expectedRevision: 1,
      payload: { entryId: entries[0].entryId },
    });
    expectError(missingContext, /COMPETITION_MATCH_CONTEXT_NOT_FOUND/);

    const directWrite = await entries[0].teamClient
      .from("pachanga_competition_match_squads")
      .insert({ id: randomUUID() });
    assert.ok(directWrite.error, "Authenticated clients must not directly insert R4C rows");

    async function preparePlayedMatch(fixture, firstFixture) {
      const home = entryById.get(fixture.home_entry_id);
      const away = entryById.get(fixture.away_entry_id);
      assert.ok(home && away);
      let snapshot = await matchSnapshot(staffA, fixture);
      assert.equal(snapshot.context.status, "scheduled");
      const homeRosterMemberId = snapshot.eligibleRoster.home[0]?.rosterMemberId;
      const awayRosterMemberId = snapshot.eligibleRoster.away[0]?.rosterMemberId;
      assert.ok(homeRosterMemberId && awayRosterMemberId);

      if (firstFixture) {
        const beforePlayed = await operation(home.teamClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: snapshot.revision,
          payload: { entryId: home.entryId, scoreAway: 0, scoreHome: 1 },
        });
        expectError(beforePlayed, /R4C_RESULT_REQUIRES_PLAYED_MATCH/);
        const unsupportedReferee = await operation(staffA, metadata, {
          action: "referee.assign",
          aggregateId: fixture.id,
          expectedRevision: snapshot.revision,
        });
        expectError(unsupportedReferee, /FEATURE_NOT_AVAILABLE/);
      }

      let revision = snapshot.revision;
      const homeCreateOperation = randomUUID();
      let receipt = await operationOk(home.teamClient, metadata, {
        action: "squad.create",
        aggregateId: fixture.id,
        expectedRevision: revision,
        operationId: homeCreateOperation,
        payload: { entryId: home.entryId, reason: "R4C staging home squad" },
      });
      if (firstFixture && home.entryId === entries[0].entryId) {
        const replay = await operationOk(ownerADevice2, metadata, {
          action: "squad.create",
          aggregateId: fixture.id,
          expectedRevision: revision,
          operationId: homeCreateOperation,
          payload: { entryId: home.entryId, reason: "R4C staging home squad" },
        });
        assert.deepEqual(replay, receipt);
      }
      revision = receipt.confirmedRevision;
      const homeSquadId = receipt.snapshot.squads.find(({ side }) => side === "HOME")?.id;
      assert.ok(homeSquadId);

      if (firstFixture) {
        const duplicate = await operation(home.teamClient, metadata, {
          action: "squad.create",
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: { entryId: home.entryId },
        });
        expectError(duplicate, /R4C_SQUAD_ALREADY_EXISTS/);
        const outsideRoster = await operation(home.teamClient, metadata, {
          action: "squad.member.add",
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: {
            memberRole: "STARTER",
            rosterMemberId: awayRosterMemberId,
            squadId: homeSquadId,
          },
        });
        expectError(outsideRoster, /R4C_ROSTER_MEMBER_NOT_ELIGIBLE/);
      }

      receipt = await operationOk(home.teamClient, metadata, {
        action: "squad.member.add",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          isCaptain: true,
          memberRole: "STARTER",
          positionOrder: 1,
          reason: "R4C staging home starter",
          rosterMemberId: homeRosterMemberId,
          shirtNumber: 9,
          squadId: homeSquadId,
        },
      });
      revision = receipt.confirmedRevision;
      if (privateBeta) {
        for (let memberIndex = 1; memberIndex < snapshot.eligibleRoster.home.length; memberIndex += 1) {
          receipt = await operationOk(home.teamClient, metadata, {
            action: "squad.member.add",
            aggregateId: fixture.id,
            expectedRevision: revision,
            payload: {
              memberRole: "STARTER",
              positionOrder: memberIndex + 1,
              reason: "League Private Beta home starter",
              rosterMemberId: snapshot.eligibleRoster.home[memberIndex].rosterMemberId,
              shirtNumber: memberIndex + 10,
              squadId: homeSquadId,
            },
          });
          revision = receipt.confirmedRevision;
        }
      }
      receipt = await operationOk(home.teamClient, metadata, {
        action: "squad.submit",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging home submit", squadId: homeSquadId },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(staffA, metadata, {
        action: "squad.validate",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging home validate", squadId: homeSquadId },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(staffA, metadata, {
        action: "squad.lock",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging home lock", squadId: homeSquadId },
      });
      revision = receipt.confirmedRevision;

      receipt = await operationOk(away.teamClient, metadata, {
        action: "squad.create",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { entryId: away.entryId, reason: "R4C staging away squad" },
      });
      revision = receipt.confirmedRevision;
      const awaySquadId = receipt.snapshot.squads.find(({ side }) => side === "AWAY")?.id;
      assert.ok(awaySquadId);
      if (firstFixture) {
        const bothTeams = await operation(away.teamClient, metadata, {
          action: "squad.member.add",
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: {
            memberRole: "STARTER",
            rosterMemberId: homeRosterMemberId,
            squadId: awaySquadId,
          },
        });
        expectError(bothTeams, /R4C_(ROSTER_MEMBER_NOT_ELIGIBLE|PLAYER_ON_BOTH_TEAMS)/);
      }
      receipt = await operationOk(away.teamClient, metadata, {
        action: "squad.member.add",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          isCaptain: true,
          memberRole: "STARTER",
          positionOrder: 1,
          reason: "R4C staging away starter",
          rosterMemberId: awayRosterMemberId,
          shirtNumber: 10,
          squadId: awaySquadId,
        },
      });
      revision = receipt.confirmedRevision;
      if (privateBeta) {
        for (let memberIndex = 1; memberIndex < snapshot.eligibleRoster.away.length; memberIndex += 1) {
          receipt = await operationOk(away.teamClient, metadata, {
            action: "squad.member.add",
            aggregateId: fixture.id,
            expectedRevision: revision,
            payload: {
              memberRole: "STARTER",
              positionOrder: memberIndex + 1,
              reason: "League Private Beta away starter",
              rosterMemberId: snapshot.eligibleRoster.away[memberIndex].rosterMemberId,
              shirtNumber: memberIndex + 20,
              squadId: awaySquadId,
            },
          });
          revision = receipt.confirmedRevision;
        }
      }
      receipt = await operationOk(away.teamClient, metadata, {
        action: "squad.submit",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging away submit", squadId: awaySquadId },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(staffA, metadata, {
        action: "squad.validate",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging away validate", squadId: awaySquadId },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(staffA, metadata, {
        action: "squad.lock",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { reason: "R4C staging away lock", squadId: awaySquadId },
      });
      revision = receipt.confirmedRevision;

      receipt = await operationOk(home.teamClient, metadata, {
        action: "attendance.set",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          entryId: home.entryId,
          reason: "R4C staging home attends",
          rosterMemberId: homeRosterMemberId,
          status: "going",
        },
      });
      revision = receipt.confirmedRevision;
      if (firstFixture) {
        receipt = await operationOk(away.teamClient, metadata, {
          action: "attendance.set",
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: {
            entryId: away.entryId,
            reason: "R4C staging away unavailable",
            rosterMemberId: awayRosterMemberId,
            status: "not_going",
          },
        });
        revision = receipt.confirmedRevision;
      }
      receipt = await operationOk(away.teamClient, metadata, {
        action: "attendance.set",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          entryId: away.entryId,
          reason: "R4C staging away attends",
          rosterMemberId: awayRosterMemberId,
          status: "going",
        },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(home.teamClient, metadata, {
        action: "attendance.close",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { entryId: home.entryId, reason: "R4C staging close home attendance" },
      });
      revision = receipt.confirmedRevision;
      receipt = await operationOk(away.teamClient, metadata, {
        action: "attendance.close",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: { entryId: away.entryId, reason: "R4C staging close away attendance" },
      });
      revision = receipt.confirmedRevision;
      for (const action of ["match.mark_ready", "match.start", "match.mark_played"]) {
        receipt = await operationOk(staffA, metadata, {
          action,
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: { reason: `R4C staging ${action}` },
        });
        revision = receipt.confirmedRevision;
      }
      assert.equal(receipt.snapshot.context.status, "played");
      return {
        away,
        awayRosterMemberId,
        fixture,
        home,
        homeRosterMemberId,
        revision,
      };
    }

    async function acceptResult(prepared, scores, options = {}) {
      const { away, awayRosterMemberId, fixture, home, homeRosterMemberId } = prepared;
      let revision = prepared.revision;
      let receipt = await operationOk(home.teamClient, metadata, {
        action: "sporting_result.submit",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          entryId: home.entryId,
          reason: "R4C staging result submit",
          ...scores,
          scorers: scorer(homeRosterMemberId, scores.scoreHome),
        },
      });
      revision = receipt.confirmedRevision;
      if (options.checkRivalScorer) {
        const rivalScorer = await operation(away.teamClient, metadata, {
          action: "sporting_result.accept",
          aggregateId: fixture.id,
          expectedRevision: revision,
          payload: {
            entryId: away.entryId,
            scorers: scorer(homeRosterMemberId, Math.max(1, scores.scoreAway)),
          },
        });
        expectError(rivalScorer, /R4C_SCORER_NOT_IN_LOCKED_SQUAD/);
      }
      receipt = await operationOk(away.teamClient, metadata, {
        action: "sporting_result.accept",
        aggregateId: fixture.id,
        expectedRevision: revision,
        payload: {
          entryId: away.entryId,
          reason: "R4C staging result accept",
          scorers: scorer(awayRosterMemberId, scores.scoreAway),
        },
      });
      assert.equal(receipt.snapshot.context.status, "official");
      assert.equal(receipt.snapshot.officialResult.scoreHome, scores.scoreHome);
      assert.equal(receipt.snapshot.officialResult.scoreAway, scores.scoreAway);
      return receipt;
    }

    const invalidations = createInvalidationQueue();
    let realtimeChannel;
    let realtimeReceipt;
    let standingsInvalidation;
    const storyReceipts = [];

    for (let index = 0; index < fixtures.length; index += 1) {
      const fixture = fixtures[index];
      const prepared = await preparePlayedMatch(fixture, index === 0);
      const scores = scoreForFixture(fixture, entryOrder);

      if (fixture.id === teamZeroFixture.id) {
        const teamZeroIsHome = fixture.home_entry_id === entries[0].entryId;
        const actor = entries[0].teamClient;
        const actorEntryId = entries[0].entryId;
        const actorRosterMemberId = teamZeroIsHome
          ? prepared.homeRosterMemberId
          : prepared.awayRosterMemberId;
        const actorGoals = teamZeroIsHome ? scores.scoreHome : scores.scoreAway;
        const opponent = teamZeroIsHome ? prepared.away : prepared.home;
        const opponentRosterMemberId = teamZeroIsHome
          ? prepared.awayRosterMemberId
          : prepared.homeRosterMemberId;
        const opponentGoals = teamZeroIsHome ? scores.scoreAway : scores.scoreHome;

        realtimeChannel = ownerADevice2.channel(`r4c-staging-${randomUUID()}`).on(
          "postgres_changes",
          {
            event: "INSERT",
            filter: `competition_id=eq.${created.competitionId}`,
            schema: "public",
            table: "pachanga_competition_invalidations",
          },
          (payload) => invalidations.push(payload.new),
        );
        channels.push([ownerADevice2, realtimeChannel]);
        await waitForSubscription(realtimeChannel);

        const operationIds = [randomUUID(), randomUUID()];
        const input = {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: actorEntryId,
            reason: "R4C staging concurrent result",
            ...scores,
            scorers: scorer(actorRosterMemberId, actorGoals),
          },
        };
        const race = await Promise.all([
          operation(actor, metadata, { ...input, operationId: operationIds[0] }),
          operation(ownerADevice2, metadata, { ...input, operationId: operationIds[1] }),
        ]);
        assert.equal(race.filter(({ error }) => !error).length, 1);
        assert.equal(race.filter(({ error }) => error).length, 1);
        expectError(race.find(({ error }) => error), /STALE_REVISION/);
        const winnerIndex = race.findIndex(({ error }) => !error);
        const winner = race[winnerIndex].data;
        const replay = await operationOk(ownerADevice2, metadata, {
          ...input,
          operationId: operationIds[winnerIndex],
        });
        assert.deepEqual(replay, winner);
        const matchEvent = invalidations.wait(
          (event) => event.entity_type === "match" && event.entity_id === fixture.id,
          "match invalidation",
        );
        assert.equal((await matchEvent).competition_id, created.competitionId);
        const refetched = await matchSnapshot(ownerADevice2, fixture);
        assert.equal(refetched.sportingResult.state, "submitted");

        const standingsBefore = await rpc(staffA, "get_pachanga_league_standings_v1", {
          target_competition_id: created.competitionId,
          target_division_id: division.id,
          target_group_id: competitionGroup.id,
          target_stage_id: stage.id,
        });
        assert.equal(standingsBefore.snapshot, null, "Unconfirmed results must not enter standings");
        const accepted = await operationOk(opponent.teamClient, metadata, {
          action: "sporting_result.accept",
          aggregateId: fixture.id,
          expectedRevision: winner.confirmedRevision,
          payload: {
            entryId: opponent.entryId,
            reason: "R4C staging concurrent result accepted",
            scorers: scorer(opponentRosterMemberId, opponentGoals),
          },
        });
        realtimeReceipt = accepted.operationId;
        standingsInvalidation = await invalidations.wait(
          (event) => event.entity_type === "standings" && event.entity_id === stage.id,
          "standings invalidation",
        );
        assert.equal(standingsInvalidation.competition_id, created.competitionId);
        const converged = await matchSnapshot(ownerADevice2, fixture);
        assert.equal(converged.context.status, "official");
        assert.deepEqual(
          [converged.officialResult.scoreHome, converged.officialResult.scoreAway],
          [scores.scoreHome, scores.scoreAway],
        );
        storyReceipts.push({ kind: "confirmed_realtime_concurrent", id: accepted.operationId });
        continue;
      }

      if (fixture.id === changeFixtureId) {
        assert.ok(scores.scoreAway > 0);
        const initial = { scoreAway: scores.scoreAway - 1, scoreHome: scores.scoreHome };
        let receipt = await operationOk(prepared.home.teamClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: prepared.home.entryId,
            reason: "R4C staging initial score",
            ...initial,
            scorers: scorer(prepared.homeRosterMemberId, initial.scoreHome),
          },
        });
        receipt = await operationOk(prepared.away.teamClient, metadata, {
          action: "sporting_result.propose_change",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            entryId: prepared.away.entryId,
            reason: "R4C staging corrected proposal",
            ...scores,
            scorers: scorer(prepared.awayRosterMemberId, scores.scoreAway),
          },
        });
        receipt = await operationOk(prepared.home.teamClient, metadata, {
          action: "sporting_result.accept",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            entryId: prepared.home.entryId,
            reason: "R4C staging proposal accepted",
            scorers: scorer(prepared.homeRosterMemberId, scores.scoreHome),
          },
        });
        const resultHistory = await fixtureAdmin
          .from("pachanga_competition_sporting_result_revisions")
          .select("id,version,previous_revision_id,revision_kind")
          .eq("sporting_result_id", receipt.snapshot.sportingResult.id)
          .order("version", { ascending: true })
          .order("server_sequence", { ascending: true });
        if (resultHistory.error) throw resultHistory.error;
        assert.deepEqual(
          resultHistory.data.map(({ revision_kind: kind, version }) => ({ kind, version })),
          [
            { kind: "INITIAL", version: 1 },
            { kind: "CHANGE", version: 2 },
            { kind: "ACCEPTANCE", version: 3 },
          ],
        );
        assert.equal(resultHistory.data[0].previous_revision_id, null);
        assert.equal(resultHistory.data[1].previous_revision_id, resultHistory.data[0].id);
        assert.equal(resultHistory.data[2].previous_revision_id, resultHistory.data[1].id);
        assert.equal(receipt.snapshot.sportingResult.currentRevisionId, resultHistory.data[2].id);
        assert.equal(receipt.snapshot.context.status, "official");
        storyReceipts.push({ kind: "change_proposal", id: receipt.operationId });
        continue;
      }

      if (fixture.id === disputeFixtureId) {
        let receipt = await operationOk(prepared.home.teamClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: prepared.home.entryId,
            reason: "R4C staging disputed score",
            ...scores,
            scorers: scorer(prepared.homeRosterMemberId, scores.scoreHome),
          },
        });
        receipt = await operationOk(prepared.away.teamClient, metadata, {
          action: "sporting_result.dispute",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            entryId: prepared.away.entryId,
            reason: "R4C staging private dispute",
            scoreAway: scores.scoreAway + 1,
            scoreHome: scores.scoreHome,
          },
        });
        assert.equal(receipt.snapshot.sportingResult.state, "disputed");
        const unauthorized = await operation(outsiderClient, metadata, {
          action: "official_result.publish",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            outcome: "CORRECTED_EFFECTIVE_SCORE",
            publicExplanation: "Unauthorized attempt",
            reasonCode: "r4c.unauthorized",
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
          },
        });
        expectError(unauthorized, /COMPETITION_RESULT_MANAGER_REQUIRED/);
        const adjusted = await operation(staffA, metadata, {
          action: "official_result.publish",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            outcome: "CORRECTED_EFFECTIVE_SCORE",
            pointsAdjustments: [{ entryId: prepared.home.entryId, points: 1 }],
            publicExplanation: "Unsupported points adjustment",
            reasonCode: "r4c.points_adjustment",
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
          },
        });
        expectError(adjusted, /FEATURE_NOT_AVAILABLE/);
        receipt = await operationOk(staffA, metadata, {
          action: "official_result.publish",
          aggregateId: fixture.id,
          expectedRevision: receipt.confirmedRevision,
          payload: {
            outcome: "CORRECTED_EFFECTIVE_SCORE",
            pointsAdjustments: [],
            privateEvidence: {
              evidenceReference: "r4c-staging://private/dispute",
              privateReason: "Private staging evidence",
            },
            publicExplanation: "Resolved by the competition director.",
            reasonCode: "result.dispute_resolved",
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
          },
        });
        const playerView = await matchSnapshot(prepared.home.teamClient, fixture);
        assert.doesNotMatch(JSON.stringify(playerView), /r4c-staging:\/\/private|Private staging evidence/);
        storyReceipts.push({ kind: "dispute", id: receipt.operationId });
        continue;
      }

      if (fixture.id === correctionFixtureId) {
        const initial = { scoreAway: scores.scoreAway, scoreHome: scores.scoreHome + 1 };
        const initialReceipt = await acceptResult(prepared, initial);
        const initialDecisionId = initialReceipt.snapshot.officialResult.id;
        const corrected = await operationOk(staffA, metadata, {
          action: "official_result.supersede",
          aggregateId: fixture.id,
          expectedRevision: initialReceipt.confirmedRevision,
          payload: {
            outcome: "CORRECTED_EFFECTIVE_SCORE",
            pointsAdjustments: [],
            privateEvidence: {
              evidenceReference: "r4c-staging://private/correction",
              privateReason: "Correction checked by the result manager",
            },
            publicExplanation: "Official score corrected.",
            reasonCode: "result.official_correction",
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
          },
        });
        assert.notEqual(corrected.snapshot.officialResult.id, initialDecisionId);
        const lineage = await fixtureAdmin
          .from("pachanga_competition_official_result_decisions")
          .select("id,supersedes_decision_id,effective_score_home,effective_score_away")
          .eq("id", corrected.snapshot.officialResult.id)
          .single();
        if (lineage.error) throw lineage.error;
        assert.equal(lineage.data.supersedes_decision_id, initialDecisionId);
        assert.deepEqual(
          [lineage.data.effective_score_home, lineage.data.effective_score_away],
          [scores.scoreHome, scores.scoreAway],
        );
        storyReceipts.push({ kind: "official_correction", id: corrected.operationId });
        continue;
      }

      if (index === 4) {
        const negativeScore = await operation(prepared.home.teamClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: prepared.home.entryId,
            scoreAway: 0,
            scoreHome: -1,
          },
        });
        expectError(negativeScore, /R4C_SCORE_INVALID/);
        const shootout = await operation(prepared.home.teamClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: prepared.home.entryId,
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
            shootoutHome: 5,
          },
        });
        expectError(shootout, /FEATURE_NOT_AVAILABLE/);
        const outsider = await operation(outsiderClient, metadata, {
          action: "sporting_result.submit",
          aggregateId: fixture.id,
          expectedRevision: prepared.revision,
          payload: {
            entryId: prepared.home.entryId,
            scoreAway: scores.scoreAway,
            scoreHome: scores.scoreHome,
          },
        });
        expectError(outsider, /R4C_TEAM_MATCH_MANAGER_REQUIRED/);
      }
      const receipt = await acceptResult(prepared, scores, { checkRivalScorer: index === 4 });
      storyReceipts.push({ kind: "confirmed", id: receipt.operationId });
    }

    const resultDesk = await rpc(staffA, "get_pachanga_league_result_desk_v1", {
      page_offset: 0,
      page_size: 50,
      target_competition_id: created.competitionId,
      target_state: null,
    });
    assert.equal(resultDesk.matches.length, 15);
    assert.equal(resultDesk.matches.every(({ officialDecisionId }) => Boolean(officialDecisionId)), true);

    let standings = await rpc(staffA, "get_pachanga_league_standings_v1", {
      target_competition_id: created.competitionId,
      target_division_id: division.id,
      target_group_id: competitionGroup.id,
      target_stage_id: stage.id,
    });
    assert.equal(standings.health, "CURRENT");
    assert.equal(standings.snapshot.computedResults, 15);
    assert.equal(standings.snapshot.rows.length, 6);
    const topRows = standings.snapshot.rows.filter(({ entryId }) => entryOrder.get(entryId) < 3);
    assert.equal(topRows.length, 3);
    assert.deepEqual(new Set(topRows.map(({ effectivePoints }) => Number(effectivePoints))), new Set([11]));
    assert.deepEqual(new Set(topRows.map(({ goalDifference }) => goalDifference)), new Set([6]));
    assert.ok(standings.snapshot.explanations.some(({ candidateEntryIds, criterion }) => (
      candidateEntryIds.length >= 3 && criterion.startsWith("HEAD_TO_HEAD_")
    )), "Three-team mini-table explanation was not persisted");
    assert.deepEqual(standings.snapshot.criteria, [
      "POINTS",
      "GOAL_DIFFERENCE",
      "GOALS_FOR",
      "WINS",
      "HEAD_TO_HEAD_POINTS",
      "HEAD_TO_HEAD_GOAL_DIFFERENCE",
      "HEAD_TO_HEAD_GOALS_FOR",
    ]);

    const anonymous = anonymousFactory();
    const publicStandingsResult = await anonymous.rpc("get_pachanga_public_league_standings_v1", {
      target_competition_id: created.competitionId,
      target_division_id: division.id,
      target_group_id: competitionGroup.id,
      target_stage_id: stage.id,
    });
    if (privateBeta) {
      expectError(publicStandingsResult, /LEAGUE_PUBLIC_STANDINGS_DISABLED/, "42501");
    } else {
      if (publicStandingsResult.error) throw publicStandingsResult.error;
      assert.equal(publicStandingsResult.data.snapshot.rows.length, 6);
    }

    const firstRoundResult = await fixtureAdmin
      .from("pachanga_competition_rounds")
      .select("id,status,revision")
      .eq("id", fixtures[0].round_id)
      .single();
    if (firstRoundResult.error) throw firstRoundResult.error;
    assert.equal(firstRoundResult.data.status, "in_progress");
    const roundCompleted = await operationOk(staffA, metadata, {
      action: "round.complete",
      aggregateId: firstRoundResult.data.id,
      expectedRevision: firstRoundResult.data.revision,
      payload: { reason: "R4C staging round complete" },
    });
    assert.equal(roundCompleted.snapshot.status, "completed");
    const roundLocked = await operationOk(staffA, metadata, {
      action: "round.lock",
      aggregateId: firstRoundResult.data.id,
      expectedRevision: roundCompleted.confirmedRevision,
      payload: { reason: "R4C staging round lock" },
    });
    assert.equal(roundLocked.snapshot.status, "locked");

    const rebuildContext = fixtures[0];
    const incremental = await operationOk(staffA, metadata, {
      action: "standings.rebuild",
      aggregateId: rebuildContext.id,
      expectedRevision: standings.revision,
      payload: { reason: "R4C staging incremental audit", rebuildKind: "INCREMENTAL" },
    });
    standings = await rpc(staffA, "get_pachanga_league_standings_v1", {
      target_competition_id: created.competitionId,
      target_division_id: division.id,
      target_group_id: competitionGroup.id,
      target_stage_id: stage.id,
    });
    assert.equal(standings.revision, incremental.confirmedRevision);
    const incrementalChecksum = standings.snapshot.checksum;
    const incrementalRows = standings.snapshot.rows;
    const full = await operationOk(staffA, metadata, {
      action: "standings.rebuild",
      aggregateId: rebuildContext.id,
      expectedRevision: standings.revision,
      payload: { reason: "R4C staging full audit", rebuildKind: "FULL_AUDIT" },
    });
    const fullStandings = await rpc(staffA, "get_pachanga_league_standings_v1", {
      target_competition_id: created.competitionId,
      target_division_id: division.id,
      target_group_id: competitionGroup.id,
      target_stage_id: stage.id,
    });
    assert.equal(fullStandings.revision, full.confirmedRevision);
    assert.equal(fullStandings.snapshot.checksum, incrementalChecksum);
    assert.deepEqual(fullStandings.snapshot.rows, incrementalRows);

    const finalFlags = await setFlags(
      Object.fromEntries(FLAG_KEYS.map((key) => [key, initialFlags[key]])),
      "R4C staging restore",
    );
    flagsEnabled = false;
    for (const key of FLAG_KEYS) assert.equal(finalFlags.snapshot[key], initialFlags[key]);

    return {
      canonicalMatches: fixtures.length,
      concurrency: "one_result_winner_one_stale",
      contexts: fixtures.length,
      fullChecksum: fullStandings.snapshot.checksum,
      idempotentReplay: true,
      miniTableCandidates: 3,
      officialResults: resultDesk.matches.length,
      officializedFixtures: storyReceipts.length,
      realtime: realtimeReceipt && standingsInvalidation ? "canonical_refetch_converged" : "missing",
      rounds: new Set(fixtures.map(({ round_id }) => round_id)).size,
      standingsRows: fullStandings.snapshot.rows.length,
      status: "PASS",
      stories: 11,
    };
  } finally {
    if (flagsEnabled) {
      await setFlags(
        Object.fromEntries(FLAG_KEYS.map((key) => [key, initialFlags[key]])),
        "R4C staging failure restore",
      ).catch((error) => {
        console.error("[cleanup:r4c-flags]", error instanceof Error ? error.message : error);
      });
    }
  }
}
