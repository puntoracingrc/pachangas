import type { ContextualNetworkCandidate } from "../../season-ranking-lab/src/network-diversity-v31";
import {
  createTerritoryReadinessSnapshot,
  type TerritoryReadinessSignals,
  type TerritoryReadinessSnapshot,
} from "../../season-ranking-lab/src/territory-award-readiness";
import { syntheticWorldNetworkCandidates } from "./network-health-v31";
import type { SyntheticWorld } from "./types";

function median(values: number[]) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1]! + sorted[middle]!) / 2
    : sorted[middle]!;
}

function round(value: number, digits = 4) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

export function syntheticWorldTerritorySignals(
  world: SyntheticWorld,
  candidates: ContextualNetworkCandidate[],
  provinceCode: string,
): TerritoryReadinessSignals {
  const teams = world.state.teams.filter(({ provinceCode: code }) => code === provinceCode);
  const teamById = new Map(teams.map((team) => [team.id, team]));
  const teamIds = new Set(teamById.keys());
  const rows = candidates.filter((candidate) => candidate.provinceCode === provinceCode);
  const validMatches = world.state.matches.filter((match) => (
    match.kind === "challenge"
    && !match.evidenceExcluded
    && (match.state === "confirmed" || match.state === "auto_confirmed")
    && match.awayTeamId
    && teamIds.has(match.homeTeamId)
    && teamIds.has(match.awayTeamId)
  ));
  const technicalEdges = new Set<string>();
  const independentEdges = new Set<string>();
  const independentlyConnectedTeams = new Set<string>();
  for (const match of validMatches) {
    const awayTeamId = match.awayTeamId!;
    technicalEdges.add([match.homeTeamId, awayTeamId].sort().join("|"));
    const homeCluster = teamById.get(match.homeTeamId)?.integrityClusterId ?? match.homeTeamId;
    const awayCluster = teamById.get(awayTeamId)?.integrityClusterId ?? awayTeamId;
    if (homeCluster === awayCluster) continue;
    independentEdges.add([homeCluster, awayCluster].sort().join("|"));
    independentlyConnectedTeams.add(match.homeTeamId);
    independentlyConnectedTeams.add(awayTeamId);
  }
  const times = validMatches.map(({ occurredAt }) => Date.parse(occurredAt)).filter(Number.isFinite);
  const observedHistoryWeeks = times.length === 0 ? 0
    : Math.max(1, Math.ceil((Math.max(...times) - Math.min(...times)) / (7 * 24 * 60 * 60 * 1_000)) + 1);

  return {
    activePlayers: world.state.agents.filter((agent) => (
      agent.kind === "registered" && agent.provinceCode === provinceCode && agent.status === "active"
    )).length,
    activeTeams: teams.filter(({ activity }) => activity !== "abandoned").length,
    awardCandidatePlayers: rows.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible).length,
    independentOpponentEdges: independentEdges.size,
    independentTeamCoverage: round(independentlyConnectedTeams.size / Math.max(1, teamIds.size)),
    logicalOpponentEdges: technicalEdges.size,
    medianChallenges: round(median(rows.map(({ validChallenges }) => validChallenges)), 2),
    medianCompetitiveConfidence: round(median(rows.map(({ matchConfidence }) => matchConfidence))),
    medianLogicalOpponents: round(median(rows.map(({ network }) => network.logicalOpponentCount)), 2),
    observedHistoryWeeks,
    rankingEligiblePlayers: rows.filter(({ rankingEligible }) => rankingEligible).length,
    validChallenges: rows.reduce((sum, candidate) => sum + candidate.validChallenges, 0),
  };
}

export function buildSyntheticTerritoryReadiness(world: SyntheticWorld) {
  const { candidates } = syntheticWorldNetworkCandidates(world);
  const provinceCodes = [...new Set(world.state.teams.map(({ provinceCode }) => provinceCode))].sort();
  const rankingByAgent = new Map(world.state.rankings.map((row) => [row.agentId, row]));
  const agentById = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  return provinceCodes.map((provinceCode) => {
    const signals = syntheticWorldTerritorySignals(world, candidates, provinceCode);
    const snapshot = createTerritoryReadinessSnapshot({
      calculatedAt: world.currentDate,
      season: world.seasonId,
      signals,
      territory: provinceCode,
    });
    const ranking = candidates
      .filter((candidate) => candidate.provinceCode === provinceCode && candidate.rankingEligible)
      .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
      .slice(0, 50)
      .map((candidate, index) => ({
        displayName: agentById.get(candidate.id)?.displayName ?? candidate.id,
        logicalOpponents: candidate.network.logicalOpponentCount,
        movement: rankingByAgent.get(candidate.id)?.movement ?? 0,
        playerId: candidate.id,
        rank: index + 1,
        score: candidate.score,
        validChallenges: candidate.validChallenges,
      }));
    const unranked = candidates
      .filter((candidate) => candidate.provinceCode === provinceCode && !candidate.rankingEligible)
      .slice(0, 12)
      .map((candidate) => ({
        displayName: agentById.get(candidate.id)?.displayName ?? candidate.id,
        missingChallenges: Math.max(0, 15 - candidate.validChallenges),
        missingLogicalOpponents: Math.max(0, 6 - candidate.network.logicalOpponentCount),
        playerId: candidate.id,
      }));
    return { provinceCode, ranking, snapshot, unranked };
  });
}

export function appendSyntheticReadinessSnapshot(options: {
  calculatedAt: string;
  history: TerritoryReadinessSnapshot[];
  season: string;
  signals: TerritoryReadinessSignals;
  territory: string;
}) {
  return createTerritoryReadinessSnapshot(options);
}
