import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.PLAYER_COSMETICS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const sqlTimeoutMs = Number(process.env.PLAYER_COSMETICS_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) {
  throw new Error("PLAYER_COSMETICS_DATABASE_URL is required for the cosmetics concurrency test");
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl],
      { env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
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
        stderr: [stderr.trim(), timedOut ? `SQL timed out after ${sqlTimeoutMs}ms` : ""]
          .filter(Boolean)
          .join("\n"),
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

const userId = randomUUID();
const groupId = randomUUID();
const profileId = randomUUID();
const matchFactId = randomUUID();
const definitionId = randomUUID();
const grantId = randomUUID();
const operationA = randomUUID();
const operationB = randomUUID();
const frameKey = "player.frame.barrio.steel";
const titleKey = "player.title.old_school";

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

insert into auth.users(id, email)
values (${sqlText(userId)}::uuid, ${sqlText(`cosmetics-${userId}@example.test`)});

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values (
  ${sqlText(groupId)}::uuid,
  ${sqlText(userId)}::uuid,
  'Concurrent cosmetics',
  ${sqlText(`COS${groupId.replaceAll("-", "").slice(0, 7).toUpperCase()}`)},
  '{"players":[],"matches":[]}'::jsonb
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (${sqlText(groupId)}::uuid, ${sqlText(userId)}::uuid, 'owner', 'Concurrent owner');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name, position,
  rating, base_overall, calibrated_overall, current_overall,
  base_facets, calibrated_facets, current_facets, rating_engine_version
) values (
  ${sqlText(profileId)}::uuid, ${sqlText(userId)}::uuid, ${sqlText(groupId)}::uuid,
  'concurrent-cosmetics-owner', 'Concurrent owner', 'MC', 7.2, 72, 72, 72,
  '{"pace":72,"shooting":72,"passing":72,"dribbling":72,"defending":72,"physical":72}'::jsonb,
  '{"pace":72,"shooting":72,"passing":72,"dribbling":72,"defending":72,"physical":72}'::jsonb,
  '{"pace":72,"shooting":72,"passing":72,"dribbling":72,"defending":72,"physical":72}'::jsonb,
  'pachangas-rating-v2'
);

insert into public.pachanga_progression_match_facts(
  id, source_kind, source_match_id, source_revision, group_id, match_scope,
  outcome, goals_for, goals_against, clean_sheet, close_win, big_win,
  scoreless_draw, player_facts_complete, source_snapshot, state, played_at
) values (
  ${sqlText(matchFactId)}::uuid, 'internal_snapshot', ${sqlText(`cosmetics-${matchFactId}`)},
  1, ${sqlText(groupId)}::uuid, 'internal', 'win', 2, 1, false, true, false,
  false, true, '{"canonicalState":"finalized"}'::jsonb, 'active', clock_timestamp()
);

insert into public.pachanga_achievement_definitions(
  id, achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, threshold, rarity, repeatable, reward_kind,
  active, catalog_key, family_key, display_priority
) values (
  ${sqlText(definitionId)}::uuid, ${sqlText(`test.cosmetics.concurrent.${definitionId}`)}, 1,
  'Cosmetics concurrency', 'Fixture de concurrencia', 'player', 'internal',
  'test', 'PLAYER_APPEARANCES', 1, 'common', false, 'none', true,
  ${sqlText(`test_cosmetics_${definitionId}`)}, 'test.cosmetics.concurrent', 1
);

insert into public.pachanga_achievement_grants(
  id, definition_id, subject_type, subject_id, group_id, origin_match_fact_id,
  metric_value, operation_id, state, occurred_at
) values (
  ${sqlText(grantId)}::uuid, ${sqlText(definitionId)}::uuid, 'player',
  ${sqlText(profileId)}::uuid, ${sqlText(groupId)}::uuid, ${sqlText(matchFactId)}::uuid,
  1, ${sqlText(randomUUID())}::uuid, 'active', clock_timestamp()
);

update private.pachanga_player_cosmetic_settings
set player_cosmetics_enabled = true, updated_at = clock_timestamp()
where singleton;

insert into public.pachanga_player_reward_inventory(
  player_profile_id, reward_kind, reward_key, source_grant_id, state, acquired_at
) values
  (${sqlText(profileId)}::uuid, 'player_cosmetic', ${sqlText(frameKey)}, ${sqlText(grantId)}::uuid, 'unlocked', clock_timestamp()),
  (${sqlText(profileId)}::uuid, 'player_cosmetic', ${sqlText(titleKey)}, ${sqlText(grantId)}::uuid, 'unlocked', clock_timestamp());
`;

const cleanupSql = `
delete from private.pachanga_player_cosmetic_operation_receipts
where player_profile_id = ${sqlText(profileId)}::uuid;
delete from public.pachanga_player_cosmetic_public_cards
where player_profile_id = ${sqlText(profileId)}::uuid;
delete from public.pachanga_player_cosmetic_loadouts
where player_profile_id = ${sqlText(profileId)}::uuid;
delete from public.pachanga_user_notifications
where recipient_user_id = ${sqlText(userId)}::uuid;
delete from public.pachanga_player_reward_inventory
where player_profile_id = ${sqlText(profileId)}::uuid;
delete from public.pachanga_achievement_grants where id = ${sqlText(grantId)}::uuid;
delete from public.pachanga_achievement_definitions where id = ${sqlText(definitionId)}::uuid;
delete from public.pachanga_progression_match_facts where id = ${sqlText(matchFactId)}::uuid;
delete from public.pachanga_player_profiles where id = ${sqlText(profileId)}::uuid;
delete from public.pachanga_group_members where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_groups where id = ${sqlText(groupId)}::uuid;
delete from auth.users where id = ${sqlText(userId)}::uuid;
update private.pachanga_player_cosmetic_settings
set player_cosmetics_enabled = false, updated_at = clock_timestamp()
where singleton;
`;

function saveSql(operationId, loadout) {
  return authenticatedSql(
    userId,
    `select public.save_pachanga_player_cosmetic_loadout_v1(
      ${sqlText(JSON.stringify(loadout))}::jsonb,
      ${sqlText(operationId)}::uuid,
      3,
      '{"surface":"cosmetics-concurrency","device":"synthetic-client"}'::jsonb
    )`,
  );
}

const loadoutA = {
  frameKey,
  backgroundKey: null,
  accentKey: null,
  effectKey: null,
  titleKey: null,
  featuredBadgeGrantId: null,
};
const loadoutB = {
  frameKey: null,
  backgroundKey: null,
  accentKey: null,
  effectKey: null,
  titleKey,
  featuredBadgeGrantId: null,
};

try {
  await runOk(setupSql, "cosmetics concurrency fixture setup");

  const initialSnapshot = lastJson(
    await runOk(
      authenticatedSql(userId, "select public.get_pachanga_player_cosmetics_snapshot_v1()"),
      "initial cosmetics snapshot",
    ),
    "initial cosmetics snapshot",
  );
  assert.equal(initialSnapshot.revision, 3, "Two grants must produce revision 3 before the race");

  const race = await Promise.all([
    runSql(saveSql(operationA, loadoutA), "client A save"),
    runSql(saveSql(operationB, loadoutB), "client B save"),
  ]);
  const successes = race.filter((result) => result.code === 0);
  const conflicts = race.filter((result) => result.code !== 0);
  assert.equal(successes.length, 1, `Exactly one concurrent save must succeed: ${JSON.stringify(race)}`);
  assert.equal(conflicts.length, 1, `Exactly one concurrent save must conflict: ${JSON.stringify(race)}`);
  assert.match(conflicts[0].stderr, /stale|PT409|revision/i);

  const winningIndex = race.findIndex((result) => result.code === 0);
  const winningOperation = winningIndex === 0 ? operationA : operationB;
  const winningLoadout = winningIndex === 0 ? loadoutA : loadoutB;
  const winningResponse = lastJson(successes[0].stdout, "winning concurrent save");
  assert.equal(winningResponse.confirmedRevision, 4);

  const replay = await Promise.all([
    runSql(saveSql(winningOperation, winningLoadout), "client A idempotent replay"),
    runSql(saveSql(winningOperation, winningLoadout), "client B idempotent replay"),
  ]);
  assert.ok(replay.every((result) => result.code === 0), `Both replays must succeed: ${JSON.stringify(replay)}`);
  const replayResponses = replay.map((result) => lastJson(result.stdout, result.label));
  assert.deepEqual(replayResponses[0], replayResponses[1], "Both clients must receive the same receipt");
  assert.equal(replayResponses[0].confirmedRevision, 4, "A replay must not increment revision");

  const canonical = lastJson(
    await runOk(
      authenticatedSql(userId, "select public.get_pachanga_player_cosmetics_snapshot_v1()"),
      "canonical cosmetics snapshot",
    ),
    "canonical cosmetics snapshot",
  );
  assert.equal(canonical.revision, 4);
  assert.deepEqual(canonical.loadout, winningLoadout);

  const receiptCount = Number(await runOk(
    `select count(*) from private.pachanga_player_cosmetic_operation_receipts
     where player_profile_id = ${sqlText(profileId)}::uuid
       and operation_kind = 'save_loadout'`,
    "cosmetics receipt count",
  ));
  assert.equal(receiptCount, 1, "The winner and its retries must retain one receipt");

  process.stdout.write(`${JSON.stringify({
    canonicalRevision: canonical.revision,
    conflict: true,
    idempotentReplay: true,
    receiptCount,
    winner: winningIndex === 0 ? "client-a" : "client-b",
  })}\n`);
} finally {
  await runOk(cleanupSql, "cosmetics concurrency cleanup");
}
