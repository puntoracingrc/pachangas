import { isSeasonScoreEvidence } from "./engine";
import { pearson, spearman } from "./metrics";
import { round } from "./random";
import { AUTONOMOUS_COMMUNITIES, TERRITORY_BY_PROVINCE } from "./territories";
import type { RankedPlayer, SeasonPlayerInput } from "./types";

export type GroundTruthKind = "capacity" | "future" | "season_merit";
export type EliteScope = "autonomous_community" | "national" | "province";

export type EliteRankingMetrics = {
  candidateRecallAt20: number;
  density: "dense" | "medium" | "national" | "small";
  eligiblePlayers: number;
  meanRankErrorTop10: number;
  medianRankErrorTop10: number;
  ndcgAt10: number;
  ndcgAt20: number;
  overlapAt10: number;
  precisionAt10: number;
  recallAt10: number;
  scopeCode: string;
  scopeName: string;
  scopeType: EliteScope;
  top10NearMissRate: number;
  truth: GroundTruthKind;
};

export type NationalTopMetrics = {
  candidateRecallAtDoubleK: number;
  k: number;
  ndcg: number;
  overlap: number;
  precision: number;
  truth: GroundTruthKind;
};

export type PredictiveTopMetrics = {
  eligiblePlayers: number;
  futureCompetitiveIndex: number;
  futureCompetitiveIndexUplift: number;
  futureOpposition: number;
  futureOppositionUplift: number;
  futurePerformance: number;
  futurePerformanceUplift: number;
  k: number;
};

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

export function percentile(values: number[], percentileValue: number) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.floor((sorted.length - 1) * percentileValue)));
  return sorted[index]!;
}

function performanceAgainstExpectation(input: SeasonPlayerInput, records = input.records.filter(isSeasonScoreEvidence)) {
  if (records.length === 0) return 50;
  return records.reduce((sum, record) => sum + record.individualPerformanceIndex, 0) / records.length;
}

function oppositionStrength(input: SeasonPlayerInput, records = input.records.filter(isSeasonScoreEvidence)) {
  if (records.length === 0) return 50;
  return records.reduce((sum, record) => sum + record.opponentRating, 0) / records.length;
}

export function groundTruthValue(input: SeasonPlayerInput, truth: GroundTruthKind, splitWeek = 34) {
  if (truth === "capacity") return input.player.latentSkill;
  if (truth === "season_merit") {
    return input.player.latentSkill * 0.45
      + performanceAgainstExpectation(input) * 0.35
      + oppositionStrength(input) * 0.2;
  }
  const futureRecords = input.records.filter(isSeasonScoreEvidence).filter(({ week }) => week > splitWeek);
  if (futureRecords.length < 3) return null;
  return performanceAgainstExpectation(input, futureRecords) * 0.75
    + oppositionStrength(input, futureRecords) * 0.25;
}

export function splitInputsForOutOfSample(inputs: SeasonPlayerInput[], splitWeek = 34) {
  return inputs.map((input) => ({
    ...input,
    records: input.records.filter(({ week }) => week <= splitWeek),
  }));
}

function truthMap(inputs: SeasonPlayerInput[], truth: GroundTruthKind, splitWeek: number) {
  return new Map(inputs.map((input) => [input.player.id, groundTruthValue(input, truth, splitWeek)]));
}

function dcg(predictedIds: string[], trueRank: Map<string, number>, k: number) {
  return predictedIds.slice(0, k).reduce((sum, playerId, index) => {
    const rank = trueRank.get(playerId) ?? Number.POSITIVE_INFINITY;
    const relevance = Math.max(0, k * 2 - rank + 1);
    return sum + relevance / Math.log2(index + 2);
  }, 0);
}

export function ndcgAtK(predictedIds: string[], referenceIds: string[], k: number) {
  const trueRank = new Map(referenceIds.map((playerId, index) => [playerId, index + 1]));
  const ideal = dcg(referenceIds, trueRank, k);
  return ideal === 0 ? 0 : dcg(predictedIds, trueRank, k) / ideal;
}

export function evaluateOrderedGroup(
  predictedIds: string[],
  referenceIds: string[],
  metadata: Omit<EliteRankingMetrics, "candidateRecallAt20" | "meanRankErrorTop10" | "medianRankErrorTop10" | "ndcgAt10" | "ndcgAt20" | "overlapAt10" | "precisionAt10" | "recallAt10" | "top10NearMissRate">,
): EliteRankingMetrics {
  const predictedTop10 = new Set(predictedIds.slice(0, 10));
  const predictedTop20 = new Set(predictedIds.slice(0, 20));
  const referenceTop10 = referenceIds.slice(0, 10);
  const overlap = referenceTop10.filter((playerId) => predictedTop10.has(playerId)).length;
  const predictedRanks = new Map(predictedIds.map((playerId, index) => [playerId, index + 1]));
  const rankErrors = referenceTop10.map((playerId, index) => Math.abs((predictedRanks.get(playerId) ?? predictedIds.length + 1) - (index + 1)));
  const missed = referenceTop10.filter((playerId) => !predictedTop10.has(playerId));
  const nearMisses = missed.filter((playerId) => {
    const rank = predictedRanks.get(playerId) ?? Number.POSITIVE_INFINITY;
    return rank >= 11 && rank <= 15;
  }).length;
  return {
    ...metadata,
    candidateRecallAt20: round(referenceTop10.filter((playerId) => predictedTop20.has(playerId)).length / Math.max(1, referenceTop10.length), 4),
    meanRankErrorTop10: round(average(rankErrors), 4),
    medianRankErrorTop10: round(percentile(rankErrors, 0.5), 4),
    ndcgAt10: round(ndcgAtK(predictedIds, referenceIds, 10), 4),
    ndcgAt20: round(ndcgAtK(predictedIds, referenceIds, 20), 4),
    overlapAt10: overlap,
    precisionAt10: round(overlap / Math.max(1, Math.min(10, predictedIds.length)), 4),
    recallAt10: round(overlap / Math.max(1, referenceTop10.length), 4),
    top10NearMissRate: round(nearMisses / Math.max(1, missed.length), 4),
  };
}

function groupRankings(results: RankedPlayer[], scope: EliteScope) {
  const groups = new Map<string, RankedPlayer[]>();
  for (const result of results.filter(({ eligibility }) => eligibility.eligible)) {
    let code: string | null = null;
    if (scope === "national") code = "ES";
    if (scope === "province") code = result.competitiveProvinceCode;
    if (scope === "autonomous_community" && result.competitiveProvinceCode) {
      code = TERRITORY_BY_PROVINCE.get(result.competitiveProvinceCode)?.autonomousCommunityCode ?? null;
    }
    if (!code) continue;
    const group = groups.get(code) ?? [];
    group.push(result);
    groups.set(code, group);
  }
  return groups;
}

function scopeMetadata(scope: EliteScope, code: string) {
  if (scope === "national") return { density: "national" as const, name: "España" };
  if (scope === "province") {
    const territory = TERRITORY_BY_PROVINCE.get(code);
    return { density: territory?.density ?? "small", name: territory?.provinceName ?? code };
  }
  const community = AUTONOMOUS_COMMUNITIES.find((item) => item.code === code);
  return { density: "medium" as const, name: community?.name ?? code };
}

export function evaluateEliteByScope(options: {
  inputs: SeasonPlayerInput[];
  minimumEligible?: number;
  results: RankedPlayer[];
  scope: EliteScope;
  splitWeek?: number;
  truth: GroundTruthKind;
}) {
  const minimumEligible = options.minimumEligible ?? 20;
  const splitWeek = options.splitWeek ?? 34;
  const values = truthMap(options.inputs, options.truth, splitWeek);
  const groups = groupRankings(options.results, options.scope);
  const rows: EliteRankingMetrics[] = [];
  for (const [code, group] of groups) {
    const eligibleWithTruth = group.filter(({ playerId }) => values.get(playerId) !== null && values.get(playerId) !== undefined);
    if (eligibleWithTruth.length < minimumEligible) continue;
    const predictedIds = [...eligibleWithTruth].sort((left, right) => right.rawScore - left.rawScore || left.playerId.localeCompare(right.playerId)).map(({ playerId }) => playerId);
    const referenceIds = [...eligibleWithTruth].sort((left, right) => (values.get(right.playerId) ?? 0) - (values.get(left.playerId) ?? 0) || left.playerId.localeCompare(right.playerId)).map(({ playerId }) => playerId);
    const metadata = scopeMetadata(options.scope, code);
    rows.push(evaluateOrderedGroup(predictedIds, referenceIds, {
      density: metadata.density,
      eligiblePlayers: eligibleWithTruth.length,
      scopeCode: code,
      scopeName: metadata.name,
      scopeType: options.scope,
      truth: options.truth,
    }));
  }
  return rows;
}

export function aggregateEliteMetric(rows: EliteRankingMetrics[], field: keyof Pick<EliteRankingMetrics,
  "candidateRecallAt20" | "meanRankErrorTop10" | "medianRankErrorTop10" | "ndcgAt10" | "ndcgAt20" | "overlapAt10" | "precisionAt10" | "recallAt10" | "top10NearMissRate">) {
  const values = rows.map((row) => Number(row[field]));
  return {
    mean: round(average(values), 4),
    p10: round(percentile(values, 0.1), 4),
    p50: round(percentile(values, 0.5), 4),
    p90: round(percentile(values, 0.9), 4),
  };
}

export function evaluatePredictiveTops(
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
  splitWeek = 34,
): PredictiveTopMetrics[] {
  const inputsById = new Map(inputs.map((input) => [input.player.id, input]));
  const eligible = results.filter(({ eligibility, playerId }) => {
    const input = inputsById.get(playerId);
    return eligibility.eligible && Boolean(input && groundTruthValue(input, "future", splitWeek) !== null);
  }).sort((left, right) => right.rawScore - left.rawScore || left.playerId.localeCompare(right.playerId));
  const observations = eligible.map(({ playerId }) => {
    const input = inputsById.get(playerId)!;
    const futureRecords = input.records.filter(isSeasonScoreEvidence).filter(({ week }) => week > splitWeek);
    return {
      futureCompetitiveIndex: groundTruthValue(input, "future", splitWeek) ?? 0,
      futureOpposition: oppositionStrength(input, futureRecords),
      futurePerformance: performanceAgainstExpectation(input, futureRecords),
    };
  });
  const population = {
    futureCompetitiveIndex: average(observations.map(({ futureCompetitiveIndex }) => futureCompetitiveIndex)),
    futureOpposition: average(observations.map(({ futureOpposition }) => futureOpposition)),
    futurePerformance: average(observations.map(({ futurePerformance }) => futurePerformance)),
  };
  return [10, 25, 50, 100].map((k) => {
    const top = observations.slice(0, k);
    const futureCompetitiveIndex = average(top.map((row) => row.futureCompetitiveIndex));
    const futureOpposition = average(top.map((row) => row.futureOpposition));
    const futurePerformance = average(top.map((row) => row.futurePerformance));
    return {
      eligiblePlayers: eligible.length,
      futureCompetitiveIndex: round(futureCompetitiveIndex, 4),
      futureCompetitiveIndexUplift: round(futureCompetitiveIndex - population.futureCompetitiveIndex, 4),
      futureOpposition: round(futureOpposition, 4),
      futureOppositionUplift: round(futureOpposition - population.futureOpposition, 4),
      futurePerformance: round(futurePerformance, 4),
      futurePerformanceUplift: round(futurePerformance - population.futurePerformance, 4),
      k,
    };
  });
}

export function evaluateNationalTops(
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
  truth: GroundTruthKind,
  splitWeek = 34,
): NationalTopMetrics[] {
  const values = truthMap(inputs, truth, splitWeek);
  const eligible = results.filter(({ eligibility, playerId }) => eligibility.eligible && values.get(playerId) !== null);
  const predictedIds = [...eligible].sort((left, right) => right.rawScore - left.rawScore || left.playerId.localeCompare(right.playerId)).map(({ playerId }) => playerId);
  const referenceIds = [...eligible].sort((left, right) => (values.get(right.playerId) ?? 0) - (values.get(left.playerId) ?? 0)).map(({ playerId }) => playerId);
  return [10, 25, 50, 100].map((k) => {
    const predicted = new Set(predictedIds.slice(0, k));
    const reference = referenceIds.slice(0, k);
    const overlap = reference.filter((id) => predicted.has(id)).length;
    const candidatePool = new Set(predictedIds.slice(0, k * 2));
    return {
      candidateRecallAtDoubleK: round(reference.filter((id) => candidatePool.has(id)).length / Math.max(1, reference.length), 4),
      k,
      ndcg: round(ndcgAtK(predictedIds, referenceIds, k), 4),
      overlap,
      precision: round(overlap / k, 4),
      truth,
    };
  });
}

export function predictiveUplift(inputs: SeasonPlayerInput[], results: RankedPlayer[], topSize: number, splitWeek = 34) {
  const values = truthMap(inputs, "future", splitWeek);
  const eligible = results.filter(({ eligibility, playerId }) => eligibility.eligible && values.get(playerId) !== null);
  if (eligible.length === 0) return { correlation: 0, populationMean: 0, topMean: 0, uplift: 0 };
  const ordered = [...eligible].sort((left, right) => right.rawScore - left.rawScore || left.playerId.localeCompare(right.playerId));
  const topValues = ordered.slice(0, topSize).map(({ playerId }) => values.get(playerId) ?? 0);
  const populationValues = eligible.map(({ playerId }) => values.get(playerId) ?? 0);
  return {
    correlation: round(spearman(eligible.map(({ score }) => score), populationValues), 4),
    populationMean: round(average(populationValues), 4),
    topMean: round(average(topValues), 4),
    uplift: round(average(topValues) - average(populationValues), 4),
  };
}

export function scoreTruthCorrelation(inputs: SeasonPlayerInput[], results: RankedPlayer[], truth: GroundTruthKind) {
  const values = truthMap(inputs, truth, 34);
  const eligible = results.filter(({ eligibility, playerId }) => eligibility.eligible && values.get(playerId) !== null);
  return round(pearson(eligible.map(({ score }) => score), eligible.map(({ playerId }) => values.get(playerId) ?? 0)), 4);
}
