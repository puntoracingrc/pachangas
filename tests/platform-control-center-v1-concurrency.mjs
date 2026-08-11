import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.PLATFORM_ADMIN_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const timeoutMs = Number(process.env.PLATFORM_ADMIN_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("PLATFORM_ADMIN_DATABASE_URL is required");

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
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
    }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => { clearTimeout(timeout); reject(error); });
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

function authenticated(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ sub: userId, role: "authenticated" }))}, true);
${statement};
commit;
`;
}

function service(statement) {
  return `
begin;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
${statement};
commit;
`;
}

function lastJson(result) {
  const line = result.stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${result.label} returned no JSON`);
  return JSON.parse(line);
}

async function sameCanonical(label, sql) {
  const results = await Promise.all([
    runSql(sql, `${label}:device-a`),
    runSql(sql, `${label}:device-b`),
  ]);
  for (const result of results) assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  assert.deepEqual(lastJson(results[0]), lastJson(results[1]), `${label} must return one canonical response`);
  return lastJson(results[0]);
}

async function oneWinner(label, statements) {
  const results = await Promise.all(statements.map(({ client, sql }) => runSql(sql, `${label}:${client}`)));
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must accept exactly one operation: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must reject exactly one operation: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, /changed before saving|changed before sending|Feature flag changed/i, `${label} must reject a stale revision explicitly`);
  return { response: lastJson(winners[0]), winner: winners[0].label };
}

const ownerId = randomUUID();
const targetId = randomUUID();
const roleTargetId = randomUUID();
const stateReplayOperation = randomUUID();
const stateRaceOperations = [randomUUID(), randomUUID()];
const roleRaceOperations = [randomUUID(), randomUUID()];
const flagRaceOperations = [randomUUID(), randomUUID()];
const telemetryOperation = randomUUID();
const incidentRaceOperations = [randomUUID(), randomUUID()];
const announcementCreateOperation = randomUUID();
const announcementSendOperation = randomUUID();

const setup = `
insert into auth.users(id, email) values
  (${quote(ownerId)}::uuid, ${quote(`owner-${ownerId}@example.test`)}),
  (${quote(targetId)}::uuid, ${quote(`target-${targetId}@example.test`)}),
  (${quote(roleTargetId)}::uuid, ${quote(`role-${roleTargetId}@example.test`)});
insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (${quote(ownerId)}::uuid, 'platform_owner', true);
`;

let flagBefore;
try {
  await runOk(setup, "setup");
  flagBefore = (await runOk(
    "select attendance_closure_enabled::text || '|' || platform_revision::text from private.pachanga_conduct_settings where singleton;",
    "read flag baseline",
  )).split("|");

  const sameState = await sameCanonical("same user-state operation", authenticated(ownerId, `
    select public.set_pachanga_platform_user_state_v1(
      ${quote(targetId)}::uuid, 'banned', null, 0,
      ${quote(stateReplayOperation)}::uuid, 'Concurrent idempotency test'
    )
  `));
  assert.equal(sameState.revision, 1);
  assert.equal(await runOk(
    `select count(*) from private.pachanga_platform_admin_action_ledger where operation_id = ${quote(stateReplayOperation)}::uuid;`,
    "state replay ledger count",
  ), "1");

  const stateRace = await oneWinner("different user-state operations", [
    {
      client: "device-a",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_user_state_v1(
        ${quote(targetId)}::uuid, 'active', null, 1,
        ${quote(stateRaceOperations[0])}::uuid, 'Concurrent state A'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_user_state_v1(
        ${quote(targetId)}::uuid, 'suspended', clock_timestamp() + interval '1 day', 1,
        ${quote(stateRaceOperations[1])}::uuid, 'Concurrent state B'
      )`),
    },
  ]);
  assert.equal(stateRace.response.revision, 2);

  const roleRace = await oneWinner("new role operations", [
    {
      client: "device-a",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_role_v1(
        ${quote(roleTargetId)}::uuid, 'support', true, 0,
        ${quote(roleRaceOperations[0])}::uuid, 'Concurrent role A'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_role_v1(
        ${quote(roleTargetId)}::uuid, 'moderator', true, 0,
        ${quote(roleRaceOperations[1])}::uuid, 'Concurrent role B'
      )`),
    },
  ]);
  assert.equal(roleRace.response.revision, 1);

  const [flagEnabled, flagRevision] = flagBefore;
  const nextFlag = flagEnabled !== "true";
  const flagRace = await oneWinner("feature flag operations", [
    {
      client: "device-a",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_flag_v1(
        'attendance', ${nextFlag}, ${flagRevision},
        ${quote(flagRaceOperations[0])}::uuid, 'Concurrent flag A'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_flag_v1(
        'attendance', ${!nextFlag}, ${flagRevision},
        ${quote(flagRaceOperations[1])}::uuid, 'Concurrent flag B'
      )`),
    },
  ]);
  assert.equal(flagRace.response.revision, Number(flagRevision) + 1);

  await runOk(service(`select public.record_pachanga_client_error_v1(
    ${quote("b".repeat(64))}, '/admin', '2.0.0+concurrency', 'render', 'Chrome', 'macOS',
    ${quote(telemetryOperation)}::uuid
  )`), "telemetry fixture");
  const incidentRace = await oneWinner("incident operations", [
    {
      client: "device-a",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_incident_v1(
        ${quote("b".repeat(64))}, 'investigating', 'Device A', 0,
        ${quote(incidentRaceOperations[0])}::uuid, 'Concurrent incident A'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(ownerId, `select public.set_pachanga_platform_incident_v1(
        ${quote("b".repeat(64))}, 'ignored', 'Device B', 0,
        ${quote(incidentRaceOperations[1])}::uuid, 'Concurrent incident B'
      )`),
    },
  ]);
  assert.equal(incidentRace.response.revision, 1);

  const announcement = JSON.parse((await runOk(authenticated(ownerId, `
    select public.create_pachanga_platform_announcement_v1(
      'user', ${quote(targetId)}::uuid, 'Concurrent announcement', 'One canonical delivery', '/avisos',
      ${quote(announcementCreateOperation)}::uuid, 'Concurrency announcement fixture'
    )
  `), "create announcement")).split("\n").filter(Boolean).at(-1));
  const sendResponse = await sameCanonical("same announcement send", authenticated(ownerId, `
    select public.send_pachanga_platform_announcement_v1(
      ${quote(announcement.id)}::uuid, 1,
      ${quote(announcementSendOperation)}::uuid, 'Concurrent confirmed send'
    )
  `));
  assert.equal(sendResponse.recipientCount, 1);
  assert.equal(await runOk(
    `select count(*) from public.pachanga_user_notifications where recipient_user_id = ${quote(targetId)}::uuid and kind = 'platform_announcement';`,
    "notification count",
  ), "1");

  console.log(JSON.stringify({
    announcementDelivery: 1,
    distinctOperationsRejectStale: true,
    entityLocks: ["incident", "role", "user_state"],
    sameOperationConverges: true,
    serverAuthoritative: true,
  }));
} finally {
  const restoreFlag = flagBefore
    ? `update private.pachanga_conduct_settings set attendance_closure_enabled = ${flagBefore[0]}, platform_revision = ${flagBefore[1]} where singleton;`
    : "";
  await runOk(`
    ${restoreFlag}
    delete from public.pachanga_user_notifications where recipient_user_id in (${quote(targetId)}::uuid, ${quote(roleTargetId)}::uuid);
    delete from private.pachanga_platform_announcements where audience_id in (${quote(targetId)}::uuid, ${quote(roleTargetId)}::uuid);
    delete from private.pachanga_platform_incidents where fingerprint = ${quote("b".repeat(64))};
    delete from private.pachanga_client_error_receipts where operation_id = ${quote(telemetryOperation)}::uuid;
    delete from private.pachanga_client_error_telemetry where fingerprint = ${quote("b".repeat(64))};
    delete from private.pachanga_platform_admin_action_ledger where actor_user_id = ${quote(ownerId)}::uuid or target_id in (${quote(targetId)}, ${quote(roleTargetId)});
    delete from private.pachanga_platform_user_states where user_id in (${quote(targetId)}::uuid, ${quote(roleTargetId)}::uuid);
    delete from private.pachanga_platform_admin_roles where user_id in (${quote(ownerId)}::uuid, ${quote(roleTargetId)}::uuid);
    delete from auth.users where id in (${quote(ownerId)}::uuid, ${quote(targetId)}::uuid, ${quote(roleTargetId)}::uuid);
  `, "cleanup");
}
