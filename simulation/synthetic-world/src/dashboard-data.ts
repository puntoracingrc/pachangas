import { syntheticWorldSummary } from "./engine";
import networkHealthV31Summary from "../generated/network-diversity-v3.1-summary.json";
import rankingFunnelSummary from "../generated/ranking-funnel-v1.1-summary.json";
import territoryAwardReadinessSummary from "../generated/territory-award-readiness-v1-summary.json";
import { buildSyntheticRankingFunnelAudit } from "./ranking-funnel";
import { rankingAuditOptionsForWorld } from "./ranking-counterfactuals";
import type { SyntheticSnapshotListItem, SyntheticWorldListItem } from "./store";
import type { SyntheticEvent, SyntheticWorld } from "./types";

const HEALTH_AREAS = [
  ["auth", ["auth."]],
  ["team", ["team."]],
  ["challenges", ["challenge."]],
  ["market", ["market."]],
  ["matches", ["match.", "attendance."]],
  ["results", ["result."]],
  ["guests", ["guest.", "conduct.guest_withdrawal"]],
  ["ratings", ["rating."]],
  ["achievements", ["achievement."]],
  ["rewards", ["reward."]],
  ["notifications", ["notification.", "attendance.joined_notification", "attendance.cancelled_notification", "attendance.injury_notification"]],
  ["rankings", ["ranking."]],
  ["integrity", ["integrity.", "invariant."]],
  ["RLS", ["rls."]],
  ["temporal flows", ["simulation.clock", "invariant.daily", "invariant.weekly"]],
] as const;

function countBy(values: string[]) {
  const result: Record<string, number> = {};
  for (const value of values) result[value] = (result[value] ?? 0) + 1;
  return result;
}

export type SyntheticDashboardData = ReturnType<typeof buildSyntheticDashboardData>;

const rankingAuditCache = new Map<string, ReturnType<typeof buildSyntheticRankingFunnelAudit>>();

function rankingAudit(world: SyntheticWorld) {
  const scenario = world.config.rankingAuditScenario?.id ?? "source";
  const key = `${world.id}:${world.revision}:${world.state.eventSequence}:${scenario}`;
  const cached = rankingAuditCache.get(key);
  if (cached) return cached;
  const audit = buildSyntheticRankingFunnelAudit(world, rankingAuditOptionsForWorld(world));
  rankingAuditCache.clear();
  rankingAuditCache.set(key, audit);
  return audit;
}

export function buildSyntheticDashboardData(options: {
  snapshots?: SyntheticSnapshotListItem[];
  timeline?: SyntheticEvent[];
  world: SyntheticWorld;
  worlds: SyntheticWorldListItem[];
}) {
  const { world } = options;
  const agentById = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const teamById = new Map(world.state.teams.map((team) => [team.id, team]));
  const rankingByAgent = new Map(world.state.rankings.map((row) => [row.agentId, row]));
  const attendanceByAgent = new Map<string, string[]>();
  for (const record of world.state.attendanceRecords) {
    const values = attendanceByAgent.get(record.agentId) ?? [];
    values.push(record.finalOutcome);
    attendanceByAgent.set(record.agentId, values);
  }
  const timeline = options.timeline ?? world.state.events.slice(-300).reverse();
  const health = HEALTH_AREAS.map(([area, prefixes]) => {
    const rows = world.state.coverage.filter(({ flow }) => prefixes.some((prefix) => flow.startsWith(prefix)));
    const status = rows.some(({ status }) => status === "FAIL") ? "FAIL"
      : rows.some(({ status }) => status === "PASS") ? "PASS"
        : rows.length > 0 ? "WARNING" : "UNTESTED";
    return {
      area,
      executions: rows.reduce((sum, row) => sum + row.timesExecuted, 0),
      failures: rows.reduce((sum, row) => sum + row.failures, 0),
      status,
    };
  });

  return {
    attendance: countBy(world.state.attendanceRecords.map(({ finalOutcome }) => finalOutcome)),
    conduct: {
      byKind: countBy(world.state.conductScenarios.map(({ kind }) => kind)),
      implementedGuestReviews: world.state.conductScenarios.filter(({ productCapability }) => productCapability === "implemented_guest_withdrawal_only").length,
      needsProduct: world.state.conductScenarios.filter(({ productCapability }) => productCapability === "not_implemented").length,
      reportSystem: "NOT_IMPLEMENTED" as const,
      trueNoShowDistinction: "NOT_IMPLEMENTED" as const,
    },
    coverage: [...world.state.coverage].sort((left, right) => left.flow.localeCompare(right.flow)),
    health,
    incidents: [...world.state.incidents]
      .sort((left, right) => right.virtualDate.localeCompare(left.virtualDate) || right.severity.localeCompare(left.severity))
      .map((incident) => ({
        ...incident,
        actorName: incident.actorAgentId ? agentById.get(incident.actorAgentId)?.displayName ?? incident.actorAgentId : null,
      })),
    matches: [...world.state.matches]
      .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt))
      .map((match) => ({
        awayTeam: match.awayTeamId ? teamById.get(match.awayTeamId)?.name ?? match.awayTeamId : "Interno",
        confidence: match.confidence,
        evidenceExcluded: match.evidenceExcluded,
        guestCount: match.guestIds.length,
        homeTeam: teamById.get(match.homeTeamId)?.name ?? match.homeTeamId,
        id: match.id,
        kind: match.kind,
        occurredAt: match.occurredAt,
        participantCount: match.participantIds.length,
        result: match.homeGoals === null || match.awayGoals === null ? null : `${match.homeGoals}-${match.awayGoals}`,
        scorers: Object.entries(match.scorerGoals).map(([agentId, goals]) => ({ goals, name: agentById.get(agentId)?.displayName ?? agentId })),
        state: match.state,
      })),
    notifications: countBy(world.state.notifications.map(({ kind }) => kind)),
    networkHealthV31: networkHealthV31Summary,
    players: world.state.agents.map((agent) => {
      const ranking = rankingByAgent.get(agent.id);
      return {
        achievements: world.state.achievements.filter(({ agentId }) => agentId === agent.id).length,
        attackProfile: agent.attackProfile,
        attendance: countBy(attendanceByAgent.get(agent.id) ?? []),
        attendanceProfile: agent.attendanceProfile,
        boxes: world.state.boxes.filter(({ agentId }) => agentId === agent.id).length,
        city: agent.city,
        conductProfile: agent.conductProfile,
        displayName: agent.displayName,
        facets: agent.facets,
        id: agent.id,
        integrityRisk: ranking?.integrityRisk ?? 0,
        kind: agent.kind,
        notifications: world.state.notifications.filter(({ agentId }) => agentId === agent.id).length,
        position: agent.position,
        provinceCode: agent.provinceCode,
        ratingReliability: agent.ratingReliability,
        ratingV2: agent.ratingV2,
        ranking: ranking ? { certification: ranking.certification, movement: ranking.movement, rank: ranking.rank, score: ranking.score } : null,
        status: agent.status,
        teams: agent.teamIds.map((id) => ({ id, name: teamById.get(id)?.name ?? id })),
      };
    }),
    ranking: [...world.state.rankings]
      .sort((left, right) => left.provinceCode.localeCompare(right.provinceCode) || left.rank - right.rank)
      .map((row) => ({ ...row, displayName: agentById.get(row.agentId)?.displayName ?? row.agentId })),
    rankingCounterfactuals: rankingFunnelSummary.clones,
    rankingFunnel: rankingAudit(world),
    rankingReference: rankingFunnelSummary.reference,
    territoryAwardReadiness: territoryAwardReadinessSummary,
    snapshots: options.snapshots ?? [],
    summary: {
      ...syntheticWorldSummary(world),
      attacksDetected: world.state.agents.filter(({ attackProfile }) => attackProfile !== "none").length,
      marketPlayers: world.state.agents.filter(({ kind, status, teamIds }) => kind === "registered" && status === "active" && teamIds.length === 0).length,
      unavailablePlayers: world.state.agents.filter(({ status }) => status === "unavailable").length,
    },
    teams: world.state.teams.map((team) => ({
      activity: team.activity,
      adminNames: team.adminAgentIds.map((id) => agentById.get(id)?.displayName ?? id),
      challengePolicy: team.challengePolicy,
      city: team.city,
      id: team.id,
      integrityClusterId: team.integrityClusterId,
      marketPolicy: team.marketPolicy,
      modality: team.modality,
      name: team.name,
      ownerName: agentById.get(team.ownerAgentId)?.displayName ?? team.ownerAgentId,
      playerCount: team.playerIds.length,
      playerNames: team.playerIds.map((id) => agentById.get(id)?.displayName ?? id),
      provinceCode: team.provinceCode,
      strength: team.strength,
      style: team.style,
    })),
    timeline: timeline.map((event) => ({
      ...event,
      actorName: event.actorAgentId ? agentById.get(event.actorAgentId)?.displayName ?? event.actorAgentId : "Sistema",
    })),
    world: {
      currentDate: world.currentDate,
      id: world.id,
      mode: world.mode,
      name: world.name,
      revision: world.revision,
      seasonEnd: world.config.seasonEnd,
      seasonId: world.seasonId,
      seed: world.seed,
      sourceCommit: world.sourceCommit,
      startDate: world.startDate,
      status: world.status,
    },
    worlds: options.worlds,
  };
}
