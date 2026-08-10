import { canonicalContract } from "./canonical-contracts";
import { PLAYER_COSMETIC_CATALOG } from "../../../app/player-cosmetics-catalog";
import { addVirtualDays, atVirtualHour, eachVirtualDayExclusive, virtualDaysBetween, virtualWeek } from "./clock";
import { evaluateInvariants } from "./invariants";
import { calculateRankings, SYNTHETIC_PROVINCE_TROPHY_RULE } from "./ranking";
import { clamp, deterministicUuid, SeededRandom } from "./random";
import type {
  SyntheticAchievement,
  SyntheticAgent,
  SyntheticAttendanceRecord,
  SyntheticChallenge,
  SyntheticConductScenario,
  SyntheticEvent,
  SyntheticMatch,
  SyntheticPlayerCosmeticInventoryItem,
  SyntheticPlayerCosmeticLoadout,
  SyntheticRatingOpinion,
  SyntheticTeam,
  SyntheticWorld,
} from "./types";

const TEAM_SIZE = { futbol11: 11, futbol7: 7, sala: 5 } as const;
const ACTIVITY_RATE: Record<SyntheticTeam["activity"], number> = {
  abandoned: 0.02,
  casual: 0.28,
  high: 0.9,
  low: 0.14,
  regular: 0.58,
};

export type AdvanceSyntheticWorldOptions = {
  failureInjectionRate?: number;
  rankingEligibilityCoverage?: boolean;
  targetDate: string;
};

function executionPayload(flow: string) {
  const contract = canonicalContract(flow);
  return {
    canonicalClassification: contract?.classification ?? "not_in_inventory",
    canonicalExecution: contract?.execution ?? "unavailable",
    canonicalRoute: contract?.route ?? null,
    executionMode: "synthetic_domain_adapter",
    timeInjectable: contract?.timeInjectable ?? true,
  };
}

function coverage(world: SyntheticWorld, flow: string, date: string, pass: boolean) {
  let row = world.state.coverage.find((item) => item.flow === flow);
  if (!row) {
    row = { failures: 0, flow, lastExecution: null, passes: 0, scenario: "synthetic-world", status: "NO_COVERAGE", timesExecuted: 0 };
    world.state.coverage.push(row);
  }
  row.timesExecuted += 1;
  row.lastExecution = date;
  if (pass) row.passes += 1;
  else row.failures += 1;
  row.status = row.failures > 0 ? "FAIL" : row.passes > 0 ? "PASS" : "NO_COVERAGE";
}

function recordEvent(
  world: SyntheticWorld,
  options: {
    actorAgentId?: string | null;
    entityIds?: string[];
    eventType: string;
    expected?: Record<string, unknown>;
    flow: string;
    key: string;
    payload?: Record<string, unknown>;
    status?: SyntheticEvent["status"];
    virtualDate: string;
  },
) {
  const operationId = deterministicUuid(`${world.id}:operation`, options.key);
  const existing = world.state.events.find((event) => event.operationId === operationId);
  if (existing) {
    existing.payload.replayCount = Number(existing.payload.replayCount ?? 0) + 1;
    return existing;
  }
  const status = options.status ?? "pass";
  const event: SyntheticEvent = {
    actorAgentId: options.actorAgentId ?? null,
    entityIds: options.entityIds ?? [],
    eventType: options.eventType,
    expected: options.expected ?? {},
    flow: options.flow,
    operationId,
    payload: { ...executionPayload(options.flow), ...options.payload },
    sequence: ++world.state.eventSequence,
    status,
    virtualDate: options.virtualDate,
  };
  world.state.events.push(event);
  coverage(world, options.flow, options.virtualDate, status === "pass");
  return event;
}

function notificationPolicy(kind: string) {
  const value = kind.toLowerCase();
  const category = value.includes("achievement") || value.includes("reward") ? "achievement"
    : value.includes("challenge") || value.includes("external_result") ? "challenge"
      : value.includes("invitation") || value.includes("open_match_request") || value.includes("withdrawal") || value.includes("market") ? "market"
        : value.includes("attendance") || value.includes("availability") || value.startsWith("match_") ? "match"
          : value.includes("security") || value.includes("sanction") || value.includes("warning") ? "security" : "group";
  const mandatoryInApp = value.includes("security") || value.includes("sanction") || value.includes("warning")
    || value.includes("challenge") || value.includes("external_result") || value.includes("invitation")
    || value.includes("open_match_request") || value.includes("withdrawal") || value.includes("achievement")
    || value.includes("reward") || value === "group_member_removed";
  return { category, mandatoryInApp } as const;
}

function notify(world: SyntheticWorld, date: string, agentId: string, kind: string, relatedEntityId: string | null, key: string) {
  const id = deterministicUuid(`${world.id}:notification`, key);
  if (world.state.notifications.some((notification) => notification.id === id)) return;
  const agent = world.state.agents.find(({ id: candidateId }) => candidateId === agentId);
  if (!agent) return;
  const policy = notificationPolicy(kind);
  world.state.notifications.push({
    agentId,
    category: policy.category,
    createdAt: date,
    id,
    kind,
    mandatoryInApp: policy.mandatoryInApp,
    readAt: null,
    relatedEntityId,
    visibleInApp: policy.mandatoryInApp || agent.notificationPreferences[policy.category].inApp,
  });
}

function missingCapabilityDemand(world: SyntheticWorld, date: string, operation: string, entityIds: string[]) {
  const id = deterministicUuid(`${world.seed}:missing-capability`, operation);
  const existing = world.state.incidents.find((incident) => incident.id === id);
  if (existing) {
    existing.occurrenceCount += 1;
    existing.virtualDate = date;
    existing.relatedEntityIds = [...new Set([...existing.relatedEntityIds, ...entityIds])].slice(-100);
    return;
  }
  world.state.incidents.push({
    actual: { productCapability: "not_implemented" },
    actorAgentId: null,
    afterState: {},
    beforeState: {},
    category: "NEEDS_PRODUCT_DECISION",
    expected: { productDecisionRequired: true },
    id,
    occurrenceCount: 1,
    operation,
    relatedEntityIds: entityIds,
    reproductionSteps: [`Load world ${world.id}`, `Filter timeline by ${operation}`, "Inspect synthetic demand without applying sanctions"],
    severity: "info",
    status: "needs_product_decision",
    virtualDate: date,
  });
}

function bootstrapCoverage(world: SyntheticWorld, date: string) {
  if (world.state.events.length > 0) return;
  for (const team of world.state.teams) {
    recordEvent(world, {
      actorAgentId: team.ownerAgentId,
      entityIds: [team.id],
      eventType: "team_created",
      flow: "team.create",
      key: `bootstrap-team:${team.id}`,
      payload: { modality: team.modality, privacy: team.challengePolicy },
      virtualDate: date,
    });
  }
  for (const team of world.state.teams) {
    for (const agentId of team.playerIds.filter((id) => id !== team.ownerAgentId)) {
      recordEvent(world, {
        actorAgentId: agentId,
        entityIds: [team.id, agentId],
        eventType: "team_member_joined",
        flow: "team.join",
        key: `bootstrap-member:${team.id}:${agentId}`,
        virtualDate: date,
      });
    }
  }
}

function provinceDistance(left: SyntheticTeam, right: SyntheticTeam) {
  if (left.provinceCode === right.provinceCode) return 0;
  if (left.city === right.city) return 0.1;
  return 1;
}

function challengeCompatibility(home: SyntheticTeam, away: SyntheticTeam) {
  if (home.modality !== away.modality) return 0;
  const strengthFit = 1 - Math.min(1, Math.abs(home.strength - away.strength) / 35);
  const distanceFit = 1 - provinceDistance(home, away) * 0.55;
  const policyFit = away.challengePolicy === "public" ? 1
    : away.challengePolicy === "invite_only" ? 0.72
      : away.challengePolicy === "private" ? 0.52 : 0.08;
  return clamp(strengthFit * 0.5 + distanceFit * 0.32 + policyFit * 0.18, 0, 1);
}

function scheduleChallengeMatch(world: SyntheticWorld, challenge: SyntheticChallenge, date: string, random: SeededRandom) {
  const home = world.state.teams.find(({ id }) => id === challenge.homeTeamId)!;
  const away = world.state.teams.find(({ id }) => id === challenge.awayTeamId)!;
  const occurredAt = atVirtualHour(addVirtualDays(date, random.integer(3, 13)), random.pick([18, 19, 20, 21]), random.pick([0, 15, 30, 45]));
  const id = deterministicUuid(`${world.id}:challenge-match`, challenge.id);
  if (world.state.matches.some((match) => match.id === id)) return;
  const venue = world.state.venues.find((candidate) => candidate.code === home.provinceCode && candidate.modality === home.modality)
    ?? world.state.venues.find((candidate) => candidate.modality === home.modality)!;
  world.state.matches.push({
    awayGoals: null,
    awayTeamId: away.id,
    confidence: 0,
    evidenceExcluded: false,
    guestIds: [],
    homeGoals: null,
    homeTeamId: home.id,
    id,
    kind: "challenge",
    occurredAt,
    participantIds: [],
    productMatchId: null,
    provinceCode: home.provinceCode,
    scorerGoals: {},
    state: "scheduled",
    venueId: venue.id,
  });
  recordEvent(world, {
    actorAgentId: home.ownerAgentId,
    entityIds: [challenge.id, id],
    eventType: "challenge_match_scheduled",
    flow: "match.attendance",
    key: `schedule:${id}`,
    payload: { occurredAt, expectedRevision: world.revision },
    virtualDate: date,
  });
}

function createDailyChallenges(world: SyntheticWorld, date: string, random: SeededRandom) {
  const active = world.state.teams.filter((team) => team.activity !== "abandoned" && team.challengePolicy !== "temporarily_unavailable");
  const attempts = random.integer(9, 18);
  for (let index = 0; index < attempts; index += 1) {
    const home = random.weighted(active.map((team) => ({ value: team, weight: 1 + ACTIVITY_RATE[team.activity] * 8 })));
    if (!random.bool(ACTIVITY_RATE[home.activity] * 0.64)) continue;
    const candidates = active.filter((team) => team.id !== home.id && team.modality === home.modality);
    if (candidates.length === 0) continue;
    const away = random.weighted(candidates.map((team) => ({ value: team, weight: Math.max(0.02, challengeCompatibility(home, team) ** 2) })));
    const id = deterministicUuid(`${world.id}:challenge`, `${date.slice(0, 10)}:${index}:${home.id}:${away.id}`);
    if (world.state.challenges.some((challenge) => challenge.id === id)) continue;
    const proposedAt = atVirtualHour(date, random.integer(8, 18), random.pick([0, 15, 30, 45]));
    const challenge: SyntheticChallenge = {
      awayTeamId: away.id,
      createdAt: proposedAt,
      homeTeamId: home.id,
      id,
      operationId: deterministicUuid(`${world.id}:challenge-create`, id),
      productChallengeId: null,
      proposedAt,
      state: "pending",
    };
    world.state.challenges.push(challenge);
    recordEvent(world, {
      actorAgentId: home.ownerAgentId,
      entityIds: [challenge.id, home.id, away.id],
      eventType: "challenge_created",
      flow: "challenge.create",
      key: `challenge-create:${id}`,
      payload: { compatibility: challengeCompatibility(home, away), expectedRevision: world.revision },
      virtualDate: proposedAt,
    });
    away.adminAgentIds.forEach((agentId) => notify(world, proposedAt, agentId, "team_challenge_received", challenge.id, `challenge:${id}:${agentId}`));

    const compatibility = challengeCompatibility(home, away);
    const awayOwner = world.state.agents.find(({ id: agentId }) => agentId === away.ownerAgentId)!;
    const slow = awayOwner.persona === "slow_responder" || away.activity === "low";
    const attackPair = home.integrityClusterId === "synthetic-fake-team-ring" && away.integrityClusterId === "synthetic-fake-team-ring";
    const decision = attackPair ? "accepted"
      : away.activity === "abandoned" || (slow && random.bool(0.28)) ? "expired"
        : random.bool(compatibility * awayOwner.behavior.acceptance) ? "accepted"
          : compatibility > 0.48 && random.bool(0.34) ? "countered"
            : random.bool(0.08) ? "cancelled" : "rejected";
    challenge.state = decision;
    if (decision === "expired") {
      recordEvent(world, {
        actorAgentId: null,
        entityIds: [challenge.id],
        eventType: "challenge_expired_needs_product_contract",
        flow: "challenge.expire",
        key: `challenge-expire:${id}`,
        status: "pending",
        virtualDate: atVirtualHour(addVirtualDays(date, 3), 12),
      });
      continue;
    }
    recordEvent(world, {
      actorAgentId: decision === "cancelled" ? home.ownerAgentId : away.ownerAgentId,
      entityIds: [challenge.id],
      eventType: `challenge_${decision}`,
      flow: decision === "cancelled" ? "challenge.cancel" : "challenge.respond",
      key: `challenge-response:${id}:${decision}`,
      payload: { decision, expectedRevision: world.revision },
      virtualDate: atVirtualHour(addVirtualDays(date, slow ? 2 : 0), random.integer(9, 22)),
    });
    notify(world, date, home.ownerAgentId, `team_challenge_${decision}`, id, `challenge-result:${id}:${home.ownerAgentId}`);
    if (decision === "accepted" || decision === "countered") {
      if (decision === "countered") {
        challenge.state = "accepted";
        recordEvent(world, {
          actorAgentId: home.ownerAgentId,
          entityIds: [challenge.id],
          eventType: "challenge_counter_accepted",
          flow: "challenge.respond",
          key: `challenge-counter-accept:${id}`,
          payload: { decision: "accepted_counterproposal", expectedRevision: world.revision },
          virtualDate: atVirtualHour(addVirtualDays(date, 1), 18),
        });
      }
      scheduleChallengeMatch(world, challenge, date, random.fork(`match:${id}`));
    }
  }
}

function scheduleInternalMatches(world: SyntheticWorld, date: string, random: SeededRandom) {
  if (![4, 5, 6].includes(new Date(date).getUTCDay())) return;
  const teams = random.sample(world.state.teams.filter(({ activity }) => activity !== "abandoned"), random.integer(4, 8));
  teams.forEach((team, index) => {
    if (!random.bool(ACTIVITY_RATE[team.activity] * 0.72)) return;
    const id = deterministicUuid(`${world.id}:internal-match`, `${date.slice(0, 10)}:${team.id}:${index}`);
    if (world.state.matches.some((match) => match.id === id)) return;
    const venue = world.state.venues.find((candidate) => candidate.code === team.provinceCode && candidate.modality === team.modality)!;
    world.state.matches.push({
      awayGoals: null, awayTeamId: null, confidence: 0, evidenceExcluded: true, guestIds: [], homeGoals: null,
      homeTeamId: team.id, id, kind: "internal", occurredAt: atVirtualHour(date, random.pick([18, 19, 20, 21])),
      participantIds: [], productMatchId: null, provinceCode: team.provinceCode, scorerGoals: {}, state: "scheduled", venueId: venue.id,
    });
    recordEvent(world, {
      actorAgentId: team.ownerAgentId,
      entityIds: [id, team.id],
      eventType: "internal_match_scheduled",
      flow: "match.attendance",
      key: `internal-schedule:${id}`,
      payload: { rankingEligible: false },
      virtualDate: date,
    });
  });
}

function eligiblePlayers(world: SyntheticWorld, team: SyntheticTeam, date: string, random: SeededRandom, capacity: number, excluded = new Set<string>()) {
  const roster = team.playerIds
    .map((id) => world.state.agents.find((agent) => agent.id === id))
    .filter((agent): agent is SyntheticAgent => Boolean(agent))
    .filter((agent) => !excluded.has(agent.id) && agent.status === "active" && agent.availableFrom <= date && (!agent.unavailableUntil || agent.unavailableUntil < date));
  const responding = random.sample(roster, roster.length).filter((agent) => random.bool(agent.behavior.acceptance * agent.behavior.reliability));
  const selected = [...responding];
  for (const agent of roster.sort((left, right) => right.behavior.reliability - left.behavior.reliability)) {
    if (selected.length >= capacity || selected.some(({ id }) => id === agent.id)) continue;
    selected.push(agent);
  }
  return selected.slice(0, capacity);
}

function poisson(random: SeededRandom, mean: number) {
  const limit = Math.exp(-mean);
  let product = 1;
  let count = 0;
  do {
    count += 1;
    product *= random.next();
  } while (product > limit && count < 12);
  return Math.max(0, count - 1);
}

function assignGoals(random: SeededRandom, players: SyntheticAgent[], goals: number, output: Record<string, number>) {
  if (players.length === 0) return;
  for (let goal = 0; goal < goals; goal += 1) {
    const scorer = random.weighted(players.map((player) => ({
      value: player,
      weight: player.position === "DEL" ? 5 : player.position === "MC" ? 3 : player.position === "DEF" ? 1.3 : 0.35,
    })));
    output[scorer.id] = (output[scorer.id] ?? 0) + 1;
  }
}

function awardAchievement(world: SyntheticWorld, achievement: SyntheticAchievement) {
  const duplicate = world.state.achievements.some(({ agentId, key, teamId }) => (
    agentId === achievement.agentId && key === achievement.key && teamId === achievement.teamId
  ));
  if (duplicate) return;
  world.state.achievements.push(achievement);
  const recipient = achievement.agentId ?? world.state.teams.find(({ id }) => id === achievement.teamId)?.ownerAgentId ?? null;
  const boxId = deterministicUuid(`${world.id}:achievement-box`, achievement.id);
  world.state.boxes.push({
    agentId: achievement.agentId,
    cosmeticGranted: null,
    cosmeticKey: null,
    createdAt: achievement.earnedAt,
    duplicatePoints: 0,
    id: boxId,
    openedAt: null,
    points: null,
    teamId: achievement.teamId,
  });
  if (recipient) notify(world, achievement.earnedAt, recipient, "achievement_unlocked", achievement.id, `achievement:${achievement.id}:${recipient}`);
  recordEvent(world, {
    actorAgentId: null,
    entityIds: [achievement.id, achievement.teamId, ...(achievement.agentId ? [achievement.agentId] : [])],
    eventType: "achievement_unlocked",
    flow: "achievement.evaluate",
    key: `achievement:${achievement.id}`,
    payload: { key: achievement.key, rewardBoxId: boxId, scope: achievement.scope },
    virtualDate: achievement.earnedAt,
  });
}

function evaluateAchievements(world: SyntheticWorld, match: SyntheticMatch, date: string) {
  const confirmed = world.state.matches.filter(({ state }) => state === "confirmed" || state === "auto_confirmed");
  for (const agentId of match.participantIds) {
    const teamId = world.state.teams.find((team) => team.playerIds.includes(agentId) && (team.id === match.homeTeamId || team.id === match.awayTeamId))?.id ?? match.homeTeamId;
    const played = confirmed.filter(({ participantIds }) => participantIds.includes(agentId)).length;
    const goals = confirmed.reduce((sum, item) => sum + (item.scorerGoals[agentId] ?? 0), 0);
    const thresholds = [
      { key: "individual_first_match", threshold: 1, value: played },
      { key: "individual_matches_5", threshold: 5, value: played },
      { key: "individual_matches_15", threshold: 15, value: played },
      { key: "individual_matches_30", threshold: 30, value: played },
      { key: "individual_first_goal", threshold: 1, value: goals },
      { key: "individual_goals_10", threshold: 10, value: goals },
    ];
    for (const item of thresholds.filter(({ threshold, value }) => value >= threshold)) {
      awardAchievement(world, {
        agentId, claimedAt: null, earnedAt: date,
        id: deterministicUuid(`${world.id}:achievement`, `${teamId}:${agentId}:${item.key}`),
        key: item.key, progress: item.value, scope: "individual", teamId,
      });
    }
  }
  for (const teamId of [match.homeTeamId, match.awayTeamId].filter((id): id is string => Boolean(id))) {
    const wins = confirmed.filter((item) => {
      if (item.homeGoals === null || item.awayGoals === null) return false;
      return item.homeTeamId === teamId ? item.homeGoals > item.awayGoals : item.awayTeamId === teamId && item.awayGoals > item.homeGoals;
    }).length;
    if (wins >= 10) awardAchievement(world, {
      agentId: null, claimedAt: null, earnedAt: date,
      id: deterministicUuid(`${world.id}:achievement`, `${teamId}:collective_wins_10`),
      key: "collective_wins_10", progress: wins, scope: "team", teamId,
    });
  }
}

function sharedMatches(world: SyntheticWorld, left: string, right: string) {
  return world.state.matches.filter((match) => (
    (match.state === "confirmed" || match.state === "auto_confirmed")
      && match.participantIds.includes(left)
      && match.participantIds.includes(right)
  )).length;
}

function comparisonValues(evaluator: SyntheticAgent, target: SyntheticAgent, random: SeededRandom): SyntheticRatingOpinion["values"] {
  const values = {} as SyntheticRatingOpinion["values"];
  for (const facet of ["defensa", "fisico", "pase", "regate", "ritmo", "tiro"] as const) {
    const gap = target.facets[facet] - evaluator.facets[facet] + random.decimal(-3, 3);
    values[facet] = evaluator.attackProfile === "rating_manipulator" ? 1 : gap > 5 ? 1 : gap < -5 ? -1 : 0;
  }
  return values;
}

function createRatingOpinions(world: SyntheticWorld, match: SyntheticMatch, date: string, random: SeededRandom) {
  const players = random.sample(match.participantIds, Math.min(6, match.participantIds.length));
  for (let index = 0; index + 1 < players.length; index += 2) {
    const evaluator = world.state.agents.find(({ id }) => id === players[index]);
    const target = world.state.agents.find(({ id }) => id === players[index + 1]);
    if (!evaluator || !target || evaluator.kind !== "registered" || target.kind !== "registered") continue;
    const active = world.state.ratingOpinions.find((opinion) => (
      opinion.evaluatorAgentId === evaluator.id && opinion.targetAgentId === target.id && opinion.status === "active"
    ));
    const currentShared = sharedMatches(world, evaluator.id, target.id);
    if (active && currentShared - active.sharedMatchesAtCreation < 3) continue;
    if (active) active.status = "superseded";
    const id = deterministicUuid(`${world.id}:rating-opinion`, `${match.id}:${evaluator.id}:${target.id}`);
    const opinion: SyntheticRatingOpinion = {
      createdAt: date,
      evaluatorAgentId: evaluator.id,
      id,
      operationId: deterministicUuid(`${world.id}:rating-opinion-operation`, id),
      sharedMatchesAtCreation: currentShared,
      status: "active",
      targetAgentId: target.id,
      values: comparisonValues(evaluator, target, random),
    };
    world.state.ratingOpinions.push(opinion);
    recordEvent(world, {
      actorAgentId: evaluator.id,
      entityIds: [opinion.id, target.id],
      eventType: "relative_rating_recorded",
      flow: "rating.peer",
      key: `rating:${id}`,
      payload: { comparisonCount: 6, expectedRevision: world.revision, sharedMatches: currentShared },
      virtualDate: date,
    });
  }
}

function attendanceOutcome(agent: SyntheticAgent, random: SeededRandom): SyntheticAttendanceRecord["finalOutcome"] {
  if (agent.attendanceProfile === "early_canceller" && random.bool(0.12)) return "cancelled_early";
  if (agent.attendanceProfile === "late_canceller" && random.bool(0.15)) return "cancelled_late";
  if (agent.attendanceProfile === "occasional_no_show" && random.bool(0.055)) return "no_show";
  if (agent.attendanceProfile === "repeat_no_show" && random.bool(0.2)) return "no_show";
  if (agent.attendanceProfile === "stops_responding" && random.bool(0.12)) return "no_show";
  if (agent.attendanceProfile === "injury_prone" && random.bool(0.075)) return "injured";
  return "played";
}

function attendanceChangeDate(matchDate: string, outcome: SyntheticAttendanceRecord["finalOutcome"]) {
  const offset = outcome === "cancelled_early" ? -36 * 3_600_000
    : outcome === "cancelled_late" ? -75 * 60_000
      : outcome === "injured" ? -8 * 3_600_000
        : outcome === "no_show" ? 15 * 60_000 : -48 * 3_600_000;
  return new Date(Date.parse(matchDate) + offset).toISOString();
}

function recordRejectedAttendance(world: SyntheticWorld, match: SyntheticMatch, team: SyntheticTeam, confirmedIds: Set<string>, date: string, random: SeededRandom) {
  const rejectors = team.playerIds
    .map((id) => world.state.agents.find((agent) => agent.id === id))
    .filter((agent): agent is SyntheticAgent => Boolean(agent) && !confirmedIds.has(agent!.id) && agent!.attendanceProfile === "correct_rejector");
  for (const agent of random.sample(rejectors, Math.min(2, rejectors.length))) {
    const id = deterministicUuid(`${world.id}:attendance`, `${match.id}:${agent.id}:rejected`);
    if (world.state.attendanceRecords.some((record) => record.id === id)) continue;
    world.state.attendanceRecords.push({
      agentId: agent.id,
      canonicalNoShowDistinguishable: true,
      changedAt: attendanceChangeDate(match.occurredAt, "rejected"),
      finalOutcome: "rejected",
      id,
      initialStatus: "no",
      matchId: match.id,
      teamId: team.id,
    });
  }
}

function applyAttendanceOutcomes(
  world: SyntheticWorld,
  match: SyntheticMatch,
  team: SyntheticTeam,
  confirmed: SyntheticAgent[],
  date: string,
  random: SeededRandom,
) {
  const played: SyntheticAgent[] = [];
  for (const agent of confirmed) {
    const outcome = attendanceOutcome(agent, random.fork(agent.id));
    const id = deterministicUuid(`${world.id}:attendance`, `${match.id}:${agent.id}`);
    const record: SyntheticAttendanceRecord = {
      agentId: agent.id,
      canonicalNoShowDistinguishable: outcome !== "no_show",
      changedAt: attendanceChangeDate(match.occurredAt, outcome),
      finalOutcome: outcome,
      id,
      initialStatus: "voy",
      matchId: match.id,
      teamId: team.id,
    };
    world.state.attendanceRecords.push(record);
    recordEvent(world, {
      actorAgentId: agent.id,
      entityIds: [match.id, agent.id],
      eventType: "match_attendance_joined",
      flow: "attendance.joined_notification",
      key: `attendance-joined:${match.id}:${agent.id}`,
      payload: { status: "voy" },
      virtualDate: attendanceChangeDate(match.occurredAt, "played"),
    });
    const admin = team.adminAgentIds.find((id) => id !== agent.id);
    if (admin) notify(world, date, admin, "match_attendance_joined", match.id, `attendance-joined:${match.id}:${agent.id}:${admin}`);
    if (outcome === "played") {
      played.push(agent);
      continue;
    }
    if (outcome === "no_show") {
      recordEvent(world, {
        actorAgentId: null,
        entityIds: [match.id, agent.id],
        eventType: "possible_no_show_not_canonically_distinguishable",
        flow: "attendance.no_show",
        key: `no-show-gap:${match.id}:${agent.id}`,
        payload: { automaticSanctionApplied: false, affectsRatingV2: false },
        status: "pending",
        virtualDate: record.changedAt,
      });
      missingCapabilityDemand(world, date, "attendance.no_show", [match.id, agent.id]);
      continue;
    }
    if (outcome === "injured") {
      recordEvent(world, {
        actorAgentId: agent.id,
        entityIds: [match.id, agent.id],
        eventType: "player_availability_unavailable",
        flow: "attendance.injury_notification",
        key: `match-injury:${match.id}:${agent.id}`,
        payload: { medicalDetailStored: false },
        virtualDate: record.changedAt,
      });
      if (admin) notify(world, date, admin, "player_availability_unavailable", agent.id, `match-injury:${match.id}:${agent.id}:${admin}`);
      continue;
    }
    recordEvent(world, {
      actorAgentId: agent.id,
      entityIds: [match.id, agent.id],
      eventType: `match_attendance_${outcome}`,
      flow: "attendance.cancelled_notification",
      key: `attendance-cancelled:${match.id}:${agent.id}`,
      payload: { status: "no", timing: outcome === "cancelled_early" ? "sufficient_notice" : "late_notice" },
      virtualDate: record.changedAt,
    });
    if (admin) notify(world, date, admin, "match_attendance_cancelled", match.id, `attendance-cancelled:${match.id}:${agent.id}:${admin}`);
  }
  recordRejectedAttendance(world, match, team, new Set(confirmed.map(({ id }) => id)), date, random.fork("rejectors"));
  return played;
}

function conductScenarioKind(target: SyntheticAgent, random: SeededRandom): SyntheticConductScenario["kind"] {
  if (target.conductProfile === "repeat_offender") return "repeat_offender";
  if (target.conductProfile === "coordinated_false_reporter") return "coordinated_false_report";
  if (target.conductProfile === "retaliatory") return "mutual_conflict";
  if (target.conductProfile === "fair") return "single_clean_history_report";
  return random.bool(0.4) ? "mutual_conflict" : "occasional_unsporting";
}

function createConductScenario(world: SyntheticWorld, match: SyntheticMatch, date: string, random: SeededRandom) {
  if (match.kind !== "challenge" || !match.awayTeamId || !random.bool(0.075)) return;
  const participants = match.participantIds.map((id) => world.state.agents.find((agent) => agent.id === id)).filter((agent): agent is SyntheticAgent => Boolean(agent));
  if (participants.length < 4) return;
  const target = random.weighted(participants.map((agent) => ({ value: agent, weight: agent.conductProfile === "fair" ? 1 : 7 })));
  const targetTeam = world.state.teams.find((team) => team.playerIds.includes(target.id) && (team.id === match.homeTeamId || team.id === match.awayTeamId));
  const opposingTeamId = targetTeam?.id === match.homeTeamId ? match.awayTeamId : match.homeTeamId;
  const reporters = participants.filter((agent) => world.state.teams.find((team) => team.id === opposingTeamId)?.playerIds.includes(agent.id));
  if (reporters.length === 0) return;
  const kind = conductScenarioKind(target, random);
  const reporterCount = kind === "coordinated_false_report" ? Math.min(5, reporters.length) : kind === "mutual_conflict" ? Math.min(2, reporters.length) : 1;
  const reporterAgentIds = random.sample(reporters, reporterCount).map(({ id }) => id);
  const id = deterministicUuid(`${world.id}:conduct-demand`, `${match.id}:${target.id}:${kind}`);
  const scenario: SyntheticConductScenario = {
    id,
    independentSourceTeams: 1,
    kind,
    matchId: match.id,
    productCapability: "not_implemented",
    relatedMatchIds: [match.id],
    reporterAgentIds,
    sourceTeamIds: opposingTeamId ? [opposingTeamId] : [],
    status: "pending",
    targetAgentId: target.id,
    virtualDate: date,
  };
  world.state.conductScenarios.push(scenario);
  recordEvent(world, {
    actorAgentId: reporterAgentIds[0],
    entityIds: [match.id, target.id, ...reporterAgentIds],
    eventType: "conduct_report_scenario_requires_product",
    flow: "conduct.player_report",
    key: `conduct-demand:${id}`,
    payload: { affectsRatingV2: false, automaticSanctionApplied: false, independentSourceTeams: 1, kind },
    status: "pending",
    virtualDate: date,
  });
  missingCapabilityDemand(world, date, "conduct.player_report", [match.id, target.id]);
}

const REQUIRED_CONDUCT_SCENARIOS: Array<{
  kind: SyntheticConductScenario["kind"];
  profile?: SyntheticAgent["conductProfile"];
}> = [
  { kind: "fair_play_control", profile: "fair" },
  { kind: "conflict_prone_incident", profile: "conflict_prone" },
  { kind: "occasional_unsporting", profile: "occasional_unsporting" },
  { kind: "repeat_offender", profile: "repeat_offender" },
  { kind: "same_team_report_burst" },
  { kind: "independent_team_reports" },
  { kind: "coordinated_false_report", profile: "fair" },
  { kind: "mutual_conflict", profile: "retaliatory" },
  { kind: "single_clean_history_report", profile: "fair" },
];

const ATTENDANCE_PROFILE_WEIGHTS: Array<[SyntheticAgent["attendanceProfile"], number]> = [
  ["normal", 51],
  ["correct_rejector", 10],
  ["early_canceller", 10],
  ["late_canceller", 9],
  ["occasional_no_show", 6],
  ["repeat_no_show", 3],
  ["stops_responding", 6],
  ["injury_prone", 5],
];
const CONDUCT_PROFILE_WEIGHTS: Array<[SyntheticAgent["conductProfile"], number]> = [
  ["fair", 83],
  ["occasional_unsporting", 8],
  ["conflict_prone", 4],
  ["repeat_offender", 2],
  ["coordinated_false_reporter", 2],
  ["retaliatory", 1],
];

function weightedProfileAt<T extends string>(index: number, entries: Array<[T, number]>) {
  const total = entries.reduce((sum, [, weight]) => sum + weight, 0);
  let cursor = index % total;
  for (const [value, weight] of entries) {
    if (cursor < weight) return value;
    cursor -= weight;
  }
  return entries[0]![0];
}

function reconcileLegacyBehaviorProfiles(world: SyntheticWorld) {
  const registered = world.state.agents.filter(({ kind }) => kind === "registered").sort((left, right) => left.id.localeCompare(right.id));
  const attendanceKinds = new Set(registered.map(({ attendanceProfile }) => attendanceProfile));
  const conductKinds = new Set(registered.map(({ conductProfile }) => conductProfile));
  const missingAttendance = ATTENDANCE_PROFILE_WEIGHTS.some(([kind]) => !attendanceKinds.has(kind));
  const missingConduct = CONDUCT_PROFILE_WEIGHTS.some(([kind]) => !conductKinds.has(kind));
  if (!missingAttendance && !missingConduct) return false;
  registered.forEach((agent, index) => {
    if (missingAttendance) agent.attendanceProfile = weightedProfileAt(index, ATTENDANCE_PROFILE_WEIGHTS);
    if (missingConduct) agent.conductProfile = weightedProfileAt(index, CONDUCT_PROFILE_WEIGHTS);
  });
  recordEvent(world, {
    eventType: "synthetic_behavior_profiles_reconciled",
    flow: "simulation.behavior_profile_reconciliation",
    key: "legacy-behavior-profile-reconciliation:v1",
    payload: { attendanceProfiles: ATTENDANCE_PROFILE_WEIGHTS.length, conductProfiles: CONDUCT_PROFILE_WEIGHTS.length },
    virtualDate: world.currentDate,
  });
  return true;
}

function teamForParticipant(world: SyntheticWorld, match: SyntheticMatch, agentId: string) {
  const home = world.state.teams.find(({ id }) => id === match.homeTeamId);
  if (home?.playerIds.includes(agentId)) return home.id;
  const away = match.awayTeamId ? world.state.teams.find(({ id }) => id === match.awayTeamId) : null;
  return away?.playerIds.includes(agentId) ? away.id : null;
}

function opponentTeamId(match: SyntheticMatch, teamId: string) {
  return match.homeTeamId === teamId ? match.awayTeamId : match.homeTeamId;
}

function teamParticipants(world: SyntheticWorld, match: SyntheticMatch, teamId: string) {
  const team = world.state.teams.find(({ id }) => id === teamId);
  if (!team) return [];
  const participantIds = new Set(match.participantIds);
  return team.playerIds.filter((id) => participantIds.has(id));
}

function addRequiredConductScenario(
  world: SyntheticWorld,
  date: string,
  kind: SyntheticConductScenario["kind"],
  targetAgentId: string,
  relatedMatchIds: string[],
  reporterAgentIds: string[],
  sourceTeamIds: string[],
) {
  const uniqueReporters = [...new Set(reporterAgentIds)].filter((id) => id !== targetAgentId);
  const uniqueTeams = [...new Set(sourceTeamIds)];
  const id = deterministicUuid(`${world.id}:required-conduct-scenario`, kind);
  if (world.state.conductScenarios.some((scenario) => scenario.id === id)) return;
  const productCapability = kind === "fair_play_control" ? "not_required" : "not_implemented";
  world.state.conductScenarios.push({
    coverageFixture: true,
    id,
    independentSourceTeams: uniqueTeams.length,
    kind,
    matchId: relatedMatchIds[0]!,
    productCapability,
    relatedMatchIds,
    reporterAgentIds: uniqueReporters,
    sourceTeamIds: uniqueTeams,
    status: "pending",
    targetAgentId,
    virtualDate: date,
  });
  recordEvent(world, {
    actorAgentId: uniqueReporters[0] ?? null,
    entityIds: [...relatedMatchIds, targetAgentId, ...uniqueReporters],
    eventType: productCapability === "not_required" ? "fair_play_control_observed" : "conduct_report_scenario_requires_product",
    flow: productCapability === "not_required" ? "conduct.fair_play_control" : "conduct.player_report",
    key: `required-conduct:${kind}`,
    payload: {
      affectsRatingV2: false,
      automaticSanctionApplied: false,
      independentSourceTeams: uniqueTeams.length,
      kind,
      productCapability,
    },
    status: productCapability === "not_required" ? "pass" : "pending",
    virtualDate: date,
  });
  if (productCapability === "not_implemented") {
    missingCapabilityDemand(world, date, "conduct.player_report", [targetAgentId, ...relatedMatchIds]);
  }
}

export function ensureRequiredConductScenarioCoverage(input: SyntheticWorld) {
  const world = structuredClone(input);
  const matches = world.state.matches
    .filter((match) => match.kind === "challenge" && match.awayTeamId && match.participantIds.length >= 4 && match.state !== "cancelled")
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt) || left.id.localeCompare(right.id));
  if (matches.length === 0) return world;
  const agents = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const occurrences = matches.flatMap((match) => match.participantIds
    .map((agentId) => ({ agent: agents.get(agentId), match, teamId: teamForParticipant(world, match, agentId) }))
    .filter((item): item is { agent: SyntheticAgent; match: SyntheticMatch; teamId: string } => Boolean(item.agent && item.teamId)));

  for (const requirement of REQUIRED_CONDUCT_SCENARIOS) {
    if (world.state.conductScenarios.some(({ coverageFixture, kind }) => coverageFixture && kind === requirement.kind)) continue;
    let occurrence = occurrences.find(({ agent }) => !requirement.profile || agent.conductProfile === requirement.profile) ?? occurrences[0];
    if (!occurrence) continue;
    let relatedMatchIds = [occurrence.match.id];
    let sourceTeamIds: string[] = [];
    let reporterAgentIds: string[] = [];
    const opposingId = opponentTeamId(occurrence.match, occurrence.teamId);
    const opposingReporters = opposingId ? teamParticipants(world, occurrence.match, opposingId) : [];

    if (requirement.kind === "fair_play_control") {
      sourceTeamIds = [];
    } else if (requirement.kind === "independent_team_reports") {
      const byOpponent = new Map<string, { match: SyntheticMatch; reporterId: string }>();
      for (const candidate of occurrences.filter(({ agent }) => agent.id === occurrence.agent.id)) {
        const opponent = opponentTeamId(candidate.match, candidate.teamId);
        const reporter = opponent ? teamParticipants(world, candidate.match, opponent).find((id) => id !== occurrence.agent.id) : null;
        if (opponent && reporter && !byOpponent.has(opponent)) byOpponent.set(opponent, { match: candidate.match, reporterId: reporter });
      }
      if (byOpponent.size < 2) {
        const alternative = occurrences.find((candidate) => {
          const opponents = new Set(occurrences.filter(({ agent }) => agent.id === candidate.agent.id).map((entry) => opponentTeamId(entry.match, entry.teamId)).filter(Boolean));
          return opponents.size >= 2;
        });
        if (alternative) occurrence = alternative;
        byOpponent.clear();
        for (const candidate of occurrences.filter(({ agent }) => agent.id === occurrence.agent.id)) {
          const opponent = opponentTeamId(candidate.match, candidate.teamId);
          const reporter = opponent ? teamParticipants(world, candidate.match, opponent).find((id) => id !== occurrence.agent.id) : null;
          if (opponent && reporter && !byOpponent.has(opponent)) byOpponent.set(opponent, { match: candidate.match, reporterId: reporter });
        }
      }
      const sources = [...byOpponent.entries()].slice(0, 2);
      sourceTeamIds = sources.map(([teamId]) => teamId);
      reporterAgentIds = sources.map(([, value]) => value.reporterId);
      relatedMatchIds = sources.map(([, value]) => value.match.id);
    } else if (requirement.kind === "mutual_conflict") {
      const ownReporter = teamParticipants(world, occurrence.match, occurrence.teamId).find((id) => id !== occurrence.agent.id);
      reporterAgentIds = [opposingReporters[0], ownReporter].filter((id): id is string => Boolean(id));
      sourceTeamIds = [opposingId, occurrence.teamId].filter((id): id is string => Boolean(id));
    } else {
      const reporterLimit = requirement.kind === "same_team_report_burst" || requirement.kind === "coordinated_false_report" ? 5 : 1;
      reporterAgentIds = opposingReporters.slice(0, reporterLimit);
      sourceTeamIds = opposingId ? [opposingId] : [];
    }
    addRequiredConductScenario(world, dateForScenario(world, relatedMatchIds), requirement.kind, occurrence.agent.id, relatedMatchIds, reporterAgentIds, sourceTeamIds);
  }
  return world;
}

function dateForScenario(world: SyntheticWorld, matchIds: string[]) {
  return matchIds.map((id) => world.state.matches.find((match) => match.id === id)?.occurredAt ?? world.currentDate).sort().at(-1) ?? world.currentDate;
}

export function ensureRankingEligibilityCoverage(input: SyntheticWorld) {
  const world = structuredClone(input);
  if (world.state.rankings.some(({ certification }) => certification === "eligible")) return world;
  const agents = new Map(world.state.agents.map((agent) => [agent.id, agent]));
  const candidates = [...world.state.rankings]
    .filter(({ agentId }) => agents.get(agentId)?.attackProfile === "none")
    .sort((left, right) => {
      const leftOnlyNeedsChallenges = left.certificationReasons.length === 1 && left.certificationReasons[0] === "insufficient_challenges";
      const rightOnlyNeedsChallenges = right.certificationReasons.length === 1 && right.certificationReasons[0] === "insufficient_challenges";
      return Number(rightOnlyNeedsChallenges) - Number(leftOnlyNeedsChallenges)
        || left.certificationReasons.length - right.certificationReasons.length
        || right.validChallenges - left.validChallenges
        || left.agentId.localeCompare(right.agentId);
    });
  const selected = candidates.map((row) => {
    const agent = agents.get(row.agentId);
    const team = agent?.teamIds.map((id) => world.state.teams.find((candidate) => candidate.id === id))
      .find((candidate) => candidate && candidate.integrityClusterId !== "synthetic-fake-team-ring");
    const opponents = team ? world.state.teams.filter((candidate) => (
      candidate.id !== team.id
      && candidate.modality === team.modality
      && candidate.integrityClusterId !== team.integrityClusterId
      && candidate.playerIds.filter((id) => team.playerIds.includes(id)).length === 0
    )).sort((left, right) => left.id.localeCompare(right.id)) : [];
    return agent && team && opponents.length >= SYNTHETIC_PROVINCE_TROPHY_RULE.minimumLogicalOpponents ? { agent, opponents, row, team } : null;
  }).find((value): value is NonNullable<typeof value> => Boolean(value));
  if (!selected) return world;

  const required = Math.max(0, SYNTHETIC_PROVINCE_TROPHY_RULE.minimumChallenges - selected.row.validChallenges) + 2;
  const size = TEAM_SIZE[selected.team.modality];
  let created = 0;
  for (let index = 0; index < required; index += 1) {
    const opponent = selected.opponents[index % selected.opponents.length]!;
    const homeIds = [...new Set([selected.agent.id, ...selected.team.playerIds])].slice(0, size);
    const awayIds = opponent.playerIds.filter((id) => !homeIds.includes(id)).slice(0, size);
    if (homeIds.length < size || awayIds.length < size) continue;
    const challengeId = deterministicUuid(`${world.id}:ranking-control-challenge`, `${selected.agent.id}:${index}`);
    const matchId = deterministicUuid(`${world.id}:ranking-control-match`, `${selected.agent.id}:${index}`);
    if (world.state.matches.some(({ id }) => id === matchId)) continue;
    const occurredAt = addVirtualDays(world.config.seasonEnd, -(required - index) * 2).toISOString();
    const venue = world.state.venues.find(({ code, modality }) => code === selected.team.provinceCode && modality === selected.team.modality)
      ?? world.state.venues.find(({ modality }) => modality === selected.team.modality)!;
    const challenge: SyntheticChallenge = {
      awayTeamId: opponent.id,
      createdAt: occurredAt,
      homeTeamId: selected.team.id,
      id: challengeId,
      operationId: deterministicUuid(`${world.id}:ranking-control-create`, challengeId),
      productChallengeId: null,
      proposedAt: occurredAt,
      state: "accepted",
    };
    const match: SyntheticMatch = {
      awayGoals: 1,
      awayTeamId: opponent.id,
      confidence: 0.98,
      evidenceExcluded: false,
      guestIds: [],
      homeGoals: 1,
      homeTeamId: selected.team.id,
      id: matchId,
      kind: "challenge",
      occurredAt,
      participantIds: [...homeIds, ...awayIds],
      productMatchId: null,
      provinceCode: selected.team.provinceCode,
      scorerGoals: { [selected.agent.id]: 1, [awayIds[0]!]: 1 },
      state: "confirmed",
      venueId: venue.id,
    };
    world.state.challenges.push(challenge);
    world.state.matches.push(match);
    for (const agentId of match.participantIds) {
      const teamId = homeIds.includes(agentId) ? selected.team.id : opponent.id;
      world.state.attendanceRecords.push({
        agentId,
        canonicalNoShowDistinguishable: true,
        changedAt: new Date(Date.parse(occurredAt) - 48 * 3_600_000).toISOString(),
        finalOutcome: "played",
        id: deterministicUuid(`${world.id}:ranking-control-attendance`, `${matchId}:${agentId}`),
        initialStatus: "voy",
        matchId,
        teamId,
      });
      recordEvent(world, {
        actorAgentId: agentId,
        entityIds: [matchId, agentId],
        eventType: "match_attendance_joined",
        flow: "match.attendance",
        key: `ranking-control-attendance:${matchId}:${agentId}`,
        payload: { syntheticEligibilityControl: true },
        virtualDate: world.currentDate,
      });
    }
    recordEvent(world, { actorAgentId: selected.team.ownerAgentId, entityIds: [challengeId, selected.team.id, opponent.id], eventType: "challenge_created", flow: "challenge.create", key: `ranking-control-challenge:${challengeId}`, payload: { syntheticEligibilityControl: true }, virtualDate: world.currentDate });
    recordEvent(world, { actorAgentId: opponent.ownerAgentId, entityIds: [challengeId], eventType: "challenge_accepted", flow: "challenge.respond", key: `ranking-control-accepted:${challengeId}`, payload: { syntheticEligibilityControl: true }, virtualDate: world.currentDate });
    recordEvent(world, { actorAgentId: selected.team.ownerAgentId, entityIds: [matchId], eventType: "match_finalized", flow: "match.finalize", key: `ranking-control-finalized:${matchId}`, payload: { result: [1, 1], syntheticEligibilityControl: true }, virtualDate: world.currentDate });
    recordEvent(world, { actorAgentId: selected.team.ownerAgentId, entityIds: [matchId], eventType: "external_result_published", flow: "result.publish", key: `ranking-control-published:${matchId}`, payload: { result: [1, 1], syntheticEligibilityControl: true }, virtualDate: world.currentDate });
    recordEvent(world, { actorAgentId: opponent.ownerAgentId, entityIds: [matchId], eventType: "external_result_confirmed", flow: "result.confirm", key: `ranking-control-confirmed:${matchId}`, payload: { syntheticEligibilityControl: true }, virtualDate: world.currentDate });
    evaluateAchievements(world, match, world.currentDate);
    createRatingOpinions(world, match, world.currentDate, new SeededRandom(`${world.seed}:ranking-control:${index}`));
    created += 1;
  }
  if (created > 0) {
    recordEvent(world, {
      eventType: "ranking_eligibility_control_completed",
      flow: "ranking.eligibility_control",
      key: `ranking-eligibility-control:${selected.agent.id}`,
      payload: { agentId: selected.agent.id, canonicalFlows: true, createdMatches: created, formulasChanged: false, ratingV2Changed: false },
      virtualDate: world.currentDate,
    });
  }
  return world;
}

function finalizeMatch(world: SyntheticWorld, match: SyntheticMatch, date: string, random: SeededRandom) {
  const home = world.state.teams.find(({ id }) => id === match.homeTeamId)!;
  const away = match.awayTeamId ? world.state.teams.find(({ id }) => id === match.awayTeamId) ?? null : null;
  const size = TEAM_SIZE[home.modality];
  const homeCapacity = match.kind === "internal" ? size * 2 : size;
  const homeConfirmed = eligiblePlayers(world, home, date, random.fork("home"), homeCapacity);
  const excluded = new Set(homeConfirmed.map(({ id }) => id));
  const awayConfirmed = away ? eligiblePlayers(world, away, date, random.fork("away"), size, excluded) : [];
  const homePlayers = applyAttendanceOutcomes(world, match, home, homeConfirmed, date, random.fork("home-attendance"));
  const awayPlayers = away ? applyAttendanceOutcomes(world, match, away, awayConfirmed, date, random.fork("away-attendance")) : [];
  const needed = match.kind === "internal" ? size * 2 : size * 2;
  const participants = [...homePlayers, ...awayPlayers];
  const localGuests = world.state.agents.filter((agent) => agent.kind === "guest" && agent.provinceCode === home.provinceCode);
  const attemptedGuestIds = new Set<string>();
  while (participants.length < needed && localGuests.length > 0 && random.bool(0.62)) {
    const availableGuests = localGuests.filter((agent) => !participants.some(({ id }) => id === agent.id) && !attemptedGuestIds.has(agent.id));
    if (availableGuests.length === 0) break;
    const guest = random.pick(availableGuests);
    attemptedGuestIds.add(guest.id);
    if (random.bool(0.055)) {
      const scenarioId = deterministicUuid(`${world.id}:guest-withdrawal`, `${match.id}:${guest.id}`);
      const dismissed = random.bool(0.22);
      world.state.conductScenarios.push({
        id: scenarioId,
        independentSourceTeams: 1,
        kind: "guest_withdrawal_review",
        matchId: match.id,
        productCapability: "implemented_guest_withdrawal_only",
        relatedMatchIds: [match.id],
        reporterAgentIds: [home.ownerAgentId],
        sourceTeamIds: [home.id],
        status: dismissed ? "dismissed" : "reviewed",
        targetAgentId: guest.id,
        virtualDate: date,
      });
      world.state.attendanceRecords.push({
        agentId: guest.id,
        canonicalNoShowDistinguishable: true,
        changedAt: attendanceChangeDate(match.occurredAt, "cancelled_early"),
        finalOutcome: "cancelled_early",
        id: deterministicUuid(`${world.id}:attendance`, `${match.id}:${guest.id}:withdrawal`),
        initialStatus: "voy",
        matchId: match.id,
        teamId: home.id,
      });
      recordEvent(world, {
        actorAgentId: guest.id,
        entityIds: [match.id, guest.id, scenarioId],
        eventType: "match_guest_left",
        flow: "conduct.guest_withdrawal",
        key: `guest-withdrawal:${scenarioId}`,
        payload: { accessRevoked: true, affectsRatingV2: false },
        virtualDate: date,
      });
      recordEvent(world, {
        actorAgentId: home.ownerAgentId,
        entityIds: [match.id, guest.id, scenarioId],
        eventType: dismissed ? "match_guest_withdrawal_dismissed" : "match_guest_withdrawal_confirmed",
        flow: "conduct.guest_withdrawal.review",
        key: `guest-withdrawal-review:${scenarioId}`,
        payload: { affectsRatingV2: false, reviewStatus: dismissed ? "dismissed" : "confirmed" },
        virtualDate: date,
      });
      notify(world, date, home.ownerAgentId, "match_guest_withdrawal_review", scenarioId, `guest-withdrawal:${scenarioId}:${home.ownerAgentId}`);
      continue;
    }
    participants.push(guest);
    match.guestIds.push(guest.id);
    if (participants.length >= needed || participants.length >= homeCapacity + size) break;
  }
  if (participants.length < Math.ceil(needed * 0.6)) {
    match.state = "cancelled";
    recordEvent(world, { actorAgentId: home.ownerAgentId, entityIds: [match.id], eventType: "match_cancelled_low_attendance", flow: "match.finalize", key: `cancel:${match.id}`, payload: { participants: participants.length }, virtualDate: date });
    return;
  }
  match.participantIds = participants.map(({ id }) => id);
  const attackMatch = away?.integrityClusterId === "synthetic-fake-team-ring" && home.integrityClusterId === "synthetic-fake-team-ring";
  const homeExpected = 1 / (1 + 10 ** (((away?.strength ?? home.strength) - home.strength) / 24));
  match.homeGoals = poisson(random.fork("score-home"), 1.7 + homeExpected * 2.3 + (attackMatch ? 2 : 0));
  match.awayGoals = poisson(random.fork("score-away"), match.kind === "internal" ? 2.1 : 1.4 + (1 - homeExpected) * 2.1);
  match.scorerGoals = {};
  let homeScorers = match.kind === "internal" ? participants.slice(0, Math.ceil(participants.length / 2)) : [...homePlayers];
  let awayScorers = match.kind === "internal" ? participants.slice(Math.ceil(participants.length / 2)) : [...awayPlayers];
  if (match.kind === "challenge") {
    const guestPlayers = participants.filter(({ kind }) => kind === "guest");
    for (const guest of guestPlayers) {
      if (homeScorers.length < size) homeScorers.push(guest);
      else awayScorers.push(guest);
    }
    if (homeScorers.length === 0) [homeScorers, awayScorers] = [awayScorers.slice(0, 1), awayScorers.slice(1)];
    if (awayScorers.length === 0) [homeScorers, awayScorers] = [homeScorers.slice(0, -1), homeScorers.slice(-1)];
  }
  assignGoals(random.fork("scorers-home"), homeScorers, match.homeGoals, match.scorerGoals);
  assignGoals(random.fork("scorers-away"), awayScorers, match.awayGoals, match.scorerGoals);
  match.evidenceExcluded = match.kind === "internal" || attackMatch || participants.some(({ attackProfile }) => attackProfile === "ghost_participant");
  const participationRatio = participants.length / needed;
  match.confidence = clamp(0.42 + participationRatio * 0.42 + (attackMatch ? -0.5 : 0) + random.decimal(-0.08, 0.08), 0.05, 0.99);
  const disputed = match.kind === "challenge" && random.bool(attackMatch ? 0.26 : 0.075);
  const autoConfirmed = !disputed && match.kind === "challenge" && random.bool(0.13);
  match.state = disputed ? "disputed" : autoConfirmed ? "auto_confirmed" : "confirmed";
  recordEvent(world, {
    actorAgentId: home.ownerAgentId,
    entityIds: [match.id],
    eventType: "match_finalized",
    flow: "match.finalize",
    key: `finalize:${match.id}`,
    payload: { expectedRevision: world.revision, participants: participants.length, result: [match.homeGoals, match.awayGoals] },
    virtualDate: date,
  });
  // A retry with the same operation id must resolve to the same receipt, never duplicate the effect.
  if (random.bool(0.12)) recordEvent(world, { actorAgentId: home.ownerAgentId, entityIds: [match.id], eventType: "match_finalized", flow: "match.finalize", key: `finalize:${match.id}`, payload: {}, virtualDate: date });
  if (match.kind === "challenge") {
    recordEvent(world, { actorAgentId: home.ownerAgentId, entityIds: [match.id], eventType: "external_result_published", flow: "result.publish", key: `result-publish:${match.id}`, payload: { result: [match.homeGoals, match.awayGoals] }, virtualDate: date });
    if (disputed) {
      recordEvent(world, { actorAgentId: away?.ownerAgentId ?? null, entityIds: [match.id], eventType: "external_result_disputed", flow: "result.counter", key: `result-dispute:${match.id}`, payload: { proposedDelta: random.pick([-1, 1]) }, virtualDate: date });
    } else if (autoConfirmed) {
      recordEvent(world, { actorAgentId: null, entityIds: [match.id], eventType: "external_result_auto_confirmed", flow: "result.auto_confirm", key: `result-auto:${match.id}`, virtualDate: date });
    } else {
      recordEvent(world, { actorAgentId: away?.ownerAgentId ?? null, entityIds: [match.id], eventType: "external_result_confirmed", flow: "result.confirm", key: `result-confirm:${match.id}`, virtualDate: date });
    }
  }
  if (!disputed) {
    evaluateAchievements(world, match, date);
    createRatingOpinions(world, match, date, random.fork("ratings"));
    createConductScenario(world, match, date, random.fork("conduct"));
  }
  [...new Set([home.ownerAgentId, away?.ownerAgentId].filter((id): id is string => Boolean(id)))].forEach((agentId) => (
    notify(world, date, agentId, disputed ? "external_result_action_required" : "match_result_confirmed", match.id, `match-result:${match.id}:${agentId}`)
  ));
}

function resolveDisputes(world: SyntheticWorld, date: string, random: SeededRandom) {
  const due = world.state.matches.filter((match) => match.state === "disputed" && virtualDaysBetween(match.occurredAt, date) >= 2);
  for (const match of due) {
    const away = match.awayTeamId ? world.state.teams.find(({ id }) => id === match.awayTeamId) : null;
    if (random.bool(0.24)) {
      match.homeGoals = Math.max(0, (match.homeGoals ?? 0) + random.pick([-1, 1]));
      match.scorerGoals = {};
      const participants = match.participantIds.map((id) => world.state.agents.find((agent) => agent.id === id)).filter((agent): agent is SyntheticAgent => Boolean(agent));
      assignGoals(random.fork(`corrected:${match.id}`), participants, (match.homeGoals ?? 0) + (match.awayGoals ?? 0), match.scorerGoals);
      recordEvent(world, { actorAgentId: away?.ownerAgentId ?? null, entityIds: [match.id], eventType: "external_result_correction_accepted", flow: "result.counter", key: `result-correction:${match.id}`, payload: { corrected: true }, virtualDate: date });
    } else {
      recordEvent(world, { actorAgentId: away?.ownerAgentId ?? null, entityIds: [match.id], eventType: "external_result_change_rejected", flow: "result.reject", key: `result-reject:${match.id}`, virtualDate: date });
    }
    match.state = "confirmed";
    recordEvent(world, { actorAgentId: away?.ownerAgentId ?? null, entityIds: [match.id], eventType: "external_result_reconciled", flow: "result.confirm", key: `result-reconciled:${match.id}`, virtualDate: date });
    evaluateAchievements(world, match, date);
    createRatingOpinions(world, match, date, random.fork(`ratings:${match.id}`));
  }
}

function resolveDueMatches(world: SyntheticWorld, date: string, random: SeededRandom) {
  const due = world.state.matches.filter((match) => match.state === "scheduled" && match.occurredAt.slice(0, 10) <= date.slice(0, 10));
  due.forEach((match) => finalizeMatch(world, match, date, random.fork(match.id)));
}

function updateAgentAvailability(world: SyntheticWorld, date: string, random: SeededRandom) {
  for (const agent of world.state.agents.filter(({ kind }) => kind === "registered")) {
    if (agent.status === "future" && agent.availableFrom <= date) {
      agent.status = "active";
      recordEvent(world, { actorAgentId: agent.id, entityIds: [agent.id], eventType: "synthetic_user_activated", flow: "rating.assessment", key: `activate:${agent.id}`, virtualDate: date });
    }
    if (agent.status === "unavailable" && agent.unavailableUntil && agent.unavailableUntil <= date) {
      agent.status = "active";
      agent.unavailableReason = null;
      agent.unavailableUntil = null;
      recordEvent(world, { actorAgentId: agent.id, entityIds: [agent.id], eventType: "player_availability_available", flow: "attendance.recovery_notification", key: `recovery:${agent.id}:${date.slice(0, 10)}`, virtualDate: date });
      agent.teamIds.flatMap((teamId) => world.state.teams.find((team) => team.id === teamId)?.adminAgentIds ?? []).forEach((adminId) => notify(world, date, adminId, "player_availability_available", agent.id, `recovery:${agent.id}:${date}:${adminId}`));
    }
    if (agent.status === "active" && random.bool(0.00042)) {
      agent.status = "unavailable";
      agent.unavailableReason = "synthetic_injury";
      agent.unavailableUntil = addVirtualDays(date, random.integer(7, 45)).toISOString();
      recordEvent(world, { actorAgentId: agent.id, entityIds: [agent.id], eventType: "player_availability_unavailable", flow: "attendance.injury_notification", key: `injury:${agent.id}:${date.slice(0, 10)}`, payload: { unavailableUntil: agent.unavailableUntil }, virtualDate: date });
      agent.teamIds.flatMap((teamId) => world.state.teams.find((team) => team.id === teamId)?.adminAgentIds ?? []).forEach((adminId) => notify(world, date, adminId, "player_availability_unavailable", agent.id, `injury:${agent.id}:${date}:${adminId}`));
    }
  }
}

function runMarket(world: SyntheticWorld, date: string, random: SeededRandom) {
  if (new Date(date).getUTCDay() !== 1) return;
  const free = world.state.agents.filter((agent) => agent.kind === "registered" && agent.status === "active" && agent.teamIds.length === 0 && agent.behavior.marketAffinity > 0.35);
  for (const agent of random.sample(free, Math.min(free.length, random.integer(1, 4)))) {
    recordEvent(world, { actorAgentId: agent.id, entityIds: [agent.id], eventType: "market_profile_published", flow: "market.player_profile", key: `market-profile:${agent.id}:${date.slice(0, 10)}`, virtualDate: date });
    const candidates = world.state.teams.filter((team) => team.marketPolicy !== "never" && team.modality !== "futbol11" && team.provinceCode === agent.provinceCode && team.playerIds.length < 18);
    if (candidates.length === 0 || !random.bool(agent.behavior.marketAffinity * 0.45)) continue;
    const team = random.pick(candidates);
    team.playerIds.push(agent.id);
    agent.teamIds.push(team.id);
    team.strength = Math.round(((team.strength * (team.playerIds.length - 1) + agent.ratingV2) / team.playerIds.length) * 10) / 10;
    recordEvent(world, { actorAgentId: agent.id, entityIds: [agent.id, team.id], eventType: "market_player_joined_team", flow: "team.join", key: `market-join:${agent.id}:${team.id}`, payload: { expectedRevision: world.revision }, virtualDate: date });
    team.adminAgentIds.forEach((adminId) => notify(world, date, adminId, "market_player_joined", agent.id, `market-join:${agent.id}:${team.id}:${adminId}`));
  }
}

function processNotificationsAndBoxes(world: SyntheticWorld, date: string, random: SeededRandom) {
  for (const notification of world.state.notifications.filter(({ readAt, visibleInApp }) => !readAt && visibleInApp)) {
    const agent = world.state.agents.find(({ id }) => id === notification.agentId);
    if (!agent || agent.status === "dormant") continue;
    const ageHours = virtualDaysBetween(notification.createdAt, date) * 24;
    if (ageHours >= agent.behavior.notificationDelayHours && random.bool(0.72)) {
      notification.readAt = date;
      recordEvent(world, { actorAgentId: agent.id, entityIds: [notification.id], eventType: "notification_read", flow: "notification.read", key: `notification-read:${notification.id}`, virtualDate: date });
    }
  }
  for (const box of world.state.boxes.filter(({ openedAt }) => !openedAt)) {
    const agentId = box.agentId ?? world.state.teams.find(({ id }) => id === box.teamId)?.ownerAgentId;
    const agent = agentId ? world.state.agents.find(({ id }) => id === agentId) : null;
    if (!agent || agent.status === "dormant" || virtualDaysBetween(box.createdAt, date) < random.integer(1, 5)) continue;
    box.openedAt = date;
    if (random.bool(0.25)) {
      const cosmetic = random.weighted(PLAYER_COSMETIC_CATALOG.map((entry) => ({
        value: entry,
        weight: entry.rarity === "common" ? 40
          : entry.rarity === "uncommon" ? 27
            : entry.rarity === "rare" ? 18
              : entry.rarity === "epic" ? 10 : 5,
      })));
      const owned = world.state.playerCosmeticInventory.find((item) => (
        item.agentId === agent.id && item.cosmeticKey === cosmetic.key
      ));
      const duplicatePoints = cosmetic.rarity === "common" ? 4
        : cosmetic.rarity === "uncommon" ? 8
          : cosmetic.rarity === "rare" ? 16
            : cosmetic.rarity === "epic" ? 28 : 45;
      box.cosmeticKey = cosmetic.key;
      box.cosmeticGranted = !owned;
      box.duplicatePoints = owned ? duplicatePoints : 0;
      box.points = owned ? duplicatePoints : 0;

      if (!owned) {
        const inventoryItem: SyntheticPlayerCosmeticInventoryItem = {
          acquiredAt: date,
          agentId: agent.id,
          cosmeticKey: cosmetic.key,
          seenAt: null,
          sourceBoxId: box.id,
        };
        world.state.playerCosmeticInventory.push(inventoryItem);
        recordEvent(world, {
          actorAgentId: agent.id,
          entityIds: [box.id, cosmetic.key],
          eventType: "player_cosmetic_inventory_granted",
          flow: "cosmetic.inventory_grant",
          key: `cosmetic-grant:${box.id}:${cosmetic.key}`,
          payload: { cosmeticKey: cosmetic.key, duplicateConverted: false, seen: false },
          virtualDate: date,
        });
        notify(world, date, agent.id, "player_reward_cosmetic_unlocked", box.id, `player-cosmetic:${agent.id}:${cosmetic.key}`);

        if (random.bool(0.7)) {
          inventoryItem.seenAt = date;
          recordEvent(world, {
            actorAgentId: agent.id,
            entityIds: [cosmetic.key],
            eventType: "player_cosmetic_marked_seen",
            flow: "cosmetic.mark_seen",
            key: `cosmetic-seen:${box.id}:${cosmetic.key}`,
            payload: { cosmeticKey: cosmetic.key, expectedRevision: 1 },
            virtualDate: date,
          });
        }

        if (random.bool(0.52)) {
          let loadout: SyntheticPlayerCosmeticLoadout | undefined = world.state.playerCosmeticLoadouts.find((item) => item.agentId === agent.id);
          if (!loadout) {
            loadout = { accentKey: null, agentId: agent.id, backgroundKey: null, effectKey: null, frameKey: null, revision: 1, titleKey: null, updatedAt: date };
            world.state.playerCosmeticLoadouts.push(loadout);
          }
          const expectedRevision = loadout.revision;
          if (cosmetic.slot === "frame") loadout.frameKey = cosmetic.key;
          else if (cosmetic.slot === "background") loadout.backgroundKey = cosmetic.key;
          else if (cosmetic.slot === "accent") loadout.accentKey = cosmetic.key;
          else if (cosmetic.slot === "effect") loadout.effectKey = cosmetic.key;
          else loadout.titleKey = cosmetic.key;
          loadout.revision += 1;
          loadout.updatedAt = date;
          inventoryItem.seenAt ??= date;
          recordEvent(world, {
            actorAgentId: agent.id,
            entityIds: [box.id, cosmetic.key],
            eventType: "player_cosmetic_equipped_from_box",
            flow: "cosmetic.equip_from_box",
            key: `cosmetic-equip:${box.id}:${cosmetic.key}`,
            payload: { confirmedRevision: loadout.revision, expectedRevision, realtimeConverged: true },
            virtualDate: date,
          });
          if (random.bool(0.08)) {
            recordEvent(world, {
              actorAgentId: agent.id,
              entityIds: [agent.id],
              eventType: "player_cosmetic_stale_revision_rejected",
              flow: "cosmetic.save_loadout",
              key: `cosmetic-stale:${box.id}:${cosmetic.key}`,
              payload: { attemptedRevision: expectedRevision, canonicalRevision: loadout.revision, optimisticStateRemoved: true },
              virtualDate: date,
            });
          }
        }
      } else {
        recordEvent(world, {
          actorAgentId: agent.id,
          entityIds: [box.id, cosmetic.key],
          eventType: "player_cosmetic_duplicate_converted",
          flow: "cosmetic.inventory_grant",
          key: `cosmetic-duplicate:${box.id}:${cosmetic.key}`,
          payload: { cosmeticKey: cosmetic.key, duplicateConverted: true, duplicatePoints, originalSeenAt: owned.seenAt },
          virtualDate: date,
        });
      }
    } else {
      box.points = random.weighted([{ value: 25, weight: 45 }, { value: 50, weight: 33 }, { value: 100, weight: 17 }, { value: 250, weight: 5 }]);
    }
    recordEvent(world, {
      actorAgentId: agent.id,
      entityIds: [box.id],
      eventType: "reward_box_opened",
      flow: "reward.open_box",
      key: `box-open:${box.id}`,
      payload: {
        cosmeticGranted: box.cosmeticGranted,
        cosmeticKey: box.cosmeticKey,
        duplicatePoints: box.duplicatePoints,
        points: box.points,
      },
      virtualDate: date,
    });
  }
}

function recordInvariantCoverage(world: SyntheticWorld, date: string, weekly: boolean) {
  const result = evaluateInvariants(world, date, weekly);
  for (const check of result.checks) coverage(world, weekly ? "invariant.weekly" : "invariant.daily", date, check.pass);
  for (const incident of result.incidents) {
    const existing = world.state.incidents.find(({ id }) => id === incident.id);
    if (existing) {
      existing.occurrenceCount += 1;
      existing.virtualDate = date;
    } else world.state.incidents.push(incident);
  }
  recordEvent(world, {
    eventType: weekly ? "weekly_invariants_evaluated" : "daily_invariants_evaluated",
    flow: weekly ? "invariant.weekly" : "invariant.daily",
    key: `${weekly ? "weekly" : "daily"}-invariants:${date.slice(0, 10)}`,
    payload: { checks: result.checks.length, failures: result.incidents.length },
    status: result.incidents.length === 0 ? "pass" : "failed",
    virtualDate: date,
  });
}

function advanceOneDay(world: SyntheticWorld, date: string, failureInjectionRate: number) {
  const dayKey = date.slice(0, 10);
  const random = new SeededRandom(`${world.seed}:${dayKey}:${world.revision}`);
  world.currentDate = date;
  bootstrapCoverage(world, date);
  updateAgentAvailability(world, date, random.fork("availability"));
  runMarket(world, date, random.fork("market"));
  resolveDisputes(world, date, random.fork("disputes"));
  if (virtualDaysBetween(date, world.config.seasonEnd) > 14) {
    createDailyChallenges(world, date, random.fork("challenges"));
  }
  scheduleInternalMatches(world, date, random.fork("internal"));
  resolveDueMatches(world, date, random.fork("due"));
  processNotificationsAndBoxes(world, date, random.fork("inbox"));
  const weekBoundary = new Date(date).getUTCDay() === 0;
  if (weekBoundary) {
    world.state.rankings = calculateRankings(world);
    recordEvent(world, { eventType: "season_ranking_recalculated", flow: "ranking.season_score_v3", key: `ranking:${dayKey}`, payload: { rows: world.state.rankings.length, strategy: "exclusion_and_hold", weights: "55/30/15" }, virtualDate: date });
  }
  if (failureInjectionRate > 0 && random.bool(failureInjectionRate)) {
    recordEvent(world, { eventType: "injected_failure_observed", expected: { detector: "must_create_incident" }, flow: "failure.injection", key: `failure:${dayKey}`, payload: { injected: true }, status: "failed", virtualDate: date });
    const incidentId = deterministicUuid(`${world.id}:injected-incident`, dayKey);
    if (!world.state.incidents.some(({ id }) => id === incidentId)) world.state.incidents.push({
      actual: { injectedFailureDetected: true },
      actorAgentId: null,
      afterState: {},
      beforeState: {},
      category: "FLOW_ERROR",
      expected: { incidentRecorded: true },
      id: incidentId,
      occurrenceCount: 1,
      operation: "failure.injection",
      relatedEntityIds: [],
      reproductionSteps: [`Create world with seed ${world.seed}`, `Advance to ${dayKey} with failure injection enabled`],
      severity: "low",
      status: "regression_verified",
      virtualDate: date,
    });
  }
  recordInvariantCoverage(world, date, weekBoundary);
  world.revision += 1;
}

export function advanceSyntheticWorld(input: SyntheticWorld, options: AdvanceSyntheticWorldOptions) {
  const world = structuredClone(input);
  const target = new Date(options.targetDate).toISOString();
  const seasonEnd = new Date(world.config.seasonEnd).toISOString();
  if (target > seasonEnd) throw new Error(`Target ${target} exceeds synthetic season end ${seasonEnd}`);
  world.status = "active";
  for (const date of eachVirtualDayExclusive(world.currentDate, target)) {
    advanceOneDay(world, date.toISOString(), options.failureInjectionRate ?? 0);
  }
  if (world.currentDate.slice(0, 10) >= seasonEnd.slice(0, 10)) {
    world.status = "completed";
    world.state.rankings = calculateRankings(world);
    if (options.rankingEligibilityCoverage === true) world.state = ensureRankingEligibilityCoverage(world).state;
    world.state.rankings = calculateRankings(world);
    world.state = ensureRequiredConductScenarioCoverage(world).state;
  } else {
    world.status = "paused";
  }
  return world;
}

export function advanceSyntheticWorldByDays(world: SyntheticWorld, days: number, options: Omit<AdvanceSyntheticWorldOptions, "targetDate"> = {}) {
  return advanceSyntheticWorld(world, { ...options, targetDate: addVirtualDays(world.currentDate, days).toISOString() });
}

export function advanceSyntheticWorldByHours(
  input: SyntheticWorld,
  hours: number,
  options: Omit<AdvanceSyntheticWorldOptions, "targetDate"> = {},
) {
  if (!Number.isInteger(hours) || hours <= 0) throw new Error("Virtual hours must be a positive integer");
  const targetDate = new Date(new Date(input.currentDate).getTime() + hours * 3_600_000).toISOString();
  const world = advanceSyntheticWorld(input, { ...options, targetDate });
  world.currentDate = targetDate;
  world.status = targetDate >= world.config.seasonEnd ? "completed" : "paused";
  recordEvent(world, {
    eventType: "virtual_clock_advanced",
    flow: "simulation.clock",
    key: `clock:${input.revision}:${targetDate}`,
    payload: { hours, previousDate: input.currentDate },
    virtualDate: targetDate,
  });
  if (world.revision === input.revision) world.revision += 1;
  return world;
}

export function cloneSyntheticWorldFromCurrent(world: SyntheticWorld, seed: number, name?: string) {
  const clone = structuredClone(world);
  clone.id = deterministicUuid("pachangas-synthetic-world-clone", `${world.id}:${seed}`);
  clone.name = name ?? `${world.name} · clone ${seed}`;
  clone.seed = seed;
  clone.mode = "persistent";
  clone.createdAt = new Date().toISOString();
  clone.revision = 0;
  return clone;
}

export function reconcileSyntheticConductCoverage(input: SyntheticWorld) {
  const prepared = structuredClone(input);
  const profilesChanged = reconcileLegacyBehaviorProfiles(prepared);
  const world = ensureRequiredConductScenarioCoverage(prepared);
  if (profilesChanged || world.state.conductScenarios.length > input.state.conductScenarios.length) world.revision += 1;
  return world;
}

export function reconcileSyntheticRankingCoverage(input: SyntheticWorld) {
  const prepared = structuredClone(input);
  prepared.state.rankings = calculateRankings(prepared);
  const world = ensureRankingEligibilityCoverage(prepared);
  world.state.rankings = calculateRankings(world);
  if (world.state.matches.length > input.state.matches.length) world.revision += 1;
  return world;
}

export function syntheticWorldSummary(world: SyntheticWorld) {
  const confirmed = world.state.matches.filter(({ state }) => state === "confirmed" || state === "auto_confirmed");
  const noShowsByAgent = new Map<string, number>();
  for (const record of world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "no_show")) {
    noShowsByAgent.set(record.agentId, (noShowsByAgent.get(record.agentId) ?? 0) + 1);
  }
  return {
    achievements: world.state.achievements.length,
    activeAgents: world.state.agents.filter(({ status }) => status === "active").length,
    attendanceCancellations: world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "cancelled_early" || finalOutcome === "cancelled_late").length,
    boxes: world.state.boxes.length,
    cosmeticDuplicates: world.state.boxes.filter(({ cosmeticGranted, cosmeticKey }) => cosmeticKey && cosmeticGranted === false).length,
    cosmeticInventory: world.state.playerCosmeticInventory.length,
    cosmeticLoadouts: world.state.playerCosmeticLoadouts.length,
    cosmeticUnseen: world.state.playerCosmeticInventory.filter(({ seenAt }) => !seenAt).length,
    challenges: world.state.challenges.length,
    confirmedMatches: confirmed.length,
    conductScenariosNeedingProduct: world.state.conductScenarios.filter(({ productCapability }) => productCapability === "not_implemented").length,
    currentDate: world.currentDate,
    events: world.state.events.length,
    guests: world.state.agents.filter(({ kind }) => kind === "guest").length,
    incidents: world.state.incidents.length,
    notifications: world.state.notifications.length,
    possibleNoShows: world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "no_show").length,
    possibleRepeatNoShowAgents: [...noShowsByAgent.values()].filter((count) => count >= 2).length,
    opinions: world.state.ratingOpinions.length,
    rankings: world.state.rankings.length,
    registeredAgents: world.state.agents.filter(({ kind }) => kind === "registered").length,
    revision: world.revision,
    scheduledMatches: world.state.matches.filter(({ state }) => state === "scheduled").length,
    teams: world.state.teams.length,
    totalMatches: world.state.matches.length,
    rankingEvidenceMatches: confirmed.filter(({ kind }) => kind === "challenge").length,
    rankingEvidenceMatchesMarkedExcluded: confirmed.filter(({ kind, evidenceExcluded }) => kind === "challenge" && evidenceExcluded).length,
    rankingEvidenceMatchesMarkedValid: confirmed.filter(({ kind, evidenceExcluded }) => kind === "challenge" && !evidenceExcluded).length,
    virtualWeeks: virtualWeek(world.startDate, world.currentDate),
  };
}
