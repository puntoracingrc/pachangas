import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.PACHANGAS_SYNTHETIC_DB_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.CONDUCT_V1_1_SQL_TIMEOUT_MS || 30_000);
if (!databaseUrl) throw new Error("PACHANGAS_SYNTHETIC_DB_URL is required");

const sqlText = (value) => `'${String(value).replaceAll("'", "''")}'`;

function runSql(sql, label) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; child.kill("SIGKILL"); }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => {
      clearTimeout(timeout);
      resolve({ code: timedOut ? 124 : code, label, stderr: stderr.trim(), stdout: stdout.trim() });
    });
    child.stdin.end(sql);
  });
}

async function runOk(sql, label) {
  const result = await runSql(sql, label);
  assert.equal(result.code, 0, `${label} failed:\n${result.stderr}`);
  return result.stdout;
}

function moderatorSql(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${sqlText(userId)}, true);
select set_config('request.jwt.claims', ${sqlText(JSON.stringify({ sub: userId, app_metadata: { pachangas_security_role: "moderator" } }))}, true);
${statement};
commit;`;
}

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no JSON`);
  return JSON.parse(line);
}

const targetUserId = randomUUID();
const reporterUserIds = [randomUUID(), randomUUID(), randomUUID()];
const moderatorId = randomUUID();
const profileId = randomUUID();
const groupIds = [randomUUID(), randomUUID(), randomUUID()];
const caseId = randomUUID();
const caseReference = randomUUID();
const clusterIds = [randomUUID(), randomUUID(), randomUUID()];
const reportIds = [randomUUID(), randomUUID(), randomUUID()];
const reportReferences = [randomUUID(), randomUUID(), randomUUID()];
const operationIds = [randomUUID(), randomUUID(), randomUUID()];

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(targetUserId)}::uuid, ${sqlText(`triage-target-${targetUserId}@example.test`)}),
  (${sqlText(reporterUserIds[0])}::uuid, ${sqlText(`triage-r1-${reporterUserIds[0]}@example.test`)}),
  (${sqlText(reporterUserIds[1])}::uuid, ${sqlText(`triage-r2-${reporterUserIds[1]}@example.test`)}),
  (${sqlText(reporterUserIds[2])}::uuid, ${sqlText(`triage-r3-${reporterUserIds[2]}@example.test`)}),
  (${sqlText(moderatorId)}::uuid, ${sqlText(`triage-m-${moderatorId}@example.test`)});
insert into public.pachanga_player_profiles(id, user_id, source_player_id, display_name)
values (${sqlText(profileId)}::uuid, ${sqlText(targetUserId)}::uuid, ${sqlText(`triage-${profileId}`)}, 'Concurrent triage target');
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${sqlText(groupIds[0])}::uuid, ${sqlText(reporterUserIds[0])}::uuid, 'Triage concurrent one', ${sqlText(`TC${groupIds[0].replaceAll("-", "").slice(0, 8)}`)}, '{}'::jsonb),
  (${sqlText(groupIds[1])}::uuid, ${sqlText(reporterUserIds[1])}::uuid, 'Triage concurrent two', ${sqlText(`TC${groupIds[1].replaceAll("-", "").slice(0, 8)}`)}, '{}'::jsonb),
  (${sqlText(groupIds[2])}::uuid, ${sqlText(reporterUserIds[2])}::uuid, 'Triage concurrent three', ${sqlText(`TC${groupIds[2].replaceAll("-", "").slice(0, 8)}`)}, '{}'::jsonb);
insert into private.pachanga_moderation_cases(
  id, opaque_reference, target_profile_id, target_user_id, source_type, category
) values (
  ${sqlText(caseId)}::uuid, ${sqlText(caseReference)}::uuid, ${sqlText(profileId)}::uuid,
  ${sqlText(targetUserId)}::uuid, 'conduct_report', 'abusive_behavior'
);
insert into private.pachanga_report_source_clusters(id, case_id, source_group_id, context_kind, context_id) values
  (${sqlText(clusterIds[0])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(groupIds[0])}::uuid, 'match', 'concurrent-1'),
  (${sqlText(clusterIds[1])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(groupIds[1])}::uuid, 'match', 'concurrent-2'),
  (${sqlText(clusterIds[2])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(groupIds[2])}::uuid, 'match', 'concurrent-3');
insert into private.pachanga_conduct_reports(
  id, opaque_reference, case_id, source_cluster_id, reporter_user_id, reporter_group_id,
  target_profile_id, target_user_id, target_group_id, context_kind, context_id,
  context_revision, category, operation_id
) values
  (${sqlText(reportIds[0])}::uuid, ${sqlText(reportReferences[0])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(clusterIds[0])}::uuid,
   ${sqlText(reporterUserIds[0])}::uuid, ${sqlText(groupIds[0])}::uuid, ${sqlText(profileId)}::uuid, ${sqlText(targetUserId)}::uuid,
   ${sqlText(groupIds[0])}::uuid, 'match', 'concurrent-1', 1, 'abusive_behavior', ${sqlText(randomUUID())}::uuid),
  (${sqlText(reportIds[1])}::uuid, ${sqlText(reportReferences[1])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(clusterIds[1])}::uuid,
   ${sqlText(reporterUserIds[1])}::uuid, ${sqlText(groupIds[1])}::uuid, ${sqlText(profileId)}::uuid, ${sqlText(targetUserId)}::uuid,
   ${sqlText(groupIds[1])}::uuid, 'match', 'concurrent-2', 1, 'abusive_behavior', ${sqlText(randomUUID())}::uuid),
  (${sqlText(reportIds[2])}::uuid, ${sqlText(reportReferences[2])}::uuid, ${sqlText(caseId)}::uuid, ${sqlText(clusterIds[2])}::uuid,
   ${sqlText(reporterUserIds[2])}::uuid, ${sqlText(groupIds[2])}::uuid, ${sqlText(profileId)}::uuid, ${sqlText(targetUserId)}::uuid,
   ${sqlText(groupIds[2])}::uuid, 'match', 'concurrent-3', 1, 'abusive_behavior', ${sqlText(randomUUID())}::uuid);
select private.pachanga_recount_conduct_case_v1_1(${sqlText(caseId)}::uuid);
select private.pachanga_recompute_conduct_triage_v1_1(${sqlText(caseId)}::uuid);
`;

const cleanupSql = `
delete from private.pachanga_moderation_events where case_id in (select id from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid);
delete from private.pachanga_moderation_case_relations where source_case_id in (select id from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid)
  or target_case_id in (select id from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid);
delete from private.pachanga_conduct_reports where target_user_id = ${sqlText(targetUserId)}::uuid;
delete from private.pachanga_report_source_clusters where case_id in (select id from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid);
delete from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid;
delete from private.pachanga_conduct_operation_receipts where actor_user_id = ${sqlText(moderatorId)}::uuid;
delete from public.pachanga_groups where id = any(array[${groupIds.map((id) => `${sqlText(id)}::uuid`).join(",")}]);
delete from public.pachanga_player_profiles where id = ${sqlText(profileId)}::uuid;
delete from auth.users where id = any(array[${[targetUserId, ...reporterUserIds, moderatorId].map((id) => `${sqlText(id)}::uuid`).join(",")}]);
`;

try {
  await runOk(setupSql, "triage concurrency fixture setup");
  const revision = Number(await runOk(`select revision from private.pachanga_moderation_cases where id = ${sqlText(caseId)}::uuid`, "source revision"));
  const splitSql = moderatorSql(moderatorId, `select public.split_pachanga_conduct_case_v1_1(
    ${sqlText(caseReference)}::uuid, array[${sqlText(reportReferences[2])}::uuid],
    ${sqlText(operationIds[0])}::uuid, ${revision}, '{}'
  )`);
  const splitResults = await Promise.all([
    runSql(splitSql, "split device A"),
    runSql(splitSql, "split device B"),
  ]);
  assert.ok(splitResults.every(({ code }) => code === 0), JSON.stringify(splitResults));
  const splitResponses = splitResults.map((result) => lastJson(result.stdout, result.label));
  assert.deepEqual(splitResponses[0], splitResponses[1]);

  const sourceAfterSplit = JSON.parse(await runOk(`select jsonb_build_object(
    'reference', opaque_reference, 'revision', revision, 'reports', report_count
  ) from private.pachanga_moderation_cases where opaque_reference = ${sqlText(caseReference)}::uuid`, "source after split"));
  const splitAfter = JSON.parse(await runOk(`select jsonb_build_object(
    'reference', opaque_reference, 'revision', revision, 'reports', report_count
  ) from private.pachanga_moderation_cases where opaque_reference = ${sqlText(splitResponses[0].splitCaseReference)}::uuid`, "split branch"));
  assert.equal(sourceAfterSplit.reports, 2);
  assert.equal(splitAfter.reports, 1);

  const mergeSql = (operationId) => moderatorSql(moderatorId, `select public.merge_pachanga_conduct_cases_v1_1(
    ${sqlText(splitAfter.reference)}::uuid, ${sqlText(sourceAfterSplit.reference)}::uuid,
    ${sqlText(operationId)}::uuid, ${splitAfter.revision}, ${sourceAfterSplit.revision}, '{}'
  )`);
  const mergeResults = await Promise.all([
    runSql(mergeSql(operationIds[1]), "merge device A"),
    runSql(mergeSql(operationIds[2]), "merge device B"),
  ]);
  assert.equal(mergeResults.filter(({ code }) => code === 0).length, 1, JSON.stringify(mergeResults));
  assert.equal(mergeResults.filter(({ code }) => code !== 0).length, 1, JSON.stringify(mergeResults));
  assert.match(mergeResults.find(({ code }) => code !== 0).stderr, /revision is newer/i);

  const canonical = JSON.parse(await runOk(`select jsonb_build_object(
    'activeCases', count(*) filter (where state <> 'closed'),
    'closedCases', count(*) filter (where state = 'closed'),
    'reports', sum(report_count),
    'lineage', (select count(*) from private.pachanga_moderation_case_relations relations
      where relations.source_case_id in (select id from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid))
  ) from private.pachanga_moderation_cases where target_user_id = ${sqlText(targetUserId)}::uuid`, "canonical convergence"));
  assert.deepEqual(canonical, { activeCases: 1, closedCases: 1, reports: 3, lineage: 2 });
  console.log(JSON.stringify({ canonical, concurrentMergeAccepted: 1, concurrentMergeRejected: 1, splitReplayIdentical: true }));
} finally {
  await runOk(cleanupSql, "triage concurrency fixture cleanup");
}
