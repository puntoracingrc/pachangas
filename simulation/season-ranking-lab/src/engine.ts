import { clamp, round } from "./random";
import { TERRITORY_BY_PROVINCE } from "./territories";
import type {
  EligibilityResult,
  PlayerMatchEvidence,
  RankedPlayer,
  RiskAssessment,
  RiskSignals,
  SeasonPlayerInput,
  SeasonScoreConfig,
  SeasonScoreResult,
} from "./types";

const VALID_STATUSES = new Set(["auto_confirmed", "confirmed"]);

export function isSeasonScoreEvidence(record: PlayerMatchEvidence) {
  return record.kind === "challenge" && record.participated && VALID_STATUSES.has(record.status);
}

export function expectedResult(teamRating: number, opponentRating: number) {
  return 1 / (1 + 10 ** ((opponentRating - teamRating) / 32));
}

function performanceValue(record: PlayerMatchEvidence) {
  return clamp(50 + (record.result - expectedResult(record.teamRating, record.opponentRating)) * 85, 0, 100);
}

function selectVolumeWindow(records: PlayerMatchEvidence[], config: SeasonScoreConfig) {
  const chronological = [...records].sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
  if (config.volumeModel === "recent_20") return chronological.slice(-20);
  if (config.volumeModel === "recent_25") return chronological.slice(-25);
  if (config.volumeModel === "recent_30") return chronological.slice(-30);
  if (config.volumeModel === "best_20") {
    return chronological
      .map((record, index) => ({ index, record, value: performanceValue(record) }))
      .sort((left, right) => right.value - left.value || right.index - left.index)
      .slice(0, 20)
      .sort((left, right) => left.index - right.index)
      .map(({ record }) => record);
  }
  return chronological;
}

function weightSelectedRecords(records: PlayerMatchEvidence[], config: SeasonScoreConfig) {
  const encounterCounts = new Map<string, number>();
  return records.map((record) => {
    const opponentKey = config.integrityMode === "weighted"
      ? record.opponentClusterId : record.opponentTeamId;
    const encounter = encounterCounts.get(opponentKey) ?? 0;
    encounterCounts.set(opponentKey, encounter + 1);
    const decay = config.opponentDecay[Math.min(encounter, config.opponentDecay.length - 1)] ?? 0;
    const independence = config.integrityMode === "weighted" ? record.opponentIndependence : 1;
    return { record, weight: decay * independence };
  });
}

function weightedRecords(records: PlayerMatchEvidence[], config: SeasonScoreConfig) {
  if (config.volumeModel !== "hybrid_70_30") {
    return weightSelectedRecords(selectVolumeWindow(records, config), config);
  }
  const chronological = [...records].sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
  const recent = weightSelectedRecords(chronological.slice(-20), config);
  const season = weightSelectedRecords(chronological, config);
  const combined = new Map<string, { record: PlayerMatchEvidence; weight: number }>();
  for (const { record, weight } of season) {
    combined.set(record.challengeId, { record, weight: weight * 0.3 });
  }
  for (const { record, weight } of recent) {
    const current = combined.get(record.challengeId);
    combined.set(record.challengeId, { record, weight: (current?.weight ?? 0) + weight * 0.7 });
  }
  return [...combined.values()].sort((left, right) => left.record.occurredAt.localeCompare(right.record.occurredAt));
}

export function resolveCompetitiveProvince(
  records: PlayerMatchEvidence[],
  previousProvinceCode: string | null,
) {
  const validRecords = records.filter(isSeasonScoreEvidence)
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
  if (validRecords.length === 0) return null;

  const counts = new Map<string, number>();
  for (const record of validRecords) {
    counts.set(record.provinceCode, (counts.get(record.provinceCode) ?? 0) + 1);
  }
  const maximum = Math.max(...counts.values());
  const tied = [...counts.entries()].filter(([, count]) => count === maximum).map(([code]) => code);
  if (previousProvinceCode && tied.includes(previousProvinceCode)) return previousProvinceCode;
  if (tied.length === 1) return tied[0]!;

  const runningCounts = new Map<string, number>();
  for (const record of validRecords) {
    const current = (runningCounts.get(record.provinceCode) ?? 0) + 1;
    runningCounts.set(record.provinceCode, current);
    if (current === maximum && tied.includes(record.provinceCode)) return record.provinceCode;
  }
  return [...tied].sort()[0] ?? null;
}

function maximumWeeklyFrequency(records: PlayerMatchEvidence[]) {
  const weekly = new Map<number, number>();
  for (const record of records) weekly.set(record.week, (weekly.get(record.week) ?? 0) + 1);
  return Math.max(0, ...weekly.values());
}

function impossibleTravelRatio(records: PlayerMatchEvidence[]) {
  const byDay = new Map<string, Set<string>>();
  for (const record of records) {
    const day = record.occurredAt.slice(0, 10);
    const provinces = byDay.get(day) ?? new Set<string>();
    provinces.add(record.provinceCode);
    byDay.set(day, provinces);
  }
  const impossibleDays = [...byDay.values()].filter((provinces) => provinces.size > 1).length;
  return byDay.size === 0 ? 0 : impossibleDays / byDay.size;
}

export function assessRankingIntegrity(input: SeasonPlayerInput): RiskAssessment {
  const records = input.records.filter(isSeasonScoreEvidence);
  if (records.length === 0) {
    const emptySignals: RiskSignals = {
      accountAgeCluster: 0,
      abnormalMatchFrequency: 0,
      closedNetworkRatio: 0,
      impossibleTravelRatio: 0,
      opponentIdentityGap: 0,
      participationAnomaly: 0,
      ratingVsExternalEvidence: input.player.ratingV2 >= 90 ? 0.45 : 0,
      repeatedOpponentRatio: 0,
      venueAnomaly: 0,
    };
    return { classification: "clean", risk: round(emptySignals.ratingVsExternalEvidence * 100 * 0.12), signals: emptySignals };
  }

  const technicalOpponents = new Set(records.map(({ opponentTeamId }) => opponentTeamId));
  const logicalOpponents = new Set(records.map(({ opponentClusterId }) => opponentClusterId));
  const clusterCounts = new Map<string, number>();
  for (const record of records) {
    clusterCounts.set(record.opponentClusterId, (clusterCounts.get(record.opponentClusterId) ?? 0) + 1);
  }
  const averageIndependence = records.reduce((sum, record) => sum + record.opponentIndependence, 0) / records.length;
  const signals: RiskSignals = {
    accountAgeCluster: clamp((30 - input.player.accountAgeDays) / 30, 0, 1)
      * clamp(1 - averageIndependence, 0, 1),
    abnormalMatchFrequency: clamp((maximumWeeklyFrequency(records) - 3) / 7, 0, 1),
    closedNetworkRatio: clamp(Math.max(...clusterCounts.values()) / records.length - 0.35, 0, 0.65) / 0.65,
    impossibleTravelRatio: clamp(impossibleTravelRatio(records) * 2, 0, 1),
    opponentIdentityGap: technicalOpponents.size === 0 ? 0
      : 1 - logicalOpponents.size / technicalOpponents.size,
    participationAnomaly: 1 - records.reduce((sum, record) => sum + record.participationConfidence, 0) / records.length,
    ratingVsExternalEvidence: clamp((input.player.ratingV2 - 80) / 20, 0, 1)
      * clamp(1 - records.length / 20, 0, 1)
      * (1 - averageIndependence * 0.5),
    repeatedOpponentRatio: clamp(1 - logicalOpponents.size / records.length, 0, 1),
    venueAnomaly: 1 - records.reduce((sum, record) => sum + record.venueConfidence, 0) / records.length,
  };
  const risk = round(100 * (
    signals.repeatedOpponentRatio * 0.1
    + signals.opponentIdentityGap * 0.18
    + signals.closedNetworkRatio * 0.14
    + signals.abnormalMatchFrequency * 0.11
    + signals.impossibleTravelRatio * 0.09
    + signals.participationAnomaly * 0.08
    + signals.venueAnomaly * 0.07
    + signals.ratingVsExternalEvidence * 0.11
    + signals.accountAgeCluster * 0.12
  ));
  const classification = risk >= 75 ? "high_risk" as const
    : risk >= 50 ? "suspicious" as const
      : risk >= 25 ? "watch" as const : "clean" as const;
  return { classification, risk, signals };
}

function resolveEligibility(
  input: SeasonPlayerInput,
  config: SeasonScoreConfig,
  records: PlayerMatchEvidence[],
  asOfWeek: number,
): EligibilityResult {
  const opponentKey = (record: PlayerMatchEvidence) => config.integrityMode === "weighted"
    ? record.opponentClusterId : record.opponentTeamId;
  const uniqueOpponents = new Set(records.map(opponentKey)).size;
  const reasons: string[] = [];
  if (records.length < config.eligibility.minimumValidChallenges) {
    reasons.push(`Retos ${records.length}/${config.eligibility.minimumValidChallenges}`);
  }
  if (uniqueOpponents < config.eligibility.minimumUniqueOpponents) {
    reasons.push(`Rivales ${uniqueOpponents}/${config.eligibility.minimumUniqueOpponents}`);
  }
  if (input.player.ratingReliability < config.eligibility.minimumRatingReliability) {
    reasons.push(`Fiabilidad ${round(input.player.ratingReliability)}/${config.eligibility.minimumRatingReliability}`);
  }
  const recentWeeks = config.eligibility.recentActivityWeeks;
  const latestWeek = Math.max(0, ...records.map(({ week }) => week));
  if (recentWeeks !== null && asOfWeek - latestWeek > recentWeeks) {
    reasons.push(`Sin actividad en las últimas ${recentWeeks} semanas`);
  }
  return { eligible: reasons.length === 0, reasons, uniqueOpponents, validChallenges: records.length };
}

function graduatedUnlock(challenges: number) {
  if (challenges <= 8) return 0.7;
  if (challenges <= 15) return 0.7 + (challenges - 8) / 7 * 0.2;
  if (challenges <= 25) return 0.9 + (challenges - 15) / 10 * 0.1;
  return 1;
}

function qualityComponent(
  input: SeasonPlayerInput,
  config: SeasonScoreConfig,
  weightedChallenges: number,
  independence: number,
  records: PlayerMatchEvidence[],
) {
  const reliabilityFactor = 0.72 + input.player.ratingReliability * 0.28;
  let unlock = 1;
  if (config.ratingConfidenceModel === "graduated") unlock = graduatedUnlock(weightedChallenges);
  if (config.ratingConfidenceModel === "competitive") {
    const evidence = 1 - Math.exp(-weightedChallenges / 11);
    unlock = 0.55 + 0.45 * evidence * (0.65 + 0.35 * independence);
  }
  let quality = input.player.ratingV2;
  if (config.ratingConfidenceModel === "challenge_calibrated" && records.length > 0) {
    const externalPerformance = records.reduce((sum, record) => (
      sum + clamp(50 + (record.result - expectedResult(record.teamRating, record.opponentRating)) * 85, 0, 100)
    ), 0) / records.length;
    const opponentStrength = records.reduce((sum, record) => sum + record.opponentRating, 0) / records.length;
    const challengeCalibratedQuality = input.player.ratingV2 * 0.62
      + externalPerformance * 0.28
      + opponentStrength * 0.1;
    quality = challengeCalibratedQuality;
    const evidence = 1 - Math.exp(-weightedChallenges / 12);
    unlock = 0.6 + 0.4 * evidence * (0.65 + independence * 0.35);
  }
  return clamp(quality * reliabilityFactor * unlock, 0, 100);
}

export function calculateSeasonScore(
  input: SeasonPlayerInput,
  config: SeasonScoreConfig,
  asOfWeek = 52,
): SeasonScoreResult {
  const validRecords = input.records.filter(isSeasonScoreEvidence).filter(({ week }) => week <= asOfWeek);
  const weighted = weightedRecords(validRecords, config);
  const totalWeight = weighted.reduce((sum, item) => sum + item.weight, 0);
  const independence = validRecords.length === 0 ? 0
    : validRecords.reduce((sum, record) => sum + record.opponentIndependence, 0) / validRecords.length;
  const quality = qualityComponent(input, config, totalWeight, independence, validRecords);

  const competitionEvidence = totalWeight === 0 ? 50 : weighted.reduce(
    (sum, item) => sum + performanceValue(item.record) * item.weight,
    0,
  ) / totalWeight;
  const evidenceConfidence = 1 - Math.exp(-totalWeight / 7);
  const competition = 50 * (1 - evidenceConfidence) + competitionEvidence * evidenceConfidence;

  const opponentStrength = totalWeight === 0 ? 50 : weighted.reduce(
    (sum, item) => sum + item.record.opponentRating * item.weight,
    0,
  ) / totalWeight;
  const uniqueOpponentKeys = new Set(weighted.filter(({ weight }) => weight > 0).map(({ record }) => (
    config.integrityMode === "weighted" ? record.opponentClusterId : record.opponentTeamId
  )));
  const diversity = 100 * (1 - Math.exp(-uniqueOpponentKeys.size / 6));
  const opposition = clamp(opponentStrength * 0.58 + diversity * 0.42, 0, 100);

  const risk = assessRankingIntegrity(input);
  const integrityFactor = config.integrityMode === "weighted"
    ? 1 - clamp((risk.risk - 20) / 100, 0, 0.42) : 1;
  const weightedScore = (
    quality * config.weights.quality
    + competition * config.weights.competition
    + opposition * config.weights.opposition
  ) / 100;
  const score = round(clamp(weightedScore * 10 * integrityFactor, 0, 1000));
  return {
    components: {
      competition: round(competition * config.weights.competition / 10),
      integrityFactor: round(integrityFactor, 4),
      opposition: round(opposition * config.weights.opposition / 10),
      quality: round(quality * config.weights.quality / 10),
    },
    competitiveProvinceCode: resolveCompetitiveProvince(validRecords, input.previousCompetitiveProvinceCode),
    eligibility: resolveEligibility(input, config, validRecords, asOfWeek),
    playerId: input.player.id,
    risk,
    score,
    seasonId: input.seasonId,
    weightedChallenges: round(totalWeight),
  };
}

function assignRanks(results: SeasonScoreResult[], key: (result: SeasonScoreResult) => string | null) {
  const groups = new Map<string, SeasonScoreResult[]>();
  for (const result of results.filter(({ eligibility }) => eligibility.eligible)) {
    const groupKey = key(result);
    if (!groupKey) continue;
    const group = groups.get(groupKey) ?? [];
    group.push(result);
    groups.set(groupKey, group);
  }
  const ranks = new Map<string, number>();
  for (const group of groups.values()) {
    group.sort((left, right) => right.score - left.score || left.playerId.localeCompare(right.playerId));
    group.forEach((result, index) => ranks.set(result.playerId, index + 1));
  }
  return ranks;
}

export function rankSeason(
  inputs: SeasonPlayerInput[],
  config: SeasonScoreConfig,
  asOfWeek = 52,
): RankedPlayer[] {
  const results = inputs.map((input) => calculateSeasonScore(input, config, asOfWeek));
  const nationalRanks = assignRanks(results, () => "ES");
  const provinceRanks = assignRanks(results, ({ competitiveProvinceCode }) => competitiveProvinceCode);
  const communityRanks = assignRanks(results, ({ competitiveProvinceCode }) => (
    competitiveProvinceCode ? TERRITORY_BY_PROVINCE.get(competitiveProvinceCode)?.autonomousCommunityCode ?? null : null
  ));
  return results.map((result) => ({
    ...result,
    autonomousCommunityRank: communityRanks.get(result.playerId) ?? null,
    nationalRank: nationalRanks.get(result.playerId) ?? null,
    provinceRank: provinceRanks.get(result.playerId) ?? null,
  }));
}
