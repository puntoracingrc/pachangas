import {
  RANKING_ELIGIBILITY,
  TROPHY_RULES,
  buildOpponentGraph,
  evaluateV3Ranking,
  type EvidenceStrategy,
  type TeamIntegrityProfile,
  type TrophyRule,
} from "../../season-ranking-lab/src/integrity-v3";
import type { PlayerMatchEvidence, SeasonPlayerInput, SeasonScoreConfig } from "../../season-ranking-lab/src/types";
import { virtualDaysBetween, virtualWeek } from "./clock";
import { clamp } from "./random";
import type { SyntheticAgent, SyntheticMatch, SyntheticRankingRow, SyntheticTeam, SyntheticWorld } from "./types";

export const SYNTHETIC_SEASON_SCORE_CONFIG: SeasonScoreConfig = {
  densityTop10Minimum: 50,
  eligibility: { ...RANKING_ELIGIBILITY },
  id: "season-score-v3-55-30-15",
  integrityMode: "weighted",
  label: "55/30/15 · recent30 · synthetic world",
  opponentDecay: [1, 1, 0.5, 0.25, 0],
  ratingConfidenceModel: "full",
  volumeModel: "recent_30",
  weights: { competition: 30, opposition: 15, quality: 55 },
};
export const SYNTHETIC_PROVINCE_TROPHY_RULE = TROPHY_RULES.province;

export function syntheticTeamIntegrityProfiles(teams: SyntheticTeam[]): TeamIntegrityProfile[] {
  return teams.map((team, index) => ({
    adminIds: team.adminAgentIds,
    createdDaysAgo: team.integrityClusterId === "synthetic-fake-team-ring" ? 18 + index % 8 : 220 + (index * 79) % 1_400,
    id: team.id,
    ownerId: team.ownerAgentId,
    playerIds: team.playerIds,
    provinceCode: team.provinceCode,
    sportsClusterId: team.integrityClusterId,
    venueClusterId: `province:${team.provinceCode}`,
  }));
}

function sideForAgent(match: SyntheticMatch, agentId: string, teams: Map<string, SyntheticTeam>) {
  const home = teams.get(match.homeTeamId);
  const away = match.awayTeamId ? teams.get(match.awayTeamId) : null;
  if (away?.playerIds.includes(agentId) && !home?.playerIds.includes(agentId)) return "away" as const;
  return "home" as const;
}

export function syntheticMatchEvidence(
  agent: SyntheticAgent,
  match: SyntheticMatch,
  teams: Map<string, SyntheticTeam>,
  startDate: string,
): PlayerMatchEvidence | null {
  if (match.kind !== "challenge" || !match.awayTeamId || match.homeGoals === null || match.awayGoals === null) return null;
  const side = sideForAgent(match, agent.id, teams);
  const team = teams.get(side === "home" ? match.homeTeamId : match.awayTeamId);
  const opponent = teams.get(side === "home" ? match.awayTeamId : match.homeTeamId);
  if (!team || !opponent) return null;
  const ownGoals = side === "home" ? match.homeGoals : match.awayGoals;
  const opponentGoals = side === "home" ? match.awayGoals : match.homeGoals;
  const result = ownGoals === opponentGoals ? 0.5 : ownGoals > opponentGoals ? 1 : 0;
  const suspicious = agent.attackProfile === "ghost_participant" || match.evidenceExcluded;
  return {
    challengeId: match.id,
    goals: match.scorerGoals[agent.id] ?? 0,
    individualPerformanceIndex: Math.round(Object.values(agent.facets).reduce((sum, value) => sum + value, 0) / 6),
    kind: "challenge",
    occurredAt: match.occurredAt,
    opponentClusterId: opponent.integrityClusterId,
    opponentIndependence: opponent.integrityClusterId === "synthetic-fake-team-ring" ? 0.12 : 0.92,
    opponentRating: opponent.strength,
    opponentTeamId: opponent.id,
    participated: true,
    participationConfidence: suspicious ? 0.32 : clamp(match.confidence + 0.08, 0, 1),
    provinceCode: match.provinceCode,
    result,
    status: match.state === "auto_confirmed" ? "auto_confirmed" : match.state === "confirmed" ? "confirmed" : "disputed",
    teamGoalDifference: ownGoals - opponentGoals,
    teamId: team.id,
    teamRating: team.strength,
    venueConfidence: match.evidenceExcluded ? 0.3 : clamp(match.confidence + 0.12, 0, 1),
    week: virtualWeek(startDate, match.occurredAt),
  };
}

export function seasonInputs(world: SyntheticWorld): SeasonPlayerInput[] {
  const teams = new Map(world.state.teams.map((team) => [team.id, team]));
  const eligibleMatches = world.state.matches.filter((match) => (
    match.participantIds.length > 0 && (match.state === "confirmed" || match.state === "auto_confirmed")
  ));
  return world.state.agents.filter((agent) => agent.kind === "registered").map((agent) => ({
    player: {
      accountAgeDays: Math.max(1, 360 + virtualDaysBetween(world.startDate, world.currentDate) - Number(agent.persona === "newcomer") * 330),
      id: agent.id,
      joinedSeasonIndex: virtualWeek(world.startDate, agent.availableFrom),
      latentSkill: agent.ratingV2,
      mobility: Math.min(1, agent.teamIds.length / 3),
      position: agent.position,
      ratingReliability: agent.ratingReliability,
      ratingV2: agent.ratingV2,
      teamIds: agent.teamIds,
    },
    previousCompetitiveProvinceCode: world.state.rankings.find((row) => row.agentId === agent.id)?.provinceCode ?? agent.provinceCode,
    records: eligibleMatches
      .filter((match) => match.participantIds.includes(agent.id))
      .map((match) => syntheticMatchEvidence(agent, match, teams, world.startDate))
      .filter((record): record is PlayerMatchEvidence => Boolean(record)),
    seasonId: world.seasonId,
  }));
}

export function calculateRankings(world: SyntheticWorld, options: {
  strategy?: EvidenceStrategy;
  trophyRule?: TrophyRule;
} = {}): SyntheticRankingRow[] {
  const { evaluated } = evaluateSyntheticRanking(world, options);
  const previous = new Map(world.state.rankings.map((row) => [row.agentId, row.rank]));
  const visible = evaluated.filter(({ provinceRank }) => provinceRank !== null);
  return visible.map((result): SyntheticRankingRow => {
    const rank = result.provinceRank ?? result.nationalRank ?? Number.MAX_SAFE_INTEGER;
    return {
      agentId: result.playerId,
      certification: result.certification,
      certificationReasons: result.certificationReasons,
      competition: result.components.competition,
      integrityRisk: result.sourceRisk.risk,
      logicalOpponents: result.logicalOpponents,
      movement: (previous.get(result.playerId) ?? rank) - rank,
      opposition: result.components.opposition,
      provinceCode: result.competitiveProvinceCode ?? "UNASSIGNED",
      quality: result.components.quality,
      rank,
      score: result.score,
      validChallenges: result.validChallenges,
    };
  }).sort((left, right) => left.provinceCode.localeCompare(right.provinceCode) || left.rank - right.rank || left.agentId.localeCompare(right.agentId));
}

export function evaluateSyntheticRanking(world: SyntheticWorld, options: {
  strategy?: EvidenceStrategy;
  trophyRule?: TrophyRule;
} = {}) {
  const inputs = seasonInputs(world);
  const graph = buildOpponentGraph(syntheticTeamIntegrityProfiles(world.state.teams), inputs);
  const evaluated = evaluateV3Ranking({
    asOfWeek: virtualWeek(world.startDate, world.currentDate),
    config: SYNTHETIC_SEASON_SCORE_CONFIG,
    graph,
    inputs,
    phase: world.status === "completed" ? "awards_certified" : "active",
    strategy: options.strategy ?? "exclusion_and_hold",
    trophyRule: options.trophyRule ?? SYNTHETIC_PROVINCE_TROPHY_RULE,
  });
  return { evaluated, graph, inputs };
}
