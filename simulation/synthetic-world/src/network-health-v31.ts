import {
  NETWORK_MODEL_IDS,
  compareNetworkModels,
  contextualizeNetworkCandidates,
  decideNetworkModel,
  type ContextualNetworkCandidate,
  type NetworkCandidateInput,
  type NetworkModelId,
} from "../../season-ranking-lab/src/network-diversity-v31";
import { cloneSyntheticWorldFromCurrent } from "./engine";
import { deterministicUuid } from "./random";
import { buildSyntheticRankingFunnelAudit } from "./ranking-funnel";
import type { SyntheticWorld } from "./types";

function executedAbuse(player: ReturnType<typeof buildSyntheticRankingFunnelAudit>["players"][number]) {
  if (player.attackProfile === "none") return false;
  const signals = player.sourceRiskSignals;
  return player.sourceRiskClassification === "suspicious"
    || player.sourceRiskClassification === "high_risk"
    || signals.abnormalMatchFrequency >= 0.35
    || signals.closedNetworkRatio >= 0.35
    || signals.impossibleTravelRatio >= 0.25
    || signals.opponentIdentityGap >= 0.2
    || signals.participationAnomaly >= 0.35
    || signals.ratingVsExternalEvidence >= 0.2
    || signals.venueAnomaly >= 0.5;
}

export function syntheticWorldNetworkCandidates(world: SyntheticWorld) {
  const audit = buildSyntheticRankingFunnelAudit(world);
  const agentById = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const candidates = contextualizeNetworkCandidates(audit.players.map((player): NetworkCandidateInput => ({
    currentCertification: player.certification,
    executedAbuse: executedAbuse(player),
    id: player.id,
    lowConfidenceEvidenceRatio: player.lowConfidenceEvidenceRatio,
    matchConfidence: player.competitiveConfidence,
    network: player.network,
    nonNetworkTrophyEligible: player.rankingEligible
      && player.gates.challenges
      && player.gates.logical_opponents
      && player.gates.confidence
      && player.gates.reliability
      && player.gates.recent_activity
      && player.lowConfidenceEvidenceRatio <= 0.2,
    provinceCode: player.provinceCode,
    rankingEligible: player.rankingEligible,
    score: player.score,
    sourceRisk: {
      classification: player.sourceRiskClassification,
      risk: player.integrityRisk,
      signals: player.sourceRiskSignals,
    },
    teamIds: [...(agentById.get(player.id)?.teamIds ?? [])],
    validChallenges: player.validChallenges,
  })));
  return { audit, candidates };
}

function networkExplanation(row: ContextualNetworkCandidate, modelId: NetworkModelId) {
  const decision = decideNetworkModel(row, modelId);
  const broad = row.network.broadConnectedOpponents;
  const concentration = Math.round(row.network.opponentConcentration * row.validChallenges);
  return {
    decision,
    text: `${row.network.logicalOpponentCount} rivales lógicos; ${broad} Team IDs con conexiones externas; ${concentration}/${row.validChallenges} evidencias en el rival dominante; oportunidad ${Math.round(row.network.ecosystemOpportunity * 100)}%.`,
  };
}

export function networkCandidateStatus(row: ContextualNetworkCandidate, modelId: NetworkModelId) {
  if (!row.nonNetworkTrophyEligible) return "NO CANDIDATO" as const;
  return decideNetworkModel(row, modelId).hold ? "HOLD" as const : "CERTIFICABLE" as const;
}

function networkGraph(world: SyntheticWorld, rows: ContextualNetworkCandidate[], modelId: NetworkModelId, provinceCode = "08") {
  const teams = world.state.teams.filter((team) => team.provinceCode === provinceCode);
  const teamIds = new Set(teams.map(({ id }) => id));
  const edgeCounts = new Map<string, number>();
  for (const match of world.state.matches.filter((match) => (
    match.kind === "challenge"
    && (match.state === "confirmed" || match.state === "auto_confirmed")
    && match.awayTeamId
    && teamIds.has(match.homeTeamId)
    && teamIds.has(match.awayTeamId)
  ))) {
    const key = [match.homeTeamId, match.awayTeamId!].sort().join("|");
    edgeCounts.set(key, (edgeCounts.get(key) ?? 0) + 1);
  }
  const candidateByTeam = new Map<string, ContextualNetworkCandidate[]>();
  for (const row of rows.filter((candidate) => candidate.provinceCode === provinceCode)) {
    const agent = world.state.agents.find(({ id }) => id === row.id);
    for (const teamId of agent?.teamIds ?? []) candidateByTeam.set(teamId, [...(candidateByTeam.get(teamId) ?? []), row]);
  }
  const degrees = new Map<string, number>();
  for (const key of edgeCounts.keys()) {
    const [left, right] = key.split("|");
    degrees.set(left!, (degrees.get(left!) ?? 0) + 1);
    degrees.set(right!, (degrees.get(right!) ?? 0) + 1);
  }
  const ordered = [...teams].sort((left, right) => left.integrityClusterId.localeCompare(right.integrityClusterId) || left.id.localeCompare(right.id));
  return {
    edges: [...edgeCounts].map(([key, matches]) => {
      const [source, target] = key.split("|");
      return { matches, source: source!, target: target! };
    }),
    nodes: ordered.map((team, index) => {
      const candidates = candidateByTeam.get(team.id) ?? [];
      const hold = candidates.some((row) => decideNetworkModel(row, modelId).hold);
      const top = candidates.some((row) => row.rankingEligible && row.score >= Math.min(...rows.filter((candidate) => candidate.provinceCode === provinceCode && candidate.rankingEligible).sort((left, right) => right.score - left.score).slice(0, 10).map(({ score }) => score)));
      const angle = (index / Math.max(1, ordered.length)) * Math.PI * 2;
      const radius = 37 + (index % 3) * 5;
      return {
        cluster: team.integrityClusterId,
        degree: degrees.get(team.id) ?? 0,
        hold,
        id: team.id,
        label: team.name,
        possibleRing: team.integrityClusterId === "synthetic-fake-team-ring",
        topCandidate: top,
        x: Math.round(50 + Math.cos(angle) * radius),
        y: Math.round(50 + Math.sin(angle) * radius),
      };
    }),
    provinceCode,
  };
}

export function buildSyntheticNetworkV31Audit(world: SyntheticWorld, researchReference: NetworkModelId = "model_3_relative_floor") {
  const { audit, candidates } = syntheticWorldNetworkCandidates(world);
  const byId = new Map(candidates.map((row) => [row.id, row]));
  const modelMetrics = compareNetworkModels(candidates);
  const legitimateHolds = audit.integrity.falsePositiveHolds.map(({ displayName, playerId }) => {
    const row = byId.get(playerId)!;
    return { displayName, explanation: networkExplanation(row, researchReference), ...row };
  });
  const attackers = audit.players.filter(({ attackProfile }) => attackProfile !== "none").map((player) => {
    const row = byId.get(player.id)!;
    return { attackProfile: player.attackProfile, displayName: player.displayName, explanation: networkExplanation(row, researchReference), ...row };
  });
  const topBarcelona = [...audit.players]
    .filter(({ provinceCode }) => provinceCode === "08")
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, 20)
    .map((player, index) => {
      const row = byId.get(player.id)!;
      const explanation = networkExplanation(row, researchReference);
      const status = networkCandidateStatus(row, researchReference);
      return { displayName: player.displayName, explanation, playerId: player.id, rank: index + 1, score: player.score, status };
    });
  const provinceReadiness = [...new Set(candidates.map(({ provinceCode }) => provinceCode))].map((provinceCode) => {
    const territory = candidates.filter((row) => row.provinceCode === provinceCode);
    const rankingEligible = territory.filter(({ rankingEligible }) => rankingEligible).length;
    const certifiable = territory.filter((row) => decideNetworkModel(row, researchReference).certified).length;
    const activeTeams = Math.max(0, ...territory.map(({ network }) => network.territorialActiveTeams));
    return {
      activeTeams,
      certifiable,
      provinceCode,
      rankingEligible,
      state: rankingEligible < 10 ? "ranking_active" : certifiable >= 10 ? "trophy_ready" : "trophy_not_ready",
    };
  });
  return {
    attackers,
    candidates,
    currentAudit: { checkpoint: audit.checkpoint, totals: audit.totals },
    executedAttackers: attackers.filter(({ executedAbuse: value }) => value).length,
    graph: networkGraph(world, candidates, researchReference),
    legitimateHolds,
    modelMetrics,
    provinceReadiness,
    researchReference,
    topBarcelona,
  };
}

export function createNetworkModelClone(source: SyntheticWorld, modelId: NetworkModelId, index: number) {
  const seed = 20261200 + index;
  const clone = cloneSyntheticWorldFromCurrent(source, seed, `${source.name} · V3.1 ${modelId}`);
  const { candidates } = syntheticWorldNetworkCandidates(clone);
  const byId = new Map(candidates.map((row) => [row.id, row]));
  clone.state.rankings = clone.state.rankings.map((ranking) => {
    const row = byId.get(ranking.agentId);
    if (!row) return ranking;
    const decision = decideNetworkModel(row, modelId);
    if (!row.nonNetworkTrophyEligible) return ranking;
    return {
      ...ranking,
      certification: decision.hold ? "pending_integrity_review" : "eligible",
      certificationReasons: decision.hold ? decision.reasons.map((reason) => `v31_${reason}`) : [],
    };
  });
  clone.state.eventSequence += 1;
  clone.state.events.push({
    actorAgentId: null,
    entityIds: [source.id, clone.id],
    eventType: "ranking_v31_model_clone_created",
    expected: { sourceRevision: source.revision },
    flow: "ranking.network_v31_counterfactual",
    operationId: deterministicUuid(`${clone.id}:network-v31`, modelId),
    payload: { formulasChanged: false, modelId, ratingV2Changed: false, sourceWorldId: source.id },
    sequence: clone.state.eventSequence,
    status: "pass",
    virtualDate: clone.currentDate,
  });
  return clone;
}

export function networkModelIds() {
  return [...NETWORK_MODEL_IDS];
}
