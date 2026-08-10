import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { buildConductV1Replay, conductCanonicalStateHash } from "../simulation/synthetic-world/src/conduct-v1";
import type { SyntheticWorld } from "../simulation/synthetic-world/src/types";

function fixtureWorld(): SyntheticWorld {
  const attendanceRecords = Array.from({ length: 37 }, (_, index) => ({
    agentId: `agent-${Math.floor(index / 4)}`,
    canonicalNoShowDistinguishable: false,
    changedAt: new Date(Date.UTC(2026, 8, 1 + index * 5)).toISOString(),
    finalOutcome: "no_show" as const,
    id: `candidate-${index}`,
    initialStatus: "voy" as const,
    matchId: `match-${index}`,
    teamId: `team-${index % 5}`,
  }));
  attendanceRecords.push(...Array.from({ length: 424 }, (_, index) => ({
    agentId: `cancel-${index}`,
    canonicalNoShowDistinguishable: true,
    changedAt: new Date(Date.UTC(2026, 8, 1 + (index % 200))).toISOString(),
    finalOutcome: index % 2 === 0 ? "cancelled_early" as const : "cancelled_late" as const,
    id: `cancel-${index}`,
    initialStatus: "voy" as const,
    matchId: `cancel-match-${index}`,
    teamId: `team-${index % 5}`,
  })));
  const conductScenarios = Array.from({ length: 68 }, (_, index) => ({
    id: `report-${index}`,
    independentSourceTeams: 1,
    kind: "single_clean_history_report" as const,
    matchId: `report-match-${index}`,
    productCapability: "not_implemented" as const,
    reporterAgentIds: [`reporter-${index}`],
    status: "pending" as const,
    targetAgentId: `target-${index}`,
    virtualDate: "2027-01-01T00:00:00.000Z",
  }));
  conductScenarios.push({
    id: "same-team-burst", independentSourceTeams: 1, kind: "same_team_report_burst", matchId: "burst-match",
    productCapability: "not_implemented", reporterAgentIds: ["a", "b", "c", "d", "e"], status: "pending",
    targetAgentId: "target-burst", virtualDate: "2027-01-02T00:00:00.000Z",
  });
  conductScenarios.push({
    id: "independent", independentSourceTeams: 2, kind: "independent_team_reports", matchId: "independent-match",
    productCapability: "not_implemented", reporterAgentIds: ["a", "z"], status: "pending",
    targetAgentId: "target-independent", virtualDate: "2027-02-02T00:00:00.000Z",
  });
  return {
    config: {} as SyntheticWorld["config"], createdAt: "2026-09-01T00:00:00.000Z", currentDate: "2027-06-30T00:00:00.000Z",
    id: "fixture", mode: "ephemeral", name: "Conduct fixture", revision: 313, seasonId: "2026-27", seed: 1,
    sourceCommit: "fixture", startDate: "2026-09-01T00:00:00.000Z", status: "completed",
    state: {
      achievements: [], agents: Array.from({ length: 640 }, (_, index) => ({ id: `agent-${index}`, kind: "registered" })) as SyntheticWorld["state"]["agents"],
      attendanceRecords, boxes: [], challenges: [], conductScenarios, coverage: [], eventSequence: 69_458, events: [],
      incidents: [], matches: [], notifications: [], ratingOpinions: [], rankings: [], teams: [], venues: [],
    },
  };
}

test("the 37 candidate no-shows traverse every post-match outcome without mutating normal cancellations", () => {
  const world = fixtureWorld();
  const before = structuredClone(world);
  const result = buildConductV1Replay(world);
  assert.equal(result.attendance.candidateNoShows, 37);
  assert.equal(result.attendance.normalCancellations, 424);
  assert.equal(result.attendance.falsePositiveNoShowsFromNormalCancellations, 0);
  assert.deepEqual(new Set(Object.keys(result.attendance.byFinalOutcome)), new Set(["played", "excused_absence", "late_cancellation", "unexcused_no_show"]));
  assert.ok(result.attendance.disputed > 0);
  assert.ok(result.attendance.corrections > 0);
  assert.deepEqual(world, before);
});

test("same-team bursts collapse while independent teams remain independent and never auto-restrict", () => {
  const result = buildConductV1Replay(fixtureWorld());
  assert.equal(result.conduct.cases, 70);
  assert.equal(result.conduct.rawReports, 75);
  assert.equal(result.conduct.independentSources, 71);
  assert.equal(result.conduct.correlatedReports, 4);
  assert.equal(result.conduct.restrictionsApplied, 0);
  assert.equal(result.conduct.warningsIssued, 0);
  assert.equal(result.featureFlags.social_restrictions_enabled, false);
});

test("conduct replay explicitly preserves every sporting and reward system", () => {
  const result = buildConductV1Replay(fixtureWorld());
  assert.deepEqual(result.isolation, {
    achievementsChanged: false,
    ratingV2Changed: false,
    seasonScoreChanged: false,
    topsChanged: false,
  });
  assert.equal(result.moderationLoad.projectionIsOrientative, true);
});

test("the canonical source hash ignores diagnostic incident projections", () => {
  const world = fixtureWorld();
  const before = conductCanonicalStateHash(world);
  world.state.incidents.push({ id: "diagnostic-only" } as SyntheticWorld["state"]["incidents"][number]);
  assert.equal(conductCanonicalStateHash(world), before);
});

test("the product surface keeps reports contextual, private and disabled by default", () => {
  const migration = readFileSync("supabase/migrations/20260809162859_conduct_reports_no_show_v1.sql", "utf8");
  const home = readFileSync("app/page.tsx", "utf8");
  const reportForm = readFileSync("app/conduct-report-form.tsx", "utf8");
  const playerCenter = readFileSync("app/conduct-player-center.tsx", "utf8");
  const adminCenter = readFileSync("app/admin/conduct/conduct-admin-client.tsx", "utf8");

  assert.match(migration, /attendance_closure_enabled boolean not null default false/);
  assert.match(migration, /conduct_reports_enabled boolean not null default false/);
  assert.match(migration, /social_restrictions_enabled boolean not null default false/);
  assert.match(migration, /revoke all on schema private from public, anon, authenticated/);
  assert.match(migration, /pachangas_security_role/);
  assert.match(migration, /pachanga_guest_access_social_gate_v1/);
  assert.match(migration, /SOCIAL_ACTION_RESTRICTED: receive public challenges/);
  assert.doesNotMatch(migration, /update\s+public\.pachanga_player_profiles\s+set\s+(rating|facets)/i);
  assert.doesNotMatch(migration, /insert\s+into\s+public\.pachanga_(individual_rating|player_rating|achievement|reward)/i);
  assert.match(home, /matchFinalized[\s\S]*Reportar conducta/);
  assert.match(reportForm, /Contexto adicional \(opcional\)/);
  assert.match(playerCenter, /pachanga_conduct_subject_state/);
  assert.match(adminCenter, /pachanga_attendance_group_state/);
  assert.doesNotMatch(`${reportForm}\n${playerCenter}\n${adminCenter}`, /service_role/i);
});
