import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.TEAM_COSMETIC_REWARDS_STAGING_URL;
const publishableKey = process.env.TEAM_COSMETIC_REWARDS_STAGING_PUBLISHABLE_KEY;
const groups = JSON.parse(process.env.TEAM_COSMETIC_REWARDS_STAGING_GROUPS || "{}");
const actors = Object.fromEntries(
  ["OWNER", "ADMIN", "LATE_ADMIN", "MEMBER", "OUTSIDER"].map((role) => [role, {
    email: process.env[`TEAM_COSMETIC_REWARDS_STAGING_${role}_EMAIL`],
    password: process.env[`TEAM_COSMETIC_REWARDS_STAGING_${role}_PASSWORD`],
  }]),
);

const stories = [
  ["firstWin", "team.external.wins.001", "team.shield.border.copper"],
  ["tenChallenges", "team.external.matches.010", "team.shield.ornament.banner"],
  ["twentyFiveMatches", "team.matches.025", "team.shield.ornament.laurels"],
  ["fiftyMatches", "team.matches.050", "team.shield.border.silver"],
  ["firstCleanSheet", "team.external.clean_sheets.001", "team.shield.effect.edge_glow"],
];

for (const [name, value] of Object.entries({
  TEAM_COSMETIC_REWARDS_STAGING_GROUPS: process.env.TEAM_COSMETIC_REWARDS_STAGING_GROUPS,
  TEAM_COSMETIC_REWARDS_STAGING_PUBLISHABLE_KEY: publishableKey,
  TEAM_COSMETIC_REWARDS_STAGING_URL: url,
})) if (!value) throw new Error(`${name} is required`);
for (const [story] of stories) {
  if (!groups[story]) throw new Error(`Missing staging group for ${story}`);
}
for (const [role, credentials] of Object.entries(actors)) {
  if (!credentials.email || !credentials.password) throw new Error(`Staging credentials required for ${role}`);
}

const metadata = {
  clientVersion: "2.0.0+team-cosmetic-rewards-staging",
  displayMode: "browser",
  serviceWorkerVersion: "team-cosmetic-rewards-staging",
  surface: "team-identity",
};

function client() {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(credentials) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword(credentials);
  if (error) throw error;
  assert.ok(data.user?.id);
  return { supabase, userId: data.user.id };
}

async function rpc(supabase, name, args = {}) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

const snapshot = (supabase, groupId) => rpc(
  supabase,
  "get_pachanga_team_shield_snapshot_v1",
  { target_group_id: groupId },
);

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Realtime subscription timed out")), 15_000);
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

function waitForEvent(register, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} timed out`)), 60_000);
    register((payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

const sessions = Object.fromEntries(await Promise.all(
  Object.entries(actors).map(async ([role, credentials]) => [role, await signIn(credentials)]),
));
const owner = sessions.OWNER.supabase;
const admin = sessions.ADMIN.supabase;
const lateAdmin = sessions.LATE_ADMIN.supabase;
const member = sessions.MEMBER.supabase;
const outsider = sessions.OUTSIDER.supabase;
const firstWinGroupId = groups.firstWin;

const publicBeforeGrant = await rpc(outsider, "get_pachanga_team_public_shield_v1", {
  target_group_id: firstWinGroupId,
});

let inventoryResolve;
const inventoryEvent = waitForEvent((resolve) => { inventoryResolve = resolve; }, "Realtime reward inventory event");
const inventoryChannel = admin
  .channel(`team-cosmetic-reward-inventory-${randomUUID()}`)
  .on("postgres_changes", {
    event: "INSERT",
    filter: `group_id=eq.${firstWinGroupId}`,
    schema: "public",
    table: "pachanga_team_cosmetic_inventory",
  }, (payload) => inventoryResolve?.(payload));
await waitForSubscription(inventoryChannel);
await new Promise((resolve) => setTimeout(resolve, 2_000));
process.stdout.write("TEAM_COSMETIC_REWARD_STAGING_READY\n");

const receivedInventoryEvent = await inventoryEvent;
assert.equal(receivedInventoryEvent.new.cosmetic_key, "team.shield.border.copper");

for (const [story, achievementKey, cosmeticKey] of stories) {
  const groupId = groups[story];
  const ownerSnapshot = await snapshot(owner, groupId);
  const adminSnapshot = await snapshot(admin, groupId);
  assert.equal(ownerSnapshot.teamCosmeticsEnabled, true);
  assert.equal(ownerSnapshot.teamCosmeticRewardsEnabled, true);
  assert.equal(ownerSnapshot.catalog.find((item) => item.key === cosmeticKey)?.seenAt, null);
  assert.ok(ownerSnapshot.catalog.find((item) => item.key === cosmeticKey)?.acquiredAt);
  assert.equal(adminSnapshot.catalog.find((item) => item.key === cosmeticKey)?.seenAt, null);

  const notifications = await owner
    .from("pachanga_user_notifications")
    .select("kind,payload,dedupe_key")
    .eq("kind", "team_cosmetic_reward")
    .eq("payload->>groupId", groupId)
    .eq("payload->>cosmeticKey", cosmeticKey);
  if (notifications.error) throw notifications.error;
  assert.equal(notifications.data.length, 1);

  const publicShield = await rpc(outsider, "get_pachanga_team_public_shield_v1", {
    target_group_id: groupId,
  });
  assert.equal("catalog" in publicShield, false);
  assert.equal("inventory" in publicShield, false);
  assert.ok(achievementKey);
}

const publicAfterGrant = await rpc(outsider, "get_pachanga_team_public_shield_v1", {
  target_group_id: firstWinGroupId,
});
assert.deepEqual(publicAfterGrant.config, publicBeforeGrant.config);

const ownerBeforeSeen = await snapshot(owner, firstWinGroupId);
await rpc(owner, "mark_pachanga_team_cosmetics_seen_v1", {
  client_metadata: metadata,
  expected_revision: ownerBeforeSeen.seenRevision,
  operation_id: randomUUID(),
  target_cosmetic_keys: ["team.shield.border.copper"],
  target_group_id: firstWinGroupId,
});
assert.equal(
  (await snapshot(admin, firstWinGroupId)).catalog.find(
    (item) => item.key === "team.shield.border.copper",
  )?.seenAt,
  null,
);

assert.equal((await snapshot(lateAdmin, firstWinGroupId)).unseenCount, 0);

const memberSnapshot = await snapshot(member, firstWinGroupId);
assert.equal(memberSnapshot.canManage, false);
assert.ok(memberSnapshot.catalog.every((item) => item.acquiredAt === null && item.serverSequence === 0));
const memberInventory = await member
  .from("pachanga_team_cosmetic_inventory")
  .select("cosmetic_key")
  .eq("group_id", firstWinGroupId);
if (memberInventory.error) throw memberInventory.error;
assert.equal(memberInventory.data.length, 0);
const outsiderSnapshot = await outsider.rpc("get_pachanga_team_shield_snapshot_v1", {
  target_group_id: firstWinGroupId,
});
assert.ok(outsiderSnapshot.error);

let shieldResolve;
const shieldEvent = waitForEvent((resolve) => { shieldResolve = resolve; }, "Realtime shield loadout event");
const shieldChannel = admin
  .channel(`team-cosmetic-reward-loadout-${randomUUID()}`)
  .on("postgres_changes", {
    event: "UPDATE",
    filter: `group_id=eq.${firstWinGroupId}`,
    schema: "public",
    table: "pachanga_team_shield_state",
  }, (payload) => shieldResolve?.(payload));
await waitForSubscription(shieldChannel);
await new Promise((resolve) => setTimeout(resolve, 2_000));

const beforeEquip = await snapshot(owner, firstWinGroupId);
const equipped = await rpc(owner, "save_pachanga_team_shield_loadout_v1", {
  client_metadata: metadata,
  expected_revision: beforeEquip.revision,
  operation_id: randomUUID(),
  target_config: { ...beforeEquip.config, borderKey: "team.shield.border.copper" },
  target_group_id: firstWinGroupId,
});
assert.equal(equipped.config.borderKey, "team.shield.border.copper");
await shieldEvent;
assert.equal((await snapshot(admin, firstWinGroupId)).config.borderKey, "team.shield.border.copper");
assert.equal(
  (await rpc(outsider, "get_pachanga_team_public_shield_v1", {
    target_group_id: firstWinGroupId,
  })).config.borderKey,
  "team.shield.border.copper",
);

await admin.removeChannel(inventoryChannel);
await admin.removeChannel(shieldChannel);
await Promise.all(Object.values(sessions).map(({ supabase }) => supabase.auth.signOut({ scope: "local" })));
await Promise.all(Object.values(sessions).map(({ supabase }) => supabase.removeAllChannels()));
Object.values(sessions).forEach(({ supabase }) => supabase.realtime.disconnect());

console.log(JSON.stringify({
  fiveCanonicalStories: true,
  lateAdminHistoricalNew: 0,
  notifications: true,
  publicShieldChangedOnlyAfterEquip: true,
  realtimeInventory: true,
  realtimeLoadout: true,
  rls: true,
  seenPerAdmin: true,
}));
