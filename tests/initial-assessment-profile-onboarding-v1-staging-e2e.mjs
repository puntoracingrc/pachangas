import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createClient } from "@supabase/supabase-js";
import {
  calculateApplicableAdvancedQuestions,
  calculateInitialRatings,
} from "../app/laboratorio-ficha-jugador/_engine/player-rating-engine.ts";

const PRODUCTION_REF = "qonbngfrnrqgmxbdfbea";
const env = {
  branchName: process.env.RATING_PROFILE_ONBOARDING_STAGING_BRANCH,
  confirmation: process.env.RATING_PROFILE_ONBOARDING_STAGING_CONFIRM,
  expectedSha: process.env.RATING_PROFILE_ONBOARDING_STAGING_EXPECTED_SHA,
  previewUrl: process.env.RATING_PROFILE_ONBOARDING_STAGING_PREVIEW_URL,
  projectRef: process.env.RATING_PROFILE_ONBOARDING_STAGING_PROJECT_REF,
  vercelScope: process.env.RATING_PROFILE_ONBOARDING_STAGING_VERCEL_SCOPE ?? "persianas-almar-web-s-projects",
};

const previewTarget = env.previewUrl ? new URL(env.previewUrl) : null;
if (
  env.confirmation !== "RATING_PROFILE_ONBOARDING_STAGING_ONLY"
  || !env.branchName
  || !env.projectRef
  || env.projectRef === PRODUCTION_REF
  || !/^[0-9a-f]{40}$/i.test(env.expectedSha ?? "")
  || !previewTarget
  || /(^|\.)pachangasiq\.com$/i.test(previewTarget.hostname)
) {
  throw new Error("RATING_PROFILE_ONBOARDING_STAGING_PRODUCTION_TARGET_FORBIDDEN");
}

function loadBranchEnvironment() {
  const result = spawnSync("supabase", ["branches", "get", env.branchName, "--output", "json"], {
    encoding: "utf8",
    maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`RATING_PROFILE_ONBOARDING_BRANCH_UNAVAILABLE:${result.stderr || "unknown"}`);
  const values = JSON.parse(result.stdout);
  if (
    values.SUPABASE_URL !== `https://${env.projectRef}.supabase.co`
    || !values.SUPABASE_ANON_KEY
    || !values.SUPABASE_SERVICE_ROLE_KEY
    || !values.POSTGRES_URL_NON_POOLING
  ) {
    throw new Error("RATING_PROFILE_ONBOARDING_BRANCH_ENVIRONMENT_INVALID");
  }
  return values;
}

const branch = loadBranchEnvironment();
const runId = randomUUID().replaceAll("-", "").slice(0, 12);
const password = `Profile-Onboarding-${randomUUID()}-Qa!`;
const accounts = [];
const clients = [];
const channels = [];

function supabaseClient(key = branch.SUPABASE_ANON_KEY, options = {}) {
  return createClient(branch.SUPABASE_URL, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
    ...options,
  });
}

const service = supabaseClient(branch.SUPABASE_SERVICE_ROLE_KEY);

function initialInput(seed = 0) {
  return {
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
    calculatedAt: "1999-01-01T00:00:00.000Z",
    email: `discard-${seed}@example.test`,
    engineVersion: "football-rating-v1",
    experienceLevel: "regular_pachangas",
    frequency: "weekly",
    modeShares: [
      { mode: "futsal_5", percentage: 0 },
      { mode: "football_7", percentage: 100 },
      { mode: "football_11", percentage: 0 },
    ],
    primaryPosition: "central_midfielder",
    questionnaireVersion: "initial-test-v1",
    secondaryPositions: [],
    yearsSinceLevel: seed,
  };
}

function assessmentBody(snapshot, kind, operationId, assessmentInput) {
  return {
    actorUserId: randomUUID(),
    assessmentInput,
    clientMetadata: {
      clientVersion: `2.0.0+profile-onboarding.${env.expectedSha.slice(0, 12)}`,
      displayMode: "standalone",
      email: "must-not-persist@example.test",
      serviceWorkerVersion: `2.0.0+sw.${env.expectedSha.slice(0, 12)}`,
      snapshot: { forged: true },
      surface: "initial-assessment-profile-onboarding-staging",
    },
    expectedRevision: snapshot.writeContext.expectedRevision,
    groupId: snapshot.writeContext.groupId,
    kind,
    operationId,
    playerId: snapshot.writeContext.playerId,
  };
}

function runPreviewCurl(path, { body, method = "GET", token } = {}) {
  const secretDir = mkdtempSync(join(tmpdir(), "profile-onboarding-http-"));
  const configPath = join(secretDir, "request.conf");
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
    env.vercelScope,
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
    "\\n__PROFILE_ONBOARDING_STATUS__:%{http_code}",
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
        reject(new Error(`RATING_PROFILE_ONBOARDING_PREVIEW_REQUEST_FAILED:${path}:${stderr || status}`));
        return;
      }
      const marker = stdout.lastIndexOf("\n__PROFILE_ONBOARDING_STATUS__:");
      const payload = marker >= 0 ? stdout.slice(0, marker).replaceAll("\r\n", "\n") : "";
      const boundary = payload.indexOf("\n\n");
      if (marker < 0 || boundary < 0) {
        reject(new Error(`RATING_PROFILE_ONBOARDING_PREVIEW_RESPONSE_INVALID:${path}`));
        return;
      }
      resolve({
        body: payload.slice(boundary + 2),
        headers: payload.slice(0, boundary),
        status: Number(stdout.slice(marker + "\n__PROFILE_ONBOARDING_STATUS__:".length).trim()),
      });
    });
  });
}

async function jsonRequest(path, options) {
  const response = await runPreviewCurl(path, options);
  try {
    return { ...response, data: JSON.parse(response.body) };
  } catch {
    throw new Error(`RATING_PROFILE_ONBOARDING_PREVIEW_JSON_INVALID:${path}:${response.status}`);
  }
}

async function createAccount(label) {
  const account = {
    email: `profile-onboarding-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const created = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "RATING_PROFILE_ONBOARDING_STAGING", runId },
  });
  if (created.error) throw created.error;
  accounts.push(account);
  const social = await service.from("pachanga_social_player_profiles_v1").insert({
    display_name: `QA ${label.toUpperCase()}`,
    preferred_modality: "futbol7",
    primary_position: "Mediocentro / pivote",
    social_preferences: { openToMatchInvites: true, openToTeamInvites: true },
    user_id: account.id,
  });
  if (social.error) throw social.error;
  return account;
}

async function signIn(account, device) {
  const client = supabaseClient();
  const result = await client.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`RATING_PROFILE_ONBOARDING_SIGN_IN_FAILED:${device}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  await client.realtime.setAuth(result.data.session.access_token);
  clients.push(client);
  return { client, token: result.data.session.access_token };
}

async function createGroup(owner, member = null) {
  const groupId = randomUUID();
  const inserted = await service.from("pachanga_groups").insert({
    id: groupId,
    name: `Profile onboarding ${runId}`,
    owner_id: owner.id,
    payload: { activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] },
    team_code: `PO${runId.slice(0, 6)}`.toUpperCase(),
  });
  if (inserted.error) throw inserted.error;
  const memberships = [{ group_id: groupId, role: "owner", user_id: owner.id }];
  if (member) memberships.push({ group_id: groupId, role: "player", user_id: member.id });
  const membership = await service.from("pachanga_group_members").insert(memberships);
  if (membership.error) throw membership.error;
  return groupId;
}

async function canonicalCounts(userId) {
  const [profiles, assessments] = await Promise.all([
    service.from("pachanga_player_profiles").select("id,display_name,source_group_id,profile_version,current_overall,current_facets,rating_reliability").eq("user_id", userId),
    service.from("pachanga_player_assessments").select("id,assessment_kind,idempotency_key,input,player_profile_id").eq("user_id", userId).order("assessment_kind"),
  ]);
  if (profiles.error) throw profiles.error;
  if (assessments.error) throw assessments.error;
  return { assessments: assessments.data, profiles: profiles.data };
}

function waitForSubscribed(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("RATING_PROFILE_ONBOARDING_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`RATING_PROFILE_ONBOARDING_REALTIME_${status}`));
      }
    });
  });
}

function nextProfileEvent(queue, userId) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("RATING_PROFILE_ONBOARDING_REALTIME_EVENT_TIMEOUT")), 20_000);
    queue.resolve = (event) => {
      if (event.new?.audience_user_id !== userId || event.new?.entity_type !== "rating_profile") return;
      clearTimeout(timeout);
      resolve(event);
    };
  });
}

async function bestEffort(action) {
  try {
    await action();
  } catch {
    // The isolated branch is destroyed after the release gate.
  }
}

let report;
try {
  const flowA = await createAccount("a-no-team");
  const flowB = await createAccount("b-team");
  const flowC = await createAccount("c-invited");
  const flowD = await createAccount("d-initial");
  const flowE = await createAccount("e-advanced");
  const groupId = await createGroup(flowB, flowC);

  const aDevice1 = await signIn(flowA, "A-1");
  const aDevice2 = await signIn(flowA, "A-2");
  const bDevice = await signIn(flowB, "B");
  const cDevice = await signIn(flowC, "C");
  const dDevice = await signIn(flowD, "D");
  const eDevice = await signIn(flowE, "E");

  const flowAStart = await jsonRequest("/api/ratings/assessment", { token: aDevice1.token });
  assert.equal(flowAStart.status, 200);
  assert.match(flowAStart.headers, /^cache-control: private, no-store/im);
  assert.equal(flowAStart.data.playerProfile, null);
  assert.deepEqual(flowAStart.data.assessments, {});
  assert.equal(flowAStart.data.writeContext.scope, "profile");
  assert.equal(flowAStart.data.writeContext.expectedRevision, 0);

  const realtimeQueue = {};
  const realtimeChannel = aDevice2.client
    .channel(`profile-onboarding-${runId}`)
    .on("postgres_changes", {
      event: "INSERT",
      filter: `audience_user_id=eq.${flowA.id}`,
      schema: "public",
      table: "pachanga_social_invalidations_v1",
    }, (event) => realtimeQueue.resolve?.(event));
  channels.push({ channel: realtimeChannel, client: aDevice2.client });
  await waitForSubscribed(realtimeChannel);
  const realtimeEvent = nextProfileEvent(realtimeQueue, flowA.id);

  const flowAOperation = randomUUID();
  const flowABody = assessmentBody(flowAStart.data, "initial", flowAOperation, initialInput());
  const flowAResponses = await Promise.all([
    jsonRequest("/api/ratings/assessment", { body: flowABody, method: "POST", token: aDevice1.token }),
    jsonRequest("/api/ratings/assessment", { body: flowABody, method: "POST", token: aDevice2.token }),
  ]);
  assert.deepEqual(flowAResponses.map((response) => response.status), [200, 200]);
  assert.equal(flowAResponses[0].data.operationId, flowAOperation);
  assert.deepEqual(flowAResponses[0].data, flowAResponses[1].data);
  const receivedInvalidation = await realtimeEvent;
  assert.equal(receivedInvalidation.new.audience_user_id, flowA.id);
  assert.equal(receivedInvalidation.new.entity_type, "rating_profile");
  const flowARows = await canonicalCounts(flowA.id);
  assert.equal(flowARows.profiles.length, 1);
  assert.equal(flowARows.assessments.length, 1);
  assert.equal(flowARows.profiles[0].display_name, "QA A-NO-TEAM");
  assert.equal(flowARows.profiles[0].source_group_id, null);
  assert.equal(flowARows.assessments[0].assessment_kind, "initial");
  assert.equal(flowARows.assessments[0].input.calculatedAt, undefined);
  assert.equal(flowARows.assessments[0].input.email, undefined);

  const flowAReload = await signIn(flowA, "A-reload");
  const flowAReadback = await jsonRequest("/api/ratings/assessment", { token: flowAReload.token });
  assert.equal(flowAReadback.status, 200);
  assert.equal(flowAReadback.data.assessments.initial.questionnaireVersion, "initial-test-v1");
  assert.equal(flowAReadback.data.playerProfile.id, flowARows.profiles[0].id);
  assert.equal(flowAReadback.data.writeContext.scope, "profile");

  const replay = await jsonRequest("/api/ratings/assessment", { body: flowABody, method: "POST", token: flowAReload.token });
  assert.equal(replay.status, 200);
  assert.equal(replay.data.operationId, flowAOperation);
  assert.deepEqual(await canonicalCounts(flowA.id), flowARows);

  const secondInitial = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowAReadback.data, "initial", randomUUID(), initialInput()),
    method: "POST",
    token: flowAReload.token,
  });
  assert.equal(secondInitial.status, 409);
  assert.match(secondInitial.data.error, /already completed/i);

  const flowBStart = await jsonRequest("/api/ratings/assessment", { token: bDevice.token });
  assert.equal(flowBStart.data.writeContext.scope, "group");
  assert.equal(flowBStart.data.writeContext.groupId, groupId);
  const flowBResult = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowBStart.data, "initial", randomUUID(), initialInput()),
    method: "POST",
    token: bDevice.token,
  });
  assert.equal(flowBResult.status, 200);
  const flowBRows = await canonicalCounts(flowB.id);
  assert.equal(flowBRows.profiles.length, 1);
  assert.equal(flowBRows.assessments.length, 1);
  assert.equal(flowBRows.profiles[0].source_group_id, groupId);

  const flowCStart = await jsonRequest("/api/ratings/assessment", { token: cDevice.token });
  assert.equal(flowCStart.status, 200);
  assert.equal(flowCStart.data.playerProfile, null);
  assert.equal(flowCStart.data.writeContext.scope, "group");
  assert.equal(flowCStart.data.writeContext.groupId, groupId);
  const advancedBeforeInitial = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowCStart.data, "advanced", randomUUID(), { answers: {} }),
    method: "POST",
    token: cDevice.token,
  });
  assert.equal(advancedBeforeInitial.status, 400);
  assert.match(advancedBeforeInitial.data.error, /primero el test inicial/i);
  assert.deepEqual(await canonicalCounts(flowC.id), { assessments: [], profiles: [] });

  const flowDStart = await jsonRequest("/api/ratings/assessment", { token: dDevice.token });
  const flowDResult = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowDStart.data, "initial", randomUUID(), initialInput()),
    method: "POST",
    token: dDevice.token,
  });
  assert.equal(flowDResult.status, 200);
  assert.equal(flowDResult.data.assessments.initial.questionnaireVersion, "initial-test-v1");
  assert.equal((await canonicalCounts(flowD.id)).assessments.length, 1);

  const flowEStart = await jsonRequest("/api/ratings/assessment", { token: eDevice.token });
  const flowEInitialInput = initialInput();
  const flowEInitial = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowEStart.data, "initial", randomUUID(), flowEInitialInput),
    method: "POST",
    token: eDevice.token,
  });
  assert.equal(flowEInitial.status, 200);
  const advancedQuestions = calculateApplicableAdvancedQuestions(calculateInitialRatings(flowEInitialInput));
  const advancedInput = { answers: Object.fromEntries(advancedQuestions.map((question) => [question.id, 3])) };
  const staleAdvanced = await jsonRequest("/api/ratings/assessment", {
    body: { ...assessmentBody(flowEInitial.data, "advanced", randomUUID(), advancedInput), expectedRevision: 0 },
    method: "POST",
    token: eDevice.token,
  });
  assert.equal(staleAdvanced.status, 409);
  const flowEAdvanced = await jsonRequest("/api/ratings/assessment", {
    body: assessmentBody(flowEInitial.data, "advanced", randomUUID(), advancedInput),
    method: "POST",
    token: eDevice.token,
  });
  assert.equal(flowEAdvanced.status, 200);
  assert.equal(flowEAdvanced.data.assessments.advanced.questionnaireVersion, "advanced-test-v1");
  assert.equal((await canonicalCounts(flowE.id)).assessments.length, 2);

  const unauthorized = await jsonRequest("/api/ratings/assessment");
  assert.equal(unauthorized.status, 401);
  const directProfile = await cDevice.client.from("pachanga_player_profiles").insert({ user_id: flowC.id });
  const directAssessment = await cDevice.client.from("pachanga_player_assessments").insert({
    assessment_kind: "initial",
    engine_version: "forged",
    idempotency_key: randomUUID(),
    input: {},
    questionnaire_version: "forged",
    rating: 10,
    result: {},
    user_id: flowC.id,
  });
  const serverOnlyRpc = await cDevice.client.rpc("persist_pachanga_player_assessment_self_authoritative_v1", {});
  assert.ok(directProfile.error);
  assert.ok(directAssessment.error);
  assert.ok(serverOnlyRpc.error);

  const beforeOffline = await canonicalCounts(flowC.id);
  const offlineClient = supabaseClient(branch.SUPABASE_ANON_KEY, {
    global: {
      fetch: async () => { throw new TypeError("RATING_PROFILE_ONBOARDING_SYNTHETIC_OFFLINE"); },
      headers: { Authorization: `Bearer ${cDevice.token}` },
    },
  });
  const offlineWrite = await offlineClient.rpc("persist_pachanga_player_assessment_self_authoritative_v1", {});
  assert.ok(offlineWrite.error);
  assert.deepEqual(await canonicalCounts(flowC.id), beforeOffline);

  const [profilePage, assessmentPage, cosmeticsPage, serviceWorker] = await Promise.all([
    runPreviewCurl("/perfil"),
    runPreviewCurl("/perfil/test-inicial"),
    runPreviewCurl("/personalizar-carta"),
    runPreviewCurl("/sw.js"),
  ]);
  for (const response of [profilePage, assessmentPage, cosmeticsPage, serviceWorker]) assert.equal(response.status, 200);
  assert.match(serviceWorker.body, new RegExp(`SERVICE_WORKER_VERSION = "2\\.0\\.0\\+sw\\.${env.expectedSha.slice(0, 12)}"`));
  assert.match(serviceWorker.body, /\/perfil\/test-inicial/);

  report = {
    FLOW_A_NO_TEAM: "PASS / TWO DEVICES / REALTIME / IDEMPOTENT",
    FLOW_B_TEAM: "PASS / EXISTING GROUP AUTHORITY",
    FLOW_C_INVITED: "PASS / GROUP ACCESS / INITIAL STILL REQUIRED",
    FLOW_D_INITIAL: "PASS / CANONICAL RELOAD",
    FLOW_E_ADVANCED: "PASS / INITIAL PRESERVED / ADVANCED OPTIONAL",
    authority: "DIRECT WRITES DENIED / ACTOR DERIVED / SERVER CALCULATION",
    offline: "FAIL_CLOSED",
    previewSha: env.expectedSha,
    status: "RATING_PROFILE_ONBOARDING_STAGING_PASS",
  };
} finally {
  for (const { channel, client } of channels) await bestEffort(() => client.removeChannel(channel));
  for (const client of clients) {
    await bestEffort(() => client.auth.signOut({ scope: "local" }));
    await bestEffort(() => client.realtime.disconnect());
  }
}

process.stdout.write(`${JSON.stringify(report)}\n`);
