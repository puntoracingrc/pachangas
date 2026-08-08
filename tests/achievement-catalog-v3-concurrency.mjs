import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.ACHIEVEMENTS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
if (!databaseUrl) throw new Error("ACHIEVEMENTS_DATABASE_URL is required");

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-w", "-Atq", "-v", "ON_ERROR_STOP=1", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolve({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

async function runOk(sql, label) {
  const result = await runSql(sql, label);
  assert.equal(result.code, 0, `${label} failed:\n${result.stderr}`);
  return result.stdout;
}

const userId = randomUUID();
const groupId = randomUUID();
const rivalId = randomUUID();
const profileId = randomUUID();
const factId = randomUUID();
const sourceId = `catalog-v3-race-${randomUUID()}`;

await runOk(`
insert into auth.users(id, email) values (${quote(userId)}::uuid, ${quote(`${userId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${quote(groupId)}::uuid, ${quote(userId)}::uuid, 'V3 concurrency', ${quote(`V3${groupId.replaceAll("-", "").slice(0, 8)}`)}, '{"players":[]}'::jsonb),
  (${quote(rivalId)}::uuid, ${quote(userId)}::uuid, 'V3 rival', ${quote(`R3${rivalId.replaceAll("-", "").slice(0, 8)}`)}, '{"players":[]}'::jsonb);
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (${quote(groupId)}::uuid, ${quote(userId)}::uuid, 'owner', 'V3 Player');
insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values (
  ${quote(profileId)}::uuid, ${quote(userId)}::uuid, 'V3 Player', 'DEL', 67, 67, 67,
  '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}',
  80, 'pachangas-rating-v2'
);
insert into public.pachanga_progression_match_facts(
  id, source_kind, source_match_id, source_revision, group_id, opponent_group_id,
  match_scope, outcome, goals_for, goals_against, clean_sheet, close_win,
  big_win, scoreless_draw, player_facts_complete, source_snapshot, state,
  server_sequence, played_at
) values (
  ${quote(factId)}::uuid, 'external_result', ${quote(sourceId)}, 1,
  ${quote(groupId)}::uuid, ${quote(rivalId)}::uuid, 'external', 'draw',
  9, 9, false, false, false, false, true,
  '{"officialState":"confirmed"}'::jsonb, 'active',
  nextval('public.pachanga_progression_sequence'), clock_timestamp()
);
insert into public.pachanga_progression_player_match_facts(
  match_fact_id, group_id, player_profile_id, local_player_id,
  team_side, outcome, goals, card_snapshot
) values (
  ${quote(factId)}::uuid, ${quote(groupId)}::uuid, ${quote(profileId)}::uuid,
  'v3-race-player', 'team', 'draw', 0,
  '{"currentOverall":67,"engineVersion":"pachangas-rating-v2"}'::jsonb
);
select private.pachanga_rebuild_player_progression_stats_v1(${quote(profileId)}::uuid, 'external');
select private.pachanga_rebuild_team_progression_stats_v1(${quote(groupId)}::uuid, 'external');
`, "setup");

const evaluationSql = `
begin;
select private.pachanga_evaluate_achievements_v1(
  ${quote(groupId)}::uuid, 'external', ${quote(factId)}::uuid
);
commit;
`;
const evaluations = await Promise.all([
  runSql(evaluationSql, "client-a"),
  runSql(evaluationSql, "client-b"),
]);
for (const result of evaluations) {
  assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
}
const awardedCounts = evaluations.map((result) => Number(result.stdout.split("\n").filter(Boolean).at(-1)));
assert.equal(awardedCounts.filter((count) => count > 0).length, 1);
assert.equal(awardedCounts.filter((count) => count === 0).length, 1);

const grantId = await runOk(`
select grants.id
from public.pachanga_achievement_grants grants
join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
where grants.origin_match_fact_id = ${quote(factId)}::uuid
  and definitions.family_key = 'team.external.match_goals';
`, "goal grant");
assert.match(grantId, /^[0-9a-f-]{36}$/);

const componentSnapshot = await runOk(`
select jsonb_build_object(
  'grants', count(distinct recipients.achievement_grant_id),
  'boxes', count(*),
  'indexes', jsonb_agg(recipients.component_index order by recipients.component_index),
  'goals', sum((recipients.reward_component ->> 'goals')::integer)
)
from public.pachanga_reward_recipients recipients
where recipients.achievement_grant_id = ${quote(grantId)}::uuid
  and recipients.user_id = ${quote(userId)}::uuid;
`, "component snapshot");
assert.deepEqual(JSON.parse(componentSnapshot), {
  boxes: 3,
  goals: 9,
  grants: 1,
  indexes: [0, 1, 2],
});

const ensureSql = `select private.pachanga_ensure_collective_boxes_v2(${quote(grantId)}::uuid);`;
const ensures = await Promise.all([
  runSql(ensureSql, "ensure-a"),
  runSql(ensureSql, "ensure-b"),
]);
for (const result of ensures) {
  assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  assert.equal(Number(result.stdout.split("\n").filter(Boolean).at(-1)), 0);
}

const finalCount = await runOk(`
select count(*) from public.pachanga_reward_recipients
where achievement_grant_id = ${quote(grantId)}::uuid
  and user_id = ${quote(userId)}::uuid;
`, "final count");
assert.equal(Number(finalCount), 3);

console.log("achievement catalog V3 concurrency: ok");
