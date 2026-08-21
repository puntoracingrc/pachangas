import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.CLUB_FOUNDATION_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const timeoutMs = Number(process.env.CLUB_FOUNDATION_SQL_TIMEOUT_MS || 45_000);

if (!databaseUrl) throw new Error("CLUB_FOUNDATION_DATABASE_URL is required");

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
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

function authenticated(userId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: userId }))}, true);
${statement};
commit;
`;
}

function lastJson(result) {
  const line = result.stdout.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${result.label} returned no JSON`);
  return JSON.parse(line);
}

async function sameCanonical(label, sql) {
  const results = await Promise.all([
    runSql(sql, `${label}:device-a`),
    runSql(sql, `${label}:device-b`),
  ]);
  for (const result of results) assert.equal(result.code, 0, `${result.label} failed:\n${result.stderr}`);
  const responses = results.map(lastJson);
  assert.deepEqual(responses[0], responses[1], `${label} must converge to one canonical receipt`);
  return responses[0];
}

async function oneWinner(label, statements) {
  const results = await Promise.all(statements.map(({ client, sql }) => runSql(sql, `${label}:${client}`)));
  const winners = results.filter(({ code }) => code === 0);
  const losers = results.filter(({ code }) => code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must reject one writer: ${JSON.stringify(results)}`);
  assert.match(
    losers[0].stderr,
    /STALE_REVISION|CLUB_PLATFORM_CONFLICT|CLUB_CONFLICT|CLUB_INVITATION_NOT_PENDING/,
    `${label} must reject the losing write explicitly`,
  );
  return lastJson(winners[0]);
}

const platformOwnerId = randomUUID();
const ownerAId = randomUUID();
const ownerBId = randomUUID();
const managerId = randomUUID();
const viewerId = randomUUID();
const teamOwnerId = randomUUID();
const clubId = randomUUID();
const groupId = randomUUID();
const clubFlagsAggregateId = "00000000-0000-0000-0000-00000000c101";
const competitionFlagsAggregateId = "00000000-0000-0000-0000-00000000c001";
const operationIds = [];
let clubFlags;
let competitionFlags;

function operation() {
  const value = randomUUID();
  operationIds.push(value);
  return value;
}

function clubCommand(actorId, operationId, aggregateId, expectedRevision, action, payload) {
  return authenticated(actorId, `select public.command_pachanga_club_foundation_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"1.0.0+club-concurrency","surface":"club_concurrency"}'::jsonb
  )`);
}

try {
  clubFlags = (await runOk(`select club_foundation_enabled::text || '|' || club_self_service_creation_enabled::text || '|' || club_team_relationships_enabled::text || '|' || club_public_profiles_enabled::text || '|' || club_competition_organizer_enabled::text || '|' || revision::text from private.pachanga_club_foundation_settings where singleton`, "read Club flag baseline")).split("|");
  competitionFlags = (await runOk(`select foundation_enabled::text || '|' || creation_enabled::text || '|' || context_binding_enabled::text || '|' || revision::text from private.pachanga_competition_foundation_settings where singleton`, "read Competition flag baseline")).split("|");

  await runOk(`
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    grant execute on function auth.jwt() to authenticated;
    insert into auth.users(id, email, email_confirmed_at) values
      (${quote(platformOwnerId)}::uuid, ${quote(`club-platform-${platformOwnerId}@example.test`)}, clock_timestamp()),
      (${quote(ownerAId)}::uuid, ${quote(`club-owner-a-${ownerAId}@example.test`)}, clock_timestamp()),
      (${quote(ownerBId)}::uuid, ${quote(`club-owner-b-${ownerBId}@example.test`)}, clock_timestamp()),
      (${quote(managerId)}::uuid, ${quote(`club-manager-${managerId}@example.test`)}, clock_timestamp()),
      (${quote(viewerId)}::uuid, ${quote(`club-viewer-${viewerId}@example.test`)}, clock_timestamp()),
      (${quote(teamOwnerId)}::uuid, ${quote(`club-team-owner-${teamOwnerId}@example.test`)}, clock_timestamp());
    insert into private.pachanga_platform_admin_roles(user_id, role, active)
    values (${quote(platformOwnerId)}::uuid, 'platform_owner', true);
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
    values (${quote(groupId)}::uuid, ${quote(teamOwnerId)}::uuid, 'Club Concurrency Team', ${quote(`CL${groupId.replaceAll("-", "").slice(0, 6)}`)}, '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');
    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    values (${quote(groupId)}::uuid, ${quote(teamOwnerId)}::uuid, 'owner', 'Club concurrency team owner');
  `, "Club concurrency fixture");

  await runOk(authenticated(platformOwnerId, `select public.command_pachanga_club_platform_v1(
    ${quote(operation())}::uuid, ${quote(clubFlagsAggregateId)}::uuid, ${Number(clubFlags[5])},
    'club_flags.set', '{"foundationEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"publicProfilesEnabled":true,"competitionOrganizerEnabled":true,"reason":"Club concurrency fixture"}',
    '{"surface":"club_concurrency"}'
  )`), "enable Club fixture");
  await runOk(authenticated(platformOwnerId, `select public.command_pachanga_competition_platform_v1(
    ${quote(operation())}::uuid, ${quote(competitionFlagsAggregateId)}::uuid, ${Number(competitionFlags[3])},
    'foundation_flags.set', '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":false,"reason":"Club concurrency fixture"}',
    '{"surface":"club_concurrency"}'
  )`), "enable Competition fixture");

  const createOperation = operation();
  const create = await sameCanonical("same Club create operation", clubCommand(
    ownerAId,
    createOperation,
    clubId,
    0,
    "club.create",
    {
      clubType: "FOOTBALL_CLUB",
      countryCode: "ES",
      name: "Club Concurrency",
      reason: "concurrent create",
      slug: `club-concurrency-${clubId.slice(0, 8)}`,
      visibility: "private",
    },
  ));
  assert.equal(create.confirmedRevision, 1);
  assert.equal(await runOk(`select count(*) from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "Club create count"), "1");
  assert.equal(await runOk(`select count(*) from private.pachanga_club_operation_receipts where operation_id = ${quote(createOperation)}::uuid`, "Club receipt count"), "1");

  async function inviteAndAccept(targetUserId, role) {
    const revision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, `read revision for ${role}`));
    const invite = lastJson({
      label: `invite ${role}`,
      stdout: await runOk(clubCommand(ownerAId, operation(), clubId, revision, "membership.invite", {
        reason: `invite ${role}`,
        role,
        targetKind: "registered_user",
        targetUserId,
      }), `invite ${role}`),
    });
    await runOk(clubCommand(targetUserId, operation(), invite.invitationId, 1, "membership.accept", {
      reason: `accept ${role}`,
      token: invite.oneTimeToken,
    }), `accept ${role}`);
    return invite;
  }

  await inviteAndAccept(ownerBId, "club_owner");
  await inviteAndAccept(managerId, "club_competition_manager");

  const viewerRevision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "read viewer invite revision"));
  const viewerInvite = lastJson({
    label: "invite viewer",
    stdout: await runOk(clubCommand(ownerAId, operation(), clubId, viewerRevision, "membership.invite", {
      reason: "viewer acceptance race",
      role: "club_viewer",
      targetKind: "registered_user",
      targetUserId: viewerId,
    }), "invite viewer"),
  });
  await oneWinner("two invitation acceptances", [
    { client: "device-a", sql: clubCommand(viewerId, operation(), viewerInvite.invitationId, 1, "membership.accept", { reason: "device a", token: viewerInvite.oneTimeToken }) },
    { client: "device-b", sql: clubCommand(viewerId, operation(), viewerInvite.invitationId, 1, "membership.accept", { reason: "device b", token: viewerInvite.oneTimeToken }) },
  ]);
  assert.equal(await runOk(`select count(*) from public.pachanga_club_memberships where club_id = ${quote(clubId)}::uuid and user_id = ${quote(viewerId)}::uuid and status = 'active'`, "viewer membership count"), "1");

  const ownerRevision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "owner transfer revision"));
  await oneWinner("two primary owner transfers", [
    { client: "device-a", sql: clubCommand(ownerAId, operation(), clubId, ownerRevision, "club.primary_owner.transfer", { reason: "device a", retainPreviousOwner: true, targetUserId: ownerBId }) },
    { client: "device-b", sql: clubCommand(ownerAId, operation(), clubId, ownerRevision, "club.primary_owner.transfer", { reason: "device b", retainPreviousOwner: true, targetUserId: ownerBId }) },
  ]);
  assert.equal(await runOk(`select primary_owner_id from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "canonical primary owner"), ownerBId);

  const activateRevision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "activate revision"));
  await runOk(authenticated(platformOwnerId, `select public.command_pachanga_club_platform_v1(
    ${quote(operation())}::uuid, ${quote(clubId)}::uuid, ${activateRevision},
    'club.status.set', '{"status":"active","reason":"activate concurrency Club"}', '{"surface":"club_concurrency"}'
  )`), "activate Club");

  const grantRevision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "grant race revision"));
  await oneWinner("two entitlement grants", [
    {
      client: "device-a",
      sql: authenticated(platformOwnerId, `select public.command_pachanga_club_platform_v1(
        ${quote(operation())}::uuid, ${quote(clubId)}::uuid, ${grantRevision}, 'club.entitlement.grant',
        '{"capability":"competition_create","source":"platform_grant","validFrom":"2026-01-01T00:00:00Z","reason":"device a"}', '{"surface":"club_concurrency"}'
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(platformOwnerId, `select public.command_pachanga_club_platform_v1(
        ${quote(operation())}::uuid, ${quote(clubId)}::uuid, ${grantRevision}, 'club.entitlement.grant',
        '{"capability":"competition_create","source":"platform_grant","validFrom":"2026-01-01T00:00:00Z","reason":"device b"}', '{"surface":"club_concurrency"}'
      )`),
    },
  ]);
  assert.equal(await runOk(`select count(*) from public.pachanga_competition_entitlement_grants where organizer_kind = 'CLUB' and organizer_club_id = ${quote(clubId)}::uuid and status = 'active'`, "active Club grant count"), "1");

  const relationshipRevision = Number(await runOk(`select revision from public.pachanga_clubs where id = ${quote(clubId)}::uuid`, "relationship invite revision"));
  await runOk(clubCommand(ownerBId, operation(), clubId, relationshipRevision, "team_relationship.invite", {
    groupId,
    reason: "relationship response race",
    relationshipType: "AFFILIATED",
  }), "invite Team");
  const relationshipId = await runOk(`select id from public.pachanga_club_team_relationships where club_id = ${quote(clubId)}::uuid and group_id = ${quote(groupId)}::uuid and status = 'invited'`, "relationship id");
  await oneWinner("two relationship responses", [
    { client: "device-a", sql: clubCommand(teamOwnerId, operation(), relationshipId, 1, "team_relationship.accept", { reason: "device a" }) },
    { client: "device-b", sql: clubCommand(teamOwnerId, operation(), relationshipId, 1, "team_relationship.reject", { reason: "device b" }) },
  ]);
  assert.equal(await runOk(`select count(*) from public.pachanga_club_team_relationships where id = ${quote(relationshipId)}::uuid and status in ('active','rejected')`, "relationship terminal count"), "1");

  const organizerRevision = Number(await runOk(`select revision from public.pachanga_competition_organizer_states where organizer_kind = 'CLUB' and organizer_club_id = ${quote(clubId)}::uuid`, "organizer revision"));
  const slug = `club-race-${clubId.slice(0, 8)}`;
  await oneWinner("two Club competition creations", [
    {
      client: "device-a",
      sql: authenticated(managerId, `select public.command_pachanga_competition_foundation_v2(
        ${quote(operation())}::uuid, 'CLUB', ${quote(clubId)}::uuid, ${organizerRevision}, 'competition.create',
        ${quote(JSON.stringify({ competitionType: "LEAGUE", name: "Club Race A", reason: "device a", slug, visibility: "private" }))}::jsonb,
        '{"surface":"club_concurrency"}'::jsonb
      )`),
    },
    {
      client: "device-b",
      sql: authenticated(managerId, `select public.command_pachanga_competition_foundation_v2(
        ${quote(operation())}::uuid, 'CLUB', ${quote(clubId)}::uuid, ${organizerRevision}, 'competition.create',
        ${quote(JSON.stringify({ competitionType: "LEAGUE", name: "Club Race B", reason: "device b", slug, visibility: "private" }))}::jsonb,
        '{"surface":"club_concurrency"}'::jsonb
      )`),
    },
  ]);
  assert.equal(await runOk(`select count(*) from public.pachanga_competitions where organizer_kind = 'CLUB' and organizer_club_id = ${quote(clubId)}::uuid and slug = ${quote(slug)}`, "Club competition slug count"), "1");

  console.log(JSON.stringify({
    clubCreateReplay: "canonical",
    competitionSlugRace: "one_winner_one_stale",
    entitlementRace: "one_winner_one_stale",
    invitationRace: "one_winner_one_stale",
    ownerTransferRace: "one_winner_one_stale",
    relationshipRace: "one_winner_one_stale",
  }));
} finally {
  const restoreClubFlags = clubFlags ? `
    update private.pachanga_club_foundation_settings set
      club_foundation_enabled = ${clubFlags[0]},
      club_self_service_creation_enabled = ${clubFlags[1]},
      club_team_relationships_enabled = ${clubFlags[2]},
      club_public_profiles_enabled = ${clubFlags[3]},
      club_competition_organizer_enabled = ${clubFlags[4]},
      revision = ${clubFlags[5]}
    where singleton;
  ` : "";
  const restoreCompetitionFlags = competitionFlags ? `
    update private.pachanga_competition_foundation_settings set
      foundation_enabled = ${competitionFlags[0]},
      creation_enabled = ${competitionFlags[1]},
      context_binding_enabled = ${competitionFlags[2]},
      revision = ${competitionFlags[3]}
    where singleton;
  ` : "";
  await runOk(`
    begin;
    alter table private.pachanga_club_events disable trigger guard_pachanga_club_events_v1;
    alter table private.pachanga_club_operation_receipts disable trigger guard_pachanga_club_receipts_v1;
    alter table private.pachanga_competition_events disable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_competition_operation_receipts disable trigger guard_pachanga_competition_receipts_v1;
    alter table public.pachanga_clubs disable trigger pachanga_club_guard_owner_from_club_v1;
    alter table public.pachanga_club_memberships disable trigger pachanga_club_guard_owner_from_membership_v1;
    ${restoreClubFlags}
    ${restoreCompetitionFlags}
    delete from public.pachanga_user_notifications where recipient_user_id in (${[platformOwnerId, ownerAId, ownerBId, managerId, viewerId, teamOwnerId].map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_competition_invalidations where organizer_club_id = ${quote(clubId)}::uuid;
    delete from private.pachanga_competition_events where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]);
    delete from private.pachanga_competition_operation_receipts where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]);
    delete from public.pachanga_competition_staff_assignments where competition_id in (select id from public.pachanga_competitions where organizer_club_id = ${quote(clubId)}::uuid);
    delete from public.pachanga_competition_rule_sets where competition_id in (select id from public.pachanga_competitions where organizer_club_id = ${quote(clubId)}::uuid);
    delete from public.pachanga_competition_editions where competition_id in (select id from public.pachanga_competitions where organizer_club_id = ${quote(clubId)}::uuid);
    delete from public.pachanga_competitions where organizer_club_id = ${quote(clubId)}::uuid;
    delete from public.pachanga_competition_entitlement_grants where organizer_club_id = ${quote(clubId)}::uuid;
    delete from public.pachanga_competition_organizer_states where organizer_club_id = ${quote(clubId)}::uuid;
    delete from public.pachanga_club_invalidations where club_id = ${quote(clubId)}::uuid;
    delete from private.pachanga_club_invitation_secrets where invitation_id in (select id from public.pachanga_club_invitations where club_id = ${quote(clubId)}::uuid);
    delete from public.pachanga_club_invitations where club_id = ${quote(clubId)}::uuid;
    delete from public.pachanga_club_team_relationships where club_id = ${quote(clubId)}::uuid;
    delete from public.pachanga_club_memberships where club_id = ${quote(clubId)}::uuid;
    delete from private.pachanga_club_events where club_id = ${quote(clubId)}::uuid;
    delete from private.pachanga_club_operation_receipts where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]);
    delete from public.pachanga_clubs where id = ${quote(clubId)}::uuid;
    delete from public.pachanga_group_members where group_id = ${quote(groupId)}::uuid;
    delete from public.pachanga_groups where id = ${quote(groupId)}::uuid;
    delete from private.pachanga_platform_admin_roles where user_id = ${quote(platformOwnerId)}::uuid;
    delete from auth.users where id in (${[platformOwnerId, ownerAId, ownerBId, managerId, viewerId, teamOwnerId].map((id) => `${quote(id)}::uuid`).join(",")});
    alter table public.pachanga_club_memberships enable trigger pachanga_club_guard_owner_from_membership_v1;
    alter table public.pachanga_clubs enable trigger pachanga_club_guard_owner_from_club_v1;
    alter table private.pachanga_competition_operation_receipts enable trigger guard_pachanga_competition_receipts_v1;
    alter table private.pachanga_competition_events enable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_club_operation_receipts enable trigger guard_pachanga_club_receipts_v1;
    alter table private.pachanga_club_events enable trigger guard_pachanga_club_events_v1;
    commit;
  `, "Club concurrency cleanup");
}
