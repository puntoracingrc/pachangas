import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.PACHANGAS_SYNTHETIC_DB_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.CONDUCT_V1_SQL_TIMEOUT_MS || 30_000);
if (!databaseUrl) throw new Error("PACHANGAS_SYNTHETIC_DB_URL is required");

const sqlText = (value) => `'${String(value).replaceAll("'", "''")}'`;
const sqlJson = (value) => `${sqlText(JSON.stringify(value))}::jsonb`;

function runSql(sql, label) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timeout = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => {
      clearTimeout(timeout);
      resolve({
        code: timedOut ? 124 : code,
        label,
        stderr: [stderr.trim(), timedOut ? `SQL timed out after ${timeoutMs}ms` : ""].filter(Boolean).join("\n"),
        stdout: stdout.trim(),
      });
    });
    child.stdin.end(sql);
  });
}

async function runOk(sql, label) {
  const result = await runSql(sql, label);
  assert.equal(result.code, 0, `${label} failed:\n${result.stderr}`);
  return result.stdout;
}

function authenticatedSql(userId, statement, appMetadata = {}) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${sqlText(userId)}, true);
select set_config('request.jwt.claims', ${sqlText(JSON.stringify({ sub: userId, app_metadata: appMetadata }))}, true);
${statement};
commit;
`;
}

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} did not return JSON`);
  return JSON.parse(line);
}

const ownerId = randomUUID();
const adminId = randomUUID();
const targetId = randomUUID();
const moderatorId = randomUUID();
const ownerProfileId = randomUUID();
const targetProfileId = randomUUID();
const groupId = randomUUID();
const matchId = `conduct-concurrent-${randomUUID()}`;
const teamCode = `CV${groupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`;
const closeOperationId = randomUUID();
const disputeOperationId = randomUUID();
const resolveOperationIds = [randomUUID(), randomUUID()];
const reportReplayOperationId = randomUUID();
const reportRaceOperationIds = [randomUUID(), randomUUID()];
const warningOperationIds = [randomUUID(), randomUUID()];
const appealOperationId = randomUUID();

const matchPayload = {
  closed: true,
  configured: true,
  date: new Date(Date.now() - 60 * 60 * 1_000).toISOString(),
  id: matchId,
  kind: "futbol7",
  lineupClosed: true,
  players: [
    { joinedAt: new Date(Date.now() - 3 * 60 * 60 * 1_000).toISOString(), playerId: "owner-player", status: "voy" },
    { joinedAt: new Date(Date.now() - (3 * 60 - 1) * 60 * 1_000).toISOString(), playerId: "target-player", status: "voy" },
  ],
  reserveLimit: 0,
  reservesAttend: false,
  scoreA: 1,
  scoreB: 0,
  targetPlayers: 2,
  teamA: ["owner-player"],
  teamB: ["target-player"],
  title: "Concurrent conduct match",
};
const groupPayload = {
  activeMatchId: matchId,
  matches: [matchPayload],
  players: [
    { globalPlayerProfileId: ownerProfileId, id: "owner-player", name: "Concurrent Owner", ownerUserId: ownerId },
    { globalPlayerProfileId: targetProfileId, id: "target-player", name: "Concurrent Target", ownerUserId: targetId },
  ],
};

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(ownerId)}::uuid, ${sqlText(`owner-${ownerId}@example.test`)}),
  (${sqlText(adminId)}::uuid, ${sqlText(`admin-${adminId}@example.test`)}),
  (${sqlText(targetId)}::uuid, ${sqlText(`target-${targetId}@example.test`)}),
  (${sqlText(moderatorId)}::uuid, ${sqlText(`moderator-${moderatorId}@example.test`)});
insert into public.pachanga_player_profiles(id, user_id, source_player_id, display_name) values
  (${sqlText(ownerProfileId)}::uuid, ${sqlText(ownerId)}::uuid, 'owner-player', 'Concurrent Owner'),
  (${sqlText(targetProfileId)}::uuid, ${sqlText(targetId)}::uuid, 'target-player', 'Concurrent Target');
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  ${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'Concurrent conduct group', ${sqlText(teamCode)}, ${sqlJson(groupPayload)}
);
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  (${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'owner', 'Concurrent Owner'),
  (${sqlText(groupId)}::uuid, ${sqlText(adminId)}::uuid, 'admin', 'Concurrent Admin'),
  (${sqlText(groupId)}::uuid, ${sqlText(targetId)}::uuid, 'player', 'Concurrent Target');
update public.pachanga_player_profiles set source_group_id = ${sqlText(groupId)}::uuid
where id in (${sqlText(ownerProfileId)}::uuid, ${sqlText(targetProfileId)}::uuid);
select public.sync_pachanga_match_read_model(${sqlText(groupId)}::uuid, ${sqlJson(matchPayload)}, 1);
update private.pachanga_conduct_settings set
  attendance_closure_enabled = true, conduct_reports_enabled = true, social_restrictions_enabled = true
where singleton;
`;

const cleanupSql = `
delete from public.pachanga_user_notifications where recipient_user_id in (
  ${sqlText(ownerId)}::uuid, ${sqlText(adminId)}::uuid, ${sqlText(targetId)}::uuid, ${sqlText(moderatorId)}::uuid
);
delete from private.pachanga_conduct_appeals where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from private.pachanga_social_restrictions where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from private.pachanga_conduct_warnings where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from private.pachanga_moderation_events where case_id in (
  select id from private.pachanga_moderation_cases where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid)
);
delete from private.pachanga_conduct_reports where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from private.pachanga_report_source_clusters where case_id in (
  select id from private.pachanga_moderation_cases where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid)
);
delete from private.pachanga_moderation_cases where target_user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from private.pachanga_attendance_events where attendance_id in (
  select id from private.pachanga_post_match_attendance where group_id = ${sqlText(groupId)}::uuid
);
delete from private.pachanga_attendance_reviews where attendance_id in (
  select id from private.pachanga_post_match_attendance where group_id = ${sqlText(groupId)}::uuid
);
delete from private.pachanga_post_match_attendance where group_id = ${sqlText(groupId)}::uuid;
delete from private.pachanga_attendance_closures where group_id = ${sqlText(groupId)}::uuid;
delete from private.pachanga_conduct_operation_receipts where actor_user_id in (
  ${sqlText(ownerId)}::uuid, ${sqlText(adminId)}::uuid, ${sqlText(targetId)}::uuid, ${sqlText(moderatorId)}::uuid
);
delete from public.pachanga_conduct_subject_state where user_id in (${sqlText(ownerId)}::uuid, ${sqlText(targetId)}::uuid);
delete from public.pachanga_attendance_group_state where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_group_members where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_groups where id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_player_profiles where id in (${sqlText(ownerProfileId)}::uuid, ${sqlText(targetProfileId)}::uuid);
delete from auth.users where id in (
  ${sqlText(ownerId)}::uuid, ${sqlText(adminId)}::uuid, ${sqlText(targetId)}::uuid, ${sqlText(moderatorId)}::uuid
);
update private.pachanga_conduct_settings set
  attendance_closure_enabled = false, conduct_reports_enabled = false, social_restrictions_enabled = false
where singleton;
`;

try {
  await runOk(setupSql, "conduct concurrency fixture setup");
  const outcomes = [
    { outcome: "played", playerId: "owner-player" },
    { outcome: "unexcused_no_show", playerId: "target-player" },
  ];
  const closeSql = authenticatedSql(ownerId, `select public.close_pachanga_post_match_attendance_v1(
    ${sqlText(groupId)}::uuid, ${sqlText(matchId)}, ${sqlJson(outcomes)}, ${sqlText(closeOperationId)}::uuid, 0,
    ${sqlJson({ clientVersion: "1.0.0+concurrency", sessionId: "device", surface: "concurrency" })}
  )`);
  const closeResults = await Promise.all([
    runSql(closeSql, "close attendance device A"),
    runSql(closeSql, "close attendance device B"),
  ]);
  assert.ok(closeResults.every(({ code }) => code === 0), JSON.stringify(closeResults));
  const closeResponses = closeResults.map((result) => lastJson(result.stdout, result.label));
  assert.deepEqual(closeResponses[0], closeResponses[1]);
  const targetAttendance = closeResponses[0].facts.find(({ playerId }) => playerId === "target-player");
  assert.ok(targetAttendance?.id);
  const receiptEvidence = lastJson(await runOk(`select jsonb_build_object(
    'closures', (select count(*) from private.pachanga_attendance_closures where group_id = ${sqlText(groupId)}::uuid),
    'facts', (select count(*) from private.pachanga_post_match_attendance where group_id = ${sqlText(groupId)}::uuid),
    'receipts', (select count(*) from private.pachanga_conduct_operation_receipts where operation_id = ${sqlText(closeOperationId)}::uuid)
  )`, "attendance receipt evidence"), "attendance receipt evidence");
  assert.deepEqual(receiptEvidence, { closures: 1, facts: 2, receipts: 1 });

  const disputed = lastJson(await runOk(authenticatedSql(targetId, `select public.respond_pachanga_post_match_attendance_v1(
    ${sqlText(targetAttendance.id)}::uuid, 'dispute', 'Concurrent dispute', ${sqlText(disputeOperationId)}::uuid, 1, '{}'
  )`), "dispute attendance"), "dispute attendance");
  assert.equal(disputed.attendance.responseState, "under_review");
  const review = lastJson(await runOk(`select jsonb_build_object('id', reviews.id, 'revision', reviews.revision)
    from private.pachanga_attendance_reviews reviews where reviews.attendance_id = ${sqlText(targetAttendance.id)}::uuid`, "attendance review lookup"), "attendance review lookup");
  const resolveSql = (userId, resolution, correctedOutcome, operationId) => authenticatedSql(userId,
    `select public.resolve_pachanga_attendance_review_v1(
      ${sqlText(review.id)}::uuid, ${sqlText(resolution)}, ${correctedOutcome ? sqlText(correctedOutcome) : "null"},
      'Concurrent resolution', ${sqlText(operationId)}::uuid, ${Number(review.revision)}, '{}'
    )`);
  const resolveResults = await Promise.all([
    runSql(resolveSql(ownerId, "maintain", null, resolveOperationIds[0]), "maintain attendance"),
    runSql(resolveSql(adminId, "correct", "excused_absence", resolveOperationIds[1]), "correct attendance"),
  ]);
  assert.equal(resolveResults.filter(({ code }) => code === 0).length, 1, JSON.stringify(resolveResults));
  assert.equal(resolveResults.filter(({ code }) => code !== 0).length, 1, JSON.stringify(resolveResults));

  const reportSql = (category, operationId) => authenticatedSql(ownerId, `select public.submit_pachanga_conduct_report_v1(
    ${sqlText(targetProfileId)}::uuid, ${sqlText(groupId)}::uuid, ${sqlText(groupId)}::uuid,
    'match', ${sqlText(matchId)}, ${sqlText(category)}, null, ${sqlText(operationId)}::uuid, 1, '{}'
  )`);
  const replayReports = await Promise.all([
    runSql(reportSql("abusive_behavior", reportReplayOperationId), "report replay A"),
    runSql(reportSql("abusive_behavior", reportReplayOperationId), "report replay B"),
  ]);
  assert.ok(replayReports.every(({ code }) => code === 0), JSON.stringify(replayReports));
  assert.deepEqual(lastJson(replayReports[0].stdout, "report replay A"), lastJson(replayReports[1].stdout, "report replay B"));

  const reportRace = await Promise.all([
    runSql(reportSql("harassment", reportRaceOperationIds[0]), "report unique A"),
    runSql(reportSql("harassment", reportRaceOperationIds[1]), "report unique B"),
  ]);
  assert.equal(reportRace.filter(({ code }) => code === 0).length, 1, JSON.stringify(reportRace));
  assert.equal(reportRace.filter(({ code }) => code !== 0).length, 1, JSON.stringify(reportRace));
  assert.match(reportRace.find(({ code }) => code !== 0).stderr, /already exists|duplicate/i);

  const abusiveCase = lastJson(await runOk(`select jsonb_build_object('reference', cases.opaque_reference, 'revision', cases.revision)
    from private.pachanga_moderation_cases cases where cases.target_profile_id = ${sqlText(targetProfileId)}::uuid
      and cases.category = 'abusive_behavior'`, "abusive case lookup"), "abusive case lookup");
  const moderatorMetadata = { pachangas_security_role: "moderator" };
  const reviewCase = lastJson(await runOk(authenticatedSql(moderatorId, `select public.moderate_pachanga_conduct_case_v1(
    ${sqlText(abusiveCase.reference)}::uuid, 'start_review', null, '{}', null, ${sqlText(randomUUID())}::uuid,
    ${Number(abusiveCase.revision)}, '{}'
  )`, moderatorMetadata), "start case review"), "start case review");
  const confirmedCase = lastJson(await runOk(authenticatedSql(moderatorId, `select public.moderate_pachanga_conduct_case_v1(
    ${sqlText(abusiveCase.reference)}::uuid, 'confirm', 'Concurrent evidence', '{}', null, ${sqlText(randomUUID())}::uuid,
    ${Number(reviewCase.confirmedRevision)}, '{}'
  )`, moderatorMetadata), "confirm case"), "confirm case");
  const warningSql = (operationId) => authenticatedSql(moderatorId, `select public.moderate_pachanga_conduct_case_v1(
    ${sqlText(abusiveCase.reference)}::uuid, 'issue_warning', 'Concurrent warning', '{}', null,
    ${sqlText(operationId)}::uuid, ${Number(confirmedCase.confirmedRevision)}, '{}'
  )`, moderatorMetadata);
  const warningResults = await Promise.all([
    runSql(warningSql(warningOperationIds[0]), "warning A"),
    runSql(warningSql(warningOperationIds[1]), "warning B"),
  ]);
  assert.equal(warningResults.filter(({ code }) => code === 0).length, 1, JSON.stringify(warningResults));
  assert.equal(warningResults.filter(({ code }) => code !== 0).length, 1, JSON.stringify(warningResults));
  assert.equal(Number(await runOk(`select count(*) from private.pachanga_conduct_warnings where case_id = (
    select id from private.pachanga_moderation_cases where opaque_reference = ${sqlText(abusiveCase.reference)}::uuid
  )`, "warning convergence")), 1);

  const harassmentCase = lastJson(await runOk(`select jsonb_build_object('reference', cases.opaque_reference, 'revision', cases.revision)
    from private.pachanga_moderation_cases cases where cases.target_profile_id = ${sqlText(targetProfileId)}::uuid
      and cases.category = 'harassment'`, "harassment case lookup"), "harassment case lookup");
  const confirmedHarassment = lastJson(await runOk(authenticatedSql(moderatorId, `select public.moderate_pachanga_conduct_case_v1(
    ${sqlText(harassmentCase.reference)}::uuid, 'confirm', 'Restriction case confirmed', '{}', null,
    ${sqlText(randomUUID())}::uuid, ${Number(harassmentCase.revision)}, '{}'
  )`, moderatorMetadata), "confirm restriction case"), "confirm restriction case");
  const restricted = lastJson(await runOk(authenticatedSql(moderatorId, `select public.moderate_pachanga_conduct_case_v1(
    ${sqlText(harassmentCase.reference)}::uuid, 'apply_restrictions', 'Explicit finite restriction', array['public_market'], 7,
    ${sqlText(randomUUID())}::uuid, ${Number(confirmedHarassment.confirmedRevision)}, '{}'
  )`, moderatorMetadata), "apply expiring restriction"), "apply expiring restriction");
  const restrictionReference = restricted.actions[0].reference;
  await runOk(`update private.pachanga_social_restrictions set effective_until = clock_timestamp() - interval '1 second'
    where opaque_reference = ${sqlText(restrictionReference)}::uuid`, "prepare restriction expiry race");
  const appealSql = authenticatedSql(targetId, `select public.appeal_pachanga_conduct_action_v1(
    ${sqlText(restrictionReference)}::uuid, 'restriction', 'Concurrent appeal', ${sqlText(appealOperationId)}::uuid, 1, '{}'
  )`);
  const expirySql = `begin; set local role service_role; select public.run_pachanga_social_restriction_expiry_v1(${sqlText(targetId)}::uuid); commit;`;
  const appealExpiryResults = await Promise.all([
    runSql(appealSql, "appeal expiring restriction"),
    runSql(expirySql, "expire appealed restriction"),
  ]);
  assert.ok(appealExpiryResults.some(({ code }) => code === 0), JSON.stringify(appealExpiryResults));
  const restrictionState = await runOk(`select state from private.pachanga_social_restrictions
    where opaque_reference = ${sqlText(restrictionReference)}::uuid`, "appeal expiry convergence");
  assert.ok(["appealed", "expired"].includes(restrictionState), restrictionState);
  assert.equal(Number(await runOk(`select count(*) from private.pachanga_social_restrictions
    where target_user_id = ${sqlText(targetId)}::uuid and state = 'active'`, "active restriction convergence")), 0);

  process.stdout.write(`${JSON.stringify({
    appealExpiryState: restrictionState,
    attendanceIdempotentReplay: true,
    attendanceResolutionWinner: resolveResults.find(({ code }) => code === 0).label,
    conductReportIdempotentReplay: true,
    duplicateReportWinner: reportRace.find(({ code }) => code === 0).label,
    status: "PASS",
    warningWinner: warningResults.find(({ code }) => code === 0).label,
  }, null, 2)}\n`);
} finally {
  await runOk(cleanupSql, "conduct concurrency fixture cleanup");
}
