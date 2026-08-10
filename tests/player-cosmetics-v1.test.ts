import assert from "node:assert/strict";
import test from "node:test";
import {
  PLAYER_COSMETIC_CATALOG,
  PLAYER_COSMETIC_PROTOTYPES,
} from "../app/player-cosmetics-catalog";
import {
  EMPTY_PLAYER_COSMETIC_LOADOUT,
  cosmeticCacheKey,
  normalizePlayerCosmeticsSnapshot,
  normalizePublicPlayerCosmeticsSnapshot,
  playerCosmeticLoadoutsEqual,
  playerCosmeticSportingChecksum,
  readPlayerCosmeticsCache,
  unseenCosmeticsBySlot,
  withCosmeticKey,
  writePlayerCosmeticsCache,
} from "../app/player-cosmetics-contract";
import { advanceSyntheticWorld, syntheticWorldSummary } from "../simulation/synthetic-world/src/engine";
import { createSyntheticWorld } from "../simulation/synthetic-world/src/generator";
import { dailyInvariantChecks, weeklyInvariantChecks } from "../simulation/synthetic-world/src/invariants";

function memoryStorage(): Storage {
  const values = new Map<string, string>();
  return {
    clear: () => values.clear(),
    getItem: (key) => values.get(key) ?? null,
    key: (index) => [...values.keys()][index] ?? null,
    get length() { return values.size; },
    removeItem: (key) => { values.delete(key); },
    setItem: (key, value) => { values.set(key, value); },
  };
}

const snapshotPayload = {
  enabled: true,
  featuredBadges: [{ achievementKey: "player.hat_trick", grantId: "grant-1", rarity: "rare", title: "Hat-trick" }],
  loadout: { ...EMPTY_PLAYER_COSMETIC_LOADOUT, frameKey: "player.frame.barrio.steel" },
  owned: [{
    acquiredAt: "2026-08-10T10:00:00Z",
    collection: "futbol_de_barrio",
    description: "Marco",
    key: "player.frame.barrio.steel",
    layerOrder: 10,
    material: "steel",
    name: "Barrio Acero",
    rarity: "common",
    render: { frameStyle: "barrio" },
    seenAt: null,
    serverSequence: 14,
    slot: "frame",
    sourceBoxId: "box-1",
  }],
  playerProfileId: "profile-1",
  revision: 4,
  serverSequence: 14,
  updatedAt: "2026-08-10T10:00:00Z",
};

test("the V1 catalog selects 14 real pieces from 30 laboratory prototypes", () => {
  assert.equal(PLAYER_COSMETIC_CATALOG.length, 14);
  assert.equal(PLAYER_COSMETIC_PROTOTYPES.length, 30);
  assert.equal(new Set(PLAYER_COSMETIC_CATALOG.map(({ key }) => key)).size, 14);
  assert.ok(PLAYER_COSMETIC_CATALOG.every(({ prototype }) => !prototype));
  assert.deepEqual(new Set(PLAYER_COSMETIC_CATALOG.map(({ slot }) => slot)), new Set(["accent", "background", "effect", "frame", "title"]));
});

test("canonical snapshots normalize ownership, NEW state and real featured achievements", () => {
  const snapshot = normalizePlayerCosmeticsSnapshot(snapshotPayload);
  assert.ok(snapshot);
  assert.equal(snapshot.revision, 4);
  assert.equal(snapshot.owned[0]?.seenAt, null);
  assert.equal(unseenCosmeticsBySlot(snapshot.owned).frame, 1);
  assert.equal(snapshot.featuredBadges[0]?.grantId, "grant-1");
  assert.equal(normalizePlayerCosmeticsSnapshot({ ...snapshotPayload, playerProfileId: "" }), null);
});

test("the local cache stores only a derived canonical snapshot", () => {
  const storage = memoryStorage();
  const snapshot = normalizePlayerCosmeticsSnapshot(snapshotPayload)!;
  writePlayerCosmeticsCache(storage, "user-1", snapshot);
  assert.deepEqual(readPlayerCosmeticsCache(storage, "user-1"), snapshot);
  assert.match(cosmeticCacheKey("user-1"), /:v1:user-1$/);
});

test("preview composition cannot change score, position or facets", () => {
  const sporting = { facets: [{ key: "pace", value: 78 }], position: "MC", score: 78 };
  const before = playerCosmeticSportingChecksum(sporting);
  const decorated = withCosmeticKey(EMPTY_PLAYER_COSMETIC_LOADOUT, "effect", "player.effect.iq_scan");
  assert.equal(playerCosmeticSportingChecksum(sporting), before);
  assert.equal(decorated.effectKey, "player.effect.iq_scan");
  assert.ok(!playerCosmeticLoadoutsEqual(decorated, EMPTY_PLAYER_COSMETIC_LOADOUT));
});

test("public snapshots expose equipped pieces but not private inventory fields", () => {
  const snapshot = normalizePublicPlayerCosmeticsSnapshot({
    enabled: true,
    equipped: [{ key: "player.effect.iq_scan", name: "IQ Scan", slot: "effect", render: { effect: "scan" } }],
    featuredBadge: { achievementKey: "player.poker", grantId: "grant-2", rarity: "epic", title: "Póker" },
    loadout: { ...EMPTY_PLAYER_COSMETIC_LOADOUT, effectKey: "player.effect.iq_scan" },
    playerProfileId: "profile-2",
    revision: 2,
    serverSequence: 9,
  });
  assert.ok(snapshot);
  assert.equal(snapshot.equipped[0]?.sourceBoxId, null);
  assert.equal(snapshot.equipped[0]?.seenAt, null);
  assert.equal(snapshot.featuredBadge?.title, "Póker");
});

test("Synthetic World grants, deduplicates, sees and equips cosmetics without touching ratings", () => {
  const initial = createSyntheticWorld({ mode: "ephemeral", seed: 202608101 });
  const ratings = new Map(initial.state.agents.map(({ facets, id, ratingV2 }) => [id, JSON.stringify({ facets, ratingV2 })]));
  const world = advanceSyntheticWorld(initial, { targetDate: "2026-12-31T00:00:00.000Z" });
  const summary = syntheticWorldSummary(world);
  assert.ok(summary.cosmeticInventory > 0);
  assert.ok(summary.cosmeticLoadouts > 0);
  assert.ok(summary.cosmeticDuplicates > 0);
  assert.ok(world.state.events.some(({ flow }) => flow === "cosmetic.inventory_grant"));
  assert.ok(world.state.events.some(({ flow }) => flow === "cosmetic.mark_seen"));
  assert.ok(world.state.events.some(({ flow }) => flow === "cosmetic.equip_from_box"));
  assert.equal(dailyInvariantChecks(world).filter(({ pass }) => !pass).length, 0);
  assert.equal(weeklyInvariantChecks(world).filter(({ pass }) => !pass).length, 0);
  assert.ok(world.state.agents.every((agent) => ratings.get(agent.id) === JSON.stringify({ facets: agent.facets, ratingV2: agent.ratingV2 })));
});
