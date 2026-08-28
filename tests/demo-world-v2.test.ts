import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { runInNewContext } from "node:vm";
import { buildServiceWorkerSource } from "../app/service-worker-source";
import {
  DEMO_WORLD_V2_SEED,
  assertDemoWorldV2Snapshot,
  computeDemoWorldV2Standings,
  demoWorldV2IntegrityErrors,
  type DemoWorldV2Snapshot,
} from "../app/demo-world/demo-world-v2-contract";
import {
  demoWorldV2TabFromSearch,
  loadDemoWorldV2Core,
  loadDemoWorldV2Snapshot,
} from "../app/demo-world/demo-world-v2-client-state";
import {
  assertDemoWorldV2AuthorityProof,
  loadDemoWorldV2AuthorityProof,
} from "../scripts/demo-world/demo-world-v2-authority";
import { generateDemoWorldV2 } from "../scripts/demo-world/generate-demo-world-v2";

const root = process.cwd();
const publicRoot = path.join(root, "public/demo-world/v2");
const historicalV21Root = path.join(root, "public/demo-world/v2-1");
const historicalV22Root = path.join(root, "public/demo-world/v2-2");
const historicalV23Root = path.join(root, "public/demo-world/v2-3");
const historicalV24Root = path.join(root, "public/demo-world/v2-4");
const historicalV25Root = path.join(root, "public/demo-world/v2-5");
const historicalV26Root = path.join(root, "public/demo-world/v2-6");

async function jsonFile<T>(name: string): Promise<T> {
  return JSON.parse(await readFile(path.join(publicRoot, name), "utf8")) as T;
}

async function committedSnapshot(): Promise<DemoWorldV2Snapshot> {
  const [activity, clubsReferees, competitions, configuration, core, manifest, matches, players, publicCompetitions, tournament] = await Promise.all([
    jsonFile<DemoWorldV2Snapshot["activity"]>("activity.json"),
    jsonFile<DemoWorldV2Snapshot["clubsReferees"]>("clubs-referees.json"),
    jsonFile<DemoWorldV2Snapshot["competitions"]>("competitions.json"),
    jsonFile<DemoWorldV2Snapshot["configuration"]>("configuration.json"),
    jsonFile<DemoWorldV2Snapshot["core"]>("core.json"),
    jsonFile<DemoWorldV2Snapshot["manifest"]>("manifest.json"),
    jsonFile<DemoWorldV2Snapshot["matches"]>("matches.json"),
    jsonFile<DemoWorldV2Snapshot["players"]>("players.json"),
    jsonFile<DemoWorldV2Snapshot["publicCompetitions"]>("public-competitions.json"),
    jsonFile<DemoWorldV2Snapshot["tournament"]>("tournament.json"),
  ]);
  return { activity, clubsReferees, competitions, configuration, core, manifest, matches, players, publicCompetitions, tournament };
}

test("Demo World V2 is deterministic and the committed snapshot matches its hash", async () => {
  const committed = await committedSnapshot();
  const generated = generateDemoWorldV2();
  assert.deepEqual(committed, generated);
  const payload = {
    activity: committed.activity,
    clubsReferees: committed.clubsReferees,
    competitions: committed.competitions,
    configuration: committed.configuration,
    core: committed.core,
    matches: committed.matches,
    players: committed.players,
    publicCompetitions: committed.publicCompetitions,
    tournament: committed.tournament,
  };
  assert.equal(createHash("sha256").update(JSON.stringify(payload)).digest("hex"), committed.manifest.hash);
  assert.equal(committed.manifest.hash, "e4830ff25db5318a169e0e8da5cf7ffb8824beee8616cc6e88e8cf6a05a2b7dd");
  assert.equal(committed.manifest.version, 2.7);
  assert.equal(committed.manifest.seed, DEMO_WORLD_V2_SEED);
  assert.deepEqual(demoWorldV2IntegrityErrors(committed), []);
});

test("the committed authority proof comes from deterministic PostgreSQL operations", async () => {
  const proof = assertDemoWorldV2AuthorityProof(loadDemoWorldV2AuthorityProof());
  const world = await committedSnapshot();
  assert.equal(proof.authorityHash, "eedee3d55d597dfc0c9037192c22c79457d4fdf5ebd22ccb41b7667d0a797c03");
  assert.equal(proof.authorityHash, world.competitions.provenance.authorityHash);
  assert.equal(proof.database, "temporary-local-postgresql");
  assert.equal(proof.migrationCount, 183);
  assert.equal(proof.remoteWrites, 0);
  assert.deepEqual(proof.rpcFamilies, ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5", "R6A", "R6B", "R6C", "PUBLIC_COMPETITIONS"]);
  assert.deepEqual(proof.refereeAssignments.unconvergedRefereeNumbers, []);
  assert.deepEqual(proof.operationReceipts, {
    discipline: 33,
    matchOperations: 266,
    operationalExceptions: 13,
    refereeAssignments: 61,
    refereeOfficiating: 18,
    refereePlatform: 80,
    scheduling: 5,
  });
  assert.equal(proof.configuration.operationReceipts, 8);
  assert.equal(proof.publicCompetitions.operationReceipts, 40);
  assert.deepEqual(proof.publicCompetitions.privacy, {
    containsContactData: false,
    containsOwnerIdentity: false,
    containsPrivateReason: false,
    containsRequestMessage: false,
  });
  assert.equal(proof.configuration.revisions.length, 2);
  assert.equal(proof.configuration.revisions[0]?.source, "LEAGUE_WIZARD_V2");
  assert.equal(proof.configuration.revisions[1]?.source, "COMPETITION_CONFIGURATION_CENTER_V1");
  assert.deepEqual(proof.configuration.comparator.changedSections, ["discipline", "incidents", "match", "referees", "scoring"]);
  assert.deepEqual(proof.configuration.r5CatalogCodes, ["YELLOW", "RED", "BLUE"]);
  assert.doesNotMatch(JSON.stringify(proof.configuration), /fixedCents/);
  assert.equal(proof.matches.length, world.competitions.matches.length);
  assert.deepEqual(
    proof.standings.map(({ entryNumber, ...row }) => ({ ...row, entryId: `demo_league_entry_${String(entryNumber).padStart(3, "0")}` })),
    world.competitions.standingSnapshot.rows.map((row) => ({
      draws: row.draws,
      effectivePoints: row.effectivePoints,
      entryId: row.entryId,
      goalDifference: row.goalDifference,
      goalsAgainst: row.goalsAgainst,
      goalsFor: row.goalsFor,
      losses: row.losses,
      played: row.played,
      position: row.position,
      wins: row.wins,
    })),
  );
});

test("the protagonist League has the complete canonical R1-R5 graph including R3 assignments", async () => {
  const world = assertDemoWorldV2Snapshot(await committedSnapshot());
  const league = world.competitions;
  assert.equal(league.competition.name, "LIGA BARRIOS IQ 2026/27");
  assert.equal(league.entries.length, 6);
  assert.equal(league.delegates.length, 6);
  assert.equal(league.rosters.length, 6);
  assert.equal(league.rounds.length, 5);
  assert.equal(league.matches.length, 15);
  assert.equal(new Set(league.matches.map(({ canonicalMatchId }) => canonicalMatchId)).size, 15);
  assert.deepEqual(league.rounds.map(({ matchIds }) => matchIds.length), [3, 3, 3, 3, 3]);
  const originalRoundWindows = league.rounds.map((round) => {
    const starts = league.matches
      .filter(({ roundNumber }) => roundNumber === round.number)
      .map(({ originalScheduledStart }) => Date.parse(originalScheduledStart));
    return { maximum: Math.max(...starts), minimum: Math.min(...starts) };
  });
  assert.ok(originalRoundWindows.every((window, index) => (
    index === 0 || originalRoundWindows[index - 1]!.maximum < window.minimum
  )));
  assert.deepEqual(league.provenance.rpcFamilies, ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5"]);
  assert.equal(league.provenance.verified, true);
  assert.equal(league.provenance.migrations, 183);
  assert.equal(league.competition.refereeAssignmentsEnabled, true);
});

test("R5 discipline is canonical, sparse, calendar-aware and public-safe", async () => {
  const world = await committedSnapshot();
  const proof = loadDemoWorldV2AuthorityProof();
  const discipline = world.competitions.disciplinePreview;
  const events = discipline.events as Array<Record<string, unknown>>;
  const sanctions = discipline.sanctions as Array<Record<string, unknown>>;
  const serviceEvents = discipline.serviceEvents as Array<Record<string, unknown>>;
  const cardCounts = events.reduce<Record<string, number>>((counts, event) => {
    const code = String(event.cardTypeCode);
    counts[code] = (counts[code] ?? 0) + 1;
    return counts;
  }, {});
  assert.deepEqual(cardCounts, { BLUE: 2, RED: 2, YELLOW: 16 });
  assert.equal(sanctions.length, 4);
  assert.equal(serviceEvents.length, 2);
  assert.deepEqual(discipline.appeals, []);
  assert.equal(events.filter((event) => Number(event.revisionVersion) > 1).length, 1);
  assert.ok(sanctions.some((sanction) => sanction.status === "served" && sanction.totalUnits === 1 && sanction.remainingUnits === 0));
  assert.ok(sanctions.some((sanction) => sanction.status === "active" && sanction.publicSummary === "Sanción confirmada"));
  assert.deepEqual(
    (discipline.eligibilityTimeline as Array<Record<string, unknown>>).map(({ primaryAvailable, selectedSlot }) => ({ primaryAvailable, selectedSlot })),
    [
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: false, selectedSlot: "alternate" },
      { primaryAvailable: true, selectedSlot: "primary" },
    ],
  );
  assert.deepEqual(proof.discipline.appeals.map(({ status }) => status), ["modified", "upheld"]);
  assert.ok(Object.values(world.competitions.matchDisciplinePreviews).every((preview) => (
    Array.isArray(preview.events) && Array.isArray(preview.sanctions)
      && Array.isArray(preview.appeals) && preview.appeals.length === 0
  )));
  assert.doesNotMatch(JSON.stringify(discipline), /privateReason|evidenceRefs|appellant|decisionFactors|operationId/i);
});

test("the independent standings oracle reconstructs the official snapshot", async () => {
  const world = await committedSnapshot();
  const teamById = new Map(world.core.teams.map((team) => [team.id, team.name]));
  const oracle = computeDemoWorldV2Standings(
    world.competitions.entries,
    world.competitions.matches,
    (teamId) => teamById.get(teamId) ?? teamId,
  );
  assert.deepEqual(oracle, world.competitions.standingSnapshot.rows);
  assert.equal(oracle.reduce((sum, row) => sum + row.played, 0), 30);
  assert.equal(oracle.reduce((sum, row) => sum + row.goalsFor, 0), oracle.reduce((sum, row) => sum + row.goalsAgainst, 0));
  assert.equal(world.competitions.standingSnapshot.computedResults, 15);
  assert.equal(world.competitions.standingsPreview.snapshot?.checksum, world.competitions.standingSnapshot.checksum);
});

test("R4D stories are sparse, canonical and preserve lineage", async () => {
  const matches = (await committedSnapshot()).competitions.matches;
  const counts = matches.reduce<Record<string, number>>((result, match) => {
    result[match.exceptionType] = (result[match.exceptionType] ?? 0) + 1;
    return result;
  }, {});
  assert.deepEqual(counts, { none: 11, no_show: 1, postponed: 1, suspended_resumed: 1, venue_changed: 1 });
  const delayed = matches.filter(({ lateArrivalStatus }) => lateArrivalStatus === "arrived_within_policy");
  assert.equal(delayed.length, 1);
  assert.equal(delayed[0]!.exceptionType, "none");
  const postponed = matches.find(({ exceptionType }) => exceptionType === "postponed")!;
  assert.notEqual(postponed.originalScheduledStart, postponed.scheduledStart);
  assert.deepEqual(postponed.lineage.map(({ type }) => type), ["postponement", "fixture_change", "official_result"]);
  const noShow = matches.find(({ exceptionType }) => exceptionType === "no_show")!;
  assert.deepEqual(noShow.result, { away: 0, home: 3 });
  assert.equal(noShow.officialDecision.outcome, "NO_SHOW");
  const suspension = matches.find(({ exceptionType }) => exceptionType === "suspended_resumed")!;
  assert.equal(suspension.partialResult?.minute, 38);
  assert.deepEqual(suspension.lineage.map(({ type }) => type), ["suspension", "resumption", "official_result"]);
  assert.ok(matches.every((match) => match.scorers.reduce((sum, scorer) => sum + scorer.goals, 0) === match.result.home + match.result.away));
});

test("Clubs, referee profiles and assignment read models form one public-safe graph", async () => {
  const world = await committedSnapshot();
  const proof = loadDemoWorldV2AuthorityProof();
  assert.equal(world.clubsReferees.clubs.length, 3);
  assert.equal(world.clubsReferees.referees.length, 8);
  assert.equal(world.clubsReferees.refereeAssignmentsEnabled, true);
  assert.equal(world.clubsReferees.relationships.filter(({ type }) => type === "club_team").length, 6);
  assert.ok(world.clubsReferees.relationships.filter(({ type }) => type === "club_referee").length >= 8);
  assert.ok(world.clubsReferees.clubs.every((club) => club.teamIds.length === 2 && Object.keys(club.publicProfile).length > 0));
  assert.ok(world.clubsReferees.referees.every((referee) => referee.marketplaceStatus === "listed" && referee.publicBio.length > 10));
  assert.deepEqual(
    world.clubsReferees.referees.map(({ statistics }) => statistics),
    proof.refereeAssignments.profiles.map(({ statistics }) => statistics),
  );

  const assignments = world.clubsReferees.refereeAssignmentPreview.items as Array<Record<string, unknown>>;
  const counts = assignments.reduce<Record<string, number>>((result, assignment) => {
    const status = String(assignment.status);
    result[status] = (result[status] ?? 0) + 1;
    return result;
  }, {});
  assert.equal(assignments.length, 16);
  assert.deepEqual(counts, { cancelled: 1, completed: 13, declined: 1, replaced: 1 });
  assert.equal(proof.refereeAssignments.noActiveOverlaps, true);
  assert.equal(proof.refereeAssignments.oneMainRefereePerMatch, true);
  assert.equal(proof.refereeAssignments.overlapRejected, true);
  assert.equal(proof.refereeAssignments.statisticsConverged, true);
  assert.deepEqual(proof.refereeAssignments.r5LinkedEvents, {
    linked: 18,
    onRefereedMatches: 18,
    unlinkedEventKeys: [],
  });
  assert.ok(assignments.some((assignment) => assignment.status === "replaced" && assignment.replacedByAssignmentId));
  assert.ok(assignments.some((assignment) => assignment.replacesAssignmentId && assignment.status === "completed"));
  assert.ok(assignments.some((assignment) => assignment.reconfirmed === true && assignment.scheduledStart !== assignment.effectiveScheduledStart));
  assert.equal(Object.keys(world.competitions.refereeAssignmentPreviews).length, 15);
  assert.doesNotMatch(JSON.stringify(world.clubsReferees.refereeAssignmentPreview), /privateTerms|privateTermsNote|agreedFee|counterFee|proposedFee/i);
  assert.ok(world.clubsReferees.referees.some(({ publicFee }) => publicFee?.feeMode === "FIXED"));
  assert.ok(world.clubsReferees.referees.some(({ publicFee }) => publicFee?.feeMode === "NEGOTIABLE"));
  assert.ok(world.clubsReferees.referees.some(({ publicFee }) => publicFee?.feeMode === "VOLUNTEER"));
});

test("V2.3 configuration parity exposes two canonical revisions without private referee terms", async () => {
  const world = await committedSnapshot();
  const configuration = world.configuration;
  assert.equal(configuration.readOnly, true);
  assert.deepEqual(configuration.transport, { methods: ["GET"], remoteWrites: 0 });
  assert.equal(configuration.currentEditionRevision, 2);
  assert.equal(configuration.health.complete, true);
  assert.equal(configuration.health.errors, 0);
  assert.deepEqual(configuration.comparator.changedSections, ["discipline", "incidents", "match", "referees", "scoring"]);
  const [standard, custom] = configuration.revisions;
  assert.deepEqual({
    blue: standard?.blueEnabled,
    duration: standard?.matchDurationMinutes,
    fee: standard?.feeMode,
    mode: standard?.authoringMode,
    noShow: standard?.noShowWinnerScore,
    referee: standard?.refereeUsage,
    win: standard?.pointsForWin,
    yellow: standard?.yellowThreshold,
  }, { blue: false, duration: 70, fee: "NEGOTIABLE", mode: "SIMPLE", noShow: 3, referee: "OPTIONAL", win: 3, yellow: 3 });
  assert.deepEqual({
    blue: custom?.blueEnabled,
    duration: custom?.matchDurationMinutes,
    fee: custom?.feeMode,
    mode: custom?.authoringMode,
    noShow: custom?.noShowWinnerScore,
    referee: custom?.refereeUsage,
    win: custom?.pointsForWin,
    yellow: custom?.yellowThreshold,
  }, { blue: true, duration: 80, fee: "FIXED", mode: "ADVANCED", noShow: 4, referee: "REQUIRED", win: 2, yellow: 4 });
  assert.deepEqual(configuration.engineConsumption.r5CatalogCodes, ["YELLOW", "RED", "BLUE"]);
  assert.equal(configuration.engineConsumption.refereePolicy.publicConsent, false);
  assert.equal(configuration.futureCapabilities.automaticRoundRobin, true);
  assert.equal(configuration.futureCapabilities.manualAssistedPairing, false);
  assert.equal(configuration.futureCapabilities.hybridPairing, false);
  assert.equal(configuration.futureCapabilities.payments, false);
  assert.equal(configuration.futureCapabilities.tournaments, false);
  assert.doesNotMatch(JSON.stringify(configuration), /fixedCents|privateTerms|proposedFee|agreedFee/);
});

test("V2.6 preserves Group Stage and exposes the canonical knockout bracket", async () => {
  const world = assertDemoWorldV2Snapshot(await committedSnapshot());
  const tournament = world.tournament;
  assert.equal(tournament.readOnly, true);
  assert.deepEqual(tournament.transport, { methods: ["GET"], remoteWrites: 0 });
  assert.deepEqual(tournament.competition, {
    acceptedParticipants: 16,
    groupCount: 4,
    name: "COPA BARRIOS IQ 2027",
    planStatus: "published",
    potCount: 4,
    publishedRevision: 5,
    slug: "copa-barrios-iq-2027",
  });
  assert.deepEqual(tournament.constraints.map(({ type, strength }) => ({ strength, type })), [
    { strength: "HARD", type: "POT_DISTRIBUTION" },
    { strength: "SOFT", type: "SAME_CLUB_AVOIDANCE" },
    { strength: "SOFT", type: "TEAM_LEVEL_BALANCE" },
  ]);

  const [automatic, hybrid] = tournament.drawOutcomes;
  assert.equal(automatic?.mode, "SEEDED_POTS");
  assert.equal(automatic?.seed, "COPA-BARRIOS-IQ-2027-AUTO");
  assert.deepEqual(automatic?.locks, []);
  assert.equal(hybrid?.mode, "HYBRID");
  assert.equal(hybrid?.seed, "COPA-BARRIOS-IQ-2027-HYBRID");
  assert.equal(hybrid?.locks.length, 2);
  assert.equal(hybrid?.manualOverrideCount, 2);

  for (const outcome of tournament.drawOutcomes) {
    assert.equal(outcome.placements.length, 16);
    assert.equal(new Set(outcome.placements.map(({ team }) => team.id)).size, 16);
    assert.equal(outcome.hardViolations, 0);
    assert.equal(outcome.sameClubCollisions, 0);
    assert.equal(outcome.unassignedEntries, 0);
    for (const groupNumber of [1, 2, 3, 4]) {
      const group = outcome.placements.filter((placement) => placement.groupNumber === groupNumber);
      assert.equal(group.length, 4);
      assert.deepEqual(group.map(({ potNumber }) => potNumber).sort(), [1, 2, 3, 4]);
    }
  }

  assert.equal(tournament.comparison.retainedLocks, 2);
  assert.ok(tournament.comparison.movedTeams.length > 0);
  assert.equal(tournament.conflict.errorCode, "DRAW_UNSATISFIABLE");
  assert.equal(tournament.conflict.reasonCode, "GROUP_CONSTRAINTS_UNSATISFIABLE");
  assert.equal(tournament.conflict.attempts, 128);
  assert.ok(tournament.conflict.suggestions.length >= 2);
  assert.deepEqual(tournament.nextPhase, {
    bracketProgression: true,
    knockoutMatches: 8,
    message: "Torneo completado y cuadro bloqueado por PostgreSQL.",
    tournamentMatches: 32,
  });
  assert.equal(tournament.groupStage.matches.length, 24);
  assert.equal(tournament.groupStage.officialMatches, 16);
  assert.equal(tournament.groupStage.scheduledMatches, 8);
  assert.equal(tournament.groupStage.standings.length, 16);
  assert.deepEqual(tournament.groupStage.incidents, {
    disputedCorrected: 1,
    noShow: 1,
    postponedRescheduled: 1,
    suspendedResumed: 1,
  });
  assert.deepEqual(tournament.groupStage.referees, { confirmedMatches: 12, unassignedMatches: 12 });
  assert.equal(tournament.groupStage.discipline.length, 4);
  assert.equal(tournament.groupStage.sanctions.length, 1);
  assert.equal(tournament.completionProof.officialMatches, 24);
  assert.equal(tournament.completionProof.qualifiers, 8);
  assert.equal(tournament.completionProof.eliminated, 8);
  assert.equal(tournament.completionProof.bracketSources.length, 8);
  assert.equal(tournament.completionProof.knockoutMatches, 0);
  assert.equal(tournament.completionProof.progressionEnabled, false);
  assert.equal(tournament.knockout.nodes.length, 8);
  assert.equal(new Set(tournament.knockout.nodes.map(({ nodeKey }) => nodeKey)).size, 8);
  assert.deepEqual(tournament.knockout.rounds.map(({ code, matches }) => ({ code, matches })), [
    { code: "QUARTERFINAL", matches: 4 },
    { code: "SEMIFINAL", matches: 2 },
    { code: "THIRD_PLACE", matches: 1 },
    { code: "FINAL", matches: 1 },
  ]);
  assert.equal(tournament.knockout.nodes.filter(({ roundCode }) => roundCode === "QUARTERFINAL").length, 4);
  assert.equal(tournament.knockout.nodes.filter(({ roundCode }) => roundCode === "SEMIFINAL").length, 2);
  assert.equal(tournament.knockout.nodes.filter(({ roundCode }) => roundCode === "THIRD_PLACE").length, 1);
  assert.equal(tournament.knockout.nodes.filter(({ roundCode }) => roundCode === "FINAL").length, 1);
  assert.equal(tournament.knockout.nodes.filter(({ resolutionKind }) => resolutionKind === "EXTRA_TIME").length, 1);
  const shootout = tournament.knockout.nodes.find(({ resolutionKind }) => resolutionKind === "PENALTY_SHOOTOUT");
  assert.deepEqual(shootout?.regulationScore, { away: 1, home: 1 });
  assert.deepEqual(shootout?.shootout, { away: 4, home: 5 });
  assert.equal(tournament.knockout.authority.penaltySeparation.groupStandingsUnchanged, true);
  assert.equal(tournament.knockout.authority.penaltySeparation.shootoutGoalsAddedToSportingScore, false);
  assert.equal(tournament.knockout.authority.noShowResolutionLinked, true);
  assert.deepEqual(tournament.knockout.authority.correction, {
    nodeHistoryRetained: true,
    oldContextRetired: true,
    oldMatchRetired: true,
    replacementCreated: true,
  });
  assert.equal(tournament.knockout.authority.activeMatches, 8);
  assert.equal(tournament.knockout.authority.historicalMatches, 9);
  assert.equal(tournament.knockout.authority.retiredMatches, 1);
  assert.equal(tournament.knockout.referees.semifinalReplacement.originalStatus, "replaced");
  assert.equal(tournament.knockout.referees.semifinalReplacement.replacementStatus, "confirmed");
  assert.equal(tournament.knockout.referees.semifinalReplacement.lineageLinked, true);
  assert.equal(tournament.knockout.referees.final.status, "confirmed");
  assert.equal(tournament.knockout.discipline.blockedFromSemifinal, true);
  assert.equal(tournament.knockout.discipline.ratingChanged, false);
  assert.equal(new Set([
    tournament.knockout.podium.champion.id,
    tournament.knockout.podium.runnerUp.id,
    tournament.knockout.podium.thirdPlace.id,
    tournament.knockout.podium.fourthPlace.id,
  ]).size, 4);
  assert.equal(world.manifest.counts.canonicalMatches, 48);
  assert.equal(world.manifest.counts.rounds, 12);
  assert.doesNotMatch(JSON.stringify(tournament), /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i);
});

test("the historical V2.1 through V2.6 snapshots remain immutable beside V2.7", async () => {
  const expectedFiles = ["activity.json", "clubs-referees.json", "competitions.json", "core.json", "manifest.json", "matches.json", "players.json"];
  await Promise.all(expectedFiles.map((name) => readFile(path.join(historicalV21Root, name), "utf8")));
  const manifest = JSON.parse(await readFile(path.join(historicalV21Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(manifest.version, 2.1);
  assert.equal(manifest.seed, "pachangas-iq-demo-world-v2-1-2026-27");
  assert.equal(manifest.hash, "0eae1613e2d84fdd5f0821cfc2f7ad77b7bc4193a6c50ee3d58c0431ee493a51");
  await Promise.all(expectedFiles.map((name) => readFile(path.join(historicalV22Root, name), "utf8")));
  const v22Manifest = JSON.parse(await readFile(path.join(historicalV22Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(v22Manifest.version, 2.2);
  assert.equal(v22Manifest.seed, "pachangas-iq-demo-world-v2-2-2026-27");
  assert.equal(v22Manifest.hash, "58074f1cf5892f5730fee4e3af4d62b44f8d551ee4f21f9ec07acebb46a65697");
  const v23Files = [...expectedFiles, "configuration.json"];
  await Promise.all(v23Files.map((name) => readFile(path.join(historicalV23Root, name), "utf8")));
  const v23Manifest = JSON.parse(await readFile(path.join(historicalV23Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(v23Manifest.version, 2.3);
  assert.equal(v23Manifest.seed, "pachangas-iq-demo-world-v2-3-2026-27");
  assert.equal(v23Manifest.hash, "9dca7d56ef77a17fbc3b625a89bfcd44096afa8e1a0420689531b6573b3bc170");
  const v24Files = [...v23Files, "tournament.json"];
  await Promise.all(v24Files.map((name) => readFile(path.join(historicalV24Root, name), "utf8")));
  const v24Manifest = JSON.parse(await readFile(path.join(historicalV24Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(v24Manifest.version, 2.4);
  assert.equal(v24Manifest.seed, "pachangas-iq-demo-world-v2-4-2026-27");
  assert.equal(v24Manifest.hash, "e3fa89f32278fac9d49eca3635ff19255a06f76b7cd65eff12b916c958c0141b");
  await Promise.all(v24Files.map((name) => readFile(path.join(historicalV25Root, name), "utf8")));
  const v25Manifest = JSON.parse(await readFile(path.join(historicalV25Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(v25Manifest.version, 2.5);
  assert.equal(v25Manifest.seed, "pachangas-iq-demo-world-v2-5-2026-27");
  assert.equal(v25Manifest.hash, "675d2992138de4253a0e9e09eab77d09682cecc708fc06a4f87ed0e6d15e57f8");
  await Promise.all(v24Files.map((name) => readFile(path.join(historicalV26Root, name), "utf8")));
  const v26Manifest = JSON.parse(await readFile(path.join(historicalV26Root, "manifest.json"), "utf8")) as Record<string, unknown>;
  assert.equal(v26Manifest.version, 2.6);
  assert.equal(v26Manifest.seed, "pachangas-iq-demo-world-v2-6-2026-27");
  assert.equal(v26Manifest.hash, "3b770ddde8a3d3599581e963f836b28e00d9ce8496d9127facdaa091f3aa68d9");
});

test("V2.7 public competitions preserve publication, registration and privacy authority", async () => {
  const publicCompetitions = (await committedSnapshot()).publicCompetitions;
  const directory = publicCompetitions.directory.items as Array<Record<string, unknown>>;
  const publicationOf = (view: Record<string, unknown>) => view.publication as Record<string, unknown>;
  const statuses = new Map(publicCompetitions.requests.map((request) => [request.status, request]));

  assert.equal(publicCompetitions.readOnly, true);
  assert.deepEqual(publicCompetitions.transport, { methods: ["GET"], remoteWrites: 0 });
  assert.equal(publicCompetitions.remoteWrites, 0);
  assert.equal(publicCompetitions.operationReceipts, 40);
  assert.equal(publicCompetitions.provenance.verified, true);
  assert.deepEqual(publicCompetitions.provenance.rpcFamilies, [
    "PUBLICATION",
    "REGISTRATION_REQUESTS",
    "WAITLIST",
    "PUBLIC_READ_MODELS",
  ]);

  assert.equal(directory.length, 2);
  assert.ok(directory.every((view) => publicationOf(view).visibility === "public" && publicationOf(view).status === "published"));
  assert.equal(publicationOf(publicCompetitions.unlisted.hub).visibility, "unlisted");
  assert.equal(publicationOf(publicCompetitions.organizerPrivate.hub).visibility, "private");
  assert.ok(directory.every((view) => !["copa-enlace-demo", "liga-privada-organizador-demo"].includes(String(publicationOf(view).slug))));

  assert.equal(statuses.get("accepted")?.entryCreated, true);
  assert.equal(statuses.get("waitlisted")?.entryCreated, false);
  assert.ok(Number(statuses.get("waitlisted")?.waitlistPosition) > 0);
  assert.equal(statuses.get("rejected")?.entryCreated, false);
  assert.equal(statuses.get("withdrawn")?.entryCreated, false);
  assert.deepEqual(publicCompetitions.privacy, {
    containsContactData: false,
    containsOwnerIdentity: false,
    containsPrivateReason: false,
    containsRequestMessage: false,
  });

  const publicPayload: Record<string, unknown> = { ...publicCompetitions };
  delete publicPayload.privacy;
  const serialized = JSON.stringify(publicPayload);
  assert.doesNotMatch(serialized, /"(?:email|telephone|phone|requestedBy|privateReason|privateNote|message|attendance|roster|fee)"\s*:/i);
  assert.ok(publicCompetitions.league.calendar.items.length > 0);
  assert.ok(publicCompetitions.tournament.calendar.items.length > 0);
  assert.ok(publicCompetitions.tournament.standings.items.length > 0);
  assert.ok(publicCompetitions.tournament.bracket);
});

test("V2 chunks stay lazy, GET-only and converge to the validated snapshot", async () => {
  const world = await committedSnapshot();
  const requested: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (input, init) => {
    assert.equal(init?.method, "GET");
    const url = String(input);
    requested.push(url);
    const name = url.replace(/^.*\/v2\//, "").replace(/\?.*$/, "");
    return new Response(JSON.stringify(await jsonFile(name)), { status: 200 });
  }) as typeof fetch;
  try {
    const core = await loadDemoWorldV2Core(world.manifest);
    assert.equal(requested.length, 1);
    assert.match(requested[0]!, /core\.json/);
    const loaded = await loadDemoWorldV2Snapshot(world.manifest, core);
    assert.deepEqual(loaded, world);
    assert.equal(requested.length, 9);
    assert.ok(requested.every((url) => /\?h=[0-9a-f]{16}$/.test(url)));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("the public Demo uses production renderers in one shell and exposes all V2 tabs", async () => {
  const [appSource, disciplineSource, disciplineStyles, scheduleSource, matchSource, assignmentSource, clubSource, demoStyles] = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/competition-discipline-client.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/competition-discipline-client.module.css"), "utf8"),
    readFile(path.join(root, "app/_components/league-scheduling-client.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/league-match-operations-client.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/referee-assignments-client.tsx"), "utf8"),
    readFile(path.join(root, "app/clubes/[slug]/public-club-profile.tsx"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8"),
  ]);
  for (const label of ["Liga", "Torneo", "Públicas", "Configuración", "Clasificación", "Jornadas", "Disciplina", "Club", "Árbitros"]) assert.match(appSource, new RegExp(`label: "${label}"`));
  assert.match(appSource, /LeagueSchedulingClient embedded/);
  assert.match(appSource, /onOpenMatch=\{\(canonicalMatchId\)/);
  assert.match(appSource, /entry\.canonicalMatchId === canonicalMatchId/);
  assert.match(appSource, /LeagueMatchOperationsClient embedded/);
  assert.match(appSource, /CompetitionDisciplineClient competitionId=.*embedded.*surface="public"/);
  assert.match(appSource, /disciplinePreviewData=\{selectedLeagueMatchDisciplinePreview\}/);
  assert.match(appSource, /refereeAssignmentPreviewData=\{selectedLeagueMatchRefereePreview\}/);
  assert.match(appSource, /RefereeAssignmentsClient embedded previewData=\{assignments\} surface="my"/);
  assert.match(matchSource, /previewData=\{props\.refereeAssignmentPreviewData\}/);
  assert.match(assignmentSource, /if \(previewData\) \{ setMessage\("Escenario visual: no se ha enviado ninguna escritura\."\); return; \}/);
  assert.match(matchSource, /disciplineAvailable=\{Boolean\(props\.disciplinePreviewData\)\}/);
  assert.match(matchSource, /disciplineAvailable \? "Disciplina R5" : "Disciplina oficial"/);
  assert.doesNotMatch(matchSource, /no disponible hasta R5/);
  assert.match(appSource, /PublicClubProfile club=.*embedded/);
  assert.match(appSource, /RefereeProfileCard compact/);
  assert.match(appSource, /data-demo-domain="configuration" data-demo-read-only="true"/);
  assert.match(appSource, /data-demo-domain="tournament" data-demo-read-only="true"/);
  for (const label of ["Directorio", "Liga pública", "Torneo público", "Solicitudes", "Lista de espera", "No listada", "Organizador", "Participante"]) {
    assert.match(appSource, new RegExp(`label: "${label}"`));
  }
  assert.match(appSource, /import \{ CompetitionDirectoryClient \} from "\.\.\/competiciones\/competition-directory-client"/);
  assert.match(appSource, /import \{ PublicCompetitionHub \} from "\.\.\/competiciones\/\[competition\]\/public-competition-hub"/);
  assert.match(appSource, /<CompetitionDirectoryClient embedded initialData=\{data\.directory\}/);
  assert.match(appSource, /<PublicCompetitionHub embedded/);
  for (const label of ["Resumen", "Jornadas", "Partidos", "Clasificación", "Equipos", "Disciplina", "Árbitros", "Incidencias", "Reglamento", "Cuadro"]) {
    assert.match(appSource, new RegExp(`label: "${label}"`));
  }
  assert.match(appSource, /32 CanonicalMatches activos/);
  assert.match(appSource, /R6C · Single leg/);
  assert.match(appSource, /R6C verificado/);
  assert.match(appSource, /Cuadro oficial/);
  assert.match(appSource, /Recorrido por equipo/);
  assert.match(appSource, /Prórroga, penaltis, no-show y corrección trazados/);
  assert.match(appSource, /Tarifa fija privada/);
  assert.match(appSource, /const domainNavRef = useRef<HTMLElement>\(null\)/);
  assert.match(appSource, /navigation\.scrollWidth <= navigation\.clientWidth \+ 2/);
  assert.match(appSource, /scrollIntoView\(\{ behavior: "auto", block: "nearest", inline: "center" \}\)/);
  assert.doesNotMatch(appSource, /DemoLeagueTable|DemoLeagueMatch/);
  assert.match(scheduleSource, /embedded \? content : <OfficialProductShellV2/);
  assert.match(matchSource, /embedded[\s\S]*\? content/);
  assert.match(disciplineSource, /preview=\{Boolean\(previewData\)\}/);
  assert.match(disciplineStyles, /\.eventRows article \{ grid-template-columns: 16px minmax\(0, 1fr\) minmax\(86px, auto\); \}/);
  assert.match(disciplineStyles, /\.eventRows article > span:nth-of-type\(3\) \{ display: none; \}/);
  assert.doesNotMatch(disciplineStyles, /span:nth-of-type\(2\),\s*\n\s*\.eventRows article > span:nth-of-type\(3\)/);
  assert.match(clubSource, /embedded \? content/);
  assert.match(demoStyles, /\.leagueHero \{ min-height: calc\(100dvh - var\(--game-nav-height, 48px\) - 36px\)/);
  assert.match(demoStyles, /\.tournamentSubnav \{[\s\S]*min-height: 36px;[\s\S]*height: 36px;[\s\S]*overflow-y: hidden;/);
  assert.match(demoStyles, /\.demoProductView \{[\s\S]*--official-text: #f1f6f2;/);
  assert.match(demoStyles, /\.demoProductView \.demoDomainHeading h1 \{[\s\S]*color: var\(--official-text\);/);
  assert.match(demoStyles, /\.configurationRevisionGrid \{/);
  assert.equal(demoWorldV2TabFromSearch("?tab=clasificacion"), "clasificacion");
  assert.equal(demoWorldV2TabFromSearch("?tab=configuracion"), "configuracion");
  assert.equal(demoWorldV2TabFromSearch("?tab=torneo"), "torneo");
  assert.equal(demoWorldV2TabFromSearch("?tab=disciplina"), "disciplina");
  assert.equal(demoWorldV2TabFromSearch("?tab=desconocido"), "inicio");
});

test("the V2 public bundle contains no PII, remote write path or product mutation", async () => {
  const world = await committedSnapshot();
  const serialized = JSON.stringify(world).toLowerCase();
  for (const forbidden of ["@example", "service_role", "access_token", "refresh_token", "phone", "telephone", "private_address", "fixedcents"]) {
    assert.doesNotMatch(serialized, new RegExp(forbidden));
  }
  const sources = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-v2-client-state.ts"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
  ]).then((parts) => parts.join("\n"));
  assert.doesNotMatch(sources, /\.rpc\(|service_role|method:\s*["'](?:POST|PUT|PATCH|DELETE)/);
  assert.match(sources, /method:\s*"GET"/);
  assert.match(sources, /sessionStorage/);
});

test("the Service Worker precaches V2 and caches every immutable versioned Demo chunk", () => {
  const source = buildServiceWorkerSource("demo-world-v2-test");
  assert.match(source, /"\/demo-world\/v2\/manifest\.json"/);
  assert.match(source, /\^\\\/demo-world\\\/v\\d\+\\\//);
  assert.match(source, /request\.method !== "GET"/);
  assert.match(source, /isImmutableDemoChunk/);
});

test("a warmed immutable Demo chunk remains readable after the network goes offline", async () => {
  const listeners = new Map<string, (event: Record<string, unknown>) => void>();
  const entries = new Map<string, Response>();
  let online = true;

  const cache = {
    addAll: async () => undefined,
    delete: async (request: Request | string) => entries.delete(typeof request === "string" ? request : request.url),
    keys: async () => [...entries.keys()].map((url) => new Request(url)),
    match: async (request: Request | string) => entries.get(typeof request === "string" ? new URL(request, "https://pachangasiq.com").href : request.url)?.clone(),
    put: async (request: Request | string, response: Response) => {
      entries.set(typeof request === "string" ? new URL(request, "https://pachangasiq.com").href : request.url, response.clone());
    },
  };
  const context = {
    URL,
    Request,
    Response,
    caches: {
      delete: async () => true,
      keys: async () => [],
      open: async () => cache,
    },
    fetch: async () => {
      if (!online) throw new TypeError("Failed to fetch");
      return new Response(JSON.stringify({ canonical: true, version: 2.7 }), {
        headers: { "content-type": "application/json" },
        status: 200,
      });
    },
    self: {
      addEventListener: (type: string, listener: (event: Record<string, unknown>) => void) => listeners.set(type, listener),
      clients: { claim: async () => undefined },
      location: new URL("https://pachangasiq.com/sw.js"),
      registration: { navigationPreload: { enable: async () => undefined } },
      skipWaiting: async () => undefined,
    },
  };
  runInNewContext(buildServiceWorkerSource("demo-world-v2-offline-regression"), context);

  const chunkUrl = "https://pachangasiq.com/demo-world/v2/public-competitions.json?h=e4830ff25db5318a";
  const dispatchFetch = async () => {
    let responsePromise: Promise<Response> | undefined;
    listeners.get("fetch")?.({
      request: new Request(chunkUrl),
      respondWith: (response: Promise<Response>) => { responsePromise = response; },
    });
    assert.ok(responsePromise, "the immutable Demo JSON request must be handled by the Service Worker");
    return responsePromise;
  };

  const onlineResponse = await dispatchFetch();
  assert.deepEqual(await onlineResponse.json(), { canonical: true, version: 2.7 });
  assert.equal(entries.has(chunkUrl), true);

  online = false;
  const offlineResponse = await dispatchFetch();
  assert.deepEqual(await offlineResponse.json(), { canonical: true, version: 2.7 });
});
