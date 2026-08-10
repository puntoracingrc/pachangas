import assert from "node:assert/strict";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import {
  calculateSeasonScore,
  isSeasonScoreEvidence,
  rankSeason,
  resolveCompetitiveProvince,
} from "../simulation/season-ranking-lab/src/engine";
import {
  createProfileInput,
  goalDifferenceExperiment,
  humanProfiles,
  volumeProfiles,
} from "../simulation/season-ranking-lab/src/scenarios";
import { createSimulationWorld } from "../simulation/season-ranking-lab/src/simulator";
import {
  assertCanonicalTerritories,
  AUTONOMOUS_COMMUNITIES,
  TERRITORIES,
  TERRITORY_BY_PROVINCE,
} from "../simulation/season-ranking-lab/src/territories";
import type { SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";

const candidates = configData.candidates as SeasonScoreConfig[];
const recommended = candidates.find(({ id }) => id === "candidate_e_recent20")!;

test("canonical Spain hierarchy has 52 base territories and 17 autonomous communities", () => {
  assert.doesNotThrow(assertCanonicalTerritories);
  assert.equal(TERRITORIES.length, 52);
  assert.equal(AUTONOMOUS_COMMUNITIES.length, 17);
  assert.equal(TERRITORY_BY_PROVINCE.get("51")?.type, "autonomous_city");
  assert.equal(TERRITORY_BY_PROVINCE.get("51")?.autonomousCommunityCode, null);
  assert.equal(TERRITORY_BY_PROVINCE.get("52")?.autonomousCommunityCode, null);
  assert.equal(TERRITORIES.filter(({ territorialDuplicate }) => territorialDuplicate).length, 7);
});

test("only confirmed challenges with real participation contribute", () => {
  const input = createProfileInput({ challenges: 12, id: "status-contract", opponentRating: 82, rating: 84, technicalOpponents: 6, winRate: 0.6 });
  const [confirmed, internal, disputed, absent] = input.records;
  assert.ok(confirmed && internal && disputed && absent);
  internal.kind = "internal";
  disputed.status = "disputed";
  absent.participated = false;
  assert.equal(input.records.filter(isSeasonScoreEvidence).length, 9);
  const result = calculateSeasonScore(input, recommended);
  assert.equal(result.eligibility.validChallenges, 9);
});

test("goals and position never alter Season Score", () => {
  const defender = createProfileInput({ challenges: 25, goals: 0, id: "same-player", opponentRating: 85, position: "DEF", rating: 88, technicalOpponents: 12, winRate: 0.6 });
  const scorer = structuredClone(defender);
  scorer.player.position = "DEL";
  scorer.records.forEach((record) => { record.goals = 4; });
  assert.equal(calculateSeasonScore(defender, recommended).score, calculateSeasonScore(scorer, recommended).score);
});

test("team goal difference is excluded after an explicit incentive comparison", () => {
  const experiment = goalDifferenceExperiment(recommended);
  assert.equal(experiment.closeCurrentScore, experiment.blowoutCurrentScore);
  assert.ok(experiment.blowoutHypotheticalScore > experiment.closeHypotheticalScore);
});

test("human sanity checks hold without mutating Rating V2", () => {
  const profiles = new Map(humanProfiles().map((input) => [input.player.id, input]));
  const before = new Map([...profiles].map(([id, input]) => [id, input.player.ratingV2]));
  const scores = new Map([...profiles].map(([id, input]) => [id, calculateSeasonScore(input, recommended)]));
  assert.ok(scores.get("A")!.score > scores.get("B")!.score, "quality should beat pure hyperactivity");
  assert.equal(scores.get("C")!.eligibility.eligible, false, "five challenges are provisional");
  assert.ok(scores.get("D")!.components.competition > scores.get("B")!.components.competition, "strong opposition should matter");
  assert.ok(scores.get("F")!.score > scores.get("G")!.score, "defender can outrank scorer without a goal bonus");
  for (const [id, input] of profiles) assert.equal(input.player.ratingV2, before.get(id));
});

test("opponent decay and saturated averaging prevent infinite volume gains", () => {
  const profiles = volumeProfiles();
  const score40 = calculateSeasonScore(profiles.find(({ records }) => records.length === 40)!, recommended);
  const score80 = calculateSeasonScore(profiles.find(({ records }) => records.length === 80)!, recommended);
  const score120 = calculateSeasonScore(profiles.find(({ records }) => records.length === 120)!, recommended);
  assert.ok(Math.abs(score120.score - score40.score) < 45, `${score40.score} vs ${score120.score}`);
  assert.ok(score80.weightedChallenges <= 20);
  assert.ok(score120.weightedChallenges <= 20);
});

test("territorial ties are sticky and a real overtake moves without resetting score", () => {
  const input = createProfileInput({ challenges: 16, id: "traveller", opponentRating: 82, provinceCodes: ["08", "17"], rating: 85, technicalOpponents: 8, winRate: 0.6 });
  assert.equal(resolveCompetitiveProvince(input.records, "08"), "08");
  const before = calculateSeasonScore({ ...input, previousCompetitiveProvinceCode: "08" }, recommended);
  input.records.push({ ...input.records[0]!, challengeId: "girona-overtakes", occurredAt: "2029-07-30T20:00:00.000Z", provinceCode: "17", week: 52 });
  const after = calculateSeasonScore({ ...input, previousCompetitiveProvinceCode: "08" }, recommended);
  assert.equal(after.competitiveProvinceCode, "17");
  assert.ok(after.score > 0);
  assert.ok(Math.abs(after.score - before.score) < 30, "territory change must not reset score");
});

test("one canonical score feeds province, community and Spain ranks", () => {
  const inputs = [
    createProfileInput({ challenges: 16, id: "barcelona-1", opponentRating: 82, provinceCodes: ["08"], rating: 88, technicalOpponents: 8, winRate: 0.65 }),
    createProfileInput({ challenges: 16, id: "barcelona-2", opponentRating: 82, provinceCodes: ["08"], rating: 82, technicalOpponents: 8, winRate: 0.55 }),
  ];
  const ranked = rankSeason(inputs, recommended);
  assert.deepEqual(ranked.map(({ provinceRank }) => provinceRank), [1, 2]);
  assert.deepEqual(ranked.map(({ autonomousCommunityRank }) => autonomousCommunityRank), [1, 2]);
  assert.deepEqual(ranked.map(({ nationalRank }) => nationalRank), [1, 2]);
});

test("the 10,000-player, three-season simulation is deterministic", { timeout: 120_000 }, () => {
  const first = createSimulationWorld({ playerCount: 10_000, seasonCount: 3, seed: configData.seed, teamSize: 10 });
  const second = createSimulationWorld({ playerCount: 10_000, seasonCount: 3, seed: configData.seed, teamSize: 10 });
  assert.equal(first.players.length, 10_000);
  assert.equal(first.teams.length, 1_000);
  assert.equal(first.seasons.length, 3);
  const firstFinal = first.inputsBySeason.get(first.seasons.at(-1)!.id)!;
  const secondFinal = second.inputsBySeason.get(second.seasons.at(-1)!.id)!;
  assert.equal(firstFinal.reduce((sum, input) => sum + input.records.length, 0), secondFinal.reduce((sum, input) => sum + input.records.length, 0));
  assert.deepEqual(firstFinal[4321], secondFinal[4321]);
});
