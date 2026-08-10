import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.TEAM_SHIELD_STAGING_URL;
const publishableKey = process.env.TEAM_SHIELD_STAGING_PUBLISHABLE_KEY;
const groupId = process.env.TEAM_SHIELD_STAGING_GROUP_ID;

const actors = Object.fromEntries(
  ["OWNER", "ADMIN_A", "ADMIN_B", "LATE_ADMIN", "MEMBER", "OUTSIDER"].map((role) => [role, {
    email: process.env[`TEAM_SHIELD_STAGING_${role}_EMAIL`],
    password: process.env[`TEAM_SHIELD_STAGING_${role}_PASSWORD`],
  }]),
);

for (const [name, value] of Object.entries({
  TEAM_SHIELD_STAGING_GROUP_ID: groupId,
  TEAM_SHIELD_STAGING_PUBLISHABLE_KEY: publishableKey,
  TEAM_SHIELD_STAGING_URL: url,
})) if (!value) throw new Error(`${name} is required`);
for (const [role, credentials] of Object.entries(actors)) {
  if (!credentials.email || !credentials.password) throw new Error(`Staging credentials required for ${role}`);
}

const metadata = {
  clientVersion: "2.0.0+team-shield-staging",
  device: "synthetic-staging-client",
  displayMode: "browser",
  serviceWorkerVersion: "team-shield-staging",
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

async function snapshot(supabase) {
  return rpc(supabase, "get_pachanga_team_shield_snapshot_v1", { target_group_id: groupId });
}

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Realtime subscription timed out")), 12_000);
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

function waitForRealtime(register) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Realtime shield event timed out")), 12_000);
    register((payload) => {
      clearTimeout(timer);
      resolve(payload);
    });
  });
}

function config(initials, shapeKey, borderKey = "team.shield.border.copper") {
  return {
    backgroundKey: "team.shield.background.duotone",
    borderKey,
    bottomOrnamentKey: null,
    effectKey: null,
    foundationYear: "2026",
    initials,
    patternKey: "team.shield.pattern.diagonal",
    primaryColorKey: "team.shield.color.midnight",
    primarySymbolKey: "team.shield.symbol.ball_iq",
    primarySymbolRotation: 0,
    primarySymbolScale: 1,
    schemaVersion: 1,
    secondaryColorKey: "team.shield.color.cyan",
    secondarySymbolKey: null,
    shapeKey,
    sideOrnamentKey: null,
    topOrnamentKey: null,
  };
}

const sessions = Object.fromEntries(await Promise.all(
  Object.entries(actors).map(async ([role, credentials]) => [role, await signIn(credentials)]),
));
const owner = sessions.OWNER.supabase;
const adminA = sessions.ADMIN_A.supabase;
const adminB = sessions.ADMIN_B.supabase;
const lateAdmin = sessions.LATE_ADMIN.supabase;
const member = sessions.MEMBER.supabase;
const outsider = sessions.OUTSIDER.supabase;

const groupBefore = await owner.from("pachanga_groups").select("payload,payload_revision,name").eq("id", groupId).single();
if (groupBefore.error) throw groupBefore.error;
const sportingBefore = JSON.stringify(groupBefore.data.payload);

const ownerInitial = await snapshot(owner);
const adminAInitial = await snapshot(adminA);
const adminBInitial = await snapshot(adminB);
const memberInitial = await snapshot(member);
assert.equal(ownerInitial.teamCosmeticsEnabled, true);
assert.equal(ownerInitial.teamCosmeticRewardsEnabled, false);
assert.equal(ownerInitial.unseenCount, 1);
assert.equal(adminAInitial.unseenCount, 1);
assert.equal(adminBInitial.unseenCount, 1);
assert.equal(memberInitial.canManage, false);
assert.equal(memberInitial.history.length, 0);
assert.ok(memberInitial.catalog.every((item) => item.acquiredAt === null && item.serverSequence === 0));

const outsiderPrivate = await outsider.rpc("get_pachanga_team_shield_snapshot_v1", { target_group_id: groupId });
assert.ok(outsiderPrivate.error);
const outsiderPublic = await rpc(outsider, "get_pachanga_team_public_shield_v1", { target_group_id: groupId });
assert.equal("catalog" in outsiderPublic, false);
assert.equal("inventory" in outsiderPublic, false);

const seen = await rpc(owner, "mark_pachanga_team_cosmetics_seen_v1", {
  client_metadata: metadata,
  expected_revision: ownerInitial.seenRevision,
  operation_id: randomUUID(),
  target_cosmetic_keys: ["team.shield.border.copper"],
  target_group_id: groupId,
});
assert.equal(seen.unseenCount, 0);
assert.equal((await snapshot(adminA)).unseenCount, 1);

await rpc(owner, "set_pachanga_member_role", {
  next_role: "admin",
  operation_key: randomUUID(),
  target_group_id: groupId,
  target_user_id: sessions.LATE_ADMIN.userId,
});
const lateAfterPromotion = await snapshot(lateAdmin);
assert.equal(lateAfterPromotion.canManage, true);
assert.equal(lateAfterPromotion.unseenCount, 0);

let realtimeResolve;
const realtimeEvent = waitForRealtime((resolve) => { realtimeResolve = resolve; });
const channel = adminA
  .channel(`team-shield-staging-${randomUUID()}`)
  .on("postgres_changes", {
    event: "UPDATE",
    filter: `group_id=eq.${groupId}`,
    schema: "public",
    table: "pachanga_team_shield_state",
  }, (payload) => realtimeResolve?.(payload));
await waitForSubscription(channel);
await new Promise((resolve) => setTimeout(resolve, 800));

const saved = await rpc(owner, "save_pachanga_team_shield_loadout_v1", {
  client_metadata: metadata,
  expected_revision: ownerInitial.revision,
  operation_id: randomUUID(),
  target_config: config("STG", "team.shield.shape.hex_iq"),
  target_group_id: groupId,
});
assert.equal(saved.confirmedRevision, ownerInitial.revision + 1);
await realtimeEvent;
const adminAfterRealtime = await snapshot(adminA);
assert.equal(adminAfterRealtime.revision, saved.confirmedRevision);
assert.equal(adminAfterRealtime.config.initials, "STG");

const concurrentOperationA = randomUUID();
const concurrentOperationB = randomUUID();
const concurrent = await Promise.all([
  owner.rpc("save_pachanga_team_shield_loadout_v1", {
    client_metadata: { ...metadata, device: "staging-owner" },
    expected_revision: saved.confirmedRevision,
    operation_id: concurrentOperationA,
    target_config: config("OWR", "team.shield.shape.classic_iq"),
    target_group_id: groupId,
  }),
  adminA.rpc("save_pachanga_team_shield_loadout_v1", {
    client_metadata: { ...metadata, device: "staging-admin" },
    expected_revision: saved.confirmedRevision,
    operation_id: concurrentOperationB,
    target_config: config("ADM", "team.shield.shape.barrio"),
    target_group_id: groupId,
  }),
]);
assert.equal(concurrent.filter(({ error }) => !error).length, 1);
assert.equal(concurrent.filter(({ error }) => error?.code === "PT409").length, 1);
const canonicalAfterRace = await snapshot(owner);
assert.equal(canonicalAfterRace.revision, saved.confirmedRevision + 1);

await rpc(owner, "set_pachanga_member_role", {
  next_role: "player",
  operation_key: randomUUID(),
  target_group_id: groupId,
  target_user_id: sessions.ADMIN_B.userId,
});
const removedAdmin = await snapshot(adminB);
assert.equal(removedAdmin.canManage, false);
const removedAdminSave = await adminB.rpc("save_pachanga_team_shield_loadout_v1", {
  client_metadata: metadata,
  expected_revision: canonicalAfterRace.revision,
  operation_id: randomUUID(),
  target_config: config("BAD", "team.shield.shape.round"),
  target_group_id: groupId,
});
assert.ok(removedAdminSave.error);

const memberInventory = await member.from("pachanga_team_cosmetic_inventory").select("cosmetic_key").eq("group_id", groupId);
if (memberInventory.error) throw memberInventory.error;
assert.equal(memberInventory.data.length, 0);
const memberDirectWrite = await member.from("pachanga_team_shield_loadouts").update({ config: config("BAD", "team.shield.shape.round") }).eq("group_id", groupId);
assert.ok(memberDirectWrite.error);

const groupRevision = await owner.from("pachanga_groups").select("payload_revision").eq("id", groupId).single();
if (groupRevision.error) throw groupRevision.error;
await rpc(owner, "transfer_pachanga_group_ownership_authoritative_v1", {
  client_metadata: metadata,
  expected_revision: groupRevision.data.payload_revision,
  operation_id: randomUUID(),
  target_group_id: groupId,
  target_user_id: sessions.ADMIN_A.userId,
});
const oldOwnerAfterTransfer = await snapshot(owner);
const newOwnerAfterTransfer = await snapshot(adminA);
assert.equal(oldOwnerAfterTransfer.canManage, true);
assert.equal(newOwnerAfterTransfer.canManage, true);
assert.deepEqual(newOwnerAfterTransfer.config, canonicalAfterRace.config);

const groupAfter = await adminA.from("pachanga_groups").select("payload").eq("id", groupId).single();
if (groupAfter.error) throw groupAfter.error;
assert.equal(JSON.stringify(groupAfter.data.payload), sportingBefore);

await adminA.removeChannel(channel);
await Promise.all(Object.values(sessions).map(({ supabase }) => supabase.auth.signOut({ scope: "local" })));
await Promise.all(Object.values(sessions).map(({ supabase }) => supabase.removeAllChannels()));
Object.values(sessions).forEach(({ supabase }) => supabase.realtime.disconnect());

console.log(JSON.stringify({
  adminRemoval: true,
  concurrency: { conflict: true, winnerCount: 1 },
  lateAdminHistoricalNew: 0,
  memberInventoryPrivate: true,
  ownerTransferPreservedLoadout: true,
  publicReadModelSafe: true,
  ratingAndSportingPayloadStable: true,
  realtimeConverged: true,
  seenPerAdmin: true,
}));
