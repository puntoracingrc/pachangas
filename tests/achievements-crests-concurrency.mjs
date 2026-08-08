import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.ACHIEVEMENTS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const sqlTimeoutMs = Number(process.env.ACHIEVEMENTS_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) {
  throw new Error("ACHIEVEMENTS_DATABASE_URL is required for the achievements concurrency test");
}

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlJson(value) {
  return `${sqlText(JSON.stringify(value))}::jsonb`;
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
        stderr: [
          stderr.trim(),
          timedOut ? `SQL timed out after ${sqlTimeoutMs}ms` : "",
        ].filter(Boolean).join("\n"),
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

function serviceSql(statement) {
  return `
begin;
set local role service_role;
${statement};
commit;
`;
}

function lastJson(stdout, label) {
  const line = stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} did not return JSON`);
  return JSON.parse(line);
}

const homeOwnerId = randomUUID();
const homeAdminId = randomUUID();
const awayOwnerId = randomUUID();
const homeGroupId = randomUUID();
const awayGroupId = randomUUID();
const homeProfileId = randomUUID();
const awayProfileId = randomUUID();
const publishChallengeId = randomUUID();
const expiryChallengeId = randomUUID();
const publishOperationAId = randomUUID();
const publishOperationBId = randomUUID();
const confirmPublishOperationId = randomUUID();
const publishExpiryOperationId = randomUUID();
const confirmExpiryOperationId = randomUUID();
const expirySweepOperationId = randomUUID();
const rewardReplayOperationId = randomUUID();
const rewardRaceOperationAId = randomUUID();
const rewardRaceOperationBId = randomUUID();

const groupIds = `${sqlText(homeGroupId)}::uuid, ${sqlText(awayGroupId)}::uuid`;
const userIds = `${sqlText(homeOwnerId)}::uuid, ${sqlText(homeAdminId)}::uuid, ${sqlText(awayOwnerId)}::uuid`;
const profileIds = `${sqlText(homeProfileId)}::uuid, ${sqlText(awayProfileId)}::uuid`;
const challengeIds = `${sqlText(publishChallengeId)}::uuid, ${sqlText(expiryChallengeId)}::uuid`;

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

insert into auth.users(id, email) values
  (${sqlText(homeOwnerId)}::uuid, ${sqlText(`achievement-${homeOwnerId}@example.test`)}),
  (${sqlText(homeAdminId)}::uuid, ${sqlText(`achievement-${homeAdminId}@example.test`)}),
  (${sqlText(awayOwnerId)}::uuid, ${sqlText(`achievement-${awayOwnerId}@example.test`)});

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    ${sqlText(homeGroupId)}::uuid, ${sqlText(homeOwnerId)}::uuid,
    'Concurrent achievements home',
    ${sqlText(`ACH${homeGroupId.replaceAll("-", "").slice(0, 7).toUpperCase()}`)},
    ${sqlJson({
      activeMatchId: null,
      matches: [],
      players: [
        { id: "home-player", name: "Home Player", ownerUserId: homeOwnerId, position: "DEL" },
      ],
      siteSettings: {},
      venues: [],
    })}
  ),
  (
    ${sqlText(awayGroupId)}::uuid, ${sqlText(awayOwnerId)}::uuid,
    'Concurrent achievements away',
    ${sqlText(`ACH${awayGroupId.replaceAll("-", "").slice(0, 7).toUpperCase()}`)},
    ${sqlJson({
      activeMatchId: null,
      matches: [],
      players: [
        { id: "away-player", name: "Away Player", ownerUserId: awayOwnerId, position: "DEL" },
      ],
      siteSettings: {},
      venues: [],
    })}
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  (${sqlText(homeGroupId)}::uuid, ${sqlText(homeOwnerId)}::uuid, 'owner', 'Home owner'),
  (${sqlText(homeGroupId)}::uuid, ${sqlText(homeAdminId)}::uuid, 'admin', 'Home admin'),
  (${sqlText(awayGroupId)}::uuid, ${sqlText(awayOwnerId)}::uuid, 'owner', 'Away owner');

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values
  (
    ${sqlText(homeProfileId)}::uuid, ${sqlText(homeOwnerId)}::uuid,
    'Home Player', 'DEL', 68, 66, 67,
    '{"pace":70,"shooting":69,"passing":66,"dribbling":68,"defending":60,"physical":65}'::jsonb,
    72, 'pachangas-rating-v2'
  ),
  (
    ${sqlText(awayProfileId)}::uuid, ${sqlText(awayOwnerId)}::uuid,
    'Away Player', 'DEL', 66, 64, 65,
    '{"pace":67,"shooting":68,"passing":62,"dribbling":66,"defending":58,"physical":64}'::jsonb,
    70, 'pachangas-rating-v2'
  );

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, status, revision, proposal_number,
  scheduled_at, modality, field_name, field_address, last_proposed_by_group_id,
  created_by, updated_by
) values
  (
    ${sqlText(publishChallengeId)}::uuid, ${sqlText(homeGroupId)}::uuid,
    ${sqlText(awayGroupId)}::uuid, 'proposed', 1, 1,
    clock_timestamp() - interval '1 day', 'futbol7',
    'Concurrent field A', 'Concurrent address A', ${sqlText(homeGroupId)}::uuid,
    ${sqlText(homeOwnerId)}::uuid, ${sqlText(homeOwnerId)}::uuid
  ),
  (
    ${sqlText(expiryChallengeId)}::uuid, ${sqlText(homeGroupId)}::uuid,
    ${sqlText(awayGroupId)}::uuid, 'proposed', 1, 1,
    clock_timestamp() - interval '2 days', 'futbol7',
    'Concurrent field B', 'Concurrent address B', ${sqlText(homeGroupId)}::uuid,
    ${sqlText(homeOwnerId)}::uuid, ${sqlText(homeOwnerId)}::uuid
  );

update public.pachanga_team_challenges
set status = 'accepted', revision = 2, accepted_at = clock_timestamp(),
    updated_by = ${sqlText(awayOwnerId)}::uuid, updated_at = clock_timestamp()
where id in (${challengeIds});
`;

const cleanupSql = `
delete from public.pachanga_reward_open_receipts where actor_user_id in (${userIds});
delete from public.pachanga_player_points_ledger
where user_id in (${userIds}) or player_profile_id in (${profileIds});
delete from public.pachanga_player_point_accounts
where user_id in (${userIds}) or player_profile_id in (${profileIds});
delete from public.pachanga_player_reward_inventory where player_profile_id in (${profileIds});
alter table private.pachanga_reward_box_contents
  disable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from private.pachanga_reward_box_contents contents
using public.pachanga_reward_recipients recipients, public.pachanga_reward_grants rewards
where contents.box_id = recipients.box_id
  and recipients.reward_grant_id = rewards.id
  and rewards.group_id in (${groupIds});
alter table private.pachanga_reward_box_contents
  enable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from public.pachanga_reward_recipients recipients
using public.pachanga_reward_grants rewards
where recipients.reward_grant_id = rewards.id and rewards.group_id in (${groupIds});
delete from public.pachanga_progression_events
where group_id in (${groupIds}) or player_profile_id in (${profileIds});
delete from public.pachanga_team_cosmetic_inventory where group_id in (${groupIds});
delete from public.pachanga_reward_grants
where group_id in (${groupIds}) or player_profile_id in (${profileIds});
delete from public.pachanga_achievement_grants
where group_id in (${groupIds}) or subject_id in (${groupIds}, ${profileIds});
delete from public.pachanga_progression_player_match_facts
where group_id in (${groupIds}) or player_profile_id in (${profileIds});
delete from public.pachanga_progression_match_facts
where group_id in (${groupIds}) or opponent_group_id in (${groupIds});
delete from public.pachanga_team_progression_stats where group_id in (${groupIds});
delete from public.pachanga_player_progression_stats where player_profile_id in (${profileIds});
delete from public.pachanga_progression_group_state where group_id in (${groupIds});
delete from public.pachanga_progression_user_state where user_id in (${userIds});

delete from public.pachanga_external_result_operation_receipts
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_match_group_state where group_id in (${groupIds});
delete from public.pachanga_external_result_attestations
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_match_scorers
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_match_participants
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_result_events
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_result_versions
where external_match_id in (
  select id from public.pachanga_external_matches
  where home_group_id in (${groupIds}) or away_group_id in (${groupIds})
);
delete from public.pachanga_external_matches
where home_group_id in (${groupIds}) or away_group_id in (${groupIds});
delete from public.pachanga_team_challenge_events where challenge_id in (${challengeIds});
delete from public.pachanga_team_challenges where id in (${challengeIds});
delete from public.pachanga_group_members where group_id in (${groupIds});
delete from public.pachanga_player_profiles where id in (${profileIds});
delete from public.pachanga_groups where id in (${groupIds});
delete from auth.users where id in (${userIds});
`;

function publishSql(userId, operationId, matchId, sessionId) {
  return authenticatedSql(
    userId,
    `select public.publish_pachanga_external_result_v1(
      ${sqlText(homeGroupId)}::uuid,
      ${sqlText(matchId)}::uuid,
      2, 0,
      array['home-player'],
      '[{"playerId":"home-player","goals":2}]'::jsonb,
      ${sqlText(operationId)}::uuid,
      1,
      ${sqlJson({ sessionId, surface: "achievements-concurrency-test" })}
    )`,
  );
}

try {
  await runOk(setupSql, "achievements concurrency fixture setup");
  const matchIds = lastJson(
    await runOk(
      `select jsonb_build_object(
        'publishMatchId', (
          select id from public.pachanga_external_matches
          where challenge_id = ${sqlText(publishChallengeId)}::uuid
        ),
        'expiryMatchId', (
          select id from public.pachanga_external_matches
          where challenge_id = ${sqlText(expiryChallengeId)}::uuid
        )
      )`,
      "external match ids",
    ),
    "external match ids",
  );
  const publishMatchId = matchIds.publishMatchId;
  const expiryMatchId = matchIds.expiryMatchId;
  assert.ok(publishMatchId && expiryMatchId, "Accepted challenges must create both external matches");

  const publishRace = await Promise.all([
    runSql(
      publishSql(homeOwnerId, publishOperationAId, publishMatchId, "home-owner-device"),
      "home owner concurrent publication",
    ),
    runSql(
      publishSql(homeAdminId, publishOperationBId, publishMatchId, "home-admin-device"),
      "home admin concurrent publication",
    ),
  ]);
  const publishWinners = publishRace.filter((result) => result.code === 0);
  const publishLosers = publishRace.filter((result) => result.code !== 0);
  assert.equal(publishWinners.length, 1, `Exactly one admin publication must win: ${JSON.stringify(publishRace)}`);
  assert.equal(publishLosers.length, 1, `Exactly one stale admin publication must fail: ${JSON.stringify(publishRace)}`);
  assert.match(
    publishLosers[0].stderr,
    /External match revision is newer|could not serialize|could not obtain lock/i,
  );
  const published = lastJson(publishWinners[0].stdout, "winning admin publication");
  assert.equal(published.revision, 2);
  assert.equal(published.state, "pending_rival");

  await runOk(
    authenticatedSql(
      awayOwnerId,
      `select public.confirm_pachanga_external_result_v1(
        ${sqlText(awayGroupId)}::uuid,
        ${sqlText(publishMatchId)}::uuid,
        array['away-player'],
        '[]'::jsonb,
        ${sqlText(confirmPublishOperationId)}::uuid,
        2,
        ${sqlJson({ sessionId: "away-confirm-device", surface: "achievements-concurrency-test" })}
      )`,
    ),
    "confirm published match",
  );

  await runOk(
    authenticatedSql(
      homeOwnerId,
      `select public.publish_pachanga_external_result_v1(
        ${sqlText(homeGroupId)}::uuid,
        ${sqlText(expiryMatchId)}::uuid,
        1, 1,
        array['home-player'],
        '[{"playerId":"home-player","goals":1}]'::jsonb,
        ${sqlText(publishExpiryOperationId)}::uuid,
        1,
        ${sqlJson({ sessionId: "expiry-publish-device", surface: "achievements-concurrency-test" })}
      )`,
    ),
    "publish expiring result",
  );
  await runOk(
    `update public.pachanga_external_matches
     set response_deadline = clock_timestamp() - interval '1 minute'
     where id = ${sqlText(expiryMatchId)}::uuid`,
    "expire response deadline",
  );

  const expiryRace = await Promise.all([
    runSql(
      authenticatedSql(
        awayOwnerId,
        `select public.confirm_pachanga_external_result_v1(
          ${sqlText(awayGroupId)}::uuid,
          ${sqlText(expiryMatchId)}::uuid,
          array['away-player'],
          '[{"playerId":"away-player","goals":1}]'::jsonb,
          ${sqlText(confirmExpiryOperationId)}::uuid,
          2,
          ${sqlJson({ sessionId: "away-expiry-device", surface: "achievements-concurrency-test" })}
        )`,
      ),
      "rival confirmation at expiry",
    ),
    runSql(
      serviceSql(
        `select public.run_pachanga_external_result_expiry_v1(
          ${sqlText(expirySweepOperationId)}::uuid,
          20
        )`,
      ),
      "expiry worker",
    ),
  ]);
  assert.ok(
    expiryRace.some((result) => result.code === 0),
    `At least one expiry contender must complete: ${JSON.stringify(expiryRace)}`,
  );
  for (const failed of expiryRace.filter((result) => result.code !== 0)) {
    assert.match(
      failed.stderr,
      /External match revision is newer|Only a pending rival result can be confirmed|could not serialize|could not obtain lock/i,
    );
  }

  const expiryEvidence = lastJson(
    await runOk(
      `select jsonb_build_object(
        'state', matches.state,
        'revision', matches.revision,
        'officialVersion', matches.official_version,
        'officialEvents', (
          select count(*) from public.pachanga_external_result_events events
          where events.external_match_id = matches.id
            and events.event_type in ('match_result_confirmed', 'match_result_auto_confirmed')
        ),
        'activeFacts', (
          select count(*) from public.pachanga_progression_match_facts facts
          where facts.source_kind = 'external_result'
            and facts.source_match_id = matches.id::text
            and facts.state = 'active'
        ),
        'factTeams', (
          select count(distinct facts.group_id) from public.pachanga_progression_match_facts facts
          where facts.source_kind = 'external_result'
            and facts.source_match_id = matches.id::text
            and facts.state = 'active'
        )
      )
      from public.pachanga_external_matches matches
      where matches.id = ${sqlText(expiryMatchId)}::uuid`,
      "expiry concurrency evidence",
    ),
    "expiry concurrency evidence",
  );
  assert.ok(["confirmed", "auto_confirmed"].includes(expiryEvidence.state));
  assert.equal(expiryEvidence.revision, 3);
  assert.equal(expiryEvidence.officialVersion, 1);
  assert.equal(expiryEvidence.officialEvents, 1);
  assert.equal(expiryEvidence.activeFacts, 2);
  assert.equal(expiryEvidence.factTeams, 2);

  const [homeSnapshotOutput, awaySnapshotOutput] = await Promise.all([
    runOk(
      authenticatedSql(
        homeOwnerId,
        `select public.get_pachanga_external_results_snapshot_v1(${sqlText(homeGroupId)}::uuid)`,
      ),
      "home canonical external snapshot",
    ),
    runOk(
      authenticatedSql(
        awayOwnerId,
        `select public.get_pachanga_external_results_snapshot_v1(${sqlText(awayGroupId)}::uuid)`,
      ),
      "away canonical external snapshot",
    ),
  ]);
  const homeSnapshot = lastJson(homeSnapshotOutput, "home canonical external snapshot");
  const awaySnapshot = lastJson(awaySnapshotOutput, "away canonical external snapshot");
  const homeExpiryMatch = homeSnapshot.matches.find((match) => match.id === expiryMatchId);
  const awayExpiryMatch = awaySnapshot.matches.find((match) => match.id === expiryMatchId);
  assert.ok(homeExpiryMatch && awayExpiryMatch, "Both teams must receive the canonical external match");
  assert.equal(homeExpiryMatch.state, awayExpiryMatch.state);
  assert.equal(homeExpiryMatch.revision, awayExpiryMatch.revision);
  assert.equal(homeExpiryMatch.officialVersion, awayExpiryMatch.officialVersion);
  assert.equal(homeExpiryMatch.serverSequence, awayExpiryMatch.serverSequence);

  const rewards = lastJson(
    await runOk(
      `select coalesce(jsonb_agg(jsonb_build_object(
        'id', recipients.reward_grant_id,
        'boxId', recipients.box_id,
        'revision', recipients.revision,
        'key', rewards.reward_key
      ) order by rewards.reward_key), '[]'::jsonb)
      from public.pachanga_reward_recipients recipients
      join public.pachanga_reward_grants rewards
        on rewards.id = recipients.reward_grant_id
      where recipients.user_id = ${sqlText(homeOwnerId)}::uuid
        and recipients.status = 'pending'
        and rewards.group_id = ${sqlText(homeGroupId)}::uuid
        and rewards.state = 'active'`,
      "pending reward list",
    ),
    "pending reward list",
  );
  assert.ok(rewards.length >= 2, "The confirmed win must create at least two pending team rewards");
  const [replayReward, staleRaceReward] = rewards;

  const replaySql = authenticatedSql(
    homeOwnerId,
    `select public.open_pachanga_reward_box_v2(
      ${sqlText(replayReward.boxId)}::uuid,
      ${sqlText(rewardReplayOperationId)}::uuid,
      ${Number(replayReward.revision)},
      ${sqlJson({ sessionId: "reward-replay-device", surface: "achievements-concurrency-test" })}
    )`,
  );
  const rewardReplayRace = await Promise.all([
    runSql(replaySql, "reward replay device A"),
    runSql(replaySql, "reward replay device B"),
  ]);
  assert.equal(
    rewardReplayRace.filter((result) => result.code === 0).length,
    2,
    `Both copies of one operation must replay successfully: ${JSON.stringify(rewardReplayRace)}`,
  );
  const replayA = lastJson(rewardReplayRace[0].stdout, "reward replay device A");
  const replayB = lastJson(rewardReplayRace[1].stdout, "reward replay device B");
  assert.deepEqual(replayA, replayB);
  const replayEvidence = lastJson(
    await runOk(
      `select jsonb_build_object(
        'receipts', (
          select count(*) from public.pachanga_reward_open_receipts
          where operation_id = ${sqlText(rewardReplayOperationId)}::uuid
        ),
        'events', (
          select count(*) from public.pachanga_progression_events
          where event_type = 'reward_opened'
            and reward_grant_id = ${sqlText(replayReward.id)}::uuid
        )
      )`,
      "reward replay evidence",
    ),
    "reward replay evidence",
  );
  assert.deepEqual(replayEvidence, { receipts: 1, events: 1 });

  const rewardRaceSql = (operationId, sessionId) => authenticatedSql(
    homeOwnerId,
    `select public.open_pachanga_reward_box_v2(
      ${sqlText(staleRaceReward.boxId)}::uuid,
      ${sqlText(operationId)}::uuid,
      ${Number(staleRaceReward.revision)},
      ${sqlJson({ sessionId, surface: "achievements-concurrency-test" })}
    )`,
  );
  const rewardRace = await Promise.all([
    runSql(rewardRaceSql(rewardRaceOperationAId, "reward-device-a"), "reward device A"),
    runSql(rewardRaceSql(rewardRaceOperationBId, "reward-device-b"), "reward device B"),
  ]);
  const rewardWinners = rewardRace.filter((result) => result.code === 0);
  assert.equal(rewardWinners.length, 2, `Both devices must converge on the opened box: ${JSON.stringify(rewardRace)}`);
  const raceResponses = rewardWinners.map((result) => lastJson(result.stdout, result.label));
  assert.equal(
    raceResponses.filter((response) => response.alreadyOpened === false).length,
    1,
    "Exactly one device must perform the transition",
  );
  assert.equal(
    raceResponses.filter((response) => response.alreadyOpened === true).length,
    1,
    "The other device must receive the canonical already-opened state",
  );
  const raceEvidence = lastJson(
    await runOk(
      `select jsonb_build_object(
        'receipts', (select count(*) from public.pachanga_reward_open_receipts
          where box_id = ${sqlText(staleRaceReward.boxId)}::uuid),
        'events', (select count(*) from public.pachanga_progression_events
          where event_type = 'reward_opened'
            and payload ->> 'boxId' = ${sqlText(staleRaceReward.boxId)}),
        'ledgerEntries', (select count(*) from public.pachanga_player_points_ledger
          where source_box_id = ${sqlText(staleRaceReward.boxId)}::uuid),
        'inventoryEntries', (select count(*) from public.pachanga_player_reward_inventory
          where source_box_id = ${sqlText(staleRaceReward.boxId)}::uuid)
      )`,
      "reward race evidence",
    ),
    "reward race evidence",
  );
  assert.equal(raceEvidence.receipts, 2);
  assert.equal(raceEvidence.events, 1);
  assert.ok(raceEvidence.ledgerEntries <= 1, "Concurrent opening must append at most one point entry");
  assert.ok(raceEvidence.inventoryEntries <= 1, "Concurrent opening must add at most one inventory item");
  assert.ok(
    raceEvidence.ledgerEntries + raceEvidence.inventoryEntries >= 1,
    "The winning transaction must persist the sealed reward exactly once",
  );
} finally {
  await runOk(cleanupSql, "achievements concurrency fixture cleanup");
}

console.error("[achievements-crests concurrency] passed");
