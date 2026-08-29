import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.ORGANIZER_ACCESS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave8a_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave8a-concurrency-${suffix}.sql`);
const teamOwner = "8a000000-0000-4000-8000-000000000001";
const nextTeamOwner = "8a000000-0000-4000-8000-000000000006";
const platformOwner = "8a000000-0000-4000-8000-000000000003";
const teams = Array.from({ length: 12 }, (_, index) =>
  `8a000000-0000-4000-8000-${String(110 + index).padStart(12, "0")}`);
let summary;
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("ORGANIZER_ACCESS_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 204);
assert.equal(migrations.at(-1), "20260829152250_organizer_access_hardening_indexes_flags_v1.sql");

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label = "query Wave 8A concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function authenticated(actorId, statement, { role = "authenticated", holdMs = 0 } = {}) {
  return `begin;
set local role ${role};
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role, sub: actorId }))}, true);
${statement};
${holdMs > 0 ? `select pg_sleep(${holdMs / 1000});` : ""}
commit;`;
}

function concurrent(sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()],
      { cwd: root, env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.stdin.end(sql);
  });
}

function responseFrom(output) {
  const line = output.split("\n").map((item) => item.trim()).filter(Boolean).at(-1);
  return JSON.parse(line);
}

function assertOneWinner(results, loserPattern = /STALE_REVISION|STATE_INVALID|NOT_WITHDRAWABLE|NOT_SUBMITTABLE|CONFLICT|AUTHORITY_REQUIRED/) {
  assert.equal(results.filter((result) => result.code === 0).length, 1, JSON.stringify(results));
  assert.equal(results.filter((result) => result.code !== 0 && loserPattern.test(result.stderr)).length, 1, JSON.stringify(results));
}

function organizerCommand(actorId, operationId, aggregateId, revision, action, payload, options = {}) {
  return authenticated(actorId, `select public.command_pachanga_organizer_access_application_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"8.0.0+concurrency","serviceWorkerVersion":"sw-wave8a","displayMode":"browser","surface":"wave8a_concurrency"}'::jsonb
  )`, options);
}

function transferOwner(operationId, teamId, holdMs = 0) {
  return authenticated(teamOwner, `select public.transfer_pachanga_group_ownership_authoritative_v1(
    ${quote(teamId)}::uuid, ${quote(nextTeamOwner)}::uuid, ${quote(operationId)}::uuid, 1,
    '{"clientVersion":"8.0.0+concurrency","surface":"wave8a_concurrency"}'::jsonb
  )`, { holdMs });
}

function manualBillingGrant(operationId, teamId) {
  return authenticated(platformOwner, `select public.command_pachanga_organizer_billing_platform_v1(
    ${quote(operationId)}::uuid, ${quote(teamId)}::uuid, 0, 'manual.grant',
    '{"organizerKind":"TEAM","planCode":"PRIVATE_BETA","expiresAt":"2027-12-31T23:59:59Z","reason":"Wave 8A concurrent manual grant"}'::jsonb,
    '{"clientVersion":"8.0.0+concurrency","surface":"wave8a_concurrency"}'::jsonb
  )`);
}

function legacyLeagueGrant(operationId, teamId) {
  return authenticated(platformOwner, `select public.command_pachanga_league_private_beta_platform_v1(
    ${quote(operationId)}::uuid, ${quote(teamId)}::uuid, 0, 'beta.bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":12,"expiresAt":"2027-12-31T23:59:59Z","reason":"Wave 8A concurrent legacy grant"}'::jsonb,
    '{"clientVersion":"8.0.0+concurrency","surface":"wave8a_concurrency"}'::jsonb
  )`);
}

function expiryReminder(operationId) {
  return authenticated(null, `select public.process_pachanga_organizer_access_expiry_notifications_v1(
    ${quote(operationId)}::uuid, 100
  )`, { role: "service_role" });
}

function applicationPayload() {
  return {
    organizerKind: "TEAM",
    planCode: "TEAM_ORGANIZER_PRO",
    intent: "LEAGUE",
    competitionType: "LEAGUE",
    teamCount: 10,
    municipality: "Terrassa",
    summary: "Solicitud de concurrencia Wave 8A.",
    reason: "Wave 8A concurrency",
  };
}

function approvePayload(validUntil = "2027-12-31T23:59:59Z") {
  return {
    decisionCode: "PRIVATE_BETA_APPROVED",
    grantPlanCode: "PRIVATE_BETA",
    grantSource: "PRIVATE_BETA",
    validUntil,
    message: "Acceso beta aprobado.",
    reason: "Wave 8A concurrent approval",
  };
}

function createApplication(teamId) {
  return responseFrom(query(organizerCommand(
    teamOwner, randomUUID(), teamId, 0, "application.create", applicationPayload(),
  ), `create application for ${teamId}`));
}

function submitApplication(applicationId, revision, actorId = teamOwner) {
  return responseFrom(query(organizerCommand(
    actorId, randomUUID(), applicationId, revision, "application.submit",
    { consent: true, reason: "Submit Wave 8A application" },
  ), `submit application ${applicationId}`));
}

function startReview(applicationId, revision) {
  return responseFrom(query(organizerCommand(
    platformOwner, randomUUID(), applicationId, revision, "review.start",
    { reason: "Start Wave 8A review" },
  ), `start review ${applicationId}`));
}

function prepareReview(teamId) {
  const created = createApplication(teamId);
  const submitted = submitApplication(created.aggregateId, created.confirmedRevision);
  const reviewed = startReview(created.aggregateId, submitted.confirmedRevision);
  return { applicationId: created.aggregateId, revision: reviewed.confirmedRevision };
}

function prepareApprovedOnboarding(teamId, validUntil = "2027-12-31T23:59:59Z") {
  const review = prepareReview(teamId);
  const approved = responseFrom(query(organizerCommand(
    platformOwner, randomUUID(), review.applicationId, review.revision,
    "review.approve", approvePayload(validUntil),
  ), `approve application ${review.applicationId}`));
  return {
    applicationId: review.applicationId,
    onboardingId: approved.snapshot.onboarding.id,
    onboardingRevision: approved.snapshot.onboarding.revision,
  };
}

function launchCompetition(actorId, operationId, onboardingId, revision) {
  return organizerCommand(actorId, operationId, onboardingId, revision, "competition.launch", {
    launcherKind: "LEAGUE",
    launcherPayload: { authoringMode: "SIMPLE", presetKey: "LEAGUE_F7_STANDARD" },
    reason: "Wave 8A first competition launch",
  });
}

function cleanup() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 8A database");
  if (exists === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 8A database");
    admin("select pg_sleep(0.25)", "wait for Wave 8A internal clients");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      join pg_roles roles on roles.oid=activity.usesysid
      where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`, "terminate Wave 8A clients");
    admin(`drop database ${databaseName}`, "drop Wave 8A database");
  }
  rmSync(infrastructureDump, { force: true });
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 8A concurrency database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 8A infrastructure");
  query("create publication supabase_realtime;", "create Wave 8A Realtime publication");

  const migrationArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    migrationArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, migrationArgs, "bootstrap Wave 8A concurrency schema");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/organizer-access-onboarding-v1-fixture.sql"),
  ], "load Wave 8A fixture");

  query(`
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    select team_id, ${quote(teamOwner)}::uuid, 'Wave 8A Race ' || ordinal,
      'W8R' || lpad(ordinal::text, 3, '0'),
      jsonb_build_object('name','Wave 8A Race ' || ordinal,'matches','[]'::jsonb,'players','[]'::jsonb,'siteSettings','{}'::jsonb,'venues','[]'::jsonb), 1
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) with ordinality seeded(team_id, ordinal);
    insert into public.pachanga_group_members(group_id,user_id,role,display_name)
    select team_id, ${quote(teamOwner)}::uuid, 'owner', 'Wave 8A Team Owner'
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) seeded(team_id);
    insert into public.pachanga_group_members(group_id,user_id,role,display_name)
    select team_id, ${quote(nextTeamOwner)}::uuid, 'admin', 'Wave 8A Next Team Owner'
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) seeded(team_id);
    insert into private.pachanga_organizer_access_rate_limit_overrides_v1(
      organizer_kind, organizer_group_id, action_pattern, valid_until, reason, granted_by
    )
    select 'TEAM', team_id, 'application.*', clock_timestamp() + interval '1 hour',
      'Wave 8A concurrency fixture override', ${quote(platformOwner)}::uuid
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) seeded(team_id);
    update private.pachanga_organizer_billing_settings set
      foundation_enabled=true, plan_catalog_enabled=true, partner_grants_enabled=true,
      revision=revision+1, updated_at=clock_timestamp()
    where singleton;
    update private.pachanga_competition_foundation_settings set
      foundation_enabled=true, creation_enabled=true, context_binding_enabled=true,
      league_participation_foundation_enabled=true, league_registration_enabled=true,
      league_delegates_enabled=true, league_rosters_enabled=true,
      league_schedule_preferences_enabled=true, league_scheduling_foundation_enabled=true,
      league_schedule_generation_enabled=true, league_schedule_editing_enabled=true,
      league_schedule_publication_enabled=true, league_canonical_fixture_creation_enabled=true,
      league_match_operations_foundation_enabled=true, league_match_squads_enabled=true,
      league_match_attendance_enabled=true, league_sporting_results_enabled=true,
      league_result_confirmation_enabled=true, league_official_results_enabled=true,
      league_standings_enabled=true, league_operational_exceptions_foundation_enabled=true,
      league_postponements_enabled=true, league_rescheduling_enabled=true,
      league_venue_changes_enabled=true, league_late_arrival_enabled=true,
      league_no_show_enabled=true, league_match_suspensions_enabled=true,
      league_administrative_decisions_enabled=true, league_private_beta_enabled=true,
      league_private_beta_creation_enabled=true, league_private_beta_public_discovery_enabled=false,
      revision=revision+1, server_sequence=nextval('private.pachanga_competition_sequence'),
      updated_by=${quote(platformOwner)}::uuid, updated_at=clock_timestamp()
    where singleton;
  `, "seed Wave 8A race organizers and engine flags");

  query(organizerCommand(platformOwner, randomUUID(), "8a000000-0000-4000-8000-000000000099", 1, "settings.flags", {
    applicationsEnabled: true,
    submissionEnabled: true,
    reviewEnabled: true,
    partnershipApprovalEnabled: true,
    onboardingEnabled: true,
    firstCompetitionLauncherEnabled: true,
    demoWorldV30Enabled: true,
    reason: "Enable Wave 8A concurrency fixture",
  }), "enable Wave 8A flags");

  const createRace = await Promise.all([
    concurrent(organizerCommand(teamOwner, randomUUID(), teams[0], 0, "application.create", applicationPayload()), "application.create A"),
    concurrent(organizerCommand(teamOwner, randomUUID(), teams[0], 0, "application.create", applicationPayload()), "application.create B"),
  ]);
  assert.equal(createRace.filter((result) => result.code === 0).length, 2, JSON.stringify(createRace));
  const createIds = createRace.map((result) => responseFrom(result.stdout).aggregateId);
  assert.equal(new Set(createIds).size, 1, JSON.stringify(createRace));
  assert.equal(query(`select count(*) from private.pachanga_organizer_access_applications_v1 where organizer_group_id=${quote(teams[0])}::uuid and status='draft'`), "1");

  const submitCreated = createApplication(teams[1]);
  const submitRace = await Promise.all([
    concurrent(organizerCommand(teamOwner, randomUUID(), submitCreated.aggregateId, submitCreated.confirmedRevision, "application.submit", { consent: true, reason: "Concurrent submit A" }), "submit A"),
    concurrent(organizerCommand(teamOwner, randomUUID(), submitCreated.aggregateId, submitCreated.confirmedRevision, "application.submit", { consent: true, reason: "Concurrent submit B" }), "submit B"),
  ]);
  assertOneWinner(submitRace);

  const submitWithdrawCreated = createApplication(teams[2]);
  const submitWithdrawRace = await Promise.all([
    concurrent(organizerCommand(teamOwner, randomUUID(), submitWithdrawCreated.aggregateId, submitWithdrawCreated.confirmedRevision, "application.submit", { consent: true, reason: "Submit side" }), "submit vs withdraw submit"),
    concurrent(organizerCommand(teamOwner, randomUUID(), submitWithdrawCreated.aggregateId, submitWithdrawCreated.confirmedRevision, "application.withdraw", { reason: "Withdraw side" }), "submit vs withdraw withdraw"),
  ]);
  assertOneWinner(submitWithdrawRace);

  const approveWithdraw = prepareReview(teams[3]);
  const approveWithdrawRace = await Promise.all([
    concurrent(organizerCommand(platformOwner, randomUUID(), approveWithdraw.applicationId, approveWithdraw.revision, "review.approve", approvePayload()), "approve vs withdraw approval"),
    concurrent(organizerCommand(teamOwner, randomUUID(), approveWithdraw.applicationId, approveWithdraw.revision, "application.withdraw", { reason: "Concurrent applicant withdrawal" }), "approve vs withdraw withdrawal"),
  ]);
  assertOneWinner(approveWithdrawRace);

  const approveReject = prepareReview(teams[4]);
  const approveRejectRace = await Promise.all([
    concurrent(organizerCommand(platformOwner, randomUUID(), approveReject.applicationId, approveReject.revision, "review.approve", approvePayload()), "approve vs reject approval"),
    concurrent(organizerCommand(platformOwner, randomUUID(), approveReject.applicationId, approveReject.revision, "review.reject", { decisionCode: "RACE_REJECTED", message: "No aprobado.", reason: "Concurrent rejection" }), "approve vs reject rejection"),
  ]);
  assertOneWinner(approveRejectRace);

  const informationApprove = prepareReview(teams[5]);
  const informationApproveRace = await Promise.all([
    concurrent(organizerCommand(platformOwner, randomUUID(), informationApprove.applicationId, informationApprove.revision, "review.request_information", { message: "Aporta una aclaración.", reason: "Concurrent information request" }), "information vs approve information"),
    concurrent(organizerCommand(platformOwner, randomUUID(), informationApprove.applicationId, informationApprove.revision, "review.approve", approvePayload()), "information vs approve approval"),
  ]);
  assertOneWinner(informationApproveRace);

  const ownerTransferCreated = createApplication(teams[6]);
  const transferPromise = concurrent(transferOwner(randomUUID(), teams[6], 350), "owner transfer");
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 80));
  const staleSubmitPromise = concurrent(organizerCommand(teamOwner, randomUUID(), ownerTransferCreated.aggregateId, ownerTransferCreated.confirmedRevision, "application.submit", { consent: true, reason: "Stale owner submit" }), "owner transfer vs submit");
  const ownerTransferRace = await Promise.all([transferPromise, staleSubmitPromise]);
  assertOneWinner(ownerTransferRace, /AUTHORITY_REQUIRED/);
  assert.equal(query(`select owner_id from public.pachanga_groups where id=${quote(teams[6])}::uuid`), nextTeamOwner);
  const continuedByNewOwner = submitApplication(ownerTransferCreated.aggregateId, ownerTransferCreated.confirmedRevision, nextTeamOwner);
  assert.equal(continuedByNewOwner.snapshot.status, "submitted");

  const doubleLaunch = prepareApprovedOnboarding(teams[7]);
  const launchRace = await Promise.all([
    concurrent(launchCompetition(teamOwner, randomUUID(), doubleLaunch.onboardingId, doubleLaunch.onboardingRevision), "first launch A"),
    concurrent(launchCompetition(teamOwner, randomUUID(), doubleLaunch.onboardingId, doubleLaunch.onboardingRevision), "first launch B"),
  ]);
  assertOneWinner(launchRace, /STALE_REVISION|FIRST_COMPETITION_ALREADY_LAUNCHED|CONFLICT/);
  assert.equal(query(`select count(*) from private.pachanga_league_private_beta_wizards where organizer_group_id=${quote(teams[7])}::uuid`), "1");

  const expiring = prepareApprovedOnboarding(teams[8], new Date(Date.now() + 1500).toISOString());
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 1700));
  const expiredLaunch = await concurrent(launchCompetition(teamOwner, randomUUID(), expiring.onboardingId, expiring.onboardingRevision), "expired entitlement vs first launch");
  assert.notEqual(expiredLaunch.code, 0, JSON.stringify(expiredLaunch));
  assert.match(expiredLaunch.stderr, /ORGANIZER_ACCESS_ENTITLEMENT_REQUIRED/);
  assert.equal(query(`select count(*) from private.pachanga_league_private_beta_wizards where organizer_group_id=${quote(teams[8])}::uuid`), "0");

  const manualGrantReview = prepareReview(teams[9]);
  const manualGrantRace = await Promise.all([
    concurrent(organizerCommand(platformOwner, randomUUID(), manualGrantReview.applicationId, manualGrantReview.revision, "review.approve", approvePayload()), "application approval vs billing manual grant approval"),
    concurrent(manualBillingGrant(randomUUID(), teams[9]), "application approval vs billing manual grant"),
  ]);
  assertOneWinner(manualGrantRace, /ORGANIZER_ACCESS_GRANT_CONFLICT|BILLING_PLATFORM_CONFLICT|CONFLICT/);
  assert.equal(query(`select count(*) from private.pachanga_organizer_access_grants_v1 grants join public.pachanga_organizer_plan_revisions revisions on revisions.id=grants.plan_revision_id join public.pachanga_organizer_plan_catalog plans on plans.id=revisions.plan_id where grants.organizer_group_id=${quote(teams[9])}::uuid and plans.plan_code='PRIVATE_BETA' and grants.status='active'`), "1");

  const legacyGrantReview = prepareReview(teams[10]);
  const legacyGrantRace = await Promise.all([
    concurrent(organizerCommand(platformOwner, randomUUID(), legacyGrantReview.applicationId, legacyGrantReview.revision, "review.approve", approvePayload()), "application approval vs legacy grant approval"),
    concurrent(legacyLeagueGrant(randomUUID(), teams[10]), "application approval vs legacy grant"),
  ]);
  assertOneWinner(legacyGrantRace, /ORGANIZER_ACCESS_LEGACY_ENTITLEMENT_CONFLICT|LEAGUE_BETA_ENTITLEMENT_CONFLICT|CONFLICT/);
  assert.equal(query(`select count(distinct coalesce(grants.billing_access_grant_id,grants.bundle_id)) from public.pachanga_competition_entitlement_grants grants where grants.organizer_group_id=${quote(teams[10])}::uuid and grants.status='active' and grants.capability='competition_create'`), "1");

  query(`update private.pachanga_organizer_access_grants_v1 grants set
    valid_until=clock_timestamp()+interval '3 days', updated_at=clock_timestamp()
    where grants.organizer_group_id=${quote(teams[7])}::uuid
      and grants.organizer_access_decision_id is not null and grants.status='active'`,
  "prepare concurrent access reminder");
  const reminderGrantId = query(`select grants.id from private.pachanga_organizer_access_grants_v1 grants
    where grants.organizer_group_id=${quote(teams[7])}::uuid
      and grants.organizer_access_decision_id is not null and grants.status='active'`,
  "read concurrent reminder grant");
  const reminderRace = await Promise.all([
    concurrent(expiryReminder(randomUUID()), "expiry reminder A"),
    concurrent(expiryReminder(randomUUID()), "expiry reminder B"),
  ]);
  assert.equal(reminderRace.filter((result) => result.code === 0).length, 2, JSON.stringify(reminderRace));
  assert.equal(query(`select count(*) from public.pachanga_user_notifications notifications
    where notifications.kind='organizer_access_warning'
      and notifications.payload->>'action'='access.expiry_notification'
      and notifications.payload->>'accessGrantId'=${quote(reminderGrantId)}`), "1");

  summary = {
    applicationApprovalVsLegacyGrant: "PASS",
    applicationApprovalVsManualGrant: "PASS",
    approveVsReject: "PASS",
    approveVsWithdraw: "PASS",
    createVsCreate: "PASS",
    database: "ephemeral-local",
    expiryReminderVsReminder: "PASS",
    entitlementExpiryVsFirstLaunch: "PASS",
    ownerTransferVsSubmit: "PASS",
    requestInformationVsApprove: "PASS",
    submitVsSubmit: "PASS",
    submitVsWithdraw: "PASS",
    twoFirstCompetitionLaunches: "PASS",
  };
} finally {
  try {
    cleanup();
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({ ...summary, cleanup: "PASS" })}\n`);
