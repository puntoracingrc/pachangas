import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.MATCH_GUEST_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "/opt/homebrew/bin/psql";
const timeoutMs = Number(process.env.MATCH_GUEST_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("MATCH_GUEST_DATABASE_URL is required");

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
const adminId = randomUUID();
const guestId = randomUUID();
const groupId = randomUUID();
const marketProfileId = randomUUID();
const openMatchId = randomUUID();
const inviteOperationId = randomUUID();
const acceptOperationId = randomUUID();
const rejectOperationId = randomUUID();
const confirmOperationId = randomUUID();
const dismissOperationId = randomUUID();
const matchId = `concurrent-${randomUUID()}`;
let invitationId;
let accessId;
let reviewId;

const setupSql = `
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;
insert into auth.users(id, email) values
  (${sqlText(ownerId)}::uuid, ${sqlText(`owner-${ownerId}@example.test`)}),
  (${sqlText(adminId)}::uuid, ${sqlText(`admin-${adminId}@example.test`)}),
  (${sqlText(guestId)}::uuid, ${sqlText(`guest-${guestId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  ${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'Concurrent guest group',
  ${sqlText(`CG${groupId.replaceAll("-", "").slice(0, 8).toUpperCase()}`)},
  ${sqlJson({
    activeMatchId: matchId,
    players: [{
      id: "owner-player", name: "Owner", phone: "+34999999999",
      ownerUserId: ownerId, position: "Mediocentro / pivote", rating: 7, ratingVotes: [],
    }],
    matches: [{
      id: matchId, title: "Concurrent match", date: "2030-08-03T21:00:00.000Z",
      place: "Synthetic field", kind: "futbol7", configured: true, lineupClosed: false,
      targetPlayers: 4, reserveLimit: 0, reservesAttend: false,
      players: [{ playerId: "owner-player", status: "voy", paid: true }],
      teamA: ["owner-player"], teamB: [],
      lineupSlots: { teamA: ["owner-player", null], teamB: [null, null] },
      publicOpen: true, publicOpenSlots: 3,
    }],
    siteSettings: {}, venues: [],
  })}
);
insert into public.pachanga_group_members(group_id, user_id, role) values
  (${sqlText(groupId)}::uuid, ${sqlText(ownerId)}::uuid, 'owner'),
  (${sqlText(groupId)}::uuid, ${sqlText(adminId)}::uuid, 'admin');
insert into public.pachanga_market_profiles(
  id, user_id, source_player_id, display_name, position, media, modalities,
  open_to_guest, open_to_group, active
) values (
  ${sqlText(marketProfileId)}::uuid, ${sqlText(guestId)}::uuid, 'concurrent-guest',
  'Concurrent Guest', 'Delantero centro', 6.5, array['futbol7'], true, true, true
);
insert into public.pachanga_open_matches(
  id, source_group_id, source_match_id, source_payload_revision, group_name, title,
  date, modality, field_name, target_players, confirmed_count, open_slots, match_url,
  created_by, active
) values (
  ${sqlText(openMatchId)}::uuid, ${sqlText(groupId)}::uuid, ${sqlText(matchId)}, 0,
  'Concurrent guest group', 'Concurrent match', '2030-08-03T21:00:00Z', 'futbol7',
  'Synthetic field', 4, 1, 3, '/synthetic', ${sqlText(ownerId)}::uuid, true
);
`;

const cleanupSql = `
delete from public.pachanga_user_notifications where recipient_user_id in (
  ${sqlText(ownerId)}::uuid, ${sqlText(adminId)}::uuid, ${sqlText(guestId)}::uuid
);
delete from public.pachanga_group_members where group_id = ${sqlText(groupId)}::uuid;
delete from public.pachanga_groups where id = ${sqlText(groupId)}::uuid;
delete from auth.users where id in (
  ${sqlText(ownerId)}::uuid, ${sqlText(adminId)}::uuid, ${sqlText(guestId)}::uuid
);
`;

try {
  await runOk(setupSql, "guest concurrency fixture setup");
  const invitationOutput = await runOk(
    authenticatedSql(
      ownerId,
      `select public.create_pachanga_match_invitation_v1(
        ${sqlText(groupId)}::uuid, ${sqlText(matchId)}, ${sqlText(marketProfileId)}::uuid,
        ${sqlText(inviteOperationId)}::uuid, 0,
        ${sqlJson({ sessionId: "admin-device", surface: "concurrency-test" })}
      )`,
    ),
    "create guest invitation",
  );
  invitationId = lastJson(invitationOutput, "create guest invitation").invitation.id;

  const responseSql = (status, operationId, sessionId) => authenticatedSql(
    guestId,
    `select public.respond_pachanga_match_invitation_v1(
      ${sqlText(invitationId)}::uuid, ${sqlText(status)}, ${sqlText(operationId)}::uuid,
      1, 0, ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );
  const invitationResults = await Promise.all([
    runSql(responseSql("accepted", acceptOperationId, "guest-device-a"), "accept invitation"),
    runSql(responseSql("rejected", rejectOperationId, "guest-device-b"), "reject invitation"),
  ]);
  const invitationWinners = invitationResults.filter((result) => result.code === 0);
  const invitationLosers = invitationResults.filter((result) => result.code !== 0);
  assert.equal(invitationWinners.length, 1, `Exactly one invitation response must win: ${JSON.stringify(invitationResults)}`);
  assert.equal(invitationLosers.length, 1, `Exactly one invitation response must lose: ${JSON.stringify(invitationResults)}`);
  assert.match(invitationLosers[0].stderr, /revision is newer|already decided|ocupada|lock/i);

  const invitationWinner = lastJson(invitationWinners[0].stdout, "winning invitation response");
  assert.equal(invitationWinner.invitation.revision, 2);
  assert.ok(["accepted", "rejected"].includes(invitationWinner.invitation.status));

  const invitationEvidence = lastJson(await runOk(
    `select jsonb_build_object(
      'status', (select status from public.pachanga_match_invitations where id = ${sqlText(invitationId)}::uuid),
      'accessCount', (select count(*) from public.pachanga_match_guest_access
        where source_kind = 'invitation' and source_id = ${sqlText(invitationId)}::uuid),
      'respondReceipts', (select count(*) from public.pachanga_operation_receipts
        where group_id = ${sqlText(groupId)}::uuid
          and operation_id in (${sqlText(acceptOperationId)}::uuid, ${sqlText(rejectOperationId)}::uuid))
    )`,
    "invitation convergence evidence",
  ), "invitation convergence evidence");
  assert.equal(invitationEvidence.respondReceipts, 1);
  assert.equal(invitationEvidence.accessCount, invitationEvidence.status === "accepted" ? 1 : 0);

  if (invitationEvidence.status === "rejected") {
    const secondInviteOperationId = randomUUID();
    const secondAcceptOperationId = randomUUID();
    const secondInviteOutput = await runOk(
      authenticatedSql(
        ownerId,
        `select public.create_pachanga_match_invitation_v1(
          ${sqlText(groupId)}::uuid, ${sqlText(matchId)}, ${sqlText(marketProfileId)}::uuid,
          ${sqlText(secondInviteOperationId)}::uuid, 0,
          ${sqlJson({ sessionId: "admin-device", surface: "concurrency-test" })}
        )`,
      ),
      "create replacement invitation",
    );
    invitationId = lastJson(secondInviteOutput, "create replacement invitation").invitation.id;
    const acceptedOutput = await runOk(
      authenticatedSql(
        guestId,
        `select public.respond_pachanga_match_invitation_v1(
          ${sqlText(invitationId)}::uuid, 'accepted', ${sqlText(secondAcceptOperationId)}::uuid,
          1, 0, ${sqlJson({ sessionId: "guest-device", surface: "concurrency-test" })}
        )`,
      ),
      "accept replacement invitation",
    );
    accessId = lastJson(acceptedOutput, "accept replacement invitation").accessId;
  } else {
    accessId = invitationWinner.accessId;
  }
  assert.ok(accessId, "The accepted invitation must return exact-match access");

  const snapshotOutput = await runOk(
    authenticatedSql(
      guestId,
      `select public.get_pachanga_guest_match_snapshot_v1(${sqlText(accessId)}::uuid)`,
    ),
    "get accepted guest snapshot",
  );
  const snapshot = lastJson(snapshotOutput, "get accepted guest snapshot");
  const leaveOperationId = randomUUID();
  const leaveOutput = await runOk(
    authenticatedSql(
      guestId,
      `select public.leave_pachanga_guest_match_v1(
        ${sqlText(accessId)}::uuid, ${sqlText(leaveOperationId)}::uuid,
        ${Number(snapshot.snapshotRevision)},
        ${sqlJson({ sessionId: "guest-device", surface: "concurrency-test" })}
      )`,
    ),
    "leave accepted guest match",
  );
  const left = lastJson(leaveOutput, "leave accepted guest match");
  reviewId = left.withdrawalReviewId;
  assert.ok(reviewId, "Leaving must create a conduct review");

  const reviewSql = (status, operationId, sessionId) => authenticatedSql(
    status === "confirmed" ? ownerId : adminId,
    `select public.review_pachanga_guest_withdrawal_v1(
      ${sqlText(reviewId)}::uuid, ${sqlText(status)}, ${sqlText(operationId)}::uuid,
      1, ${Number(left.confirmedRevision)},
      ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );
  const reviewResults = await Promise.all([
    runSql(reviewSql("confirmed", confirmOperationId, "admin-device-a"), "confirm withdrawal"),
    runSql(reviewSql("dismissed", dismissOperationId, "admin-device-b"), "dismiss withdrawal"),
  ]);
  const reviewWinners = reviewResults.filter((result) => result.code === 0);
  const reviewLosers = reviewResults.filter((result) => result.code !== 0);
  assert.equal(reviewWinners.length, 1, `Exactly one conduct review must win: ${JSON.stringify(reviewResults)}`);
  assert.equal(reviewLosers.length, 1, `Exactly one conduct review must lose: ${JSON.stringify(reviewResults)}`);
  assert.match(reviewLosers[0].stderr, /revision is newer|already decided|ocupada|lock/i);

  const canonicalReview = lastJson(await runOk(
    `select jsonb_build_object(
      'status', status,
      'revision', revision,
      'events', (select count(*) from public.pachanga_group_events
        where group_id = ${sqlText(groupId)}::uuid
          and match_id = ${sqlText(matchId)}
          and event_type in ('match_guest_withdrawal_confirmed', 'match_guest_withdrawal_dismissed')),
      'receipts', (select count(*) from public.pachanga_operation_receipts
        where group_id = ${sqlText(groupId)}::uuid
          and operation_id in (${sqlText(confirmOperationId)}::uuid, ${sqlText(dismissOperationId)}::uuid))
    ) from public.pachanga_guest_withdrawal_reviews where id = ${sqlText(reviewId)}::uuid`,
    "conduct review convergence evidence",
  ), "conduct review convergence evidence");
  assert.ok(["confirmed", "dismissed"].includes(canonicalReview.status));
  assert.equal(canonicalReview.revision, 2);
  assert.equal(canonicalReview.events, 1);
  assert.equal(canonicalReview.receipts, 1);

  const guestReadback = lastJson(await runOk(
    authenticatedSql(
      guestId,
      `select public.get_pachanga_guest_match_snapshot_v1(${sqlText(accessId)}::uuid)`,
    ),
    "revoked guest convergence readback",
  ), "revoked guest convergence readback");
  assert.equal(guestReadback.access.status, "revoked");
  assert.equal(guestReadback.snapshot, undefined);

  const publicRequestOperationId = randomUUID();
  const publicAcceptOperationId = randomUUID();
  const publicRejectOperationId = randomUUID();
  const requestRevisions = lastJson(await runOk(
    `select jsonb_build_object(
      'groupRevision', (select payload_revision from public.pachanga_groups where id = ${sqlText(groupId)}::uuid),
      'matchRevision', (select source_payload_revision from public.pachanga_open_matches where id = ${sqlText(openMatchId)}::uuid)
    )`,
    "public request revisions",
  ), "public request revisions");
  const publicRequestOutput = await runOk(
    authenticatedSql(
      guestId,
      `select public.request_pachanga_open_match_authoritative_v2(
        ${sqlText(openMatchId)}::uuid, ${sqlText(publicRequestOperationId)}::uuid,
        ${Number(requestRevisions.matchRevision)},
        ${sqlJson({ sessionId: "guest-public-device", surface: "concurrency-test" })}
      )`,
    ),
    "create public match request",
  );
  const publicRequestId = lastJson(publicRequestOutput, "create public match request").request.id;
  const publicReviewSql = (status, operationId, actorId, sessionId) => authenticatedSql(
    actorId,
    `select public.review_pachanga_open_match_request_authoritative_v2(
      ${sqlText(groupId)}::uuid, ${sqlText(publicRequestId)}::uuid, ${sqlText(status)},
      ${sqlText(operationId)}::uuid, ${Number(requestRevisions.groupRevision)},
      ${sqlJson({ sessionId, surface: "concurrency-test" })}
    )`,
  );
  const publicReviewResults = await Promise.all([
    runSql(publicReviewSql("accepted", publicAcceptOperationId, ownerId, "public-admin-a"), "accept public request"),
    runSql(publicReviewSql("rejected", publicRejectOperationId, adminId, "public-admin-b"), "reject public request"),
  ]);
  const publicReviewWinners = publicReviewResults.filter((result) => result.code === 0);
  const publicReviewLosers = publicReviewResults.filter((result) => result.code !== 0);
  assert.equal(publicReviewWinners.length, 1, `Exactly one public-request review must win: ${JSON.stringify(publicReviewResults)}`);
  assert.equal(publicReviewLosers.length, 1, `Exactly one public-request review must lose: ${JSON.stringify(publicReviewResults)}`);
  assert.match(publicReviewLosers[0].stderr, /already decided|ya estaba decidida|newer|ocupada|lock/i);

  const publicReviewEvidence = lastJson(await runOk(
    `select jsonb_build_object(
      'status', status,
      'accessCount', (select count(*) from public.pachanga_match_guest_access
        where source_kind = 'open_request' and source_id = ${sqlText(publicRequestId)}::uuid),
      'reviewReceipts', (select count(*) from public.pachanga_operation_receipts
        where group_id = ${sqlText(groupId)}::uuid
          and operation_id in (${sqlText(publicAcceptOperationId)}::uuid, ${sqlText(publicRejectOperationId)}::uuid))
    ) from public.pachanga_open_match_requests where id = ${sqlText(publicRequestId)}::uuid`,
    "public request convergence evidence",
  ), "public request convergence evidence");
  assert.ok(["accepted", "rejected"].includes(publicReviewEvidence.status));
  assert.equal(publicReviewEvidence.accessCount, publicReviewEvidence.status === "accepted" ? 1 : 0);
  assert.equal(publicReviewEvidence.reviewReceipts, 1);
} finally {
  await runOk(cleanupSql, "guest concurrency fixture cleanup");
}

console.error("[match-guest concurrency] passed");
