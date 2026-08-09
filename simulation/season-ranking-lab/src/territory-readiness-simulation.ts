import { isSeasonScoreEvidence } from "./engine";
import type {
  ContextualNetworkCandidate,
  EcosystemDataset,
} from "./network-diversity-v31";
import type { TerritoryReadinessSignals } from "./territory-award-readiness";

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

export function networkDatasetReadinessSignals(options: {
  candidates: ContextualNetworkCandidate[];
  dataset: EcosystemDataset;
  provinceCode?: string;
}): TerritoryReadinessSignals {
  const provinceCode = options.provinceCode ?? "08";
  const profiles = options.dataset.profiles.filter((profile) => profile.provinceCode === provinceCode);
  const teamIds = new Set(profiles.map(({ id }) => id));
  const rows = options.candidates.filter((candidate) => candidate.provinceCode === provinceCode);
  const technicalEdges = new Set<string>();
  const independentEdges = new Set<string>();
  const independentlyConnectedTeams = new Set<string>();

  for (const teamId of teamIds) {
    for (const opponentId of options.dataset.graph.matchNeighbors.get(teamId) ?? []) {
      if (!teamIds.has(opponentId) || teamId >= opponentId) continue;
      technicalEdges.add(`${teamId}|${opponentId}`);
      const leftLogical = options.dataset.graph.logicalOpponentByTeam.get(teamId) ?? teamId;
      const rightLogical = options.dataset.graph.logicalOpponentByTeam.get(opponentId) ?? opponentId;
      if (leftLogical === rightLogical) continue;
      independentEdges.add([leftLogical, rightLogical].sort().join("|"));
      independentlyConnectedTeams.add(teamId);
      independentlyConnectedTeams.add(opponentId);
    }
  }

  const evidence = options.dataset.inputs
    .filter(({ player }) => rows.some(({ id }) => id === player.id))
    .flatMap(({ records }) => records.filter(isSeasonScoreEvidence));
  const weeks = evidence.map(({ week }) => week);
  const observedHistoryWeeks = weeks.length === 0 ? 0 : Math.max(...weeks) - Math.min(...weeks) + 1;

  return {
    activePlayers: rows.length,
    activeTeams: teamIds.size,
    awardCandidatePlayers: rows.filter(({ nonNetworkTrophyEligible }) => nonNetworkTrophyEligible).length,
    independentOpponentEdges: independentEdges.size,
    independentTeamCoverage: round(independentlyConnectedTeams.size / Math.max(1, teamIds.size)),
    logicalOpponentEdges: technicalEdges.size,
    medianChallenges: round(median(rows.map(({ validChallenges }) => validChallenges)), 2),
    medianCompetitiveConfidence: round(median(rows.map(({ matchConfidence }) => matchConfidence))),
    medianLogicalOpponents: round(median(rows.map(({ network }) => network.logicalOpponentCount)), 2),
    observedHistoryWeeks,
    rankingEligiblePlayers: rows.filter(({ rankingEligible }) => rankingEligible).length,
    validChallenges: new Set(evidence.map(({ challengeId }) => challengeId)).size,
  };
}
