import { evaluateEliteByScope, evaluateNationalTops } from "./elite-metrics";
import { isSeasonScoreEvidence } from "./engine";
import {
  RANKING_ELIGIBILITY,
  TROPHY_RULES,
  buildOpponentGraph,
  compareV3Players,
  enrichCompetitiveEvidence,
  evaluateV3Ranking,
  teamProfilesFromWorld,
  type ConfidencePolicy,
  type EvidenceStrategy,
  type OpponentGraph,
  type TeamIntegrityProfile,
  type TrophyRule,
  type TrophyScope,
  type V3RankedPlayer,
} from "./integrity-v3";
import { evaluateFormula } from "./metrics";
import { round } from "./random";
import { attackProfiles, createProfileInput, legitimateRiskProfiles } from "./scenarios";
import { TERRITORY_BY_PROVINCE } from "./territories";
import type { SimulationWorld } from "./simulator";
import type { AttackKind, PlayerMatchEvidence, RankedPlayer, SeasonPlayerInput, SeasonScoreConfig } from "./types";

export const V3_STRATEGIES: EvidenceStrategy[] = [
  "control",
  "score_penalty",
  "evidence_exclusion",
  "certification_hold",
  "penalty_and_hold",
  "exclusion_and_hold",
];

export function v3Baseline(previous: SeasonScoreConfig): SeasonScoreConfig {
  return {
    ...previous,
    eligibility: { ...RANKING_ELIGIBILITY },
    id: "season-score-v3-55-30-15",
    label: "55/30/15 · recent30 · V3 evidence lab",
    ratingConfidenceModel: "full",
    volumeModel: "recent_30",
    weights: { competition: 30, opposition: 15, quality: 55 },
  };
}

export function worldGraph(world: SimulationWorld, inputs: SeasonPlayerInput[]) {
  return buildOpponentGraph(teamProfilesFromWorld(world.teams), inputs);
}

function cloneAttack(input: SeasonPlayerInput, suffix: string, provinceCode: string, attack: AttackKind) {
  return {
    ...input,
    player: { ...input.player, id: `${input.player.id}-${suffix}` },
    records: input.records.map((record, index) => {
      const coordinatedTeamHopping = attack === "team_hopping";
      return {
        ...record,
        challengeId: `${record.challengeId}-${suffix}`,
        occurredAt: new Date(Date.UTC(2029, 1 + Math.floor(index / 5), 1 + index % 24, 18, index % 60)).toISOString(),
        opponentIndependence: coordinatedTeamHopping ? 0.38 : record.opponentIndependence,
        provinceCode,
      };
    }),
  };
}

function largestProvincePopulation(inputs: SeasonPlayerInput[], config: SeasonScoreConfig) {
  const ranked = evaluateV3Ranking({
    config,
    graph: buildOpponentGraph([], inputs),
    inputs,
    strategy: "control",
    trophyRule: TROPHY_RULES.province,
  });
  const counts = new Map<string, number>();
  for (const result of ranked) {
    if (!result.competitiveProvinceCode) continue;
    counts.set(result.competitiveProvinceCode, (counts.get(result.competitiveProvinceCode) ?? 0) + 1);
  }
  const provinceCode = [...counts].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))[0]?.[0] ?? "08";
  const ids = new Set(ranked.filter((result) => result.competitiveProvinceCode === provinceCode).map(({ playerId }) => playerId));
  return { population: inputs.filter(({ player }) => ids.has(player.id)).slice(0, 1_000), provinceCode };
}

export function contaminationExperiment(
  inputs: SeasonPlayerInput[],
  graph: OpponentGraph,
  config: SeasonScoreConfig,
  options: { rates?: number[]; strategies?: EvidenceStrategy[] } = {},
) {
  const { population, provinceCode } = largestProvincePopulation(inputs, config);
  const attacks = attackProfiles().filter(({ attack }) => [
    "collusion",
    "fake_matches",
    "fake_participation",
    "ghost_teams",
    "opponent_boost",
    "rating_boost",
    "team_hopping",
    "territory_gaming",
  ].includes(attack));
  return (options.rates ?? [0, 0.01, 0.02, 0.05, 0.1]).flatMap((rate) => {
    const count = Math.round(population.length * rate);
    const cheaters = Array.from({ length: count }, (_, index) => cloneAttack(
      attacks[index % attacks.length]!.input,
      `${rate}-${index}`,
      provinceCode,
      attacks[index % attacks.length]!.attack,
    ));
    const cheaterIds = new Set(cheaters.map(({ player }) => player.id));
    return (options.strategies ?? V3_STRATEGIES).map((strategy) => {
      const results = evaluateV3Ranking({
        config,
        graph,
        inputs: [...population, ...cheaters],
        strategy,
        trophyRule: TROPHY_RULES.province,
      });
      const top10 = results.filter(({ competitiveProvinceCode, eligibility }) => (
        eligibility.eligible && competitiveProvinceCode === provinceCode
      )).sort(compareV3Players).slice(0, 10);
      const rawCheaters = top10.filter(({ playerId }) => cheaterIds.has(playerId)).length;
      const certifiedCheaters = top10.filter(({ certification, playerId }) => (
        certification === "eligible" && cheaterIds.has(playerId)
      )).length;
      return {
        certifiedTop10Contamination: round(certifiedCheaters / 10, 4),
        cheaterTop10Ids: top10.filter(({ playerId }) => cheaterIds.has(playerId)).map(({ playerId }) => playerId).join("|"),
        cheaters: count,
        highRiskTop10: top10.filter(({ sourceRisk }) => sourceRisk.classification === "high_risk" || sourceRisk.classification === "suspicious").length,
        pendingTop10: top10.filter(({ certification }) => certification === "pending_integrity_review").length,
        provinceCode,
        rate,
        strategy,
        top10Contamination: round(rawCheaters / 10, 4),
      };
    });
  });
}

function profile(id: string, overrides: Partial<TeamIntegrityProfile> = {}): TeamIntegrityProfile {
  return {
    adminIds: [`admin-${id}`],
    createdDaysAgo: 800,
    id,
    ownerId: `owner-${id}`,
    playerIds: Array.from({ length: 10 }, (_, index) => `${id}-player-${index}`),
    provinceCode: "08",
    sportsClusterId: `sport-${id}`,
    venueClusterId: "venue-08",
    ...overrides,
  };
}

export function legitimateClubVsFakeFarm(config: SeasonScoreConfig) {
  const sharedFakeRoster = Array.from({ length: 9 }, (_, index) => `fake-shared-${index}`);
  const legitimateTeams = Array.from({ length: 4 }, (_, index) => profile(`club-${index}`, {
    adminIds: ["club-admin"],
    ownerId: "club-owner",
    playerIds: [`club-shared-${index % 2}`, ...Array.from({ length: 9 }, (_, playerIndex) => `club-${index}-p-${playerIndex}`)],
    sportsClusterId: "club-real",
  }));
  const fakeTeams = Array.from({ length: 10 }, (_, index) => profile(`fake-${index}`, {
    adminIds: ["fake-admin"],
    createdDaysAgo: 2 + index,
    ownerId: "fake-owner",
    playerIds: [...sharedFakeRoster, `fake-unique-${index}`],
    sportsClusterId: "fake-network",
  }));
  const beneficiary = profile("beneficiary");
  const clubInput = createProfileInput({ challenges: 30, id: "legitimate-club-player", independence: 0.78, logicalOpponents: 4, opponentRating: 84, rating: 86, technicalOpponents: 4, winRate: 0.62 });
  clubInput.records = clubInput.records.map((record, index) => ({ ...record, opponentTeamId: legitimateTeams[index % legitimateTeams.length]!.id, teamId: legitimateTeams[(index + 1) % legitimateTeams.length]!.id }));
  const fakeInput = createProfileInput({ accountAgeDays: 3, challenges: 30, id: "fake-farm-beneficiary", opponentRating: 94, rating: 96, technicalOpponents: 10, winRate: 0.94 });
  fakeInput.records = fakeInput.records.map((record, index) => ({ ...record, opponentTeamId: fakeTeams[index % fakeTeams.length]!.id, teamId: beneficiary.id }));
  const graph = buildOpponentGraph([...legitimateTeams, ...fakeTeams, beneficiary], [clubInput, fakeInput]);
  const results = evaluateV3Ranking({ config, graph, inputs: [clubInput, fakeInput], strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  return results.map((result) => ({
    certification: result.certification,
    competitionNetworkDiversity: result.competitionNetworkDiversity,
    id: result.playerId,
    logicalOpponents: result.logicalOpponents,
    risk: result.sourceRisk.risk,
    technicalOpponents: result.technicalOpponents,
  }));
}

export function collusionExperiment(config: SeasonScoreConfig) {
  return ([5, 10] as const).flatMap((teamCount) => {
    const scenario = teamCount === 5 ? "ABCDE" : "ten-team-ring";
    const own = profile(`${scenario}-a`);
    const opponents = Array.from({ length: teamCount }, (_, index) => profile(`${scenario}-${String.fromCharCode(98 + index)}`));
    const colluder = createProfileInput({ challenges: 30, id: `real-team-collusion-${scenario}`, opponentRating: 92, rating: 87, technicalOpponents: teamCount, winRate: 0.94 });
    colluder.records = colluder.records.map((record, index) => ({
      ...record,
      opponentTeamId: opponents[index % opponents.length]!.id,
      teamId: own.id,
    }));
    const graph = buildOpponentGraph([own, ...opponents], [colluder]);
    return V3_STRATEGIES.map((strategy) => {
      const [result] = evaluateV3Ranking({ config, graph, inputs: [colluder], strategy, trophyRule: TROPHY_RULES.province });
      return {
        certification: result!.certification,
        competitionNetworkDiversity: result!.competitionNetworkDiversity,
        competitiveConfidence: result!.competitiveConfidence,
        risk: result!.sourceRisk.risk,
        scenario,
        score: result!.score,
        strategy,
      };
    });
  });
}

export function falsePositiveExperiment(config: SeasonScoreConfig) {
  const inputs = legitimateRiskProfiles();
  const graph = buildOpponentGraph([], inputs);
  const results = evaluateV3Ranking({ config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  const highRisk = results.filter(({ sourceRisk }) => sourceRisk.classification === "high_risk" || sourceRisk.classification === "suspicious");
  return {
    highRiskRate: round(highRisk.length / Math.max(1, results.length), 4),
    rows: results.map((result) => ({
      certification: result.certification,
      classification: result.sourceRisk.classification,
      id: result.playerId,
      risk: result.sourceRisk.risk,
    })),
  };
}

function certifiedResults(results: V3RankedPlayer[]): RankedPlayer[] {
  return results.map((result) => ({
    ...result,
    eligibility: { ...result.eligibility, eligible: result.certification === "eligible" },
  }));
}

function trophyRule(scope: TrophyScope, challenges: number, opponents: number, confidence: number): TrophyRule {
  const base = TROPHY_RULES[scope];
  return {
    ...base,
    id: `${scope}-${challenges}/${opponents}`,
    minimumChallenges: challenges,
    minimumCompetitiveConfidence: confidence,
    minimumLogicalOpponents: opponents,
  };
}

export function trophyEligibilityExperiments(
  inputs: SeasonPlayerInput[],
  graph: OpponentGraph,
  config: SeasonScoreConfig,
) {
  const candidates: TrophyRule[] = [
    trophyRule("province", 20, 8, 0.65),
    trophyRule("province", 25, 10, 0.72),
    trophyRule("province", 30, 10, 0.76),
    trophyRule("autonomous_community", 25, 10, 0.72),
    trophyRule("autonomous_community", 30, 12, 0.75),
    trophyRule("autonomous_community", 35, 15, 0.78),
    trophyRule("national", 30, 12, 0.76),
    trophyRule("national", 40, 15, 0.8),
    trophyRule("national", 50, 20, 0.84),
  ];
  return candidates.map((rule) => {
    const evaluated = evaluateV3Ranking({ config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: rule });
    const certified = certifiedResults(evaluated);
    const scopeRows = rule.scope === "national" ? [] : evaluateEliteByScope({
      inputs,
      minimumEligible: 20,
      results: certified,
      scope: rule.scope,
      truth: "season_merit",
    });
    const national = rule.scope === "national" ? evaluateNationalTops(inputs, certified, "season_merit") : [];
    const middle = <T extends number>(values: T[]) => [...values].sort((left, right) => left - right)[Math.floor((values.length - 1) / 2)] ?? 0;
    return {
      candidateRecall20Median: round(middle(scopeRows.map(({ candidateRecallAt20 }) => candidateRecallAt20)), 4),
      certifiedPlayers: evaluated.filter(({ certification }) => certification === "eligible").length,
      id: rule.id,
      nationalTop100Ndcg: national.find(({ k }) => k === 100)?.ndcg ?? null,
      nationalTop10Ndcg: national.find(({ k }) => k === 10)?.ndcg ?? null,
      ndcg10Median: round(middle(scopeRows.map(({ ndcgAt10 }) => ndcgAt10)), 4),
      scope: rule.scope,
      territories: scopeRows.length,
    };
  });
}

function provinceGroups(results: V3RankedPlayer[]) {
  const groups = new Map<string, V3RankedPlayer[]>();
  for (const result of results.filter(({ eligibility }) => eligibility.eligible)) {
    if (!result.competitiveProvinceCode) continue;
    groups.set(result.competitiveProvinceCode, [...(groups.get(result.competitiveProvinceCode) ?? []), result]);
  }
  for (const group of groups.values()) group.sort(compareV3Players);
  return groups;
}

function fabricatedRecord(template: PlayerMatchEvidence, account: number, match: number): PlayerMatchEvidence {
  return {
    ...template,
    challengeId: `v3-cutoff-account-${account}-match-${match}`,
    occurredAt: new Date(Date.UTC(2029, 6, 1 + match, 18, account)).toISOString(),
    opponentClusterId: `v3-cutoff-account-${account}`,
    opponentIndependence: account >= 10 ? 0.82 : 0.12 + account * 0.035,
    opponentRating: 95,
    opponentTeamId: `v3-cutoff-team-${account}`,
    participationConfidence: account >= 10 ? 0.9 : 0.2,
    result: 1,
    status: "confirmed",
    teamGoalDifference: 1,
    venueConfidence: account >= 10 ? 0.95 : 0.45,
    week: 48 + Math.floor(match / 4),
  };
}

export function cutoffAttackMatrix(
  inputs: SeasonPlayerInput[],
  graph: OpponentGraph,
  config: SeasonScoreConfig,
) {
  const base = evaluateV3Ranking({ config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const target = [...provinceGroups(base)].filter(([, group]) => group.length >= 20 && group[14] && group[8])
    .sort((left, right) => right[1].length - left[1].length)[0];
  if (!target) return [];
  const [provinceCode, group] = target;
  const attacker = inputById.get(group[14]!.playerId)!;
  const threshold = group[8]!.rawScore;
  return [1, 3, 5, 10].flatMap((accounts) => [1, 3, 5, 10].map((matches) => {
    const modified = structuredClone(attacker);
    const template = attacker.records.find(isSeasonScoreEvidence)!;
    for (let index = 0; index < matches; index += 1) {
      modified.records.push(fabricatedRecord(template, 1 + index % accounts, index + 1));
    }
    const [result] = evaluateV3Ranking({ config, graph, inputs: [modified], strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
    return {
      accounts,
      attackCost: accounts + matches,
      baselineRank: 15,
      crossedToRank9: Boolean(result!.eligibility.eligible && result!.rawScore >= threshold),
      evidenceAccepted: result!.validChallenges - attacker.records.filter(isSeasonScoreEvidence).length,
      matches,
      provinceCode,
      targetRank: 9,
    };
  }));
}

export function weightedLeaveOneOut(
  inputs: SeasonPlayerInput[],
  graph: OpponentGraph,
  config: SeasonScoreConfig,
  maximumProvinces = 12,
) {
  const results = evaluateV3Ranking({ config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const categories = new Map<string, { dependencies: number; removals: number }>([
    ["low_confidence", { dependencies: 0, removals: 0 }],
    ["low_independence", { dependencies: 0, removals: 0 }],
    ["normal", { dependencies: 0, removals: 0 }],
    ["repeated_opponent", { dependencies: 0, removals: 0 }],
    ["strong_opponent", { dependencies: 0, removals: 0 }],
  ]);
  let dependentPlayers = 0;
  let players = 0;
  for (const [, group] of [...provinceGroups(results)].filter(([, values]) => values.length >= 50 && values[10]).slice(0, maximumProvinces)) {
    const threshold = group[10]!.rawScore;
    for (const ranked of group.slice(0, 10)) {
      const input = inputById.get(ranked.playerId)!;
      const evidence = enrichCompetitiveEvidence(input, graph);
      const logicalCounts = new Map<string, number>();
      evidence.forEach(({ logicalOpponentId }) => logicalCounts.set(logicalOpponentId, (logicalCounts.get(logicalOpponentId) ?? 0) + 1));
      let playerDependent = false;
      for (const item of evidence.filter(({ record }) => isSeasonScoreEvidence(record))) {
        const category = item.matchCompetitiveConfidence < 0.5 ? "low_confidence"
          : item.opponentIndependenceScore < 0.5 ? "low_independence"
            : (logicalCounts.get(item.logicalOpponentId) ?? 0) > 1 ? "repeated_opponent"
              : item.record.opponentRating >= 85 ? "strong_opponent" : "normal";
        const modified = { ...input, records: input.records.filter(({ challengeId }) => challengeId !== item.record.challengeId) };
        const [after] = evaluateV3Ranking({ config, graph, inputs: [modified], strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
        const dependency = !after!.eligibility.eligible || after!.rawScore < threshold;
        const aggregate = categories.get(category) ?? { dependencies: 0, removals: 0 };
        aggregate.removals += 1;
        if (dependency) aggregate.dependencies += 1;
        categories.set(category, aggregate);
        if (dependency) playerDependent = true;
      }
      players += 1;
      if (playerDependent) dependentPlayers += 1;
    }
  }
  return {
    categories: [...categories].map(([category, value]) => ({
      category,
      dependencies: value.dependencies,
      dependencyRate: round(value.dependencies / Math.max(1, value.removals), 4),
      removals: value.removals,
    })),
    dependentPlayers,
    playerDependencyRate: round(dependentPlayers / Math.max(1, players), 4),
    players,
  };
}

export function confidencePolicyExperiment(
  inputs: SeasonPlayerInput[],
  graph: OpponentGraph,
  config: SeasonScoreConfig,
) {
  const policies: ConfidencePolicy[] = ["graduated", "hard_050", "hard_075"];
  return policies.map((confidencePolicy) => {
    const results = evaluateV3Ranking({ config, confidencePolicy, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
    const formula = evaluateFormula(`v3-${confidencePolicy}`, inputs, results);
    const attackInputs = attackProfiles().map(({ input }, index) => ({
      ...input,
      player: { ...input.player, id: `${input.player.id}-${confidencePolicy}-${index}` },
    }));
    const attackResults = evaluateV3Ranking({
      confidencePolicy,
      config,
      graph: buildOpponentGraph([], attackInputs),
      inputs: attackInputs,
      strategy: "evidence_exclusion",
      trophyRule: TROPHY_RULES.province,
    });
    const provinceRows = evaluateEliteByScope({ inputs, minimumEligible: 50, results, scope: "province", truth: "season_merit" });
    const median = (values: number[]) => [...values].sort((left, right) => left - right)[Math.floor((values.length - 1) / 2)] ?? 0;
    return {
      confidencePolicy,
      eligibleAttackProfiles: attackResults.filter(({ eligibility }) => eligibility.eligible).length,
      eligiblePlayers: results.filter(({ eligibility }) => eligibility.eligible).length,
      ndcg10Median: round(median(provinceRows.map(({ ndcgAt10 }) => ndcgAt10)), 4),
      recall20Median: round(median(provinceRows.map(({ candidateRecallAt20 }) => candidateRecallAt20)), 4),
      volumeAdvantage: formula.volumeAdvantage,
    };
  });
}

export function certificationReviewWorkload(results: V3RankedPlayer[]) {
  const playerIds = new Set<string>();
  let nominations = 0;
  for (const group of provinceGroups(results).values()) {
    for (const result of group.slice(0, 10).filter(({ certification }) => certification === "pending_integrity_review")) {
      nominations += 1;
      playerIds.add(result.playerId);
    }
  }
  const communityGroups = new Map<string, V3RankedPlayer[]>();
  for (const result of results.filter(({ eligibility, competitiveProvinceCode }) => eligibility.eligible && competitiveProvinceCode)) {
    const community = TERRITORY_BY_PROVINCE.get(result.competitiveProvinceCode!)?.autonomousCommunityCode;
    if (!community) continue;
    communityGroups.set(community, [...(communityGroups.get(community) ?? []), result]);
  }
  for (const group of communityGroups.values()) {
    for (const result of group.sort(compareV3Players).slice(0, 10).filter(({ certification }) => certification === "pending_integrity_review")) {
      nominations += 1;
      playerIds.add(result.playerId);
    }
  }
  for (const result of [...results].sort(compareV3Players).slice(0, 100).filter(({ certification }) => certification === "pending_integrity_review")) {
    nominations += 1;
    playerIds.add(result.playerId);
  }
  return { deduplicatedProfiles: playerIds.size, nominations };
}

export function exactTieCount(results: V3RankedPlayer[]) {
  const ordered = results.filter(({ eligibility }) => eligibility.eligible).sort(compareV3Players);
  let ties = 0;
  for (let index = 1; index < ordered.length; index += 1) {
    if (ordered[index]!.rawScore === ordered[index - 1]!.rawScore) ties += 1;
  }
  return ties;
}
