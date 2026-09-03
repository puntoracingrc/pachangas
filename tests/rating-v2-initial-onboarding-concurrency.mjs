import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.RATING_V2_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const sqlTimeoutMs = Number(process.env.RATING_V2_INITIAL_SQL_TIMEOUT_MS || 15_000);

if (!databaseUrl) throw new Error("RATING_V2_DATABASE_URL is required");

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

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.stdin.on("error", (error) => {
      stderr += `${error.message}\n`;
    });
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

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no JSON`);
  return JSON.parse(line);
}

const input = {
  age: 31,
  heightCm: 178,
  weightKg: 76,
  primaryPosition: "central_midfielder",
  secondaryPositions: ["attacking_midfielder"],
  modeShares: [
    { mode: "futsal_5", percentage: 10 },
    { mode: "football_7", percentage: 70 },
    { mode: "football_11", percentage: 20 },
  ],
  experienceLevel: "social_league",
  yearsSinceLevel: 0,
  frequency: "weekly",
  answers: {
    controlUnderPressure: 3,
    ballCarrying: 3,
    passingExecution: 3,
    decisionMaking: 3,
    finishing: 3,
    attackingMovement: 3,
    defensivePositioning: 3,
    defensiveDuels: 3,
    paceComparison: 3,
    physicalIntensity: 3,
  },
  calculatedAt: "2026-09-03T20:00:00.000Z",
  engineVersion: "football-rating-v1",
  questionnaireVersion: "initial-test-v1",
};

const result = {
  calculatedAt: "2026-09-03T20:00:00.000Z",
  engineResult: {},
  engineVersion: "football-rating-v1",
  facets: { ritmo: 5.5, tiro: 5.5, pase: 5.5, regate: 5.5, defensa: 5.5, fisico: 5.5 },
  position: "Mediocentro / pivote",
  primaryPosition: "central_midfielder",
  questionnaireVersion: "initial-test-v1",
  rating: 5.5,
  reliability: 41.5625,
  v2Facets: { pace: 55, shooting: 55, passing: 55, dribbling: 55, defending: 55, physical: 55 },
  v2CurrentModifiers: { pace: 0, shooting: 0, passing: 0, dribbling: 0, defending: 0, physical: 0 },
};

const actors = Array.from({ length: 7 }, () => ({
  groupId: randomUUID(),
  operationId: randomUUID(),
  playerId: `rating165-${randomUUID()}`,
  userId: randomUUID(),
}));

function assessmentSql(actor, { assessmentInput = input, operationId = actor.operationId } = {}) {
  return `
begin;
set local role service_role;
set local statement_timeout = '8s';
select public.persist_pachanga_player_assessment_authoritative_v2(
  ${sqlText(actor.userId)}::uuid,
  ${sqlText(actor.groupId)}::uuid,
  ${sqlText(actor.playerId)},
  'initial',
  ${sqlJson(assessmentInput)},
  ${sqlJson(result)},
  ${sqlText(operationId)}::uuid,
  0,
  '{"surface":"rating165-concurrency"}'::jsonb
)::text;
commit;
`;
}

function countSql(actor) {
  return `
select jsonb_build_object(
  'profiles', (select count(*) from public.pachanga_player_profiles where user_id = ${sqlText(actor.userId)}::uuid),
  'assessments', (select count(*) from public.pachanga_player_assessments where user_id = ${sqlText(actor.userId)}::uuid and assessment_kind = 'initial'),
  'events', (select count(*) from public.pachanga_group_events where group_id = ${sqlText(actor.groupId)}::uuid),
  'receipts', (select count(*) from public.pachanga_operation_receipts where group_id = ${sqlText(actor.groupId)}::uuid),
  'revision', (select payload_revision from public.pachanga_groups where id = ${sqlText(actor.groupId)}::uuid)
)::text;
`;
}

const setup = `
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

insert into auth.users(id, email) values
${actors.map((actor, index) => `(${sqlText(actor.userId)}::uuid, ${sqlText(`rating165-concurrency-${index}-${actor.userId}@example.test`)})`).join(",\n")};

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
${actors.map((actor, index) => `(
  ${sqlText(actor.groupId)}::uuid,
  ${sqlText(actor.userId)}::uuid,
  ${sqlText(`Rating 165 concurrency ${index}`)},
  ${sqlText(`R165${actor.groupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)},
  '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
)`).join(",\n")};

insert into public.pachanga_group_members(group_id, user_id, role) values
${actors.map((actor) => `(${sqlText(actor.groupId)}::uuid, ${sqlText(actor.userId)}::uuid, 'owner')`).join(",\n")};

create or replace function public.rating165_test_delay_profile_insert()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.user_id = ${sqlText(actors[0].userId)}::uuid then
    perform pg_catalog.pg_sleep(0.35);
  end if;
  return new;
end;
$$;

create trigger rating165_test_delay_profile_insert
before insert on public.pachanga_player_profiles
for each row execute function public.rating165_test_delay_profile_insert();
`;

const cleanup = `
begin;
drop trigger if exists rating165_test_delay_profile_insert on public.pachanga_player_profiles;
drop function if exists public.rating165_test_delay_profile_insert();
delete from public.pachanga_player_rating_snapshots
where player_profile_id in (
  select id from public.pachanga_player_profiles
  where user_id = any(array[${actors.map((actor) => `${sqlText(actor.userId)}::uuid`).join(",")}])
);
delete from public.pachanga_player_assessments
where user_id = any(array[${actors.map((actor) => `${sqlText(actor.userId)}::uuid`).join(",")}]);
delete from public.pachanga_player_profiles
where user_id = any(array[${actors.map((actor) => `${sqlText(actor.userId)}::uuid`).join(",")}]);
delete from public.pachanga_operation_receipts
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from public.pachanga_group_events
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from public.pachanga_group_members
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
alter table private.pachanga_team_operational_operation_receipts_v1 disable trigger user;
alter table private.pachanga_team_operational_events_v1 disable trigger user;
alter table private.pachanga_team_operational_state_revisions_v1 disable trigger user;
alter table private.pachanga_team_operational_states_v1 disable trigger user;
delete from private.pachanga_team_operational_operation_receipts_v1
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from private.pachanga_team_operational_events_v1
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from private.pachanga_team_operational_state_revisions_v1
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from private.pachanga_team_operational_states_v1
where group_id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
alter table private.pachanga_team_operational_operation_receipts_v1 enable trigger user;
alter table private.pachanga_team_operational_events_v1 enable trigger user;
alter table private.pachanga_team_operational_state_revisions_v1 enable trigger user;
alter table private.pachanga_team_operational_states_v1 enable trigger user;
delete from public.pachanga_groups
where id = any(array[${actors.map((actor) => `${sqlText(actor.groupId)}::uuid`).join(",")}]);
delete from auth.users
where id = any(array[${actors.map((actor) => `${sqlText(actor.userId)}::uuid`).join(",")}]);
commit;
`;

try {
  const databaseName = await runOk("select current_database();", "database safety check");
  assert.match(
    databaseName,
    /(rating165|rating_v2|synthetic|test|repro)/i,
    "Concurrency cleanup is restricted to an explicitly disposable database",
  );
  await runOk(setup, "setup");

  const identical = await Promise.all([
    runSql(assessmentSql(actors[0]), "identical-a"),
    runSql(assessmentSql(actors[0]), "identical-b"),
  ]);
  assert.ok(identical.every((entry) => entry.code === 0), `identical retries must both succeed: ${JSON.stringify(identical)}`);
  const identicalResponses = identical.map((entry) => lastJson(entry.stdout, entry.label));
  assert.deepEqual(identicalResponses[0], identicalResponses[1], "concurrent identical retries must return one canonical response");
  assert.deepEqual(lastJson(await runOk(countSql(actors[0]), "identical counts"), "identical counts"), {
    profiles: 1,
    assessments: 1,
    events: 1,
    receipts: 1,
    revision: identicalResponses[0].confirmedRevision,
  });

  const conflictingInput = { ...input, age: input.age + 1 };
  const incompatible = await Promise.all([
    runSql(assessmentSql(actors[1]), "incompatible-a"),
    runSql(assessmentSql(actors[1], { assessmentInput: conflictingInput }), "incompatible-b"),
  ]);
  assert.equal(incompatible.filter((entry) => entry.code === 0).length, 1, "one incompatible request must win");
  const incompatibleLoser = incompatible.find((entry) => entry.code !== 0);
  assert.ok(incompatibleLoser);
  assert.match(incompatibleLoser.stderr, /different assessment payload/i);
  const incompatibleCounts = lastJson(await runOk(countSql(actors[1]), "incompatible counts"), "incompatible counts");
  assert.deepEqual(
    { ...incompatibleCounts, revision: Number(incompatibleCounts.revision) > 0 },
    { profiles: 1, assessments: 1, events: 1, receipts: 1, revision: true },
  );

  const distinctOperation = randomUUID();
  const distinct = await Promise.all([
    runSql(assessmentSql(actors[2]), "distinct-operation-a"),
    runSql(assessmentSql(actors[2], { operationId: distinctOperation }), "distinct-operation-b"),
  ]);
  assert.equal(distinct.filter((entry) => entry.code === 0).length, 1, "only one distinct operation may initialize an actor");
  assert.match(distinct.find((entry) => entry.code !== 0)?.stderr ?? "", /Server revision is newer|assessment already completed/i);
  const distinctCounts = lastJson(await runOk(countSql(actors[2]), "distinct counts"), "distinct counts");
  assert.equal(distinctCounts.profiles, 1);
  assert.equal(distinctCounts.assessments, 1);
  assert.equal(distinctCounts.events, 1);
  assert.equal(distinctCounts.receipts, 1);

  const fanout = await Promise.all(
    Array.from({ length: 6 }, (_, index) => runSql(assessmentSql(actors[3]), `fanout-${index}`)),
  );
  assert.ok(fanout.every((entry) => entry.code === 0), `all same-operation fanout retries must converge: ${JSON.stringify(fanout)}`);
  const fanoutResponses = fanout.map((entry) => JSON.stringify(lastJson(entry.stdout, entry.label)));
  assert.equal(new Set(fanoutResponses).size, 1, "fanout must return the same receipt to every caller");
  const fanoutCounts = lastJson(await runOk(countSql(actors[3]), "fanout counts"), "fanout counts");
  assert.deepEqual(
    { ...fanoutCounts, revision: Number(fanoutCounts.revision) > 0 },
    { profiles: 1, assessments: 1, events: 1, receipts: 1, revision: true },
  );

  const independent = await Promise.all([
    runSql(assessmentSql(actors[4]), "independent-a"),
    runSql(assessmentSql(actors[5]), "independent-b"),
  ]);
  assert.ok(independent.every((entry) => entry.code === 0), `independent actors must both initialize: ${JSON.stringify(independent)}`);
  for (const actor of [actors[4], actors[5]]) {
    const counts = lastJson(await runOk(countSql(actor), `independent counts ${actor.userId}`), "independent counts");
    assert.equal(counts.profiles, 1);
    assert.equal(counts.assessments, 1);
    assert.equal(counts.events, 1);
    assert.equal(counts.receipts, 1);
  }

  const replay = lastJson(await runOk(assessmentSql(actors[0]), "lost-response retry"), "lost-response retry");
  assert.deepEqual(replay, identicalResponses[0], "retry after a simulated lost response must recover the receipt");

  console.log(JSON.stringify({
    concurrentIdentical: "PASS",
    incompatiblePayload: "PASS",
    distinctOperations: "PASS",
    fanout: "PASS",
    independentActors: "PASS",
    lostResponseRetry: "PASS",
  }));
} finally {
  await runOk(cleanup, "cleanup");
}
