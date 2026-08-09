import assert from "node:assert/strict";
import test from "node:test";
import { CANONICAL_CONTRACTS } from "../simulation/synthetic-world/src/canonical-contracts";
import {
  advanceSyntheticWorld,
  advanceSyntheticWorldByDays,
  advanceSyntheticWorldByHours,
  reconcileSyntheticConductCoverage,
  reconcileSyntheticRankingCoverage,
  syntheticWorldSummary,
} from "../simulation/synthetic-world/src/engine";
import { assertSyntheticWorldEnvironment, syntheticWorldAdminEnabled, SyntheticWorldEnvironmentError } from "../simulation/synthetic-world/src/environment";
import { syntheticErrorMessage } from "../simulation/synthetic-world/src/errors";
import { createSyntheticWorld } from "../simulation/synthetic-world/src/generator";
import { dailyInvariantChecks, weeklyInvariantChecks } from "../simulation/synthetic-world/src/invariants";
import { KNOWN_SYNTHETIC_INCIDENTS, knownIncidentsForWorld } from "../simulation/synthetic-world/src/known-incidents";
import { normalizeSyntheticWorldState } from "../simulation/synthetic-world/src/normalization";
import { seasonInputs } from "../simulation/synthetic-world/src/ranking";

const safeEnvironment = {
  NEXT_PUBLIC_APP_URL: "http://127.0.0.1:3090",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:55321",
  PACHANGAS_SYNTHETIC_WORLD: "1",
  SUPABASE_SERVICE_ROLE_KEY: "local-test-key",
} as NodeJS.ProcessEnv;

test("synthetic environment is loopback-only and rejects hosted or external integrations", () => {
  assert.equal(assertSyntheticWorldEnvironment(safeEnvironment).isolated, true);
  assert.throws(() => assertSyntheticWorldEnvironment({ ...safeEnvironment, VERCEL_ENV: "preview" }), SyntheticWorldEnvironmentError);
  assert.throws(() => assertSyntheticWorldEnvironment({ ...safeEnvironment, NEXT_PUBLIC_SUPABASE_URL: "https://example.supabase.co" }), SyntheticWorldEnvironmentError);
  assert.throws(() => assertSyntheticWorldEnvironment({ ...safeEnvironment, RESEND_API_KEY: "forbidden" }), SyntheticWorldEnvironmentError);
  assert.equal(syntheticWorldAdminEnabled(safeEnvironment), false);
  assert.equal(syntheticWorldAdminEnabled({ ...safeEnvironment, PACHANGAS_SYNTHETIC_ADMIN: "1" }), true);
  assert.equal(syntheticWorldAdminEnabled({ ...safeEnvironment, PACHANGAS_SYNTHETIC_ADMIN: "1", NODE_ENV: "production" }), false);
});

test("the base world meets population, geography, personality and integrity distributions", () => {
  const world = createSyntheticWorld({ seed: 20260809 });
  const registered = world.state.agents.filter(({ kind }) => kind === "registered");
  const attacks = registered.filter(({ attackProfile }) => attackProfile !== "none");
  const geography = new Map<string, number>();
  world.state.agents.forEach(({ provinceCode }) => geography.set(provinceCode, (geography.get(provinceCode) ?? 0) + 1));
  assert.equal(registered.length, 640);
  assert.equal(world.state.agents.filter(({ kind }) => kind === "guest").length, 30);
  assert.equal(registered.filter(({ teamIds }) => teamIds.length === 0).length, 40);
  assert.equal(world.state.teams.length, 50);
  assert.ok(attacks.length / registered.length >= 0.05 && attacks.length / registered.length <= 0.1);
  assert.ok(new Set(registered.map(({ persona }) => persona)).size >= 12);
  assert.ok(Math.max(...geography.values()) > Math.min(...geography.values()) * 4);
  assert.ok(world.state.agents.every(({ displayName }) => displayName.startsWith("SIM · ")));
  assert.equal(world.sourceCommit, "4c75d52e15449528fe206e4d542715ec96d42422");
  assert.equal(world.state.teams.filter(({ integrityClusterId }) => integrityClusterId === "synthetic-fake-team-ring").length, 10);
  assert.ok(world.state.teams.every(({ playerIds }) => new Set(playerIds).size === playerIds.length));
  assert.equal(new Set(registered.map(({ attendanceProfile }) => attendanceProfile)).size, 8);
  assert.equal(new Set(registered.map(({ conductProfile }) => conductProfile)).size, 6);
});

test("legacy worlds reconcile every behavior archetype once without replacing sporting history", () => {
  const legacy = createSyntheticWorld({ seed: 20260810 });
  legacy.state.agents.forEach((agent) => {
    agent.attendanceProfile = "normal";
    agent.conductProfile = "fair";
  });
  const matchesBefore = structuredClone(legacy.state.matches);
  const reconciled = reconcileSyntheticConductCoverage(legacy);
  const registered = reconciled.state.agents.filter(({ kind }) => kind === "registered");
  assert.equal(new Set(registered.map(({ attendanceProfile }) => attendanceProfile)).size, 8);
  assert.equal(new Set(registered.map(({ conductProfile }) => conductProfile)).size, 6);
  assert.deepEqual(reconciled.state.matches, matchesBefore);
  assert.equal(reconciled.revision, legacy.revision + 1);
  assert.equal(reconcileSyntheticConductCoverage(reconciled).revision, reconciled.revision);
});

test("virtual advancement is deterministic and cannot rewind", () => {
  const left = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 31 }), 45);
  const right = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 31 }), 45);
  assert.deepEqual(syntheticWorldSummary(left), syntheticWorldSummary(right));
  assert.deepEqual(left.state.matches, right.state.matches);
  assert.throws(() => advanceSyntheticWorld(left, { targetDate: "2026-09-01T00:00:00.000Z" }), /cannot run backwards/);
});

test("the virtual clock advances one hour without replaying a daily cycle", () => {
  const base = createSyntheticWorld({ seed: 32 });
  const first = advanceSyntheticWorldByHours(base, 1);
  const second = advanceSyntheticWorldByHours(first, 1);
  assert.equal(first.currentDate, "2026-09-01T09:00:00.000Z");
  assert.equal(second.currentDate, "2026-09-01T10:00:00.000Z");
  assert.equal(first.revision, 1);
  assert.equal(second.revision, 2);
  assert.equal(first.state.events.filter(({ eventType }) => eventType === "virtual_clock_advanced").length, 1);
  assert.equal(second.state.events.filter(({ eventType }) => eventType === "virtual_clock_advanced").length, 2);
  const dayBoundary = advanceSyntheticWorldByHours({ ...base, currentDate: "2026-09-01T23:00:00.000Z" }, 1);
  assert.equal(dayBoundary.currentDate, "2026-09-02T00:00:00.000Z");
  assert.equal(dayBoundary.revision, 1);
  assert.throws(() => advanceSyntheticWorldByHours(base, 0), /positive integer/);
});

test("structured database errors retain diagnostics without secret fields", () => {
  const message = syntheticErrorMessage({ code: "57014", details: "statement timeout", secretKey: "must-not-leak" });
  assert.match(message, /57014/);
  assert.match(message, /statement timeout/);
  assert.doesNotMatch(message, /must-not-leak|secretKey/);
});

test("legacy duplicate attendance is normalized to the participant outcome", () => {
  const world = createSyntheticWorld({ seed: 33 });
  const team = world.state.teams[0]!;
  const match = {
    awayGoals: 0, awayTeamId: null, confidence: 1, evidenceExcluded: true, guestIds: [], homeGoals: 1,
    homeTeamId: team.id, id: "legacy-match", kind: "internal" as const, occurredAt: world.currentDate,
    participantIds: [team.playerIds[0]!], productMatchId: null, provinceCode: team.provinceCode,
    scorerGoals: {}, state: "confirmed" as const, venueId: world.state.venues[0]!.id,
  };
  world.state.matches.push(match);
  const common = { agentId: team.playerIds[0]!, canonicalNoShowDistinguishable: true, id: "duplicate", initialStatus: "voy" as const, matchId: match.id, teamId: team.id };
  world.state.attendanceRecords.push(
    { ...common, changedAt: world.currentDate, finalOutcome: "cancelled_late" },
    { ...common, changedAt: world.currentDate, finalOutcome: "played" },
  );
  team.playerIds.push(team.playerIds[0]!);
  const normalized = normalizeSyntheticWorldState(world.state);
  assert.equal(normalized.attendanceRecords.filter(({ id }) => id === "duplicate").length, 1);
  assert.equal(normalized.attendanceRecords.find(({ id }) => id === "duplicate")?.finalOutcome, "played");
  assert.equal(new Set(normalized.teams[0]!.playerIds).size, normalized.teams[0]!.playerIds.length);
});

test("five deterministic smoke seeds keep daily and weekly invariants green", () => {
  for (const seed of [11, 22, 33, 44, 55]) {
    const world = advanceSyntheticWorldByDays(createSyntheticWorld({ mode: "ephemeral", seed }), 35);
    assert.equal(dailyInvariantChecks(world).filter(({ pass }) => !pass).length, 0, `daily seed ${seed}`);
    assert.equal(weeklyInvariantChecks(world).filter(({ pass }) => !pass).length, 0, `weekly seed ${seed}`);
    assert.ok(world.state.matches.length > 80, `match volume seed ${seed}`);
  }
});

test("a full season is rich, closed, auditable and ranking-capable", () => {
  const legacy = advanceSyntheticWorld(createSyntheticWorld({ mode: "ephemeral", seed: 20260811 }), {
    rankingEligibilityCoverage: false,
    targetDate: "2027-06-30T00:00:00.000Z",
  });
  assert.equal(legacy.state.rankings.filter(({ certification }) => certification === "eligible").length, 0);
  const ratingsBefore = new Map(legacy.state.agents.map(({ facets, id, ratingV2 }) => [id, { facets: structuredClone(facets), ratingV2 }]));
  const world = reconcileSyntheticRankingCoverage(legacy);
  const summary = syntheticWorldSummary(world);
  assert.equal(world.status, "completed");
  assert.ok(summary.totalMatches >= 1_000);
  assert.ok(summary.challenges >= 1_000);
  assert.ok(summary.notifications >= 3_000);
  assert.ok(summary.boxes >= 1_000);
  assert.ok(summary.rankings >= 80);
  assert.equal(summary.scheduledMatches, 0);
  assert.equal(new Set(world.state.events.map(({ operationId }) => operationId)).size, world.state.events.length);
  assert.equal(dailyInvariantChecks(world).filter(({ pass }) => !pass).length, 0);
  assert.equal(weeklyInvariantChecks(world).filter(({ pass }) => !pass).length, 0);
  const requiredConductKinds = new Set([
    "conflict_prone_incident",
    "coordinated_false_report",
    "fair_play_control",
    "independent_team_reports",
    "mutual_conflict",
    "occasional_unsporting",
    "repeat_offender",
    "same_team_report_burst",
    "single_clean_history_report",
  ]);
  const fixtures = world.state.conductScenarios.filter(({ coverageFixture }) => coverageFixture);
  assert.deepEqual(new Set(fixtures.map(({ kind }) => kind)), requiredConductKinds);
  assert.ok(fixtures.every(({ reporterAgentIds, targetAgentId }) => !reporterAgentIds.includes(targetAgentId)));
  assert.equal(fixtures.find(({ kind }) => kind === "fair_play_control")?.reporterAgentIds.length, 0);
  assert.equal(fixtures.find(({ kind }) => kind === "fair_play_control")?.productCapability, "not_required");
  assert.ok((fixtures.find(({ kind }) => kind === "same_team_report_burst")?.reporterAgentIds.length ?? 0) >= 2);
  assert.equal(fixtures.find(({ kind }) => kind === "same_team_report_burst")?.independentSourceTeams, 1);
  assert.ok((fixtures.find(({ kind }) => kind === "independent_team_reports")?.independentSourceTeams ?? 0) >= 2);
  assert.ok(world.state.events.filter(({ flow }) => flow === "conduct.player_report").every(({ payload, status }) => (
    status === "pending" && payload.affectsRatingV2 === false && payload.automaticSanctionApplied === false
  )));
  assert.ok(world.state.rankings.some(({ certification }) => certification === "eligible"));
  assert.ok(world.state.rankings.some(({ certification }) => certification === "pending_integrity_review"));
  const rankingControl = world.state.events.find(({ flow }) => flow === "ranking.eligibility_control");
  assert.equal(rankingControl?.payload.formulasChanged, false);
  assert.equal(rankingControl?.payload.ratingV2Changed, false);
  assert.ok(world.state.agents.every((agent) => JSON.stringify({ facets: agent.facets, ratingV2: agent.ratingV2 }) === JSON.stringify(ratingsBefore.get(agent.id))));
});

test("scorers match results and internal matches never become Season Score evidence", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 71 }), 90);
  for (const match of world.state.matches.filter(({ homeGoals, awayGoals }) => homeGoals !== null && awayGoals !== null)) {
    assert.equal(Object.values(match.scorerGoals).reduce((sum, goals) => sum + goals, 0), match.homeGoals! + match.awayGoals!);
  }
  const evidenceIds = new Set(seasonInputs(world).flatMap(({ records }) => records.map(({ challengeId }) => challengeId)));
  assert.ok(world.state.matches.filter(({ kind }) => kind === "internal").every(({ id }) => !evidenceIds.has(id)));
});

test("seed 20261001 assigns guest scorers to the side they complete", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ mode: "ephemeral", seed: 20261001 }), 35);
  const match = world.state.matches.find(({ id }) => id === "d87eb3c5-b7b9-4c02-844c-5dd26776ca97");
  assert.ok(match);
  assert.equal(Object.values(match.scorerGoals).reduce((sum, goals) => sum + goals, 0), match.homeGoals! + match.awayGoals!);
  assert.equal(dailyInvariantChecks(world).find(({ name }) => name === "matches.scorers_equal_score")?.pass, true);
});

test("peer opinions keep one active pair and require three additional shared matches", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 81 }), 150);
  const active = world.state.ratingOpinions.filter(({ status }) => status === "active");
  const keys = active.map(({ evaluatorAgentId, targetAgentId }) => `${evaluatorAgentId}:${targetAgentId}`);
  assert.equal(new Set(keys).size, keys.length);
  for (const opinion of world.state.ratingOpinions.filter(({ status }) => status === "superseded")) {
    const replacement = world.state.ratingOpinions.find((candidate) => (
      candidate.status === "active" && candidate.evaluatorAgentId === opinion.evaluatorAgentId && candidate.targetAgentId === opinion.targetAgentId
    ));
    if (replacement) assert.ok(replacement.sharedMatchesAtCreation - opinion.sharedMatchesAtCreation >= 3);
  }
});

test("injected failures are visible as failed events and reproducible incidents", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 91 }), 2, { failureInjectionRate: 1 });
  assert.equal(world.state.events.filter(({ flow, status }) => flow === "failure.injection" && status === "failed").length, 2);
  assert.equal(world.state.incidents.filter(({ operation }) => operation === "failure.injection").length, 2);
});

test("canonical flow inventory keeps product and lab execution visibly distinct", () => {
  assert.equal(CANONICAL_CONTRACTS.find(({ flow }) => flow === "match.finalize")?.route, "finalize_pachanga_match_authoritative_v2");
  assert.equal(CANONICAL_CONTRACTS.find(({ flow }) => flow === "rating.peer")?.execution, "product_rpc");
  assert.equal(CANONICAL_CONTRACTS.find(({ flow }) => flow === "ranking.season_score_v3")?.classification, "implemented_lab");
  assert.equal(CANONICAL_CONTRACTS.find(({ flow }) => flow === "team.leave")?.classification, "not_implemented");
});

test("permanent incident resolutions change only after a verified regression", () => {
  const byId = new Map(KNOWN_SYNTHETIC_INCIDENTS.map((incident) => [incident.id, incident]));
  for (const id of ["SW-0002", "SW-0003", "SW-0009"]) {
    assert.equal(byId.get(id)?.fixed, false, id);
    assert.equal(byId.get(id)?.regressionVerified, false, id);
  }
  for (const id of ["SW-0004", "SW-0005", "SW-0006", "SW-0007", "SW-0008", "SW-0012", "SW-0013", "SW-0014"]) {
    assert.equal(byId.get(id)?.fixed, true, id);
    assert.equal(byId.get(id)?.regressionVerified, true, id);
  }
});

test("the permanent incident catalog accepts every incident-first classification", () => {
  const allowed = new Set([
    "ENVIRONMENT_ISSUE",
    "NEEDS_PRODUCT_DECISION",
    "PRODUCT_BUG",
    "SIMULATION_BUG",
    "TESTABILITY_GAP",
  ]);
  assert.ok(KNOWN_SYNTHETIC_INCIDENTS.every(({ category }) => allowed.has(category)));
  assert.equal(KNOWN_SYNTHETIC_INCIDENTS.find(({ id }) => id === "SW-0030")?.category, "PRODUCT_BUG");
  assert.equal(KNOWN_SYNTHETIC_INCIDENTS.find(({ id }) => id === "SW-0031")?.category, "SIMULATION_BUG");
  const mapped = knownIncidentsForWorld(20260809, "2026-09-01T00:00:00.000Z");
  assert.equal(mapped.find(({ operation }) => operation === "simulation.dashboard.mobile_content_clipping")?.status, "false_positive");
});

test("attendance outcomes separate normal cancellation, injury and possible no-show", () => {
  const base = createSyntheticWorld({ seed: 20260901 });
  const originalFacets = new Map(base.state.agents.map(({ facets, id }) => [id, structuredClone(facets)]));
  const world = advanceSyntheticWorldByDays(base, 120);
  const cancellations = world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "cancelled_early" || finalOutcome === "cancelled_late");
  const noShows = world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "no_show");
  const injuries = world.state.attendanceRecords.filter(({ finalOutcome }) => finalOutcome === "injured");
  assert.ok(cancellations.length > 0);
  assert.ok(noShows.length > 0);
  assert.ok(injuries.length > 0);
  assert.ok(cancellations.every(({ canonicalNoShowDistinguishable }) => canonicalNoShowDistinguishable));
  assert.ok(noShows.every(({ canonicalNoShowDistinguishable }) => !canonicalNoShowDistinguishable));
  assert.ok(world.state.events.filter(({ flow }) => flow === "attendance.no_show").every(({ status }) => status === "pending"));
  assert.ok(world.state.incidents.some(({ operation, status }) => operation === "attendance.no_show" && status === "needs_product_decision"));
  assert.ok(world.state.agents.every((agent) => JSON.stringify(agent.facets) === JSON.stringify(originalFacets.get(agent.id))));
});

test("notification preferences never hide mandatory warnings and dedupe event keys", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 20260902 }), 70);
  assert.ok(world.state.notifications.some(({ mandatoryInApp }) => mandatoryInApp));
  assert.ok(world.state.notifications.filter(({ mandatoryInApp }) => mandatoryInApp).every(({ visibleInApp }) => visibleInApp));
  assert.equal(new Set(world.state.notifications.map(({ id }) => id)).size, world.state.notifications.length);
  assert.ok(world.state.events.some(({ flow }) => flow === "attendance.joined_notification"));
  assert.ok(world.state.events.some(({ flow }) => flow === "attendance.cancelled_notification"));
  assert.ok(world.state.events.some(({ flow }) => flow === "attendance.injury_notification"));
});

test("general conduct scenarios are counted without inventing reports or sanctions", () => {
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ seed: 20260903 }), 140);
  const missing = world.state.conductScenarios.filter(({ productCapability }) => productCapability === "not_implemented");
  const guestReviews = world.state.conductScenarios.filter(({ productCapability }) => productCapability === "implemented_guest_withdrawal_only");
  assert.ok(missing.length > 0);
  assert.ok(guestReviews.length > 0);
  assert.ok(world.state.events.filter(({ flow }) => flow === "conduct.player_report").every(({ status, payload }) => (
    status === "pending" && payload.automaticSanctionApplied === false && payload.affectsRatingV2 === false
  )));
  assert.ok(world.state.events.filter(({ flow }) => flow === "conduct.guest_withdrawal.review").every(({ payload }) => payload.affectsRatingV2 === false));
});

test("repeat no-show summary requires at least two records for the same agent", () => {
  const world = createSyntheticWorld({ seed: 20260904 });
  const [once, repeated] = world.state.agents;
  assert.ok(once && repeated);
  world.state.attendanceRecords.push(
    { agentId: once.id, canonicalNoShowDistinguishable: false, changedAt: world.currentDate, finalOutcome: "no_show", id: "one", initialStatus: "voy", matchId: "m1", teamId: "t1" },
    { agentId: repeated.id, canonicalNoShowDistinguishable: false, changedAt: world.currentDate, finalOutcome: "no_show", id: "two-a", initialStatus: "voy", matchId: "m2", teamId: "t2" },
    { agentId: repeated.id, canonicalNoShowDistinguishable: false, changedAt: world.currentDate, finalOutcome: "no_show", id: "two-b", initialStatus: "voy", matchId: "m3", teamId: "t2" },
  );
  assert.equal(syntheticWorldSummary(world).possibleNoShows, 3);
  assert.equal(syntheticWorldSummary(world).possibleRepeatNoShowAgents, 1);
});
