import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import configData from "../simulation/season-ranking-lab/season_score_config.json";
import {
  candidatesFromDataset,
  createNetworkEcosystem,
} from "../simulation/season-ranking-lab/src/network-diversity-v31";
import { networkDatasetReadinessSignals } from "../simulation/season-ranking-lab/src/territory-readiness-simulation";
import {
  PROVINCIAL_PILOT_FLAGS,
  PROVINCIAL_FEATURE_FLAG_KEYS,
  PROVINCIAL_SEASON_CLOSE_PHASES,
  closeProvincialSeason,
  createTerritoryReadinessSnapshot,
  isTerritoryReadinessState,
  observeTerritoryReadiness,
  readinessPublicSurface,
  resolveProvincialFeatureFlags,
  territoryReadinessTelemetry,
  type TerritoryReadinessSignals,
  type TerritoryReadinessSnapshot,
} from "../simulation/season-ranking-lab/src/territory-award-readiness";
import { v3Baseline } from "../simulation/season-ranking-lab/src/v3-validation";
import type { SeasonScoreConfig } from "../simulation/season-ranking-lab/src/types";
import { syntheticWorldTerritorySignals } from "../simulation/synthetic-world/src/territory-readiness";
import type { SyntheticWorld } from "../simulation/synthetic-world/src/types";
import generatedReadiness from "../simulation/synthetic-world/generated/territory-award-readiness-v1-summary.json";

const baseSignals: TerritoryReadinessSignals = {
  activePlayers: 120,
  activeTeams: 20,
  awardCandidatePlayers: 12,
  independentOpponentEdges: 40,
  independentTeamCoverage: 1,
  logicalOpponentEdges: 44,
  medianChallenges: 28,
  medianCompetitiveConfidence: 0.82,
  medianLogicalOpponents: 12,
  observedHistoryWeeks: 24,
  rankingEligiblePlayers: 24,
  validChallenges: 320,
};

function snapshot(signals: TerritoryReadinessSignals, history: TerritoryReadinessSnapshot[] = [], index = history.length) {
  return createTerritoryReadinessSnapshot({
    calculatedAt: new Date(Date.UTC(2027, index, 1)).toISOString(),
    history,
    season: "2026-27",
    signals,
    territory: "08",
  });
}

function config() {
  const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
  return v3Baseline(previous);
}

test("readiness is deterministic and uses the four explicit states", () => {
  const inactive = observeTerritoryReadiness({ ...baseSignals, activeTeams: 3, rankingEligiblePlayers: 2, validChallenges: 20 });
  const active = observeTerritoryReadiness({ ...baseSignals, activeTeams: 6, awardCandidatePlayers: 0, rankingEligiblePlayers: 7, validChallenges: 90 });
  const notReady = observeTerritoryReadiness({ ...baseSignals, activeTeams: 10, awardCandidatePlayers: 0, independentOpponentEdges: 18, rankingEligiblePlayers: 10, validChallenges: 180 });
  const ready = observeTerritoryReadiness(baseSignals);
  assert.equal(inactive.state, "ranking_inactive");
  assert.equal(active.state, "ranking_active");
  assert.equal(notReady.state, "trophy_not_ready");
  assert.equal(ready.state, "trophy_ready");
  assert.deepEqual(observeTerritoryReadiness(baseSignals), ready);
});

test("every generated snapshot narrows to the closed readiness state contract", () => {
  const states = [
    ...generatedReadiness.sourceTerritories.map(({ snapshot: item }) => item.readinessState),
    ...generatedReadiness.temporalHistory.flatMap((item) => [item.observedState, item.readinessState]),
    ...generatedReadiness.growth.healthy.flatMap(({ snapshot: item }) => [item.observedState, item.readinessState]),
    ...generatedReadiness.growth.manipulated.flatMap(({ snapshot: item }) => [item.observedState, item.readinessState]),
  ];
  assert.equal(states.every(isTerritoryReadinessState), true);
});

test("trophy readiness requires three windows and demotion also requires three", () => {
  const notReadySignals = { ...baseSignals, awardCandidatePlayers: 4 };
  const history: TerritoryReadinessSnapshot[] = [snapshot(notReadySignals)];
  history.push(snapshot(baseSignals, history));
  history.push(snapshot(baseSignals, history));
  assert.equal(history.at(-1)!.readinessState, "trophy_not_ready");
  history.push(snapshot(baseSignals, history));
  assert.equal(history.at(-1)!.readinessState, "trophy_ready");
  assert.equal(history.at(-1)!.stability.direction, "stable");

  history.push(snapshot(notReadySignals, history));
  history.push(snapshot(notReadySignals, history));
  assert.equal(history.at(-1)!.readinessState, "trophy_ready");
  history.push(snapshot(notReadySignals, history));
  assert.equal(history.at(-1)!.readinessState, "trophy_not_ready");
});

test("ten healthy teams can rank but cannot satisfy the 25/10 award baseline", () => {
  const dataset = createNetworkEcosystem({ scenario: "healthy", seed: 20261710, teamCount: 10 });
  const candidates = candidatesFromDataset(dataset, config());
  const signals = networkDatasetReadinessSignals({ candidates, dataset });
  const result = observeTerritoryReadiness(signals);
  assert.equal(signals.rankingEligiblePlayers, 10);
  assert.equal(signals.awardCandidatePlayers, 0);
  assert.equal(result.state, "trophy_not_ready");
  assert.ok(result.reasons.includes("insufficient_award_candidates"));
});

test("Synthetic World readiness counts accepted player-match evidence, not match rows", () => {
  const dataset = createNetworkEcosystem({ scenario: "healthy", seed: 20261710, teamCount: 10 });
  const candidates = candidatesFromDataset(dataset, config());
  const world = {
    state: {
      agents: candidates.map((candidate) => ({ id: candidate.id, kind: "registered", provinceCode: "08", status: "active" })),
      matches: [],
      teams: dataset.profiles.map((profile) => ({
        activity: "regular",
        id: profile.id,
        integrityClusterId: dataset.graph.logicalOpponentByTeam.get(profile.id) ?? profile.id,
        provinceCode: profile.provinceCode,
      })),
    },
  } as unknown as SyntheticWorld;
  const signals = syntheticWorldTerritorySignals(world, candidates, "08");
  assert.equal(signals.validChallenges, candidates.reduce((sum, candidate) => sum + candidate.validChallenges, 0));
  assert.equal(signals.validChallenges, 300);
});

test("a healthy connected ecosystem reaches readiness without using externalNetworkRatio as a territory gate", () => {
  const history: TerritoryReadinessSnapshot[] = [];
  for (const teamCount of [10, 20, 30, 50]) {
    const dataset = createNetworkEcosystem({ scenario: "healthy", seed: 20261700 + teamCount, teamCount });
    const candidates = candidatesFromDataset(dataset, config());
    const current = snapshot(networkDatasetReadinessSignals({ candidates, dataset }), history);
    history.push(current);
  }
  assert.equal(history[0]!.readinessState, "trophy_not_ready");
  assert.equal(history.at(-1)!.readinessState, "trophy_ready");
});

test("territory maturity and individual integrity remain separate", () => {
  const history: TerritoryReadinessSnapshot[] = [];
  let executedAttackers = 0;
  for (const teamCount of [20, 30, 50]) {
    const dataset = createNetworkEcosystem({ scenario: "manipulated", seed: 20261800 + teamCount, teamCount });
    const candidates = candidatesFromDataset(dataset, config());
    executedAttackers += candidates.filter(({ executedAbuse }) => executedAbuse).length;
    history.push(snapshot(networkDatasetReadinessSignals({ candidates, dataset }), history));
  }
  assert.ok(executedAttackers > 0);
  assert.equal(history.at(-1)!.readinessState, "trophy_ready");
  const close = closeProvincialSeason({
    candidates: [
      { individualDecision: "clean", playerId: "clean", rank: 1 },
      { individualDecision: "pending_integrity_review", playerId: "pending", rank: 8 },
    ],
    flags: { provincialAwardsEnabled: true, provincialRankingsEnabled: true },
    readiness: history.at(-1)!,
  });
  assert.deepEqual(close.awards, [
    { playerId: "clean", rank: 1, status: "certified" },
    { playerId: "pending", rank: 8, status: "pending_integrity_review" },
  ]);
});

test("rankings ON and awards OFF remains a supported public state", () => {
  const current = snapshot(baseSignals);
  const surface = readinessPublicSurface(current, PROVINCIAL_PILOT_FLAGS);
  assert.equal(surface.rankingVisible, true);
  assert.equal(surface.awardsAvailable, false);
  assert.match(surface.message, /piloto/i);
});

test("provincial ranking and award flags are independent and use the contracted keys", () => {
  assert.deepEqual(PROVINCIAL_FEATURE_FLAG_KEYS, {
    awards: "provincial_awards_enabled",
    rankings: "provincial_rankings_enabled",
  });
  assert.deepEqual(resolveProvincialFeatureFlags({
    provincial_awards_enabled: "false",
    provincial_rankings_enabled: "true",
  }), PROVINCIAL_PILOT_FLAGS);
  assert.deepEqual(resolveProvincialFeatureFlags({
    provincial_awards_enabled: "true",
    provincial_rankings_enabled: "false",
  }), {
    provincialAwardsEnabled: true,
    provincialRankingsEnabled: false,
  });
});

test("awards cannot be granted while provincial rankings are disabled", () => {
  const current = snapshot(baseSignals);
  const close = closeProvincialSeason({
    candidates: [{ individualDecision: "clean", playerId: "rank-1", rank: 1 }],
    flags: { provincialAwardsEnabled: true, provincialRankingsEnabled: false },
    readiness: current,
  });
  assert.equal(close.classification, "ranking_not_launched");
  assert.deepEqual(close.awards, []);
});

test("a non-ready territory archives its ranking without awards", () => {
  const current = snapshot({ ...baseSignals, awardCandidatePlayers: 2 });
  const close = closeProvincialSeason({
    candidates: [{ individualDecision: "clean", playerId: "rank-1", rank: 1 }],
    flags: { provincialAwardsEnabled: true, provincialRankingsEnabled: true },
    readiness: current,
  });
  assert.equal(close.classification, "archived_without_certified_awards");
  assert.deepEqual(close.awards, []);
});

test("rank 11 is never promoted when rank 8 is pending", () => {
  const current = snapshot(baseSignals);
  const close = closeProvincialSeason({
    candidates: [
      { individualDecision: "pending_integrity_review", playerId: "rank-8", rank: 8 },
      { individualDecision: "clean", playerId: "rank-11", rank: 11 },
    ],
    flags: { provincialAwardsEnabled: true, provincialRankingsEnabled: true },
    readiness: current,
  });
  assert.equal(close.promotedRank11, false);
  assert.equal(close.awards.some(({ playerId }) => playerId === "rank-11"), false);
  assert.equal(close.awards.find(({ playerId }) => playerId === "rank-8")?.status, "pending_integrity_review");
});

test("historical awards survive later territory degradation", () => {
  const degraded = snapshot({ ...baseSignals, activeTeams: 2, awardCandidatePlayers: 0, rankingEligiblePlayers: 0, validChallenges: 10 });
  const close = closeProvincialSeason({
    candidates: [],
    flags: { provincialAwardsEnabled: false, provincialRankingsEnabled: true },
    previousAwards: [{ playerId: "historic", rank: 2, status: "certified" }],
    readiness: degraded,
  });
  assert.equal(close.grantedAwardsPreserved, true);
  assert.deepEqual(close.awards, [{ playerId: "historic", rank: 2, status: "certified" }]);
});

test("readiness telemetry is aggregate and contains no player identity", () => {
  const telemetry = JSON.stringify(territoryReadinessTelemetry(snapshot(baseSignals)));
  assert.doesNotMatch(telemetry, /playerId|displayName|email|latitude|longitude/i);
});

test("the public pilot receives a reduced read model without anti-fraud laboratory data", () => {
  const client = readFileSync("app/laboratorio-ranking-provincial/provincial-ranking-pilot.tsx", "utf8");
  const server = readFileSync("app/laboratorio-ranking-provincial/page.tsx", "utf8");
  assert.doesNotMatch(client, /territory-award-readiness-v1-summary|manipulated|sourceRisk|model_3/i);
  assert.match(server, /\{ provinceCode, provinceName, ranking, snapshot, unranked \}/);
});

test("season closure order is explicit and immutable", () => {
  assert.deepEqual(PROVINCIAL_SEASON_CLOSE_PHASES, [
    "season_active",
    "season_frozen",
    "territory_readiness_final",
    "integrity_reconciliation",
    "award_certification",
    "season_closed",
  ]);
});

test("the generated growth matrix covers every requested territorial size", () => {
  assert.deepEqual(generatedReadiness.growth.healthy.map(({ teamCount }) => teamCount), [10, 20, 30, 50, 75, 100, 150]);
  assert.equal(generatedReadiness.growth.healthy[0]!.snapshot.readinessState, "trophy_not_ready");
  assert.equal(generatedReadiness.growth.healthy.at(-1)!.snapshot.readinessState, "trophy_ready");
  assert.equal(generatedReadiness.growth.manipulated.at(-1)!.snapshot.readinessState, "trophy_ready");
  assert.equal(generatedReadiness.m3, "experimental_reference");
  assert.deepEqual(generatedReadiness.scopes, {
    autonomousCommunity: "lab_only",
    national: "lab_only",
    province: "pilot_ready",
  });
});

test("TOPS V1 keeps the frozen Season Score formula", () => {
  const current = config();
  assert.deepEqual(current.weights, { competition: 30, opposition: 15, quality: 55 });
  assert.equal(current.volumeModel, "recent_30");
  assert.deepEqual(current.eligibility, {
    minimumRatingReliability: 0.45,
    minimumUniqueOpponents: 6,
    minimumValidChallenges: 15,
    recentActivityWeeks: 12,
  });
});
