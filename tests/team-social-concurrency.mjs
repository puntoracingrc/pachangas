import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.TEAM_SOCIAL_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const sqlTimeoutMs = Number(process.env.TEAM_SOCIAL_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("TEAM_SOCIAL_DATABASE_URL is required for the social concurrency test");

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

const senderUserId = randomUUID();
const receiverUserId = randomUUID();
const senderGroupId = randomUUID();
const receiverGroupId = randomUUID();
const createOperationId = randomUUID();
const acceptOperationId = randomUUID();
const rejectOperationId = randomUUID();
const initialProfileOperationId = randomUUID();
const profileOperationAId = randomUUID();
const profileOperationBId = randomUUID();
const receiverCode = `SC${receiverGroupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`;
let challengeId = null;

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(senderUserId)}::uuid, ${sqlText(`social-${senderUserId}@example.test`)}),
  (${sqlText(receiverUserId)}::uuid, ${sqlText(`social-${receiverUserId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${sqlText(senderGroupId)}::uuid, ${sqlText(senderUserId)}::uuid, 'Concurrent sender',
   ${sqlText(`SC${senderGroupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)},
   ${sqlJson({ activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] })}),
  (${sqlText(receiverGroupId)}::uuid, ${sqlText(receiverUserId)}::uuid, 'Concurrent receiver',
   ${sqlText(receiverCode)},
   ${sqlJson({ activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] })});
insert into public.pachanga_group_members(group_id, user_id, role) values
  (${sqlText(senderGroupId)}::uuid, ${sqlText(senderUserId)}::uuid, 'owner'),
  (${sqlText(receiverGroupId)}::uuid, ${sqlText(receiverUserId)}::uuid, 'owner');
`;

const cleanupSql = `
delete from public.pachanga_challengeable_team_profile_events
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_challengeable_team_operation_receipts
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_team_challenge_events where challenge_id in (
  select id from public.pachanga_team_challenges
  where sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_match_scorers where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_match_participants where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_result_attestations where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_result_versions where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_result_events where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_result_operation_receipts where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_match_group_state where external_match_id in (
  select matches.id from public.pachanga_external_matches matches
  join public.pachanga_team_challenges challenges on challenges.id=matches.challenge_id
  where challenges.sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or challenges.receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_external_matches where challenge_id in (
  select id from public.pachanga_team_challenges
  where sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
     or receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
);
delete from public.pachanga_team_social_operation_receipts
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_team_challenges
where sender_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
   or receiver_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_known_opponents
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid)
   or opponent_group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_group_members
where group_id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from public.pachanga_groups
where id in (${sqlText(senderGroupId)}::uuid, ${sqlText(receiverGroupId)}::uuid);
delete from auth.users where id in (${sqlText(senderUserId)}::uuid, ${sqlText(receiverUserId)}::uuid);
`;

try {
  await runOk(setupSql, "social concurrency fixture setup");
  const createdOutput = await runOk(
    authenticatedSql(
      senderUserId,
      `select public.create_pachanga_team_challenge_authoritative(
        ${sqlText(senderGroupId)}::uuid,
        ${sqlText(receiverCode)},
        clock_timestamp() + interval '7 days',
        'futbol7', 'Concurrent field', 'Concurrent address', null, null, null,
        ${sqlText(createOperationId)}::uuid, 0,
        ${sqlJson({ sessionId: "sender-device", surface: "concurrency-test" })}
      )`,
    ),
    "create concurrent challenge",
  );
  const created = lastJson(createdOutput, "create concurrent challenge");
  challengeId = created.challenges[0]?.id;
  assert.ok(challengeId, "The challenge creation did not return its canonical id");

  const actionSql = (action, operationId, sessionId) => authenticatedSql(
    receiverUserId,
    `select public.respond_pachanga_team_challenge_authoritative(
      ${sqlText(receiverGroupId)}::uuid,
      ${sqlText(challengeId)}::uuid,
      ${sqlText(action)}, null, null, null, null, null, null, null,
      ${sqlText(operationId)}::uuid, 1,
      ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );

  const results = await Promise.all([
    runSql(actionSql("accept", acceptOperationId, "receiver-device-a"), "accept"),
    runSql(actionSql("reject", rejectOperationId, "receiver-device-b"), "reject"),
  ]);
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `Exactly one concurrent response must win: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `Exactly one stale response must fail: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, /Challenge revision is newer|could not serialize|could not obtain lock/i);

  const winner = lastJson(winners[0].stdout, "winning response");
  assert.equal(winner.challenges[0]?.revision, 2);
  assert.ok(["accepted", "rejected"].includes(winner.challenges[0]?.status));

  const [senderSnapshotOutput, receiverSnapshotOutput] = await Promise.all([
    runOk(
      authenticatedSql(senderUserId, `select public.get_pachanga_team_social_snapshot(${sqlText(senderGroupId)}::uuid)`),
      "sender canonical snapshot",
    ),
    runOk(
      authenticatedSql(receiverUserId, `select public.get_pachanga_team_social_snapshot(${sqlText(receiverGroupId)}::uuid)`),
      "receiver canonical snapshot",
    ),
  ]);
  const senderSnapshot = lastJson(senderSnapshotOutput, "sender canonical snapshot");
  const receiverSnapshot = lastJson(receiverSnapshotOutput, "receiver canonical snapshot");
  assert.equal(senderSnapshot.challenges[0]?.id, challengeId);
  assert.equal(receiverSnapshot.challenges[0]?.id, challengeId);
  assert.equal(senderSnapshot.challenges[0]?.status, receiverSnapshot.challenges[0]?.status);
  assert.equal(senderSnapshot.challenges[0]?.revision, 2);
  assert.equal(receiverSnapshot.challenges[0]?.revision, 2);
  assert.equal(senderSnapshot.serverSequence, receiverSnapshot.serverSequence);

  const evidence = await runOk(
    `select jsonb_build_object(
      'events', (select count(*) from public.pachanga_team_challenge_events where challenge_id = ${sqlText(challengeId)}::uuid),
      'receipts', (select count(*) from public.pachanga_team_social_operation_receipts where operation_id in (
        ${sqlText(createOperationId)}::uuid, ${sqlText(acceptOperationId)}::uuid, ${sqlText(rejectOperationId)}::uuid
      ))
    )`,
    "concurrency evidence",
  );
  assert.deepEqual(lastJson(evidence, "concurrency evidence"), { events: 2, receipts: 2 });

  const publicProfileSql = (radius, operationId, expectedRevision, sessionId) => authenticatedSql(
    receiverUserId,
    `select public.upsert_pachanga_challengeable_team_profile_authoritative(
      ${sqlText(receiverGroupId)}::uuid,
      true,
      'Barcelona',
      'concurrent-public-zone',
      41.3874,
      2.1686,
      ${radius},
      0,
      100,
      array['futbol7'],
      ${sqlJson([{ day: 4, start: "20:00", end: "22:00" }])},
      ${sqlText(operationId)}::uuid,
      ${expectedRevision},
      ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );

  await runOk(
    publicProfileSql(20, initialProfileOperationId, 0, "public-profile-device-initial"),
    "create public challengeable profile",
  );

  const profileResults = await Promise.all([
    runSql(publicProfileSql(30, profileOperationAId, 1, "public-profile-device-a"), "public profile device A"),
    runSql(publicProfileSql(40, profileOperationBId, 1, "public-profile-device-b"), "public profile device B"),
  ]);
  const profileWinners = profileResults.filter((result) => result.code === 0);
  const profileLosers = profileResults.filter((result) => result.code !== 0);
  assert.equal(profileWinners.length, 1, `Exactly one public-profile update must win: ${JSON.stringify(profileResults)}`);
  assert.equal(profileLosers.length, 1, `Exactly one stale public-profile update must fail: ${JSON.stringify(profileResults)}`);
  assert.match(profileLosers[0].stderr, /Server revision is newer|could not serialize|could not obtain lock/i);

  const winningProfile = lastJson(profileWinners[0].stdout, "winning public profile update");
  assert.equal(winningProfile.profileRevision, 2);
  assert.ok([30, 40].includes(winningProfile.profile.travelRadiusKm));

  const [canonicalProfileOutput, canonicalSearchOutput] = await Promise.all([
    runOk(
      authenticatedSql(
        receiverUserId,
        `select public.get_pachanga_challengeable_team_profile(${sqlText(receiverGroupId)}::uuid)`,
      ),
      "receiver canonical public profile",
    ),
    runOk(
      authenticatedSql(
        senderUserId,
        `select public.search_pachanga_challengeable_teams(
          ${sqlText(senderGroupId)}::uuid,
          null, null, null, null, null, null, null, null, null, null, 1, 12
        )`,
      ),
      "sender canonical public search",
    ),
  ]);
  const canonicalProfile = lastJson(canonicalProfileOutput, "receiver canonical public profile");
  const canonicalSearch = lastJson(canonicalSearchOutput, "sender canonical public search");
  const canonicalPublicItem = canonicalSearch.items.find((item) => item.groupId === receiverGroupId);
  assert.ok(canonicalPublicItem, "The receiver must remain visible in the canonical public search");
  assert.equal(canonicalProfile.profileRevision, 2);
  assert.equal(canonicalPublicItem.profileRevision, canonicalProfile.profileRevision);
  assert.equal(canonicalPublicItem.travelRadiusKm, canonicalProfile.profile.travelRadiusKm);
  assert.equal(canonicalSearch.serverSequence, canonicalProfile.serverSequence);

  const publicEvidence = await runOk(
    `select jsonb_build_object(
      'events', (select count(*) from public.pachanga_challengeable_team_profile_events
        where group_id = ${sqlText(receiverGroupId)}::uuid),
      'receipts', (select count(*) from public.pachanga_challengeable_team_operation_receipts
        where operation_id in (
          ${sqlText(initialProfileOperationId)}::uuid,
          ${sqlText(profileOperationAId)}::uuid,
          ${sqlText(profileOperationBId)}::uuid
        ))
    )`,
    "public profile concurrency evidence",
  );
  assert.deepEqual(lastJson(publicEvidence, "public profile concurrency evidence"), { events: 2, receipts: 2 });
} finally {
  await runOk(cleanupSql, "social concurrency fixture cleanup");
}

console.error("[team-social concurrency] passed");
