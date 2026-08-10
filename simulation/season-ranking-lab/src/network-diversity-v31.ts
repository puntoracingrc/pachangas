import { isSeasonScoreEvidence } from "./engine";
import {
  TROPHY_RULES,
  buildOpponentGraph,
  enrichCompetitiveEvidence,
  evaluateV3Ranking,
  explainNetworkDiversity,
  type NetworkDiversityBreakdown,
  type OpponentGraph,
  type TeamIntegrityProfile,
  type V3RankedPlayer,
} from "./integrity-v3";
import { DeterministicRandom, clamp, round } from "./random";
import { attackProfiles, createProfileInput } from "./scenarios";
import type { AttackKind, SeasonPlayerInput, SeasonScoreConfig } from "./types";

export const NETWORK_MODEL_IDS = [
  "model_0_v3",
  "model_1_absolute",
  "model_2_relative",
  "model_3_relative_floor",
  "model_4_composite_integrity",
  "model_5_opportunity_adjusted",
] as const;

export type NetworkModelId = typeof NETWORK_MODEL_IDS[number];
export type EcosystemScenario = "healthy" | "legitimate_club" | "manipulated";

export type NetworkCandidateInput = {
  currentCertification: V3RankedPlayer["certification"];
  executedAbuse: boolean;
  id: string;
  lowConfidenceEvidenceRatio: number;
  matchConfidence: number;
  network: NetworkDiversityBreakdown;
  nonNetworkTrophyEligible: boolean;
  provinceCode: string;
  rankingEligible: boolean;
  score: number;
  sourceRisk: V3RankedPlayer["sourceRisk"];
  teamIds: string[];
  validChallenges: number;
};

export type ContextualNetworkCandidate = NetworkCandidateInput & {
  absoluteAbuseRisk: number;
  networkHealth: number;
  opportunityAdjustedDiversity: number;
  relativeNetworkDiversity: number;
};

export type NetworkModelDecision = {
  certified: boolean;
  hold: boolean;
  modelId: NetworkModelId;
  reasons: string[];
};

export type ModelMetrics = {
  certifiedTop10Contamination: number;
  certifiedTop20Contamination: number;
  certifiedTop50Contamination: number;
  certifiable: number;
  falseNegative: number;
  falsePositive: number;
  falsePositiveRate: number;
  legitimateCertificationRate: number;
  modelId: NetworkModelId;
  precision: number;
  recall: number;
  top10Contamination: number;
  top20Contamination: number;
  top50Contamination: number;
  trueNegative: number;
  truePositive: number;
  threshold?: number;
};

export type EcosystemDataset = {
  graph: OpponentGraph;
  inputs: SeasonPlayerInput[];
  metadata: Map<string, { executedAbuse: boolean; role: string }>;
  profiles: TeamIntegrityProfile[];
  scenario: EcosystemScenario;
  seed: number;
  teamCount: number;
};

const ABSOLUTE_THRESHOLDS = [0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.68] as const;

function percentile(values: number[], quantile: number) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const position = (sorted.length - 1) * quantile;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower]!;
  return sorted[lower]! + (sorted[upper]! - sorted[lower]!) * (position - lower);
}

function ratio(numerator: number, denominator: number) {
  return denominator === 0 ? 0 : numerator / denominator;
}

function volumeBand(validChallenges: number) {
  if (validChallenges < 20) return "under_20";
  if (validChallenges < 30) return "20_29";
  if (validChallenges < 40) return "30_39";
  return "40_plus";
}

function relativeDistribution(cohort: number[]) {
  if (cohort.length < 4) return { median: 0, neutral: true, spread: 1 };
  return {
    median: percentile(cohort, 0.5),
    neutral: false,
    spread: Math.max(0.12, percentile(cohort, 0.75) - percentile(cohort, 0.25)),
  };
}

function relativeScore(value: number, distribution: ReturnType<typeof relativeDistribution>) {
  if (distribution.neutral) return 0.5;
  return clamp(0.5 + (value - distribution.median) / distribution.spread * 0.25, 0, 1);
}

function absoluteAbuseRisk(input: NetworkCandidateInput) {
  let risk = input.sourceRisk.risk / 100;
  if (input.network.pairIndependence < 0.5) risk = Math.max(risk, 0.76);
  if (input.network.opponentClusterDiversity < 0.65) risk = Math.max(risk, 0.82);
  if (input.network.opponentConcentration > 0.55 && input.network.closedNetworkRatio > 0.8) risk = Math.max(risk, 0.68);
  if (input.network.externalExposure < 0.1 && input.network.outcomeAnomaly > 0.25) risk = Math.max(risk, 0.72);
  return round(clamp(risk, 0, 1), 4);
}

function networkHealth(input: NetworkCandidateInput) {
  const value = input.network.pairIndependence * 0.22
    + input.network.opponentClusterDiversity * 0.12
    + input.network.opponentEntropy * 0.18
    + input.network.externalExposure * 0.1
    + input.network.ecosystemOpportunity * 0.2
    + (1 - input.network.opponentConcentration) * 0.18;
  return round(clamp(value, 0, 1), 4);
}

function opportunityAdjustedDiversity(input: NetworkCandidateInput) {
  const value = input.network.pairIndependence * 0.3
    + input.network.opponentClusterDiversity * 0.15
    + input.network.opponentEntropy * 0.2
    + input.network.ecosystemOpportunity * 0.25
    + input.network.externalExposure * 0.1;
  return round(clamp(value, 0, 1), 4);
}

export function contextualizeNetworkCandidates(rows: NetworkCandidateInput[]) {
  const prepared = rows.map((row) => ({ adjusted: opportunityAdjustedDiversity(row), row }));
  const byProvince = new Map<string, number[]>();
  const byComparableVolume = new Map<string, number[]>();
  for (const item of prepared) {
    const province = byProvince.get(item.row.provinceCode) ?? [];
    province.push(item.adjusted);
    byProvince.set(item.row.provinceCode, province);
    const key = `${item.row.provinceCode}:${volumeBand(item.row.validChallenges)}`;
    const comparable = byComparableVolume.get(key) ?? [];
    comparable.push(item.adjusted);
    byComparableVolume.set(key, comparable);
  }
  const provinceDistributions = new Map([...byProvince].map(([key, values]) => [key, relativeDistribution(values)]));
  const volumeDistributions = new Map([...byComparableVolume].map(([key, values]) => [key, relativeDistribution(values)]));
  return prepared.map(({ adjusted, row }): ContextualNetworkCandidate => {
    const key = `${row.provinceCode}:${volumeBand(row.validChallenges)}`;
    const comparable = byComparableVolume.get(key) ?? [];
    const distribution = comparable.length >= 8 ? volumeDistributions.get(key)! : provinceDistributions.get(row.provinceCode)!;
    return {
      ...row,
      absoluteAbuseRisk: absoluteAbuseRisk(row),
      networkHealth: networkHealth(row),
      opportunityAdjustedDiversity: adjusted,
      relativeNetworkDiversity: round(relativeScore(adjusted, distribution), 4),
    };
  });
}

export function decideNetworkModel(
  row: ContextualNetworkCandidate,
  modelId: NetworkModelId,
  absoluteThreshold = 0.68,
): NetworkModelDecision {
  const reasons: string[] = [];
  if (modelId === "model_0_v3" || modelId === "model_1_absolute") {
    if (row.network.competitionNetworkDiversity < absoluteThreshold) reasons.push("absolute_network_diversity");
    if (row.sourceRisk.classification === "suspicious" || row.sourceRisk.classification === "high_risk") reasons.push("absolute_abuse_signal");
    if (row.lowConfidenceEvidenceRatio > 0.2) reasons.push("low_confidence_dependency");
  }
  if (modelId === "model_2_relative") {
    if (row.relativeNetworkDiversity < 0.38) reasons.push("relative_network_diversity");
    if (row.absoluteAbuseRisk >= 0.5) reasons.push("absolute_abuse_signal");
  }
  if (modelId === "model_3_relative_floor") {
    if (row.relativeNetworkDiversity < 0.38) reasons.push("relative_network_diversity");
    if (row.network.competitionNetworkDiversity < 0.35) reasons.push("absolute_diversity_floor");
    if (row.absoluteAbuseRisk >= 0.5) reasons.push("absolute_abuse_signal");
  }
  if (modelId === "model_4_composite_integrity") {
    if (row.networkHealth < 0.52) reasons.push("low_network_health");
    if (row.absoluteAbuseRisk >= 0.5) reasons.push("absolute_abuse_signal");
  }
  if (modelId === "model_5_opportunity_adjusted") {
    if (row.opportunityAdjustedDiversity < 0.62) reasons.push("opportunity_adjusted_diversity");
    if (row.relativeNetworkDiversity < 0.35) reasons.push("relative_network_diversity");
    if (row.absoluteAbuseRisk >= 0.5) reasons.push("absolute_abuse_signal");
  }
  const hold = reasons.length > 0;
  return { certified: row.nonNetworkTrophyEligible && !hold, hold, modelId, reasons };
}

export function evaluateNetworkModel(
  rows: ContextualNetworkCandidate[],
  modelId: NetworkModelId,
  absoluteThreshold = 0.68,
): ModelMetrics {
  const decisions = new Map(rows.map((row) => [row.id, decideNetworkModel(row, modelId, absoluteThreshold)]));
  const candidates = rows.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible);
  const truePositive = candidates.filter((row) => row.executedAbuse && decisions.get(row.id)!.hold).length;
  const falseNegative = candidates.filter((row) => row.executedAbuse && !decisions.get(row.id)!.hold).length;
  const falsePositive = candidates.filter((row) => !row.executedAbuse && decisions.get(row.id)!.hold).length;
  const trueNegative = candidates.filter((row) => !row.executedAbuse && !decisions.get(row.id)!.hold).length;
  const top10 = territorialTopRows(rows.filter(({ rankingEligible }) => rankingEligible));
  const top20 = territorialTopRows(rows.filter(({ rankingEligible }) => rankingEligible), 20);
  const top50 = territorialTopRows(rows.filter(({ rankingEligible }) => rankingEligible), 50);
  const certifiedTop10 = territorialTopRows(rows.filter((row) => decisions.get(row.id)!.certified));
  const certifiedTop20 = territorialTopRows(rows.filter((row) => decisions.get(row.id)!.certified), 20);
  const certifiedTop50 = territorialTopRows(rows.filter((row) => decisions.get(row.id)!.certified), 50);
  return {
    certifiedTop10Contamination: round(ratio(certifiedTop10.filter(({ executedAbuse }) => executedAbuse).length, certifiedTop10.length), 4),
    certifiedTop20Contamination: round(ratio(certifiedTop20.filter(({ executedAbuse }) => executedAbuse).length, certifiedTop20.length), 4),
    certifiedTop50Contamination: round(ratio(certifiedTop50.filter(({ executedAbuse }) => executedAbuse).length, certifiedTop50.length), 4),
    certifiable: candidates.filter((row) => decisions.get(row.id)!.certified).length,
    falseNegative,
    falsePositive,
    falsePositiveRate: round(ratio(falsePositive, falsePositive + trueNegative), 4),
    legitimateCertificationRate: round(ratio(trueNegative, trueNegative + falsePositive), 4),
    modelId,
    precision: round(ratio(truePositive, truePositive + falsePositive), 4),
    recall: round(ratio(truePositive, truePositive + falseNegative), 4),
    top10Contamination: round(ratio(top10.filter(({ executedAbuse }) => executedAbuse).length, top10.length), 4),
    top20Contamination: round(ratio(top20.filter(({ executedAbuse }) => executedAbuse).length, top20.length), 4),
    top50Contamination: round(ratio(top50.filter(({ executedAbuse }) => executedAbuse).length, top50.length), 4),
    trueNegative,
    truePositive,
  };
}

export function territorialTopRows<T extends Pick<ContextualNetworkCandidate, "id" | "provinceCode" | "score">>(rows: T[], limit = 10) {
  const byProvince = new Map<string, T[]>();
  for (const row of rows) byProvince.set(row.provinceCode, [...(byProvince.get(row.provinceCode) ?? []), row]);
  return [...byProvince.values()].flatMap((territory) => territory
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, limit));
}

export function compareNetworkModels(rows: ContextualNetworkCandidate[]) {
  return [
    evaluateNetworkModel(rows, "model_0_v3", 0.68),
    ...ABSOLUTE_THRESHOLDS.map((threshold) => ({ threshold, ...evaluateNetworkModel(rows, "model_1_absolute", threshold) })),
    ...NETWORK_MODEL_IDS.slice(2).map((modelId) => evaluateNetworkModel(rows, modelId)),
  ];
}

function connect(adjacency: Map<string, Set<string>>, left: string, right: string) {
  if (left === right) return;
  adjacency.get(left)!.add(right);
  adjacency.get(right)!.add(left);
}

function ringConnections(ids: string[], adjacency: Map<string, Set<string>>, degree: number) {
  const radius = Math.ceil(Math.min(degree, Math.max(0, ids.length - 1)) / 2);
  for (let index = 0; index < ids.length; index += 1) {
    for (let offset = 1; offset <= radius; offset += 1) connect(adjacency, ids[index]!, ids[(index + offset) % ids.length]!);
  }
}

function teamProfile(id: string, index: number, fake = false): TeamIntegrityProfile {
  const shared = Array.from({ length: 8 }, (_, playerIndex) => `fake-shared-player-${playerIndex}`);
  return {
    adminIds: [fake ? "fake-shared-admin" : `admin-${id}`],
    createdDaysAgo: fake ? 7 : 365 + index * 11,
    id,
    ownerId: fake ? "fake-shared-owner" : `owner-${id}`,
    playerIds: fake ? [...shared, `${id}-unique-1`, `${id}-unique-2`] : Array.from({ length: 10 }, (_, playerIndex) => `${id}-player-${playerIndex}`),
    provinceCode: "08",
    sportsClusterId: fake ? "fake-farm" : `club-${Math.floor(index / 10)}`,
    venueClusterId: `venue-${index % 8}`,
  };
}

function playerInput(options: {
  abusive?: boolean;
  id: string;
  neighbors: string[];
  random: DeterministicRandom;
  teamId: string;
}) {
  const challenges = 30;
  const input = createProfileInput({
    accountAgeDays: options.abusive ? 5 : 700,
    challenges,
    id: options.id,
    opponentRating: options.abusive ? 94 : 82,
    rating: options.abusive ? 96 : clamp(options.random.normal(84, 5), 68, 94),
    technicalOpponents: Math.max(1, options.neighbors.length),
    winRate: options.abusive ? 0.95 : clamp(options.random.normal(0.57, 0.08), 0.38, 0.76),
  });
  input.player.teamIds = [options.teamId];
  input.records = input.records.map((record, index) => ({
    ...record,
    challengeId: `${options.id}-match-${index}`,
    opponentClusterId: options.neighbors[index % options.neighbors.length]!,
    opponentTeamId: options.neighbors[index % options.neighbors.length]!,
    teamId: options.teamId,
  }));
  return input;
}

export function createNetworkEcosystem(options: {
  scenario: EcosystemScenario;
  seed: number;
  teamCount: number;
}): EcosystemDataset {
  const random = new DeterministicRandom(options.seed);
  const ids = Array.from({ length: options.teamCount }, (_, index) => `eco-${options.teamCount}-team-${index}`);
  const adjacency = new Map(ids.map((id) => [id, new Set<string>()]));
  const manipulatedNodes = options.scenario === "manipulated" ? Math.min(15, Math.max(4, Math.floor(options.teamCount * 0.3))) : 0;
  const farmNodes = options.scenario === "manipulated" ? Math.min(5, Math.max(2, Math.floor(manipulatedNodes / 3))) : 0;
  const normalIds = ids.slice(0, ids.length - manipulatedNodes);
  const ringIds = ids.slice(normalIds.length, ids.length - farmNodes);
  const fakeIds = ids.slice(ids.length - farmNodes);
  const healthyIds = options.scenario === "manipulated" ? normalIds : ids;
  ringConnections(healthyIds, adjacency, Math.min(14, healthyIds.length - 1));
  for (const id of healthyIds) {
    if (healthyIds.length > 4 && random.bool(0.35)) connect(adjacency, id, random.pick(healthyIds));
  }
  if (options.scenario === "legitimate_club" && ids.length >= 12) {
    const clubIds = ids.slice(0, 10);
    ringConnections(clubIds, adjacency, 8);
    clubIds.forEach((id, index) => connect(adjacency, id, ids[10 + index % Math.max(1, ids.length - 10)]!));
  }
  if (options.scenario === "manipulated") {
    ringConnections(ringIds, adjacency, Math.min(9, ringIds.length - 1));
    fakeIds.forEach((id) => ringIds.forEach((ringId) => connect(adjacency, id, ringId)));
    ringConnections(fakeIds, adjacency, fakeIds.length - 1);
    if (normalIds.length > 0 && ringIds.length > 0) connect(adjacency, normalIds.at(-1)!, ringIds[0]!);
  }
  const profiles = ids.map((id, index) => teamProfile(id, index, fakeIds.includes(id)));
  const metadata = new Map<string, { executedAbuse: boolean; role: string }>();
  const candidateTeams = options.scenario === "manipulated" ? normalIds : ids;
  const inputs = candidateTeams.map((teamId, index) => {
    const id = `${teamId}-candidate`;
    metadata.set(id, { executedAbuse: false, role: options.scenario === "legitimate_club" && index < 10 ? "legitimate_club" : "legitimate" });
    return playerInput({ id, neighbors: [...adjacency.get(teamId)!], random, teamId });
  });
  if (options.scenario === "manipulated" && ringIds.length > 0) {
    const attackCount = Math.max(1, Math.round(inputs.length * 0.05));
    for (let index = 0; index < attackCount; index += 1) {
      const teamId = ringIds[index % ringIds.length]!;
      const pool = index % 2 === 0 ? [...ringIds.filter((id) => id !== teamId), ...fakeIds] : [...fakeIds, ...ringIds.filter((id) => id !== teamId)];
      const opponents = pool.slice(0, Math.min(10, pool.length));
      const id = `executed-abuse-${options.teamCount}-${index}`;
      metadata.set(id, { executedAbuse: true, role: index % 2 === 0 ? "collusion_ring" : "fake_farm" });
      inputs.push(playerInput({ abusive: true, id, neighbors: opponents.length > 0 ? opponents : [teamId], random, teamId }));
    }
  }
  const graph = buildOpponentGraph(profiles, inputs);
  return { graph, inputs, metadata, profiles, scenario: options.scenario, seed: options.seed, teamCount: options.teamCount };
}

export function candidatesFromDataset(dataset: EcosystemDataset, config: SeasonScoreConfig) {
  const evaluated = evaluateV3Ranking({
    config,
    graph: dataset.graph,
    inputs: dataset.inputs,
    strategy: "exclusion_and_hold",
    trophyRule: TROPHY_RULES.province,
  });
  const inputById = new Map(dataset.inputs.map((input) => [input.player.id, input]));
  return contextualizeNetworkCandidates(evaluated.map((result): NetworkCandidateInput => {
    const input = inputById.get(result.playerId)!;
    const enriched = enrichCompetitiveEvidence(input, dataset.graph).filter(({ record }) => isSeasonScoreEvidence(record));
    const nonNetworkReasons = result.certificationReasons.filter((reason) => ![
      "insufficient_network_diversity",
      "integrity_anomaly",
    ].includes(reason));
    return {
      currentCertification: result.certification,
      executedAbuse: dataset.metadata.get(result.playerId)?.executedAbuse ?? false,
      id: result.playerId,
      lowConfidenceEvidenceRatio: result.lowConfidenceEvidenceRatio,
      matchConfidence: result.competitiveConfidence,
      network: explainNetworkDiversity(enriched, dataset.graph),
      nonNetworkTrophyEligible: nonNetworkReasons.length === 0,
      provinceCode: result.competitiveProvinceCode ?? "08",
      rankingEligible: result.eligibility.eligible,
      score: result.score,
      sourceRisk: result.sourceRisk,
      teamIds: [...input.player.teamIds],
      validChallenges: result.validChallenges,
    };
  }));
}

export function ecosystemModelRun(options: {
  config: SeasonScoreConfig;
  scenario: EcosystemScenario;
  seed: number;
  teamCount: number;
}) {
  const dataset = createNetworkEcosystem(options);
  const candidates = candidatesFromDataset(dataset, options.config);
  return {
    candidates,
    metrics: compareNetworkModels(candidates),
    scenario: options.scenario,
    seed: options.seed,
    teamCount: options.teamCount,
  };
}

export function growthStabilityExperiment(config: SeasonScoreConfig, seed: number) {
  const core = createNetworkEcosystem({ scenario: "healthy", seed, teamCount: 50 });
  const coreRows = candidatesFromDataset(core, config);
  const target = coreRows[0]!;
  const expandedProfiles = [...core.profiles, ...Array.from({ length: 100 }, (_, index) => teamProfile(`unrelated-${index}`, 100 + index))];
  const expandedGraph = buildOpponentGraph(expandedProfiles, core.inputs);
  const expanded = candidatesFromDataset({ ...core, graph: expandedGraph, profiles: expandedProfiles, teamCount: 150 }, config).find(({ id }) => id === target.id)!;
  return {
    after: expanded,
    before: target,
    certificationStable: NETWORK_MODEL_IDS.slice(2).every((modelId) => (
      decideNetworkModel(target, modelId).certified === decideNetworkModel(expanded, modelId).certified
    )),
    unrelatedTeamsAdded: 100,
  };
}

export const TERRITORY_GROWTH_STAGES = [10, 20, 35, 50, 80, 150] as const;

export function territoryGrowthExperiment(config: SeasonScoreConfig, seed: number) {
  const ids = Array.from({ length: TERRITORY_GROWTH_STAGES.at(-1)! }, (_, index) => `growth-team-${index}`);
  const adjacency = new Map(ids.map((id) => [id, new Set<string>()]));
  const random = new DeterministicRandom(seed);
  let previousTeamCount = 0;

  return TERRITORY_GROWTH_STAGES.map((teamCount) => {
    for (let index = previousTeamCount; index < teamCount; index += 1) {
      const teamId = ids[index]!;
      const available = ids.slice(0, index);
      const connectionCount = Math.min(14, available.length);
      const selected = new Set<string>();
      while (selected.size < connectionCount) selected.add(random.pick(available));
      for (const opponentId of selected) connect(adjacency, teamId, opponentId);
    }
    previousTeamCount = teamCount;

    const activeTeamIds = ids.slice(0, teamCount);
    const activeTeamIdSet = new Set(activeTeamIds);
    const profiles = activeTeamIds.map((id, index) => teamProfile(id, index));
    const metadata = new Map<string, { executedAbuse: boolean; role: string }>();
    const inputs = activeTeamIds.map((teamId, index) => {
      const id = `${teamId}-candidate`;
      metadata.set(id, { executedAbuse: false, role: "legitimate_growth" });
      return playerInput({
        id,
        neighbors: [...adjacency.get(teamId)!].filter((opponentId) => activeTeamIdSet.has(opponentId)),
        random: new DeterministicRandom(seed + index * 7_919),
        teamId,
      });
    });
    const dataset: EcosystemDataset = {
      graph: buildOpponentGraph(profiles, inputs),
      inputs,
      metadata,
      profiles,
      scenario: "healthy",
      seed,
      teamCount,
    };
    const candidates = candidatesFromDataset(dataset, config);
    const core = candidates.find(({ id }) => id === "growth-team-0-candidate")!;
    return {
      activeTeamIds,
      core: {
        id: core.id,
        network: core.network,
        status: Object.fromEntries(NETWORK_MODEL_IDS.map((modelId) => [modelId, decideNetworkModel(core, modelId)])),
      },
      metrics: compareNetworkModels(candidates),
      nonNetworkCandidates: candidates.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible).length,
      teamCount,
    };
  });
}

export function redTeamNetworkModels(config: SeasonScoreConfig) {
  return attackProfiles().map(({ attack, input }) => {
    const graph = buildOpponentGraph([], [input]);
    const [result] = evaluateV3Ranking({ config, graph, inputs: [input], strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
    const enriched = enrichCompetitiveEvidence(input, graph).filter(({ record }) => isSeasonScoreEvidence(record));
    const [row] = contextualizeNetworkCandidates([{
      currentCertification: result!.certification,
      executedAbuse: true,
      id: result!.playerId,
      lowConfidenceEvidenceRatio: result!.lowConfidenceEvidenceRatio,
      matchConfidence: result!.competitiveConfidence,
      network: explainNetworkDiversity(enriched, graph),
      nonNetworkTrophyEligible: result!.certificationReasons.filter((reason) => !["insufficient_network_diversity", "integrity_anomaly"].includes(reason)).length === 0,
      provinceCode: result!.competitiveProvinceCode ?? "08",
      rankingEligible: result!.eligibility.eligible,
      score: result!.score,
      sourceRisk: result!.sourceRisk,
      teamIds: [...input.player.teamIds],
      validChallenges: result!.validChallenges,
    }]);
    return {
      attack: attack as AttackKind,
      decisions: Object.fromEntries(NETWORK_MODEL_IDS.map((modelId) => [modelId, decideNetworkModel(row!, modelId)])),
      network: row!.network,
      nonNetworkTrophyEligible: row!.nonNetworkTrophyEligible,
      risk: row!.sourceRisk,
    };
  });
}

export function aggregateModelMetrics(rows: ModelMetrics[]) {
  return Object.fromEntries(Object.entries(rows.reduce<Record<string, ModelMetrics[]>>((groups, row) => {
    const key = row.threshold === undefined ? row.modelId : `${row.modelId}_${row.threshold.toFixed(2)}`;
    groups[key] = [...(groups[key] ?? []), row];
    return groups;
  }, {})).map(([key, values]) => [key, {
    certifiedTop10Contamination: round(percentile(values.map((row) => row.certifiedTop10Contamination), 0.5), 4),
    certifiedTop20Contamination: round(percentile(values.map((row) => row.certifiedTop20Contamination), 0.5), 4),
    certifiedTop50Contamination: round(percentile(values.map((row) => row.certifiedTop50Contamination), 0.5), 4),
    certifiable: round(values.reduce((sum, row) => sum + row.certifiable, 0) / values.length, 2),
    falseNegativeRate: round(ratio(values.reduce((sum, row) => sum + row.falseNegative, 0), values.reduce((sum, row) => sum + row.falseNegative + row.truePositive, 0)), 4),
    falsePositiveRate: round(ratio(values.reduce((sum, row) => sum + row.falsePositive, 0), values.reduce((sum, row) => sum + row.falsePositive + row.trueNegative, 0)), 4),
    legitimateCertificationRate: round(percentile(values.map((row) => row.legitimateCertificationRate), 0.5), 4),
    modelId: values[0]!.modelId,
    precision: round(ratio(values.reduce((sum, row) => sum + row.truePositive, 0), values.reduce((sum, row) => sum + row.truePositive + row.falsePositive, 0)), 4),
    recall: round(ratio(values.reduce((sum, row) => sum + row.truePositive, 0), values.reduce((sum, row) => sum + row.truePositive + row.falseNegative, 0)), 4),
    top10Contamination: round(percentile(values.map((row) => row.top10Contamination), 0.5), 4),
    top20Contamination: round(percentile(values.map((row) => row.top20Contamination), 0.5), 4),
    top50Contamination: round(percentile(values.map((row) => row.top50Contamination), 0.5), 4),
    threshold: values[0]!.threshold,
  }]));
}
