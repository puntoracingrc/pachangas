import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { buildConductTriageV11Audit, CONDUCT_TRIAGE_POLICY_V1_1 } from "../src/conduct-triage-v1-1";
import { conductCanonicalStateHash } from "../src/conduct-v1";
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

function auditWithoutMutation(world: SyntheticWorld) {
  const fullBefore = hash(world.state);
  const canonicalBefore = conductCanonicalStateHash(world);
  const sportingBefore = hash(sportingState(world));
  const audit = buildConductTriageV11Audit(world);
  const fullAfter = hash(world.state);
  const canonicalAfter = conductCanonicalStateHash(world);
  const sportingAfter = hash(sportingState(world));
  if (fullBefore !== fullAfter || canonicalBefore !== canonicalAfter) throw new Error("CONDUCT_TRIAGE_MUTATED_WORLD");
  if (sportingBefore !== sportingAfter) throw new Error("CONDUCT_TRIAGE_CHANGED_SPORTING_STATE");
  return { audit, canonicalHash: canonicalAfter, sourcePreserved: true, sportingSystemsPreserved: true };
}

async function run() {
  loadSyntheticLocalEnv();
  const source = await new SyntheticWorldStore().loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION || source.state.eventSequence !== SOURCE_SEQUENCE) {
    throw new Error(`SOURCE_WORLD_CHANGED expected r${SOURCE_REVISION}/seq${SOURCE_SEQUENCE}, actual r${source.revision}/seq${source.state.eventSequence}`);
  }
  const sourceResult = auditWithoutMutation(source);
  if (sourceResult.audit.cases !== 79) throw new Error("SOURCE_TRIAGE_CASE_COUNT_CHANGED");

  const soakWorld = reconcileSyntheticConductCoverage(advanceSyntheticWorld(createSyntheticWorld({
    mode: "ephemeral",
    seed: 20260819,
  }), { targetDate: "2027-06-30T00:00:00.000Z" }));
  const soakResult = auditWithoutMutation(soakWorld);
  const dailyFailures = dailyInvariantChecks(soakWorld).filter(({ pass }) => !pass);
  const weeklyFailures = weeklyInvariantChecks(soakWorld).filter(({ pass }) => !pass);
  if (dailyFailures.length || weeklyFailures.length) throw new Error("CONDUCT_TRIAGE_SOAK_INVARIANT_FAILURE");
  if (soakResult.audit.cases !== 88) throw new Error("SOAK_TRIAGE_CASE_COUNT_CHANGED");
  const result = {
    generatedAt: new Date().toISOString(),
    policy: CONDUCT_TRIAGE_POLICY_V1_1,
    shadowMode: {
      activeTriageEnabled: false,
      humanV1QueuePreserved: true,
      recommendedTriageCalculated: true,
      sanctionsAppliedAutomatically: false,
    },
    soak: {
      ...soakResult,
      invariants: { dailyFailures: 0, weeklyFailures: 0 },
      summary: syntheticWorldSummary(soakWorld),
    },
    source: {
      ...sourceResult,
      eventSequence: source.state.eventSequence,
      revision: source.revision,
      worldId: source.id,
    },
  };
  mkdirSync(GENERATED, { recursive: true });
  writeFileSync(resolve(GENERATED, "conduct-triage-v1-1-summary.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  console.log(JSON.stringify({
    soak: {
      backlog: result.soak.audit.backlog,
      cases: result.soak.audit.cases,
      humanReviewCases: result.soak.audit.humanReviewCases,
      metrics: {
        falseEscalationRate: result.soak.audit.falseEscalationRate,
        humanReviewRate: result.soak.audit.humanReviewRate,
        seriousCasePrecision: result.soak.audit.seriousCasePrecision,
        seriousCaseRecall: result.soak.audit.seriousCaseRecall,
      },
      queues: result.soak.audit.queues,
    },
    source: {
      cases: result.source.audit.cases,
      humanReviewCases: result.source.audit.humanReviewCases,
      metrics: {
        falseEscalationRate: result.source.audit.falseEscalationRate,
        humanReviewRate: result.source.audit.humanReviewRate,
        seriousCasePrecision: result.source.audit.seriousCasePrecision,
        seriousCaseRecall: result.source.audit.seriousCaseRecall,
      },
      queues: result.source.audit.queues,
    },
  }, null, 2));
}

await run();
