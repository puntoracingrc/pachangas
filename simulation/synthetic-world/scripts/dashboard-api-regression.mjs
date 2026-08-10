import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const baseUrl = process.env.SYNTHETIC_DASHBOARD_API_URL ?? "http://127.0.0.1:3090/api/admin/simulation-world";
const worldId = process.env.SYNTHETIC_WORLD_ID;

if (!worldId) throw new Error("SYNTHETIC_WORLD_ID is required");

async function request(body) {
  const response = await fetch(baseUrl, {
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
    method: "POST",
  });
  return { body: await response.json(), status: response.status };
}

const initialResponse = await fetch(`${baseUrl}?world=${encodeURIComponent(worldId)}`);
assert.equal(initialResponse.status, 200);
const initial = await initialResponse.json();
const expectedRevision = initial.data?.world?.revision;
assert.equal(Number.isInteger(expectedRevision), true);

const operationId = randomUUID();
const intention = { action: "advance", expectedRevision, operationId, step: "hour", worldId };
const first = await request(intention);
const replay = await request(intention);
const stale = await request({ ...intention, operationId: randomUUID() });

assert.equal(first.status, 200);
assert.equal(first.body.data.world.revision, expectedRevision + 1);
assert.equal(first.body.receipt.idempotentReplay, false);
assert.equal(replay.status, 200);
assert.equal(replay.body.data.world.revision, first.body.data.world.revision);
assert.equal(replay.body.data.world.currentDate, first.body.data.world.currentDate);
assert.equal(replay.body.receipt.idempotentReplay, true);
assert.equal(stale.status, 409);
assert.equal(stale.body.error, "STALE_WORLD_REVISION");

console.log(JSON.stringify({
  confirmedRevision: first.body.data.world.revision,
  idempotentReplay: replay.body.receipt.idempotentReplay,
  staleResult: stale.body.error,
  virtualDate: first.body.data.world.currentDate,
  worldId,
}, null, 2));
