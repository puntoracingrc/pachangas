import assert from "node:assert/strict";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import { assessRankingIntegrity, calculateSeasonScore } from "../simulation/season-ranking-lab/src/engine";
import {
  attackProfiles,
  createProfileInput,
  evaluateAttacks,
  legitimateRiskProfiles,
} from "../simulation/season-ranking-lab/src/scenarios";
import type { SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";

const candidates = configData.candidates as SeasonScoreConfig[];
const minimal = candidates.find(({ id }) => id === "candidate_a_full_rating")!;
const protectedConfig = candidates.find(({ id }) => id === "candidate_e_recent20")!;

test("simple sybil and ghost-team farms lose eligibility under logical opponents", () => {
  const attacks = new Map(attackProfiles().map(({ attack, input }) => [attack, input]));
  for (const attack of ["sybil", "ghost_teams", "sacrifice_accounts"] as const) {
    const input = attacks.get(attack)!;
    const open = calculateSeasonScore(input, minimal);
    const protectedResult = calculateSeasonScore(input, protectedConfig);
    assert.equal(open.eligibility.eligible, true, `${attack} should expose the unprotected weakness`);
    assert.equal(protectedResult.eligibility.eligible, false, `${attack} should not manufacture logical diversity`);
    assert.ok(protectedResult.score < open.score, `${attack} should lose score weight`);
  }
});

test("red-team suite covers every specified logical attack family", () => {
  const attacks = evaluateAttacks(minimal, protectedConfig);
  assert.equal(attacks.length, 14);
  assert.ok(attacks.every(({ protectedRisk }) => protectedRisk >= 0 && protectedRisk <= 100));
  assert.ok(attacks.some(({ attack, protectedRisk }) => attack === "impossible_volume" && protectedRisk >= 18));
  assert.ok(attacks.some(({ attack, protectedRisk }) => attack === "simultaneous_matches" && protectedRisk >= 25));
  assert.ok(attacks.some(({ attack, protectedScore, unprotectedScore }) => attack === "rating_boost" && protectedScore < unprotectedScore));
});

test("legitimate shared structures are never auto-labelled suspicious or high-risk", () => {
  const assessments = legitimateRiskProfiles().map(assessRankingIntegrity);
  assert.ok(assessments.every(({ classification }) => classification === "clean" || classification === "watch"));
});

test("risk uses product evidence, not IP, fingerprint or permanent GPS", () => {
  const input = createProfileInput({ challenges: 20, id: "privacy-contract", opponentRating: 82, rating: 84, technicalOpponents: 8, winRate: 0.6 });
  const assessment = assessRankingIntegrity(input);
  assert.deepEqual(Object.keys(assessment.signals).sort(), [
    "abnormalMatchFrequency",
    "accountAgeCluster",
    "closedNetworkRatio",
    "impossibleTravelRatio",
    "opponentIdentityGap",
    "participationAnomaly",
    "ratingVsExternalEvidence",
    "repeatedOpponentRatio",
    "venueAnomaly",
  ]);
});

test("risk remains diagnostic and never modifies source evidence", () => {
  const input = attackProfiles().find(({ attack }) => attack === "collusion")!.input;
  const before = structuredClone(input);
  calculateSeasonScore(input, protectedConfig);
  assert.deepEqual(input, before);
});
