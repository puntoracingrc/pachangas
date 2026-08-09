import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { CORE_SOCIAL_V2_FLOWS, createCoreSocialV2Clone } from "../src/core-social-v2";
import { loadSyntheticLocalEnv } from "../src/local-env";
import { deterministicUuid } from "../src/random";
import { SyntheticWorldStore } from "../src/store";

const SOURCE_WORLD_ID = "3df9494d-3b8c-4447-96e8-d5244892af78";
const SOURCE_REVISION = 313;
const SOURCE_SEQUENCE = 69_458;
const SEED_COUNT = 30;
const ROOT = resolve(new URL("../../..", import.meta.url).pathname);
const GENERATED = resolve(ROOT, "simulation/synthetic-world/generated");

function hash(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

async function run() {
  loadSyntheticLocalEnv();
  const store = new SyntheticWorldStore();
  const source = await store.loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION || source.state.eventSequence !== SOURCE_SEQUENCE) {
    throw new Error(`SOURCE_WORLD_CHANGED expected r${SOURCE_REVISION}/seq${SOURCE_SEQUENCE}, actual r${source.revision}/seq${source.state.eventSequence}`);
  }
  const sourceHashBefore = hash(source);
  const primary = createCoreSocialV2Clone(source, 20260820);
  if (primary.audit.coverage.some(({ status }) => status !== "PASS")) throw new Error("CORE_SOCIAL_V2_COVERAGE_INCOMPLETE");

  const existing = new Set((await store.listWorlds()).map(({ id }) => id));
  let persisted = false;
  if (!existing.has(primary.clone.id)) {
    await store.saveWorld(primary.clone, {
      expectedRevision: -1,
      operationId: deterministicUuid(`${primary.clone.id}:persist`, "core-social-v2"),
      snapshotKind: "checkpoint",
      snapshotPayload: primary.clone,
    });
    persisted = true;
  }

  const soak = Array.from({ length: SEED_COUNT }, (_, index) => {
    const result = createCoreSocialV2Clone(source, 20260820 + index);
    const failedFlows = result.audit.coverage.filter(({ status }) => status !== "PASS").map(({ flow }) => flow);
    if (failedFlows.length > 0) throw new Error(`CORE_SOCIAL_V2_SEED_${20260820 + index}_FAILED:${failedFlows.join(",")}`);
    if (!Object.values(result.audit.preserved).every(Boolean)) throw new Error(`CORE_SOCIAL_V2_SEED_${20260820 + index}_PRESERVATION_FAILED`);
    return {
      eventsAdded: result.clone.state.eventSequence - source.state.eventSequence,
      flowsPassed: result.audit.coverage.length,
      seed: 20260820 + index,
      stories: result.audit.stories.length,
    };
  });

  const sourceHashAfter = hash(source);
  if (sourceHashBefore !== sourceHashAfter) throw new Error("SOURCE_WORLD_MUTATED");
  const result = {
    audit: primary.audit,
    generatedAt: new Date().toISOString(),
    persistedClone: persisted,
    sourceHash: sourceHashAfter,
    soak: {
      eventsAdded: soak.reduce((sum, row) => sum + row.eventsAdded, 0),
      expectedFlows: CORE_SOCIAL_V2_FLOWS.length,
      failedSeeds: 0,
      flowsPassed: soak.reduce((sum, row) => sum + row.flowsPassed, 0),
      seeds: SEED_COUNT,
      stories: soak.reduce((sum, row) => sum + row.stories, 0),
    },
  };
  mkdirSync(GENERATED, { recursive: true });
  writeFileSync(resolve(GENERATED, "core-social-flows-v2-summary.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  process.stdout.write(`${JSON.stringify({
    clone: result.audit.clone,
    coverage: result.audit.coverage.length,
    source: result.audit.source,
    sourceHash: result.sourceHash,
    soak: result.soak,
  }, null, 2)}\n`);
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
