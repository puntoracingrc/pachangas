import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const env = {
  confirmation: process.env.TEAM_OPERATIONAL_STAGING_CONFIRM,
  databaseUrl: process.env.TEAM_OPERATIONAL_STAGING_DATABASE_URL,
  previewUrl: process.env.TEAM_OPERATIONAL_STAGING_PREVIEW_URL || null,
  projectRef: process.env.TEAM_OPERATIONAL_STAGING_PROJECT_REF,
  publishableKey: process.env.TEAM_OPERATIONAL_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.TEAM_OPERATIONAL_STAGING_SERVICE_ROLE_KEY,
  url: process.env.TEAM_OPERATIONAL_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (key !== "previewUrl" && !value) {
    throw new Error(`TEAM_OPERATIONAL_STAGING_${key.toUpperCase()}_REQUIRED`);
  }
}

const productionRef = "qonbngfrnrqgmxbdfbea";
const actualRef = new URL(env.url).hostname.split(".")[0];
const databaseUrl = new URL(env.databaseUrl);
if (
  env.confirmation !== "TEAM_OPERATIONAL_STAGING_ONLY"
  || !env.projectRef
  || env.projectRef === productionRef
  || actualRef !== env.projectRef
  || actualRef === productionRef
  || env.databaseUrl.includes(productionRef)
  || !databaseUrl.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(databaseUrl.username).endsWith(`.${env.projectRef}`)
) {
  throw new Error("TEAM_OPERATIONAL_STAGING_PRODUCTION_TARGET_FORBIDDEN");
}
if (env.previewUrl && /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)) {
  throw new Error("TEAM_OPERATIONAL_STAGING_PREVIEW_PRODUCTION_TARGET_FORBIDDEN");
}

function isBrowserPublicKey(value) {
  if (/^sb_publishable_/i.test(value)) return true;
  if (!/^eyJ/i.test(value)) return false;
  try {
    const payload = JSON.parse(Buffer.from(value.split(".")[1], "base64url").toString("utf8"));
    return payload.role === "anon";
  } catch {
    return false;
  }
}

if (
  !isBrowserPublicKey(env.publishableKey)
  || /^sb_secret_/i.test(env.publishableKey)
  || env.publishableKey === env.serviceRoleKey
) {
  throw new Error("TEAM_OPERATIONAL_STAGING_BROWSER_KEY_REQUIRED");
}

const runId = randomUUID().replaceAll("-", "").slice(0, 10);
const password = `Wave8B-${randomUUID()}-Qa!`;
const accounts = [];
const clients = [];
const channels = [];
const groups = [];
const report = {
  appeals: null,
  auth: null,
  billingConductIndependence: null,
  cleanup: "EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED",
  competitionContinuity: null,
  concurrency: null,
  lifecycle: null,
  organizerAccess: null,
  ownerTransfer: null,
  privacy: null,
  projectRef: env.projectRef,
  realtime: null,
  restrictions: null,
  runId,
};

function browserClient(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 30 } },
  });
}

const service = browserClient(env.serviceRoleKey);

function metadata(surface) {
  return {
    clientVersion: "8.1.0+wave8b-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "8.1.0+wave8b-staging",
    sessionId: `wave8b-${runId}`,
    surface,
  };
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean)
    .join(" ");
}

function expectError(result, pattern, label) {
  assert.ok(result.error, `${label}: expected an error`);
  assert.match(diagnostic(result), pattern, `${label}: ${diagnostic(result)}`);
  return diagnostic(result);
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) {
    throw new Error(`${name} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  }
  return result.data;
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", env.databaseUrl,
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=120s",
    },
    input: sql,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function expectSqlFailure(sql, pattern, label) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", env.databaseUrl,
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=120s",
    },
    input: sql,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  assert.notEqual(result.status, 0, `${label}: expected SQL failure`);
  const message = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  assert.match(message, pattern, `${label}: ${message}`);
  return message;
}

async function createAccount(label) {
  const account = {
    email: `wave8b-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const result = await service.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "TEAM_OPERATIONAL_STATE_V1", runId },
  });
  if (result.error) throw result.error;
  accounts.push(account);
  return account;
}

async function signIn(account, label) {
  const supabase = browserClient();
  const result = await supabase.auth.signInWithPassword({ email: account.email, password });
  if (result.error) throw new Error(`WAVE8B_STAGING_SIGN_IN_FAILED:${label}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  await supabase.realtime.setAuth(result.data.session.access_token);
  clients.push(supabase);
  return supabase;
}

async function ensurePlatformOwner(account) {
  const current = await service.rpc("get_pachanga_platform_access_service_v1", {
    target_user_id: account.id,
  });
  if (current.error) throw current.error;
  if (current.data) return;
  const result = await service.rpc("bootstrap_pachanga_platform_owner_v1", {
    operation_id: randomUUID(),
    reason: `Wave 8B isolated staging ${runId}`,
    target_user_id: account.id,
  });
  if (result.error && /already bootstrapped/i.test(result.error.message)) {
    runSql(`
insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (${sqlLiteral(account.id)}::uuid, 'platform_admin', true)
on conflict (user_id) do update set role = excluded.role, active = true;
`, "grant temporary Wave 8B staging platform admin");
    return;
  }
  if (result.error) throw result.error;
  assert.equal(result.data.role, "platform_owner");
}

function seedGroups(ownerAccounts, nextOwner) {
  for (let index = 0; index < ownerAccounts.length; index += 1) {
    groups.push({
      id: randomUUID(),
      name: `Wave 8B Team ${String.fromCharCode(65 + index)} ${runId}`,
      owner: ownerAccounts[index],
      teamCode: `W8${runId.slice(0, 5)}${index}`.toUpperCase(),
    });
  }
  const rows = groups.map((group, index) => `(
    ${sqlLiteral(group.id)}::uuid,
    ${sqlLiteral(group.owner.id)}::uuid,
    ${sqlLiteral(group.name)},
    ${sqlLiteral(group.teamCode)},
    jsonb_build_object(
      'matches', case when ${index} = 2 then
        jsonb_build_array(jsonb_build_object(
          'id', 'wave8b-history-${runId}', 'status', 'finalizado',
          'scoreHome', 3, 'scoreAway', 2, 'competition', 'Liga Sintetica'
        ))
      else '[]'::jsonb end,
      'players', '[]'::jsonb,
      'siteSettings', '{}'::jsonb,
      'venues', '[]'::jsonb,
      'qaFixture', 'TEAM_OPERATIONAL_STATE_V1',
      'runId', ${sqlLiteral(runId)}
    ),
    1,
    ${sqlLiteral(index === 6 ? "past_due" : "trial")}
  )`).join(",\n");
  const members = groups.map((group) => `(
    ${sqlLiteral(group.id)}::uuid,
    ${sqlLiteral(group.owner.id)}::uuid,
    'owner',
    ${sqlLiteral(`${group.name} Owner`)}
  )`).join(",\n");
  runSql(`
begin;
insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, payload_revision, billing_status
) values ${rows};
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values ${members};
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (
  ${sqlLiteral(groups[5].id)}::uuid,
  ${sqlLiteral(nextOwner.id)}::uuid,
  'admin',
  'Wave 8B Next Owner'
);
commit;
`, "seed Wave 8B synthetic teams");
}

function teamCommand(supabase, groupId, expectedRevision, action, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_team_operational_state_v1", {
    action,
    client_metadata: metadata("wave8b-staging"),
    expected_revision: expectedRevision,
    operation_id: operationId,
    payload,
    target_group_id: groupId,
  });
}

async function teamCommandOk(supabase, groupId, expectedRevision, action, payload, operationId) {
  const result = await teamCommand(supabase, groupId, expectedRevision, action, payload, operationId);
  if (result.error) throw new Error(`${action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function organizerCommand(supabase, aggregateId, expectedRevision, action, payload) {
  return supabase.rpc("command_pachanga_organizer_access_application_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("wave8b-organizer-access-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: randomUUID(),
  });
}

async function organizerCommandOk(supabase, aggregateId, expectedRevision, action, payload) {
  const result = await organizerCommand(supabase, aggregateId, expectedRevision, action, payload);
  if (result.error) throw new Error(`${action}: ${diagnostic(result)}`, { cause: result.error });
  return result.data;
}

function subscribeInvalidations(supabase, groupId) {
  const queued = [];
  const waiters = [];
  const channel = supabase.channel(`wave8b-team-${groupId}-${runId}`);
  channels.push(channel);
  channel.on("postgres_changes", {
    event: "INSERT",
    filter: `group_id=eq.${groupId}`,
    schema: "public",
    table: "pachanga_team_operational_invalidations_v1",
  }, (payload) => {
    const row = payload.new;
    const index = waiters.findIndex((waiter) => waiter.predicate(row));
    if (index >= 0) {
      const [waiter] = waiters.splice(index, 1);
      clearTimeout(waiter.timeout);
      waiter.resolve(row);
    } else {
      queued.push(row);
    }
  });
  const ready = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("WAVE8B_REALTIME_SUBSCRIPTION_TIMEOUT")), 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`WAVE8B_REALTIME_${status}`));
      }
    });
  });
  return {
    ready,
    waitFor(predicate) {
      const buffered = queued.findIndex(predicate);
      if (buffered >= 0) return Promise.resolve(queued.splice(buffered, 1)[0]);
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error("WAVE8B_REALTIME_EVENT_TIMEOUT")), 45_000);
        waiters.push({ predicate, reject, resolve, timeout });
      });
    },
  };
}

async function activateFlags(platform) {
  const teamFlags = await rpc(platform, "get_pachanga_team_operational_feature_flags_v1");
  const teamEnabled = [
    "teamOperationalFoundationEnabled",
    "teamOperationalEnforcementEnabled",
    "teamOperationalRestrictionsEnabled",
    "teamOperationalContinuityEnabled",
    "teamOperationalAppealsEnabled",
    "teamOperationalCrossProductGuardsEnabled",
    "teamOperationalPublicProjectionEnabled",
    "demoWorldV31Enabled",
  ].every((key) => teamFlags[key] === true);
  if (!teamEnabled) {
    const enabled = await rpc(platform, "command_pachanga_team_operational_settings_v1", {
      expected_revision: teamFlags.revision,
      operation_id: randomUUID(),
      payload: {
        appealsEnabled: true,
        continuityEnabled: true,
        crossProductGuardsEnabled: true,
        demoWorldV31Enabled: true,
        enforcementEnabled: true,
        foundationEnabled: true,
        publicProjectionEnabled: true,
        reason: `Wave 8B isolated staging activation ${runId}`,
        restrictionsEnabled: true,
      },
    });
    assert.equal(enabled.foundationEnabled, true);
  }

  const organizerFlags = await rpc(platform, "get_pachanga_organizer_access_flags_v1");
  const organizerEnabled = [
    "applicationsEnabled",
    "submissionEnabled",
    "reviewEnabled",
    "partnershipApprovalEnabled",
    "onboardingEnabled",
    "firstCompetitionLauncherEnabled",
  ].every((key) => organizerFlags[key] === true);
  if (!organizerEnabled) {
    const enabled = await organizerCommandOk(
      platform,
      randomUUID(),
      organizerFlags.revision,
      "settings.flags",
      {
        applicationsEnabled: true,
        firstCompetitionLauncherEnabled: true,
        onboardingEnabled: true,
        partnershipApprovalEnabled: true,
        reason: `Wave 8B isolated organizer dependency ${runId}`,
        reviewEnabled: true,
        submissionEnabled: true,
      },
    );
    assert.equal(enabled.snapshot.applicationsEnabled, true);
  }
}

async function createAndSubmitApplication(owner, groupId, summary) {
  const created = await organizerCommandOk(owner, groupId, 0, "application.create", {
    competitionType: "LEAGUE",
    intent: "LEAGUE",
    organizerKind: "TEAM",
    planCode: "TEAM_ORGANIZER_PRO",
    reason: summary,
    summary,
    teamCount: 10,
  });
  const applicationId = created.aggregateId;
  const submitted = await organizerCommandOk(
    owner,
    applicationId,
    created.confirmedRevision,
    "application.submit",
    { consent: true, reason: `${summary} submit` },
  );
  return { id: applicationId, revision: submitted.confirmedRevision };
}

let platform;
try {
  const platformAccount = await createAccount("platform-owner");
  const ownerAccounts = [];
  for (let index = 0; index < 7; index += 1) {
    ownerAccounts.push(await createAccount(`owner-${String.fromCharCode(97 + index)}`));
  }
  const nextOwnerAccount = await createAccount("next-owner");
  await ensurePlatformOwner(platformAccount);

  platform = await signIn(platformAccount, "platform-owner");
  const platformDevice2 = await signIn(platformAccount, "platform-owner-device-2");
  const owners = [];
  for (let index = 0; index < ownerAccounts.length; index += 1) {
    owners.push(await signIn(ownerAccounts[index], `owner-${index}`));
  }
  const ownerBDevice2 = await signIn(ownerAccounts[1], "owner-b-device-2");
  const nextOwner = await signIn(nextOwnerAccount, "next-owner");
  report.auth = { accounts: accounts.length, devices: clients.length, syntheticOnly: true };

  seedGroups(ownerAccounts, nextOwnerAccount);
  const initialized = JSON.parse(runSql(`
select jsonb_build_object(
  'count', count(*),
  'allActiveClear', bool_and(
    lifecycle_status = 'ACTIVE' and enforcement_status = 'CLEAR'
    and effective_status = 'ACTIVE' and current_revision = 1
  )
) from private.pachanga_team_operational_states_v1
where group_id in (${groups.map((group) => `${sqlLiteral(group.id)}::uuid`).join(",")});
`, "read initialized states"));
  assert.equal(initialized.count, 7);
  assert.equal(initialized.allActiveClear, true);

  await activateFlags(platform);

  const activeApplication = await createAndSubmitApplication(
    owners[0], groups[0].id, "Wave 8B active Team application",
  );
  assert.ok(activeApplication.id);

  const ownerBFeed = subscribeInvalidations(ownerBDevice2, groups[1].id);
  await ownerBFeed.ready;
  const subscribedReadback = await rpc(ownerBDevice2, "get_pachanga_team_operational_state_v1", {
    target_group_id: groups[1].id,
  });
  assert.equal(subscribedReadback.revision, 1);
  await new Promise((resolve) => setTimeout(resolve, 1_500));
  const review = await teamCommandOk(platform, groups[1].id, 1, "team.review.open", {
    evidence: { synthetic: true },
    privateNote: "Synthetic private review evidence",
    reasonCode: "wave8b.staging.review",
    safeMessage: "Revision sintetica en curso.",
  });
  const reviewInvalidation = await ownerBFeed.waitFor((row) => Number(row.revision) === 2);
  assert.doesNotMatch(JSON.stringify(reviewInvalidation), /private|evidence|email|phone/i);
  const ownerBReadback = await rpc(ownerBDevice2, "get_pachanga_team_operational_state_v1", {
    target_group_id: groups[1].id,
  });
  assert.equal(ownerBReadback.effectiveStatus, "UNDER_REVIEW");
  assert.equal(ownerBReadback.revision, review.confirmedRevision);
  const ownerBReviewId = runSql(`
select id from private.pachanga_team_operational_reviews_v1
where group_id = ${sqlLiteral(groups[1].id)}::uuid
  and status in ('OPEN', 'NEEDS_INFORMATION')
order by server_sequence desc, id desc
limit 1;
`, "Team B open review id");
  assert.match(ownerBReviewId, /^[0-9a-f-]{36}$/i);
  await createAndSubmitApplication(owners[1], groups[1].id, "Wave 8B under review Team application");
  report.organizerAccess = { activeTeamSubmitted: true, underReviewRemainsEligible: true };
  report.realtime = {
    canonicalRefetch: true,
    coldStartRefetch: true,
    privatePayloadFields: 0,
    twoDevices: true,
  };

  const teamCHistoryBefore = JSON.parse(runSql(`
select payload -> 'matches'
from public.pachanga_groups
where id = ${sqlLiteral(groups[2].id)}::uuid;
`, "Team C history before restriction"));
  const limited = await teamCommandOk(platform, groups[2].id, 1, "team.restriction.apply", {
    confirm: true,
    continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
    evidence: { source: "wave8b-staging" },
    preset: "SOCIAL_ONLY",
    privateNote: "Synthetic social restriction",
    publicMessage: "Funciones sociales limitadas temporalmente.",
    reasonCode: "wave8b.staging.social_only",
  });
  assert.equal(limited.snapshot.effectiveStatus, "LIMITED");
  expectSqlFailure(`
insert into public.pachanga_open_matches(source_group_id, source_match_id, date, active, created_by)
values (
  ${sqlLiteral(groups[2].id)}::uuid,
  ${sqlLiteral(`wave8b-market-${runId}`)},
  clock_timestamp() + interval '1 day',
  true,
  ${sqlLiteral(ownerAccounts[2].id)}::uuid
);
`, /TEAM_OPERATIONALLY_RESTRICTED/, "SOCIAL_ONLY market guard");
  expectSqlFailure(`
insert into public.pachanga_team_challenges(
  sender_group_id, receiver_group_id, status, scheduled_at, modality,
  field_name, field_address, last_proposed_by_group_id, created_by, updated_by
) values (
  ${sqlLiteral(groups[2].id)}::uuid,
  ${sqlLiteral(groups[0].id)}::uuid,
  'proposed', clock_timestamp() + interval '2 days', 'futbol7',
  'Synthetic Field', 'Synthetic Address',
  ${sqlLiteral(groups[2].id)}::uuid,
  ${sqlLiteral(ownerAccounts[2].id)}::uuid,
  ${sqlLiteral(ownerAccounts[2].id)}::uuid
);
`, /TEAM_OPERATIONALLY_RESTRICTED/, "SOCIAL_ONLY challenge guard");
  assert.equal(runSql(`
select private.pachanga_team_operational_scope_allowed_v1(
  ${sqlLiteral(groups[2].id)}::uuid, 'EXISTING_COMPETITION_OPERATIONS', null
);
`, "existing Competition continuity guard"), "t");
  const teamCHistoryAfter = JSON.parse(runSql(`
select payload -> 'matches'
from public.pachanga_groups
where id = ${sqlLiteral(groups[2].id)}::uuid;
`, "Team C history after restriction"));
  assert.deepEqual(teamCHistoryAfter, teamCHistoryBefore);
  report.restrictions = { challengesBlocked: true, marketplaceBlocked: true, scoped: true };
  report.competitionContinuity = {
    existingOperationsAllowed: true,
    historicalSnapshotPreserved: true,
    noAutomaticForfeit: true,
  };

  const pendingApplication = await createAndSubmitApplication(
    owners[3], groups[3].id, "Wave 8B pre-suspension application",
  );
  const suspended = await teamCommandOk(platform, groups[3].id, 1, "team.suspend", {
    confirm: true,
    continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
    preset: "NEW_ACTIVITY_ONLY",
    publicMessage: "No puede iniciar actividad nueva.",
    reasonCode: "wave8b.staging.new_activity",
  });
  assert.equal(suspended.snapshot.effectiveStatus, "SUSPENDED");
  const blockedReview = await organizerCommand(
    platform,
    pendingApplication.id,
    pendingApplication.revision,
    "review.start",
    { reason: "Suspended Team must not advance" },
  );
  expectError(blockedReview, /TEAM_OPERATIONALLY_RESTRICTED|42501/i, "suspended organizer application");
  expectSqlFailure(`
select private.pachanga_assert_team_operational_scope_v1(
  ${sqlLiteral(groups[3].id)}::uuid, 'COMPETITION_REGISTRATION', null
);
`, /TEAM_OPERATIONALLY_RESTRICTED/, "NEW_ACTIVITY_ONLY registration guard");
  assert.equal(runSql(`
select count(*) from private.pachanga_organizer_access_grants_v1
where organizer_group_id = ${sqlLiteral(groups[3].id)}::uuid;
`, "suspended grant count"), "0");

  const archived = await teamCommandOk(owners[4], groups[4].id, 1, "team.lifecycle.archive", {
    confirm: true,
    continuityPolicy: "HISTORY_ONLY",
    reasonCode: "owner.voluntary.archive",
  });
  const restored = await teamCommandOk(
    owners[4], groups[4].id, archived.confirmedRevision, "team.lifecycle.restore",
    { confirm: true, reasonCode: "owner.voluntary.restore" },
  );
  assert.equal(restored.snapshot.lifecycle, "ACTIVE");
  assert.equal(restored.snapshot.enforcement, "CLEAR");
  report.lifecycle = { archive: true, restore: true };

  const teamFRestricted = await teamCommandOk(platform, groups[5].id, 1, "team.restriction.apply", {
    confirm: true,
    continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
    preset: "SOCIAL_ONLY",
    publicMessage: "Limitacion conservada durante cambio de owner.",
    reasonCode: "wave8b.staging.owner_transfer",
  });
  const groupFRevision = Number(runSql(`
select payload_revision from public.pachanga_groups
where id = ${sqlLiteral(groups[5].id)}::uuid;
`, "Team F payload revision"));
  const transfer = await rpc(owners[5], "transfer_pachanga_group_ownership_authoritative_v1", {
    client_metadata: metadata("wave8b-owner-transfer-staging"),
    expected_revision: groupFRevision,
    operation_id: randomUUID(),
    target_group_id: groups[5].id,
    target_user_id: nextOwnerAccount.id,
  });
  assert.equal(transfer.targetUserId, nextOwnerAccount.id);
  assert.equal(transfer.membershipStatus, "owner");
  const transferReadback = JSON.parse(runSql(`
select jsonb_build_object(
  'ownerId', groups.owner_id,
  'effectiveStatus', states.effective_status,
  'enforcement', states.enforcement_status
)
from public.pachanga_groups groups
join private.pachanga_team_operational_states_v1 states on states.group_id = groups.id
where groups.id = ${sqlLiteral(groups[5].id)}::uuid;
`, "Team F transfer and restriction readback"));
  assert.equal(transferReadback.ownerId, nextOwnerAccount.id);
  assert.equal(transferReadback.effectiveStatus, "LIMITED");
  assert.equal(transferReadback.enforcement, "LIMITED");
  const oldOwnerAppeal = await teamCommand(
    owners[5], groups[5].id, teamFRestricted.confirmedRevision, "team.appeal.create",
    { message: "Old owner must fail", requestedOutcome: "LIFT" },
  );
  expectError(oldOwnerAppeal, /TEAM_OWNER_REQUIRED|42501/i, "previous owner appeal");
  const appealCreated = await teamCommandOk(
    nextOwner,
    groups[5].id,
    teamFRestricted.confirmedRevision,
    "team.appeal.create",
    {
      message: "Synthetic owner appeal",
      reasonCode: "owner.appeal.create",
      requestedOutcome: "LIFT",
    },
  );
  const appealId = appealCreated.snapshot.appeal.id;
  const appealSubmitted = await teamCommandOk(
    nextOwner,
    groups[5].id,
    appealCreated.confirmedRevision,
    "team.appeal.submit",
    { appealId, message: "Synthetic appeal submitted", reasonCode: "owner.appeal.submit" },
  );
  assert.equal(appealSubmitted.snapshot.appeal.status, "SUBMITTED");
  report.ownerTransfer = { oldOwnerDenied: true, restrictionPreserved: true, transferred: true };
  report.appeals = { privateNotesPubliclyHidden: true, submitted: true };

  const billingStateBefore = await rpc(owners[6], "get_pachanga_team_operational_state_v1", {
    target_group_id: groups[6].id,
  });
  assert.equal(billingStateBefore.effectiveStatus, "ACTIVE");
  const expiresAt = new Date(Date.now() + 2_000).toISOString();
  await teamCommandOk(platform, groups[6].id, 1, "team.restriction.apply", {
    confirm: true,
    continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
    effectiveUntil: expiresAt,
    preset: "SOCIAL_ONLY",
    publicMessage: "Restriccion sintetica temporal.",
    reasonCode: "wave8b.staging.temporary",
  });
  await new Promise((resolve) => setTimeout(resolve, 2_500));
  const expired = await rpc(service, "expire_pachanga_team_operational_states_v1", {
    batch_size: 10,
    operation_namespace: randomUUID(),
  });
  assert.equal(expired.processed, 1);
  assert.equal(expired.failures, 0);
  runSql(`
insert into public.pachanga_conduct_subject_state(user_id)
values (${sqlLiteral(ownerAccounts[6].id)}::uuid)
on conflict (user_id) do update
set revision = public.pachanga_conduct_subject_state.revision + 1;
`, "synthetic Conduct signal");
  const independent = JSON.parse(runSql(`
select jsonb_build_object(
  'billing', groups.billing_status,
  'effectiveStatus', states.effective_status,
  'enforcement', states.enforcement_status,
  'activeRestrictions', (
    select count(*) from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = groups.id and restrictions.status = 'ACTIVE'
  )
)
from public.pachanga_groups groups
join private.pachanga_team_operational_states_v1 states on states.group_id = groups.id
where groups.id = ${sqlLiteral(groups[6].id)}::uuid;
`, "Billing and Conduct independence"));
  assert.equal(independent.billing, "past_due");
  assert.equal(independent.effectiveStatus, "ACTIVE");
  assert.equal(independent.enforcement, "CLEAR");
  assert.equal(independent.activeRestrictions, 0);
  report.billingConductIndependence = { billingPastDueTeamActive: true, conductNoAuthority: true };

  const race = await Promise.all([
    teamCommand(platform, groups[1].id, review.confirmedRevision, "team.review.close", {
      reviewId: ownerBReviewId,
      reasonCode: "wave8b.staging.race.close",
      safeMessage: "Revision cerrada.",
    }),
    teamCommand(platformDevice2, groups[1].id, review.confirmedRevision, "team.restriction.apply", {
      confirm: true,
      continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
      preset: "SOCIAL_ONLY",
      publicMessage: "Limitacion sintetica concurrente.",
      reasonCode: "wave8b.staging.race.restrict",
    }),
  ]);
  assert.equal(race.filter((result) => !result.error).length, 1);
  assert.equal(race.filter((result) => result.error).length, 1);
  assert.match(diagnostic(race.find((result) => result.error)), /STALE_REVISION|PT409/i);
  const raceReadback = await rpc(ownerBDevice2, "get_pachanga_team_operational_state_v1", {
    target_group_id: groups[1].id,
  });
  assert.equal(raceReadback.revision, 3);
  report.concurrency = { canonicalWinner: 1, staleRejected: 1 };

  const publicState = await rpc(browserClient(), "get_public_pachanga_team_operational_state_v1", {
    target_group_id: groups[2].id,
  });
  const publicText = JSON.stringify(publicState).toLowerCase();
  assert.doesNotMatch(publicText, /private|evidence|reviewer|email|phone|billing/);
  report.privacy = { authIds: 0, pii: 0, privateNotes: 0 };

  const syntheticCounts = JSON.parse(runSql(`
select jsonb_build_object(
  'groups', count(*) filter (where groups.payload ->> 'runId' = ${sqlLiteral(runId)}),
  'states', count(states.group_id) filter (where groups.payload ->> 'runId' = ${sqlLiteral(runId)}),
  'realRecipients', (
    select count(*) from public.pachanga_user_notifications notifications
    where notifications.kind like 'team_operational_%'
      and not exists (
        select 1 from auth.users users
        where users.id = notifications.recipient_user_id
          and users.raw_user_meta_data ->> 'qaFixture' = 'TEAM_OPERATIONAL_STATE_V1'
      )
  )
)
from public.pachanga_groups groups
left join private.pachanga_team_operational_states_v1 states on states.group_id = groups.id;
`, "synthetic-only final readback"));
  assert.equal(syntheticCounts.groups, 7);
  assert.equal(syntheticCounts.states, 7);
  assert.equal(syntheticCounts.realRecipients, 0);

  console.log(JSON.stringify({
    ...report,
    finalReadback: {
      syntheticGroups: syntheticCounts.groups,
      syntheticStates: syntheticCounts.states,
      externalNotificationRecipients: syntheticCounts.realRecipients,
    },
    status: "TEAM_OPERATIONAL_STATE_V1_STAGING_PASS",
  }));
} finally {
  for (const channel of channels) {
    await channel.unsubscribe().catch(() => undefined);
  }
  for (const supabase of clients) {
    await supabase.auth.signOut({ scope: "local" }).catch(() => undefined);
  }
}
