import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.TEAM_SHIELD_STAGING_URL;
const publishableKey = process.env.TEAM_SHIELD_STAGING_PUBLISHABLE_KEY;
const serviceRoleKey = process.env.TEAM_SHIELD_STAGING_SERVICE_ROLE_KEY;
const groupId = process.env.TEAM_SHIELD_STAGING_GROUP_ID;
const pregrantedFixture = process.env.TEAM_SHIELD_STAGING_PREGRANTED === "true";
const premiumBallKey = "team.shield.symbol.ball_premium";
const actors = Object.fromEntries(
  ["OWNER", "ADMIN_A", "ADMIN_B", "MEMBER", "OUTSIDER"].map((role) => [role, {
    email: process.env[`TEAM_SHIELD_STAGING_${role}_EMAIL`],
    password: process.env[`TEAM_SHIELD_STAGING_${role}_PASSWORD`],
  }]),
);

for (const [name, value] of Object.entries({
  TEAM_SHIELD_STAGING_GROUP_ID: groupId,
  TEAM_SHIELD_STAGING_PUBLISHABLE_KEY: publishableKey,
  TEAM_SHIELD_STAGING_URL: url,
})) if (!value) throw new Error(`${name} is required`);
if (!serviceRoleKey && !pregrantedFixture) {
  throw new Error("TEAM_SHIELD_STAGING_SERVICE_ROLE_KEY or TEAM_SHIELD_STAGING_PREGRANTED=true is required");
}
for (const [role, credentials] of Object.entries(actors)) {
  if (!credentials.email || !credentials.password) throw new Error(`Staging credentials required for ${role}`);
}

const metadata = {
  clientVersion: "2.0.0+team-shield-premium-rc",
  device: "synthetic-staging-client",
  displayMode: "browser",
  serviceWorkerVersion: "team-shield-premium-rc",
};

function client(key = publishableKey) {
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(credentials) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword(credentials);
  if (error) throw error;
  assert.ok(data.user?.id);
  return supabase;
}

async function rpc(supabase, name, args = {}) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw error;
  return data;
}

const snapshot = (supabase) => rpc(supabase, "get_pachanga_team_shield_snapshot_v1", { target_group_id: groupId });

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

const sessions = Object.fromEntries(await Promise.all(
  Object.entries(actors).map(async ([role, credentials]) => [role, await signIn(credentials)]),
));
const service = serviceRoleKey ? client(serviceRoleKey) : null;
const owner = sessions.OWNER;
const adminA = sessions.ADMIN_A;
const adminB = sessions.ADMIN_B;
const member = sessions.MEMBER;
const outsider = sessions.OUTSIDER;

const groupBefore = await owner.from("pachanga_groups").select("name,payload").eq("id", groupId).single();
if (groupBefore.error) throw groupBefore.error;
assert.equal(groupBefore.data.name, "Raval FC");
const sportingBefore = JSON.stringify(groupBefore.data.payload);

if (!pregrantedFixture) {
  for (const admin of [owner, adminA, adminB]) {
    const current = await snapshot(admin);
    const unseen = current.catalog.filter((item) => item.acquiredAt && !item.seenAt).map((item) => item.key);
    if (unseen.length) {
      await rpc(admin, "mark_pachanga_team_cosmetics_seen_v1", {
        client_metadata: metadata,
        expected_revision: current.seenRevision,
        operation_id: randomUUID(),
        target_cosmetic_keys: unseen,
        target_group_id: groupId,
      });
    }
  }
}

const beforeGrant = await snapshot(owner);
if (pregrantedFixture) {
  const premium = beforeGrant.catalog.find((item) => item.key === premiumBallKey);
  assert.ok(premium?.acquiredAt);
  assert.equal(premium.seenAt, null);
} else {
  const grant = await rpc(service, "grant_pachanga_team_cosmetic_v1", {
    client_metadata: { ...metadata, device: "staging-service-fixture" },
    expected_revision: beforeGrant.revision,
    operation_id: randomUUID(),
    source_kind: "staging_fixture",
    source_metadata: { fixture: "raval-fc-premium-rc" },
    target_cosmetic_key: premiumBallKey,
    target_group_id: groupId,
  });
  assert.equal(grant.config.primarySymbolKey === premiumBallKey, false);
}

const ownerAfterGrant = await snapshot(owner);
const adminAAfterGrant = await snapshot(adminA);
const adminBAfterGrant = await snapshot(adminB);
assert.equal(ownerAfterGrant.catalog.find((item) => item.key === premiumBallKey)?.seenAt, null);
assert.equal(adminAAfterGrant.catalog.find((item) => item.key === premiumBallKey)?.seenAt, null);
assert.equal(adminBAfterGrant.catalog.find((item) => item.key === premiumBallKey)?.seenAt, null);

await rpc(owner, "mark_pachanga_team_cosmetics_seen_v1", {
  client_metadata: metadata,
  expected_revision: ownerAfterGrant.seenRevision,
  operation_id: randomUUID(),
  target_cosmetic_keys: [premiumBallKey],
  target_group_id: groupId,
});
assert.ok((await snapshot(adminB)).catalog.find((item) => item.key === premiumBallKey)?.seenAt === null);

let realtimeResolve;
const realtimeEvent = new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error("Premium loadout Realtime event timed out")), 12_000);
  realtimeResolve = (payload) => {
    clearTimeout(timer);
    resolve(payload);
  };
});
const channel = adminB
  .channel(`team-shield-premium-rc-${randomUUID()}`)
  .on("postgres_changes", {
    event: "UPDATE",
    filter: `group_id=eq.${groupId}`,
    schema: "public",
    table: "pachanga_team_shield_state",
  }, (payload) => realtimeResolve?.(payload));
await waitForSubscription(channel);
// A dormant preview branch may report SUBSCRIBED just before its replication
// stream finishes warming. Wait briefly before committing the observed write.
await new Promise((resolve) => setTimeout(resolve, 2_500));

const canonicalBeforeEquip = await snapshot(owner);
const equipped = await rpc(owner, "save_pachanga_team_shield_loadout_v1", {
  client_metadata: metadata,
  expected_revision: canonicalBeforeEquip.revision,
  operation_id: randomUUID(),
  target_config: { ...canonicalBeforeEquip.config, primarySymbolKey: premiumBallKey },
  target_group_id: groupId,
});
assert.equal(equipped.config.primarySymbolKey, premiumBallKey);
await realtimeEvent;
assert.equal((await snapshot(adminB)).config.primarySymbolKey, premiumBallKey);

const memberPrivate = await snapshot(member);
assert.equal(memberPrivate.canManage, false);
assert.ok(memberPrivate.catalog.every((item) => item.acquiredAt === null && item.serverSequence === 0));
const memberInventory = await member.from("pachanga_team_cosmetic_inventory").select("cosmetic_key").eq("group_id", groupId);
if (memberInventory.error) throw memberInventory.error;
assert.equal(memberInventory.data.length, 0);
const outsiderPublic = await rpc(outsider, "get_pachanga_team_public_shield_v1", { target_group_id: groupId });
assert.equal(outsiderPublic.config.primarySymbolKey, premiumBallKey);
assert.equal("catalog" in outsiderPublic, false);
assert.equal("inventory" in outsiderPublic, false);

const groupAfter = await owner.from("pachanga_groups").select("payload").eq("id", groupId).single();
if (groupAfter.error) throw groupAfter.error;
assert.equal(JSON.stringify(groupAfter.data.payload), sportingBefore);

await adminB.removeChannel(channel);
await Promise.all(Object.values(sessions).map((supabase) => supabase.auth.signOut({ scope: "local" })));
await Promise.all(Object.values(sessions).map((supabase) => supabase.removeAllChannels()));
Object.values(sessions).forEach((supabase) => supabase.realtime.disconnect());
service?.realtime.disconnect();

console.log(JSON.stringify({
  fixture: "Raval FC",
  newPerAdmin: true,
  premiumBallEquipped: true,
  publicReadSafe: true,
  ratingChecksumUnchanged: true,
  realtimeConverged: true,
}));
