import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { buildConductV1Replay, conductCanonicalStateHash } from "../src/conduct-v1";
import { advanceSyntheticWorld, reconcileSyntheticConductCoverage, syntheticWorldSummary } from "../src/engine";
import { createSyntheticWorld } from "../src/generator";
import { dailyInvariantChecks, weeklyInvariantChecks } from "../src/invariants";
import { loadSyntheticLocalEnv } from "../src/local-env";
import { SyntheticWorldStore } from "../src/store";
import type { SyntheticWorld } from "../src/types";

const SOURCE_WORLD_ID = "3df9494d-3b8c-4447-96e8-d5244892af78";
const SOURCE_REVISION = 313;
const SOURCE_SEQUENCE = 69_458;
const ROOT = resolve(new URL("../../..", import.meta.url).pathname);
const GENERATED = resolve(ROOT, "simulation/synthetic-world/generated");

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function sportingState(world: SyntheticWorld) {
  return {
    achievements: world.state.achievements,
    agents: world.state.agents.map(({ facets, id, ratingReliability, ratingV2 }) => ({ facets, id, ratingReliability, ratingV2 })),
    boxes: world.state.boxes,
    ratingOpinions: world.state.ratingOpinions,
    rankings: world.state.rankings,
  };
}

function replayWithoutMutation(world: SyntheticWorld) {
  const stateHashBefore = hash(world.state);
  const canonicalStateHashBefore = conductCanonicalStateHash(world);
  const sportingHashBefore = hash(sportingState(world));
  const replay = buildConductV1Replay(world);
  const stateHashAfter = hash(world.state);
  const canonicalStateHashAfter = conductCanonicalStateHash(world);
  const sportingHashAfter = hash(sportingState(world));
  if (stateHashBefore !== stateHashAfter) throw new Error("CONDUCT_REPLAY_MUTATED_SOURCE_WORLD");
  if (canonicalStateHashBefore !== canonicalStateHashAfter) throw new Error("CONDUCT_REPLAY_CHANGED_CANONICAL_SOURCE_STATE");
  if (sportingHashBefore !== sportingHashAfter) throw new Error("CONDUCT_REPLAY_CHANGED_SPORTING_STATE");
  return {
    canonicalStateHashAfter,
    canonicalStateHashBefore,
    replay,
    sportingHashAfter,
    sportingHashBefore,
    stateHashAfter,
    stateHashBefore,
  };
}

async function run() {
  loadSyntheticLocalEnv();
  const source = await new SyntheticWorldStore().loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION || source.state.eventSequence !== SOURCE_SEQUENCE) {
    throw new Error(`SOURCE_WORLD_CHANGED expected r${SOURCE_REVISION}/seq${SOURCE_SEQUENCE}, actual r${source.revision}/seq${source.state.eventSequence}`);
  }
  const sourceResult = replayWithoutMutation(source);
  if (sourceResult.replay.attendance.candidateNoShows !== 37) throw new Error("SOURCE_NO_SHOW_COUNT_CHANGED");
  if (sourceResult.replay.attendance.sourceRepeatCandidates !== 8) throw new Error("SOURCE_REPEAT_NO_SHOW_COUNT_CHANGED");
  if (sourceResult.replay.attendance.normalCancellations !== 424) throw new Error("SOURCE_CANCELLATION_COUNT_CHANGED");
  if (sourceResult.replay.conduct.cases !== 79) throw new Error("SOURCE_CONDUCT_SCENARIO_COUNT_CHANGED");

  const soakWorld = reconcileSyntheticConductCoverage(advanceSyntheticWorld(createSyntheticWorld({
    mode: "ephemeral",
    seed: 20260819,
  }), { targetDate: "2027-06-30T00:00:00.000Z" }));
  const soakResult = replayWithoutMutation(soakWorld);
  const dailyFailures = dailyInvariantChecks(soakWorld).filter(({ pass }) => !pass);
  const weeklyFailures = weeklyInvariantChecks(soakWorld).filter(({ pass }) => !pass);
  if (dailyFailures.length > 0 || weeklyFailures.length > 0) {
    throw new Error(`CONDUCT_SOAK_INVARIANT_FAILURE ${JSON.stringify({ dailyFailures, weeklyFailures })}`);
  }
  const soakSummary = syntheticWorldSummary(soakWorld);
  if (soakSummary.teams !== 50 || soakSummary.registeredAgents < 600 || soakWorld.status !== "completed") {
    throw new Error(`CONDUCT_SOAK_VOLUME_FAILURE ${JSON.stringify(soakSummary)}`);
  }

  const result = {
    generatedAt: new Date().toISOString(),
    policy: {
      appealAndCorrection: true,
      attendanceClosureHours: 48,
      disputeHours: 72,
      humanDecisionRequiredForRestriction: true,
      lateCancellationIsNoShow: false,
      reporterIdentityPublic: false,
      socialRestrictionsAffectSport: false,
    },
    soak: {
      invariants: { dailyFailures: 0, weeklyFailures: 0 },
      replay: soakResult.replay,
      sourcePreserved: soakResult.stateHashBefore === soakResult.stateHashAfter,
      sportingSystemsPreserved: soakResult.sportingHashBefore === soakResult.sportingHashAfter,
      summary: soakSummary,
    },
    source: {
      eventSequence: source.state.eventSequence,
      replay: sourceResult.replay,
      revision: source.revision,
      sourcePreserved: sourceResult.stateHashBefore === sourceResult.stateHashAfter,
      sportingSystemsPreserved: sourceResult.sportingHashBefore === sourceResult.sportingHashAfter,
      stateHash: sourceResult.canonicalStateHashAfter,
      worldId: source.id,
    },
  };
  mkdirSync(GENERATED, { recursive: true });
  writeFileSync(resolve(GENERATED, "conduct-reports-no-show-v1-summary.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  console.log(JSON.stringify({
    soak: {
      matches: result.soak.summary.totalMatches,
      players: result.soak.summary.registeredAgents,
      teams: result.soak.summary.teams,
    },
    source: {
      attendance: result.source.replay.attendance,
      conduct: result.source.replay.conduct,
      eventSequence: result.source.eventSequence,
      revision: result.source.revision,
    },
  }, null, 2));
  return result;
}

await run();
