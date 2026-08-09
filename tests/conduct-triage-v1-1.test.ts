import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { buildConductTriageV11Audit, evaluateConductTriageV11 } from "../simulation/synthetic-world/src/conduct-triage-v1-1";
import type { SyntheticWorld } from "../simulation/synthetic-world/src/types";

function evidence(overrides: Partial<Parameters<typeof evaluateConductTriageV11>[0]> = {}) {
  return {
    category: "other",
    contextIds: ["match-1"],
    correlatedReportCount: 0,
    independentSourceCount: 1,
    mutualRetaliation: false,
    priorCompatibleSignalDates: [],
    rawReportCount: 1,
    reportedAt: "2027-01-10T12:00:00.000Z",
    sourceTeamIds: ["team-1"],
    ...overrides,
  };
}

test("isolated non-serious reports are recorded without immediate human review", () => {
  const result = evaluateConductTriageV11(evidence());
  assert.equal(result.queue, "record_only");
  assert.equal(result.humanReviewRequired, false);
  assert.deepEqual(result.reasonCodes, ["ISOLATED_NON_SERIOUS_SIGNAL"]);
  assert.equal(result.sanctionApplied, false);
});

test("raw same-team clicks remain correlated instead of multiplying priority", () => {
  const result = evaluateConductTriageV11(evidence({ correlatedReportCount: 9, rawReportCount: 10 }));
  assert.equal(result.queue, "record_only");
  assert.equal(result.humanReviewRequired, false);
  assert.ok(result.reasonCodes.includes("CORRELATED_SOURCE_CLUSTER"));
});

test("one threat reaches urgent human review without applying a sanction", () => {
  const result = evaluateConductTriageV11(evidence({ category: "threats_or_violence" }));
  assert.equal(result.queue, "urgent_review");
  assert.equal(result.humanReviewRequired, true);
  assert.equal(result.sanctionApplied, false);
});

test("three independent teams reach priority review with explainable reasons", () => {
  const result = evaluateConductTriageV11(evidence({
    contextIds: ["match-1", "match-2", "match-3"],
    independentSourceCount: 3,
    rawReportCount: 3,
    sourceTeamIds: ["team-1", "team-2", "team-3"],
  }));
  assert.equal(result.queue, "priority_review");
  assert.ok(result.reasonCodes.includes("INDEPENDENT_SOURCES_3_PLUS"));
  assert.ok(result.reasonCodes.includes("DISTINCT_CONTEXTS_2_PLUS"));
});

test("old isolated evidence is audit history but no longer active risk", () => {
  const result = evaluateConductTriageV11(evidence({
    priorCompatibleSignalDates: ["2023-01-01T00:00:00.000Z"],
  }));
  assert.equal(result.queue, "record_only");
  assert.ok(result.reasonCodes.includes("ACTIVE_WINDOW_EXPIRED"));
});

test("synthetic audit keeps sporting systems isolated and never auto-sanctions", () => {
  const world = {
    state: {
      agents: Array.from({ length: 640 }, (_, index) => ({ id: `p-${index}`, kind: "registered" })),
      attendanceRecords: [],
      conductScenarios: [
        { id: "clean", independentSourceTeams: 1, kind: "single_clean_history_report", matchId: "m1", productCapability: "not_implemented", reporterAgentIds: ["a"], sourceTeamIds: ["t1"], status: "pending", targetAgentId: "clean-target", virtualDate: "2027-01-01T00:00:00.000Z" },
        { id: "campaign", independentSourceTeams: 1, kind: "coordinated_false_report", matchId: "m2", productCapability: "not_implemented", reporterAgentIds: ["a", "b", "c", "d", "e"], sourceTeamIds: ["t1"], status: "pending", targetAgentId: "clean-target-2", virtualDate: "2027-01-02T00:00:00.000Z" },
        { id: "repeat", independentSourceTeams: 1, kind: "repeat_offender", matchId: "m3", productCapability: "not_implemented", reporterAgentIds: ["z"], sourceTeamIds: ["t2"], status: "pending", targetAgentId: "repeat-target", virtualDate: "2027-02-01T00:00:00.000Z" },
      ],
    },
  } as unknown as SyntheticWorld;
  const result = buildConductTriageV11Audit(world);
  assert.equal(result.beforeHumanReviewCases, 3);
  assert.equal(result.humanReviewCases, 1);
  assert.equal(result.falseCampaignEscalation, 0);
  assert.equal(result.singleCleanReportEscalation, 0);
  assert.equal(result.seriousCaseRecall, 1);
  assert.deepEqual(result.isolation, {
    achievementsChanged: false,
    ratingV2Changed: false,
    rewardsChanged: false,
    seasonScoreChanged: false,
    topsChanged: false,
  });
});

test("the server contract is disabled by default, explainable and protected by the PWA bridge", () => {
  const migration = readFileSync("supabase/migrations/20260809203000_conduct_triage_v1_1.sql", "utf8");
  const classifier = readFileSync("app/pwa-write-classifier.ts", "utf8");
  const admin = readFileSync("app/admin/conduct/conduct-admin-client.tsx", "utf8");

  assert.match(migration, /conduct_triage_enabled boolean not null default false/);
  assert.match(migration, /conduct_triage_shadow_mode boolean not null default true/);
  assert.match(migration, /triage_reason_codes text\[\]/);
  assert.match(migration, /ACTIVE_WINDOW_EXPIRED/);
  assert.match(migration, /Threat or violence incidents must remain distinct/);
  assert.match(migration, /automaticSanctionApplied', false/);
  assert.match(migration, /affectsSportRating', false/);
  assert.doesNotMatch(migration, /add column[^;]*(conduct_score|risk_score)|jsonb_build_object\([^;]*'(conductScore|riskScore)'/i);
  assert.doesNotMatch(migration, /update\s+public\.pachanga_player_profiles\s+set\s+(rating|facets)/i);
  assert.match(classifier, /merge_pachanga_conduct_cases_v1_1/);
  assert.match(classifier, /split_pachanga_conduct_case_v1_1/);
  assert.match(admin, /Urgente/);
  assert.match(admin, /Solo registro/);
  assert.doesNotMatch(admin, /service_role/i);
});
