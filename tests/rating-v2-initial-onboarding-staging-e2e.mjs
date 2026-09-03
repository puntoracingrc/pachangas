import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createClient } from "@supabase/supabase-js";

const PRODUCTION_REF = "qonbngfrnrqgmxbdfbea";
const env = {
  confirmation: process.env.RATING_V2_INITIAL_ONBOARDING_STAGING_CONFIRM,
  expectedSha: process.env.RATING_V2_INITIAL_ONBOARDING_STAGING_EXPECTED_SHA,
  previewUrl: process.env.RATING_V2_INITIAL_ONBOARDING_STAGING_PREVIEW_URL,
  projectRef: process.env.RATING_V2_INITIAL_ONBOARDING_STAGING_PROJECT_REF,
  scope: process.env.RATING_V2_INITIAL_ONBOARDING_VERCEL_SCOPE ?? "persianas-almar-web-s-projects",
};

if (
  env.confirmation !== "RATING_V2_ISSUE_165_STAGING_ONLY"
  || !env.projectRef
  || env.projectRef === PRODUCTION_REF
  || !/^[0-9a-f]{40}$/i.test(env.expectedSha ?? "")
  || !env.previewUrl
  || /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)
) {
  throw new Error("RATING_V2_ISSUE_165_PRODUCTION_TARGET_FORBIDDEN");
}

function loadEphemeralApiKeys() {
  const result = spawnSync(
    "supabase",
    ["projects", "api-keys", "--project-ref", env.projectRef, "--output", "json"],
    { encoding: "utf8", maxBuffer: 4 * 1024 * 1024 },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`RATING_V2_STAGING_API_KEYS_UNAVAILABLE:${result.stderr || "unknown"}`);

  const keys = JSON.parse(result.stdout);
  const publishable = keys.find((entry) => entry.type === "publishable")
    ?? keys.find((entry) => entry.name === "anon");
  const serviceRole = keys.find((entry) => entry.name === "service_role");
  if (!publishable?.api_key || !serviceRole?.api_key) throw new Error("RATING_V2_STAGING_KEYS_INCOMPLETE");
  if (/^sb_secret_/i.test(publishable.api_key) || publishable.api_key === serviceRole.api_key) {
    throw new Error("RATING_V2_STAGING_BROWSER_KEY_INVALID");
  }
  return { publishableKey: publishable.api_key, serviceRoleKey: serviceRole.api_key };
}

const { publishableKey, serviceRoleKey } = loadEphemeralApiKeys();
const supabaseUrl = `https://${env.projectRef}.supabase.co`;
const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `Rating165-${randomUUID()}-Qa!`;
const accounts = [];
const clients = [];
const channels = [];

function supabaseClient(key = publishableKey, options = {}) {
  return createClient(supabaseUrl, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
    ...options,
  });
}

const service = supabaseClient(serviceRoleKey);

function initialInput(seed = 0) {
  return {
    age: 31 + seed,
    answers: {
      attackingMovement: 3,
      ballCarrying: 3,
      controlUnderPressure: 3,
      decisionMaking: 3,
      defensiveDuels: 3,
      defensivePositioning: 3,
      finishing: 3,
      paceComparison: 3,
      passingExecution: 3,
      physicalIntensity: 3,
    },
    calculatedAt: "2026-09-03T20:00:00.000Z",
    engineVersion: "football-rating-v1",
    experienceLevel: "social_league",
    frequency: "weekly",
    heightCm: 178,
    modeShares: [
      { mode: "futsal_5", percentage: 10 },
      { mode: "football_7", percentage: 70 },
      { mode: "football_11", percentage: 20 },
    ],
    primaryPosition: "central_midfielder",
    questionnaireVersion: "initial-test-v1",
    secondaryPositions: ["attacking_midfielder"],
    weightKg: 76,
    yearsSinceLevel: 0,
  };
}

function requestBody(fixture, operationId, input = initialInput()) {
  return {
    assessmentInput: input,
    clientMetadata: {
      clientVersion: `2.0.0+rating165.${env.expectedSha.slice(0, 12)}`,
      displayMode: "standalone",
      serviceWorkerVersion: `2.0.0+sw.${env.expectedSha.slice(0, 12)}`,
      surface: "rating-v2-initial-onboarding-staging",
    },
    expectedRevision: fixture.revision,
    groupId: fixture.groupId,
    kind: "initial",
    operationId,
    playerId: fixture.playerId,
  };
}

function runVercelCurl(path, { body, method = "GET", token } = {}) {
  const secretDir = mkdtempSync(join(tmpdir(), "rating165-http-"));
  const configPath = join(secretDir, "headers.conf");
  const bodyPath = join(secretDir, "body.json");
  const config = token ? `header = \"Authorization: Bearer ${token}\"\n` : "";
  writeFileSync(configPath, config, { mode: 0o600 });
  if (body !== undefined) writeFileSync(bodyPath, JSON.stringify(body), { mode: 0o600 });

  const args = [
    "curl",
    path,
    "--deployment",
    env.previewUrl,
    "--scope",
    env.scope,
    "--",
    "--silent",
    "--show-error",
    "--dump-header",
    "-",
    "--request",
    method,
    "--config",
    configPath,
    "--write-out",
    "\\n__RATING165_STATUS__:%{http_code}",
  ];
  if (body !== undefined) args.push("--header", "Content-Type: application/json", "--data-binary", `@${bodyPath}`);

  return new Promise((resolve, reject) => {
    const child = spawn("vercel", args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => {
      rmSync(secretDir, { force: true, recursive: true });
      reject(error);
    });
    child.on("close", (status) => {
      rmSync(secretDir, { force: true, recursive: true });
      if (status !== 0) {
        reject(new Error(`RATING_V2_PREVIEW_REQUEST_FAILED:${path}:${stderr || status}`));
        return;
      }
      const marker = stdout.lastIndexOf("\n__RATING165_STATUS__:");
      if (marker < 0) {
        reject(new Error(`RATING_V2_PREVIEW_STATUS_MISSING:${path}`));
        return;
      }
      const payload = stdout.slice(0, marker).replaceAll("\r\n", "\n");
      const boundary = payload.indexOf("\n\n");
      if (boundary < 0) {
        reject(new Error(`RATING_V2_PREVIEW_HEADERS_MISSING:${path}`));
        return;
      }
      const headers = payload.slice(0, boundary);
      const responseBody = payload.slice(boundary + 2);
      const httpStatus = Number(stdout.slice(marker + "\n__RATING165_STATUS__:".length).trim());
      resolve({ body: responseBody, headers, status: httpStatus });
    });
  });
}

async function jsonRequest(path, options) {
  const response = await runVercelCurl(path, options);
  let data;
  try {
    data = JSON.parse(response.body);
  } catch {
    throw new Error(`RATING_V2_PREVIEW_INVALID_JSON:${path}:${response.status}`);
  }
  return { ...response, data };
}

async function createAccount(label) {
  const account = {
    email: `rating165-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const result = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "RATING_V2_ISSUE_165_STAGING", runId },
  });
  if (result.error) throw result.error;
  accounts.push(account);
  return account;
}

async function signIn(account, device) {
  const client = supabaseClient();
  const result = await client.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`RATING_V2_SIGN_IN_FAILED:${device}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  await client.realtime.setAuth(result.data.session.access_token);
  clients.push(client);
  return { client, token: result.data.session.access_token };
}

async function createFixture(account, label) {
  const fixture = {
    groupId: randomUUID(),
    playerId: `rating165-${label}-${runId}`,
    revision: 0,
  };
  const group = await service.from("pachanga_groups").insert({
    id: fixture.groupId,
    name: `Rating 165 ${label} ${runId}`,
    owner_id: account.id,
    payload: { activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] },
    team_code: `R${runId.slice(0, 6)}${label.slice(0, 2)}`.toUpperCase(),
  });
  if (group.error) throw group.error;
  const membership = await service.from("pachanga_group_members").insert({
    group_id: fixture.groupId,
    role: "owner",
    user_id: account.id,
  });
  if (membership.error) throw membership.error;
  return fixture;
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("RATING_V2_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`RATING_V2_REALTIME_${status}`));
      }
    });
  });
}

function nextAssessmentEvent(queue, groupId) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("RATING_V2_REALTIME_EVENT_TIMEOUT")), 20_000);
    queue.resolve = (event) => {
      if (event.new?.group_id !== groupId || event.new?.event_type !== "player_initial_assessment_v2_completed") return;
      clearTimeout(timeout);
      resolve(event);
    };
  });
}

async function canonicalRows(accountId, fixture) {
  const [profiles, assessments, groups, events, receipts, notifications] = await Promise.all([
    service.from("pachanga_player_profiles").select("id,user_id,source_group_id,source_player_id,rating,base_facets,rating_reliability").eq("user_id", accountId),
    service.from("pachanga_player_assessments").select("id,user_id,player_profile_id,assessment_kind,idempotency_key,rating,facet_ratings,reliability").eq("user_id", accountId),
    service.from("pachanga_groups").select("payload,payload_revision,updated_at").eq("id", fixture.groupId).single(),
    service.from("pachanga_group_events").select("event_type,operation_id,server_sequence").eq("group_id", fixture.groupId),
    service.from("pachanga_operation_receipts").select("operation_id,response,server_sequence,client_metadata").eq("group_id", fixture.groupId),
    service.from("pachanga_user_notifications").select("id", { count: "exact", head: true }).eq("recipient_user_id", accountId),
  ]);
  for (const result of [profiles, assessments, groups, events, receipts, notifications]) {
    if (result.error) throw result.error;
  }
  return {
    assessments: assessments.data,
    events: events.data,
    group: groups.data,
    notifications: notifications.count ?? 0,
    profiles: profiles.data,
    receipts: receipts.data,
  };
}

async function countRows(accountId) {
  const [profiles, assessments] = await Promise.all([
    service.from("pachanga_player_profiles").select("id", { count: "exact", head: true }).eq("user_id", accountId),
    service.from("pachanga_player_assessments").select("id", { count: "exact", head: true }).eq("user_id", accountId),
  ]);
  if (profiles.error) throw profiles.error;
  if (assessments.error) throw assessments.error;
  return { assessments: assessments.count ?? 0, profiles: profiles.count ?? 0 };
}

async function bestEffort(action) {
  try {
    await action();
  } catch {
    // The isolated branch is destroyed after evidence collection.
  }
}

let completed = false;
let report;
try {
  const baseline = await service.from("pachanga_player_assessments").select("id", { count: "exact", head: true });
  if (baseline.error) throw baseline.error;
  assert.equal(baseline.count, 0, "Rating V2 staging branch must start without assessments");

  const fresh = await createAccount("fresh");
  const concurrent = await createAccount("concurrent");
  const existing = await createAccount("existing");
  const invalid = await createAccount("invalid");
  const outsider = await createAccount("outsider");
  const freshFixture = await createFixture(fresh, "fresh");
  const concurrentFixture = await createFixture(concurrent, "concurrent");
  const existingFixture = await createFixture(existing, "existing");
  const invalidFixture = await createFixture(invalid, "invalid");

  const existingProfileId = randomUUID();
  const existingProfile = await service.from("pachanga_player_profiles").insert({
    display_name: "Existing synthetic profile",
    id: existingProfileId,
    source_group_id: existingFixture.groupId,
    source_player_id: existingFixture.playerId,
    user_id: existing.id,
  });
  if (existingProfile.error) throw existingProfile.error;

  const freshSession = await signIn(fresh, "fresh-device");
  const concurrentSessionA = await signIn(concurrent, "concurrent-device-a");
  const concurrentSessionB = await signIn(concurrent, "concurrent-device-b");
  const existingSession = await signIn(existing, "existing-device");
  const invalidSession = await signIn(invalid, "invalid-device");

  const realtimeQueue = {};
  const realtimeChannel = freshSession.client
    .channel(`rating165-${runId}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `group_id=eq.${freshFixture.groupId}`,
      schema: "public",
      table: "pachanga_group_events",
    }, (event) => realtimeQueue.resolve?.(event));
  channels.push({ channel: realtimeChannel, client: freshSession.client });
  await waitForSubscribed(realtimeChannel);
  const realtimeEvent = nextAssessmentEvent(realtimeQueue, freshFixture.groupId);

  const freshOperation = randomUUID();
  const freshBody = {
    ...requestBody(freshFixture, freshOperation),
    actorUserId: outsider.id,
  };
  const freshResponse = await jsonRequest("/api/ratings/assessment", {
    body: freshBody,
    method: "POST",
    token: freshSession.token,
  });
  assert.equal(freshResponse.status, 200);
  assert.match(freshResponse.headers, /^cache-control: .*no-store/im);
  assert.equal(freshResponse.data.operationId, freshOperation);
  assert.ok(freshResponse.data.confirmedRevision > 0);
  assert.ok(freshResponse.data.serverSequence > 0);
  const realtime = await realtimeEvent;
  assert.equal(realtime.new.operation_id, freshOperation);

  const freshRows = await canonicalRows(fresh.id, freshFixture);
  assert.equal(freshRows.profiles.length, 1);
  assert.equal(freshRows.assessments.length, 1);
  assert.equal(freshRows.assessments[0].player_profile_id, freshRows.profiles[0].id);
  assert.equal(freshRows.assessments[0].assessment_kind, "initial");
  assert.equal(freshRows.assessments[0].rating, 5.5);
  assert.equal(freshRows.profiles[0].rating, 5.5);
  assert.equal(freshRows.notifications, 0);
  assert.equal(freshRows.events.length, 1);
  assert.equal(freshRows.receipts.length, 1);
  assert.equal(
    freshRows.group.payload.players.some((player) => player.id === freshFixture.playerId && player.ownerUserId === fresh.id),
    true,
  );
  assert.deepEqual(await countRows(outsider.id), { assessments: 0, profiles: 0 });

  const lostResponseRetry = await jsonRequest("/api/ratings/assessment", {
    body: freshBody,
    method: "POST",
    token: freshSession.token,
  });
  assert.equal(lostResponseRetry.status, 200);
  assert.deepEqual(lostResponseRetry.data, freshResponse.data);
  const incompatibleReplay = await jsonRequest("/api/ratings/assessment", {
    body: { ...freshBody, assessmentInput: initialInput(1) },
    method: "POST",
    token: freshSession.token,
  });
  assert.equal(incompatibleReplay.status, 400);
  assert.match(incompatibleReplay.data.error, /different assessment payload/i);
  assert.deepEqual(await countRows(fresh.id), { assessments: 1, profiles: 1 });

  const concurrentOperation = randomUUID();
  const concurrentBody = requestBody(concurrentFixture, concurrentOperation);
  const concurrentResponses = await Promise.all([
    jsonRequest("/api/ratings/assessment", { body: concurrentBody, method: "POST", token: concurrentSessionA.token }),
    jsonRequest("/api/ratings/assessment", { body: concurrentBody, method: "POST", token: concurrentSessionB.token }),
  ]);
  assert.deepEqual(concurrentResponses.map((response) => response.status), [200, 200]);
  assert.deepEqual(concurrentResponses[0].data, concurrentResponses[1].data);
  assert.deepEqual(await countRows(concurrent.id), { assessments: 1, profiles: 1 });

  const existingOperation = randomUUID();
  const existingResponse = await jsonRequest("/api/ratings/assessment", {
    body: requestBody(existingFixture, existingOperation),
    method: "POST",
    token: existingSession.token,
  });
  assert.equal(existingResponse.status, 200);
  const existingRows = await canonicalRows(existing.id, existingFixture);
  assert.equal(existingRows.profiles.length, 1);
  assert.equal(existingRows.profiles[0].id, existingProfileId);
  assert.equal(existingRows.assessments[0].player_profile_id, existingProfileId);

  const invalidOperation = randomUUID();
  const invalidPayload = initialInput();
  delete invalidPayload.answers.finishing;
  const invalidResponse = await jsonRequest("/api/ratings/assessment", {
    body: requestBody(invalidFixture, invalidOperation, invalidPayload),
    method: "POST",
    token: invalidSession.token,
  });
  assert.equal(invalidResponse.status, 400);
  assert.deepEqual(await countRows(invalid.id), { assessments: 0, profiles: 0 });

  const staleResponse = await jsonRequest("/api/ratings/assessment", {
    body: { ...requestBody(invalidFixture, randomUUID()), expectedRevision: 1 },
    method: "POST",
    token: invalidSession.token,
  });
  assert.equal(staleResponse.status, 400);
  assert.match(staleResponse.data.error, /revision is newer|reload/i);
  assert.deepEqual(await countRows(invalid.id), { assessments: 0, profiles: 0 });

  const directProfileWrite = await invalidSession.client.from("pachanga_player_profiles").insert({ user_id: invalid.id });
  const directAssessmentWrite = await invalidSession.client.from("pachanga_player_assessments").insert({
    assessment_kind: "initial",
    engine_version: "forged",
    idempotency_key: randomUUID(),
    input: {},
    questionnaire_version: "forged",
    rating: 10,
    result: {},
    user_id: invalid.id,
  });
  assert.ok(directProfileWrite.error);
  assert.ok(directAssessmentWrite.error);
  const internalHelper = await invalidSession.client.rpc("persist_pachanga_player_assessment_v2", {});
  assert.ok(internalHelper.error);

  const beforeOffline = await countRows(invalid.id);
  const offlineClient = supabaseClient(publishableKey, {
    global: {
      fetch: async () => { throw new TypeError("RATING165_SYNTHETIC_OFFLINE"); },
      headers: { Authorization: `Bearer ${invalidSession.token}` },
    },
  });
  const offlineAttempt = await offlineClient.rpc("persist_pachanga_player_assessment_authoritative_v2", {});
  assert.ok(offlineAttempt.error);
  assert.deepEqual(await countRows(invalid.id), beforeOffline);

  const preview = await runVercelCurl("/perfil");
  assert.equal(preview.status, 200);
  const serviceWorker = await runVercelCurl("/sw.js");
  assert.equal(serviceWorker.status, 200);
  assert.match(serviceWorker.body, new RegExp(`SERVICE_WORKER_VERSION = "2\\.0\\.0\\+sw\\.${env.expectedSha.slice(0, 12)}"`));

  report = {
    auth: "5 synthetic .test users / 2 sessions for one actor",
    canonicalCard: "PROFILE / ASSESSMENT / GROUP READ MODEL PASS",
    cleanup: "EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED",
    concurrency: "2 IDENTICAL CALLS / 1 PROFILE / 1 ASSESSMENT",
    directWrites: "DENIED",
    idempotency: "REPLAY / LOST RESPONSE / PAYLOAD CONFLICT PASS",
    invalidPayload: "ROLLBACK / 0 ROWS",
    notifications: 0,
    offline: "FAIL_CLOSED / 0 ROWS",
    preview: "PROFILE / SERVICE WORKER PASS",
    projectRef: env.projectRef,
    realtime: "EVENT / CANONICAL REFETCH PASS",
    staleRevision: "ROLLBACK / 0 ROWS",
  };
  completed = true;
} finally {
  for (const { channel, client } of channels) await bestEffort(() => client.removeChannel(channel));
  for (const client of clients) {
    await bestEffort(() => client.auth.signOut({ scope: "local" }));
    await bestEffort(() => client.realtime.disconnect());
  }
}

assert.equal(completed, true);
process.stdout.write(`${JSON.stringify({ status: "RATING_V2_INITIAL_ONBOARDING_STAGING_PASS", ...report })}\n`);
