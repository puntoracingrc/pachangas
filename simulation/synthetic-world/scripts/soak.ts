import { performance } from "node:perf_hooks";
import { advanceSyntheticWorldByDays, syntheticWorldSummary } from "../src/engine";
import { createSyntheticWorld } from "../src/generator";
import { dailyInvariantChecks, weeklyInvariantChecks } from "../src/invariants";

const seedCount = Number(process.env.SYNTHETIC_SOAK_SEEDS ?? 30);
const days = Number(process.env.SYNTHETIC_SOAK_DAYS ?? 35);
if (!Number.isInteger(seedCount) || seedCount < 30) throw new Error("SYNTHETIC_SOAK_SEEDS must be an integer >= 30");
if (!Number.isInteger(days) || days < 7) throw new Error("SYNTHETIC_SOAK_DAYS must be an integer >= 7");

const started = performance.now();
let eventCount = 0;
let matchCount = 0;
for (let offset = 0; offset < seedCount; offset += 1) {
  const seed = 20261000 + offset;
  const world = advanceSyntheticWorldByDays(createSyntheticWorld({ mode: "ephemeral", seed }), days);
  const dailyFailures = dailyInvariantChecks(world).filter(({ pass }) => !pass);
  const weeklyFailures = weeklyInvariantChecks(world).filter(({ pass }) => !pass);
  if (dailyFailures.length > 0 || weeklyFailures.length > 0) {
    throw new Error(`Seed ${seed} failed invariants: ${JSON.stringify({ dailyFailures, weeklyFailures })}`);
  }
  const summary = syntheticWorldSummary(world);
  eventCount += summary.events;
  matchCount += summary.totalMatches;
}

const durationMs = performance.now() - started;
const memory = process.memoryUsage();
process.stdout.write(`${JSON.stringify({
  daysPerSeed: days,
  durationMs: Math.round(durationMs),
  events: eventCount,
  matches: matchCount,
  millisecondsPerVirtualDay: Math.round((durationMs / (seedCount * days)) * 100) / 100,
  peakResidentMemoryMb: Math.round((memory.rss / 1024 / 1024) * 10) / 10,
  seeds: seedCount,
  status: "PASS",
}, null, 2)}\n`);
