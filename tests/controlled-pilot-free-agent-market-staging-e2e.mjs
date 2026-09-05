import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const PRODUCTION_REF = "qonbngfrnrqgmxbdfbea";
const env = {
  confirmation: process.env.FREE_AGENT_MARKET_STAGING_CONFIRM,
  databaseUrl: process.env.POSTGRES_URL,
  projectRef: process.env.FREE_AGENT_MARKET_STAGING_PROJECT_REF,
  publishableKey: process.env.SUPABASE_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  supabaseUrl: process.env.SUPABASE_URL,
};

if (
  env.confirmation !== "CONTROLLED_PILOT_FREE_AGENT_STAGING_ONLY"
  || !env.projectRef
  || env.projectRef === PRODUCTION_REF
  || !env.supabaseUrl
  || new URL(env.supabaseUrl).hostname !== `${env.projectRef}.supabase.co`
  || !env.publishableKey
  || !env.serviceRoleKey
  || env.publishableKey === env.serviceRoleKey
  || !env.databaseUrl
  || !decodeURIComponent(new URL(env.databaseUrl).username).includes(env.projectRef)
) {
  throw new Error("FREE_AGENT_MARKET_PRODUCTION_TARGET_FORBIDDEN");
}

const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `FreeAgent-${randomUUID()}-Qa!`;
const accounts = [];
const clients = [];
const channels = [];
let platformClient = null;
let initialFlags = null;
let temporaryPlatformGrant = false;

function client(key = env.publishableKey, options = {}) {
  return createClient(env.supabaseUrl, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
    ...options,
  });
}

const service = client(env.serviceRoleKey);

function metadata(surface, displayMode = "standalone") {
  return {
    clientVersion: "3.12.0+controlled-pilot",
    displayMode,
    serviceWorkerVersion: "3.12.0+controlled-pilot",
    surface,
  };
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean)
    .join(" ");
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw new Error(`${name}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

async function createAccount(label) {
  const account = {
    email: `free-agent-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const result = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "CONTROLLED_PILOT_FREE_AGENT_STAGING", runId },
  });
  if (result.error) throw result.error;
  accounts.push(account);
  return account;
}

async function signIn(account, device) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`FREE_AGENT_SIGN_IN_FAILED:${device}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  await supabase.realtime.setAuth(result.data.session.access_token);
  clients.push(supabase);
  return {
    accessToken: result.data.session.access_token,
    refreshToken: result.data.session.refresh_token,
    supabase,
  };
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runFixtureSql(sql, label) {
  const result = spawnSync("psql", ["-X", "-w", env.databaseUrl, "-v", "ON_ERROR_STOP=1", "-At"], {
    encoding: "utf8",
    input: sql,
    maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label}: ${result.stderr || "unknown"}`);
  return result.stdout.trim();
}

function grantTemporaryPlatformOwner(account) {
  runFixtureSql(`
insert into private.pachanga_platform_admin_roles(user_id, role, active, granted_by)
values (${sqlText(account.id)}::uuid, 'platform_owner', true, null)
on conflict (user_id) do update set role='platform_owner', active=true, granted_by=null, updated_at=clock_timestamp();
`, "temporary platform grant");
  temporaryPlatformGrant = true;
}

async function setProfileFlags(profileFoundationEnabled, independentWriteEnabled) {
  const current = await rpc(platformClient, "get_pachanga_social_team_feature_flags_v1");
  return rpc(platformClient, "command_pachanga_social_team_settings_v1", {
    client_metadata: metadata("controlled-pilot-flags", "browser"),
    expected_revision: current.confirmedRevision,
    operation_id: randomUUID(),
    payload: {
      socialProfileFoundationEnabled: profileFoundationEnabled,
      socialProfileIndependentWriteEnabled: independentWriteEnabled,
    },
  });
}

function profileCommand(supabase, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_social_profile_v1", {
    action: "profile.create",
    client_metadata: metadata("controlled-pilot-profile"),
    expected_revision: 0,
    operation_id: operationId,
    payload,
  });
}

function updateProfileCommand(supabase, expectedRevision, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_social_profile_v1", {
    action: "profile.update",
    client_metadata: metadata("controlled-pilot-profile"),
    expected_revision: expectedRevision,
    operation_id: operationId,
    payload,
  });
}

function marketCommand(supabase, action, expectedRevision, operationId = randomUUID(), payload = {}) {
  return supabase.rpc("command_pachanga_free_agent_market_v1", {
    action,
    client_metadata: metadata("controlled-pilot-free-agent-market"),
    expected_revision: expectedRevision,
    operation_id: operationId,
    payload,
  });
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("FREE_AGENT_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`FREE_AGENT_REALTIME_${status}`));
      }
    });
  });
}

function postgresChangesBinding(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("FREE_AGENT_POSTGRES_CHANGES_BINDING_TIMEOUT")), 20_000);
    queue.binding = (payload) => {
      if (payload?.extension !== "postgres_changes") return;
      clearTimeout(timeout);
      if (payload.status === "ok") resolve(payload);
      else reject(new Error(`FREE_AGENT_POSTGRES_CHANGES_BINDING_${String(payload.status || "ERROR").toUpperCase()}`));
    };
  });
}

function nextInvalidation(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("FREE_AGENT_REALTIME_EVENT_TIMEOUT")), 20_000);
    queue.resolve = (event) => {
      clearTimeout(timeout);
      resolve(event);
    };
  });
}

async function bestEffort(action) {
  try {
    await action();
  } catch {
    // The isolated branch is destroyed after certification; cleanup still runs best effort here.
  }
}

function cleanupSyntheticEvidence() {
  if (!accounts.length) return;
  const ids = accounts.map((account) => `${sqlText(account.id)}::uuid`).join(",");
  runFixtureSql(`
begin;
create temporary table free_agent_market_cleanup_profiles on commit drop as
select id from public.pachanga_market_profiles where user_id = any(array[${ids}]::uuid[]);
alter table public.pachanga_market_profiles disable trigger pachanga_market_profiles_invalidate_v1;
delete from public.pachanga_market_profiles where user_id = any(array[${ids}]::uuid[]);
alter table public.pachanga_market_profiles enable trigger pachanga_market_profiles_invalidate_v1;
delete from public.pachanga_market_invalidations_v1
where profile_id in (select id from free_agent_market_cleanup_profiles);
alter table private.pachanga_social_events_v1 disable trigger user;
alter table private.pachanga_social_player_profile_revisions_v1 disable trigger user;
alter table private.pachanga_social_operation_receipts_v1 disable trigger user;
delete from private.pachanga_social_events_v1 where actor_id = any(array[${ids}]::uuid[]);
delete from private.pachanga_social_player_profile_revisions_v1
where actor_id = any(array[${ids}]::uuid[]) or user_id = any(array[${ids}]::uuid[]);
delete from private.pachanga_social_operation_receipts_v1 where actor_id = any(array[${ids}]::uuid[]);
alter table private.pachanga_social_events_v1 enable trigger user;
alter table private.pachanga_social_player_profile_revisions_v1 enable trigger user;
alter table private.pachanga_social_operation_receipts_v1 enable trigger user;
commit;
`, "synthetic social evidence cleanup");
}

let completed = false;
let report;
try {
  const platform = await createAccount("platform");
  const freeAgent = await createAccount("player-c");
  const reader = await createAccount("reader");

  grantTemporaryPlatformOwner(platform);
  platformClient = (await signIn(platform, "platform")).supabase;
  initialFlags = await rpc(platformClient, "get_pachanga_social_team_feature_flags_v1");
  const enabled = await setProfileFlags(true, true);
  assert.equal(enabled.socialProfileFoundationEnabled, true);
  assert.equal(enabled.socialProfileIndependentWriteEnabled, true);

  const deviceA = await signIn(freeAgent, "player-c-device-a");
  const deviceB = await signIn(freeAgent, "player-c-device-b");
  const readerSession = await signIn(reader, "reader");

  const profilePayload = {
    approximateTime: "20:00-22:00",
    displayName: `Jugador Libre ${runId}`,
    generalArea: "Barcelona",
    preferredModality: "futbol7",
    primaryPosition: "Mediocentro / pivote",
    shortBio: "Disponible para pachangas controladas.",
    socialPreferences: { openToMatchInvites: true, openToTeamInvites: true },
    usualDays: ["M", "J"],
  };
  const profile = await profileCommand(deviceA.supabase, profilePayload);
  if (profile.error) throw new Error(`profile.create: ${diagnostic(profile)}`, { cause: profile.error });
  assert.equal(profile.data.confirmedRevision, 1);
  assert.equal(profile.data.marketPublished, false);

  const realtimeQueue = {};
  const realtimeBinding = postgresChangesBinding(realtimeQueue);
  const realtimeChannel = deviceB.supabase
    .channel(`controlled-pilot-free-agent-${runId}`)
    .on("system", {}, (payload) => realtimeQueue.binding?.(payload))
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_social_invalidations_v1",
    }, (event) => {
      if (
        event.new?.entity_type === "profile"
        && event.new?.entity_id === freeAgent.id
        && event.new?.revision === 2
      ) {
        realtimeQueue.resolve?.(event);
      }
    });
  channels.push({ channel: realtimeChannel, supabase: deviceB.supabase });
  await waitForSubscribed(realtimeChannel);
  await realtimeBinding;
  const realtimeEvent = nextInvalidation(realtimeQueue);

  const marketQueue = {};
  const marketBinding = postgresChangesBinding(marketQueue);
  const marketChannel = readerSession.supabase
    .channel(`controlled-pilot-market-reader-${runId}`)
    .on("system", {}, (payload) => marketQueue.binding?.(payload))
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_market_invalidations_v1",
    }, (event) => marketQueue.resolve?.(event));
  channels.push({ channel: marketChannel, supabase: readerSession.supabase });
  await waitForSubscribed(marketChannel);
  await marketBinding;
  const publishMarketEvent = nextInvalidation(marketQueue);

  const publishOperations = [randomUUID(), randomUUID()];
  const publishResults = await Promise.all([
    marketCommand(deviceA.supabase, "market.publish", 1, publishOperations[0]),
    marketCommand(deviceB.supabase, "market.publish", 1, publishOperations[1]),
  ]);
  const winnerIndex = publishResults.findIndex((result) => !result.error);
  const loserIndex = publishResults.findIndex((result) => result.error);
  assert.notEqual(winnerIndex, -1, "one concurrent publish must win");
  assert.notEqual(loserIndex, -1, "one concurrent publish must be stale");
  assert.match(diagnostic(publishResults[loserIndex]), /PT409|STALE_PROFILE_REVISION/);
  const published = publishResults[winnerIndex].data;
  assert.equal(published.marketPublished, true);
  assert.equal(published.confirmedRevision, 2);

  const invalidation = await realtimeEvent;
  assert.equal(invalidation.new.revision, 2);
  const marketPublishInvalidation = await publishMarketEvent;
  assert.equal(marketPublishInvalidation.new.active, true);
  const deviceBReadback = await rpc(deviceB.supabase, "get_my_pachanga_social_profile_v1");
  assert.equal(deviceBReadback.marketPublished, true);
  assert.equal(deviceBReadback.confirmedRevision, 2);

  const replay = await marketCommand(
    winnerIndex === 0 ? deviceA.supabase : deviceB.supabase,
    "market.publish",
    1,
    publishOperations[winnerIndex],
  );
  if (replay.error) throw new Error(`market.publish replay: ${diagnostic(replay)}`, { cause: replay.error });
  assert.deepEqual(replay.data, published);

  const readerSearch = await readerSession.supabase
    .from("pachanga_market_profiles")
    .select("id,user_id,display_name,position,media,zones,availability_text,modalities,bio,active")
    .eq("active", true)
    .ilike("display_name", `%${runId}%`)
    .contains("zones", ["Barcelona"])
    .contains("modalities", ["futbol7"]);
  if (readerSearch.error) throw readerSearch.error;
  assert.equal(readerSearch.data.length, 1);
  assert.equal(readerSearch.data[0].user_id, freeAgent.id);
  assert.equal(readerSearch.data[0].display_name, profilePayload.displayName);
  assert.equal(readerSearch.data[0].position, profilePayload.primaryPosition);
  assert.equal(readerSearch.data[0].media, 5);
  assert.match(readerSearch.data[0].availability_text, /Martes, Jueves.*20:00-22:00/);
  const marketProfileId = readerSearch.data[0].id;
  assert.equal(marketPublishInvalidation.new.profile_id, marketProfileId);

  const profileUpdateMarketEvent = nextInvalidation(marketQueue);
  const updatedProfile = await updateProfileCommand(deviceA.supabase, 2, {
    approximateTime: "16:00-20:00",
    generalArea: "Barcelona Centro",
    shortBio: "Perfil actualizado desde el servidor.",
    usualDays: ["V"],
  });
  if (updatedProfile.error) throw new Error(`profile.update: ${diagnostic(updatedProfile)}`, { cause: updatedProfile.error });
  assert.equal(updatedProfile.data.confirmedRevision, 3);
  assert.equal(updatedProfile.data.marketPublished, true);
  const profileUpdateInvalidation = await profileUpdateMarketEvent;
  assert.equal(profileUpdateInvalidation.new.profile_id, marketProfileId);
  assert.equal(profileUpdateInvalidation.new.active, true);

  const updatedReaderSearch = await readerSession.supabase
    .from("pachanga_market_profiles")
    .select("id,zones,availability_text,bio,active")
    .eq("id", marketProfileId)
    .single();
  if (updatedReaderSearch.error) throw updatedReaderSearch.error;
  assert.deepEqual(updatedReaderSearch.data.zones, ["Barcelona Centro"]);
  assert.match(updatedReaderSearch.data.availability_text, /Viernes.*16:00-20:00/);
  assert.equal(updatedReaderSearch.data.bio, "Perfil actualizado desde el servidor.");
  assert.equal(updatedReaderSearch.data.active, true);

  const directWrite = await deviceA.supabase
    .from("pachanga_market_profiles")
    .update({ display_name: "CLIENT_AUTHORITY_FORBIDDEN" })
    .eq("user_id", freeAgent.id)
    .select("id");
  assert.ok(directWrite.error, "authenticated direct market writes must be denied");
  assert.match(diagnostic(directWrite), /42501|permission denied/i);

  const offlineClient = client(env.publishableKey, {
    global: {
      fetch: async () => { throw new TypeError("SYNTHETIC_OFFLINE"); },
      headers: { Authorization: `Bearer ${deviceA.accessToken}` },
    },
  });
  const offlineAttempt = await marketCommand(offlineClient, "market.unpublish", 3);
  assert.ok(offlineAttempt.error, "offline unpublish must not be confirmed");
  const stateAfterOffline = await rpc(deviceB.supabase, "get_my_pachanga_social_profile_v1");
  assert.equal(stateAfterOffline.marketPublished, true);
  assert.equal(stateAfterOffline.confirmedRevision, 3);

  const unpublishMarketEvent = nextInvalidation(marketQueue);
  const unpublish = await marketCommand(deviceB.supabase, "market.unpublish", 3);
  if (unpublish.error) throw new Error(`market.unpublish: ${diagnostic(unpublish)}`, { cause: unpublish.error });
  assert.equal(unpublish.data.marketPublished, false);
  assert.equal(unpublish.data.confirmedRevision, 4);
  const marketUnpublishInvalidation = await unpublishMarketEvent;
  assert.equal(marketUnpublishInvalidation.new.profile_id, marketProfileId);
  assert.equal(marketUnpublishInvalidation.new.active, false);

  const hiddenFromReader = await readerSession.supabase
    .from("pachanga_market_profiles")
    .select("id")
    .eq("user_id", freeAgent.id);
  if (hiddenFromReader.error) throw hiddenFromReader.error;
  assert.equal(hiddenFromReader.data.length, 0);

  const ownPausedProjection = await deviceA.supabase
    .from("pachanga_market_profiles")
    .select("active,display_name")
    .eq("user_id", freeAgent.id)
    .single();
  if (ownPausedProjection.error) throw ownPausedProjection.error;
  assert.equal(ownPausedProjection.data.active, false);
  assert.equal(ownPausedProjection.data.display_name, profilePayload.displayName);

  const ratingRows = await service.from("pachanga_player_profiles")
    .select("id", { count: "exact", head: true })
    .eq("user_id", freeAgent.id);
  if (ratingRows.error) throw ratingRows.error;
  assert.equal(ratingRows.count, 0, "Mercado must not create or mutate Rating V2");

  const publishInvalidations = await service.from("pachanga_social_invalidations_v1")
    .select("id", { count: "exact", head: true })
    .eq("audience_user_id", freeAgent.id)
    .eq("entity_type", "profile")
    .eq("revision", 2);
  if (publishInvalidations.error) throw publishInvalidations.error;
  assert.equal(publishInvalidations.count, 1, "the stale attempt and exact replay must not emit extra invalidations");

  const marketInvalidations = await service.from("pachanga_market_invalidations_v1")
    .select("active,server_sequence,id")
    .eq("profile_id", marketProfileId)
    .order("server_sequence", { ascending: true })
    .order("id", { ascending: true });
  if (marketInvalidations.error) throw marketInvalidations.error;
  assert.deepEqual(
    marketInvalidations.data.map((entry) => entry.active),
    [true, true, false],
    "publish, canonical profile edit and unpublish must each emit one ordered invalidation",
  );

  report = {
    auth: "3 synthetic .test users / 2 sessions for Player C",
    concurrency: "ONE_WINNER_ONE_STALE",
    directWrites: "DENIED",
    idempotency: "EXACT_REPLAY_ONE_INVALIDATION",
    market: "PUBLISH_SEARCH_PROFILE_SYNC_UNPUBLISH_PASS",
    offline: "FAIL_CLOSED_STATE_UNCHANGED",
    projectRef: env.projectRef,
    ratingV2: "0_ROWS_UNCHANGED",
    realtime: "INVALIDATION_CANONICAL_REFETCH_PASS",
  };
  completed = true;
} finally {
  if (platformClient && initialFlags) {
    await bestEffort(() => setProfileFlags(
      initialFlags.socialProfileFoundationEnabled === true,
      initialFlags.socialProfileIndependentWriteEnabled === true,
    ));
  }
  if (temporaryPlatformGrant && accounts[0]) {
    await bestEffort(async () => {
      runFixtureSql(`delete from private.pachanga_platform_admin_roles where user_id=${sqlText(accounts[0].id)}::uuid;`, "temporary platform grant cleanup");
      temporaryPlatformGrant = false;
    });
  }
  for (const { channel, supabase } of channels) {
    await bestEffort(() => supabase.removeChannel(channel));
  }
  for (const supabase of clients) {
    await bestEffort(() => supabase.auth.signOut({ scope: "local" }));
    await bestEffort(() => supabase.realtime.disconnect());
  }
  await bestEffort(async () => cleanupSyntheticEvidence());
  for (const account of accounts.reverse()) {
    await bestEffort(() => service.auth.admin.deleteUser(account.id));
  }
}

assert.equal(completed, true);
process.stdout.write(`${JSON.stringify({ status: "CONTROLLED_PILOT_FREE_AGENT_STAGING_PASS", ...report })}\n`);
