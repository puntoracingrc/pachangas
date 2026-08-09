import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { addVirtualDays } from "./src/clock";
import {
  advanceSyntheticWorld,
  cloneSyntheticWorldFromCurrent,
  reconcileSyntheticConductCoverage,
  reconcileSyntheticRankingCoverage,
  syntheticWorldSummary,
} from "./src/engine";
import { assertSyntheticWorldEnvironment } from "./src/environment";
import { createSyntheticWorld } from "./src/generator";
import { syntheticErrorMessage } from "./src/errors";
import { loadSyntheticLocalEnv } from "./src/local-env";
import { deterministicUuid } from "./src/random";
import { SyntheticWorldStore } from "./src/store";

function argumentsMap(values: string[]) {
  const result = new Map<string, string>();
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index]!;
    if (!value.startsWith("--")) continue;
    result.set(value.slice(2), values[index + 1]?.startsWith("--") ? "1" : values[++index] ?? "1");
  }
  return result;
}

function required(map: Map<string, string>, name: string) {
  const value = map.get(name);
  if (!value) throw new Error(`--${name} is required`);
  return value;
}

function nextMonthBoundary(currentDate: string, seasonEnd: string) {
  const current = new Date(currentDate);
  const next = new Date(Date.UTC(current.getUTCFullYear(), current.getUTCMonth() + 1, 1));
  return next.toISOString() > seasonEnd ? seasonEnd : next.toISOString();
}

async function createCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const seed = Number(args.get("seed") ?? 20260809);
  const world = createSyntheticWorld({ mode: args.get("mode") === "ephemeral" ? "ephemeral" : "persistent", name: args.get("name"), seed });
  const receipt = await store.saveWorld(world, {
    expectedRevision: -1,
    operationId: deterministicUuid(`${world.id}:create`, seed),
    snapshotKind: "checkpoint",
    snapshotPayload: world,
  });
  return { receipt, summary: syntheticWorldSummary(world) };
}

async function advanceCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const world = await store.loadWorld(required(args, "world"));
  const expectedRevision = world.revision;
  const targetDate = args.get("to") ?? addVirtualDays(world.currentDate, Number(args.get("days") ?? 7)).toISOString();
  const advanced = advanceSyntheticWorld(world, { failureInjectionRate: Number(args.get("failure-rate") ?? 0), targetDate });
  const receipt = await store.saveWorld(advanced, {
    expectedRevision,
    operationId: args.get("operation-id") ?? deterministicUuid(`${world.id}:advance`, `${expectedRevision}:${targetDate}`),
    snapshotKind: args.get("snapshot") === "1" ? "checkpoint" : null,
    snapshotPayload: args.get("snapshot") === "1" ? advanced : null,
  });
  return { receipt, summary: syntheticWorldSummary(advanced) };
}

async function seasonCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const seed = Number(args.get("seed") ?? 20260809);
  const id = deterministicUuid("pachangas-synthetic-world", `${seed}:persistent:2026-27`);
  let world;
  try {
    world = await store.loadWorld(id);
  } catch {
    world = createSyntheticWorld({ mode: "persistent", name: args.get("name"), seed });
    await store.saveWorld(world, { expectedRevision: -1, operationId: deterministicUuid(`${world.id}:create`, seed), snapshotKind: "checkpoint", snapshotPayload: world });
  }
  while (world.currentDate.slice(0, 10) < world.config.seasonEnd.slice(0, 10)) {
    const expectedRevision = world.revision;
    const targetDate = nextMonthBoundary(world.currentDate, world.config.seasonEnd);
    world = advanceSyntheticWorld(world, { failureInjectionRate: Number(args.get("failure-rate") ?? 0), targetDate });
    await store.saveWorld(world, {
      expectedRevision,
      operationId: deterministicUuid(`${world.id}:season-advance`, `${expectedRevision}:${targetDate}`),
      snapshotKind: world.status === "completed" ? "season_end" : "monthly",
      snapshotPayload: world,
    });
    process.stdout.write(`Advanced ${world.currentDate.slice(0, 10)} · revision ${world.revision} · ${world.state.matches.length} matches\n`);
  }
  return { summary: syntheticWorldSummary(world), worldId: world.id };
}

async function cloneCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const source = await store.loadWorld(required(args, "world"));
  const seed = Number(required(args, "seed"));
  const clone = cloneSyntheticWorldFromCurrent(source, seed, args.get("name"));
  const receipt = await store.saveWorld(clone, { expectedRevision: -1, operationId: deterministicUuid(`${clone.id}:create`, seed), snapshotKind: "checkpoint", snapshotPayload: clone });
  return { receipt, summary: syntheticWorldSummary(clone) };
}

async function reconcileConductCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const source = await store.loadWorld(required(args, "world"));
  const reconciled = reconcileSyntheticConductCoverage(source);
  if (reconciled.revision === source.revision) return { changed: false, summary: syntheticWorldSummary(source) };
  const receipt = await store.saveWorld(reconciled, {
    expectedRevision: source.revision,
    operationId: deterministicUuid(`${source.id}:conduct-coverage`, reconciled.revision),
    snapshotKind: "checkpoint",
    snapshotPayload: reconciled,
  });
  return { changed: true, receipt, summary: syntheticWorldSummary(reconciled) };
}

async function reconcileRankingCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const source = await store.loadWorld(required(args, "world"));
  const reconciled = reconcileSyntheticRankingCoverage(source);
  if (reconciled.revision === source.revision) return { changed: false, summary: syntheticWorldSummary(source) };
  const receipt = await store.saveWorld(reconciled, {
    expectedRevision: source.revision,
    operationId: deterministicUuid(`${source.id}:ranking-coverage`, reconciled.revision),
    snapshotKind: "checkpoint",
    snapshotPayload: reconciled,
  });
  return { changed: true, receipt, summary: syntheticWorldSummary(reconciled) };
}

function incidentSignature(incidents: Array<{ id: string; occurrenceCount: number; status: string }>) {
  return incidents.map(({ id, occurrenceCount, status }) => `${id}:${status}:${occurrenceCount}`).sort().join("|");
}

async function syncIncidentsCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const source = await store.loadWorld(required(args, "world"));
  const persisted = await store.incidents(source.id);
  const signature = incidentSignature(source.state.incidents);
  if (signature === incidentSignature(persisted)) return { changed: false, summary: syntheticWorldSummary(source) };
  const synchronized = structuredClone(source);
  synchronized.revision += 1;
  const receipt = await store.saveWorld(synchronized, {
    expectedRevision: source.revision,
    operationId: deterministicUuid(`${source.id}:incident-catalog-sync`, signature),
  });
  return { changed: true, receipt, summary: syntheticWorldSummary(synchronized) };
}

async function exportCommand(store: SyntheticWorldStore, args: Map<string, string>) {
  const world = await store.loadWorld(required(args, "world"));
  const directory = resolve(process.cwd(), "simulation/synthetic-world/exports");
  await mkdir(directory, { recursive: true });
  const path = resolve(directory, `${world.id}-${world.currentDate.slice(0, 10)}.json`);
  await writeFile(path, `${JSON.stringify({ exportedAt: new Date().toISOString(), summary: syntheticWorldSummary(world), world }, null, 2)}\n`, "utf8");
  return { path, summary: syntheticWorldSummary(world) };
}

async function main() {
  loadSyntheticLocalEnv();
  assertSyntheticWorldEnvironment();
  const [command = "list", ...rawArgs] = process.argv.slice(2);
  const args = argumentsMap(rawArgs);
  const store = new SyntheticWorldStore();
  const output = command === "create" ? await createCommand(store, args)
    : command === "advance" ? await advanceCommand(store, args)
      : command === "season" ? await seasonCommand(store, args)
        : command === "clone" ? await cloneCommand(store, args)
          : command === "reconcile-conduct" ? await reconcileConductCommand(store, args)
            : command === "reconcile-ranking" ? await reconcileRankingCommand(store, args)
              : command === "sync-incidents" ? await syncIncidentsCommand(store, args)
                : command === "export" ? await exportCommand(store, args)
                  : command === "list" ? await store.listWorlds()
                    : null;
  if (output === null) throw new Error(`Unknown command: ${command}`);
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

void main().catch((error) => {
  process.stderr.write(`${syntheticErrorMessage(error)}\n`);
  process.exitCode = 1;
});
