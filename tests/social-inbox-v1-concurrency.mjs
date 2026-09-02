import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.SOCIAL_INBOX_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.SOCIAL_INBOX_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("SOCIAL_INBOX_DATABASE_URL is required");

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

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

function holdActorLock(userId) {
  return new Promise((resolve, reject) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const timeout = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`actor lock fixture timed out: ${stderr}`));
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      if (!settled && stdout.includes("LOCKED")) {
        settled = true;
        resolve(child);
      }
    });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => {
      clearTimeout(timeout);
      if (!settled) reject(new Error(`actor lock fixture exited ${code}: ${stderr}`));
    });
    child.stdin.end(`
begin;
select pg_advisory_xact_lock(hashtextextended(${sqlText(userId)}, 0));
select 'LOCKED';
select pg_sleep(1.5);
commit;
`);
  });
}

const userId = randomUUID();
const notificationId = randomUUID();
const operationId = randomUUID();
const dedupeKey = `social-inbox-concurrency:${randomUUID()}`;

const setupSql = `
insert into auth.users(id, email)
values (${sqlText(userId)}::uuid, ${sqlText(`inbox-concurrency-${userId}@example.test`)});
insert into public.pachanga_user_notifications(
  id, recipient_user_id, kind, category, title, body, action_url,
  payload, dedupe_key, priority, visible_in_app
) values (
  ${sqlText(notificationId)}::uuid,
  ${sqlText(userId)}::uuid,
  'team_shield_updated', 'group', 'Escudo actualizado',
  'La identidad del equipo ha cambiado.', '/equipo',
  jsonb_build_object('groupId', ${sqlText(randomUUID())}),
  ${sqlText(dedupeKey)}, 'normal', true
);
`;

const cleanupSql = `
delete from private.pachanga_social_inbox_command_receipts_v1
where operation_id = ${sqlText(operationId)}::uuid;
delete from public.pachanga_user_notifications
where id = ${sqlText(notificationId)}::uuid;
delete from auth.users where id = ${sqlText(userId)}::uuid;
`;

try {
  await runOk(setupSql, "social Inbox concurrency fixture setup");
  await holdActorLock(userId);

  const commandSql = authenticatedSql(
    userId,
    `select public.command_pachanga_social_inbox_v1(
      'inbox.mark_read',
      ${sqlText(notificationId)}::uuid,
      ${sqlText(operationId)}::uuid,
      1,
      null
    )`,
  );
  const results = await Promise.all([
    runSql(commandSql, "same operation device A"),
    runSql(commandSql, "same operation device B"),
  ]);

  for (const result of results) assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  const responses = results.map((result) => lastJson(result.stdout, result.label));
  assert.deepEqual(responses[0], responses[1], "Concurrent replays must return the exact same receipt");

  const evidence = lastJson(await runOk(`
select jsonb_build_object(
  'read', read_at is not null,
  'revision', revision,
  'receiptCount', (
    select count(*)
    from private.pachanga_social_inbox_command_receipts_v1
    where operation_id = ${sqlText(operationId)}::uuid
  )
)
from public.pachanga_user_notifications
where id = ${sqlText(notificationId)}::uuid;
`, "social Inbox convergence evidence"), "social Inbox convergence evidence");
  assert.equal(evidence.read, true);
  assert.equal(evidence.revision, 2, "The notification must be mutated exactly once");
  assert.equal(evidence.receiptCount, 1, "The operation must retain exactly one receipt");
  console.log(JSON.stringify({ concurrentReplay: "PASS", ...evidence }));
} finally {
  await runOk(cleanupSql, "social Inbox concurrency fixture cleanup");
}
