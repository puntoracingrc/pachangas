import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  DEMO_WORLD_V34_AUTHORITY_HASH,
  assertDemoWorldV34FieldOperations,
  type DemoWorldV34FieldOperations,
  type DemoWorldV34PresentationManifest,
} from "../app/demo-world/demo-world-v3-4-contract";

const root = new URL("../", import.meta.url);
async function bytes(path: string) { return readFile(new URL(path, root)); }
async function json<T>(path: string) { return JSON.parse((await bytes(path)).toString("utf8")) as T; }

test("Demo World V3.4 preserves the exact V3.2 authority and has a content-addressed field snapshot", async () => {
  const manifest = await json<DemoWorldV34PresentationManifest>("public/demo-world/v3-4/manifest.json");
  const fieldBytes = await bytes("public/demo-world/v3-4/field-operations.json");
  assert.equal(manifest.authority.hash, DEMO_WORLD_V34_AUTHORITY_HASH);
  assert.equal(manifest.authority.manifest, "/demo-world/v3-2/manifest.json");
  assert.equal(manifest.authority.version, 3.2);
  assert.equal(manifest.fieldOperations.hash, createHash("sha256").update(fieldBytes).digest("hex"));
  assert.equal(manifest.remoteWrites, 0);
});

test("Field Operations contains exactly four Venues, eight Pitches and sixteen canonical stories", async () => {
  const data = assertDemoWorldV34FieldOperations(await json<DemoWorldV34FieldOperations>("public/demo-world/v3-4/field-operations.json"));
  assert.equal(data.venues.length, 4);
  assert.equal(data.pitches.length, 8);
  assert.equal(data.stories.length, 16);
  assert.equal(new Set(data.pitches.map(({ id }) => id)).size, 8);
  assert.ok(data.pitches.every(({ venueId }) => data.venues.some(({ id }) => id === venueId)));
  assert.deepEqual(new Set(data.stories.map(({ id }) => id)), new Set([
    "venue-public-consent", "venue-private", "pitch-maintenance", "recurring-availability",
    "closure-exception", "request-submitted", "club-counter", "team-accepts-counter",
    "reservation-confirmed", "last-slot-race", "hold-expired", "reservation-cancelled",
    "league-binding", "r4d-venue-change", "referee-reconfirmation", "historical-venue",
  ]));
});

test("all six perspectives are represented and privacy/payment remain inert", async () => {
  const data = await json<DemoWorldV34FieldOperations>("public/demo-world/v3-4/field-operations.json");
  assert.deepEqual(new Set(data.stories.map(({ perspective }) => perspective)), new Set([
    "team-owner", "club-booking-manager", "league-organizer", "player", "referee", "platform-reviewer",
  ]));
  assert.equal(data.privacy.pii, false);
  assert.equal(data.privacy.authIds, false);
  assert.equal(data.privacy.exactPrivateLocationBeforeConfirmation, false);
  assert.equal(data.remoteWrites, 0);
  assert.equal(data.payment.stripeCalls, 0);
  assert.equal(data.payment.customers, 0);
  assert.equal(data.payment.charges, 0);
  assert.equal(data.payment.notice, "Pago fuera de Pachangas IQ.");
  assert.doesNotMatch(JSON.stringify(data), /@[a-z0-9.-]+|auth\.users|stripe_customer|phone|telefono/i);
});

test("reservation races, hold expiry, R4D and historical Venue integrity are explicit", async () => {
  const data = await json<DemoWorldV34FieldOperations>("public/demo-world/v3-4/field-operations.json");
  assert.equal(data.integrity.confirmedOverlaps, 0);
  assert.equal(data.integrity.noAutoCancel, true);
  assert.equal(data.integrity.noAutoForfeit, true);
  assert.equal(data.stories.find(({ id }) => id === "last-slot-race")?.reservationStatus, "ONE_WINNER");
  assert.equal(data.stories.find(({ id }) => id === "hold-expired")?.state, "EXPIRED");
  assert.deepEqual(data.stories.find(({ id }) => id === "r4d-venue-change")?.matchBinding?.lineage, ["original-binding", "fixture-change", "replacement-binding"]);
  assert.equal(data.stories.find(({ id }) => id === "referee-reconfirmation")?.state, "ACTION_REQUIRED");
  assert.equal(data.stories.find(({ id }) => id === "historical-venue")?.matchBinding?.status, "CONSUMED");
});

test("Demo UI exposes Campos responsively and performs no remote mutation", async () => {
  const [page, fullPage, currentManifest, app, component, css, contextCss] = await Promise.all([
    bytes("app/demo/page.tsx"),
    bytes("app/admin/demo/page.tsx"),
    bytes("app/demo-world/current-demo-world-manifest.ts"),
    bytes("app/demo-world/demo-world-app.tsx"),
    bytes("app/demo-world/demo-world-v3-4-field-operations.tsx"),
    bytes("app/demo-world/demo-world-v3-4-field-operations.module.css"),
    bytes("app/_components/product-context-selector.module.css"),
  ]).then((values) => values.map((value) => value.toString("utf8")));
  assert.match(page, /mode="social"/);
  assert.match(fullPage, /session\.access\.role !== "platform_owner"/);
  assert.match(fullPage, /mode="full"/);
  assert.match(currentManifest, /public\/demo-world\/v3-4\/manifest\.json/);
  assert.match(currentManifest, /fieldOperations: fieldOperationsSource as DemoWorldV34PresentationManifest/);
  assert.match(app, /id: "campos"/);
  assert.match(app, /DemoWorldV34FieldOperations/);
  assert.match(component, /cache: "force-cache"/);
  assert.doesNotMatch(component, /method: "POST"|clientWriteFetch|\.rpc\(/);
  assert.match(css, /max-width: 760px/);
  assert.match(css, /orientation: landscape/);
  assert.match(
    contextCss,
    /\.copy select \{[\s\S]*color: var\(--official-text, #f1f6f2\);[\s\S]*color-scheme: inherit;/,
  );
});
