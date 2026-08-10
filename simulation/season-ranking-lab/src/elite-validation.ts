import { calculateSeasonScore, isSeasonScoreEvidence, rankSeason } from "./engine";
import { groundTruthValue, percentile } from "./elite-metrics";
import { pearson } from "./metrics";
import { DeterministicRandom, clamp, round } from "./random";
import { createProfileInput } from "./scenarios";
import { TERRITORY_BY_PROVINCE } from "./territories";
import type { PlayerMatchEvidence, Position, RankedPlayer, SeasonPlayerInput, SeasonScoreConfig } from "./types";

export type CutoffUncertainty = {
  cutoffGap: number;
  eligiblePlayers: number;
  provinceCode: string;
  provinceName: string;
  rank10Confidence: number;
  rank10High: number;
  rank10Low: number;
  rank11High: number;
  rank11Low: number;
  sameUncertaintyBand: boolean;
};

function validRecords(input: SeasonPlayerInput) {
  return input.records.filter(isSeasonScoreEvidence);
}

function provinceGroups(results: RankedPlayer[]) {
  const groups = new Map<string, RankedPlayer[]>();
  for (const result of results.filter(({ eligibility }) => eligibility.eligible)) {
    if (!result.competitiveProvinceCode) continue;
    const group = groups.get(result.competitiveProvinceCode) ?? [];
    group.push(result);
    groups.set(result.competitiveProvinceCode, group);
  }
  for (const group of groups.values()) group.sort((left, right) => right.rawScore - left.rawScore || left.playerId.localeCompare(right.playerId));
  return groups;
}

function bootstrapInput(input: SeasonPlayerInput, random: DeterministicRandom, iteration: number) {
  const valid = validRecords(input);
  if (valid.length === 0) return input;
  const sampled = Array.from({ length: valid.length }, (_, index) => {
    const record = random.pick(valid);
    return { ...record, challengeId: `${record.challengeId}-bootstrap-${iteration}-${index}` };
  });
  return { ...input, records: sampled };
}

export function bootstrapCutoffUncertainty(
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
  config: SeasonScoreConfig,
  options: { iterations?: number; minimumEligible?: number; seed?: number } = {},
) {
  const iterations = options.iterations ?? 100;
  const minimumEligible = options.minimumEligible ?? 50;
  const random = new DeterministicRandom(options.seed ?? 11_510);
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const rows: CutoffUncertainty[] = [];
  for (const [provinceCode, group] of provinceGroups(results)) {
    if (group.length < minimumEligible || !group[10]) continue;
    const cutoff = group.slice(6, 14);
    const distributions = new Map(cutoff.map(({ playerId }) => [playerId, [] as number[]]));
    for (let iteration = 0; iteration < iterations; iteration += 1) {
      for (const result of cutoff) {
        const input = inputById.get(result.playerId);
        if (!input) continue;
        distributions.get(result.playerId)!.push(calculateSeasonScore(bootstrapInput(input, random, iteration), config).score);
      }
    }
    const rank10 = group[9]!;
    const rank11 = group[10]!;
    const rank10Scores = distributions.get(rank10.playerId) ?? [rank10.score];
    const rank11Scores = distributions.get(rank11.playerId) ?? [rank11.score];
    const rank10Low = percentile(rank10Scores, 0.05);
    const rank10High = percentile(rank10Scores, 0.95);
    const rank11Low = percentile(rank11Scores, 0.05);
    const rank11High = percentile(rank11Scores, 0.95);
    rows.push({
      cutoffGap: round(rank10.score - rank11.score),
      eligiblePlayers: group.length,
      provinceCode,
      provinceName: TERRITORY_BY_PROVINCE.get(provinceCode)?.provinceName ?? provinceCode,
      rank10Confidence: round(clamp(1 - (rank10High - rank10Low) / 150, 0, 1), 4),
      rank10High: round(rank10High),
      rank10Low: round(rank10Low),
      rank11High: round(rank11High),
      rank11Low: round(rank11Low),
      sameUncertaintyBand: rank10Low <= rank11High && rank11Low <= rank10High,
    });
  }
  return rows;
}

export function leaveOneOutTop10Sensitivity(
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
  config: SeasonScoreConfig,
  minimumEligible = 50,
) {
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  return [...provinceGroups(results)].filter(([, group]) => group.length >= minimumEligible && group[10]).map(([provinceCode, group]) => {
    const threshold = group[10]!.score;
    let dependentPlayers = 0;
    let sensitiveRemovals = 0;
    let testedRemovals = 0;
    for (const result of group.slice(0, 10)) {
      const input = inputById.get(result.playerId);
      if (!input) continue;
      let playerDependsOnOne = false;
      for (const record of validRecords(input)) {
        testedRemovals += 1;
        const modified = calculateSeasonScore({
          ...input,
          records: input.records.filter(({ challengeId }) => challengeId !== record.challengeId),
        }, config);
        if (!modified.eligibility.eligible || modified.score < threshold) {
          playerDependsOnOne = true;
          sensitiveRemovals += 1;
        }
      }
      if (playerDependsOnOne) dependentPlayers += 1;
    }
    return {
      dependentPlayers,
      provinceCode,
      provinceName: TERRITORY_BY_PROVINCE.get(provinceCode)?.provinceName ?? provinceCode,
      sensitiveRemovalRate: round(sensitiveRemovals / Math.max(1, testedRemovals), 4),
      testedRemovals,
      top10DependencyRate: round(dependentPlayers / 10, 4),
    };
  });
}

export function applyTrophyEligibility(
  inputs: SeasonPlayerInput[],
  results: RankedPlayer[],
  rule: { minimumChallenges: number; minimumCompetitiveConfidence: number; minimumUniqueOpponents: number; recentWeeks: number },
  asOfWeek = 52,
) {
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  return results.map((result): RankedPlayer => {
    const input = inputById.get(result.playerId);
    const latestWeek = Math.max(0, ...(input?.records.filter(isSeasonScoreEvidence).map(({ week }) => week) ?? []));
    const competitiveConfidence = clamp(result.weightedChallenges / 20, 0, 1) * (1 - result.risk.risk / 100);
    const trophyEligible = result.eligibility.eligible
      && result.eligibility.validChallenges >= rule.minimumChallenges
      && result.eligibility.uniqueOpponents >= rule.minimumUniqueOpponents
      && competitiveConfidence >= rule.minimumCompetitiveConfidence
      && asOfWeek - latestWeek <= rule.recentWeeks;
    return { ...result, eligibility: { ...result.eligibility, eligible: trophyEligible } };
  });
}

export function positionValidation(inputs: SeasonPlayerInput[], results: RankedPlayer[]) {
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const eligible = results.filter(({ eligibility }) => eligibility.eligible);
  const groups = [...provinceGroups(results).values()];
  const top10Ids = new Set(groups.flatMap((group) => group.slice(0, 10).map(({ playerId }) => playerId)));
  const referenceTop10Ids = new Set(groups.flatMap((group) => [...group]
    .sort((left, right) => (
      (groundTruthValue(inputById.get(right.playerId)!, "season_merit") ?? 0)
      - (groundTruthValue(inputById.get(left.playerId)!, "season_merit") ?? 0)
    ) || left.playerId.localeCompare(right.playerId))
    .slice(0, 10)
    .map(({ playerId }) => playerId)));
  const positions: Position[] = ["POR", "DEF", "MC", "DEL"];
  return positions.map((position) => {
    const positionResults = eligible.filter(({ playerId }) => inputById.get(playerId)?.player.position === position);
    const topCount = positionResults.filter(({ playerId }) => top10Ids.has(playerId)).length;
    const eligibleShare = positionResults.length / Math.max(1, eligible.length);
    const topShare = topCount / Math.max(1, top10Ids.size);
    const truths = positionResults.map(({ playerId }) => groundTruthValue(inputById.get(playerId)!, "season_merit") ?? 0);
    return {
      eligiblePlayers: positionResults.length,
      eligibleShare: round(eligibleShare, 4),
      meanScore: round(positionResults.reduce((sum, result) => sum + result.score, 0) / Math.max(1, positionResults.length)),
      position: position === "MC" ? "MED" : position,
      precisionAt10: round(positionResults.filter(({ playerId }) => top10Ids.has(playerId) && referenceTop10Ids.has(playerId)).length / Math.max(1, topCount), 4),
      representationRatio: round(topShare / Math.max(0.0001, eligibleShare), 4),
      scoreMeritCorrelation: round(pearson(positionResults.map(({ score }) => score), truths), 4),
      top10Places: topCount,
      top10Share: round(topShare, 4),
    };
  });
}

export function ownTeamDiversityExperiment(config: SeasonScoreConfig) {
  return [1, 2, 5, 10].map((ownTeams) => {
    const input = createProfileInput({ challenges: 40, id: `own-teams-${ownTeams}`, opponentRating: 84, ownTeams, rating: 85, technicalOpponents: 16, winRate: 0.6 });
    const result = calculateSeasonScore(input, config);
    return { ownTeams, risk: result.risk.risk, score: result.score, weightedChallenges: result.weightedChallenges };
  });
}

export function teamStrengthFairnessExperiment(config: SeasonScoreConfig) {
  const mediocreStrongTeam = createProfileInput({ challenges: 25, id: "mediocre-strong-team", latentSkill: 75, opponentRating: 85, rating: 75, teamRating: 92, technicalOpponents: 12, winRate: 0.72 });
  const excellentWeakTeam = createProfileInput({ challenges: 25, id: "excellent-weak-team", latentSkill: 91, opponentRating: 82, rating: 91, teamRating: 72, technicalOpponents: 12, winRate: 0.42 });
  const goodNormalTeam = createProfileInput({ challenges: 25, id: "good-normal-team", latentSkill: 88, opponentRating: 85, rating: 88, teamRating: 80, technicalOpponents: 12, winRate: 0.55 });
  return [mediocreStrongTeam, excellentWeakTeam, goodNormalTeam].map((input) => {
    const result = calculateSeasonScore(input, config);
    return {
      competition: result.components.competition,
      label: input.player.id,
      latentSkill: input.player.latentSkill,
      quality: result.components.quality,
      rating: input.player.ratingV2,
      score: result.score,
      teamRating: input.records[0]?.teamRating ?? 0,
      winRate: round(input.records.filter(({ result: matchResult }) => matchResult === 1).length / input.records.length),
    };
  });
}

function fabricatedCutoffRecord(template: PlayerMatchEvidence, index: number): PlayerMatchEvidence {
  return {
    ...template,
    challengeId: `cutoff-fake-${index}`,
    occurredAt: new Date(Date.UTC(2029, 6, 20 + Math.floor(index / 2), 18 + index % 2)).toISOString(),
    opponentClusterId: "cutoff-sybil-cluster",
    opponentIndependence: 0.04,
    opponentRating: 94,
    opponentTeamId: `cutoff-fake-team-${index}`,
    result: 1,
    status: "confirmed",
    teamGoalDifference: 1,
    venueConfidence: 0.95,
    week: 51 + Math.floor(index / 15),
  };
}

export function cutoffAttackExperiment(
  inputs: SeasonPlayerInput[],
  protectedResults: RankedPlayer[],
  unprotectedConfig: SeasonScoreConfig,
  protectedConfig: SeasonScoreConfig,
) {
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const targetGroup = [...provinceGroups(protectedResults).entries()]
    .filter(([, group]) => group.length >= 50 && group[14])
    .sort((left, right) => right[1].length - left[1].length)[0];
  if (!targetGroup) return [];
  const [provinceCode, group] = targetGroup;
  const attacker = inputById.get(group[14]!.playerId)!;
  return ([['unprotected', unprotectedConfig], ['protected', protectedConfig]] as const).map(([mode, config]) => {
    const threshold = rankSeason(inputs, config).filter((result) => result.competitiveProvinceCode === provinceCode && result.eligibility.eligible)
      .sort((left, right) => right.score - left.score)[8]?.score ?? Number.POSITIVE_INFINITY;
    const working = structuredClone(attacker);
    let requiredMatches: number | null = null;
    for (let index = 1; index <= 30; index += 1) {
      working.records.push(fabricatedCutoffRecord(attacker.records[0]!, index));
      const score = calculateSeasonScore(working, config).score;
      if (score >= threshold) {
        requiredMatches = index;
        break;
      }
    }
    return {
      accountsRequired: requiredMatches,
      baselineRank: 15,
      fakeMatchesRequired: requiredMatches,
      mode,
      provinceCode,
      targetRank: 9,
    };
  });
}

export function territorialTop10Churn(previous: RankedPlayer[], current: RankedPlayer[], minimumEligible = 50) {
  const previousGroups = provinceGroups(previous);
  const currentGroups = provinceGroups(current);
  const churn: number[] = [];
  for (const [code, currentGroup] of currentGroups) {
    const previousGroup = previousGroups.get(code);
    if (!previousGroup || currentGroup.length < minimumEligible || previousGroup.length < minimumEligible) continue;
    const previousTop = new Set(previousGroup.slice(0, 10).map(({ playerId }) => playerId));
    const retained = currentGroup.slice(0, 10).filter(({ playerId }) => previousTop.has(playerId)).length;
    churn.push(1 - retained / 10);
  }
  return {
    mean: round(churn.reduce((sum, value) => sum + value, 0) / Math.max(1, churn.length), 4),
    p50: round(percentile(churn, 0.5), 4),
    p90: round(percentile(churn, 0.9), 4),
    territories: churn.length,
  };
}
