import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.COMPETITION_FOUNDATION_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const timeoutMs = Number(process.env.COMPETITION_FOUNDATION_SQL_TIMEOUT_MS || 45_000);

if (!databaseUrl) throw new Error("COMPETITION_FOUNDATION_DATABASE_URL is required");

function quote(value) {
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

function authenticated(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: userId }))}, true);
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
  const responses = results.map(lastJson);
  assert.deepEqual(responses[0], responses[1], `${label} must converge to one canonical receipt`);
  return responses[0];
}

async function oneWinner(label, statements) {
  const results = await Promise.all(statements.map(({ client, sql }) => runSql(sql, `${label}:${client}`)));
  const winners = results.filter(({ code }) => code === 0);
  const losers = results.filter(({ code }) => code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must reject one stale writer: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, /STALE_REVISION/, `${label} must fail explicitly as stale`);
  return lastJson(winners[0]);
}

const platformOwnerId = randomUUID();
const ownerId = randomUUID();
const groupId = randomUUID();
const enableOperation = randomUUID();
const grantOperation = randomUUID();
const createOperation = randomUUID();
const editionOperations = [randomUUID(), randomUUID()];
const reuseOperation = randomUUID();
const flagsAggregateId = "00000000-0000-0000-0000-00000000c001";
const operationIds = [enableOperation, grantOperation, createOperation, ...editionOperations, reuseOperation];
let baselineFlags;

try {
  baselineFlags = (await runOk(`select foundation_enabled::text || '|' || creation_enabled::text || '|' || context_binding_enabled::text || '|' || revision::text from private.pachanga_competition_foundation_settings where singleton`, "read baseline flags")).split("|");
  await runOk(`
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    grant execute on function auth.jwt() to authenticated;
    insert into auth.users(id, email) values
      (${quote(platformOwnerId)}::uuid, ${quote(`competition-platform-${platformOwnerId}@example.test`)}),
      (${quote(ownerId)}::uuid, ${quote(`competition-owner-${ownerId}@example.test`)});
    insert into private.pachanga_platform_admin_roles(user_id, role, active)
    values (${quote(platformOwnerId)}::uuid, 'platform_owner', true);
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
    values (${quote(groupId)}::uuid, ${quote(ownerId)}::uuid, 'Competition Concurrency Team', ${quote(`CC${groupId.replaceAll("-", "").slice(0, 6)}`)}, '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}');
  `, "competition concurrency fixture");

  const baselineRevision = Number(baselineFlags[3]);
  await runOk(authenticated(platformOwnerId, `select public.command_pachanga_competition_platform_v1(
    ${quote(enableOperation)}::uuid, ${quote(flagsAggregateId)}::uuid, ${baselineRevision},
    'foundation_flags.set', '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"concurrency fixture"}',
    '{"surface":"competition_concurrency"}'
  )`), "enable competition fixture");

  await runOk(authenticated(platformOwnerId, `select public.command_pachanga_competition_platform_v1(
    ${quote(grantOperation)}::uuid, ${quote(groupId)}::uuid, 0,
    'entitlement.grant', '{"capability":"competition_create","reason":"concurrency fixture grant"}',
    '{"surface":"competition_concurrency"}'
  )`), "grant organizer entitlement");

  const create = await sameCanonical("same competition create operation", authenticated(ownerId, `
    select public.command_pachanga_competition_foundation_v1(
      ${quote(createOperation)}::uuid, ${quote(groupId)}::uuid, 1,
      'competition.create',
      '{"name":"Concurrency Competition","slug":"concurrency-competition","competitionType":"LEAGUE","visibility":"private","reason":"idempotent create"}',
      '{"surface":"competition_concurrency"}'
    )
  `));
  const competitionId = create.snapshot.competition.id;
  assert.equal(create.snapshot.competition.revision, 1);
  assert.equal(await runOk(`select count(*) from public.pachanga_competitions where organizer_group_id = ${quote(groupId)}::uuid`, "competition count"), "1");
  assert.equal(await runOk(`select count(*) from private.pachanga_competition_operation_receipts where operation_id = ${quote(createOperation)}::uuid`, "create receipt count"), "1");

  const race = await oneWinner("distinct edition writes", [
    {
      client: "device-a",
      sql: authenticated(ownerId, `select public.command_pachanga_competition_foundation_v1(
        ${quote(editionOperations[0])}::uuid, ${quote(competitionId)}::uuid, 1,
        'edition.create', '{"name":"Edition A","seasonLabel":"A","reason":"device a"}',
        '{"surface":"competition_concurrency"}'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(ownerId, `select public.command_pachanga_competition_foundation_v1(
        ${quote(editionOperations[1])}::uuid, ${quote(competitionId)}::uuid, 1,
        'edition.create', '{"name":"Edition B","seasonLabel":"B","reason":"device b"}',
        '{"surface":"competition_concurrency"}'
      )`),
    },
  ]);
  assert.equal(race.confirmedRevision, 2);
  assert.equal(await runOk(`select count(*) from public.pachanga_competition_editions where competition_id = ${quote(competitionId)}::uuid`, "edition race count"), "1");
  assert.equal(await runOk(`select revision from public.pachanga_competitions where id = ${quote(competitionId)}::uuid`, "competition canonical revision"), "2");

  const firstReuse = await runOk(authenticated(ownerId, `select public.command_pachanga_competition_foundation_v1(
    ${quote(reuseOperation)}::uuid, ${quote(competitionId)}::uuid, 2,
    'rule_set.create', '{"name":"Canonical rules","reason":"replay guard"}',
    '{"surface":"competition_concurrency"}'
  )`), "idempotency key initial use");
  assert.ok(firstReuse);
  const conflictingReuse = await runSql(authenticated(ownerId, `select public.command_pachanga_competition_foundation_v1(
    ${quote(reuseOperation)}::uuid, ${quote(competitionId)}::uuid, 2,
    'rule_set.create', '{"name":"Different rules","reason":"replay guard"}',
    '{"surface":"competition_concurrency"}'
  )`), "idempotency key conflicting reuse");
  assert.notEqual(conflictingReuse.code, 0);
  assert.match(conflictingReuse.stderr, /IDEMPOTENCY_KEY_REUSED/);

  console.log(JSON.stringify({
    differentOperations: "one_winner_one_stale",
    idempotencyConflictRejected: true,
    sameOperationConverges: true,
    serverAuthoritativeRevision: 3,
  }));
} finally {
  const restore = baselineFlags ? `
    update private.pachanga_competition_foundation_settings set
      foundation_enabled = ${baselineFlags[0]},
      creation_enabled = ${baselineFlags[1]},
      context_binding_enabled = ${baselineFlags[2]},
      revision = ${baselineFlags[3]}
    where singleton;
  ` : "";
  await runOk(`
    begin;
    alter table private.pachanga_competition_events disable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_competition_operation_receipts disable trigger guard_pachanga_competition_receipts_v1;
    ${restore}
    delete from public.pachanga_competition_invalidations where organizer_group_id = ${quote(groupId)}::uuid;
    delete from private.pachanga_competition_events where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]);
    delete from private.pachanga_competition_operation_receipts where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]);
    delete from public.pachanga_competition_rule_revisions where rule_set_id in (select id from public.pachanga_competition_rule_sets where competition_id in (select id from public.pachanga_competitions where organizer_group_id = ${quote(groupId)}::uuid));
    delete from public.pachanga_competition_rule_sets where competition_id in (select id from public.pachanga_competitions where organizer_group_id = ${quote(groupId)}::uuid);
    delete from public.pachanga_competition_editions where competition_id in (select id from public.pachanga_competitions where organizer_group_id = ${quote(groupId)}::uuid);
    delete from public.pachanga_competitions where organizer_group_id = ${quote(groupId)}::uuid;
    delete from public.pachanga_competition_entitlement_grants where organizer_group_id = ${quote(groupId)}::uuid;
    delete from public.pachanga_competition_organizer_states where organizer_group_id = ${quote(groupId)}::uuid;
    delete from public.pachanga_groups where id = ${quote(groupId)}::uuid;
    delete from private.pachanga_platform_admin_roles where user_id = ${quote(platformOwnerId)}::uuid;
    delete from auth.users where id in (${quote(platformOwnerId)}::uuid, ${quote(ownerId)}::uuid);
    alter table private.pachanga_competition_events enable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_competition_operation_receipts enable trigger guard_pachanga_competition_receipts_v1;
    commit;
  `, "competition concurrency cleanup");
}
