import assert from "node:assert/strict";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import { calculateSeasonScore, rankSeason } from "../simulation/season-ranking-lab/src/engine";
import {
  evaluateEliteByScope,
  evaluateNationalTops,
  evaluateOrderedGroup,
  evaluatePredictiveTops,
  ndcgAtK,
  splitInputsForOutOfSample,
} from "../simulation/season-ranking-lab/src/elite-metrics";
import {
  applyTrophyEligibility,
  bootstrapCutoffUncertainty,
  ownTeamDiversityExperiment,
  teamStrengthFairnessExperiment,
} from "../simulation/season-ranking-lab/src/elite-validation";
import { createProfileInput } from "../simulation/season-ranking-lab/src/scenarios";
import { createSimulationWorld } from "../simulation/season-ranking-lab/src/simulator";
import type { SeasonPlayerInput, SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";

const candidates = configData.candidates as SeasonScoreConfig[];
const base = candidates.find(({ id }) => id === "candidate_e_recent20")!;

function provincePopulation(size: number, provinceCode: string, prefix: string): SeasonPlayerInput[] {
  return Array.from({ length: size }, (_, index) => createProfileInput({
    challenges: 30,
    id: `${prefix}-${String(index + 1).padStart(2, "0")}`,
    latentSkill: 95 - index * 0.8,
    opponentRating: 82,
    provinceCodes: [provinceCode],
    rating: 95 - index * 0.8,
    technicalOpponents: 12,
    winRate: Math.max(0.35, 0.75 - index * 0.01),
  }));
}

test("NDCG and near-miss metrics reward elite proximity without demanding exact order", () => {
  const reference = Array.from({ length: 30 }, (_, index) => `p${index + 1}`);
  assert.equal(ndcgAtK(reference, reference, 10), 1);
  const predicted = [...reference];
  [predicted[9], predicted[10]] = [predicted[10]!, predicted[9]!];
  const metrics = evaluateOrderedGroup(predicted, reference, {
    density: "dense",
    eligiblePlayers: 30,
    scopeCode: "08",
    scopeName: "Barcelona",
    scopeType: "province",
    truth: "capacity",
  });
  assert.equal(metrics.precisionAt10, 0.9);
  assert.equal(metrics.candidateRecallAt20, 1);
  assert.equal(metrics.top10NearMissRate, 1);
  assert.ok(metrics.ndcgAt10 > 0.9);
  const distant = [...reference.slice(10), ...reference.slice(0, 10)];
  assert.ok(ndcgAtK(predicted, reference, 10) > ndcgAtK(distant, reference, 10));
});

test("predictive validation reports Top 10, 25, 50 and 100 without future leakage", () => {
  const inputs = provincePopulation(120, "08", "predictive");
  const training = splitInputsForOutOfSample(inputs, 34);
  const rows = evaluatePredictiveTops(inputs, rankSeason(training, base, 34));
  assert.deepEqual(rows.map(({ k }) => k), [10, 25, 50, 100]);
  assert.ok(rows.every(({ eligiblePlayers, futureCompetitiveIndex, futureOpposition, futurePerformance }) => (
    eligiblePlayers >= 100
    && Number.isFinite(futureCompetitiveIndex)
    && Number.isFinite(futureOpposition)
    && Number.isFinite(futurePerformance)
  )));
});

test("elite metrics split provinces and keep national tops separate", () => {
  const inputs = [...provincePopulation(30, "08", "barcelona"), ...provincePopulation(30, "17", "girona")];
  const results = rankSeason(inputs, base);
  const provinces = evaluateEliteByScope({ inputs, minimumEligible: 20, results, scope: "province", truth: "capacity" });
  assert.equal(provinces.length, 2);
  assert.ok(provinces.every(({ eligiblePlayers }) => eligiblePlayers === 30));
  assert.deepEqual(evaluateNationalTops(inputs, results, "capacity").map(({ k }) => k), [10, 25, 50, 100]);
});

test("out-of-sample split never leaks weeks 35 through 52 into ranking inputs", () => {
  const inputs = provincePopulation(25, "08", "future");
  const training = splitInputsForOutOfSample(inputs, 34);
  assert.ok(training.every((input) => input.records.every(({ week }) => week <= 34)));
  const before = rankSeason(training, base, 34).map(({ playerId, score }) => [playerId, score]);
  inputs.forEach((input) => input.records.filter(({ week }) => week > 34).forEach((record) => { record.result = record.result === 1 ? 0 : 1; }));
  const after = rankSeason(splitInputsForOutOfSample(inputs, 34), base, 34).map(({ playerId, score }) => [playerId, score]);
  assert.deepEqual(after, before);
});

test("recent30 and hybrid windows remain finite, saturated and reproducible", () => {
  const input = createProfileInput({ challenges: 80, id: "hybrid", opponentRating: 84, rating: 86, technicalOpponents: 14, winRate: 0.6 });
  const recent30 = calculateSeasonScore(input, { ...base, volumeModel: "recent_30" });
  const hybridFirst = calculateSeasonScore(input, { ...base, volumeModel: "hybrid_70_30" });
  const hybridSecond = calculateSeasonScore(input, { ...base, volumeModel: "hybrid_70_30" });
  assert.ok(Number.isFinite(recent30.score));
  assert.ok(Number.isFinite(hybridFirst.score));
  assert.deepEqual(hybridFirst, hybridSecond);
  assert.ok(hybridFirst.weightedChallenges < input.records.length);
});

test("hidden synthetic individual performance is ground truth only and never enters Season Score", () => {
  const input = createProfileInput({ challenges: 30, id: "hidden-outcome", opponentRating: 84, rating: 86, technicalOpponents: 12, winRate: 0.6 });
  const before = calculateSeasonScore(input, base);
  const changed: SeasonPlayerInput = {
    ...input,
    records: input.records.map((record, index) => ({ ...record, individualPerformanceIndex: index % 2 === 0 ? 0 : 100 })),
  };
  assert.deepEqual(calculateSeasonScore(changed, base), before);
});

test("challenge-calibrated quality is read-only and team strength does not dominate player quality", () => {
  const config: SeasonScoreConfig = { ...base, ratingConfidenceModel: "challenge_calibrated" };
  const cases = teamStrengthFairnessExperiment(config);
  const mediocre = cases.find(({ label }) => label === "mediocre-strong-team")!;
  const excellent = cases.find(({ label }) => label === "excellent-weak-team")!;
  assert.ok(excellent.quality > mediocre.quality);
  assert.ok(excellent.score > mediocre.score);
  assert.equal(mediocre.rating, 75);
  assert.equal(excellent.rating, 91);
});

test("playing for more own teams never creates a direct Season Score bonus", () => {
  const rows = ownTeamDiversityExperiment(base);
  assert.equal(new Set(rows.map(({ score }) => score)).size, 1);
  assert.equal(new Set(rows.map(({ risk }) => risk)).size, 1);
});

test("trophy eligibility is stricter than visible ranking eligibility", () => {
  const inputs = provincePopulation(40, "08", "trophy");
  const results = rankSeason(inputs, base);
  const strict = applyTrophyEligibility(inputs, results, {
    minimumChallenges: 30,
    minimumCompetitiveConfidence: 0.8,
    minimumUniqueOpponents: 10,
    recentWeeks: 10,
  });
  assert.ok(strict.filter(({ eligibility }) => eligibility.eligible).length <= results.filter(({ eligibility }) => eligibility.eligible).length);
});

test("bootstrap cutoff uncertainty is deterministic and compares rank 10 with rank 11", () => {
  const inputs = provincePopulation(24, "08", "bootstrap");
  const results = rankSeason(inputs, base);
  const first = bootstrapCutoffUncertainty(inputs, results, base, { iterations: 20, minimumEligible: 20, seed: 115 });
  const second = bootstrapCutoffUncertainty(inputs, results, base, { iterations: 20, minimumEligible: 20, seed: 115 });
  assert.deepEqual(first, second);
  assert.equal(first.length, 1);
  assert.ok(first[0]!.rank10Confidence >= 0 && first[0]!.rank10Confidence <= 1);
});

test("seasonality profiles are deterministic and preserve the 10,000-player contract", { timeout: 120_000 }, () => {
  const first = createSimulationWorld({ activityProfile: "summer_dip", playerCount: 10_000, seasonCount: 1, seed: 9115, teamSize: 10 });
  const second = createSimulationWorld({ activityProfile: "summer_dip", playerCount: 10_000, seasonCount: 1, seed: 9115, teamSize: 10 });
  assert.equal(first.players.length, 10_000);
  assert.deepEqual(first.inputsBySeason.get(first.seasons[0]!.id)![500], second.inputsBySeason.get(second.seasons[0]!.id)![500]);
});
