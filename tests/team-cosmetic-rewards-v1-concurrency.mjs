import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.TEAM_COSMETIC_REWARDS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
if (!databaseUrl) throw new Error("TEAM_COSMETIC_REWARDS_DATABASE_URL is required");

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
const factId = randomUUID();
const activationOperationId = randomUUID();
const sourceId = `team-cosmetic-reward-race-${randomUUID()}`;
const groupIds = `${quote(groupId)}::uuid, ${quote(rivalId)}::uuid`;

const cleanupSql = `
begin;
delete from private.pachanga_team_cosmetic_reward_ledger where group_id in (${groupIds});
delete from public.pachanga_team_cosmetic_seen where group_id in (${groupIds});
delete from public.pachanga_team_shield_events where group_id in (${groupIds});
delete from public.pachanga_team_shield_operation_receipts where group_id in (${groupIds});
delete from public.pachanga_team_shield_public where group_id in (${groupIds});
delete from public.pachanga_team_shield_versions where group_id in (${groupIds});
delete from public.pachanga_team_shield_loadouts where group_id in (${groupIds});
delete from public.pachanga_team_shield_state where group_id in (${groupIds});
delete from public.pachanga_team_cosmetic_inventory where group_id in (${groupIds});
delete from public.pachanga_user_notifications where recipient_user_id = ${quote(userId)}::uuid;
alter table private.pachanga_reward_box_contents disable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from private.pachanga_reward_box_contents contents
using public.pachanga_reward_recipients recipients
where contents.box_id = recipients.box_id and recipients.group_id in (${groupIds});
alter table private.pachanga_reward_box_contents enable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from public.pachanga_reward_recipients where group_id in (${groupIds});
delete from public.pachanga_progression_events where group_id in (${groupIds});
delete from public.pachanga_reward_grants where group_id in (${groupIds});
delete from public.pachanga_achievement_grants where group_id in (${groupIds});
delete from public.pachanga_progression_match_facts
where group_id in (${groupIds}) or opponent_group_id in (${groupIds});
delete from public.pachanga_team_progression_stats where group_id in (${groupIds});
delete from public.pachanga_progression_group_state where group_id in (${groupIds});
delete from public.pachanga_progression_user_state where user_id = ${quote(userId)}::uuid;
delete from public.pachanga_group_members where group_id in (${groupIds});
delete from public.pachanga_groups where id in (${groupIds});
delete from auth.users where id = ${quote(userId)}::uuid;
update private.pachanga_team_cosmetic_settings
set team_cosmetic_rewards_enabled = false, updated_at = clock_timestamp()
where singleton;
commit;
`;

try {
  await runOk(`
insert into auth.users(id, email)
values (${quote(userId)}::uuid, ${quote(`${userId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${quote(groupId)}::uuid, ${quote(userId)}::uuid, 'Reward concurrency', ${quote(`TC${groupId.replaceAll("-", "").slice(0, 8)}`)}, '{"players":[]}'::jsonb),
  (${quote(rivalId)}::uuid, ${quote(userId)}::uuid, 'Reward rival', ${quote(`TR${rivalId.replaceAll("-", "").slice(0, 8)}`)}, '{"players":[]}'::jsonb);
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (${quote(groupId)}::uuid, ${quote(userId)}::uuid, 'owner', 'Reward Owner');
select private.pachanga_set_team_cosmetic_rewards_enabled_v1(
  true, ${quote(activationOperationId)}::uuid, 1
);
insert into public.pachanga_progression_match_facts(
  id, source_kind, source_match_id, source_revision, group_id, opponent_group_id,
  match_scope, outcome, goals_for, goals_against, clean_sheet, close_win,
  big_win, scoreless_draw, player_facts_complete, source_snapshot, state,
  server_sequence, played_at
) values (
  ${quote(factId)}::uuid, 'external_result', ${quote(sourceId)}, 1,
  ${quote(groupId)}::uuid, ${quote(rivalId)}::uuid, 'external', 'win',
  2, 1, false, true, false, false, true,
  '{"canonicalState":"confirmed","officialState":"confirmed"}'::jsonb,
  'active', nextval('public.pachanga_progression_sequence'), clock_timestamp()
);
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
    runSql(evaluationSql, "consumer-a"),
    runSql(evaluationSql, "consumer-b"),
  ]);
  for (const result of evaluations) {
    assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  }
  const awardedCounts = evaluations.map(({ stdout }) => Number(stdout.split("\n").filter(Boolean).at(-1)));
  assert.equal(awardedCounts.filter((count) => count > 0).length, 1);
  assert.equal(awardedCounts.filter((count) => count === 0).length, 1);

  const canonical = JSON.parse(await runOk(`
select jsonb_build_object(
  'achievementGrants', (
    select count(*) from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
    where grants.group_id = ${quote(groupId)}::uuid
      and definitions.achievement_key = 'team.external.wins.001'
  ),
  'rewardLedger', (
    select count(*) from private.pachanga_team_cosmetic_reward_ledger
    where group_id = ${quote(groupId)}::uuid and mapping_key = 'first_challenge_win'
  ),
  'inventory', (
    select count(*) from public.pachanga_team_cosmetic_inventory
    where group_id = ${quote(groupId)}::uuid
      and cosmetic_key = 'team.shield.border.copper'
  ),
  'notifications', (
    select count(*) from public.pachanga_user_notifications
    where recipient_user_id = ${quote(userId)}::uuid
      and kind = 'team_cosmetic_reward'
      and payload ->> 'groupId' = ${quote(groupId)}
  ),
  'currency', (
    select coalesce(sum((response ->> 'currencyGranted')::integer), 0)
    from private.pachanga_team_cosmetic_reward_ledger
    where group_id = ${quote(groupId)}::uuid
  )
);
`, "canonical reward outcome"));
  assert.deepEqual(canonical, {
    achievementGrants: 1,
    currency: 0,
    inventory: 1,
    notifications: 1,
    rewardLedger: 1,
  });

  console.log(JSON.stringify({
    canonical,
    concurrentConsumers: 2,
    idempotent: true,
    winnerCount: 1,
  }));
} finally {
  await runOk(cleanupSql, "cleanup");
}
