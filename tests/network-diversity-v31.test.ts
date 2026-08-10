import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import {
  aggregateModelMetrics,
  contextualizeNetworkCandidates,
  decideNetworkModel,
  ecosystemModelRun,
  evaluateNetworkModel,
  growthStabilityExperiment,
  redTeamNetworkModels,
  territoryGrowthExperiment,
  territorialTopRows,
} from "../simulation/season-ranking-lab/src/network-diversity-v31";
import { v3Baseline } from "../simulation/season-ranking-lab/src/v3-validation";
import type { SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";
import { KNOWN_SYNTHETIC_INCIDENTS } from "../simulation/synthetic-world/src/known-incidents";
import { networkCandidateStatus } from "../simulation/synthetic-world/src/network-health-v31";

const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
const config = v3Baseline(previous);
const researchReference = "model_3_relative_floor" as const;

test("network diversity decomposition reconstructs the exact V3 aggregate", () => {
  const run = ecosystemModelRun({ config, scenario: "healthy", seed: 20263101, teamCount: 50 });
  for (const row of run.candidates) {
    const network = row.network;
    const reconstructed = (network.structuralDiversity * 0.72 + network.externalExposure * 0.28)
      * (1 - network.outcomeAnomaly * (1 - network.externalExposure) * 0.35);
    assert.ok(Math.abs(network.competitionNetworkDiversity - reconstructed) <= 0.0002, row.id);
    assert.ok(network.availableCompetitiveOpportunity >= network.logicalOpponentCount);
    assert.ok(network.opponentEntropy >= 0 && network.opponentEntropy <= 1);
  }
});

test("a healthy connected 50-team ecosystem keeps legitimate trophy candidates reachable", () => {
  const run = ecosystemModelRun({ config, scenario: "healthy", seed: 20263102, teamCount: 50 });
  const metrics = run.metrics.find(({ modelId }) => modelId === researchReference)!;
  assert.ok(metrics.certifiable >= 10);
  assert.ok(metrics.falsePositiveRate <= 0.02);
  assert.equal(metrics.certifiedTop10Contamination, 0);
});

test("a legitimate ten-team club with external matches is not treated as a fake farm", () => {
  const run = ecosystemModelRun({ config, scenario: "legitimate_club", seed: 20263103, teamCount: 50 });
  const metrics = run.metrics.find(({ modelId }) => modelId === researchReference)!;
  assert.ok(metrics.legitimateCertificationRate >= 0.98);
  assert.ok(metrics.certifiable >= 10);
});

test("the manipulated 50-team network keeps executed trophy-capable abuse out of certified Top10", () => {
  const run = ecosystemModelRun({ config, scenario: "manipulated", seed: 20263104, teamCount: 50 });
  const metrics = run.metrics.find(({ modelId }) => modelId === researchReference)!;
  assert.equal(metrics.certifiedTop10Contamination, 0);
  assert.equal(metrics.falseNegative, 0);
  assert.ok(metrics.truePositive > 0);
});

test("thirty seeds keep research-reference false positives and certified contamination within target", () => {
  const rows = Array.from({ length: 30 }, (_, index) => 20263200 + index).flatMap((seed) => [
    ecosystemModelRun({ config, scenario: "healthy", seed, teamCount: 50 }),
    ecosystemModelRun({ config, scenario: "manipulated", seed, teamCount: 50 }),
  ]);
  const healthy = aggregateModelMetrics(rows.filter(({ scenario }) => scenario === "healthy").flatMap(({ metrics }) => metrics));
  const manipulated = aggregateModelMetrics(rows.filter(({ scenario }) => scenario === "manipulated").flatMap(({ metrics }) => metrics));
  assert.ok(healthy[researchReference].falsePositiveRate <= 0.02);
  assert.ok(manipulated[researchReference].certifiedTop10Contamination <= 0.05);
  assert.ok(manipulated[researchReference].recall >= 0.9);
});

test("unrelated future teams cannot change a core player's contextual certification", () => {
  const result = growthStabilityExperiment(config, 20263105);
  assert.equal(result.certificationStable, true);
  assert.equal(decideNetworkModel(result.before, researchReference).certified, decideNetworkModel(result.after, researchReference).certified);
  assert.equal(result.before.network.availableCompetitiveOpportunity, result.after.network.availableCompetitiveOpportunity);
});

test("red-team attacks that pass non-network trophy gates are held by the research reference", () => {
  const rows = redTeamNetworkModels(config);
  assert.ok(rows.length >= 13);
  for (const row of rows.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible)) {
    assert.equal(row.decisions[researchReference].hold, true, row.attack);
  }
});

test("Top10 contamination uses every territorial Top10 rather than one global slice", () => {
  const [base] = ecosystemModelRun({ config, scenario: "healthy", seed: 20263106, teamCount: 20 }).candidates;
  const madrid = Array.from({ length: 10 }, (_, index) => ({ ...base!, id: `madrid-${index}`, provinceCode: "28", score: 200 - index }));
  const barcelona = [
    ...Array.from({ length: 9 }, (_, index) => ({ ...base!, id: `barcelona-${index}`, provinceCode: "08", score: 110 - index })),
    { ...base!, executedAbuse: true, id: "barcelona-abuse", provinceCode: "08", score: 101 },
  ];
  const rows = [...madrid, ...barcelona];
  assert.equal(territorialTopRows(rows).length, 20);
  assert.equal(evaluateNetworkModel(rows, "model_0_v3").top10Contamination, 0.05);
});

test("territorial contamination is explicit across Top10, Top20 and Top50", () => {
  const [base] = ecosystemModelRun({ config, scenario: "healthy", seed: 20263108, teamCount: 20 }).candidates;
  const cleanBase = {
    ...base!,
    network: { ...base!.network, competitionNetworkDiversity: 1 },
    nonNetworkTrophyEligible: true,
    rankingEligible: true,
    sourceRisk: { ...base!.sourceRisk, classification: "clean" as const, risk: 0 },
  };
  const madrid = Array.from({ length: 50 }, (_, index) => ({ ...cleanBase, id: `madrid-surface-${index}`, provinceCode: "28", score: 300 - index }));
  const barcelona = Array.from({ length: 50 }, (_, index) => ({
    ...cleanBase,
    executedAbuse: index === 9 || index === 19 || index === 49,
    id: `barcelona-surface-${index}`,
    provinceCode: "08",
    score: 200 - index,
  }));
  const metrics = evaluateNetworkModel([...madrid, ...barcelona], "model_1_absolute", 0.4);
  assert.equal(metrics.top10Contamination, 0.05);
  assert.equal(metrics.certifiedTop10Contamination, 0.05);
  assert.equal(metrics.top20Contamination, 0.05);
  assert.equal(metrics.certifiedTop20Contamination, 0.05);
  assert.equal(metrics.top50Contamination, 0.03);
  assert.equal(metrics.certifiedTop50Contamination, 0.03);
});

test("one territory grows through nested stages without replacing existing teams", () => {
  const stages = territoryGrowthExperiment(config, 20263109);
  assert.deepEqual(stages.map(({ teamCount }) => teamCount), [10, 20, 35, 50, 80, 150]);
  for (let index = 1; index < stages.length; index += 1) {
    assert.deepEqual(stages[index]!.activeTeamIds.slice(0, stages[index - 1]!.activeTeamIds.length), stages[index - 1]!.activeTeamIds);
    assert.equal(stages[index]!.core.id, stages[0]!.core.id);
    assert.ok(stages[index]!.core.network.availableCompetitiveOpportunity <= stages[index]!.teamCount - 1);
  }
  assert.equal(stages[0]!.nonNetworkCandidates, 0);
  assert.ok(stages.slice(1).every(({ nonNetworkCandidates }) => nonNetworkCandidates >= 10));
});

test("candidate evidence carries real team IDs and server-calculated match confidence", () => {
  const run = ecosystemModelRun({ config, scenario: "healthy", seed: 20263110, teamCount: 50 });
  for (const row of run.candidates) {
    assert.equal(row.teamIds.length, 1);
    assert.match(row.teamIds[0]!, /^eco-50-team-/);
    assert.ok(row.matchConfidence > 0 && row.matchConfidence <= 1);
  }
});

test("the root report distinguishes the preserved V1 checkpoint from current V3.1 totals", () => {
  const report = readFileSync(new URL("../SYNTHETIC_WORLD_V1_REPORT.md", import.meta.url), "utf8");
  assert.match(report, /Estado del cierre V1 previo a V1\.1\/V3\.1/);
  assert.match(report, /7 pruebas HTML \+ 163 pruebas TypeScript/);
  assert.doesNotMatch(report, /Estado final: 50 incidencias/);
});

test("low-confidence evidence remains a separate non-network gate", () => {
  const [base] = ecosystemModelRun({ config, scenario: "healthy", seed: 20263107, teamCount: 20 }).candidates;
  const [row] = contextualizeNetworkCandidates([{
    ...base!,
    lowConfidenceEvidenceRatio: 1,
    nonNetworkTrophyEligible: false,
    sourceRisk: { ...base!.sourceRisk, classification: "clean", risk: 0 },
  }]);
  assert.equal(row!.absoluteAbuseRisk, 0);
  assert.equal(decideNetworkModel(row!, researchReference).certified, false);
  assert.equal(networkCandidateStatus(row!, researchReference), "NO CANDIDATO");
});

test("all V3.1 findings remain permanently recorded for regression closure", () => {
  for (const id of ["SW-0068", "SW-0069", "SW-0070", "SW-0071", "SW-0072", "SW-0073", "SW-0074", "SW-0075"]) {
    const incident = KNOWN_SYNTHETIC_INCIDENTS.find((item) => item.id === id);
    assert.ok(incident, id);
    assert.equal(incident.fixed, true, id);
    assert.equal(incident.regressionVerified, true, id);
  }
});
