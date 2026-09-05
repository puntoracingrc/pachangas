import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.RATING_V2_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
if (!databaseUrl) throw new Error("RATING_V2_DATABASE_URL is required");

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function json(value) {
  return `${literal(JSON.stringify(value))}::jsonb`;
}

function runSql(sql, label) {
  return new Promise((resolve, reject) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

async function ok(sql, label) {
  const result = await runSql(sql, label);
  assert.equal(result.code, 0, `${label} failed:\n${result.stderr}`);
  return result.stdout;
}

const input = {
  primaryPosition: "central_midfielder",
  secondaryPositions: [],
  modeShares: [
    { mode: "futsal_5", percentage: 0 },
    { mode: "football_7", percentage: 100 },
    { mode: "football_11", percentage: 0 },
  ],
  experienceLevel: "regular_pachangas",
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
  calculatedAt: "2026-09-05T08:00:00.000Z",
  engineVersion: "football-rating-v1",
  questionnaireVersion: "initial-test-v1",
};

const result = {
  calculatedAt: "2026-09-05T08:00:00.000Z",
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

const sameActor = { operationId: randomUUID(), userId: randomUUID() };
const competingActor = { userId: randomUUID() };

function command(actor, operationId) {
  return `
begin;
set local role service_role;
select public.persist_pachanga_player_assessment_self_authoritative_v1(
  ${literal(actor.userId)}::uuid, 'initial', ${json(input)}, ${json(result)},
  ${literal(operationId)}::uuid, 0, '{"surface":"onboarding-concurrency"}'::jsonb
)::text;
commit;
`;
}

const setup = `
insert into auth.users(id, email) values
  (${literal(sameActor.userId)}::uuid, ${literal(`onboarding-same-${sameActor.userId}@example.test`)}),
  (${literal(competingActor.userId)}::uuid, ${literal(`onboarding-competing-${competingActor.userId}@example.test`)});
drop trigger if exists onboarding_test_delay_profile_insert on public.pachanga_player_profiles;
create or replace function public.onboarding_test_delay_profile_insert()
returns trigger language plpgsql set search_path = pg_catalog as $$
begin
  if new.user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid) then
    perform pg_catalog.pg_sleep(0.3);
  end if;
  return new;
end;
$$;
create trigger onboarding_test_delay_profile_insert
before insert on public.pachanga_player_profiles
for each row execute function public.onboarding_test_delay_profile_insert();
`;

const cleanup = `
begin;
drop trigger if exists onboarding_test_delay_profile_insert on public.pachanga_player_profiles;
drop function if exists public.onboarding_test_delay_profile_insert();
alter table private.pachanga_player_assessment_self_events_v1 disable trigger pachanga_player_assessment_self_events_immutable_v1;
alter table private.pachanga_player_assessment_self_receipts_v1 disable trigger pachanga_player_assessment_self_receipts_immutable_v1;
delete from private.pachanga_player_assessment_self_events_v1 where user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid);
delete from private.pachanga_player_assessment_self_receipts_v1 where user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid);
alter table private.pachanga_player_assessment_self_events_v1 enable trigger pachanga_player_assessment_self_events_immutable_v1;
alter table private.pachanga_player_assessment_self_receipts_v1 enable trigger pachanga_player_assessment_self_receipts_immutable_v1;
delete from public.pachanga_player_rating_snapshots where player_profile_id in (select id from public.pachanga_player_profiles where user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid));
delete from public.pachanga_player_assessments where user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid);
delete from public.pachanga_player_profiles where user_id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid);
delete from auth.users where id in (${literal(sameActor.userId)}::uuid, ${literal(competingActor.userId)}::uuid);
commit;
`;

try {
  const databaseName = await ok("select current_database();", "database safety check");
  assert.match(databaseName, /(onboarding|rating|test|synthetic|repro)/i, "Concurrency test requires a disposable database");
  await ok(setup, "setup");

  const sameResults = await Promise.all([
    runSql(command(sameActor, sameActor.operationId), "same operation A"),
    runSql(command(sameActor, sameActor.operationId), "same operation B"),
  ]);
  assert.deepEqual(sameResults.map((entry) => entry.code), [0, 0]);
  assert.equal(sameResults[0].stdout.split("\n").at(-1), sameResults[1].stdout.split("\n").at(-1));

  const sameCounts = JSON.parse(await ok(`select jsonb_build_object(
    'profiles',(select count(*) from public.pachanga_player_profiles where user_id=${literal(sameActor.userId)}::uuid),
    'assessments',(select count(*) from public.pachanga_player_assessments where user_id=${literal(sameActor.userId)}::uuid),
    'snapshots',(select count(*) from public.pachanga_player_rating_snapshots s join public.pachanga_player_profiles p on p.id=s.player_profile_id where p.user_id=${literal(sameActor.userId)}::uuid),
    'receipts',(select count(*) from private.pachanga_player_assessment_self_receipts_v1 where user_id=${literal(sameActor.userId)}::uuid),
    'events',(select count(*) from private.pachanga_player_assessment_self_events_v1 where user_id=${literal(sameActor.userId)}::uuid)
  )::text;`, "same-operation counts"));
  assert.deepEqual(sameCounts, { profiles: 1, assessments: 1, snapshots: 1, receipts: 1, events: 1 });

  const competingResults = await Promise.all([
    runSql(command(competingActor, randomUUID()), "competing operation A"),
    runSql(command(competingActor, randomUUID()), "competing operation B"),
  ]);
  assert.equal(competingResults.filter((entry) => entry.code === 0).length, 1);
  assert.equal(competingResults.filter((entry) => entry.code !== 0).length, 1);
  assert.match(competingResults.find((entry) => entry.code !== 0)?.stderr ?? "", /revision|already completed|concurrent/i);

  const competingCounts = JSON.parse(await ok(`select jsonb_build_object(
    'profiles',(select count(*) from public.pachanga_player_profiles where user_id=${literal(competingActor.userId)}::uuid),
    'assessments',(select count(*) from public.pachanga_player_assessments where user_id=${literal(competingActor.userId)}::uuid),
    'receipts',(select count(*) from private.pachanga_player_assessment_self_receipts_v1 where user_id=${literal(competingActor.userId)}::uuid)
  )::text;`, "competing-operation counts"));
  assert.deepEqual(competingCounts, { profiles: 1, assessments: 1, receipts: 1 });
} finally {
  await ok(cleanup, "cleanup");
}
