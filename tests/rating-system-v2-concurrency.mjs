import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.RATING_V2_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const sqlTimeoutMs = Number(process.env.RATING_V2_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) {
  throw new Error("RATING_V2_DATABASE_URL is required for the V2 concurrency test");
}

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
      const timeoutMessage = timedOut ? `SQL timed out after ${sqlTimeoutMs}ms` : "";
      resolve({
        code: timedOut ? 124 : code,
        label,
        sql,
        stderr: [stderr.trim(), timeoutMessage].filter(Boolean).join("\n"),
        stdout: stdout.trim(),
      });
    });
    child.stdin.end(sql);
  });
}

function progress(label) {
  console.error(`[rating-v2 concurrency] ${label}`);
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

async function scalar(sql, label) {
  return runOk(sql, label);
}

async function oneWinner(label, actions) {
  const results = await Promise.all(actions.map((action) => runSql(action.sql, `${label}:${action.client}`)));
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have exactly one accepted client: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must reject exactly one stale client: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, /Server revision is newer|could not serialize|could not obtain lock/i, `${label} must reject stale revision explicitly`);
  const action = actions.find((candidate) => `${label}:${candidate.client}` === winners[0].label);
  const response = lastJson(winners[0].stdout, `${label} winner`);
  assert.ok(Number(response.confirmedRevision) > Number(response.expectedRevision), `${label} must advance revision`);
  assert.ok(Number(response.serverSequence) > 0, `${label} must return a server sequence`);
  assert.equal(response.operationId, action.operationId, `${label} must confirm the winning operation id`);
  return { action, response, result: winners[0] };
}

const groupId = randomUUID();
const evaluatorUserId = randomUUID();
const targetUserId = randomUUID();
const matchId = `match-${randomUUID()}`;
const teamCode = `V2${groupId.replaceAll("-", "").slice(0, 9).toUpperCase()}`;
const baseFacets = {
  pace: 60,
  shooting: 60,
  passing: 60,
  dribbling: 60,
  defending: 60,
  physical: 60,
};
const initialPayload = {
  activeMatchId: matchId,
  matches: [
    {
      id: matchId,
      title: "Concurrency fixture",
      date: "2026-08-20T21:00:00.000Z",
      season: "2026-2027",
      place: "Test pitch",
      configured: true,
      kind: "futbol7",
      targetPlayers: 2,
      fieldCost: 20,
      players: [
        { playerId: "p1", status: "no", paid: false },
        { playerId: "p2", status: "no", paid: false },
      ],
      reservesAttend: false,
      reserveLimit: 0,
      lineupClosed: false,
      teamA: [],
      teamB: [],
    },
  ],
  players: [
    {
      id: "p1",
      name: "Evaluator",
      ownerUserId: evaluatorUserId,
      appearances: 0,
      goals: 0,
      wins: 0,
      injured: false,
      inactive: false,
    },
    {
      id: "p2",
      name: "Target",
      ownerUserId: targetUserId,
      appearances: 0,
      goals: 0,
      wins: 0,
      injured: false,
      inactive: false,
    },
  ],
  siteSettings: {},
  venues: [],
};

const setupSql = `
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;
insert into auth.users(id, email) values
  (${sqlText(evaluatorUserId)}::uuid, ${sqlText(`evaluator-${evaluatorUserId}@example.test`)}),
  (${sqlText(targetUserId)}::uuid, ${sqlText(`target-${targetUserId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values (
  ${sqlText(groupId)}::uuid,
  ${sqlText(evaluatorUserId)}::uuid,
  'V2 concurrency group',
  ${sqlText(teamCode)},
  ${sqlJson(initialPayload)}
);
insert into public.pachanga_group_members(group_id, user_id, role) values
  (${sqlText(groupId)}::uuid, ${sqlText(evaluatorUserId)}::uuid, 'owner'),
  (${sqlText(groupId)}::uuid, ${sqlText(targetUserId)}::uuid, 'player');
insert into public.pachanga_player_profiles(
  user_id, source_group_id, source_player_id, display_name, base_facets,
  calibrated_facets, current_facets, base_overall, calibrated_overall,
  current_overall, rating_reliability, rating_engine_version
) values
  (
    ${sqlText(evaluatorUserId)}::uuid, ${sqlText(groupId)}::uuid, 'p1', 'Evaluator',
    ${sqlJson(baseFacets)}, ${sqlJson(baseFacets)}, ${sqlJson(baseFacets)},
    60, 60, 60, 80, 'pachangas-rating-v2'
  ),
  (
    ${sqlText(targetUserId)}::uuid, ${sqlText(groupId)}::uuid, 'p2', 'Target',
    ${sqlJson({ ...baseFacets, pace: 50, shooting: 50, passing: 50, dribbling: 50, defending: 50, physical: 50 })},
    ${sqlJson({ ...baseFacets, pace: 50, shooting: 50, passing: 50, dribbling: 50, defending: 50, physical: 50 })},
    ${sqlJson({ ...baseFacets, pace: 50, shooting: 50, passing: 50, dribbling: 50, defending: 50, physical: 50 })},
    50, 50, 50, 60, 'pachangas-rating-v2'
  );
`;

const userIds = `${sqlText(evaluatorUserId)}::uuid, ${sqlText(targetUserId)}::uuid`;
const cleanupSql = `
begin;
delete from public.pachanga_reward_open_receipts
where actor_user_id in (${userIds})
   or box_id in (
     select box_id from public.pachanga_reward_recipients
     where group_id = ${sqlText(groupId)}::uuid or user_id in (${userIds})
   );
delete from public.pachanga_player_points_ledger
where user_id in (${userIds})
   or player_profile_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_player_point_accounts where user_id in (${userIds});
delete from public.pachanga_player_reward_inventory
where player_profile_id in (
  select id from public.pachanga_player_profiles where user_id in (${userIds})
);
alter table private.pachanga_reward_box_contents
  disable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from private.pachanga_reward_box_contents contents
using public.pachanga_reward_recipients recipients
where contents.box_id = recipients.box_id
  and (recipients.group_id = ${sqlText(groupId)}::uuid or recipients.user_id in (${userIds}));
alter table private.pachanga_reward_box_contents
  enable trigger keep_pachanga_reward_box_contents_sealed_v1;
delete from public.pachanga_reward_recipients
where group_id = ${sqlText(groupId)}::uuid or user_id in (${userIds});
delete from public.pachanga_progression_events
where group_id = ${sqlText(groupId)}::uuid
   or player_profile_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_team_cosmetic_inventory where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_reward_grants
where group_id = ${sqlText(groupId)}::uuid
   or player_profile_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_achievement_grants
where group_id = ${sqlText(groupId)}::uuid
   or subject_id = ${sqlText(groupId)}::uuid
   or subject_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_progression_player_match_facts
where group_id = ${sqlText(groupId)}::uuid
   or player_profile_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_progression_match_facts
where group_id = ${sqlText(groupId)}::uuid or opponent_group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_team_progression_stats where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_player_progression_stats
where player_profile_id in (
  select id from public.pachanga_player_profiles where user_id in (${userIds})
);
delete from public.pachanga_progression_group_state where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_progression_user_state where user_id in (${userIds});
delete from public.pachanga_match_rating_participants where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_match_rating_snapshots where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_rating_evidence_state_events events
using public.pachanga_individual_rating_evidence evidence
where events.evidence_id = evidence.id and evidence.group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_rating_flags where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_individual_rating_evidence where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_player_rating_snapshots
where group_id = ${sqlText(groupId)}::uuid
   or player_profile_id in (
     select id from public.pachanga_player_profiles where user_id in (${userIds})
   );
delete from public.pachanga_operation_receipts where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_group_events where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_group_members where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_player_profiles
where user_id in (${userIds}) or source_group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_groups where id = ${sqlText(groupId)}::uuid;
delete from auth.users where id in (${userIds});
commit;
`;

try {
  progress("fixture setup");
  await runOk(setupSql, "fixture setup");

const tiedSnapshotIds = [randomUUID(), randomUUID(), randomUUID()];
const expectedTiedSnapshotId = [...tiedSnapshotIds].sort().at(-1);
await runOk(
  `insert into public.pachanga_player_rating_snapshots(
     id, player_profile_id, snapshot_kind, base_facets, calibrated_facets,
     current_facets, base_overall, calibrated_overall, current_overall,
     reliability, evaluator_count, engine_version, created_at
   )
   select snapshot_ids.id,
          profiles.id,
          'recalculation',
          profiles.base_facets,
          profiles.calibrated_facets,
          profiles.current_facets,
          profiles.base_overall,
          profiles.calibrated_overall,
          profiles.current_overall,
          profiles.rating_reliability,
          profiles.rating_evaluator_count,
          'pachangas-rating-v2',
          transaction_timestamp()
   from public.pachanga_player_profiles profiles
   cross join (values
     (${sqlText(tiedSnapshotIds[0])}::uuid),
     (${sqlText(tiedSnapshotIds[1])}::uuid),
     (${sqlText(tiedSnapshotIds[2])}::uuid)
   ) snapshot_ids(id)
   where profiles.user_id = ${sqlText(targetUserId)}::uuid`,
  "same timestamp snapshot setup",
);

const targetProfileId = await scalar(
  `select profiles.id from public.pachanga_player_profiles profiles where profiles.user_id = ${sqlText(targetUserId)}::uuid`,
  "target profile id",
);
const canonicalSnapshotSql = authenticatedSql(
  targetUserId,
  `select public.get_latest_pachanga_player_rating_snapshot_v2(${sqlText(targetProfileId)}::uuid)`,
);
const [snapshotClientAOutput, snapshotClientBOutput] = await Promise.all([
  runOk(canonicalSnapshotSql, "same timestamp snapshot client a"),
  runOk(canonicalSnapshotSql, "same timestamp snapshot client b"),
]);
const snapshotClientA = lastJson(snapshotClientAOutput, "same timestamp snapshot client a");
const snapshotClientB = lastJson(snapshotClientBOutput, "same timestamp snapshot client b");
assert.deepEqual(snapshotClientA, snapshotClientB, "clients must receive one canonical snapshot when created_at ties");
assert.equal(snapshotClientA.id, expectedTiedSnapshotId, "canonical snapshot must use the stable UUID tie-breaker");

async function readCanonical(userId) {
  const output = await runOk(
    authenticatedSql(
      userId,
      `select jsonb_build_object(
        'confirmedRevision', groups.payload_revision,
        'payload', groups.payload
      ) from public.pachanga_groups groups where groups.id = ${sqlText(groupId)}::uuid`,
    ),
    "canonical read",
  );
  return lastJson(output, "canonical read");
}

async function assertConverged(label) {
  const [clientA, clientB] = await Promise.all([
    readCanonical(evaluatorUserId),
    readCanonical(targetUserId),
  ]);
  assert.deepEqual(clientA, clientB, `${label}: both clients must converge to the same canonical snapshot`);
  return clientA;
}

function currentMatch(canonical) {
  const match = canonical.payload.matches.find((candidate) => candidate.id === matchId);
  assert.ok(match, "canonical match missing");
  return match;
}

function ratingAction(client, operationId, revision, comparisons) {
  return {
    client,
    operationId,
    sql: authenticatedSql(
      evaluatorUserId,
      `select public.record_pachanga_individual_rating_authoritative_v2(
        ${sqlText(groupId)}::uuid,
        'p2',
        ${sqlJson(comparisons)},
        ${sqlText(operationId)}::uuid,
        ${revision},
        ${sqlJson({ sessionId: client, surface: "concurrency-test" })}
      )`,
    ),
  };
}

function attendanceAction(client, operationId, revision, status, userId = evaluatorUserId, playerId = "p1") {
  return {
    client,
    operationId,
    playerId,
    status,
    sql: authenticatedSql(
      userId,
      `select public.patch_pachanga_match_player_status_authoritative_v2(
        ${sqlText(groupId)}::uuid,
        ${sqlText(matchId)},
        ${sqlText(playerId)},
        ${sqlText(status)},
        ${sqlText(operationId)}::uuid,
        ${revision},
        ${sqlJson({ sessionId: client, surface: "concurrency-test" })}
      )`,
    ),
  };
}

function lineupAction(client, operationId, revision, teamA, teamB, payerId) {
  const arraySql = (items) => `array[${items.map(sqlText).join(",")}]::text[]`;
  return {
    client,
    operationId,
    payerId,
    teamA,
    teamB,
    sql: authenticatedSql(
      evaluatorUserId,
      `select public.patch_pachanga_match_lineup_authoritative_v2(
        ${sqlText(groupId)}::uuid,
        ${sqlText(matchId)},
        true,
        ${arraySql(teamA)},
        ${arraySql(teamB)},
        ${sqlText(payerId)},
        ${sqlText(operationId)}::uuid,
        ${revision},
        ${sqlJson({ sessionId: client, surface: "concurrency-test" })}
      )`,
    ),
  };
}

function finalizeAction(client, operationId, revision, scoreA, scoreB) {
  return {
    client,
    operationId,
    scoreA,
    scoreB,
    sql: authenticatedSql(
      evaluatorUserId,
      `select public.finalize_pachanga_match_authoritative_v2(
        ${sqlText(groupId)}::uuid,
        ${sqlText(matchId)},
        ${scoreA},
        ${scoreB},
        '[]'::jsonb,
        ${sqlText(operationId)}::uuid,
        ${revision},
        ${sqlJson({ sessionId: client, surface: "concurrency-test" })}
      )`,
    ),
  };
}

const comparisonsA = {
  pace: "MEJOR",
  shooting: "PARECIDO",
  passing: "MEJOR",
  dribbling: "PEOR",
  defending: "PARECIDO",
  physical: "MUCHO_MEJOR",
};
const comparisonsB = {
  pace: "PEOR",
  shooting: "MEJOR",
  passing: "PARECIDO",
  dribbling: "MEJOR",
  defending: "PEOR",
  physical: "PARECIDO",
};

let canonical = await assertConverged("initial state");
let revision = Number(canonical.confirmedRevision);

progress("concurrent first rating");
const firstRating = await oneWinner("concurrent first rating", [
  ratingAction("rating-a", randomUUID(), revision, comparisonsA),
  ratingAction("rating-b", randomUUID(), revision, comparisonsB),
]);
canonical = await assertConverged("first rating");
assert.equal(
  Number(await scalar(`select count(*) from public.pachanga_individual_rating_evidence where group_id = ${sqlText(groupId)}::uuid and state = 'active'`, "active rating count")),
  1,
  "two devices must not create two active ratings",
);
const revisionAfterFirstRating = Number(canonical.confirmedRevision);
assert.equal(revisionAfterFirstRating, Number(firstRating.response.confirmedRevision));
const replayOutput = await runOk(firstRating.action.sql, "first rating idempotent replay");
assert.deepEqual(lastJson(replayOutput, "first rating replay"), firstRating.response, "same operation must replay the stored response");
assert.equal(Number((await readCanonical(evaluatorUserId)).confirmedRevision), revisionAfterFirstRating, "rating replay must not advance revision");

await runOk(
  `
insert into public.pachanga_match_rating_snapshots(group_id, match_id, engine_version, snapshot, finalized_at)
select ${sqlText(groupId)}::uuid, 'shared-' || series, 'pachangas-rating-v2', '{}'::jsonb,
       clock_timestamp() + make_interval(mins => series)
from generate_series(1, 3) series;
insert into public.pachanga_match_rating_participants(
  group_id, match_id, local_player_id, player_profile_id, team_side,
  attendance_confirmed, was_reserve, card_snapshot
)
select ${sqlText(groupId)}::uuid, 'shared-' || series, 'p1',
       (select id from public.pachanga_player_profiles where user_id = ${sqlText(evaluatorUserId)}::uuid),
       'A', true, false, '{"currentOverall":60}'::jsonb
from generate_series(1, 3) series
union all
select ${sqlText(groupId)}::uuid, 'shared-' || series, 'p2',
       (select id from public.pachanga_player_profiles where user_id = ${sqlText(targetUserId)}::uuid),
       'B', true, false, '{"currentOverall":50}'::jsonb
from generate_series(1, 3) series;
`,
  "shared match setup",
);

revision = Number((await readCanonical(evaluatorUserId)).confirmedRevision);
progress("concurrent rating replacement");
await oneWinner("concurrent rating replacement", [
  ratingAction("replacement-a", randomUUID(), revision, comparisonsA),
  ratingAction("replacement-b", randomUUID(), revision, comparisonsB),
]);
canonical = await assertConverged("rating replacement");
assert.equal(
  Number(await scalar(`select count(*) from public.pachanga_individual_rating_evidence where group_id = ${sqlText(groupId)}::uuid and state = 'active'`, "replacement active count")),
  1,
  "replacement must leave one active opinion",
);
assert.equal(
  Number(await scalar(`select count(*) from public.pachanga_individual_rating_evidence where group_id = ${sqlText(groupId)}::uuid`, "replacement history count")),
  2,
  "replacement must preserve immutable history",
);

revision = Number(canonical.confirmedRevision);
progress("concurrent attendance");
const attendance = await oneWinner("concurrent attendance", [
  attendanceAction("attendance-a", randomUUID(), revision, "voy"),
  attendanceAction("attendance-b", randomUUID(), revision, "duda"),
]);
canonical = await assertConverged("attendance");
let match = currentMatch(canonical);
const p1Entries = match.players.filter((entry) => entry.playerId === "p1");
assert.equal(p1Entries.length, 1, "attendance must not duplicate a participant");
assert.equal(p1Entries[0].status, attendance.action.status, "canonical attendance must match the accepted intent");

if (p1Entries[0].status !== "voy") {
  revision = Number(canonical.confirmedRevision);
  await runOk(attendanceAction("attendance-normalize-p1", randomUUID(), revision, "voy").sql, "normalize p1 attendance");
  canonical = await assertConverged("normalized p1 attendance");
}
revision = Number(canonical.confirmedRevision);
await runOk(
  attendanceAction("attendance-normalize-p2", randomUUID(), revision, "voy", evaluatorUserId, "p2").sql,
  "normalize p2 attendance",
);
canonical = await assertConverged("normalized p2 attendance");

revision = Number(canonical.confirmedRevision);
progress("concurrent lineup");
const lineup = await oneWinner("concurrent lineup", [
  lineupAction("lineup-a", randomUUID(), revision, ["p1"], ["p2"], "p1"),
  lineupAction("lineup-b", randomUUID(), revision, ["p2"], ["p1"], "p2"),
]);
canonical = await assertConverged("lineup");
match = currentMatch(canonical);
assert.equal(match.lineupClosed, true, "accepted lineup must be closed");
assert.deepEqual(match.teamA, lineup.action.teamA, "canonical team A must match the accepted intent");
assert.deepEqual(match.teamB, lineup.action.teamB, "canonical team B must match the accepted intent");
assert.equal(match.payerId, lineup.action.payerId, "canonical payer must match the accepted lineup");
assert.deepEqual([...match.teamA, ...match.teamB].sort(), ["p1", "p2"], "lineup must contain each confirmed player once");

revision = Number(canonical.confirmedRevision);
progress("concurrent finalization");
const finalization = await oneWinner("concurrent finalization", [
  finalizeAction("finalize-a", randomUUID(), revision, 0, 0),
  finalizeAction("finalize-b", randomUUID(), revision, 1, 1),
]);
canonical = await assertConverged("finalization");
match = currentMatch(canonical);
assert.equal(match.closed, true, "match must be finalized once");
assert.equal(match.scoreA, finalization.action.scoreA, "canonical score A must match the accepted intent");
assert.equal(match.scoreB, finalization.action.scoreB, "canonical score B must match the accepted intent");
for (const player of canonical.payload.players) {
  assert.equal(player.appearances, 1, "finalization must increment each participant exactly once");
}
assert.equal(
  Number(await scalar(`select billing_trial_finalized_matches from public.pachanga_groups where id = ${sqlText(groupId)}::uuid`, "finalized billing count")),
  1,
  "concurrent finalization must rotate billing/finalization exactly once",
);
assert.equal(
  Number(await scalar(`select count(*) from public.pachanga_match_rating_snapshots where group_id = ${sqlText(groupId)}::uuid and match_id = ${sqlText(matchId)}`, "finalization snapshot count")),
  1,
  "finalization must persist one canonical rating snapshot",
);
const finalRevision = Number(canonical.confirmedRevision);
const finalReplay = await runOk(finalization.action.sql, "finalization idempotent replay");
assert.deepEqual(lastJson(finalReplay, "finalization replay"), finalization.response, "finalization replay must return the same receipt");
assert.equal(Number((await readCanonical(evaluatorUserId)).confirmedRevision), finalRevision, "finalization replay must not advance revision");

const activeEvidenceId = await scalar(
  `select evidence.id from public.pachanga_individual_rating_evidence evidence
   join public.pachanga_player_profiles evaluator on evaluator.id = evidence.evaluator_profile_id
   where evidence.group_id = ${sqlText(groupId)}::uuid
     and evaluator.user_id = ${sqlText(evaluatorUserId)}::uuid
     and evidence.state = 'active'`,
  "active evidence id",
);
revision = Number((await readCanonical(evaluatorUserId)).confirmedRevision);
const voidActions = ["void-a", "void-b"].map((client) => {
  const operationId = randomUUID();
  return {
    client,
    operationId,
    sql: authenticatedSql(
      evaluatorUserId,
      `select public.void_my_pachanga_individual_rating_v2(
        ${sqlText(activeEvidenceId)}::uuid,
        'Concurrent withdrawal',
        ${sqlText(operationId)}::uuid,
        ${revision},
        ${sqlJson({ sessionId: client, surface: "concurrency-test" })}
      )`,
    ),
  };
});
progress("concurrent void");
await oneWinner("concurrent void", voidActions);
canonical = await assertConverged("void");
assert.equal(
  Number(await scalar(`select count(*) from public.pachanga_individual_rating_evidence where group_id = ${sqlText(groupId)}::uuid and state = 'active'`, "void active count")),
  1,
  "concurrent void must leave one restored active opinion",
);
assert.equal(
  await scalar(`select state from public.pachanga_individual_rating_evidence where id = ${sqlText(activeEvidenceId)}::uuid`, "void selected state"),
  "void",
  "selected evidence must be voided once",
);

const staleRevision = revision;
const beforeReconnect = await readCanonical(evaluatorUserId);
progress("stale reconnect");
const staleReconnect = await runSql(
  attendanceAction("stale-reconnect", randomUUID(), staleRevision, "no").sql,
  "stale reconnect",
);
assert.notEqual(staleReconnect.code, 0, "a stale reconnect must not be silently accepted");
assert.match(staleReconnect.stderr, /Server revision is newer|could not serialize|could not obtain lock/i, "stale reconnect must receive an explicit revision conflict");
const afterReconnect = await assertConverged("stale reconnect reload");
assert.deepEqual(afterReconnect, beforeReconnect, "stale reconnect must not mutate the canonical state before reload");

const eventJournal = lastJson(
  await runOk(
    `select jsonb_build_object(
       'eventCount', count(*),
       'uniqueSequenceCount', count(distinct server_sequence),
       'uniqueOperationCount', count(distinct operation_id),
       'nullSequenceCount', count(*) filter (where server_sequence is null),
       'nullOperationCount', count(*) filter (where operation_id is null)
     )
     from public.pachanga_group_events
     where group_id = ${sqlText(groupId)}::uuid`,
    "server event journal",
  ),
  "server event journal",
);
assert.ok(Number(eventJournal.eventCount) > 0, "the server must preserve an auditable event journal");
assert.equal(eventJournal.nullSequenceCount, 0, "every V2 event must have a server sequence");
assert.equal(eventJournal.nullOperationCount, 0, "every V2 event must retain its operation id");
assert.equal(
  eventJournal.uniqueSequenceCount,
  eventJournal.eventCount,
  "server event sequences must be unique and define the canonical order",
);
assert.equal(
  eventJournal.uniqueOperationCount,
  eventJournal.eventCount,
  "idempotent replays must not duplicate events for one operation",
);
assert.equal(
  Number(afterReconnect.confirmedRevision),
  Number(eventJournal.eventCount),
  "each accepted mutation must advance the group revision and event journal exactly once",
);
assert.ok(
  [7, 8].includes(Number(eventJournal.eventCount)),
  "the attendance winner may require one normalization, but no other event count is valid",
);

  console.log(JSON.stringify({
    groupId,
    cases: [
      "same-timestamp-snapshot",
      "first-rating",
      "rating-replacement",
      "attendance",
      "lineup",
      "finalization",
      "void",
      "stale-reconnect",
    ],
    confirmedRevision: afterReconnect.confirmedRevision,
    serverEventCount: eventJournal.eventCount,
    status: "passed",
  }));
} finally {
  await runOk(cleanupSql, "rating V2 concurrency cleanup");
}
