import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.PLAYER_COSMETICS_STAGING_URL;
const publishableKey = process.env.PLAYER_COSMETICS_STAGING_PUBLISHABLE_KEY;
const userAEmail = process.env.PLAYER_COSMETICS_STAGING_USER_A_EMAIL;
const userAPassword = process.env.PLAYER_COSMETICS_STAGING_USER_A_PASSWORD;
const userBEmail = process.env.PLAYER_COSMETICS_STAGING_USER_B_EMAIL;
const userBPassword = process.env.PLAYER_COSMETICS_STAGING_USER_B_PASSWORD;
const outsiderEmail = process.env.PLAYER_COSMETICS_STAGING_OUTSIDER_EMAIL;
const outsiderPassword = process.env.PLAYER_COSMETICS_STAGING_OUTSIDER_PASSWORD;

const required = {
  PLAYER_COSMETICS_STAGING_OUTSIDER_EMAIL: outsiderEmail,
  PLAYER_COSMETICS_STAGING_OUTSIDER_PASSWORD: outsiderPassword,
  PLAYER_COSMETICS_STAGING_PUBLISHABLE_KEY: publishableKey,
  PLAYER_COSMETICS_STAGING_URL: url,
  PLAYER_COSMETICS_STAGING_USER_A_EMAIL: userAEmail,
  PLAYER_COSMETICS_STAGING_USER_A_PASSWORD: userAPassword,
  PLAYER_COSMETICS_STAGING_USER_B_EMAIL: userBEmail,
  PLAYER_COSMETICS_STAGING_USER_B_PASSWORD: userBPassword,
};

for (const [name, value] of Object.entries(required)) {
  if (!value) throw new Error(`${name} is required`);
}

const ids = {
  badgeA: "d4600000-0000-0000-0000-000000000001",
  badgeB: "d4600000-0000-0000-0000-000000000004",
  boxDuplicate: "d4900000-0000-0000-0000-000000000003",
  boxEquipNow: "d4900000-0000-0000-0000-000000000002",
  boxNew: "d4900000-0000-0000-0000-000000000001",
  profileA: "d4300000-0000-0000-0000-000000000001",
  profileB: "d4300000-0000-0000-0000-000000000002",
};

const metadata = {
  clientVersion: "2.0.0+staging-rc",
  device: "synthetic-staging-client",
  displayMode: "browser",
  serviceWorkerVersion: "staging-rc",
};

function client() {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(email, password) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  assert.ok(data.user?.id);
  return supabase;
}

async function rpc(supabase, name, args = {}) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

async function cosmetics(supabase) {
  return rpc(supabase, "get_pachanga_player_cosmetics_snapshot_v1");
}

async function sportingChecksum(supabase, profileId) {
  const { data, error } = await supabase
    .from("pachanga_player_profiles")
    .select("rating,base_overall,calibrated_overall,current_overall,base_facets,calibrated_facets,current_facets,rating_reliability,rating_engine_version")
    .eq("id", profileId)
    .single();
  if (error) throw error;
  return JSON.stringify(data);
}

function owned(snapshot, key) {
  return snapshot.owned.find((item) => item.key === key);
}

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Realtime subscription timed out")), 10_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timer);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timer);
        reject(new Error(`Realtime subscription failed: ${status}`));
      }
    });
  });
}

function waitForRealtimeEvent(register) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Realtime event timed out")), 10_000);
    register((payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

const aDesktop = await signIn(userAEmail, userAPassword);
const aMobile = await signIn(userAEmail, userAPassword);
const bClient = await signIn(userBEmail, userBPassword);
const outsider = await signIn(outsiderEmail, outsiderPassword);

const sportingBefore = await sportingChecksum(aDesktop, ids.profileA);
const initialA = await cosmetics(aDesktop);
assert.equal(initialA.enabled, true);
assert.equal(initialA.owned.length, 0);

const openedNew = await rpc(aDesktop, "open_pachanga_reward_box_v2", {
  client_metadata: metadata,
  expected_revision: 1,
  operation_id: randomUUID(),
  target_box_id: ids.boxNew,
});
assert.equal(openedNew.rewardPayload.grant.cosmeticGranted, true);
assert.equal(openedNew.rewardPayload.grant.cosmeticKey, "player.frame.barrio.copper");
assert.equal(openedNew.rewardPayload.grant.pointsGranted, 0);

const afterNew = await cosmetics(aDesktop);
assert.equal(owned(afterNew, "player.frame.barrio.copper")?.seenAt, null);

await aDesktop.auth.signOut({ scope: "local" });
const persistedOnOtherDevice = await cosmetics(aMobile);
assert.equal(owned(persistedOnOtherDevice, "player.frame.barrio.copper")?.seenAt, null);

const notificationRead = await aMobile
  .from("pachanga_user_notifications")
  .select("kind,read_at")
  .eq("kind", "player_reward_cosmetic_unlocked");
if (notificationRead.error) throw notificationRead.error;
assert.equal(notificationRead.data.length, 1);

let realtimeResolver;
const seenRealtime = waitForRealtimeEvent((resolve) => {
  realtimeResolver = resolve;
});
const realtimeChannel = aMobile
  .channel(`cosmetics-staging-${randomUUID()}`)
  .on(
    "postgres_changes",
    {
      event: "UPDATE",
      filter: `player_profile_id=eq.${ids.profileA}`,
      schema: "public",
      table: "pachanga_player_reward_inventory",
    },
    (payload) => realtimeResolver?.(payload),
  );
await waitForSubscription(realtimeChannel);
await new Promise((resolve) => setTimeout(resolve, 1_500));

const seenResult = await rpc(aMobile, "mark_pachanga_player_cosmetics_seen_v1", {
  client_metadata: metadata,
  expected_revision: persistedOnOtherDevice.revision,
  operation_id: randomUUID(),
  target_cosmetic_keys: ["player.frame.barrio.copper"],
});
assert.equal(seenResult.markedSeen, 1);
await seenRealtime;
const afterSeenOnSecondClient = await cosmetics(aMobile);
assert.ok(owned(afterSeenOnSecondClient, "player.frame.barrio.copper")?.seenAt);

const savedFrame = await rpc(aMobile, "save_pachanga_player_cosmetic_loadout_v1", {
  client_metadata: metadata,
  expected_revision: afterSeenOnSecondClient.revision,
  operation_id: randomUUID(),
  target_loadout: { frameKey: "player.frame.barrio.copper" },
});
assert.equal(savedFrame.loadout.frameKey, "player.frame.barrio.copper");

const publicAfterSave = await rpc(bClient, "get_pachanga_public_player_card_cosmetics_v1", {
  target_player_profile_id: ids.profileA,
});
assert.equal(publicAfterSave.loadout.frameKey, "player.frame.barrio.copper");
assert.equal("owned" in publicAfterSave, false);

const openedEquipNow = await rpc(aMobile, "open_pachanga_reward_box_v2", {
  client_metadata: metadata,
  expected_revision: 1,
  operation_id: randomUUID(),
  target_box_id: ids.boxEquipNow,
});
assert.equal(openedEquipNow.rewardPayload.grant.cosmeticGranted, true);
const beforeEquipNow = await cosmetics(aMobile);
const equippedNow = await rpc(aMobile, "equip_pachanga_player_cosmetic_from_box_v1", {
  client_metadata: metadata,
  expected_revision: beforeEquipNow.revision,
  operation_id: randomUUID(),
  target_box_id: ids.boxEquipNow,
  target_cosmetic_key: "player.background.asphalt_night",
});
assert.equal(equippedNow.loadout.backgroundKey, "player.background.asphalt_night");
assert.ok(owned(equippedNow, "player.background.asphalt_night")?.seenAt);

const pointsBefore = await aMobile
  .from("pachanga_player_point_accounts")
  .select("balance")
  .eq("player_profile_id", ids.profileA)
  .maybeSingle();
if (pointsBefore.error) throw pointsBefore.error;
const openedDuplicate = await rpc(aMobile, "open_pachanga_reward_box_v2", {
  client_metadata: metadata,
  expected_revision: 1,
  operation_id: randomUUID(),
  target_box_id: ids.boxDuplicate,
});
assert.equal(openedDuplicate.rewardPayload.grant.cosmeticGranted, false);
assert.equal(openedDuplicate.rewardPayload.grant.duplicateConverted, true);
assert.equal(openedDuplicate.rewardPayload.grant.duplicateConversionPoints, 8);

const afterDuplicate = await cosmetics(aMobile);
assert.equal(afterDuplicate.owned.filter(({ key }) => key === "player.frame.barrio.copper").length, 1);
assert.equal(afterDuplicate.owned.filter(({ seenAt }) => !seenAt).length, 0);
const pointsAfter = await aMobile
  .from("pachanga_player_point_accounts")
  .select("balance")
  .eq("player_profile_id", ids.profileA)
  .single();
if (pointsAfter.error) throw pointsAfter.error;
assert.equal(pointsAfter.data.balance - (pointsBefore.data?.balance ?? 0), 8);
const notificationsAfterDuplicate = await aMobile
  .from("pachanga_user_notifications")
  .select("id", { count: "exact" })
  .eq("kind", "player_reward_cosmetic_unlocked");
if (notificationsAfterDuplicate.error) throw notificationsAfterDuplicate.error;
assert.equal(notificationsAfterDuplicate.count, 2);

const withEarnedBadge = await rpc(aMobile, "save_pachanga_player_cosmetic_loadout_v1", {
  client_metadata: metadata,
  expected_revision: afterDuplicate.revision,
  operation_id: randomUUID(),
  target_loadout: {
    backgroundKey: "player.background.asphalt_night",
    featuredBadgeGrantId: ids.badgeA,
    frameKey: "player.frame.barrio.copper",
  },
});
assert.equal(withEarnedBadge.loadout.featuredBadgeGrantId, ids.badgeA);

const rejectedBadge = await aMobile.rpc("save_pachanga_player_cosmetic_loadout_v1", {
  client_metadata: metadata,
  expected_revision: withEarnedBadge.revision,
  operation_id: randomUUID(),
  target_loadout: {
    backgroundKey: "player.background.asphalt_night",
    featuredBadgeGrantId: ids.badgeB,
    frameKey: "player.frame.barrio.copper",
  },
});
assert.ok(rejectedBadge.error);
assert.match(rejectedBadge.error.message, /not earned/i);

const concurrencyBase = await cosmetics(aMobile);
const aConcurrent = await signIn(userAEmail, userAPassword);
const concurrency = await Promise.all([
  aMobile.rpc("save_pachanga_player_cosmetic_loadout_v1", {
    client_metadata: { ...metadata, device: "staging-device-a" },
    expected_revision: concurrencyBase.revision,
    operation_id: randomUUID(),
    target_loadout: {
      featuredBadgeGrantId: ids.badgeA,
      frameKey: "player.frame.barrio.copper",
    },
  }),
  aConcurrent.rpc("save_pachanga_player_cosmetic_loadout_v1", {
    client_metadata: { ...metadata, device: "staging-device-b" },
    expected_revision: concurrencyBase.revision,
    operation_id: randomUUID(),
    target_loadout: {
      backgroundKey: "player.background.asphalt_night",
      featuredBadgeGrantId: ids.badgeA,
    },
  }),
]);
assert.equal(concurrency.filter(({ error }) => !error).length, 1);
assert.equal(concurrency.filter(({ error }) => error?.code === "PT409").length, 1);

const bSnapshot = await cosmetics(bClient);
const bSaved = await rpc(bClient, "save_pachanga_player_cosmetic_loadout_v1", {
  client_metadata: metadata,
  expected_revision: bSnapshot.revision,
  operation_id: randomUUID(),
  target_loadout: {
    accentKey: "player.accent.navy",
    featuredBadgeGrantId: ids.badgeB,
  },
});
assert.equal(bSaved.loadout.accentKey, "player.accent.navy");

const privateInventoryB = await aMobile
  .from("pachanga_player_reward_inventory")
  .select("reward_key")
  .eq("player_profile_id", ids.profileB);
if (privateInventoryB.error) throw privateInventoryB.error;
assert.equal(privateInventoryB.data.length, 0);

const directInventoryWrite = await aMobile
  .from("pachanga_player_reward_inventory")
  .update({ seen_at: new Date().toISOString() })
  .eq("player_profile_id", ids.profileB);
assert.ok(directInventoryWrite.error);

const directLoadoutWrite = await aMobile
  .from("pachanga_player_cosmetic_loadouts")
  .update({ accent_key: null })
  .eq("player_profile_id", ids.profileB);
assert.ok(directLoadoutWrite.error);

const privatePointsB = await aMobile
  .from("pachanga_player_point_accounts")
  .select("balance")
  .eq("player_profile_id", ids.profileB);
if (privatePointsB.error) throw privatePointsB.error;
assert.equal(privatePointsB.data.length, 0);

const publicB = await rpc(aMobile, "get_pachanga_public_player_card_cosmetics_v1", {
  target_player_profile_id: ids.profileB,
});
assert.equal(publicB.loadout.accentKey, "player.accent.navy");
assert.equal("owned" in publicB, false);

const outsiderOpen = await outsider.rpc("open_pachanga_reward_box_v2", {
  client_metadata: metadata,
  expected_revision: 1,
  operation_id: randomUUID(),
  target_box_id: ids.boxNew,
});
assert.ok(outsiderOpen.error);

const sportingAfter = await sportingChecksum(aMobile, ids.profileA);
assert.equal(sportingAfter, sportingBefore);

await aMobile.removeChannel(realtimeChannel);
await Promise.all([
  aMobile.auth.signOut({ scope: "local" }),
  aConcurrent.auth.signOut({ scope: "local" }),
  bClient.auth.signOut({ scope: "local" }),
  outsider.auth.signOut({ scope: "local" }),
]);
await Promise.all([
  aDesktop.removeAllChannels(),
  aMobile.removeAllChannels(),
  aConcurrent.removeAllChannels(),
  bClient.removeAllChannels(),
  outsider.removeAllChannels(),
]);
[aDesktop, aMobile, aConcurrent, bClient, outsider].forEach((supabase) => {
  supabase.realtime.disconnect();
});

console.log(JSON.stringify({
  badgeEarned: true,
  badgeUnearnedRejected: true,
  concurrency: { conflict: true, winnerCount: 1 },
  duplicate: { inventoryRows: 1, newArtificial: false, points: 8 },
  equipNow: { equipped: true, owned: true, seen: true },
  multideviceNew: true,
  notificationCount: notificationsAfterDuplicate.count,
  publicCardsSafe: true,
  ratingChecksumStable: true,
  realtimeSeenConverged: true,
  rlsAdversarial: true,
}));
