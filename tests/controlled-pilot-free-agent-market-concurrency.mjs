import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.FREE_AGENT_MARKET_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.FREE_AGENT_MARKET_SQL_TIMEOUT_MS || 20_000);

if (!databaseUrl) throw new Error("FREE_AGENT_MARKET_DATABASE_URL is required");
if (!/localhost|127\.0\.0\.1/.test(databaseUrl) && process.env.FREE_AGENT_MARKET_ALLOW_REMOTE !== "1") {
  throw new Error("Set FREE_AGENT_MARKET_ALLOW_REMOTE=1 only for an explicitly disposable database");
}

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

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no JSON`);
  return JSON.parse(line);
}

function authenticatedSql(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  ${sqlText(JSON.stringify({ sub: userId, role: "authenticated", is_anonymous: false }))},
  true
);
${statement};
commit;
`;
}

const userId = randomUUID();
const createOperation = randomUUID();
const publishOperations = [randomUUID(), randomUUID()];

const settings = lastJson(await runOk(`
select jsonb_build_object(
  'foundation', social_profile_foundation_enabled,
  'write', social_profile_independent_write_enabled
)
from private.pachanga_social_team_settings_v1 where singleton;
`, "read social settings"), "read social settings");

const setupSql = `
update private.pachanga_social_team_settings_v1 set
  social_profile_foundation_enabled = true,
  social_profile_independent_write_enabled = true;
insert into auth.users(id, email)
values (${sqlText(userId)}::uuid, ${sqlText(`free-agent-concurrency-${userId}@example.test`)});
${authenticatedSql(userId, `select public.command_pachanga_social_profile_v1(
  'profile.create',
  0,
  ${sqlText(createOperation)}::uuid,
  '{"displayName":"Concurrent Free Agent","primaryPosition":"Defensa central","preferredModality":"futbol7","generalArea":"Madrid","usualDays":["S"],"approximateTime":"16:00-20:00"}'::jsonb,
  '{"surface":"free-agent-concurrency"}'::jsonb
)`)}
`;

const cleanupSql = `
begin;
create temporary table free_agent_market_cleanup_profiles on commit drop as
select id from public.pachanga_market_profiles where user_id = ${sqlText(userId)}::uuid;
delete from public.pachanga_social_invalidations_v1 where audience_user_id = ${sqlText(userId)}::uuid;
alter table public.pachanga_market_profiles disable trigger pachanga_market_profiles_invalidate_v1;
delete from public.pachanga_market_profiles where user_id = ${sqlText(userId)}::uuid;
alter table public.pachanga_market_profiles enable trigger pachanga_market_profiles_invalidate_v1;
delete from public.pachanga_market_invalidations_v1
where profile_id in (select id from free_agent_market_cleanup_profiles);
alter table private.pachanga_social_operation_receipts_v1 disable trigger user;
alter table private.pachanga_social_events_v1 disable trigger user;
alter table private.pachanga_social_player_profile_revisions_v1 disable trigger user;
delete from private.pachanga_social_operation_receipts_v1 where actor_id = ${sqlText(userId)}::uuid;
delete from private.pachanga_social_events_v1 where actor_id = ${sqlText(userId)}::uuid;
delete from private.pachanga_social_player_profile_revisions_v1 where user_id = ${sqlText(userId)}::uuid;
alter table private.pachanga_social_operation_receipts_v1 enable trigger user;
alter table private.pachanga_social_events_v1 enable trigger user;
alter table private.pachanga_social_player_profile_revisions_v1 enable trigger user;
delete from public.pachanga_social_player_profiles_v1 where user_id = ${sqlText(userId)}::uuid;
delete from auth.users where id = ${sqlText(userId)}::uuid;
update private.pachanga_social_team_settings_v1 set
  social_profile_foundation_enabled = ${settings.foundation ? "true" : "false"},
  social_profile_independent_write_enabled = ${settings.write ? "true" : "false"};
commit;
`;

try {
  await runOk(setupSql, "free-agent concurrency fixture setup");

  const commands = publishOperations.map((operationId) => authenticatedSql(
    userId,
    `select public.command_pachanga_free_agent_market_v1(
      'market.publish',
      1,
      ${sqlText(operationId)}::uuid,
      '{}'::jsonb,
      '{"surface":"free-agent-concurrency"}'::jsonb
    )::text`,
  ));
  const attempts = await Promise.all(commands.map((sql, index) => runSql(sql, `device ${index + 1}`)));
  const winners = attempts.filter((attempt) => attempt.code === 0);
  const stale = attempts.filter((attempt) => attempt.code !== 0 && /STALE_PROFILE_REVISION|PT409/i.test(attempt.stderr));
  assert.equal(winners.length, 1, "Exactly one concurrent publication must win");
  assert.equal(stale.length, 1, "The other device must receive an explicit stale revision conflict");

  const evidence = lastJson(await runOk(`
select jsonb_build_object(
  'activeProfiles', (select count(*) from public.pachanga_market_profiles where user_id = ${sqlText(userId)}::uuid and active),
  'profileRevision', (select revision from public.pachanga_social_player_profiles_v1 where user_id = ${sqlText(userId)}::uuid),
  'publishReceipts', (select count(*) from private.pachanga_social_operation_receipts_v1 where actor_id = ${sqlText(userId)}::uuid and action = 'market.publish'),
  'publishEvents', (select count(*) from private.pachanga_social_events_v1 where actor_id = ${sqlText(userId)}::uuid and event_kind = 'market.publish.confirmed')
);
`, "free-agent convergence evidence"), "free-agent convergence evidence");
  assert.deepEqual(evidence, {
    activeProfiles: 1,
    profileRevision: 2,
    publishEvents: 1,
    publishReceipts: 1,
  });

  const winningOperation = publishOperations[attempts.findIndex((attempt) => attempt.code === 0)];
  const replay = await runOk(authenticatedSql(
    userId,
    `select public.command_pachanga_free_agent_market_v1(
      'market.publish', 1, ${sqlText(winningOperation)}::uuid, '{}'::jsonb,
      '{"surface":"free-agent-concurrency"}'::jsonb
    )::text`,
  ), "winning operation replay");
  assert.equal(lastJson(replay, "winning operation replay").revision, 2);

  const replayEvidence = lastJson(await runOk(`
select jsonb_build_object(
  'revision', (select revision from public.pachanga_social_player_profiles_v1 where user_id = ${sqlText(userId)}::uuid),
  'receipts', (select count(*) from private.pachanga_social_operation_receipts_v1 where actor_id = ${sqlText(userId)}::uuid and action = 'market.publish')
);
`, "free-agent replay evidence"), "free-agent replay evidence");
  assert.deepEqual(replayEvidence, { receipts: 1, revision: 2 });

  console.log(JSON.stringify({ concurrentPublish: "PASS", exactReplay: "PASS", ...evidence }));
} finally {
  await runOk(cleanupSql, "free-agent concurrency fixture cleanup");
}
