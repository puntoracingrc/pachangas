import { NextResponse } from "next/server";
import { buildSyntheticDashboardData } from "../../../../simulation/synthetic-world/src/dashboard-data";
import { advanceSyntheticWorld, advanceSyntheticWorldByHours } from "../../../../simulation/synthetic-world/src/engine";
import { syntheticWorldAdminEnabled } from "../../../../simulation/synthetic-world/src/environment";
import { createSyntheticWorld } from "../../../../simulation/synthetic-world/src/generator";
import { deterministicUuid } from "../../../../simulation/synthetic-world/src/random";
import { SyntheticWorldStore } from "../../../../simulation/synthetic-world/src/store";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const noStoreHeaders = { "Cache-Control": "no-store, max-age=0" };

function disabled() {
  return NextResponse.json({ error: "NOT_FOUND" }, { headers: noStoreHeaders, status: 404 });
}

async function dashboard(store: SyntheticWorldStore, worldId?: string | null) {
  const worlds = await store.listWorlds();
  const selectedId = worldId && worlds.some(({ id }) => id === worldId) ? worldId : worlds[0]?.id;
  if (!selectedId) return { data: null, worlds };
  const [world, timeline, snapshots] = await Promise.all([
    store.loadWorld(selectedId),
    store.timeline(selectedId, 350),
    store.snapshots(selectedId, 120),
  ]);
  return { data: buildSyntheticDashboardData({ snapshots, timeline, world, worlds }), worlds };
}

export async function GET(request: Request) {
  if (!syntheticWorldAdminEnabled()) return disabled();
  const url = new URL(request.url);
  const result = await dashboard(new SyntheticWorldStore(), url.searchParams.get("world"));
  return NextResponse.json(result, { headers: noStoreHeaders });
}

export async function POST(request: Request) {
  if (!syntheticWorldAdminEnabled()) return disabled();
  try {
    const body = await request.json() as { action?: string; expectedRevision?: number; operationId?: string; seed?: number; step?: string; worldId?: string };
    const store = new SyntheticWorldStore();
    if (body.action === "create") {
      const seed = Number.isInteger(body.seed) ? Number(body.seed) : 20260809;
      const world = createSyntheticWorld({ mode: "persistent", seed });
      await store.saveWorld(world, {
        expectedRevision: -1,
        operationId: deterministicUuid(`${world.id}:create`, seed),
        snapshotKind: "checkpoint",
        snapshotPayload: world,
      });
      const result = await dashboard(store, world.id);
      return NextResponse.json(result, { headers: noStoreHeaders });
    }
    if (body.action !== "advance" || !body.worldId || !body.operationId || !Number.isInteger(body.expectedRevision)) {
      return NextResponse.json({ error: "INVALID_SYNTHETIC_ACTION" }, { headers: noStoreHeaders, status: 400 });
    }

    const replay = await store.operationReceipt(body.worldId, body.operationId);
    if (replay) {
      const result = await dashboard(store, body.worldId);
      return NextResponse.json({ ...result, receipt: { ...replay, idempotentReplay: true } }, { headers: noStoreHeaders });
    }

    const world = await store.loadWorld(body.worldId);
    if (world.revision !== body.expectedRevision) {
      return NextResponse.json({ error: "STALE_WORLD_REVISION" }, { headers: noStoreHeaders, status: 409 });
    }
    const expectedRevision = world.revision;
    const step = body.step ?? "day";
    let advanced;
    if (step === "hour") advanced = advanceSyntheticWorldByHours(world, 1);
    else if (step === "day") advanced = advanceSyntheticWorldByHours(world, 24);
    else if (step === "week") advanced = advanceSyntheticWorldByHours(world, 24 * 7);
    else if (step === "month") {
      const target = new Date(world.currentDate);
      target.setUTCMonth(target.getUTCMonth() + 1);
      advanced = advanceSyntheticWorld(world, { targetDate: target.toISOString() > world.config.seasonEnd ? world.config.seasonEnd : target.toISOString() });
    } else if (step === "season") advanced = advanceSyntheticWorld(world, { targetDate: world.config.seasonEnd });
    else return NextResponse.json({ error: "INVALID_SYNTHETIC_STEP" }, { headers: noStoreHeaders, status: 400 });

    const snapshotKind = step === "season" ? "season_end" : step === "month" ? "monthly" : null;
    const receipt = await store.saveWorld(advanced, {
      expectedRevision,
      operationId: body.operationId,
      snapshotKind,
      snapshotPayload: snapshotKind ? advanced : null,
    });
    const result = await dashboard(store, world.id);
    return NextResponse.json({ ...result, receipt }, { headers: noStoreHeaders });
  } catch (error) {
    const message = error instanceof Error ? error.message : "SYNTHETIC_WORLD_ERROR";
    const stale = /STALE_WORLD_REVISION|serialization/i.test(message);
    return NextResponse.json({ error: stale ? "STALE_WORLD_REVISION" : message }, { headers: noStoreHeaders, status: stale ? 409 : 500 });
  }
}
