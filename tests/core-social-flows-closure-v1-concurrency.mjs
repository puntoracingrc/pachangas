import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.CORE_SOCIAL_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.CORE_SOCIAL_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("CORE_SOCIAL_DATABASE_URL is required");

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlJson(value) {
  return `${sqlText(JSON.stringify(value))}::jsonb`;
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

const ownerId = randomUUID();
const nextOwnerId = randomUUID();
const memberId = randomUUID();
const requesterAId = randomUUID();
const requesterBId = randomUUID();
const rivalOwnerId = randomUUID();
const groupId = randomUUID();
const rivalGroupId = randomUUID();
const profileAId = randomUUID();
const profileBId = randomUUID();
const openMatchId = randomUUID();
const matchId = `core-social-${randomUUID()}`;
const challengeId = randomUUID();

const fixturePayload = {
  activeMatchId: matchId,
  players: [
    { id: "owner-player", name: "Owner", ownerUserId: ownerId, position: "Mediocentro / pivote", rating: 7, ratingVotes: [] },
    { id: "member-player", name: "Member", ownerUserId: memberId, position: "Defensa central", rating: 6, ratingVotes: [] },
  ],
  matches: [{
    id: matchId,
    title: "Core social last seat",
    date: "2030-08-09T20:00:00.000Z",
    place: "Synthetic field",
    kind: "futbol7",
    configured: true,
    lineupClosed: false,
    targetPlayers: 2,
    reserveLimit: 0,
    reservesAttend: false,
    players: [{ playerId: "owner-player", status: "voy", paid: true }],
    teamA: ["owner-player"],
    teamB: [],
    lineupSlots: { teamA: ["owner-player"], teamB: [null] },
    publicOpen: true,
    publicOpenSlots: 1,
  }],
  siteSettings: {},
  venues: [],
};

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(ownerId)}::uuid, ${sqlText(`owner-${ownerId}@example.test`)}),
  (${sqlText(nextOwnerId)}::uuid, ${sqlText(`next-${nextOwnerId}@example.test`)}),
  (${sqlText(memberId)}::uuid, ${sqlText(`member-${memberId}@example.test`)}),
  (${sqlText(requesterAId)}::uuid, ${sqlText(`request-a-${requesterAId}@example.test`)}),
  (${sqlText(requesterBId)}::uuid, ${sqlText(`request-b-${requesterBId}@example.test`)}),
  (${sqlText(rivalOwnerId)}::uuid, ${sqlText(`rival-${rivalOwnerId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'Core Social A',
   ${sqlText(`CA${groupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)}, ${sqlJson(fixturePayload)}),
  (${sqlText(rivalGroupId)}::uuid, ${sqlText(rivalOwnerId)}::uuid, 'Core Social B',
   ${sqlText(`CB${rivalGroupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)},
   ${sqlJson({ activeMatchId: null, matches: [], players: [], siteSettings: {}, venues: [] })});
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  (${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'owner', 'Owner'),
  (${sqlText(groupId)}::uuid, ${sqlText(nextOwnerId)}::uuid, 'admin', 'Next owner'),
  (${sqlText(groupId)}::uuid, ${sqlText(memberId)}::uuid, 'player', 'Member'),
  (${sqlText(rivalGroupId)}::uuid, ${sqlText(rivalOwnerId)}::uuid, 'owner', 'Rival owner');
insert into public.pachanga_market_profiles(id,user_id,source_player_id,display_name,position,media,modalities,open_to_guest,open_to_group,active) values
  (${sqlText(profileAId)}::uuid,${sqlText(requesterAId)}::uuid,'market-a','Requester A','Delantero centro',6.5,array['futbol7'],true,true,true),
  (${sqlText(profileBId)}::uuid,${sqlText(requesterBId)}::uuid,'market-b','Requester B','Defensa central',6.4,array['futbol7'],true,true,true);
`;

const cleanupSql = `
delete from public.pachanga_user_notifications where recipient_user_id in (
  ${sqlText(ownerId)}::uuid,${sqlText(nextOwnerId)}::uuid,${sqlText(memberId)}::uuid,
  ${sqlText(requesterAId)}::uuid,${sqlText(requesterBId)}::uuid,${sqlText(rivalOwnerId)}::uuid
);
delete from public.pachanga_team_challenge_events where challenge_id=${sqlText(challengeId)}::uuid;
delete from public.pachanga_team_social_operation_receipts where group_id in (${sqlText(groupId)}::uuid,${sqlText(rivalGroupId)}::uuid);
delete from public.pachanga_team_challenges where id=${sqlText(challengeId)}::uuid;
delete from public.pachanga_group_members where group_id in (${sqlText(groupId)}::uuid,${sqlText(rivalGroupId)}::uuid);
delete from public.pachanga_groups where id in (${sqlText(groupId)}::uuid,${sqlText(rivalGroupId)}::uuid);
delete from public.pachanga_market_profiles where id in (${sqlText(profileAId)}::uuid,${sqlText(profileBId)}::uuid);
delete from auth.users where id in (
  ${sqlText(ownerId)}::uuid,${sqlText(nextOwnerId)}::uuid,${sqlText(memberId)}::uuid,
  ${sqlText(requesterAId)}::uuid,${sqlText(requesterBId)}::uuid,${sqlText(rivalOwnerId)}::uuid
);
`;

try {
  await runOk(setupSql, "core social concurrency fixture setup");

  const initialRevision = Number(await runOk(
    `select payload_revision from public.pachanga_groups where id=${sqlText(groupId)}::uuid`,
    "initial group revision",
  ));
  const leaveOperationId = randomUUID();
  const removeOperationId = randomUUID();
  const membershipResults = await Promise.all([
    runSql(authenticatedSql(memberId, `select public.leave_pachanga_group_authoritative_v1(
      ${sqlText(groupId)}::uuid,${sqlText(leaveOperationId)}::uuid,${initialRevision},
      ${sqlJson({ sessionId: "member-device" })})`), "member self-leave"),
    runSql(authenticatedSql(ownerId, `select public.remove_pachanga_group_member_authoritative_v1(
      ${sqlText(groupId)}::uuid,${sqlText(memberId)}::uuid,${sqlText(removeOperationId)}::uuid,${initialRevision},
      ${sqlJson({ sessionId: "owner-device" })})`), "admin member removal"),
  ]);
  assert.ok(membershipResults.some(({ code }) => code === 0), JSON.stringify(membershipResults));
  const membershipEvidence = lastJson(await runOk(`select jsonb_build_object(
    'memberships',(select count(*) from public.pachanga_group_members where group_id=${sqlText(groupId)}::uuid and user_id=${sqlText(memberId)}::uuid),
    'events',(select count(*) from public.pachanga_group_events where group_id=${sqlText(groupId)}::uuid and operation_id in (${sqlText(leaveOperationId)}::uuid,${sqlText(removeOperationId)}::uuid)),
    'receipts',(select count(*) from public.pachanga_operation_receipts where group_id=${sqlText(groupId)}::uuid and operation_id in (${sqlText(leaveOperationId)}::uuid,${sqlText(removeOperationId)}::uuid))
  )`, "membership convergence"), "membership convergence");
  assert.deepEqual(membershipEvidence, { events: 1, memberships: 0, receipts: 2 });

  const transferRevision = Number(await runOk(
    `select payload_revision from public.pachanga_groups where id=${sqlText(groupId)}::uuid`,
    "transfer revision",
  ));
  const transferOperationId = randomUUID();
  const ownerLeaveOperationId = randomUUID();
  const ownerRace = await Promise.all([
    runSql(authenticatedSql(ownerId, `select public.transfer_pachanga_group_ownership_authoritative_v1(
      ${sqlText(groupId)}::uuid,${sqlText(nextOwnerId)}::uuid,${sqlText(transferOperationId)}::uuid,${transferRevision},'{}'::jsonb)`), "owner transfer"),
    runSql(authenticatedSql(ownerId, `select public.leave_pachanga_group_authoritative_v1(
      ${sqlText(groupId)}::uuid,${sqlText(ownerLeaveOperationId)}::uuid,${transferRevision},'{}'::jsonb)`), "owner concurrent leave"),
  ]);
  assert.equal(ownerRace.filter(({ code }) => code === 0).length, 1, JSON.stringify(ownerRace));
  assert.match(ownerRace.find(({ code }) => code !== 0)?.stderr ?? "", /Transfer ownership|revision is newer/i);
  const ownerEvidence = lastJson(await runOk(`select jsonb_build_object(
    'ownerId',(select owner_id from public.pachanga_groups where id=${sqlText(groupId)}::uuid),
    'formerOwnerRole',(select role from public.pachanga_group_members where group_id=${sqlText(groupId)}::uuid and user_id=${sqlText(ownerId)}::uuid)
  )`, "owner convergence"), "owner convergence");
  assert.deepEqual(ownerEvidence, { formerOwnerRole: "admin", ownerId: nextOwnerId });

  await runOk(`insert into public.pachanga_team_challenges(
    id,sender_group_id,receiver_group_id,status,scheduled_at,modality,field_name,field_address,
    last_proposed_by_group_id,created_by,updated_by
  ) values (
    ${sqlText(challengeId)}::uuid,${sqlText(groupId)}::uuid,${sqlText(rivalGroupId)}::uuid,'proposed',
    clock_timestamp()-interval '1 second','futbol7','Race field','Race address',${sqlText(groupId)}::uuid,
    ${sqlText(nextOwnerId)}::uuid,${sqlText(nextOwnerId)}::uuid
  )`, "challenge expiry fixture");
  const expireOperationId = randomUUID();
  const acceptOperationId = randomUUID();
  const challengeRace = await Promise.all([
    runSql(authenticatedSql(nextOwnerId, `select public.reconcile_pachanga_team_challenge_expiry_v1(
      ${sqlText(groupId)}::uuid,${sqlText(challengeId)}::uuid,${sqlText(expireOperationId)}::uuid,1,'{}'::jsonb)`), "challenge expiry"),
    runSql(authenticatedSql(rivalOwnerId, `select public.respond_pachanga_team_challenge_authoritative(
      ${sqlText(rivalGroupId)}::uuid,${sqlText(challengeId)}::uuid,'accept',null,null,null,null,null,null,null,
      ${sqlText(acceptOperationId)}::uuid,1,'{}'::jsonb)`), "challenge accept at expiry"),
  ]);
  assert.ok(challengeRace.some(({ code }) => code === 0), JSON.stringify(challengeRace));
  const challengeEvidence = lastJson(await runOk(`select jsonb_build_object(
    'status',(select status from public.pachanga_team_challenges where id=${sqlText(challengeId)}::uuid),
    'transitions',(select count(*) from public.pachanga_team_challenge_events where challenge_id=${sqlText(challengeId)}::uuid and event_type in ('accepted','expired')),
    'expiryEvents',(select count(*) from public.pachanga_team_challenge_events where challenge_id=${sqlText(challengeId)}::uuid and event_type='expired')
  )`, "challenge convergence"), "challenge convergence");
  assert.deepEqual(challengeEvidence, { expiryEvents: 1, status: "expired", transitions: 1 });

  const marketRevision = Number(await runOk(
    `select payload_revision from public.pachanga_groups where id=${sqlText(groupId)}::uuid`,
    "market group revision",
  ));
  await runOk(`insert into public.pachanga_open_matches(
    id,source_group_id,source_match_id,source_payload_revision,group_name,title,date,modality,
    field_name,target_players,confirmed_count,open_slots,active,created_by
  ) values (
    ${sqlText(openMatchId)}::uuid,${sqlText(groupId)}::uuid,${sqlText(matchId)},${marketRevision},
    'Core Social A','Core social last seat','2030-08-09T20:00:00Z','futbol7','Synthetic field',2,1,1,true,
    ${sqlText(nextOwnerId)}::uuid
  )`, "last seat fixture");
  const requestOperationA = randomUUID();
  const requestOperationB = randomUUID();
  const [requestAOutput, requestBOutput] = await Promise.all([
    runOk(authenticatedSql(requesterAId, `select public.request_pachanga_open_match_authoritative_v2(
      ${sqlText(openMatchId)}::uuid,${sqlText(requestOperationA)}::uuid,${marketRevision},'{}'::jsonb)`), "request last seat A"),
    runOk(authenticatedSql(requesterBId, `select public.request_pachanga_open_match_authoritative_v2(
      ${sqlText(openMatchId)}::uuid,${sqlText(requestOperationB)}::uuid,${marketRevision},'{}'::jsonb)`), "request last seat B"),
  ]);
  const requestAId = lastJson(requestAOutput, "request A").request.id;
  const requestBId = lastJson(requestBOutput, "request B").request.id;
  const reviewOperationA = randomUUID();
  const reviewOperationB = randomUUID();
  const reviewRevision = Number(await runOk(
    `select payload_revision from public.pachanga_groups where id=${sqlText(groupId)}::uuid`,
    "last seat review revision",
  ));
  const lastSeatRace = await Promise.all([
    runSql(authenticatedSql(nextOwnerId, `select public.review_pachanga_open_match_request_authoritative_v2(
      ${sqlText(groupId)}::uuid,${sqlText(requestAId)}::uuid,'accepted',${sqlText(reviewOperationA)}::uuid,${reviewRevision},'{}'::jsonb)`), "accept last seat A"),
    runSql(authenticatedSql(ownerId, `select public.review_pachanga_open_match_request_authoritative_v2(
      ${sqlText(groupId)}::uuid,${sqlText(requestBId)}::uuid,'accepted',${sqlText(reviewOperationB)}::uuid,${reviewRevision},'{}'::jsonb)`), "accept last seat B"),
  ]);
  assert.equal(lastSeatRace.filter(({ code }) => code === 0).length, 1, JSON.stringify(lastSeatRace));
  const lastSeatEvidence = lastJson(await runOk(`select jsonb_build_object(
    'accepted',(select count(*) from public.pachanga_open_match_requests where id in (${sqlText(requestAId)}::uuid,${sqlText(requestBId)}::uuid) and status='accepted'),
    'rejected',(select count(*) from public.pachanga_open_match_requests where id in (${sqlText(requestAId)}::uuid,${sqlText(requestBId)}::uuid) and status='rejected'),
    'active',(select active from public.pachanga_open_matches where id=${sqlText(openMatchId)}::uuid),
    'openSlots',(select open_slots from public.pachanga_open_matches where id=${sqlText(openMatchId)}::uuid),
    'access',(select count(*) from public.pachanga_match_guest_access where source_kind='open_request' and source_id in (${sqlText(requestAId)}::uuid,${sqlText(requestBId)}::uuid))
  )`, "last seat convergence"), "last seat convergence");
  assert.deepEqual(lastSeatEvidence, { accepted: 1, access: 1, active: false, openSlots: 0, rejected: 1 });
} finally {
  await runOk(cleanupSql, "core social concurrency fixture cleanup");
}

console.error("[core social concurrency] passed");
