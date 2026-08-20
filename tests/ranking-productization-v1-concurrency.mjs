import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.RANKING_PRODUCT_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.RANKING_PRODUCT_SQL_TIMEOUT_MS || 60_000);

if (!databaseUrl) throw new Error("RANKING_PRODUCT_DATABASE_URL is required");

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
  assert.deepEqual(lastJson(results[0]), lastJson(results[1]), `${label} must converge to one response`);
  return lastJson(results[0]);
}

const ownerId = randomUUID();
const seasonKey = `ranking-concurrency-${randomUUID()}`;
const createOperation = randomUUID();
const transitionOperations = [randomUUID(), randomUUID()];
const rebuildOperation = randomUUID();
const queueOperation = randomUUID();
const publishOperation = randomUUID();
const freezeOperation = randomUUID();
const closeOperation = randomUUID();
const archiveOperation = randomUUID();

await runOk(`
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values (
  ${quote(ownerId)}::uuid,
  ${quote(`ranking-concurrency-${ownerId}@example.test`)}
);
insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (${quote(ownerId)}::uuid, 'platform_owner', true);
`, "ranking concurrency fixture");

const season = await sameCanonical("same season-create operation", authenticated(ownerId, `
  select public.create_pachanga_ranking_season_v1(
    ${quote(seasonKey)}, 'Ranking concurrency season',
    clock_timestamp() - interval '30 days', clock_timestamp() + interval '30 days',
    array['08']::text[], ${quote(createOperation)}::uuid,
    'Concurrent idempotent season creation'
  )
`));
assert.equal(await runOk(`
  select count(*) from private.pachanga_ranking_operation_receipts
  where operation_id = ${quote(createOperation)}::uuid
`, "season operation receipt count"), "1");
assert.equal(await runOk(`
  select count(*) from private.pachanga_platform_admin_action_ledger
  where operation_id = ${quote(createOperation)}::uuid
`, "season admin ledger count"), "1");

const transitionResults = await Promise.all(transitionOperations.map((operationId, index) => runSql(
  authenticated(ownerId, `select public.transition_pachanga_ranking_season_v1(
    ${quote(season.seasonId)}::uuid, 'open', 1,
    ${quote(operationId)}::uuid, 'Concurrent lifecycle device ${index + 1}'
  )`),
  `season transition:device-${index + 1}`,
)));
assert.equal(transitionResults.filter(({ code }) => code === 0).length, 1, JSON.stringify(transitionResults));
assert.equal(transitionResults.filter(({ code }) => code !== 0).length, 1, JSON.stringify(transitionResults));
assert.match(transitionResults.find(({ code }) => code !== 0)?.stderr ?? "", /revision mismatch/i);

const canonicalRevision = Number(await runOk(`
  select revision from private.pachanga_ranking_seasons where id = ${quote(season.seasonId)}::uuid
`, "canonical season revision"));
assert.equal(canonicalRevision, 2);

const rebuild = await sameCanonical("same full-rebuild operation", authenticated(ownerId, `
  select public.rebuild_pachanga_provincial_ranking_v1(
    ${quote(season.seasonId)}::uuid, ${canonicalRevision},
    ${quote(rebuildOperation)}::uuid, 'Concurrent deterministic full rebuild'
  )
`));
assert.match(rebuild.candidateChecksum, /^[0-9a-f]{64}$/);
assert.equal(await runOk(`
  select count(*) from private.pachanga_ranking_rebuilds
  where operation_id = ${quote(rebuildOperation)}::uuid
`, "rebuild row count"), "1");
assert.equal(await runOk(`
  select count(*) from private.pachanga_ranking_operation_receipts
  where operation_id = ${quote(rebuildOperation)}::uuid
`, "rebuild receipt count"), "1");

await runOk(`select private.pachanga_enqueue_ranking_refresh_v1(
  ${quote(season.seasonId)}::uuid, null, 'season',
  'Concurrent durable queue regression', 'test', ${quote(queueOperation)}, null,
  ${quote(queueOperation)}::uuid
)`, "enqueue ranking refresh");
const queueProcessors = await Promise.all([
  runSql(service("select public.process_pachanga_ranking_refresh_queue_v1(1)"), "queue processor A"),
  runSql(service("select public.process_pachanga_ranking_refresh_queue_v1(1)"), "queue processor B"),
]);
for (const result of queueProcessors) assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
const queueResponses = queueProcessors.map(lastJson);
assert.equal(queueResponses.reduce((total, response) => total + response.processed, 0), 1);
assert.equal(queueResponses.reduce((total, response) => total + response.completed, 0), 1);
assert.equal(queueResponses.reduce((total, response) => total + response.failed, 0), 0);
assert.equal(await runOk(`
  select count(*) from private.pachanga_ranking_refresh_queue
  where operation_id = ${quote(queueOperation)}::uuid and state = 'completed' and attempts = 1
`, "queue convergence"), "1");
assert.equal(await runOk(`
  select count(*) from private.pachanga_ranking_operation_receipts
  where operation_id = ${quote(queueOperation)}::uuid
`, "queue operation receipt"), "1");

const latestCandidate = lastJson({
  label: "latest queue candidate",
  stdout: await runOk(`select jsonb_build_object(
    'id', rebuilds.id,
    'checksum', rebuilds.candidate_checksum
  ) from private.pachanga_ranking_rebuilds rebuilds
  where rebuilds.operation_id = ${quote(queueOperation)}::uuid`, "latest queue candidate"),
});
await runOk(authenticated(ownerId, `select public.publish_pachanga_provincial_ranking_v1(
  ${quote(latestCandidate.id)}::uuid, ${canonicalRevision}, ${quote(latestCandidate.checksum)},
  ${quote(publishOperation)}::uuid, 'Publish concurrency fixture before archival'
)`), "publish concurrency fixture");
const frozen = lastJson({
  label: "freeze concurrency season",
  stdout: await runOk(authenticated(ownerId, `select public.transition_pachanga_ranking_season_v1(
    ${quote(season.seasonId)}::uuid, 'frozen', 2,
    ${quote(freezeOperation)}::uuid, 'Freeze completed concurrency fixture'
  )`), "freeze concurrency season"),
});
const closed = lastJson({
  label: "close concurrency season",
  stdout: await runOk(authenticated(ownerId, `select public.transition_pachanga_ranking_season_v1(
    ${quote(season.seasonId)}::uuid, 'closed', ${frozen.revision},
    ${quote(closeOperation)}::uuid, 'Close completed concurrency fixture'
  )`), "close concurrency season"),
});
const archived = lastJson({
  label: "archive concurrency season",
  stdout: await runOk(authenticated(ownerId, `select public.transition_pachanga_ranking_season_v1(
    ${quote(season.seasonId)}::uuid, 'archived', ${closed.revision},
    ${quote(archiveOperation)}::uuid, 'Archive completed concurrency fixture'
  )`), "archive concurrency season"),
});
assert.equal(archived.status, "archived");

console.log(JSON.stringify({
  durableQueueSkipLocked: true,
  oneLifecycleWinner: true,
  sameOperationConverges: true,
  staleRevisionRejected: true,
}));
