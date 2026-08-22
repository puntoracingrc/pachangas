import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.REFEREE_PLATFORM_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const timeoutMs = Number(process.env.REFEREE_PLATFORM_SQL_TIMEOUT_MS || 45_000);

if (!databaseUrl) throw new Error("REFEREE_PLATFORM_DATABASE_URL is required");

function quote(value) { return `'${String(value).replaceAll("'", "''")}'`; }

function runSql(sql, label) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timeout = setTimeout(() => { timedOut = true; child.kill("SIGKILL"); }, timeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => {
      clearTimeout(timeout);
      resolve({ code: timedOut ? 124 : code, label, stderr: stderr.trim(), stdout: stdout.trim() });
    });
    child.stdin.end(sql);
  });
}

async function runOk(sql, label) {
  const result = await runSql(sql, label);
  assert.equal(result.code, 0, `${label} failed:\n${result.stderr}`);
  return result.stdout;
}

function authenticated(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: userId }))}, true);
${statement};
commit;
`;
}

function command(actorId, operationId, aggregateId, expectedRevision, action, payload) {
  return authenticated(actorId, `select public.command_pachanga_referee_platform_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${expectedRevision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"3.0.0+referee-concurrency","serviceWorkerVersion":"sw-r3","installedMode":"standalone","surface":"referee_concurrency"}'::jsonb
  )`);
}

function reconcile(actorId, operationId, assignmentId, expectedRevision) {
  return authenticated(actorId, `select public.reconcile_pachanga_referee_assignment_v1(
    ${quote(operationId)}::uuid, ${quote(assignmentId)}::uuid, ${expectedRevision},
    '{"clientVersion":"3.0.0+referee-concurrency","surface":"referee_concurrency"}'::jsonb
  )`);
}

function lastJson(result) {
  const line = result.stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${result.label} returned no JSON`);
  return JSON.parse(line);
}

async function sameCanonical(label, sql) {
  const results = await Promise.all([runSql(sql, `${label}:a`), runSql(sql, `${label}:b`)]);
  for (const result of results) assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  const responses = results.map(lastJson);
  assert.deepEqual(responses[0], responses[1], `${label} did not converge to one receipt`);
  return responses[0];
}

async function oneWinner(label, statements, failure = /STALE_REVISION|ALREADY_EXISTS|SLUG_TAKEN|NOT_PENDING|TIME_CONFLICT|SLOT_TAKEN|NOT_PROPOSED|NOT_ACCEPTED|NOT_CONFIRMED|duplicate key/i) {
  const results = await Promise.all(statements.map(({ client, sql }) => runSql(sql, `${label}:${client}`)));
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} expected one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} expected one loser: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, failure, `${label} did not reject explicitly`);
  return { response: lastJson(winners[0]), winner: winners[0] };
}

const ids = {
  platform: randomUUID(), owner: randomUUID(), clubOwner: randomUUID(), idem: randomUUID(), sameUser: randomUUID(),
  slugA: randomUUID(), slugB: randomUUID(), refA: randomUUID(), refB: randomUUID(), refC: randomUUID(),
  group: randomUUID(), club: randomUUID(),
  idemProfile: randomUUID(), sameProfileA: randomUUID(), sameProfileB: randomUUID(), slugProfileA: randomUUID(), slugProfileB: randomUUID(),
  refProfileA: randomUUID(), refProfileB: randomUUID(), refProfileC: randomUUID(),
  relationship: randomUUID(), responseAssignment: randomUUID(), slotAssignmentA: randomUUID(), slotAssignmentB: randomUUID(),
  overlapAssignmentA: randomUUID(), overlapAssignmentB: randomUUID(), reconcileAssignment: randomUUID(),
};
const canonicalIds = Array.from({ length: 5 }, () => randomUUID());
const users = [ids.platform, ids.owner, ids.clubOwner, ids.idem, ids.sameUser, ids.slugA, ids.slugB, ids.refA, ids.refB, ids.refC];
let flagBaseline = null;

const matches = [
  { id: "r3-concurrency-1", date: "2026-09-15T18:00:00Z" },
  { id: "r3-concurrency-2", date: "2026-09-16T18:00:00Z" },
  { id: "r3-concurrency-3", date: "2026-09-17T18:00:00Z" },
  { id: "r3-concurrency-4", date: "2026-09-17T19:00:00Z" },
  { id: "r3-concurrency-5", date: "2026-09-18T18:00:00Z" },
];

function profilePayload(slug) {
  return { availabilityStatus: "AVAILABLE", bio: "Perfil arbitral para una prueba real de concurrencia.", experienceSummary: "Experiencia local declarada.", reason: "concurrency profile create", slug };
}

function assignmentValues(id, profileId, matchIndex, status = "proposed") {
  const match = matches[matchIndex];
  return `(
    ${quote(id)}::uuid, ${quote(profileId)}::uuid, ${quote(canonicalIds[matchIndex])}::uuid,
    'MAIN_REFEREE', 'TEAM', ${quote(ids.group)}::uuid, 'group_match', ${quote(ids.group)}::uuid,
    ${quote(match.id)}, ${quote(status)}, ${quote(match.date)}::timestamptz,
    ${quote(new Date(Date.parse(match.date) + 2 * 60 * 60 * 1000).toISOString())}::timestamptz,
    'Europe/Madrid', 1, ${quote(ids.owner)}::uuid, 'team_owner', 'Concurrency fixture',
    clock_timestamp() + interval '1 day',
    ${status === "confirmed" ? "clock_timestamp()" : "null"},
    ${status === "confirmed" ? "clock_timestamp()" : "null"}
  )`;
}

try {
  flagBaseline = (await runOk(`select referee_foundation_enabled::text || '|' || referee_self_service_enabled::text || '|' || referee_public_profiles_enabled::text || '|' || referee_marketplace_enabled::text || '|' || referee_club_relationships_enabled::text || '|' || referee_assignments_enabled::text || '|' || revision::text from private.pachanga_referee_foundation_settings where singleton`, "read R3 flags")).split("|");

  const groupPayload = JSON.stringify({ matches: matches.map((match) => ({ ...match, kind: "futbol7" })), players: [], siteSettings: { timezone: "Europe/Madrid" }, venues: [] });
  await runOk(`
    begin;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    grant execute on function auth.jwt() to authenticated;
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    select user_id, 'r3-concurrency-' || row_number() over () || '-' || left(user_id::text, 8) || '@example.test', clock_timestamp(), jsonb_build_object('full_name', 'R3 Concurrency ' || row_number() over ())
    from unnest(array[${users.map((id) => `${quote(id)}::uuid`).join(",")}]) user_id;
    insert into private.pachanga_platform_admin_roles(user_id, role, active) values (${quote(ids.platform)}::uuid, 'platform_owner', true);
    update private.pachanga_referee_foundation_settings set
      referee_foundation_enabled = true, referee_self_service_enabled = true,
      referee_public_profiles_enabled = true, referee_marketplace_enabled = true,
      referee_club_relationships_enabled = true, referee_assignments_enabled = true
    where singleton;
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    values (${quote(ids.group)}::uuid, ${quote(ids.owner)}::uuid, 'R3 Concurrency Team', ${quote(`R3${ids.group.replaceAll("-", "").slice(0, 7)}`)}, ${quote(groupPayload)}::jsonb, 1);
    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    values (${quote(ids.group)}::uuid, ${quote(ids.owner)}::uuid, 'owner', 'R3 owner');
    insert into public.pachanga_match_read_model(group_id, match_id, match_state, match_version, configured, lineup_closed, finalized, target_players, reserve_limit, source_payload_revision)
    select ${quote(ids.group)}::uuid, source_id, 'published', 1, true, false, false, 14, 2, 1
    from unnest(array[${matches.map((match) => quote(match.id)).join(",")}]) source_id;
    insert into public.pachanga_canonical_matches(id, created_by)
    select canonical_id, ${quote(ids.platform)}::uuid from unnest(array[${canonicalIds.map((id) => `${quote(id)}::uuid`).join(",")}]) canonical_id;
    insert into public.pachanga_canonical_match_bindings(canonical_match_id, source_kind, source_group_id, source_id, relation_kind, created_by)
    values ${matches.map((match, index) => `(${quote(canonicalIds[index])}::uuid, 'group_match', ${quote(ids.group)}::uuid, ${quote(match.id)}, 'manual_verified', ${quote(ids.platform)}::uuid)`).join(",")};
    alter table public.pachanga_clubs disable trigger pachanga_club_guard_owner_from_club_v1;
    insert into public.pachanga_clubs(id, slug, name, club_type, primary_owner_id, operational_status, visibility, created_by)
    values (${quote(ids.club)}::uuid, ${quote(`r3-concurrency-${ids.club.slice(0, 8)}`)}, 'R3 Concurrency Club', 'FOOTBALL_CLUB', ${quote(ids.clubOwner)}::uuid, 'active', 'private', ${quote(ids.clubOwner)}::uuid);
    insert into public.pachanga_club_memberships(id, club_id, user_id, role, status, accepted_at)
    values (gen_random_uuid(), ${quote(ids.club)}::uuid, ${quote(ids.clubOwner)}::uuid, 'club_owner', 'active', clock_timestamp());
    alter table public.pachanga_clubs enable trigger pachanga_club_guard_owner_from_club_v1;
    insert into public.pachanga_referee_profiles(id, user_id, slug, public_display_name_snapshot, bio, operational_status, visibility, availability_status, available_for_assignments)
    values
      (${quote(ids.refProfileA)}::uuid, ${quote(ids.refA)}::uuid, ${quote(`ref-a-${ids.refA.slice(0, 8)}`)}, 'Referee A', 'Active referee A', 'active', 'public', 'AVAILABLE', true),
      (${quote(ids.refProfileB)}::uuid, ${quote(ids.refB)}::uuid, ${quote(`ref-b-${ids.refB.slice(0, 8)}`)}, 'Referee B', 'Active referee B', 'active', 'public', 'AVAILABLE', true),
      (${quote(ids.refProfileC)}::uuid, ${quote(ids.refC)}::uuid, ${quote(`ref-c-${ids.refC.slice(0, 8)}`)}, 'Referee C', 'Active referee C', 'active', 'public', 'AVAILABLE', true);
    insert into public.pachanga_club_referee_relationships(id, club_id, referee_profile_id, target_kind, target_user_id, relationship_type, initiated_by, status, created_by, expires_at)
    values (${quote(ids.relationship)}::uuid, ${quote(ids.club)}::uuid, ${quote(ids.refProfileA)}::uuid, 'registered_user', ${quote(ids.refA)}::uuid, 'REGULAR', 'CLUB', 'invited', ${quote(ids.clubOwner)}::uuid, clock_timestamp() + interval '1 day');
    insert into private.pachanga_referee_invitation_secrets(relationship_id, token_hash, retention_until)
    values (${quote(ids.relationship)}::uuid, repeat('a', 64), clock_timestamp() + interval '90 days');
    insert into public.pachanga_referee_assignments(
      id, referee_profile_id, canonical_match_id, assignment_role, requester_kind, requester_team_id,
      source_kind, source_group_id, source_id, status, scheduled_start, scheduled_end, timezone,
      schedule_source_revision, proposed_by, authority_used, proposal_message, response_deadline,
      accepted_at, confirmed_at
    ) values
      ${assignmentValues(ids.responseAssignment, ids.refProfileA, 0)},
      ${assignmentValues(ids.slotAssignmentA, ids.refProfileA, 1)},
      ${assignmentValues(ids.slotAssignmentB, ids.refProfileB, 1)},
      ${assignmentValues(ids.overlapAssignmentA, ids.refProfileC, 2)},
      ${assignmentValues(ids.overlapAssignmentB, ids.refProfileC, 3)},
      ${assignmentValues(ids.reconcileAssignment, ids.refProfileA, 4, "confirmed")};
    commit;
  `, "create R3 concurrency fixtures");

  const idemOperation = randomUUID();
  const idemSql = command(ids.idem, idemOperation, ids.idemProfile, 0, "profile.create", profilePayload(`idem-${ids.idem.slice(0, 8)}`));
  await sameCanonical("idempotent profile create", idemSql);
  assert.equal(await runOk(`select count(*) from private.pachanga_referee_operation_receipts where operation_id = ${quote(idemOperation)}::uuid`, "idempotent receipt count"), "1");

  await oneWinner("one profile per user", [
    { client: "a", sql: command(ids.sameUser, randomUUID(), ids.sameProfileA, 0, "profile.create", profilePayload(`same-a-${ids.sameUser.slice(0, 7)}`)) },
    { client: "b", sql: command(ids.sameUser, randomUUID(), ids.sameProfileB, 0, "profile.create", profilePayload(`same-b-${ids.sameUser.slice(0, 7)}`)) },
  ]);

  const sharedSlug = `shared-${randomUUID().slice(0, 8)}`;
  await oneWinner("one owner per slug", [
    { client: "a", sql: command(ids.slugA, randomUUID(), ids.slugProfileA, 0, "profile.create", profilePayload(sharedSlug)) },
    { client: "b", sql: command(ids.slugB, randomUUID(), ids.slugProfileB, 0, "profile.create", profilePayload(sharedSlug)) },
  ]);

  await oneWinner("relationship response race", [
    { client: "accept", sql: command(ids.refA, randomUUID(), ids.relationship, 1, "relationship.accept", { reason: "accept relationship" }) },
    { client: "reject", sql: command(ids.refA, randomUUID(), ids.relationship, 1, "relationship.reject", { reason: "reject relationship" }) },
  ]);

  await oneWinner("assignment response race", [
    { client: "accept", sql: command(ids.refA, randomUUID(), ids.responseAssignment, 1, "assignment.accept", { reason: "accept proposal" }) },
    { client: "decline", sql: command(ids.refA, randomUUID(), ids.responseAssignment, 1, "assignment.decline", { reason: "decline proposal" }) },
  ]);

  await oneWinner("two referees one canonical slot", [
    { client: "ref-a", sql: command(ids.refA, randomUUID(), ids.slotAssignmentA, 1, "assignment.accept", { reason: "accept slot A" }) },
    { client: "ref-b", sql: command(ids.refB, randomUUID(), ids.slotAssignmentB, 1, "assignment.accept", { reason: "accept slot B" }) },
  ]);

  await oneWinner("one referee overlapping assignments", [
    { client: "match-a", sql: command(ids.refC, randomUUID(), ids.overlapAssignmentA, 1, "assignment.accept", { reason: "accept overlap A" }) },
    { client: "match-b", sql: command(ids.refC, randomUUID(), ids.overlapAssignmentB, 1, "assignment.accept", { reason: "accept overlap B" }) },
  ]);

  const acceptedSlot = (await runOk(`select assignments.id::text || '|' || profiles.user_id::text from public.pachanga_referee_assignments assignments join public.pachanga_referee_profiles profiles on profiles.id = assignments.referee_profile_id where assignments.id in (${quote(ids.slotAssignmentA)}::uuid, ${quote(ids.slotAssignmentB)}::uuid) and assignments.status = 'accepted'`, "accepted slot assignment")).split("|");
  assert.equal(acceptedSlot.length, 2, "No accepted slot assignment was found");
  await oneWinner("confirm versus cancel", [
    { client: "owner-confirm", sql: command(ids.owner, randomUUID(), acceptedSlot[0], 2, "assignment.confirm", { reason: "confirm assignment" }) },
    { client: "referee-cancel", sql: command(acceptedSlot[1], randomUUID(), acceptedSlot[0], 2, "assignment.cancel", { reason: "cancel assignment", reasonCode: "race_cancel", reasonText: "Concurrent cancellation" }) },
  ]);

  await runOk(`update public.pachanga_match_read_model set match_state = 'finalized', finalized = true, lineup_closed = true where group_id = ${quote(ids.group)}::uuid and match_id = ${quote(matches[4].id)}`, "conclude reconcile match");
  const reconcileA = randomUUID();
  const reconcileB = randomUUID();
  await oneWinner("two completion reconciliations", [
    { client: "a", sql: reconcile(ids.platform, reconcileA, ids.reconcileAssignment, 1) },
    { client: "b", sql: reconcile(ids.platform, reconcileB, ids.reconcileAssignment, 1) },
  ], /STALE_REVISION|NOT_CONFIRMED/i);
  const winningReconcile = await runOk(`select operation_id from private.pachanga_referee_operation_receipts where operation_id in (${quote(reconcileA)}::uuid, ${quote(reconcileB)}::uuid)`, "winning reconcile operation");
  await runOk(reconcile(ids.platform, winningReconcile, ids.reconcileAssignment, 1), "replay winning reconciliation");
  assert.equal(await runOk(`select count(*) from public.pachanga_referee_assignments where id = ${quote(ids.reconcileAssignment)}::uuid and status = 'completed'`, "completed assignment count"), "1");

  console.log(JSON.stringify({
    assignmentResponse: "one_winner", completionReconcile: "one_winner_and_idempotent_replay",
    confirmCancel: "one_winner", overlappingAssignments: "one_winner", profilePerUser: "one_winner",
    profileReplay: "canonical", relationshipResponse: "one_winner", sameSlug: "one_winner", slotAcceptance: "one_winner",
  }));
} finally {
  const restoreFlags = flagBaseline ? `
    update private.pachanga_referee_foundation_settings set
      referee_foundation_enabled = ${flagBaseline[0]}, referee_self_service_enabled = ${flagBaseline[1]},
      referee_public_profiles_enabled = ${flagBaseline[2]}, referee_marketplace_enabled = ${flagBaseline[3]},
      referee_club_relationships_enabled = ${flagBaseline[4]}, referee_assignments_enabled = ${flagBaseline[5]},
      revision = ${flagBaseline[6]}
    where singleton;
  ` : "";
  await runOk(`
    begin;
    alter table private.pachanga_referee_events disable trigger pachanga_referee_events_immutable_v1;
    alter table private.pachanga_referee_operation_receipts disable trigger pachanga_referee_receipts_immutable_v1;
    alter table public.pachanga_clubs disable trigger pachanga_club_guard_owner_from_club_v1;
    alter table public.pachanga_club_memberships disable trigger pachanga_club_guard_owner_from_membership_v1;
    ${restoreFlags}
    delete from public.pachanga_user_notifications where recipient_user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_referee_invalidations where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")})) or club_id = ${quote(ids.club)}::uuid or target_group_id = ${quote(ids.group)}::uuid;
    delete from private.pachanga_referee_invitation_secrets where relationship_id = ${quote(ids.relationship)}::uuid;
    delete from public.pachanga_club_referee_relationships where id = ${quote(ids.relationship)}::uuid;
    delete from public.pachanga_referee_assignments where requester_team_id = ${quote(ids.group)}::uuid;
    delete from public.pachanga_referee_statistics_snapshots where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}));
    delete from private.pachanga_referee_events where actor_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}) or club_id = ${quote(ids.club)}::uuid;
    delete from private.pachanga_referee_operation_receipts where actor_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_referee_availability_exceptions where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}));
    delete from public.pachanga_referee_availability_windows where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}));
    delete from public.pachanga_referee_service_areas where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}));
    delete from public.pachanga_referee_modalities where referee_profile_id in (select id from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")}));
    delete from public.pachanga_referee_profiles where user_id in (${users.map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_canonical_match_bindings where source_group_id = ${quote(ids.group)}::uuid;
    delete from public.pachanga_canonical_matches where id in (${canonicalIds.map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_match_read_model where group_id = ${quote(ids.group)}::uuid;
    delete from public.pachanga_group_members where group_id = ${quote(ids.group)}::uuid;
    delete from public.pachanga_groups where id = ${quote(ids.group)}::uuid;
    delete from public.pachanga_club_memberships where club_id = ${quote(ids.club)}::uuid;
    delete from public.pachanga_clubs where id = ${quote(ids.club)}::uuid;
    delete from private.pachanga_platform_admin_roles where user_id = ${quote(ids.platform)}::uuid;
    delete from auth.users where id in (${users.map((id) => `${quote(id)}::uuid`).join(",")});
    alter table public.pachanga_club_memberships enable trigger pachanga_club_guard_owner_from_membership_v1;
    alter table public.pachanga_clubs enable trigger pachanga_club_guard_owner_from_club_v1;
    alter table private.pachanga_referee_operation_receipts enable trigger pachanga_referee_receipts_immutable_v1;
    alter table private.pachanga_referee_events enable trigger pachanga_referee_events_immutable_v1;
    commit;
  `, "cleanup R3 concurrency fixtures");
}
