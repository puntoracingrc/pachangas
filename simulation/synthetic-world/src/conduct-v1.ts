import { createHash } from "node:crypto";
import type {
  SyntheticAttendanceRecord,
  SyntheticConductScenario,
  SyntheticWorld,
} from "./types";

export function conductCanonicalStateHash(world: SyntheticWorld) {
  const { incidents: diagnosticIncidents, ...canonicalState } = world.state;
  void diagnosticIncidents;
  return createHash("sha256").update(JSON.stringify(canonicalState)).digest("hex");
}

export type ConductV1AttendanceOutcome =
  | "excused_absence"
  | "late_cancellation"
  | "played"
  | "unexcused_no_show";

export type ConductV1AttendanceReplay = {
  candidateId: string;
  disputed: boolean;
  finalOutcome: ConductV1AttendanceOutcome;
  initialOutcome: "unexcused_no_show";
  resolution: "agreed" | "confirmed_uncontested" | "corrected" | "maintained_after_dispute";
};

export type ConductV1Replay = ReturnType<typeof buildConductV1Replay>;

const REPORT_SCENARIOS = new Set<SyntheticConductScenario["kind"]>([
  "conflict_prone_incident",
  "coordinated_false_report",
  "independent_team_reports",
  "mutual_conflict",
  "occasional_unsporting",
  "repeat_offender",
  "same_team_report_burst",
  "single_clean_history_report",
]);

function countBy<T extends string>(values: T[]) {
  const counts = {} as Record<T, number>;
  for (const value of values) counts[value] = (counts[value] ?? 0) + 1;
  return counts;
}

function withinDays(left: string, right: string, days: number) {
  return Date.parse(right) - Date.parse(left) <= days * 24 * 60 * 60 * 1_000;
}

function hasWindow(records: SyntheticAttendanceRecord[], minimum: number, days: number) {
  const ordered = [...records].sort((left, right) => left.changedAt.localeCompare(right.changedAt));
  return ordered.some((record, index) => {
    const window = ordered.slice(index).filter((candidate) => withinDays(record.changedAt, candidate.changedAt, days));
    return window.length >= minimum;
  });
}

function replayNoShowCandidate(record: SyntheticAttendanceRecord, index: number): ConductV1AttendanceReplay {
  if (index % 17 === 0) {
    return { candidateId: record.id, disputed: true, finalOutcome: "played", initialOutcome: "unexcused_no_show", resolution: "corrected" };
  }
  if (index % 13 === 0) {
    return { candidateId: record.id, disputed: true, finalOutcome: "late_cancellation", initialOutcome: "unexcused_no_show", resolution: "corrected" };
  }
  if (index % 11 === 0) {
    return { candidateId: record.id, disputed: true, finalOutcome: "excused_absence", initialOutcome: "unexcused_no_show", resolution: "corrected" };
  }
  if (index % 7 === 0) {
    return { candidateId: record.id, disputed: true, finalOutcome: "unexcused_no_show", initialOutcome: "unexcused_no_show", resolution: "maintained_after_dispute" };
  }
  return {
    candidateId: record.id,
    disputed: false,
    finalOutcome: "unexcused_no_show",
    initialOutcome: "unexcused_no_show",
    resolution: index % 3 === 0 ? "agreed" : "confirmed_uncontested",
  };
}

function reportScenarioMetrics(scenario: SyntheticConductScenario) {
  const rawReports = scenario.reporterAgentIds.length;
  const independentSources = Math.min(rawReports, Math.max(0, scenario.independentSourceTeams));
  return {
    correlatedReports: Math.max(0, rawReports - independentSources),
    dismissalRecommended: scenario.kind === "coordinated_false_report",
    humanReviewRequired: rawReports > 0,
    independentSources,
    priority: scenario.kind === "independent_team_reports" || scenario.kind === "repeat_offender" ? "high" as const : "normal" as const,
    rawReports,
    retaliationSignal: scenario.kind === "mutual_conflict",
    restrictionRecommended: scenario.kind === "independent_team_reports" || scenario.kind === "repeat_offender",
  };
}

export function buildConductV1Replay(world: SyntheticWorld) {
  const noShowCandidates = world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "no_show");
  const attendanceReplay = noShowCandidates.map(replayNoShowCandidate);
  const replayById = new Map(attendanceReplay.map((row) => [row.candidateId, row]));
  const finalNoShows = noShowCandidates.filter((record) => replayById.get(record.id)?.finalOutcome === "unexcused_no_show");
  const sourceNoShowsByAgent = new Map<string, SyntheticAttendanceRecord[]>();
  const finalNoShowsByAgent = new Map<string, SyntheticAttendanceRecord[]>();
  for (const record of noShowCandidates) {
    sourceNoShowsByAgent.set(record.agentId, [...(sourceNoShowsByAgent.get(record.agentId) ?? []), record]);
  }
  for (const record of finalNoShows) {
    finalNoShowsByAgent.set(record.agentId, [...(finalNoShowsByAgent.get(record.agentId) ?? []), record]);
  }

  const normalCancellations = world.state.attendanceRecords.filter(({ finalOutcome }) => (
    finalOutcome === "cancelled_early" || finalOutcome === "cancelled_late"
  ));
  const reportScenarios = world.state.conductScenarios.filter(({ kind, productCapability }) => (
    productCapability === "not_implemented" && REPORT_SCENARIOS.has(kind)
  ));
  const scenarioMetrics = reportScenarios.map(reportScenarioMetrics);
  const registeredPlayers = world.state.agents.filter(({ kind }) => kind === "registered").length;
  const humanCases = scenarioMetrics.filter(({ humanReviewRequired }) => humanReviewRequired).length;
  const perPlayerLoad = registeredPlayers > 0 ? humanCases / registeredPlayers : 0;

  return {
    attendance: {
      byFinalOutcome: countBy(attendanceReplay.map(({ finalOutcome }) => finalOutcome)),
      candidateNoShows: noShowCandidates.length,
      corrections: attendanceReplay.filter(({ resolution }) => resolution === "corrected").length,
      disputed: attendanceReplay.filter(({ disputed }) => disputed).length,
      falsePositiveNoShowsFromNormalCancellations: 0,
      finalConfirmedNoShows: finalNoShows.length,
      normalCancellations: normalCancellations.length,
      reminderCandidates90Days: [...finalNoShowsByAgent.values()].filter((records) => hasWindow(records, 2, 90)).length,
      reviewCandidates180Days: [...finalNoShowsByAgent.values()].filter((records) => hasWindow(records, 3, 180)).length,
      sourceRepeatCandidates: [...sourceNoShowsByAgent.values()].filter((records) => records.length >= 2).length,
    },
    conduct: {
      appeals: 0,
      byKind: countBy(reportScenarios.map(({ kind }) => kind)),
      cases: reportScenarios.length,
      correlatedReports: scenarioMetrics.reduce((sum, row) => sum + row.correlatedReports, 0),
      corrections: 0,
      dismissalRecommendations: scenarioMetrics.filter(({ dismissalRecommended }) => dismissalRecommended).length,
      humanCases,
      independentSources: scenarioMetrics.reduce((sum, row) => sum + row.independentSources, 0),
      rawReports: scenarioMetrics.reduce((sum, row) => sum + row.rawReports, 0),
      retaliationSignals: scenarioMetrics.filter(({ retaliationSignal }) => retaliationSignal).length,
      restrictionRecommendations: scenarioMetrics.filter(({ restrictionRecommended }) => restrictionRecommended).length,
      restrictionsApplied: 0,
      sameTeamCampaigns: reportScenarios.filter(({ kind }) => kind === "same_team_report_burst" || kind === "coordinated_false_report").length,
      warningsIssued: 0,
    },
    featureFlags: {
      attendance_closure_enabled: true,
      conduct_reports_enabled: true,
      social_restrictions_enabled: false,
    },
    isolation: {
      achievementsChanged: false,
      ratingV2Changed: false,
      seasonScoreChanged: false,
      topsChanged: false,
    },
    moderationLoad: {
      observedPlayers: registeredPlayers,
      observedSeasonCases: humanCases,
      projectedCases: {
        players1000: Math.round(perPlayerLoad * 1_000),
        players5000: Math.round(perPlayerLoad * 5_000),
        players10000: Math.round(perPlayerLoad * 10_000),
      },
      projectionIsOrientative: true,
    },
  };
}
