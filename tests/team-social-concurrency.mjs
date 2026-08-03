import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.TEAM_SOCIAL_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const sqlTimeoutMs = Number(process.env.TEAM_SOCIAL_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("TEAM_SOCIAL_DATABASE_URL is required for the social concurrency test");

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlJson(value) {
  return `${sqlText(JSON.stringify(value))}::jsonb`;
}

function runSql(sql, label) {
  return new Promise((resolve, reject) => {
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
    }, sqlTimeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => {
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timeout);
      resolve({
        code: timedOut ? 124 : code,
        label,
        stderr: [stderr.trim(), timedOut ? `SQL timed out after ${sqlTimeoutMs}ms` : ""].filter(Boolean).join("\n"),
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

function authenticatedSql(userId, statement) {
  return `
begin;
set local role authenticated;
set local "request.jwt.claim.sub" = ${sqlText(userId)};
${statement};
commit;
`;
}

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} did not return JSON`);
  return JSON.parse(line);
}

const senderUserId = randomUUID();
const receiverUserId = randomUUID();
const senderGroupId = randomUUID();
const receiverGroupId = randomUUID();
const createOperationId = randomUUID();
const acceptOperationId = randomUUID();
const rejectOperationId = randomUUID();
const receiverCode = `SC${receiverGroupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`;
let challengeId = null;

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(senderUserId)}::uuid, ${sqlText(`social-${senderUserId}@example.test`)}),
  (${sqlText(receiverUserId)}::uuid, ${sqlText(`social-${receiverUserId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${sqlText(senderGroupId)}::uuid, ${sqlText(senderUserId)}::uuid, 'Concurrent sender',
   ${sqlText(`SC${senderGroupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)},
   ${sqlJson({ activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] })}),
  (${sqlText(receiverGroupId)}::uuid, ${sqlText(receiverUserId)}::uuid, 'Concurrent receiver',
   ${sqlText(receiverCode)},
   ${sqlJson({ activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] })});
insert into public.pachanga_group_members(group_id, user_id, role) values
  (${sqlText(senderGroupId)}::uuid, ${sqlText(senderUserId)}::uuid, 'owner'),
  (${sqlText(receiverGroupId)}::uuid, ${sqlText(receiverUserId)}::uuid, 'owner');
`;

const cleanupSql = `
delete from public.pachanga_team_challenge_events where challenge_id in (
  select id from public.pachanga_team_challenges
  where sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_team_social_operation_receipts
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_team_challenges
where sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
   or receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_known_opponents
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
   or opponent_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_group_members
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_groups
where id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from auth.users where id in (${sqlText(senderUserId)}::uuid, ${sqlText(receiverUserId)}::uuid);
`;

try {
  await runOk(setupSql, "social concurrency fixture setup");
  const createdOutput = await runOk(
    authenticatedSql(
      senderUserId,
      `select public.create_pachanga_team_challenge_authoritative(
        ${sqlText(senderGroupId)}::uuid,
        ${sqlText(receiverCode)},
        clock_timestamp() + interval '7 days',
        'futbol7', 'Concurrent field', 'Concurrent address', null, null, null,
        ${sqlText(createOperationId)}::uuid, 0,
        ${sqlJson({ sessionId: "sender-device", surface: "concurrency-test" })}
      )`,
    ),
    "create concurrent challenge",
  );
  const created = lastJson(createdOutput, "create concurrent challenge");
  challengeId = created.challenges[0]?.id;
  assert.ok(challengeId, "The challenge creation did not return its canonical id");

  const actionSql = (action, operationId, sessionId) => authenticatedSql(
    receiverUserId,
    `select public.respond_pachanga_team_challenge_authoritative(
      ${sqlText(receiverGroupId)}::uuid,
      ${sqlText(challengeId)}::uuid,
      ${sqlText(action)}, null, null, null, null, null, null, null,
      ${sqlText(operationId)}::uuid, 1,
      ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );

  const results = await Promise.all([
    runSql(actionSql("accept", acceptOperationId, "receiver-device-a"), "accept"),
    runSql(actionSql("reject", rejectOperationId, "receiver-device-b"), "reject"),
  ]);
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `Exactly one concurrent response must win: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `Exactly one stale response must fail: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, /Challenge revision is newer|could not serialize|could not obtain lock/i);

  const winner = lastJson(winners[0].stdout, "winning response");
  assert.equal(winner.challenges[0]?.revision, 2);
  assert.ok(["accepted", "rejected"].includes(winner.challenges[0]?.status));

  const [senderSnapshotOutput, receiverSnapshotOutput] = await Promise.all([
    runOk(
      authenticatedSql(senderUserId, `select public.get_pachanga_team_social_snapshot(${sqlText(senderGroupId)}::uuid)`),
      "sender canonical snapshot",
    ),
    runOk(
      authenticatedSql(receiverUserId, `select public.get_pachanga_team_social_snapshot(${sqlText(receiverGroupId)}::uuid)`),
      "receiver canonical snapshot",
    ),
  ]);
  const senderSnapshot = lastJson(senderSnapshotOutput, "sender canonical snapshot");
  const receiverSnapshot = lastJson(receiverSnapshotOutput, "receiver canonical snapshot");
  assert.equal(senderSnapshot.challenges[0]?.id, challengeId);
  assert.equal(receiverSnapshot.challenges[0]?.id, challengeId);
  assert.equal(senderSnapshot.challenges[0]?.status, receiverSnapshot.challenges[0]?.status);
  assert.equal(senderSnapshot.challenges[0]?.revision, 2);
  assert.equal(receiverSnapshot.challenges[0]?.revision, 2);
  assert.equal(senderSnapshot.serverSequence, receiverSnapshot.serverSequence);

  const evidence = await runOk(
    `select jsonb_build_object(
      'events', (select count(*) from public.pachanga_team_challenge_events where challenge_id = ${sqlText(challengeId)}::uuid),
      'receipts', (select count(*) from public.pachanga_team_social_operation_receipts where operation_id in (
        ${sqlText(createOperationId)}::uuid, ${sqlText(acceptOperationId)}::uuid, ${sqlText(rejectOperationId)}::uuid
      ))
    )`,
    "concurrency evidence",
  );
  assert.deepEqual(lastJson(evidence, "concurrency evidence"), { events: 2, receipts: 2 });
} finally {
  await runOk(cleanupSql, "social concurrency fixture cleanup");
}

console.error("[team-social concurrency] passed");
