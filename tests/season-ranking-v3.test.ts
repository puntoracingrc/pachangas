import assert from "node:assert/strict";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import { rankSeason } from "../simulation/season-ranking-lab/src/engine";
import {
  RANKING_ELIGIBILITY,
  TROPHY_RULES,
  awardDecisionForPendingCandidate,
  buildOpponentGraph,
  compareV3Players,
  confidenceWeight,
  enrichCompetitiveEvidence,
  evaluateV3Ranking,
  participationConfirmationExperiment,
  type TeamIntegrityProfile,
  type V3RankedPlayer,
} from "../simulation/season-ranking-lab/src/integrity-v3";
import { createProfileInput } from "../simulation/season-ranking-lab/src/scenarios";
import { collusionExperiment } from "../simulation/season-ranking-lab/src/v3-validation";
import type { SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";

const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
const baseline: SeasonScoreConfig = {
  ...previous,
  eligibility: { ...RANKING_ELIGIBILITY },
  id: "v3-baseline-55-30-15",
  label: "V3 baseline 55/30/15 recent30",
  ratingConfidenceModel: "full",
  volumeModel: "recent_30",
  weights: { competition: 30, opposition: 15, quality: 55 },
};

function team(overrides: Partial<TeamIntegrityProfile> & Pick<TeamIntegrityProfile, "id">): TeamIntegrityProfile {
  return {
    adminIds: [`admin-${overrides.id}`],
    createdDaysAgo: 600,
    ownerId: `owner-${overrides.id}`,
    playerIds: Array.from({ length: 10 }, (_, index) => `${overrides.id}-p${index}`),
    provinceCode: "08",
    sportsClusterId: `sport-${overrides.id}`,
    venueClusterId: "venue-08",
    ...overrides,
  };
}

test("V3 keeps the 55/30/15 recent30 baseline and 15/6 ranking eligibility", () => {
  assert.deepEqual(baseline.weights, { competition: 30, opposition: 15, quality: 55 });
  assert.equal(baseline.volumeModel, "recent_30");
  assert.deepEqual(baseline.eligibility, RANKING_ELIGIBILITY);
});

test("logical opponents collapse new 90%-shared fake teams but preserve a legitimate club", () => {
  const shared = Array.from({ length: 9 }, (_, index) => `shared-${index}`);
  const fakeA = team({ adminIds: ["fake-admin"], createdDaysAgo: 3, id: "fake-a", ownerId: "fake-owner", playerIds: [...shared, "a"] });
  const fakeB = team({ adminIds: ["fake-admin"], createdDaysAgo: 4, id: "fake-b", ownerId: "fake-owner", playerIds: [...shared, "b"] });
  const clubA = team({ adminIds: ["club-admin"], id: "club-u23", ownerId: "club-x", playerIds: ["club-shared", ...Array.from({ length: 9 }, (_, index) => `u23-${index}`)] });
  const clubB = team({ adminIds: ["club-admin"], id: "club-veterans", ownerId: "club-x", playerIds: ["club-shared", ...Array.from({ length: 9 }, (_, index) => `vet-${index}`)] });
  const graph = buildOpponentGraph([fakeA, fakeB, clubA, clubB]);
  assert.equal(graph.logicalOpponentByTeam.get("fake-a"), graph.logicalOpponentByTeam.get("fake-b"));
  assert.notEqual(graph.logicalOpponentByTeam.get("club-u23"), graph.logicalOpponentByTeam.get("club-veterans"));
});

test("opponent independence is low for fake shared rosters and remains usable for real club squads", () => {
  const input = createProfileInput({ challenges: 2, id: "graph-player", opponentRating: 84, rating: 85, technicalOpponents: 2, winRate: 0.5 });
  input.records[0]!.teamId = "beneficiary";
  input.records[0]!.opponentTeamId = "fake-a";
  input.records[1]!.teamId = "club-u23";
  input.records[1]!.opponentTeamId = "club-veterans";
  const shared = Array.from({ length: 9 }, (_, index) => `shared-${index}`);
  const graph = buildOpponentGraph([
    team({ id: "beneficiary" }),
    team({ adminIds: ["fake-admin"], createdDaysAgo: 3, id: "fake-a", ownerId: "fake-owner", playerIds: [...shared, "a"] }),
    team({ adminIds: ["fake-admin"], createdDaysAgo: 4, id: "fake-b", ownerId: "fake-owner", playerIds: [...shared, "b"] }),
    team({ adminIds: ["club-admin"], id: "club-u23", ownerId: "club-x", playerIds: ["club-shared", ...Array.from({ length: 9 }, (_, index) => `u23-${index}`)] }),
    team({ adminIds: ["club-admin"], id: "club-veterans", ownerId: "club-x", playerIds: ["club-shared", ...Array.from({ length: 9 }, (_, index) => `vet-${index}`)] }),
  ], [input]);
  const evidence = enrichCompetitiveEvidence(input, graph);
  assert.ok(evidence[0]!.opponentIndependenceScore <= 0.5);
  assert.ok(evidence[1]!.opponentIndependenceScore > 0.6);
});

test("graduated confidence excludes weak evidence and never overweights partial evidence", () => {
  assert.equal(confidenceWeight(0.49, "graduated"), 0);
  assert.ok(confidenceWeight(0.6, "graduated") > 0 && confidenceWeight(0.6, "graduated") < 1);
  assert.equal(confidenceWeight(0.75, "graduated"), 1);
  assert.equal(confidenceWeight(0.74, "hard_075"), 0);
});

test("evidence exclusion removes low-confidence matches from ranking eligibility", () => {
  const input = createProfileInput({
    challenges: 20,
    id: "ghost-participation",
    opponentRating: 88,
    participationConfidence: 0,
    rating: 92,
    sameDay: true,
    technicalOpponents: 10,
    winRate: 1,
  });
  const graph = buildOpponentGraph([], [input]);
  const [result] = evaluateV3Ranking({
    config: baseline,
    graph,
    inputs: [input],
    strategy: "exclusion_and_hold",
    trophyRule: TROPHY_RULES.province,
  });
  assert.equal(result!.eligibility.eligible, false);
  assert.equal(result!.certification, "not_eligible");
});

test("unconfirmed physical participation cannot remain ranking evidence through aggregate confidence", () => {
  const input = createProfileInput({ challenges: 20, id: "physical-presence", opponentRating: 84, participationConfidence: 0.15, rating: 88, technicalOpponents: 10, winRate: 0.8 });
  const graph = buildOpponentGraph([], [input]);
  assert.ok(enrichCompetitiveEvidence(input, graph).every(({ confidenceWeight }) => confidenceWeight === 0));
});

test("territory evidence with an unverified venue cannot decide a territorial ranking", () => {
  const input = createProfileInput({ challenges: 20, id: "territory-evidence", opponentRating: 84, provinceCodes: ["17"], rating: 88, technicalOpponents: 10, venueConfidence: 0.2, winRate: 0.8 });
  const graph = buildOpponentGraph([], [input]);
  assert.ok(enrichCompetitiveEvidence(input, graph).every(({ confidenceWeight }) => confidenceWeight === 0));
});

test("certification distinguishes eligible, provisional, pending and not eligible", () => {
  const eligible = createProfileInput({ challenges: 30, id: "eligible", opponentRating: 84, rating: 88, technicalOpponents: 12, winRate: 0.62 });
  const weak = createProfileInput({ challenges: 10, id: "weak", opponentRating: 84, rating: 88, technicalOpponents: 4, winRate: 0.62 });
  const risky = createProfileInput({ accountAgeDays: 1, challenges: 30, id: "risky", independence: 0.2, logicalOpponents: 6, opponentRating: 94, participationConfidence: 0.8, provinceCodes: ["08", "17", "43"], rating: 97, sameDay: true, technicalOpponents: 12, venueConfidence: 0.5, winRate: 1 });
  risky.records = risky.records.map((record) => ({ ...record, occurredAt: "2029-06-30T18:00:00.000Z", week: 48 }));
  const graph = buildOpponentGraph([], [eligible, weak, risky]);
  const laxRule = { ...TROPHY_RULES.province, minimumCompetitionNetworkDiversity: 0.05, minimumCompetitiveConfidence: 0.2, minimumLogicalOpponents: 6 };
  const certified = evaluateV3Ranking({ config: baseline, graph, inputs: [eligible, weak, risky], strategy: "certification_hold", trophyRule: laxRule });
  assert.equal(certified.find(({ playerId }) => playerId === "eligible")!.certification, "eligible");
  assert.equal(certified.find(({ playerId }) => playerId === "weak")!.certification, "not_eligible");
  assert.equal(certified.find(({ playerId }) => playerId === "risky")!.certification, "pending_integrity_review");
  const frozen = evaluateV3Ranking({ config: baseline, graph, inputs: [eligible], phase: "frozen", strategy: "certification_hold", trophyRule: laxRule });
  assert.equal(frozen[0]!.certification, "provisional");
});

test("a pending rank 8 does not promote rank 11 under the recommended policy", () => {
  assert.deepEqual(awardDecisionForPendingCandidate("trophy_pending"), { promoteRank11: false, trophyStatus: "pending" });
});

test("a closed network of ten established teams holds certification without changing Season Score", () => {
  const rows = collusionExperiment(baseline).filter(({ scenario }) => scenario === "ten-team-ring");
  const control = rows.find(({ strategy }) => strategy === "control")!;
  const protectedResult = rows.find(({ strategy }) => strategy === "exclusion_and_hold")!;
  assert.equal(protectedResult.score, control.score);
  assert.equal(protectedResult.certification, "pending_integrity_review");
});

test("internal ranking uses canonical precision before the visible rounded score", () => {
  const lower = createProfileInput({ challenges: 20, id: "a-lower", opponentRating: 84, rating: 80, technicalOpponents: 8, winRate: 0.6 });
  const higher = structuredClone(lower);
  higher.player.id = "z-higher";
  higher.player.ratingV2 += 0.0005;
  higher.records = higher.records.map((record, index) => ({ ...record, challengeId: `higher-${index}` }));
  const ranked = rankSeason([lower, higher], baseline);
  const lowResult = ranked.find(({ playerId }) => playerId === "a-lower")!;
  const highResult = ranked.find(({ playerId }) => playerId === "z-higher")!;
  assert.equal(lowResult.score, highResult.score);
  assert.ok(highResult.rawScore > lowResult.rawScore);
  assert.equal(highResult.nationalRank, 1);
});

test("exact canonical ties use only the public deterministic V3 tie-break order", () => {
  const input = createProfileInput({ challenges: 30, id: "tie", opponentRating: 84, rating: 86, technicalOpponents: 12, winRate: 0.6 });
  const graph = buildOpponentGraph([], [input]);
  const [baseResult] = evaluateV3Ranking({ config: baseline, graph, inputs: [input], strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  const left = { ...baseResult!, playerId: "left", competitiveConfidence: 0.9 } as V3RankedPlayer;
  const right = { ...baseResult!, playerId: "right", competitiveConfidence: 0.8 } as V3RankedPlayer;
  assert.ok(compareV3Players(left, right) < 0);
});

test("sampled participation confirmation is the best UX/resistance compromise in the lab assumptions", () => {
  const rows = participationConfirmationExperiment();
  const sampled = rows.find(({ id }) => id === "sampled")!;
  const rival = rows.find(({ id }) => id === "rival")!;
  assert.ok(sampled.additionalActionsPerMatch < rival.additionalActionsPerMatch);
  assert.ok(sampled.attackAcceptanceRate <= 0.12);
  assert.ok(sampled.legitimateCompletionRate >= 0.95);
});
