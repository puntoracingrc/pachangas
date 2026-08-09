import { assessRankingIntegrity, isSeasonScoreEvidence, rankSeason } from "./engine";
import { clamp, round } from "./random";
import type {
  PlayerMatchEvidence,
  RankedPlayer,
  RiskAssessment,
  SeasonPlayerInput,
  SeasonScoreConfig,
  SyntheticTeam,
} from "./types";

export type EvidenceStrategy = "control" | "score_penalty" | "evidence_exclusion" | "certification_hold" | "penalty_and_hold" | "exclusion_and_hold";
export type ConfidencePolicy = "graduated" | "hard_050" | "hard_075";
export type CertificationState = "eligible" | "not_eligible" | "pending_integrity_review" | "provisional";
export type CertificationPhase = "active" | "awards_certified" | "frozen" | "integrity_reconciliation";
export type TrophyScope = "autonomous_community" | "national" | "province";

export type TeamIntegrityProfile = {
  adminIds: string[];
  createdDaysAgo: number;
  id: string;
  ownerId: string;
  playerIds: string[];
  provinceCode: string;
  sportsClusterId: string;
  venueClusterId: string;
};

export type OpponentGraph = {
  logicalClusterSize: Map<string, number>;
  logicalOpponentByTeam: Map<string, string>;
  matchNeighbors: Map<string, Set<string>>;
  profilesById: Map<string, TeamIntegrityProfile>;
};

export type MatchEvidenceV3 = {
  confidenceBreakdown: MatchCompetitiveConfidenceBreakdown;
  confidenceWeight: number;
  logicalOpponentId: string;
  matchCompetitiveConfidence: number;
  opponentIndependenceScore: number;
  record: PlayerMatchEvidence;
};

export type MatchCompetitiveConfidenceBreakdown = {
  acceptedChallenge: number;
  agreedTime: number;
  agreedVenue: number;
  bilateralResult: number;
  dayAnomalyPenalty: number;
  establishedTeams: number;
  history: number;
  opponentIndependence: number;
  participants: number;
  score: number;
};

export type CompetitiveEvidenceSummary = {
  competitionNetworkDiversity: number;
  competitiveConfidence: number;
  latestValidWeek: number;
  logicalOpponents: number;
  lowConfidenceEvidenceRatio: number;
  ratingReliability: number;
  scoreReachedAt: string;
  technicalOpponents: number;
  validChallenges: number;
};

export type NetworkDiversityBreakdown = {
  availableCompetitiveOpportunity: number;
  broadConnectedOpponents: number;
  closedNetworkRatio: number;
  competitionNetworkDiversity: number;
  ecosystemOpportunity: number;
  externalExposure: number;
  logicalOpponentCount: number;
  opponentClusterDiversity: number;
  opponentConcentration: number;
  opponentEntropy: number;
  outcomeAnomaly: number;
  pairIndependence: number;
  reciprocity: number;
  structuralDiversity: number;
  technicalOpponentCount: number;
  territorialActiveTeams: number;
  territorialNetworkDensity: number;
};

export type V3RankedPlayer = RankedPlayer & CompetitiveEvidenceSummary & {
  certification: CertificationState;
  certificationReasons: string[];
  sourceRisk: RiskAssessment;
};

export type TrophyRule = {
  id: string;
  minimumChallenges: number;
  minimumCompetitionNetworkDiversity: number;
  minimumCompetitiveConfidence: number;
  minimumLogicalOpponents: number;
  minimumRatingReliability: number;
  recentWeeks: number;
  scope: TrophyScope;
};

export const RANKING_ELIGIBILITY = {
  minimumRatingReliability: 0.45,
  minimumUniqueOpponents: 6,
  minimumValidChallenges: 15,
  recentActivityWeeks: 12,
} as const;

export const TROPHY_RULES = {
  province: {
    id: "province-25/10",
    minimumChallenges: 25,
    minimumCompetitionNetworkDiversity: 0.68,
    minimumCompetitiveConfidence: 0.72,
    minimumLogicalOpponents: 10,
    minimumRatingReliability: 0.55,
    recentWeeks: 12,
    scope: "province",
  },
  autonomous_community: {
    id: "community-30/12",
    minimumChallenges: 30,
    minimumCompetitionNetworkDiversity: 0.72,
    minimumCompetitiveConfidence: 0.75,
    minimumLogicalOpponents: 12,
    minimumRatingReliability: 0.6,
    recentWeeks: 10,
    scope: "autonomous_community",
  },
  national: {
    id: "national-40/15",
    minimumChallenges: 40,
    minimumCompetitionNetworkDiversity: 0.76,
    minimumCompetitiveConfidence: 0.8,
    minimumLogicalOpponents: 15,
    minimumRatingReliability: 0.65,
    recentWeeks: 8,
    scope: "national",
  },
} satisfies Record<TrophyScope, TrophyRule>;

class DisjointSet {
  private readonly parent = new Map<string, string>();

  add(value: string) {
    if (!this.parent.has(value)) this.parent.set(value, value);
  }

  find(value: string): string {
    this.add(value);
    const parent = this.parent.get(value)!;
    if (parent === value) return value;
    const root = this.find(parent);
    this.parent.set(value, root);
    return root;
  }

  union(left: string, right: string) {
    const leftRoot = this.find(left);
    const rightRoot = this.find(right);
    if (leftRoot === rightRoot) return;
    const [root, child] = [leftRoot, rightRoot].sort();
    this.parent.set(child!, root!);
  }
}

function intersectionSize(left: Set<string>, right: Set<string>) {
  let count = 0;
  for (const value of left) if (right.has(value)) count += 1;
  return count;
}

function jaccard(left: string[], right: string[]) {
  const leftSet = new Set(left);
  const rightSet = new Set(right);
  const intersection = intersectionSize(leftSet, rightSet);
  return intersection / Math.max(1, leftSet.size + rightSet.size - intersection);
}

function candidatePairs(profiles: TeamIntegrityProfile[]) {
  const buckets = new Map<string, string[]>();
  const add = (key: string, teamId: string) => buckets.set(key, [...(buckets.get(key) ?? []), teamId]);
  for (const profile of profiles) {
    add(`owner:${profile.ownerId}`, profile.id);
    profile.adminIds.forEach((adminId) => add(`admin:${adminId}`, profile.id));
    profile.playerIds.forEach((playerId) => add(`player:${playerId}`, profile.id));
  }
  const pairs = new Set<string>();
  for (const ids of buckets.values()) {
    for (let left = 0; left < ids.length; left += 1) {
      for (let right = left + 1; right < ids.length; right += 1) {
        pairs.add([ids[left]!, ids[right]!].sort().join("|"));
      }
    }
  }
  return [...pairs].map((pair) => pair.split("|") as [string, string]);
}

export function buildOpponentGraph(
  profiles: TeamIntegrityProfile[],
  inputs: SeasonPlayerInput[] = [],
): OpponentGraph {
  const profilesById = new Map(profiles.map((profile) => [profile.id, profile]));
  const set = new DisjointSet();
  profiles.forEach(({ id }) => set.add(id));
  for (const [leftId, rightId] of candidatePairs(profiles)) {
    const left = profilesById.get(leftId)!;
    const right = profilesById.get(rightId)!;
    const overlap = jaccard(left.playerIds, right.playerIds);
    const sharedAdmin = left.adminIds.some((adminId) => right.adminIds.includes(adminId));
    const bothNew = left.createdDaysAgo < 45 && right.createdDaysAgo < 45;
    if (overlap >= 0.75 || (overlap >= 0.55 && sharedAdmin && bothNew)) set.union(left.id, right.id);
  }
  const matchNeighbors = new Map<string, Set<string>>();
  for (const input of inputs) {
    for (const record of input.records.filter(isSeasonScoreEvidence)) {
      const own = matchNeighbors.get(record.teamId) ?? new Set<string>();
      const opponent = matchNeighbors.get(record.opponentTeamId) ?? new Set<string>();
      own.add(record.opponentTeamId);
      opponent.add(record.teamId);
      matchNeighbors.set(record.teamId, own);
      matchNeighbors.set(record.opponentTeamId, opponent);
    }
  }
  const logicalOpponentByTeam = new Map(profiles.map(({ id }) => [id, set.find(id)]));
  const logicalClusterSize = new Map<string, number>();
  for (const logicalId of logicalOpponentByTeam.values()) {
    logicalClusterSize.set(logicalId, (logicalClusterSize.get(logicalId) ?? 0) + 1);
  }
  return {
    logicalClusterSize,
    logicalOpponentByTeam,
    matchNeighbors,
    profilesById,
  };
}

export function teamProfilesFromWorld(teams: SyntheticTeam[]): TeamIntegrityProfile[] {
  return teams.map((team, index) => ({
    adminIds: [`admin:${team.ownerClusterId}`],
    createdDaysAgo: 180 + (index * 97) % 1_600,
    id: team.id,
    ownerId: team.ownerClusterId,
    playerIds: [...team.playerIds],
    provinceCode: team.provinceCode,
    sportsClusterId: team.ownerClusterId,
    venueClusterId: `province:${team.provinceCode}`,
  }));
}

function pairIndependence(record: PlayerMatchEvidence, graph: OpponentGraph) {
  const own = graph.profilesById.get(record.teamId);
  const opponent = graph.profilesById.get(record.opponentTeamId);
  if (!own || !opponent) return clamp(record.opponentIndependence, 0, 1);
  const overlap = jaccard(own.playerIds, opponent.playerIds);
  const sharedAdmin = own.adminIds.some((adminId) => opponent.adminIds.includes(adminId));
  const sameOwner = own.ownerId === opponent.ownerId;
  const sameSportsCluster = own.sportsClusterId === opponent.sportsClusterId;
  const bothNew = own.createdDaysAgo < 45 && opponent.createdDaysAgo < 45;
  const ownNeighbors = graph.matchNeighbors.get(record.teamId) ?? new Set<string>();
  const opponentNeighbors = graph.matchNeighbors.get(record.opponentTeamId) ?? new Set<string>();
  const closedPairRatio = intersectionSize(ownNeighbors, opponentNeighbors)
    / Math.max(1, Math.min(ownNeighbors.size, opponentNeighbors.size));
  const logicalId = graph.logicalOpponentByTeam.get(record.opponentTeamId) ?? record.opponentTeamId;
  const clusterFactor = 1 / Math.max(1, graph.logicalClusterSize.get(logicalId) ?? 1);
  return clamp(
    1
      - overlap * 0.55
      - (sharedAdmin ? 0.18 : 0)
      - (sameOwner ? 0.08 : 0)
      - (sameSportsCluster && sharedAdmin ? 0.04 : 0)
      - (bothNew ? 0.08 : 0)
      - closedPairRatio * 0.11,
    0,
    1,
  ) * clusterFactor;
}

function sameDayAnomaly(records: PlayerMatchEvidence[]) {
  const byDay = new Map<string, number>();
  for (const record of records) {
    const day = record.occurredAt.slice(0, 10);
    byDay.set(day, (byDay.get(day) ?? 0) + 1);
  }
  return new Map(records.map((record) => {
    const count = byDay.get(record.occurredAt.slice(0, 10)) ?? 1;
    return [record.challengeId, clamp((count - 2) / 8, 0, 1)] as const;
  }));
}

export function explainMatchCompetitiveConfidence(
  record: PlayerMatchEvidence,
  graph: OpponentGraph,
  independence: number,
  dayAnomaly: number,
): MatchCompetitiveConfidenceBreakdown {
  const opponent = graph.profilesById.get(record.opponentTeamId);
  const own = graph.profilesById.get(record.teamId);
  const acceptedChallenge = record.kind === "challenge" ? 1 : 0;
  const agreedVenue = clamp(record.venueConfidence, 0, 1);
  const agreedTime = Number.isFinite(Date.parse(record.occurredAt)) ? 1 : 0;
  const participants = clamp(record.participationConfidence, 0, 1);
  const bilateralResult = record.status === "confirmed" ? 1 : record.status === "auto_confirmed" ? 0.72 : 0;
  const established = own && opponent
    ? clamp(Math.min(own.createdDaysAgo, opponent.createdDaysAgo) / 120, 0, 1)
    : clamp(record.opponentIndependence, 0, 1);
  const history = clamp((graph.matchNeighbors.get(record.opponentTeamId)?.size ?? 4) / 5, 0, 1);
  const breakdown = {
    acceptedChallenge: acceptedChallenge * 0.15,
    agreedTime: agreedTime * 0.05,
    agreedVenue: agreedVenue * 0.1,
    bilateralResult: bilateralResult * 0.17,
    dayAnomalyPenalty: -dayAnomaly * 0.28,
    establishedTeams: established * 0.08,
    history: history * 0.04,
    opponentIndependence: independence * 0.06,
    participants: participants * 0.35,
  };
  return {
    ...breakdown,
    score: clamp(Object.values(breakdown).reduce((sum, value) => sum + value, 0), 0, 1),
  };
}

export function confidenceWeight(confidence: number, policy: ConfidencePolicy) {
  if (policy === "hard_050") return confidence >= 0.5 ? 1 : 0;
  if (policy === "hard_075") return confidence >= 0.75 ? 1 : 0;
  if (confidence < 0.5) return 0;
  if (confidence >= 0.75) return 1;
  return 0.35 + (confidence - 0.5) / 0.25 * 0.65;
}

export function enrichCompetitiveEvidence(
  input: SeasonPlayerInput,
  graph: OpponentGraph,
  policy: ConfidencePolicy = "graduated",
) {
  const anomalyByChallenge = sameDayAnomaly(input.records.filter(isSeasonScoreEvidence));
  return input.records.map((record): MatchEvidenceV3 => {
    const opponentIndependenceScore = pairIndependence(record, graph);
    const confidenceBreakdown = explainMatchCompetitiveConfidence(
      record,
      graph,
      opponentIndependenceScore,
      anomalyByChallenge.get(record.challengeId) ?? 0,
    );
    const matchCompetitiveConfidence = confidenceBreakdown.score;
    return {
      confidenceBreakdown,
      confidenceWeight: opponentIndependenceScore < 0.5
        || record.participationConfidence < 0.5
        || record.venueConfidence < 0.5
        ? 0 : confidenceWeight(matchCompetitiveConfidence, policy),
      logicalOpponentId: graph.logicalOpponentByTeam.get(record.opponentTeamId) ?? record.opponentClusterId,
      matchCompetitiveConfidence,
      opponentIndependenceScore,
      record,
    };
  });
}

export function externalNetworkRatio(evidence: MatchEvidenceV3[], graph: OpponentGraph) {
  const opponentIds = new Set(evidence.map(({ record }) => record.opponentTeamId));
  const closedSet = new Set([...opponentIds, ...evidence.map(({ record }) => record.teamId)]);
  const ratios = [...opponentIds].map((teamId) => {
    const neighbors = graph.matchNeighbors.get(teamId);
    if (!neighbors || neighbors.size === 0) return 0;
    const external = [...neighbors].filter((neighbor) => !closedSet.has(neighbor)).length;
    return external / neighbors.size;
  });
  return ratios.length === 0 ? 0 : ratios.reduce((sum, value) => sum + value, 0) / ratios.length;
}

function normalizedEntropy(values: number[]) {
  const total = values.reduce((sum, value) => sum + value, 0);
  if (total === 0 || values.length <= 1) return values.length === 1 ? 0 : 1;
  const entropy = values.reduce((sum, value) => {
    const probability = value / total;
    return sum - probability * Math.log(probability);
  }, 0);
  return clamp(entropy / Math.log(values.length), 0, 1);
}

const territoryStatsCache = new WeakMap<OpponentGraph, Map<string, {
  activeTeams: number;
  density: number;
  reciprocity: number;
}>>();

function territoryStats(graph: OpponentGraph) {
  const cached = territoryStatsCache.get(graph);
  if (cached) return cached;
  const teamIdsByProvince = new Map<string, string[]>();
  for (const teamId of graph.matchNeighbors.keys()) {
    const provinceCode = graph.profilesById.get(teamId)?.provinceCode ?? "*";
    const ids = teamIdsByProvince.get(provinceCode) ?? [];
    ids.push(teamId);
    teamIdsByProvince.set(provinceCode, ids);
  }
  const stats = new Map<string, { activeTeams: number; density: number; reciprocity: number }>();
  for (const [provinceCode, ids] of teamIdsByProvince) {
    const idSet = new Set(ids);
    let edges = 0;
    let reciprocalEdges = 0;
    for (const teamId of ids) {
      for (const neighbor of graph.matchNeighbors.get(teamId) ?? []) {
        if (!idSet.has(neighbor) || teamId >= neighbor) continue;
        edges += 1;
        if (graph.matchNeighbors.get(neighbor)?.has(teamId)) reciprocalEdges += 1;
      }
    }
    const possibleEdges = ids.length * Math.max(0, ids.length - 1) / 2;
    stats.set(provinceCode, {
      activeTeams: ids.length,
      density: possibleEdges === 0 ? 0 : edges / possibleEdges,
      reciprocity: edges === 0 ? 0 : reciprocalEdges / edges,
    });
  }
  territoryStatsCache.set(graph, stats);
  return stats;
}

function networkOpportunity(evidence: MatchEvidenceV3[], graph: OpponentGraph) {
  const ownTeamIds = new Set(evidence.map(({ record }) => record.teamId));
  const provinceCodes = new Set([...ownTeamIds]
    .map((teamId) => graph.profilesById.get(teamId)?.provinceCode)
    .filter((provinceCode): provinceCode is string => Boolean(provinceCode)));
  const inTerritory = (teamId: string) => {
    const provinceCode = graph.profilesById.get(teamId)?.provinceCode;
    return provinceCodes.size === 0 || Boolean(provinceCode && provinceCodes.has(provinceCode));
  };
  const reachable = new Set(ownTeamIds);
  let frontier = new Set(ownTeamIds);
  for (let depth = 0; depth < 2; depth += 1) {
    const next = new Set<string>();
    for (const teamId of frontier) {
      for (const neighbor of graph.matchNeighbors.get(teamId) ?? []) {
        if (!inTerritory(neighbor) || reachable.has(neighbor)) continue;
        reachable.add(neighbor);
        next.add(neighbor);
      }
    }
    frontier = next;
  }
  const ownLogical = new Set([...ownTeamIds].map((teamId) => graph.logicalOpponentByTeam.get(teamId) ?? teamId));
  const availableLogical = new Set([...reachable]
    .map((teamId) => graph.logicalOpponentByTeam.get(teamId) ?? teamId)
    .filter((logicalId) => !ownLogical.has(logicalId)));
  const provinceCode = [...provinceCodes][0] ?? "*";
  const stats = territoryStats(graph).get(provinceCode) ?? { activeTeams: 0, density: 0, reciprocity: 0 };
  return {
    availableCompetitiveOpportunity: availableLogical.size,
    reciprocity: stats.reciprocity,
    territorialActiveTeams: stats.activeTeams,
    territorialNetworkDensity: stats.density,
  };
}

export function explainNetworkDiversity(
  evidence: MatchEvidenceV3[],
  graph: OpponentGraph,
): NetworkDiversityBreakdown {
  const valid = evidence.filter(({ record }) => isSeasonScoreEvidence(record));
  const technicalOpponentIds = new Set(valid.map(({ record }) => record.opponentTeamId));
  const logicalIndependence = new Map<string, number>();
  const logicalFrequency = new Map<string, number>();
  for (const item of valid) {
    logicalIndependence.set(item.logicalOpponentId, Math.max(logicalIndependence.get(item.logicalOpponentId) ?? 0, item.opponentIndependenceScore));
    logicalFrequency.set(item.logicalOpponentId, (logicalFrequency.get(item.logicalOpponentId) ?? 0) + 1);
  }
  const logicalOpponentCount = logicalIndependence.size;
  const structuralDiversity = technicalOpponentIds.size === 0 ? 0
    : [...logicalIndependence.values()].reduce((sum, value) => sum + value, 0) / technicalOpponentIds.size;
  const externalExposure = externalNetworkRatio(valid, graph);
  const outcomeAnomaly = valid.length === 0 ? 0 : valid.reduce((sum, { record }) => {
    const expected = 1 / (1 + 10 ** ((record.opponentRating - record.teamRating) / 32));
    return sum + Math.max(0, record.result - expected);
  }, 0) / valid.length;
  const competitionNetworkDiversity = (structuralDiversity * 0.72 + externalExposure * 0.28)
    * (1 - outcomeAnomaly * (1 - externalExposure) * 0.35);
  const externalRatios = [...technicalOpponentIds].map((teamId) => {
    const neighbors = graph.matchNeighbors.get(teamId) ?? new Set<string>();
    const closedSet = new Set([...technicalOpponentIds, ...valid.map(({ record }) => record.teamId)]);
    return neighbors.size === 0 ? 0 : [...neighbors].filter((neighbor) => !closedSet.has(neighbor)).length / neighbors.size;
  });
  const opportunity = networkOpportunity(valid, graph);
  const opponentConcentration = valid.length === 0 ? 0
    : Math.max(0, ...logicalFrequency.values()) / valid.length;
  return {
    ...opportunity,
    broadConnectedOpponents: externalRatios.filter((ratio) => ratio >= 0.25).length,
    closedNetworkRatio: 1 - externalExposure,
    competitionNetworkDiversity: round(clamp(competitionNetworkDiversity, 0, 1), 4),
    ecosystemOpportunity: opportunity.availableCompetitiveOpportunity === 0 ? 0
      : clamp(logicalOpponentCount / opportunity.availableCompetitiveOpportunity, 0, 1),
    externalExposure: round(externalExposure, 4),
    logicalOpponentCount,
    opponentClusterDiversity: technicalOpponentIds.size === 0 ? 0 : logicalOpponentCount / technicalOpponentIds.size,
    opponentConcentration: round(opponentConcentration, 4),
    opponentEntropy: round(normalizedEntropy([...logicalFrequency.values()]), 4),
    outcomeAnomaly: round(outcomeAnomaly, 4),
    pairIndependence: valid.length === 0 ? 0
      : round(valid.reduce((sum, item) => sum + item.opponentIndependenceScore, 0) / valid.length, 4),
    reciprocity: round(opportunity.reciprocity, 4),
    structuralDiversity: round(structuralDiversity, 4),
    technicalOpponentCount: technicalOpponentIds.size,
    territorialNetworkDensity: round(opportunity.territorialNetworkDensity, 4),
  };
}

export function summarizeCompetitiveEvidence(
  evidence: MatchEvidenceV3[],
  graph: OpponentGraph,
  ratingReliability: number,
): CompetitiveEvidenceSummary {
  const valid = evidence.filter(({ record }) => isSeasonScoreEvidence(record));
  const technicalOpponents = new Set(valid.map(({ record }) => record.opponentTeamId)).size;
  const logical = new Map<string, number>();
  for (const item of valid) {
    logical.set(item.logicalOpponentId, Math.max(logical.get(item.logicalOpponentId) ?? 0, item.opponentIndependenceScore));
  }
  const averageConfidence = valid.length === 0 ? 0
    : valid.reduce((sum, item) => (
      sum + item.matchCompetitiveConfidence * (0.7 + item.opponentIndependenceScore * 0.3)
    ), 0) / valid.length;
  const network = explainNetworkDiversity(valid, graph);
  return {
    competitionNetworkDiversity: network.competitionNetworkDiversity,
    competitiveConfidence: round(averageConfidence * (0.65 + ratingReliability * 0.35), 4),
    latestValidWeek: Math.max(0, ...valid.map(({ record }) => record.week)),
    logicalOpponents: logical.size,
    lowConfidenceEvidenceRatio: round(valid.filter(({ matchCompetitiveConfidence, opponentIndependenceScore }) => (
      matchCompetitiveConfidence < 0.5 || opponentIndependenceScore < 0.5
    )).length / Math.max(1, valid.length), 4),
    ratingReliability,
    scoreReachedAt: [...valid].sort((left, right) => right.record.occurredAt.localeCompare(left.record.occurredAt))[0]?.record.occurredAt ?? "9999-12-31T23:59:59.999Z",
    technicalOpponents,
    validChallenges: valid.length,
  };
}

function transformInput(
  input: SeasonPlayerInput,
  evidence: MatchEvidenceV3[],
  strategy: EvidenceStrategy,
) {
  const exclude = strategy === "evidence_exclusion" || strategy === "exclusion_and_hold";
  return {
    ...input,
    records: evidence.map((item) => ({
      ...item.record,
      opponentClusterId: item.logicalOpponentId,
      opponentIndependence: item.opponentIndependenceScore * (exclude ? item.confidenceWeight : 1),
      participated: item.record.participated && (!exclude || item.confidenceWeight > 0),
    })),
  };
}

function certificationReasons(
  result: RankedPlayer,
  summary: CompetitiveEvidenceSummary,
  input: SeasonPlayerInput,
  sourceRisk: RiskAssessment,
  rule: TrophyRule,
  asOfWeek: number,
) {
  const reasons: string[] = [];
  if (!result.eligibility.eligible) reasons.push("ranking_not_eligible");
  if (summary.validChallenges < rule.minimumChallenges) reasons.push("insufficient_challenges");
  if (summary.logicalOpponents < rule.minimumLogicalOpponents) reasons.push("insufficient_logical_opponents");
  if (summary.competitiveConfidence < rule.minimumCompetitiveConfidence) reasons.push("insufficient_competitive_confidence");
  if (summary.competitionNetworkDiversity < rule.minimumCompetitionNetworkDiversity) reasons.push("insufficient_network_diversity");
  if (input.player.ratingReliability < rule.minimumRatingReliability) reasons.push("insufficient_rating_reliability");
  if (asOfWeek - summary.latestValidWeek > rule.recentWeeks) reasons.push("insufficient_recent_activity");
  if (sourceRisk.classification === "high_risk" || sourceRisk.classification === "suspicious") reasons.push("integrity_anomaly");
  if (summary.lowConfidenceEvidenceRatio > 0.2) reasons.push("low_confidence_dependency");
  return reasons;
}

function resolveCertification(
  reasons: string[],
  phase: CertificationPhase,
  strategy: EvidenceStrategy,
): CertificationState {
  const integrityHold = strategy === "certification_hold"
    || strategy === "penalty_and_hold"
    || strategy === "exclusion_and_hold";
  const integrityReasons = new Set<string>(reasons.filter((reason) => (
    reason === "integrity_anomaly"
      || reason === "low_confidence_dependency"
      || reason === "insufficient_network_diversity"
  )));
  const eligibilityReasons = reasons.filter((reason) => !integrityReasons.has(reason));
  if (eligibilityReasons.length > 0) return "not_eligible";
  if (integrityHold && integrityReasons.size > 0) return "pending_integrity_review";
  if (phase !== "awards_certified") return "provisional";
  return "eligible";
}

export function evaluateV3Ranking(options: {
  asOfWeek?: number;
  confidencePolicy?: ConfidencePolicy;
  config: SeasonScoreConfig;
  graph: OpponentGraph;
  inputs: SeasonPlayerInput[];
  phase?: CertificationPhase;
  strategy: EvidenceStrategy;
  trophyRule: TrophyRule;
}) {
  const asOfWeek = options.asOfWeek ?? 52;
  const phase = options.phase ?? "awards_certified";
  const evidenceByPlayer = new Map(options.inputs.map((input) => [
    input.player.id,
    enrichCompetitiveEvidence(input, options.graph, options.confidencePolicy),
  ]));
  const transformed = options.inputs.map((input) => transformInput(input, evidenceByPlayer.get(input.player.id)!, options.strategy));
  const penalize = options.strategy === "score_penalty" || options.strategy === "penalty_and_hold" || options.strategy === "certification_hold";
  const config = {
    ...options.config,
    integrityScorePenalty: penalize,
  };
  const ranked = rankSeason(transformed, config, asOfWeek);
  const transformedById = new Map(transformed.map((input) => [input.player.id, input]));
  const originalById = new Map(options.inputs.map((input) => [input.player.id, input]));
  return ranked.map((result): V3RankedPlayer => {
    const input = originalById.get(result.playerId)!;
    const transformedInput = transformedById.get(result.playerId)!;
    const evidence = evidenceByPlayer.get(result.playerId)!;
    const summary = summarizeCompetitiveEvidence(evidence, options.graph, input.player.ratingReliability);
    const sourceRisk = assessRankingIntegrity(transformInput(input, evidence, "control"));
    const reasons = certificationReasons(result, summary, input, sourceRisk, options.trophyRule, asOfWeek);
    return {
      ...result,
      ...summary,
      certification: resolveCertification(reasons, phase, options.strategy),
      certificationReasons: reasons,
      sourceRisk,
      weightedChallenges: result.weightedChallenges,
      eligibility: result.eligibility,
      risk: assessRankingIntegrity(transformedInput),
    };
  });
}

export function compareV3Players(left: V3RankedPlayer, right: V3RankedPlayer) {
  return right.rawScore - left.rawScore
    || right.competitiveConfidence - left.competitiveConfidence
    || right.logicalOpponents - left.logicalOpponents
    || right.ratingReliability - left.ratingReliability
    || right.validChallenges - left.validChallenges
    || left.scoreReachedAt.localeCompare(right.scoreReachedAt)
    || left.playerId.localeCompare(right.playerId);
}

export function certificationWindow(hours: 24 | 48 | 168, pendingProfiles: number) {
  const automaticCapacity = hours * 30;
  return {
    automaticCapacity,
    hours,
    manualProfiles: Math.max(0, pendingProfiles - automaticCapacity),
    pendingProfiles,
    viable: pendingProfiles <= automaticCapacity + Math.ceil(hours / 8) * 6,
  };
}

export function participationConfirmationExperiment() {
  return [
    { additionalActionsPerMatch: 0, attackAcceptanceRate: 1, id: "self", label: "Confirmación propia", legitimateCompletionRate: 0.99 },
    { additionalActionsPerMatch: 1, attackAcceptanceRate: 0.48, id: "admin", label: "Confirmación admin", legitimateCompletionRate: 0.96 },
    { additionalActionsPerMatch: 2, attackAcceptanceRate: 0.08, id: "rival", label: "Confirmación cruzada rival", legitimateCompletionRate: 0.91 },
    { additionalActionsPerMatch: 0.18, attackAcceptanceRate: 0.12, id: "sampled", label: "Muestreo Top10/anomalías", legitimateCompletionRate: 0.97 },
  ] as const;
}

export function awardDecisionForPendingCandidate(policy: "no_promotion" | "provisional_promotion" | "trophy_pending") {
  if (policy === "provisional_promotion") return { promoteRank11: true, trophyStatus: "provisional" } as const;
  if (policy === "no_promotion") return { promoteRank11: false, trophyStatus: "withheld" } as const;
  return { promoteRank11: false, trophyStatus: "pending" } as const;
}
