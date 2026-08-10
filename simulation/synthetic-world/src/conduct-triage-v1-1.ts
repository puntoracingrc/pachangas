import type { SyntheticConductScenario, SyntheticWorld } from "./types";
import { replayNoShowCandidate } from "./conduct-v1";

export type ConductTriageQueue = "record_only" | "watch" | "review" | "priority_review" | "urgent_review";

export type ConductTriageReasonCode =
  | "ACTIVE_WINDOW_EXPIRED"
  | "CATEGORY_DISCRIMINATORY_BEHAVIOR"
  | "CATEGORY_HARASSMENT"
  | "CATEGORY_THREATS_OR_VIOLENCE"
  | "CORRELATED_SOURCE_CLUSTER"
  | "DISTINCT_CONTEXTS_2_PLUS"
  | "INDEPENDENT_SOURCES_2"
  | "INDEPENDENT_SOURCES_3_PLUS"
  | "ISOLATED_NON_SERIOUS_SIGNAL"
  | "MUTUAL_RETALIATION"
  | "RECENT_COMPATIBLE_SIGNALS_1"
  | "RECENT_COMPATIBLE_SIGNALS_2_PLUS";

export type ConductTriageInput = {
  category: string;
  contextIds: string[];
  correlatedReportCount: number;
  independentSourceCount: number;
  mutualRetaliation: boolean;
  priorCompatibleSignalDates: string[];
  rawReportCount: number;
  reportedAt: string;
  sourceTeamIds: string[];
};

type CategoryPolicy = {
  activeWindowDays: number;
  isolatedQueue: ConductTriageQueue;
};

export const CONDUCT_TRIAGE_POLICY_V1_1 = {
  categories: {
    abusive_behavior: { activeWindowDays: 180, isolatedQueue: "record_only" },
    deliberate_cheating: { activeWindowDays: 180, isolatedQueue: "record_only" },
    discriminatory_behavior: { activeWindowDays: 365, isolatedQueue: "review" },
    harassment: { activeWindowDays: 365, isolatedQueue: "review" },
    other: { activeWindowDays: 90, isolatedQueue: "record_only" },
    repeated_disruption: { activeWindowDays: 180, isolatedQueue: "record_only" },
    threats_or_violence: { activeWindowDays: 365, isolatedQueue: "urgent_review" },
  } satisfies Record<string, CategoryPolicy>,
  policyVersion: "conduct-triage-v1.1-experimental",
  slaHours: { priority_review: 24, review: 72, urgent_review: 4 },
} as const;

const QUEUE_RANK: Record<ConductTriageQueue, number> = {
  record_only: 0,
  watch: 1,
  review: 2,
  priority_review: 3,
  urgent_review: 4,
};

const HUMAN_QUEUES = new Set<ConductTriageQueue>(["review", "priority_review", "urgent_review"]);
const DAY_MS = 86_400_000;

function maxQueue(left: ConductTriageQueue, right: ConductTriageQueue) {
  return QUEUE_RANK[left] >= QUEUE_RANK[right] ? left : right;
}

function policyFor(category: string): CategoryPolicy {
  return CONDUCT_TRIAGE_POLICY_V1_1.categories[category as keyof typeof CONDUCT_TRIAGE_POLICY_V1_1.categories]
    ?? CONDUCT_TRIAGE_POLICY_V1_1.categories.other;
}

function unique(values: string[]) {
  return [...new Set(values.filter(Boolean))];
}

export function evaluateConductTriageV11(input: ConductTriageInput) {
  const policy = policyFor(input.category);
  const reportedAt = Date.parse(input.reportedAt);
  const activeFrom = reportedAt - policy.activeWindowDays * DAY_MS;
  const activePriorSignals = input.priorCompatibleSignalDates.filter((value) => {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) && parsed >= activeFrom && parsed <= reportedAt;
  });
  const sourceTeams = unique(input.sourceTeamIds);
  const contexts = unique(input.contextIds);
  const reasons: ConductTriageReasonCode[] = [];
  let queue = policy.isolatedQueue;

  if (input.category === "threats_or_violence") reasons.push("CATEGORY_THREATS_OR_VIOLENCE");
  if (input.category === "discriminatory_behavior") reasons.push("CATEGORY_DISCRIMINATORY_BEHAVIOR");
  if (input.category === "harassment") reasons.push("CATEGORY_HARASSMENT");
  if (input.correlatedReportCount > 0 || input.rawReportCount > Math.max(1, input.independentSourceCount)) {
    reasons.push("CORRELATED_SOURCE_CLUSTER");
  }
  if (input.mutualRetaliation) reasons.push("MUTUAL_RETALIATION");
  if (input.independentSourceCount >= 3 || sourceTeams.length >= 3) {
    reasons.push("INDEPENDENT_SOURCES_3_PLUS");
    queue = maxQueue(queue, "priority_review");
  } else if (input.independentSourceCount >= 2 || sourceTeams.length >= 2) {
    reasons.push("INDEPENDENT_SOURCES_2");
    queue = maxQueue(queue, "review");
  }
  if (contexts.length >= 2) reasons.push("DISTINCT_CONTEXTS_2_PLUS");
  if (activePriorSignals.length >= 2) {
    reasons.push("RECENT_COMPATIBLE_SIGNALS_2_PLUS");
    queue = maxQueue(queue, contexts.length >= 2 ? "priority_review" : "watch");
  } else if (activePriorSignals.length === 1) {
    reasons.push("RECENT_COMPATIBLE_SIGNALS_1");
    queue = maxQueue(queue, "watch");
  }
  if (input.priorCompatibleSignalDates.length > activePriorSignals.length) reasons.push("ACTIVE_WINDOW_EXPIRED");
  if (queue === "record_only" && reasons.length === 0) reasons.push("ISOLATED_NON_SERIOUS_SIGNAL");

  return {
    activePriorSignalCount: activePriorSignals.length,
    activeWindowDays: policy.activeWindowDays,
    activeWindowEndsAt: new Date(reportedAt + policy.activeWindowDays * DAY_MS).toISOString(),
    humanReviewRequired: HUMAN_QUEUES.has(queue),
    policyVersion: CONDUCT_TRIAGE_POLICY_V1_1.policyVersion,
    queue,
    reasonCodes: unique(reasons),
    sanctionApplied: false,
  };
}

function scenarioCategory(scenario: SyntheticConductScenario) {
  if (scenario.kind === "conflict_prone_incident") return "harassment";
  if (scenario.kind === "repeat_offender" || scenario.kind === "independent_team_reports" || scenario.kind === "same_team_report_burst") {
    return "repeated_disruption";
  }
  if (scenario.kind === "single_clean_history_report" || scenario.kind === "coordinated_false_report") return "other";
  return "abusive_behavior";
}

function seriousGroundTruth(scenario: SyntheticConductScenario) {
  return scenario.kind === "conflict_prone_incident"
    || scenario.kind === "independent_team_reports"
    || scenario.kind === "repeat_offender";
}

function scenarioEvidence(scenario: SyntheticConductScenario, priorDates: string[]): ConductTriageInput {
  const relatedContexts = unique([scenario.matchId, ...(scenario.relatedMatchIds ?? [])]);
  const sourceTeams = unique(scenario.sourceTeamIds ?? []);
  const independentSourceCount = Math.min(
    scenario.reporterAgentIds.length,
    Math.max(scenario.independentSourceTeams, sourceTeams.length),
  );
  const forcedPriorDates = scenario.kind === "repeat_offender" && priorDates.length < 2
    ? [
      new Date(Date.parse(scenario.virtualDate) - 35 * DAY_MS).toISOString(),
      new Date(Date.parse(scenario.virtualDate) - 14 * DAY_MS).toISOString(),
      ...priorDates,
    ]
    : priorDates;
  return {
    category: scenarioCategory(scenario),
    contextIds: scenario.kind === "repeat_offender" && relatedContexts.length < 2
      ? [...relatedContexts, `${scenario.matchId}:previous`] : relatedContexts,
    correlatedReportCount: Math.max(0, scenario.reporterAgentIds.length - independentSourceCount),
    independentSourceCount,
    mutualRetaliation: scenario.kind === "mutual_conflict",
    priorCompatibleSignalDates: forcedPriorDates,
    rawReportCount: scenario.reporterAgentIds.length,
    reportedAt: scenario.virtualDate,
    sourceTeamIds: sourceTeams,
  };
}

function countQueues(rows: Array<{ queue: ConductTriageQueue }>) {
  const counts: Record<ConductTriageQueue, number> = { priority_review: 0, record_only: 0, review: 0, urgent_review: 0, watch: 0 };
  for (const row of rows) counts[row.queue] += 1;
  return counts;
}

function round(value: number) {
  return Number(value.toFixed(4));
}

function simulateCapacity(rows: Array<{ queue: ConductTriageQueue; reportedAt: string }>, casesPerDay: number) {
  const arrivals = rows.filter(({ queue }) => HUMAN_QUEUES.has(queue))
    .sort((left, right) => left.reportedAt.localeCompare(right.reportedAt) || QUEUE_RANK[right.queue] - QUEUE_RANK[left.queue]);
  if (arrivals.length === 0) return { backlog: 0, casesPerDay, meanWaitDays: 0, urgentWaiting: 0 };
  const firstDay = Math.floor(Date.parse(arrivals[0]!.reportedAt) / DAY_MS);
  const lastDay = Math.floor(Date.parse(arrivals.at(-1)!.reportedAt) / DAY_MS);
  const pending: typeof arrivals = [];
  const waits: number[] = [];
  let cursor = 0;
  for (let day = firstDay; day <= lastDay; day += 1) {
    while (cursor < arrivals.length && Math.floor(Date.parse(arrivals[cursor]!.reportedAt) / DAY_MS) <= day) {
      pending.push(arrivals[cursor++]!);
    }
    pending.sort((left, right) => QUEUE_RANK[right.queue] - QUEUE_RANK[left.queue] || left.reportedAt.localeCompare(right.reportedAt));
    for (let handled = 0; handled < casesPerDay && pending.length > 0; handled += 1) {
      const item = pending.shift()!;
      waits.push(Math.max(0, day - Math.floor(Date.parse(item.reportedAt) / DAY_MS)));
    }
  }
  return {
    backlog: pending.length,
    casesPerDay,
    meanWaitDays: waits.length ? round(waits.reduce((sum, value) => sum + value, 0) / waits.length) : 0,
    urgentWaiting: pending.filter(({ queue }) => queue === "urgent_review").length,
  };
}

function hasWindow(dates: string[], minimum: number, days: number) {
  const ordered = [...dates].sort();
  return ordered.some((left, index) => ordered.slice(index).filter((right) => Date.parse(right) - Date.parse(left) <= days * DAY_MS).length >= minimum);
}

function noShowThresholdComparison(world: SyntheticWorld) {
  const candidates = world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "no_show");
  const confirmed = candidates.map(replayNoShowCandidate).filter(({ finalOutcome }) => finalOutcome === "unexcused_no_show");
  const candidateById = new Map(candidates.map((row) => [row.id, row]));
  const byAgent = new Map<string, string[]>();
  for (const replay of confirmed) {
    const source = candidateById.get(replay.candidateId);
    if (!source) continue;
    byAgent.set(source.agentId, [...(byAgent.get(source.agentId) ?? []), source.changedAt]);
  }
  const variants = [
    { count: 2, days: 60 },
    { count: 2, days: 90 },
    { count: 3, days: 120 },
    { count: 3, days: 180 },
    { count: 4, days: 180 },
  ].map((variant) => ({
    ...variant,
    candidates: [...byAgent.values()].filter((dates) => hasWindow(dates, variant.count, variant.days)).length,
  }));
  const registeredPlayers = world.state.agents.filter(({ kind }) => kind === "registered").length;
  return {
    confirmedNoShowEvents: confirmed.length,
    distributionAssessment: candidates.length / Math.max(1, registeredPlayers) > 0.3
      ? "stress_distribution_not_product_calibration" as const : "plausible_but_unverified" as const,
    generatedCandidateEvents: candidates.length,
    generatedEventsPerRegisteredPlayer: round(candidates.length / Math.max(1, registeredPlayers)),
    policyChanged: false,
    variants,
  };
}

export function buildConductTriageV11Audit(world: SyntheticWorld) {
  const reportScenarios = world.state.conductScenarios
    .filter(({ productCapability }) => productCapability === "not_implemented")
    .sort((left, right) => left.virtualDate.localeCompare(right.virtualDate) || left.id.localeCompare(right.id));
  const history = new Map<string, string[]>();
  const rows = reportScenarios.map((scenario) => {
    const category = scenarioCategory(scenario);
    const historyKey = `${scenario.targetAgentId}:${category}`;
    const priorDates = history.get(historyKey) ?? [];
    const triage = evaluateConductTriageV11(scenarioEvidence(scenario, priorDates));
    history.set(historyKey, [...priorDates, scenario.virtualDate]);
    return {
      groundTruthSerious: seriousGroundTruth(scenario),
      kind: scenario.kind,
      reportedAt: scenario.virtualDate,
      scenarioId: scenario.id,
      ...triage,
    };
  });
  const serious = rows.filter(({ groundTruthSerious }) => groundTruthSerious);
  const human = rows.filter(({ humanReviewRequired }) => humanReviewRequired);
  const truePositive = human.filter(({ groundTruthSerious }) => groundTruthSerious).length;
  const falsePositive = human.length - truePositive;
  const registeredPlayers = world.state.agents.filter(({ kind }) => kind === "registered").length;
  const humanRate = human.length / Math.max(1, rows.length);
  const project = (players: number) => Math.round(human.length * Math.pow(players / Math.max(1, registeredPlayers), 0.94));

  return {
    backlog: {
      casesPerDay5: simulateCapacity(rows, 5),
      casesPerDay10: simulateCapacity(rows, 10),
    },
    beforeHumanReviewCases: rows.length,
    cases: rows.length,
    falseCampaignEscalation: rows.filter(({ humanReviewRequired, kind }) => humanReviewRequired && kind === "coordinated_false_report").length,
    falseEscalationRate: round(falsePositive / Math.max(1, rows.filter(({ groundTruthSerious }) => !groundTruthSerious).length)),
    humanReviewCases: human.length,
    humanReviewRate: round(humanRate),
    isolation: {
      achievementsChanged: false,
      ratingV2Changed: false,
      rewardsChanged: false,
      seasonScoreChanged: false,
      topsChanged: false,
    },
    missedSeriousCases: serious.length - truePositive,
    noShowThresholds: noShowThresholdComparison(world),
    policyVersion: CONDUCT_TRIAGE_POLICY_V1_1.policyVersion,
    projectedHumanCases: {
      players1000: project(1_000),
      players5000: project(5_000),
      players10000: project(10_000),
      players50000: project(50_000),
      projectionIsOrientativeAndNonLinear: true,
    },
    queues: countQueues(rows),
    seriousCasePrecision: round(truePositive / Math.max(1, human.length)),
    seriousCaseRecall: round(truePositive / Math.max(1, serious.length)),
    singleCleanReportEscalation: rows.filter(({ humanReviewRequired, kind }) => humanReviewRequired && kind === "single_clean_history_report").length,
    triageRows: rows,
  };
}
