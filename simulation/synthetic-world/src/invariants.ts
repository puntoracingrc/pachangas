import { deterministicUuid } from "./random";
import type { SyntheticIncident, SyntheticWorld } from "./types";

type Check = {
  actual: unknown;
  entityIds?: string[];
  expected: unknown;
  name: string;
  pass: boolean;
  severity?: SyntheticIncident["severity"];
};

function incident(world: SyntheticWorld, date: string, check: Check): SyntheticIncident {
  const id = deterministicUuid(`${world.seed}:invariant:${check.name}`, date.slice(0, 10));
  return {
    actual: { value: check.actual },
    actorAgentId: null,
    afterState: {},
    beforeState: {},
    category: "INVARIANT_FAILURE",
    expected: { value: check.expected },
    id,
    occurrenceCount: 1,
    operation: check.name,
    relatedEntityIds: check.entityIds ?? [],
    reproductionSteps: [
      `Load synthetic world ${world.id}`,
      `Advance or clone to ${date}`,
      `Run invariant ${check.name}`,
    ],
    severity: check.severity ?? "high",
    status: "confirmed_bug",
    virtualDate: date,
  };
}

function duplicateValues(values: string[]) {
  const seen = new Set<string>();
  return [...new Set(values.filter((value) => seen.has(value) || (seen.add(value), false)))];
}

export function dailyInvariantChecks(world: SyntheticWorld): Check[] {
  const agentIds = new Set(world.state.agents.map(({ id }) => id));
  const teamIds = new Set(world.state.teams.map(({ id }) => id));
  const malformedMatches = world.state.matches.filter((match) => (
    !teamIds.has(match.homeTeamId)
      || (match.awayTeamId !== null && !teamIds.has(match.awayTeamId))
      || match.participantIds.some((id) => !agentIds.has(id))
  ));
  const scorerMismatch = world.state.matches.filter((match) => (
    match.homeGoals !== null
      && match.awayGoals !== null
      && Object.values(match.scorerGoals).reduce((sum, goals) => sum + goals, 0) !== match.homeGoals + match.awayGoals
  ));
  const activeOpinionKeys = world.state.ratingOpinions
    .filter(({ status }) => status === "active")
    .map(({ evaluatorAgentId, targetAgentId }) => `${evaluatorAgentId}:${targetAgentId}`);
  const achievementKeys = world.state.achievements.map(({ agentId, key, teamId }) => `${teamId}:${agentId ?? "team"}:${key}`);
  const duplicateRosterIds = world.state.teams.flatMap((team) => duplicateValues(team.playerIds).map((agentId) => `${team.id}:${agentId}`));
  const duplicateAttendanceIds = duplicateValues(world.state.attendanceRecords.map(({ id }) => id));
  return [
    { actual: duplicateValues(world.state.agents.map(({ id }) => id)), expected: [], name: "agents.unique_ids", pass: duplicateValues(world.state.agents.map(({ id }) => id)).length === 0 },
    { actual: duplicateValues(world.state.teams.map(({ id }) => id)), expected: [], name: "teams.unique_ids", pass: duplicateValues(world.state.teams.map(({ id }) => id)).length === 0 },
    { actual: duplicateRosterIds, expected: [], name: "teams.unique_roster_members", pass: duplicateRosterIds.length === 0 },
    { actual: malformedMatches.map(({ id }) => id), entityIds: malformedMatches.map(({ id }) => id), expected: [], name: "matches.valid_references", pass: malformedMatches.length === 0 },
    { actual: scorerMismatch.map(({ id }) => id), entityIds: scorerMismatch.map(({ id }) => id), expected: [], name: "matches.scorers_equal_score", pass: scorerMismatch.length === 0 },
    { actual: duplicateValues(activeOpinionKeys), expected: [], name: "rating.one_active_opinion_per_pair", pass: duplicateValues(activeOpinionKeys).length === 0 },
    { actual: duplicateValues(achievementKeys), expected: [], name: "achievements.unique_award", pass: duplicateValues(achievementKeys).length === 0 },
    { actual: duplicateAttendanceIds, expected: [], name: "attendance.unique_record_ids", pass: duplicateAttendanceIds.length === 0 },
    { actual: world.state.matches.filter(({ confidence }) => confidence < 0 || confidence > 1).map(({ id }) => id), expected: [], name: "matches.confidence_bounds", pass: world.state.matches.every(({ confidence }) => confidence >= 0 && confidence <= 1) },
    { actual: world.state.challenges.filter(({ homeTeamId, awayTeamId }) => homeTeamId === awayTeamId).map(({ id }) => id), expected: [], name: "challenges.distinct_teams", pass: world.state.challenges.every(({ homeTeamId, awayTeamId }) => homeTeamId !== awayTeamId) },
  ];
}

export function weeklyInvariantChecks(world: SyntheticWorld): Check[] {
  const operationIds = world.state.events.map(({ operationId }) => operationId);
  const badRankingGroups: string[] = [];
  const groups = new Map<string, number[]>();
  for (const row of world.state.rankings) groups.set(row.provinceCode, [...(groups.get(row.provinceCode) ?? []), row.rank]);
  for (const [province, ranks] of groups) {
    if (new Set(ranks).size !== ranks.length) badRankingGroups.push(province);
  }
  return [
    { actual: duplicateValues(operationIds), expected: [], name: "events.idempotent_operation_ids", pass: duplicateValues(operationIds).length === 0, severity: "critical" },
    { actual: badRankingGroups, expected: [], name: "ranking.unique_province_positions", pass: badRankingGroups.length === 0 },
    { actual: world.state.boxes.filter(({ points }) => points !== null && points < 0).map(({ id }) => id), expected: [], name: "rewards.non_negative_points", pass: world.state.boxes.every(({ points }) => points === null || points >= 0) },
    { actual: world.state.events.some(({ payload }) => JSON.stringify(payload).includes("service_role")), expected: false, name: "events.no_service_role_secret", pass: !world.state.events.some(({ payload }) => JSON.stringify(payload).includes("service_role")), severity: "critical" },
  ];
}

export function evaluateInvariants(world: SyntheticWorld, date: string, weekly: boolean) {
  const checks = [...dailyInvariantChecks(world), ...(weekly ? weeklyInvariantChecks(world) : [])];
  return {
    checks,
    incidents: checks.filter(({ pass }) => !pass).map((check) => incident(world, date, check)),
  };
}
