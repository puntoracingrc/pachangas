import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  DEMO_WORLD_V35_V32_AUTHORITY_HASH,
  DEMO_WORLD_V35_V34_FIELD_HASH,
  assertDemoWorldV35SeasonFieldAllocation,
  type DemoWorldV35PresentationManifest,
  type DemoWorldV35SeasonFieldAllocation,
} from "../app/demo-world/demo-world-v3-5-contract";
import type { SyntheticSeasonIndex } from "../app/demo-world/demo-world-v3-2-contract";
import type { DemoWorldV34FieldOperations } from "../app/demo-world/demo-world-v3-4-contract";

const root = new URL("../", import.meta.url);
async function bytes(path: string) { return readFile(new URL(path, root)); }
async function json<T>(path: string) { return JSON.parse((await bytes(path)).toString("utf8")) as T; }

test("Demo World V3.5 preserves V3.2 and V3.4 authority hashes", async () => {
  const manifest = await json<DemoWorldV35PresentationManifest>("public/demo-world/v3-5/manifest.json");
  const allocationBytes = await bytes("public/demo-world/v3-5/season-field-allocation.json");
  assert.equal(manifest.authority.seasonHash, DEMO_WORLD_V35_V32_AUTHORITY_HASH);
  assert.equal(manifest.authority.fieldOperationsHash, DEMO_WORLD_V35_V34_FIELD_HASH);
  assert.equal(manifest.seasonFieldAllocation.hash, createHash("sha256").update(allocationBytes).digest("hex"));
  assert.equal(manifest.seasonFieldAllocation.matches, 128);
  assert.equal(manifest.remoteWrites, 0);
});

test("all 128 schedule times remain identical and every published Pitch is compatible", async () => {
  const data = assertDemoWorldV35SeasonFieldAllocation(await json<DemoWorldV35SeasonFieldAllocation>("public/demo-world/v3-5/season-field-allocation.json"));
  const season = await json<SyntheticSeasonIndex>("public/demo-world/v3-2/season.json");
  const fields = await json<DemoWorldV34FieldOperations>("public/demo-world/v3-4/field-operations.json");
  const source = new Map(season.matches.map((match) => [match.canonicalMatchId, match.scheduledAt]));
  const pitches = new Map(fields.pitches.map((pitch) => [pitch.id, pitch]));
  assert.equal(new Set(data.assignments.map((item) => item.canonicalMatchId)).size, 128);
  assert.ok(data.assignments.every((item) => source.get(item.canonicalMatchId) === item.scheduledBefore && item.scheduledBefore === item.scheduledAfter));
  assert.ok(data.assignments.filter((item) => item.pitchId).every((item) => {
    const pitch = pitches.get(item.pitchId);
    return pitch?.status === "ACTIVE" && pitch.modalities.includes(item.modality);
  }));
  assert.equal(data.assignments.filter((item) => item.assignmentStatus === "UNASSIGNED").length, 1);
  assert.equal(data.assignments.filter((item) => item.sourceKind === "EXISTING_BINDING").length, 16);
});

test("confirmed reservations have no Pitch overlap or duplicate active binding", async () => {
  const data = await json<DemoWorldV35SeasonFieldAllocation>("public/demo-world/v3-5/season-field-allocation.json");
  const active = data.assignments.filter((item) => item.bindingStatus === "ACTIVE");
  assert.equal(active.length, 126);
  assert.equal(new Set(active.map((item) => item.canonicalMatchId)).size, active.length);
  const byPitch = new Map<string, Array<[number, number, string]>>();
  for (const item of active) {
    assert.ok(item.pitchId);
    const start = Date.parse(item.scheduledAfter);
    const end = start + 70 * 60_000;
    const rows = byPitch.get(item.pitchId!) ?? [];
    assert.ok(rows.every(([from, until]) => end <= from || start >= until), `${item.canonicalMatchId} overlaps on ${item.pitchId}`);
    rows.push([start, end, item.canonicalMatchId]);
    byPitch.set(item.pitchId!, rows);
  }
  assert.equal(data.integrity.confirmedOverlaps, 0);
  assert.equal(data.integrity.activeBindingDuplicates, 0);
});

test("automatic and hybrid histories reconcile locks, incidents and canonical publication", async () => {
  const data = await json<DemoWorldV35SeasonFieldAllocation>("public/demo-world/v3-5/season-field-allocation.json");
  assert.equal(data.plans.length, 8);
  assert.equal(data.plans.filter((plan) => plan.mode === "AUTOMATIC").length, 4);
  assert.equal(data.plans.filter((plan) => plan.mode === "HYBRID").length, 4);
  assert.equal(data.plans.filter((plan) => plan.mode === "HYBRID").reduce((sum, plan) => sum + plan.lockCount, 0), 3);
  assert.ok(data.plans.every((plan) => plan.algorithmVersion === "season-venue-allocation-v1" && plan.hardViolations === 0 && plan.resultChecksum.length === 64));
  assert.deepEqual(new Set(data.conflicts.map(({ code }) => code)), new Set([
    "PITCH_MAINTENANCE", "RECURRING_OCCURRENCE_CANCELLED", "HOLD_EXPIRED",
    "PITCH_SLOT_COMPETITION", "VENUE_ALLOCATION_CONFLICT",
    "RESERVATION_CANCELLED_AFTER_PUBLISH", "R4D_VENUE_CHANGE",
  ]));
  assert.equal(data.counts.reservations, 127);
  assert.equal(data.counts.activeBindings, 126);
  assert.equal(data.integrity.hardViolationsPublished, 0);
});

test("V3.5 is sanitized, read-only, PWA-cacheable and visually responsive", async () => {
  const [data, view, css, app, page, worker, generator] = await Promise.all([
    bytes("public/demo-world/v3-5/season-field-allocation.json"),
    bytes("app/demo-world/demo-world-v3-5-season-field-allocation.tsx"),
    bytes("app/demo-world/demo-world-v3-5-season-field-allocation.module.css"),
    bytes("app/demo-world/demo-world-app.tsx"),
    bytes("app/demo/page.tsx"),
    bytes("app/service-worker-source.ts"),
    bytes("scripts/demo-world/generate-demo-world-v3-5.ts"),
  ]).then((values) => values.map((value) => value.toString("utf8")));
  assert.doesNotMatch(data, /@[a-z0-9.-]+|auth\.users|private_address|phone|telefono|sk_live_|rk_live_|whsec_/i);
  assert.match(view, /cache: "force-cache"/);
  assert.doesNotMatch(view, /method: "POST"|clientWriteFetch|\.rpc\(/);
  assert.match(view, /club-booking-manager/);
  assert.match(view, /tournament-organizer/);
  assert.match(css, /max-width: 760px/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(app, /DemoWorldV35SeasonFieldAllocation/);
  assert.match(app, /closest\("details"\)\?\.removeAttribute\("open"\)/);
  assert.match(page, /version: 3\.5/);
  assert.match(worker, /\/demo-world\/v3-5\/manifest\.json/);
  assert.match(generator, /season-venue-allocation-v1-db-runner\.mjs/);
  assert.match(generator, /temporaryDatabaseDestroyed: true/);
});
