import { isSeasonScoreEvidence } from "../../season-ranking-lab/src/engine";
import {
  RANKING_ELIGIBILITY,
  enrichCompetitiveEvidence,
  explainNetworkDiversity,
  type EvidenceStrategy,
  type TrophyRule,
} from "../../season-ranking-lab/src/integrity-v3";
import { virtualDaysBetween, virtualWeek } from "./clock";
import {
  SYNTHETIC_PROVINCE_TROPHY_RULE,
  evaluateSyntheticRanking,
  syntheticMatchEvidence,
} from "./ranking";
import type { SyntheticAgent, SyntheticMatch, SyntheticWorld } from "./types";

const TROPHY_GATES = [
  "challenges",
  "logical_opponents",
  "confidence",
  "network_diversity",
  "reliability",
  "recent_activity",
  "integrity",
] as const;

type TrophyGate = typeof TROPHY_GATES[number];
type AuditOptions = {
  strategy?: EvidenceStrategy;
  trophyRule?: TrophyRule;
};

function round(value: number, digits = 2) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function percentile(values: number[], quantile: number) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const position = (sorted.length - 1) * quantile;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower]!;
  return sorted[lower]! + (sorted[upper]! - sorted[lower]!) * (position - lower);
}

function distribution(values: number[]) {
  return {
    p10: round(percentile(values, 0.1)),
    p25: round(percentile(values, 0.25)),
    p50: round(percentile(values, 0.5)),
    p75: round(percentile(values, 0.75)),
    p90: round(percentile(values, 0.9)),
    p95: round(percentile(values, 0.95)),
    max: Math.max(0, ...values),
  };
}

export function orderedDistributionValues(value: ReturnType<typeof distribution>) {
  return [value.p10, value.p25, value.p50, value.p75, value.p90, value.p95, value.max];
}

function countBy(values: string[]) {
  const result: Record<string, number> = {};
  for (const value of values) result[value] = (result[value] ?? 0) + 1;
  return result;
}

function bucket(value: number, definitions: Array<{ label: string; maximum: number }>) {
  return definitions.find(({ maximum }) => value <= maximum)?.label ?? definitions.at(-1)!.label;
}

function bucketRows(
  players: PlayerRankingAudit[],
  selector: (player: PlayerRankingAudit) => number,
  definitions: Array<{ label: string; maximum: number }>,
) {
  const provinces = ["08", "28", "46", "41", "17"];
  return definitions.map(({ label }) => ({
    byProvince: Object.fromEntries(provinces.map((provinceCode) => [
      provinceCode,
      players.filter((player) => player.provinceCode === provinceCode && bucket(selector(player), definitions) === label).length,
    ])),
    label,
    other: players.filter((player) => !provinces.includes(player.provinceCode) && bucket(selector(player), definitions) === label).length,
    total: players.filter((player) => bucket(selector(player), definitions) === label).length,
  }));
}

function matchSide(match: SyntheticMatch, agentId: string, agent: SyntheticAgent) {
  const belongsAway = Boolean(match.awayTeamId && agent.teamIds.includes(match.awayTeamId));
  const belongsHome = agent.teamIds.includes(match.homeTeamId);
  return belongsAway && !belongsHome ? "away" as const : "home" as const;
}

function exclusionReason(item: ReturnType<typeof enrichCompetitiveEvidence>[number], match: SyntheticMatch | undefined) {
  const reasons: string[] = [];
  if (match?.evidenceExcluded) reasons.push("source_marked_excluded");
  if (item.opponentIndependenceScore < 0.5) reasons.push("opponent_independence_below_0_50");
  if (item.record.participationConfidence < 0.5) reasons.push("participation_below_0_50");
  if (item.record.venueConfidence < 0.5) reasons.push("venue_below_0_50");
  if (item.matchCompetitiveConfidence < 0.5) reasons.push("competitive_confidence_below_0_50");
  if (item.confidenceBreakdown.dayAnomalyPenalty < 0) reasons.push("same_day_frequency_penalty");
  return reasons.length > 0 ? reasons : ["graduated_policy_zero_weight"];
}

function integrityReasonCodes(player: PlayerRankingAudit) {
  const reasons = new Set(player.certificationReasons);
  const signals = player.sourceRiskSignals;
  if (signals.closedNetworkRatio >= 0.35) reasons.add("closed_network");
  if (signals.repeatedOpponentRatio >= 0.55) reasons.add("repeated_opponent");
  if (signals.opponentIdentityGap >= 0.2) reasons.add("collapsed_opponent_identity");
  if (signals.participationAnomaly >= 0.35) reasons.add("fake_participation_signal");
  if (signals.impossibleTravelRatio > 0) reasons.add("territory_signal");
  if (player.attackProfile === "colluder") reasons.add("collusion_truth_profile");
  if (player.attackProfile === "sybil_operator") reasons.add("sybil_truth_profile");
  if (player.attackProfile === "fake_team_operator") reasons.add("fake_opponent_truth_profile");
  if (player.attackProfile === "team_hopper") reasons.add("team_hopping_truth_profile");
  if (player.attackProfile === "territory_gamer") reasons.add("territory_truth_profile");
  return [...reasons];
}

type PlayerRankingAudit = ReturnType<typeof buildPlayerAudit>;

function buildPlayerAudit(
  world: SyntheticWorld,
  agent: SyntheticAgent,
  input: ReturnType<typeof evaluateSyntheticRanking>["inputs"][number],
  result: ReturnType<typeof evaluateSyntheticRanking>["evaluated"][number],
  graph: ReturnType<typeof evaluateSyntheticRanking>["graph"],
  rule: TrophyRule,
) {
  const matchById = new Map(world.state.matches.map((match) => [match.id, match]));
  const allPlayed = world.state.matches.filter((match) => (
    (match.state === "confirmed" || match.state === "auto_confirmed") && match.participantIds.includes(agent.id)
  ));
  const enriched = enrichCompetitiveEvidence(input, graph).filter(({ record }) => isSeasonScoreEvidence(record));
  const accepted = enriched.filter(({ confidenceWeight }) => confidenceWeight > 0);
  const excluded = enriched.filter(({ confidenceWeight }) => confidenceWeight === 0);
  const network = explainNetworkDiversity(enriched, graph);
  const acceptedLogical = new Set(accepted.map(({ logicalOpponentId }) => logicalOpponentId));
  const acceptedTechnical = new Set(accepted.map(({ record }) => record.opponentTeamId));
  const sourceTechnical = new Set(enriched.map(({ record }) => record.opponentTeamId));
  const sourceLogical = new Set(enriched.map(({ logicalOpponentId }) => logicalOpponentId));
  const asOfWeek = virtualWeek(world.startDate, world.currentDate);
  const latestAcceptedWeek = Math.max(0, ...accepted.map(({ record }) => record.week));
  const latestSourceWeek = Math.max(0, ...enriched.map(({ record }) => record.week));
  const certificationReasons = [...result.certificationReasons];
  const gates: Record<TrophyGate, boolean> = {
    challenges: result.validChallenges >= rule.minimumChallenges,
    confidence: result.competitiveConfidence >= rule.minimumCompetitiveConfidence,
    integrity: !certificationReasons.includes("integrity_anomaly") && !certificationReasons.includes("low_confidence_dependency"),
    logical_opponents: result.logicalOpponents >= rule.minimumLogicalOpponents,
    network_diversity: result.competitionNetworkDiversity >= rule.minimumCompetitionNetworkDiversity,
    recent_activity: asOfWeek - result.latestValidWeek <= rule.recentWeeks,
    reliability: agent.ratingReliability >= rule.minimumRatingReliability,
  };
  const wins = enriched.filter(({ record }) => record.result === 1).length;
  const draws = enriched.filter(({ record }) => record.result === 0.5).length;
  const losses = enriched.length - wins - draws;
  return {
    acceptedEvidence: accepted.length,
    acceptedLogicalOpponents: acceptedLogical.size,
    acceptedTechnicalOpponents: acceptedTechnical.size,
    activityWeeksAgo: asOfWeek - latestAcceptedWeek,
    allMatches: allPlayed.length,
    attackProfile: agent.attackProfile,
    certification: result.certification,
    certificationReasons,
    city: agent.city,
    competitiveConfidence: result.competitiveConfidence,
    competitionNetworkDiversity: result.competitionNetworkDiversity,
    displayName: agent.displayName,
    draws,
    excludedEvidence: excluded.length,
    excludedReasonCounts: countBy(excluded.flatMap((item) => exclusionReason(item, matchById.get(item.record.challengeId)))),
    gates,
    id: agent.id,
    integrityRisk: result.sourceRisk.risk,
    internalMatches: allPlayed.filter(({ kind }) => kind === "internal").length,
    latestAcceptedWeek,
    latestSourceWeek,
    logicalOpponents: result.logicalOpponents,
    losses,
    lowConfidenceEvidenceRatio: result.lowConfidenceEvidenceRatio,
    network,
    persona: agent.persona,
    position: agent.position,
    provinceCode: agent.provinceCode,
    provinceRank: result.provinceRank,
    rankingEligible: result.eligibility.eligible,
    rankingReasons: result.eligibility.reasons,
    ratingReliability: agent.ratingReliability,
    ratingV2: agent.ratingV2,
    score: result.score,
    sourceChallengeEvidence: enriched.length,
    sourceLogicalOpponents: sourceLogical.size,
    sourceRiskClassification: result.sourceRisk.classification,
    sourceRiskSignals: result.sourceRisk.signals,
    sourceTechnicalOpponents: sourceTechnical.size,
    trophyEligible: result.certification === "eligible",
    validChallenges: result.validChallenges,
    wins,
  };
}

function funnelStage(label: string, previous: PlayerRankingAudit[], current: PlayerRankingAudit[], total: number, reason: string) {
  return {
    count: current.length,
    label,
    lossFromPrevious: previous.length - current.length,
    mainReasonForLoss: previous.length === current.length ? "none" : reason,
    percentage: round(current.length / Math.max(1, total) * 100, 1),
  };
}

function buildFunnel(players: PlayerRankingAudit[], rule: TrophyRule) {
  const stages: Array<ReturnType<typeof funnelStage>> = [];
  let previous = players;
  stages.push(funnelStage("Registrados", players, players, players.length, "none"));
  const add = (label: string, predicate: (player: PlayerRankingAudit) => boolean, reason: string) => {
    const current = previous.filter(predicate);
    stages.push(funnelStage(label, previous, current, players.length, reason));
    previous = current;
  };
  add("Jugaron al menos un partido", (player) => player.allMatches >= 1, "sin_partidos_confirmados");
  add("Jugaron al menos un Reto", (player) => player.sourceChallengeEvidence >= 1, "sin_retos_confirmados");
  add("Jugaron 5 Retos", (player) => player.sourceChallengeEvidence >= 5, "menos_de_5_retos");
  add("Jugaron 10 Retos", (player) => player.sourceChallengeEvidence >= 10, "menos_de_10_retos");
  add("15 evidencias Season Score", (player) => player.acceptedEvidence >= RANKING_ELIGIBILITY.minimumValidChallenges, "evidencia_B_excluida");
  add("6 rivales lógicos válidos", (player) => player.acceptedLogicalOpponents >= RANKING_ELIGIBILITY.minimumUniqueOpponents, "menos_de_6_rivales_logicos");
  add("Fiabilidad >= 0,45", (player) => player.ratingReliability >= RANKING_ELIGIBILITY.minimumRatingReliability, "fiabilidad_rating");
  add("Actividad <= 12 semanas", (player) => player.activityWeeksAgo <= RANKING_ELIGIBILITY.recentActivityWeeks, "inactividad_reciente");
  add("Entran en ranking", (player) => player.rankingEligible, "gate_compuesto_ranking");
  add("Llegan a 20 Retos", (player) => player.validChallenges >= 20, "menos_de_20_retos");
  add(`Llegan a ${rule.minimumChallenges} Retos`, (player) => player.gates.challenges, "insufficient_challenges");
  add(`${rule.minimumLogicalOpponents} rivales lógicos`, (player) => player.gates.logical_opponents, "insufficient_logical_opponents");
  add(`Confidence >= ${rule.minimumCompetitiveConfidence}`, (player) => player.gates.confidence, "insufficient_competitive_confidence");
  add(`Diversity >= ${rule.minimumCompetitionNetworkDiversity}`, (player) => player.gates.network_diversity, "insufficient_network_diversity");
  add(`Fiabilidad >= ${rule.minimumRatingReliability}`, (player) => player.gates.reliability, "insufficient_rating_reliability");
  add(`Actividad <= ${rule.recentWeeks} semanas`, (player) => player.gates.recent_activity, "insufficient_recent_activity");
  add("Sin retención de integridad", (player) => player.gates.integrity, "integrity_hold");
  add("Certificables provinciales", (player) => player.trophyEligible, "certification_state");
  return stages;
}

function buildGateDiagnostics(players: PlayerRankingAudit[]) {
  const ranked = players.filter(({ rankingEligible }) => rankingEligible);
  const patterns = countBy(ranked.map((player) => {
    const failed = TROPHY_GATES.filter((gate) => !player.gates[gate]);
    return failed.length === 0 ? "passes_all" : failed.join("+");
  }));
  const gates = TROPHY_GATES.map((gate) => {
    const failed = ranked.filter((player) => !player.gates[gate]);
    return {
      failedOnlyThisGate: failed.filter((player) => TROPHY_GATES.every((other) => other === gate || player.gates[other])).length,
      failedThisAndOthers: failed.filter((player) => TROPHY_GATES.some((other) => other !== gate && !player.gates[other])).length,
      gate,
      passed: ranked.length - failed.length,
      totalFailed: failed.length,
    };
  });
  const baseline = ranked.filter((player) => TROPHY_GATES.every((gate) => player.gates[gate])).length;
  const leaveOneOut = [
    { certificable: baseline, removedGate: "none" },
    ...TROPHY_GATES.map((removedGate) => ({
      certificable: ranked.filter((player) => TROPHY_GATES.every((gate) => gate === removedGate || player.gates[gate])).length,
      removedGate,
    })),
  ];
  return { gates, intersections: patterns, leaveOneOut, rankedPopulation: ranked.length };
}

function confusionMatrix(players: PlayerRankingAudit[]) {
  const attacker = (player: PlayerRankingAudit) => player.attackProfile !== "none";
  const hold = (player: PlayerRankingAudit) => player.certification === "pending_integrity_review";
  return {
    falseNegative: players.filter((player) => attacker(player) && !hold(player)).length,
    falsePositive: players.filter((player) => !attacker(player) && hold(player)).length,
    trueNegative: players.filter((player) => !attacker(player) && !hold(player)).length,
    truePositive: players.filter((player) => attacker(player) && hold(player)).length,
  };
}

function activityClass(challengesPerMonth: number) {
  if (challengesPerMonth >= 3) return "hyperactive";
  if (challengesPerMonth >= 1.5) return "regular";
  if (challengesPerMonth >= 0.5) return "casual";
  return "low_activity";
}

function buildDensity(world: SyntheticWorld, players: PlayerRankingAudit[]) {
  const agents = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const completed = world.state.matches.filter(({ state }) => state === "confirmed" || state === "auto_confirmed");
  const challengeMatches = completed.filter(({ kind }) => kind === "challenge");
  const months = Math.max(1, virtualDaysBetween(world.startDate, world.currentDate) / 30.4375);
  const teamRows = world.state.teams.map((team) => {
    const matches = completed.filter((match) => match.homeTeamId === team.id || match.awayTeamId === team.id);
    const challenges = matches.filter(({ kind }) => kind === "challenge");
    const internal = matches.filter(({ kind }) => kind === "internal");
    const seenOpponents = new Set<string>();
    let newOpponents = 0;
    let repeatedOpponents = 0;
    const participationRatios: number[] = [];
    for (const match of [...challenges].sort((left, right) => left.occurredAt.localeCompare(right.occurredAt))) {
      const opponent = match.homeTeamId === team.id ? match.awayTeamId : match.homeTeamId;
      if (opponent && seenOpponents.has(opponent)) repeatedOpponents += 1;
      else if (opponent) {
        newOpponents += 1;
        seenOpponents.add(opponent);
      }
      const participants = match.participantIds.filter((agentId) => {
        const agent = agents.get(agentId);
        return agent ? matchSide(match, agentId, agent) === (match.homeTeamId === team.id ? "home" : "away") : false;
      }).length;
      participationRatios.push(participants / Math.max(1, team.playerIds.length));
    }
    return {
      activity: team.activity,
      challengeMatches: challenges.length,
      challengesPerMonth: round(challenges.length / months),
      id: team.id,
      internalMatches: internal.length,
      internalPerMonth: round(internal.length / months),
      meanRosterParticipation: round(average(participationRatios), 3),
      name: team.name,
      newOpponentRatio: round(newOpponents / Math.max(1, challenges.length), 3),
      playersPerChallenge: round(average(participationRatios.map((ratio) => ratio * team.playerIds.length))),
      provinceCode: team.provinceCode,
      repeatedOpponentRatio: round(repeatedOpponents / Math.max(1, challenges.length), 3),
      rosterSize: team.playerIds.length,
      uniqueOpponents: seenOpponents.size,
    };
  });
  const activityRows = players.map((player) => {
    const challengesPerMonth = player.sourceChallengeEvidence / months;
    return {
      challengesPerMonth: round(challengesPerMonth),
      class: activityClass(challengesPerMonth),
      id: player.id,
      matchesPerMonth: round(player.allMatches / months),
      rankingEligible: player.rankingEligible,
      trophyEligible: player.trophyEligible,
    };
  });
  return {
    activityScenarios: Object.entries(countBy(activityRows.map(({ class: value }) => value))).map(([classification, count]) => {
      const rows = activityRows.filter((row) => row.class === classification);
      return {
        classification,
        count,
        rankingEligible: rows.filter(({ rankingEligible }) => rankingEligible).length,
        rankingEligiblePercentage: round(rows.filter(({ rankingEligible }) => rankingEligible).length / Math.max(1, rows.length) * 100, 1),
        trophyEligible: rows.filter(({ trophyEligible }) => trophyEligible).length,
        trophyEligiblePercentage: round(rows.filter(({ trophyEligible }) => trophyEligible).length / Math.max(1, rows.length) * 100, 1),
      };
    }),
    challengePlayers: distribution(challengeMatches.map((match) => match.participantIds.length)),
    meanChallengesPerTeam: round(average(teamRows.map(({ challengeMatches: value }) => value))),
    meanRoster: round(average(teamRows.map(({ rosterSize }) => rosterSize))),
    meanRosterParticipation: round(average(teamRows.map(({ meanRosterParticipation }) => meanRosterParticipation)), 3),
    meanUniqueOpponentsPerTeam: round(average(teamRows.map(({ uniqueOpponents }) => uniqueOpponents))),
    months: round(months),
    playerActivity: {
      challengesPerMonth: distribution(activityRows.map(({ challengesPerMonth }) => challengesPerMonth)),
      matchesPerMonth: distribution(activityRows.map(({ matchesPerMonth }) => matchesPerMonth)),
    },
    teamRows,
  };
}

function buildTopCandidates(players: PlayerRankingAudit[]) {
  return [...players]
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, 50)
    .map((player, index) => ({
      activityWeeksAgo: player.activityWeeksAgo,
      certification: player.certification,
      certificationBlockers: player.certificationReasons,
      competitiveConfidence: player.competitiveConfidence,
      displayName: player.displayName,
      integrityRisk: player.integrityRisk,
      logicalOpponents: player.logicalOpponents,
      networkDiversity: player.competitionNetworkDiversity,
      playerId: player.id,
      provinceCode: player.provinceCode,
      provinceRank: player.provinceRank,
      rank: index + 1,
      ratingReliability: player.ratingReliability,
      score: player.score,
      validChallenges: player.validChallenges,
    }));
}

function playerNarrative(player: PlayerRankingAudit) {
  const trajectory = player.wins > player.losses ? "trayectoria positiva"
    : player.wins < player.losses ? "trayectoria adversa" : "trayectoria equilibrada";
  const status = player.trophyEligible ? "certificable"
    : player.certification === "pending_integrity_review" ? "pendiente de integridad"
      : "no certificable";
  return `${player.displayName}, ${player.position}, nivel ${player.ratingV2.toFixed(1)}. ${trajectory}: ${player.wins}V/${player.draws}E/${player.losses}D en ${player.sourceChallengeEvidence} Retos, ${player.logicalOpponents} rivales lógicos y Season Score ${player.score.toFixed(1)}. Estado ${status}: ${player.certificationReasons.join(", ") || "sin bloqueos"}.`;
}

function deterministicSample(players: PlayerRankingAudit[], count: number, salt: string) {
  const score = (id: string) => [...`${salt}:${id}`].reduce((sum, character, index) => sum + character.charCodeAt(0) * (index + 17), 0);
  return [...players].sort((left, right) => score(left.id) - score(right.id) || left.id.localeCompare(right.id)).slice(0, count);
}

export function buildSyntheticRankingFunnelAudit(world: SyntheticWorld, options: AuditOptions = {}) {
  const strategy = options.strategy ?? "exclusion_and_hold";
  const rule = options.trophyRule ?? SYNTHETIC_PROVINCE_TROPHY_RULE;
  const { evaluated, graph, inputs } = evaluateSyntheticRanking(world, { strategy, trophyRule: rule });
  const inputById = new Map(inputs.map((input) => [input.player.id, input]));
  const resultById = new Map(evaluated.map((result) => [result.playerId, result]));
  const players = world.state.agents.filter(({ kind }) => kind === "registered").map((agent) => buildPlayerAudit(
    world,
    agent,
    inputById.get(agent.id)!,
    resultById.get(agent.id)!,
    graph,
    rule,
  ));
  const matchById = new Map(world.state.matches.map((match) => [match.id, match]));
  const agentById = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const teamById = new Map(world.state.teams.map((team) => [team.id, team]));
  const controlMatchIds = new Set(world.state.events.filter((event) => (
    event.eventType === "match_finalized" && event.payload.syntheticEligibilityControl === true
  )).map((event) => event.entityIds[0]).filter((id): id is string => Boolean(id)));
  const challengeDefinitions = [
    { label: "0", maximum: 0 }, { label: "1-4", maximum: 4 }, { label: "5-9", maximum: 9 },
    { label: "10-14", maximum: 14 }, { label: "15-19", maximum: 19 }, { label: "20-24", maximum: 24 },
    { label: "25-29", maximum: 29 }, { label: "30+", maximum: Number.POSITIVE_INFINITY },
  ];
  const opponentDefinitions = [
    { label: "0", maximum: 0 }, { label: "1-2", maximum: 2 }, { label: "3-5", maximum: 5 },
    { label: "6-9", maximum: 9 }, { label: "10-14", maximum: 14 }, { label: "15+", maximum: Number.POSITIVE_INFINITY },
  ];
  const diversityDefinitions = [
    { label: "<0.25", maximum: 0.249999 }, { label: "0.25-0.49", maximum: 0.499999 },
    { label: "0.50-0.67", maximum: 0.679999 }, { label: ">=0.68", maximum: Number.POSITIVE_INFINITY },
  ];
  const reliabilityDefinitions = [
    { label: "<0.45", maximum: 0.449999 }, { label: "0.45-0.54", maximum: 0.549999 },
    { label: "0.55-0.74", maximum: 0.749999 }, { label: ">=0.75", maximum: Number.POSITIVE_INFINITY },
  ];
  const recencyDefinitions = [
    { label: "0-4 semanas", maximum: 4 }, { label: "5-8 semanas", maximum: 8 },
    { label: "9-12 semanas", maximum: 12 }, { label: "13+ semanas", maximum: Number.POSITIVE_INFINITY },
  ];

  const evidenceItems = inputs.flatMap((input) => enrichCompetitiveEvidence(input, graph)
    .filter(({ record }) => isSeasonScoreEvidence(record))
    .map((item) => ({ agentId: input.player.id, item, match: matchById.get(item.record.challengeId) })));
  const excludedItems = evidenceItems.filter(({ item }) => item.confidenceWeight === 0);
  const exclusionReasons = [...new Set(excludedItems.flatMap(({ item, match }) => exclusionReason(item, match)))].map((reason) => {
    const rows = excludedItems.filter(({ item, match }) => exclusionReason(item, match).includes(reason));
    return {
      affectedPlayers: new Set(rows.map(({ agentId }) => agentId)).size,
      attackerEvidence: rows.filter(({ agentId }) => agentById.get(agentId)?.attackProfile !== "none").length,
      evidence: rows.length,
      legitimateEvidence: rows.filter(({ agentId }) => agentById.get(agentId)?.attackProfile === "none").length,
      reason,
    };
  }).sort((left, right) => right.evidence - left.evidence || left.reason.localeCompare(right.reason));
  const evidenceTraces = evidenceItems.map(({ agentId, item, match }) => ({
    accepted: item.confidenceWeight > 0,
    agentId,
    confidenceBreakdown: item.confidenceBreakdown,
    confidenceWeight: round(item.confidenceWeight, 4),
    exclusionReasons: item.confidenceWeight > 0 ? [] : exclusionReason(item, match),
    logicalOpponentId: item.logicalOpponentId,
    matchCompetitiveConfidence: round(item.matchCompetitiveConfidence, 4),
    matchId: item.record.challengeId,
    occurredAt: item.record.occurredAt,
    opponentIndependence: round(item.opponentIndependenceScore, 4),
    opponentTeamId: item.record.opponentTeamId,
    rule: item.confidenceWeight > 0 ? "B_ACCEPTED" : "B_WEAK_EVIDENCE_EXCLUDED",
    status: item.record.status,
    teamId: item.record.teamId,
  }));

  const sourceMissing: Array<{ agentId: string; matchId: string; reason: string }> = [];
  for (const match of world.state.matches.filter((candidate) => (
    candidate.kind === "challenge" && (candidate.state === "confirmed" || candidate.state === "auto_confirmed")
  ))) {
    for (const agentId of match.participantIds) {
      const agent = agentById.get(agentId);
      if (!agent || agent.kind !== "registered") continue;
      const expected = syntheticMatchEvidence(agent, match, teamById, world.startDate);
      if (!expected || expected.opponentIndependence < 0.5 || expected.participationConfidence < 0.5 || expected.venueConfidence < 0.5) continue;
      const exists = inputById.get(agentId)?.records.some(({ challengeId }) => challengeId === match.id);
      if (!exists) sourceMissing.push({ agentId, matchId: match.id, reason: "eligible_source_match_without_ranking_evidence" });
    }
  }

  const confidenceByMatch = new Map<string, typeof evidenceItems>();
  for (const row of evidenceItems) confidenceByMatch.set(row.item.record.challengeId, [...(confidenceByMatch.get(row.item.record.challengeId) ?? []), row]);
  const confidenceRows = [...confidenceByMatch].map(([matchId, rows]) => {
    const attackers = rows.filter(({ agentId }) => agentById.get(agentId)?.attackProfile !== "none").length;
    const component = (key: keyof typeof rows[number]["item"]["confidenceBreakdown"]) => average(rows.map(({ item }) => item.confidenceBreakdown[key]));
    return {
      attacker: attackers > 0,
      components: {
        acceptedChallenge: round(component("acceptedChallenge"), 4),
        agreedTime: round(component("agreedTime"), 4),
        agreedVenue: round(component("agreedVenue"), 4),
        bilateralResult: round(component("bilateralResult"), 4),
        dayAnomalyPenalty: round(component("dayAnomalyPenalty"), 4),
        establishedTeams: round(component("establishedTeams"), 4),
        history: round(component("history"), 4),
        opponentIndependence: round(component("opponentIndependence"), 4),
        participants: round(component("participants"), 4),
      },
      confidence: round(average(rows.map(({ item }) => item.matchCompetitiveConfidence)), 4),
      matchId,
    };
  });
  const confidenceBucketDefinitions = [
    { label: "<0.25", maximum: 0.249999 }, { label: "0.25-0.49", maximum: 0.499999 },
    { label: "0.50-0.74", maximum: 0.749999 }, { label: ">=0.75", maximum: Number.POSITIVE_INFINITY },
  ];
  const confidenceDistribution = confidenceBucketDefinitions.map(({ label }) => ({
    label,
    total: confidenceRows.filter((row) => bucket(row.confidence, confidenceBucketDefinitions) === label).length,
  }));
  const playerConfidenceDistribution = confidenceBucketDefinitions.map(({ label }) => ({
    attackers: evidenceItems.filter(({ agentId, item }) => (
      agentById.get(agentId)?.attackProfile !== "none"
        && bucket(item.matchCompetitiveConfidence, confidenceBucketDefinitions) === label
    )).length,
    label,
    normal: evidenceItems.filter(({ agentId, item }) => (
      agentById.get(agentId)?.attackProfile === "none"
        && bucket(item.matchCompetitiveConfidence, confidenceBucketDefinitions) === label
    )).length,
    total: evidenceItems.filter(({ item }) => bucket(item.matchCompetitiveConfidence, confidenceBucketDefinitions) === label).length,
  }));

  const collapseRows = players.filter((player) => player.sourceTechnicalOpponents >= 10 && player.sourceLogicalOpponents < 10).map((player) => {
    const input = inputById.get(player.id)!;
    const collapsedClusters = new Map<string, Set<string>>();
    for (const item of enrichCompetitiveEvidence(input, graph).filter(({ record }) => isSeasonScoreEvidence(record))) {
      const teams = collapsedClusters.get(item.logicalOpponentId) ?? new Set<string>();
      teams.add(item.record.opponentTeamId);
      collapsedClusters.set(item.logicalOpponentId, teams);
    }
    const collapsedTeamIds = [...collapsedClusters.values()].filter((ids) => ids.size > 1).flatMap((ids) => [...ids]);
    const correct = collapsedTeamIds.length > 0 && collapsedTeamIds.every((teamId) => (
      world.state.teams.find((team) => team.id === teamId)?.integrityClusterId === "synthetic-fake-team-ring"
    ));
    return {
      classification: correct ? "correct_collapse" : collapsedTeamIds.length > 0 ? "suspicious_collapse" : "false_positive",
      collapsedTeamIds,
      displayName: player.displayName,
      logicalOpponents: player.sourceLogicalOpponents,
      playerId: player.id,
      technicalOpponents: player.sourceTechnicalOpponents,
    };
  });

  const pendingPlayers = players.filter(({ certification }) => certification === "pending_integrity_review");
  const pendingDetails = pendingPlayers.map((player) => ({
    affectedMatches: player.excludedEvidence,
    attackProfile: player.attackProfile,
    attacker: player.attackProfile !== "none",
    displayName: player.displayName,
    logicalOpponents: player.logicalOpponents,
    networkDiversity: player.competitionNetworkDiversity,
    networkPattern: `${player.sourceTechnicalOpponents} team_ids -> ${player.sourceLogicalOpponents} logical`,
    playerId: player.id,
    reasonCodes: integrityReasonCodes(player),
    risk: player.integrityRisk,
    riskSignals: player.sourceRiskSignals,
    validChallenges: player.validChallenges,
  }));

  const sampleGroups = [
    ...deterministicSample(players.filter(({ attackProfile }) => attackProfile === "none"), 50, `${world.id}:normal`).map((player) => ({ group: "normal", player })),
    ...[...players].sort((left, right) => right.score - left.score).slice(0, 20).map((player) => ({ group: "good", player })),
    ...[...players].sort((left, right) => left.score - right.score).slice(0, 20).map((player) => ({ group: "bad", player })),
    ...deterministicSample(players.filter(({ attackProfile }) => attackProfile !== "none"), 10, `${world.id}:attacker`).map((player) => ({ group: "attacker", player })),
    ...deterministicSample(pendingPlayers, 10, `${world.id}:pending`).map((player) => ({ group: "pending_integrity_review", player })),
  ];
  const sampleTraces = sampleGroups.map(({ group, player }) => ({
    attackProfile: player.attackProfile,
    confirmedChallenges: player.sourceChallengeEvidence,
    displayName: player.displayName,
    excludedChallenges: player.excludedEvidence,
    exclusionReasons: player.excludedReasonCounts,
    group,
    logicalOpponents: player.sourceLogicalOpponents,
    matchConfidence: player.competitiveConfidence,
    opponentIndependence: player.competitionNetworkDiversity,
    playerId: player.id,
    playedMatches: player.allMatches,
    seasonScoreEvidence: player.acceptedEvidence,
    technicalOpponents: player.sourceTechnicalOpponents,
  }));

  const participation = (() => {
    const completed = world.state.matches.filter(({ state }) => state === "confirmed" || state === "auto_confirmed");
    const rows = completed.flatMap((match) => match.participantIds.map((agentId) => ({ agent: agentById.get(agentId), match })));
    return {
      challengeParticipationsPerRegisteredPlayer: distribution(players.map(({ sourceChallengeEvidence }) => sourceChallengeEvidence)),
      guests: rows.filter(({ agent }) => agent?.kind === "guest").length,
      internal: rows.filter(({ match }) => match.kind === "internal").length,
      registered: rows.filter(({ agent }) => agent?.kind === "registered").length,
      retos: rows.filter(({ match }) => match.kind === "challenge").length,
      total: rows.length,
    };
  })();
  const gateDiagnostics = buildGateDiagnostics(players);
  const density = buildDensity(world, players);
  const topCandidates = buildTopCandidates(players);
  const provinceComparison = [...new Set(players.map(({ provinceCode }) => provinceCode))].sort().map((provinceCode) => {
    const rows = players.filter((player) => player.provinceCode === provinceCode);
    return {
      medianChallenges: round(percentile(rows.map(({ sourceChallengeEvidence }) => sourceChallengeEvidence), 0.5)),
      medianConfidence: round(percentile(rows.map(({ competitiveConfidence }) => competitiveConfidence), 0.5)),
      medianDiversity: round(percentile(rows.map(({ competitionNetworkDiversity }) => competitionNetworkDiversity), 0.5)),
      medianLogicalOpponents: round(percentile(rows.map(({ sourceLogicalOpponents }) => sourceLogicalOpponents), 0.5)),
      pendingIntegrityReview: rows.filter(({ certification }) => certification === "pending_integrity_review").length,
      provinceCode,
      rankingEligible: rows.filter(({ rankingEligible }) => rankingEligible).length,
      registered: rows.length,
      trophyEligible: rows.filter(({ trophyEligible }) => trophyEligible).length,
    };
  });
  const organicEligible = controlMatchIds.size === 0
    ? players.filter(({ trophyEligible }) => trophyEligible).length
    : evaluateSyntheticRanking({
      ...world,
      state: {
        ...world.state,
        matches: world.state.matches.filter(({ id }) => !controlMatchIds.has(id)),
      },
    }, { strategy, trophyRule: rule }).evaluated.filter(({ certification }) => certification === "eligible").length;
  const topBarcelonaNarrative = [...players]
    .filter(({ provinceCode }) => provinceCode === "08")
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, 20)
    .map((player) => ({ narrative: playerNarrative(player), playerId: player.id }));

  return {
    checkpoint: {
      controlMatches: controlMatchIds.size,
      eventSequence: world.state.eventSequence,
      revision: world.revision,
      worldId: world.id,
    },
    confidence: {
      componentAverages: Object.fromEntries(Object.keys(confidenceRows[0]?.components ?? {}).map((key) => [
        key,
        round(average(confidenceRows.map((row) => row.components[key as keyof typeof row.components])), 4),
      ])),
      matchDistribution: confidenceDistribution,
      playerEvidenceDistribution: playerConfidenceDistribution,
    },
    density,
    evidence: {
      excludedByReason: exclusionReasons,
      excludedPlayerMatchEvidence: excludedItems.length,
      matchLevelChallengeEvidence: world.state.matches.filter((match) => match.kind === "challenge" && (match.state === "confirmed" || match.state === "auto_confirmed")).length,
      matchLevelMarkedExcluded: world.state.matches.filter((match) => match.kind === "challenge" && (match.state === "confirmed" || match.state === "auto_confirmed") && match.evidenceExcluded).length,
      matchLevelMarkedValid: world.state.matches.filter((match) => match.kind === "challenge" && (match.state === "confirmed" || match.state === "auto_confirmed") && !match.evidenceExcluded).length,
      playerMatchAccepted: evidenceItems.length - excludedItems.length,
      playerMatchSource: evidenceItems.length,
      sourceMatchesWithoutEvidence: sourceMissing,
    },
    evidenceTraces,
    funnel: buildFunnel(players, rule),
    gates: gateDiagnostics,
    integrity: {
      confusionAllRegistered: confusionMatrix(players),
      confusionRankingEligible: confusionMatrix(players.filter(({ rankingEligible }) => rankingEligible)),
      falseNegativeAttackers: players.filter((player) => player.attackProfile !== "none" && player.certification !== "pending_integrity_review").map(({ displayName, id, rankingEligible }) => ({ displayName, playerId: id, rankingEligible })),
      falsePositiveHolds: pendingPlayers.filter(({ attackProfile }) => attackProfile === "none").map(({ displayName, id }) => ({ displayName, playerId: id })),
      pendingByReason: countBy(pendingDetails.flatMap(({ reasonCodes }) => reasonCodes)),
      pendingDetails,
    },
    opponents: {
      collapseClassification: countBy(collapseRows.map(({ classification }) => classification)),
      collapseRows,
      logicalDistribution: bucketRows(players, (player) => player.sourceLogicalOpponents, opponentDefinitions),
      technicalDistribution: bucketRows(players, (player) => player.sourceTechnicalOpponents, opponentDefinitions),
    },
    participation,
    playerDistributions: {
      activityRecency: bucketRows(players, (player) => player.activityWeeksAgo, recencyDefinitions),
      networkDiversity: bucketRows(players, (player) => player.competitionNetworkDiversity, diversityDefinitions),
      ratingReliability: bucketRows(players, (player) => player.ratingReliability, reliabilityDefinitions),
    },
    players,
    provinceComparison,
    retosDistribution: {
      accepted: bucketRows(players, (player) => player.acceptedEvidence, challengeDefinitions),
      source: bucketRows(players, (player) => player.sourceChallengeEvidence, challengeDefinitions),
    },
    sampleTraces,
    stateMeaning: {
      eligible: "Aparece en ranking y cumple certificación/trofeo provincial sin hold.",
      notEligible: "Aparece en ranking, pero no cumple uno o más gates no-integrity de certificación provincial.",
      pendingIntegrityReview: "Aparece en ranking y cumple los gates no-integrity; el trofeo queda retenido por diversidad, dependencia de evidencia débil o riesgo.",
      scope: "Los tres estados almacenados en las 135 filas describen certificación provincial. La presencia de la fila y provinceRank describen elegibilidad de ranking.",
    },
    strategy,
    topBarcelonaNarrative,
    topCandidates,
    totals: {
      organicEligible,
      pendingIntegrityReview: pendingPlayers.length,
      rankingEligible: players.filter(({ rankingEligible }) => rankingEligible).length,
      registered: players.length,
      trophyEligible: players.filter(({ trophyEligible }) => trophyEligible).length,
    },
    trophyRule: rule,
  };
}

export type SyntheticRankingFunnelAudit = ReturnType<typeof buildSyntheticRankingFunnelAudit>;
