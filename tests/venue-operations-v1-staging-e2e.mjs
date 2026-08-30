import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawnSync } from "node:child_process";

import { createClient } from "@supabase/supabase-js";

const env = {
  confirmation: process.env.VENUE_OPERATIONS_STAGING_CONFIRM,
  databaseUrl: process.env.VENUE_OPERATIONS_STAGING_DATABASE_URL,
  previewUrl: process.env.VENUE_OPERATIONS_STAGING_PREVIEW_URL || null,
  projectRef: process.env.VENUE_OPERATIONS_STAGING_PROJECT_REF,
  publishableKey: process.env.VENUE_OPERATIONS_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.VENUE_OPERATIONS_STAGING_SERVICE_ROLE_KEY,
  url: process.env.VENUE_OPERATIONS_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (key !== "previewUrl" && !value) throw new Error(`VENUE_OPERATIONS_STAGING_${key.toUpperCase()}_REQUIRED`);
}

const productionRef = "qonbngfrnrqgmxbdfbea";
const actualRef = new URL(env.url).hostname.split(".")[0];
const databaseUrl = new URL(env.databaseUrl);
if (
  env.confirmation !== "VENUE_OPERATIONS_STAGING_ONLY"
  || env.projectRef === productionRef
  || actualRef !== env.projectRef
  || databaseUrl.hostname === `db.${productionRef}.supabase.co`
  || !databaseUrl.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(databaseUrl.username).endsWith(`.${env.projectRef}`)
) throw new Error("VENUE_OPERATIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN");
if (env.previewUrl && /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)) {
  throw new Error("VENUE_OPERATIONS_STAGING_PREVIEW_PRODUCTION_TARGET_FORBIDDEN");
}
assert.notEqual(env.publishableKey, env.serviceRoleKey);

const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `Wave9A-${randomUUID()}-Qa!`;
const clubId = "e9210000-0000-4000-8000-000000000001";
const accounts = [];
const clients = [];
const channels = [];

function client(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
  });
}

const service = client(env.serviceRoleKey);

function metadata(surface) {
  return {
    clientVersion: "9.0.0+wave9a-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "9.0.0+wave9a-staging",
    sessionId: `wave9a-${runId}`,
    surface,
  };
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", env.databaseUrl,
  ], {
    encoding: "utf8",
    env: { ...process.env, PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=120s" },
    input: sql,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label}: ${result.stderr || result.stdout}`);
  return (result.stdout ?? "").trim();
}

function command(supabase, { action, aggregateId, expectedRevision, operationId, payload = {} }) {
  return supabase.rpc("command_pachanga_venue_reservation_v1", {
    action,
    aggregate_id: aggregateId,
    client_metadata: metadata("wave9a-staging-authenticated"),
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean).join(" ");
}

async function commandOk(supabase, input) {
  const result = await command(supabase, input);
  if (result.error) throw new Error(`${input.action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

async function createAccount(label) {
  const account = {
    email: `wave9a-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const created = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "VENUE_OPERATIONS_V1", runId },
  });
  if (created.error) throw created.error;
  accounts.push(account);
  return account;
}

async function signIn(account) {
  const supabase = client();
  const signedIn = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (signedIn.error) throw signedIn.error;
  assert.equal(signedIn.data.user.id, account.id);
  await supabase.realtime.setAuth(signedIn.data.session.access_token);
  clients.push(supabase);
  return supabase;
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("VENUE_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`VENUE_REALTIME_${status}`));
      }
    });
  });
}

function nextInvalidation(queue) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("VENUE_REALTIME_EVENT_TIMEOUT")), 20_000);
    queue.resolve = (value) => {
      clearTimeout(timeout);
      resolve(value);
    };
  });
}

async function clubDesk(supabase) {
  const result = await supabase.rpc("get_pachanga_club_venue_desk_v1", { target_club_id: clubId });
  if (result.error) throw result.error;
  return result.data;
}

async function previewSmoke() {
  if (!env.previewUrl) return { status: "NOT_REQUESTED" };
  const paths = ["/manifest.webmanifest", "/sw.js", "/demo-world/v3-4/manifest.json", "/campos", "/reservas"];
  for (const path of paths) {
    const response = await fetch(new URL(path, env.previewUrl), { cache: "no-store", redirect: "follow" });
    assert.equal(response.ok, true, `${path} returned ${response.status}`);
    if (path === "/sw.js") {
      assert.match(response.headers.get("cache-control") ?? "", /no-store/);
      assert.match(await response.text(), /demo-world\/v3-4|\/campos|\/reservas/);
    }
  }
  return { paths: paths.length, status: "PASS" };
}

let completed = false;
let report;
try {
  const topology = JSON.parse(runSql(`
select json_build_object(
  'ledger',(select count(*) from supabase_migrations.schema_migrations),
  'clubs',(select count(*) from public.pachanga_clubs),
  'teams',(select count(*) from public.pachanga_groups),
  'venues',(select count(*) from public.pachanga_club_venues),
  'pitches',(select count(*) from public.pachanga_venue_pitches),
  'leagues',(select count(*) from public.pachanga_competitions where competition_type='LEAGUE'),
  'tournaments',(select count(*) from public.pachanga_competitions where competition_type='TOURNAMENT'),
  'matches',(select count(*) from public.pachanga_canonical_matches)
)::text;
`, "inspect Wave 9A staging topology"));
  assert.deepEqual(topology, { ledger: 220, clubs: 3, teams: 6, venues: 6, pitches: 12, leagues: 1, tournaments: 1, matches: 20 });

  const accountA = await createAccount("device-a");
  const accountB = await createAccount("device-b");
  runSql(`
insert into public.pachanga_club_memberships(club_id,user_id,role,status,accepted_at,invited_by)
values
  (${sqlLiteral(clubId)}::uuid,${sqlLiteral(accountA.id)}::uuid,'club_venue_manager','active',clock_timestamp(),'e9200000-0000-4000-8000-000000000001'),
  (${sqlLiteral(clubId)}::uuid,${sqlLiteral(accountB.id)}::uuid,'club_venue_manager','active',clock_timestamp(),'e9200000-0000-4000-8000-000000000001');
`, "grant two synthetic Venue memberships");

  const deviceA = await signIn(accountA);
  const deviceB = await signIn(accountB);
  const initialDesk = await clubDesk(deviceA);
  const venue = initialDesk.venues.find((item) => item.slug === "instalacion-iq-staging-2");
  assert.ok(venue?.id);

  const visibleInvalidations = await deviceB.from("pachanga_venue_invalidations")
    .select("server_sequence,audience_kind,audience_id,entity_type,entity_id,revision")
    .eq("audience_id", clubId)
    .order("server_sequence", { ascending: false })
    .limit(1);
  if (visibleInvalidations.error) throw visibleInvalidations.error;
  assert.equal(visibleInvalidations.data.length, 1);

  const queue = {};
  const channel = deviceB.channel(`wave9a-${runId}`).on("postgres_changes", {
    event: "INSERT",
    schema: "public",
    table: "pachanga_venue_invalidations",
  }, (event) => {
    if (
      event.new?.entity_id === venue.id
      && (event.new?.audience_id === clubId || event.new?.audience_kind === "PUBLIC")
    ) queue.resolve?.(event);
  });
  channels.push({ channel, supabase: deviceB });
  await waitForSubscribed(channel);
  const firstEvent = nextInvalidation(queue);
  const firstOperation = randomUUID();
  const updated = await commandOk(deviceA, {
    action: "venue.update",
    aggregateId: venue.id,
    expectedRevision: venue.revision,
    operationId: firstOperation,
    payload: { description: `Realtime Wave 9A ${runId}`, reasonCode: "STAGING_REALTIME" },
  });
  const invalidation = await firstEvent;
  assert.equal(invalidation.new.entity_id, venue.id);
  const refetchedDesk = await clubDesk(deviceB);
  const refetched = refetchedDesk.venues.find((item) => item.id === venue.id);
  assert.equal(refetched.revision, updated.confirmedRevision);

  const raceInputs = [randomUUID(), randomUUID()].map((operationId, index) => ({
    action: "venue.update",
    aggregateId: venue.id,
    expectedRevision: updated.confirmedRevision,
    operationId,
    payload: { description: `Race ${index} Wave 9A ${runId}`, reasonCode: "STAGING_CONCURRENCY" },
  }));
  const race = await Promise.all([command(deviceA, raceInputs[0]), command(deviceB, raceInputs[1])]);
  const winners = race.filter((item) => !item.error);
  const losers = race.filter((item) => item.error);
  assert.equal(winners.length, 1);
  assert.equal(losers.length, 1);
  assert.match(diagnostic(losers[0]), /STALE_REVISION|PT409/);
  const winnerIndex = race.findIndex((item) => !item.error);
  const winnerClient = winnerIndex === 0 ? deviceA : deviceB;
  const replay = await commandOk(winnerClient, raceInputs[winnerIndex]);
  assert.deepEqual(replay, winners[0].data);

  const directWrite = await deviceA.from("pachanga_club_venues")
    .update({ description: "forbidden direct write" }).eq("id", venue.id);
  assert.ok(directWrite.error);

  await deviceB.removeChannel(channel);
  const reconnect = deviceB.channel(`wave9a-reconnect-${runId}`).on("postgres_changes", {
    event: "INSERT", schema: "public", table: "pachanga_venue_invalidations",
  }, () => {});
  channels.push({ channel: reconnect, supabase: deviceB });
  await waitForSubscribed(reconnect);
  const convergedDesk = await clubDesk(deviceB);
  assert.equal(
    convergedDesk.venues.find((item) => item.id === venue.id).revision,
    winners[0].data.confirmedRevision,
  );

  report = {
    auth: "2 synthetic accounts / 2 authenticated devices",
    canonicalRevision: winners[0].data.confirmedRevision,
    cleanup: "EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED",
    concurrency: "1 winner / 1 STALE_REVISION",
    directWrite: "DENIED",
    idempotency: "PASS",
    preview: await previewSmoke(),
    projectRef: env.projectRef,
    realtime: "SUBSCRIBED / invalidation / refetch / reconnect PASS",
    topology,
  };
  completed = true;
} finally {
  for (const { channel, supabase } of channels) {
    try { await supabase.removeChannel(channel); } catch {}
  }
  for (const supabase of clients) {
    try { await supabase.auth.signOut({ scope: "local" }); } catch {}
  }
}

assert.equal(completed, true);
process.stdout.write(`${JSON.stringify({ status: "VENUE_OPERATIONS_V1_STAGING_PASS", ...report })}\n`);
