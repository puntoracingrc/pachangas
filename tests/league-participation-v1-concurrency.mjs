import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.LEAGUE_PARTICIPATION_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const timeoutMs = Number(process.env.LEAGUE_PARTICIPATION_SQL_TIMEOUT_MS || 45_000);

if (!databaseUrl) throw new Error("LEAGUE_PARTICIPATION_DATABASE_URL is required");

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

function command(actorId, operationId, aggregateId, expectedRevision, action, payload = {}) {
  return authenticated(actorId, `select public.command_pachanga_league_participation_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"4.0.0+r4a-concurrency","serviceWorkerVersion":"sw-r4a-concurrency","installedMode":"standalone","surface":"r4a_concurrency"}'::jsonb
  )`);
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
  assert.deepEqual(responses[0], responses[1], `${label} did not converge to one canonical receipt`);
  return responses[0];
}

async function oneWinner(label, statements, failure = /STALE_REVISION|PT409|duplicate key|ALREADY|CONFLICT|NOT_PENDING|TRANSITION_NOT_ALLOWED|PLAYER_MULTI_TEAM_CONFLICT|REGISTRATION_PENDING_ENTRIES|REGISTRATION_NOT_OPEN|REGISTRATION_TRANSITION_NOT_ALLOWED/i) {
  const results = await Promise.all(statements.map(({ client, sql }) => runSql(sql, `${label}:${client}`)));
  const winners = results.filter(({ code }) => code === 0);
  const losers = results.filter(({ code }) => code !== 0);
  assert.equal(winners.length, 1, `${label} expected one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} expected one loser: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, failure, `${label} did not reject the losing write explicitly`);
  return lastJson(winners[0]);
}

const ids = Object.fromEntries([
  "platform", "organizerOwner", "submitOwner", "inviteOwner", "delegateOwner",
  "rosterOwner", "reviewOwner", "jerseyOwner", "multiOwnerA", "multiOwnerB",
  "stageOwner", "closeOwner", "delegateA", "delegateB", "sharedPlayer",
  "rosterPlayer", "reviewPlayer", "jerseyPlayerA", "jerseyPlayerB",
  "organizerGroup", "submitTeam", "inviteTeam", "delegateTeam", "rosterTeam",
  "reviewTeam", "jerseyTeam", "multiTeamA", "multiTeamB", "stageTeam", "closeTeam",
  "competition", "ruleSet", "ruleRevision", "edition", "closeEdition",
  "category", "closeCategory", "inviteEntry", "delegateEntry", "rosterEntry",
  "reviewEntry", "jerseyEntry", "multiEntryA", "multiEntryB", "stageEntry",
  "invite", "delegateRecordA", "delegateRecordB", "roster", "reviewRoster",
  "jerseyRoster", "multiRosterA", "multiRosterB", "stageRoster",
  "rosterRevision", "reviewRevision", "jerseyRevision", "multiRevisionA",
  "multiRevisionB", "stageRevision", "rosterProfile", "reviewProfile",
  "jerseyProfileA", "jerseyProfileB", "sharedProfile", "rosterMember",
  "reviewMember", "jerseyMemberA", "jerseyMemberB", "stageA", "stageB",
  "divisionA", "divisionB", "competitionGroupA", "competitionGroupB",
].map((name) => [name, randomUUID()]));

const operationIds = [];
function operation() { const id = randomUUID(); operationIds.push(id); return id; }
const teams = [
  [ids.organizerGroup, ids.organizerOwner, "Organizer"],
  [ids.submitTeam, ids.submitOwner, "Submit"],
  [ids.inviteTeam, ids.inviteOwner, "Invite"],
  [ids.delegateTeam, ids.delegateOwner, "Delegate"],
  [ids.rosterTeam, ids.rosterOwner, "Roster"],
  [ids.reviewTeam, ids.reviewOwner, "Review"],
  [ids.jerseyTeam, ids.jerseyOwner, "Jersey"],
  [ids.multiTeamA, ids.multiOwnerA, "Multi A"],
  [ids.multiTeamB, ids.multiOwnerB, "Multi B"],
  [ids.stageTeam, ids.stageOwner, "Stage"],
  [ids.closeTeam, ids.closeOwner, "Close"],
];
const users = [...new Set([
  ids.platform, ...teams.map(([, owner]) => owner), ids.delegateA, ids.delegateB,
  ids.sharedPlayer, ids.rosterPlayer, ids.reviewPlayer, ids.jerseyPlayerA, ids.jerseyPlayerB,
])];
let flagBaseline;

const ruleDocument = {
  format: { modality: "futbol7" },
  registration: {
    registrationPolicy: { teamLimits: { minimum: 0, maximum: 100 } },
    rosterPolicy: {
      minimumSize: 1,
      maximumSize: 25,
      multiTeamPolicy: "FORBIDDEN_SAME_EDITION_CATEGORY",
      closeRequiresApprovedRosters: false,
    },
    identityRequirements: { credentialRequired: false },
    kitPolicy: { jerseyRequired: false, jerseyNumberMinimum: 1, jerseyNumberMaximum: 99 },
    publicSummary: { approval: "manual", teamLimits: { minimum: 0, maximum: 100 } },
  },
  structure: { stageGraph: { nodes: [{ id: "league-stage", root: true }], edges: [] } },
};

function entryValues(id, teamId, status = "accepted", editionId = ids.edition, categoryId = ids.category) {
  return `(
    ${quote(id)}::uuid, ${quote(ids.competition)}::uuid, ${quote(editionId)}::uuid,
    ${quote(categoryId)}::uuid, ${quote(teamId)}::uuid, 'PUBLIC_APPLICATION', ${quote(status)},
    ${quote(ids.ruleRevision)}::uuid, ${status === "accepted" ? `${quote(ids.platform)}::uuid` : "null"},
    ${status === "accepted" ? "clock_timestamp()" : "null"}, 'fixture.created', '', 1,
    nextval('private.pachanga_competition_sequence'), ${quote(ids.platform)}::uuid
  )`;
}

function rosterValues(id, entryId, _revisionId, status) {
  return `(
    ${quote(id)}::uuid, ${quote(entryId)}::uuid, ${quote(ids.category)}::uuid,
    ${quote(ids.ruleRevision)}::uuid, ${quote(status)}, null, 1,
    nextval('private.pachanga_competition_sequence'), ${quote(ids.platform)}::uuid
  )`;
}

function revisionValues(id, rosterId, status, count) {
  return `(
    ${quote(id)}::uuid, ${quote(rosterId)}::uuid, 1, ${quote(status)},
    ${quote(ids.ruleRevision)}::uuid, ${count},
    '{"eligible":0,"waived":0,"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}'::jsonb,
    repeat('0', 64), clock_timestamp(), 'Concurrency fixture',
    nextval('private.pachanga_competition_sequence'), ${quote(ids.platform)}::uuid
  )`;
}

try {
  flagBaseline = (await runOk(`
    select foundation_enabled::text || '|' || league_participation_foundation_enabled::text || '|' || league_registration_enabled::text
      || '|' || league_public_registration_enabled::text || '|' || league_delegates_enabled::text
      || '|' || league_rosters_enabled::text || '|' || league_schedule_preferences_enabled::text
    from private.pachanga_competition_foundation_settings where singleton
  `, "read R4A flag baseline")).split("|");

  await runOk(`
    begin;
    grant usage on schema auth to authenticated;
    grant execute on function auth.uid() to authenticated;
    grant execute on function auth.jwt() to authenticated;
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    select user_id, 'r4a-concurrency-' || row_number() over () || '-' || left(user_id::text, 8) || '@example.test',
      clock_timestamp(), jsonb_build_object('full_name', 'R4A Concurrency ' || row_number() over ())
    from unnest(array[${users.map((id) => `${quote(id)}::uuid`).join(",")}]) user_id;
    insert into private.pachanga_platform_admin_roles(user_id, role, active)
    values (${quote(ids.platform)}::uuid, 'platform_owner', true);
    update private.pachanga_competition_foundation_settings set
      foundation_enabled = true,
      league_participation_foundation_enabled = true,
      league_registration_enabled = true,
      league_public_registration_enabled = true,
      league_delegates_enabled = true,
      league_rosters_enabled = true,
      league_schedule_preferences_enabled = true
    where singleton;

    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    values ${teams.map(([group, owner, name]) => `(
      ${quote(group)}::uuid, ${quote(owner)}::uuid, ${quote(`R4A ${name}`)},
      ${quote(`R4${group.replaceAll("-", "").slice(0, 7)}`)},
      '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb, 1
    )`).join(",")};
    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    values ${teams.map(([group, owner, name]) => `(${quote(group)}::uuid, ${quote(owner)}::uuid, 'owner', ${quote(`${name} owner`)})`).join(",")},
      (${quote(ids.multiTeamA)}::uuid, ${quote(ids.sharedPlayer)}::uuid, 'player', 'Shared player'),
      (${quote(ids.multiTeamB)}::uuid, ${quote(ids.sharedPlayer)}::uuid, 'player', 'Shared player'),
      (${quote(ids.rosterTeam)}::uuid, ${quote(ids.rosterPlayer)}::uuid, 'player', 'Roster player'),
      (${quote(ids.reviewTeam)}::uuid, ${quote(ids.reviewPlayer)}::uuid, 'player', 'Review player'),
      (${quote(ids.jerseyTeam)}::uuid, ${quote(ids.jerseyPlayerA)}::uuid, 'player', 'Jersey A'),
      (${quote(ids.jerseyTeam)}::uuid, ${quote(ids.jerseyPlayerB)}::uuid, 'player', 'Jersey B');

    insert into public.pachanga_player_profiles(
      id, user_id, source_group_id, source_player_id, display_name, rating,
      current_overall, base_facets, calibrated_facets, current_facets, position
    ) values
      (${quote(ids.sharedProfile)}::uuid, ${quote(ids.sharedPlayer)}::uuid, ${quote(ids.multiTeamA)}::uuid, 'shared', 'Shared player', 6.5, 65, '{}', '{}', '{}', 'Mediocentro / pivote'),
      (${quote(ids.rosterProfile)}::uuid, ${quote(ids.rosterPlayer)}::uuid, ${quote(ids.rosterTeam)}::uuid, 'roster', 'Roster player', 6.5, 65, '{}', '{}', '{}', 'Defensa central'),
      (${quote(ids.reviewProfile)}::uuid, ${quote(ids.reviewPlayer)}::uuid, ${quote(ids.reviewTeam)}::uuid, 'review', 'Review player', 6.5, 65, '{}', '{}', '{}', 'Portero'),
      (${quote(ids.jerseyProfileA)}::uuid, ${quote(ids.jerseyPlayerA)}::uuid, ${quote(ids.jerseyTeam)}::uuid, 'jersey-a', 'Jersey A', 6.5, 65, '{}', '{}', '{}', 'Delantero centro'),
      (${quote(ids.jerseyProfileB)}::uuid, ${quote(ids.jerseyPlayerB)}::uuid, ${quote(ids.jerseyTeam)}::uuid, 'jersey-b', 'Jersey B', 6.5, 65, '{}', '{}', '{}', 'Lateral derecho');

    insert into public.pachanga_competitions(
      id, organizer_kind, organizer_group_id, name, slug, competition_type,
      visibility, status, created_by
    ) values (
      ${quote(ids.competition)}::uuid, 'TEAM', ${quote(ids.organizerGroup)}::uuid,
      'R4A Concurrency League', ${quote(`r4a-concurrency-${ids.competition.slice(0, 8)}`)},
      'LEAGUE', 'public', 'draft', ${quote(ids.organizerOwner)}::uuid
    );
    insert into public.pachanga_competition_entitlement_grants(
      organizer_kind, organizer_group_id, capability, grant_source, status, reason, granted_by
    ) values (
      'TEAM', ${quote(ids.organizerGroup)}::uuid, 'competition_manage', 'platform_grant',
      'active', 'R4A concurrency entitlement', ${quote(ids.platform)}::uuid
    );
    insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
    values (${quote(ids.ruleSet)}::uuid, ${quote(ids.competition)}::uuid, 'R4A concurrency rules', 'active', ${quote(ids.organizerOwner)}::uuid);
    insert into public.pachanga_competition_rule_revisions(
      id, rule_set_id, version, schema_version, rule_document, checksum,
      effective_from, effective_scope, status, revision, reason, created_by
    ) values (
      ${quote(ids.ruleRevision)}::uuid, ${quote(ids.ruleSet)}::uuid, 1, 'competition_rules.v1',
      ${quote(JSON.stringify(ruleDocument))}::jsonb,
      private.pachanga_competition_rule_checksum_v1('competition_rules.v1', ${quote(JSON.stringify(ruleDocument))}::jsonb),
      clock_timestamp(), 'future_only', 'published', 1, 'R4A concurrency rules', ${quote(ids.organizerOwner)}::uuid
    );
    insert into public.pachanga_competition_editions(
      id, competition_id, name, season_label, starts_at, ends_at, status,
      rule_revision_id, registration_mode, registration_opens_at,
      registration_closes_at, registration_rule_revision_id, revision, created_by
    ) values
      (${quote(ids.edition)}::uuid, ${quote(ids.competition)}::uuid, 'Concurrent edition', 'C1', current_date, current_date + 365, 'registration_open', ${quote(ids.ruleRevision)}::uuid, 'PUBLIC_APPROVAL', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 day', ${quote(ids.ruleRevision)}::uuid, 1, ${quote(ids.organizerOwner)}::uuid),
      (${quote(ids.closeEdition)}::uuid, ${quote(ids.competition)}::uuid, 'Close race edition', 'C2', current_date, current_date + 365, 'registration_open', ${quote(ids.ruleRevision)}::uuid, 'PUBLIC_APPROVAL', clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 day', ${quote(ids.ruleRevision)}::uuid, 1, ${quote(ids.organizerOwner)}::uuid);
    insert into public.pachanga_competition_categories(
      id, edition_id, name, slug, sport_format, visibility, status,
      rule_revision_id, revision, created_by
    ) values
      (${quote(ids.category)}::uuid, ${quote(ids.edition)}::uuid, 'Concurrent Open', 'concurrent-open', 'FOOTBALL_7', 'public', 'active', ${quote(ids.ruleRevision)}::uuid, 1, ${quote(ids.organizerOwner)}::uuid),
      (${quote(ids.closeCategory)}::uuid, ${quote(ids.closeEdition)}::uuid, 'Close Open', 'close-open', 'FOOTBALL_7', 'public', 'active', ${quote(ids.ruleRevision)}::uuid, 1, ${quote(ids.organizerOwner)}::uuid);

    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source, status,
      rule_revision_id, accepted_by, accepted_at, reason_code, reason_text_private,
      revision, server_sequence, created_by
    ) values
      ${entryValues(ids.inviteEntry, ids.inviteTeam, "invited")},
      ${entryValues(ids.delegateEntry, ids.delegateTeam)},
      ${entryValues(ids.rosterEntry, ids.rosterTeam)},
      ${entryValues(ids.reviewEntry, ids.reviewTeam)},
      ${entryValues(ids.jerseyEntry, ids.jerseyTeam)},
      ${entryValues(ids.multiEntryA, ids.multiTeamA)},
      ${entryValues(ids.multiEntryB, ids.multiTeamB)},
      ${entryValues(ids.stageEntry, ids.stageTeam)};
    insert into public.pachanga_competition_entry_invitations(
      id, entry_id, team_id, status, expires_at, revision, invited_by
    ) values (${quote(ids.invite)}::uuid, ${quote(ids.inviteEntry)}::uuid, ${quote(ids.inviteTeam)}::uuid, 'pending', clock_timestamp() + interval '1 day', 1, ${quote(ids.platform)}::uuid);
    insert into public.pachanga_competition_team_delegates(
      id, entry_id, user_id, delegate_role, status, revision, invited_by
    ) values
      (${quote(ids.delegateRecordA)}::uuid, ${quote(ids.delegateEntry)}::uuid, ${quote(ids.delegateA)}::uuid, 'PRIMARY_DELEGATE', 'invited', 1, ${quote(ids.delegateOwner)}::uuid),
      (${quote(ids.delegateRecordB)}::uuid, ${quote(ids.delegateEntry)}::uuid, ${quote(ids.delegateB)}::uuid, 'PRIMARY_DELEGATE', 'invited', 1, ${quote(ids.delegateOwner)}::uuid);

    insert into public.pachanga_competition_rosters(
      id, entry_id, category_id, rule_revision_id, status, current_revision_id,
      revision, server_sequence, created_by
    ) values
      ${rosterValues(ids.roster, ids.rosterEntry, ids.rosterRevision, "draft")},
      ${rosterValues(ids.reviewRoster, ids.reviewEntry, ids.reviewRevision, "submitted")},
      ${rosterValues(ids.jerseyRoster, ids.jerseyEntry, ids.jerseyRevision, "draft")},
      ${rosterValues(ids.multiRosterA, ids.multiEntryA, ids.multiRevisionA, "draft")},
      ${rosterValues(ids.multiRosterB, ids.multiEntryB, ids.multiRevisionB, "draft")},
      ${rosterValues(ids.stageRoster, ids.stageEntry, ids.stageRevision, "draft")};
    insert into public.pachanga_competition_roster_revisions(
      id, roster_id, revision_number, roster_status, rule_revision_id,
      member_count, eligibility_summary, member_set_checksum, effective_from,
      reason, server_sequence, created_by
    ) values
      ${revisionValues(ids.rosterRevision, ids.roster, "draft", 1)},
      ${revisionValues(ids.reviewRevision, ids.reviewRoster, "submitted", 1)},
      ${revisionValues(ids.jerseyRevision, ids.jerseyRoster, "draft", 2)},
      ${revisionValues(ids.multiRevisionA, ids.multiRosterA, "draft", 0)},
      ${revisionValues(ids.multiRevisionB, ids.multiRosterB, "draft", 0)},
      ${revisionValues(ids.stageRevision, ids.stageRoster, "draft", 0)};
    update public.pachanga_competition_rosters rosters set current_revision_id = mapping.revision_id
    from (values
      (${quote(ids.roster)}::uuid, ${quote(ids.rosterRevision)}::uuid),
      (${quote(ids.reviewRoster)}::uuid, ${quote(ids.reviewRevision)}::uuid),
      (${quote(ids.jerseyRoster)}::uuid, ${quote(ids.jerseyRevision)}::uuid),
      (${quote(ids.multiRosterA)}::uuid, ${quote(ids.multiRevisionA)}::uuid),
      (${quote(ids.multiRosterB)}::uuid, ${quote(ids.multiRevisionB)}::uuid),
      (${quote(ids.stageRoster)}::uuid, ${quote(ids.stageRevision)}::uuid)
    ) mapping(roster_id, revision_id)
    where rosters.id = mapping.roster_id;
    insert into public.pachanga_competition_roster_members(
      id, roster_id, roster_revision_id, entry_id, player_profile_id,
      source_group_id, source_user_id, eligibility_status, effective_from,
      public_snapshot, reason_code
    ) values
      (${quote(ids.rosterMember)}::uuid, ${quote(ids.roster)}::uuid, ${quote(ids.rosterRevision)}::uuid, ${quote(ids.rosterEntry)}::uuid, ${quote(ids.rosterProfile)}::uuid, ${quote(ids.rosterTeam)}::uuid, ${quote(ids.rosterPlayer)}::uuid, 'eligible', clock_timestamp(), '{"displayName":"Roster player"}', 'eligibility.valid'),
      (${quote(ids.reviewMember)}::uuid, ${quote(ids.reviewRoster)}::uuid, ${quote(ids.reviewRevision)}::uuid, ${quote(ids.reviewEntry)}::uuid, ${quote(ids.reviewProfile)}::uuid, ${quote(ids.reviewTeam)}::uuid, ${quote(ids.reviewPlayer)}::uuid, 'eligible', clock_timestamp(), '{"displayName":"Review player"}', 'eligibility.valid'),
      (${quote(ids.jerseyMemberA)}::uuid, ${quote(ids.jerseyRoster)}::uuid, ${quote(ids.jerseyRevision)}::uuid, ${quote(ids.jerseyEntry)}::uuid, ${quote(ids.jerseyProfileA)}::uuid, ${quote(ids.jerseyTeam)}::uuid, ${quote(ids.jerseyPlayerA)}::uuid, 'eligible', clock_timestamp(), '{"displayName":"Jersey A"}', 'eligibility.valid'),
      (${quote(ids.jerseyMemberB)}::uuid, ${quote(ids.jerseyRoster)}::uuid, ${quote(ids.jerseyRevision)}::uuid, ${quote(ids.jerseyEntry)}::uuid, ${quote(ids.jerseyProfileB)}::uuid, ${quote(ids.jerseyTeam)}::uuid, ${quote(ids.jerseyPlayerB)}::uuid, 'eligible', clock_timestamp(), '{"displayName":"Jersey B"}', 'eligibility.valid');

    insert into public.pachanga_competition_stages(
      id, edition_id, name, stage_type, stage_order, optional_stage,
      status, rule_revision_id, created_by
    )
    values
      (${quote(ids.stageA)}::uuid, ${quote(ids.edition)}::uuid, 'Stage A', 'LEAGUE_STAGE', 1, false, 'draft', ${quote(ids.ruleRevision)}::uuid, ${quote(ids.organizerOwner)}::uuid),
      (${quote(ids.stageB)}::uuid, ${quote(ids.edition)}::uuid, 'Stage B', 'LEAGUE_STAGE', 2, false, 'draft', ${quote(ids.ruleRevision)}::uuid, ${quote(ids.organizerOwner)}::uuid);
    insert into public.pachanga_competition_divisions(
      id, stage_id, name, division_order, level_label, status, created_by
    )
    values
      (${quote(ids.divisionA)}::uuid, ${quote(ids.stageA)}::uuid, 'Division A', 1, 'A', 'draft', ${quote(ids.organizerOwner)}::uuid),
      (${quote(ids.divisionB)}::uuid, ${quote(ids.stageB)}::uuid, 'Division B', 1, 'B', 'draft', ${quote(ids.organizerOwner)}::uuid);
    insert into public.pachanga_competition_groups(
      id, stage_id, division_id, name, group_order, status, created_by
    )
    values
      (${quote(ids.competitionGroupA)}::uuid, ${quote(ids.stageA)}::uuid, ${quote(ids.divisionA)}::uuid, 'Group A', 1, 'draft', ${quote(ids.organizerOwner)}::uuid),
      (${quote(ids.competitionGroupB)}::uuid, ${quote(ids.stageB)}::uuid, ${quote(ids.divisionB)}::uuid, 'Group B', 1, 'draft', ${quote(ids.organizerOwner)}::uuid);
    commit;
  `, "create R4A concurrency fixtures");

  const replayOperation = operation();
  const replay = await sameCanonical("same operation entry submission", command(
    ids.submitOwner, replayOperation, ids.category, 1, "entry.submit",
    { teamId: ids.submitTeam, reason: "idempotent concurrent submission" },
  ));
  assert.equal(replay.snapshot.entry.status, "submitted");
  assert.equal(await runOk(`select count(*) from private.pachanga_competition_operation_receipts where operation_id = ${quote(replayOperation)}::uuid`, "same operation receipt"), "1");

  const secondSubmitTeam = randomUUID();
  const secondSubmitOwner = randomUUID();
  users.push(secondSubmitOwner);
  teams.push([secondSubmitTeam, secondSubmitOwner, "Second Submit"]);
  await runOk(`
    insert into auth.users(id, email, email_confirmed_at) values (${quote(secondSubmitOwner)}::uuid, ${quote(`r4a-concurrency-second-${secondSubmitOwner}@example.test`)}, clock_timestamp());
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    values (${quote(secondSubmitTeam)}::uuid, ${quote(secondSubmitOwner)}::uuid, 'R4A Second Submit', ${quote(`R4${secondSubmitTeam.replaceAll("-", "").slice(0, 7)}`)}, '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1);
    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    values (${quote(secondSubmitTeam)}::uuid, ${quote(secondSubmitOwner)}::uuid, 'owner', 'Second Submit owner');
  `, "create second submission race team");
  await oneWinner("two submissions for one team/category", [
    { client: "device-a", sql: command(secondSubmitOwner, operation(), ids.category, 1, "entry.submit", { teamId: secondSubmitTeam, reason: "device a" }) },
    { client: "device-b", sql: command(secondSubmitOwner, operation(), ids.category, 1, "entry.submit", { teamId: secondSubmitTeam, reason: "device b" }) },
  ]);

  await oneWinner("invitation accept versus decline", [
    { client: "accept", sql: command(ids.inviteOwner, operation(), ids.inviteEntry, 1, "entry.accept", { reason: "accept" }) },
    { client: "decline", sql: command(ids.inviteOwner, operation(), ids.inviteEntry, 1, "entry.decline", { reason: "decline" }) },
  ]);

  await oneWinner("two primary delegate acceptances", [
    { client: "delegate-a", sql: command(ids.delegateA, operation(), ids.delegateRecordA, 1, "delegate.accept", { reason: "accept A" }) },
    { client: "delegate-b", sql: command(ids.delegateB, operation(), ids.delegateRecordB, 1, "delegate.accept", { reason: "accept B" }) },
  ]);

  await oneWinner("two roster submissions", [
    { client: "device-a", sql: command(ids.rosterOwner, operation(), ids.roster, 1, "roster.submit", { reason: "submit A" }) },
    { client: "device-b", sql: command(ids.rosterOwner, operation(), ids.roster, 1, "roster.submit", { reason: "submit B" }) },
  ]);

  await oneWinner("roster approve versus request changes", [
    { client: "approve", sql: command(ids.platform, operation(), ids.reviewRoster, 1, "roster.approve", { reason: "approve" }) },
    { client: "changes", sql: command(ids.platform, operation(), ids.reviewRoster, 1, "roster.request_changes", { reason: "changes" }) },
  ]);

  await oneWinner("duplicate jersey number", [
    { client: "player-a", sql: command(ids.jerseyOwner, operation(), ids.jerseyRoster, 1, "jersey.assign", { playerProfileId: ids.jerseyProfileA, number: 9, reason: "jersey A" }) },
    { client: "player-b", sql: command(ids.jerseyOwner, operation(), ids.jerseyRoster, 1, "jersey.assign", { playerProfileId: ids.jerseyProfileB, number: 9, reason: "jersey B" }) },
  ]);

  await oneWinner("same player in incompatible team rosters", [
    { client: "team-a", sql: command(ids.multiOwnerA, operation(), ids.multiRosterA, 1, "roster.member.add", { playerProfileId: ids.sharedProfile, reason: "multi A" }) },
    { client: "team-b", sql: command(ids.multiOwnerB, operation(), ids.multiRosterB, 1, "roster.member.add", { playerProfileId: ids.sharedProfile, reason: "multi B" }) },
  ]);
  assert.equal(await runOk(`
    select count(*) from public.pachanga_competition_roster_members members
    join public.pachanga_competition_rosters rosters on rosters.current_revision_id = members.roster_revision_id
    where members.player_profile_id = ${quote(ids.sharedProfile)}::uuid
      and rosters.id in (${quote(ids.multiRosterA)}::uuid, ${quote(ids.multiRosterB)}::uuid)
  `, "canonical multi-team assignment"), "1");

  await oneWinner("two stage reassignments", [
    { client: "stage-a", sql: command(ids.platform, operation(), ids.stageEntry, 1, "stage_membership.assign", { stageId: ids.stageA, divisionId: ids.divisionA, groupId: ids.competitionGroupA, reason: "stage A" }) },
    { client: "stage-b", sql: command(ids.platform, operation(), ids.stageEntry, 1, "stage_membership.assign", { stageId: ids.stageB, divisionId: ids.divisionB, groupId: ids.competitionGroupB, reason: "stage B" }) },
  ]);
  assert.equal(await runOk(`select count(*) from public.pachanga_competition_stage_memberships where entry_id = ${quote(ids.stageEntry)}::uuid and status = 'active'`, "active stage membership"), "1");

  await oneWinner("registration close versus new submission", [
    { client: "close", sql: command(ids.platform, operation(), ids.closeEdition, 1, "registration.close", { reason: "close race" }) },
    { client: "submit", sql: command(ids.closeOwner, operation(), ids.closeCategory, 1, "entry.submit", { teamId: ids.closeTeam, reason: "submit race" }) },
  ]);

  console.log(JSON.stringify({
    concurrentScenarios: 9,
    idempotentReplay: "canonical",
    multiTeamLock: "one_winner",
    result: "all_clients_converged",
  }));
} finally {
  const restoreFlags = flagBaseline ? `
    update private.pachanga_competition_foundation_settings set
      foundation_enabled = ${flagBaseline[0]},
      league_participation_foundation_enabled = ${flagBaseline[1]},
      league_registration_enabled = ${flagBaseline[2]},
      league_public_registration_enabled = ${flagBaseline[3]},
      league_delegates_enabled = ${flagBaseline[4]},
      league_rosters_enabled = ${flagBaseline[5]},
      league_schedule_preferences_enabled = ${flagBaseline[6]}
    where singleton;
  ` : "";
  await runOk(`
    begin;
    alter table private.pachanga_competition_events disable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_competition_operation_receipts disable trigger guard_pachanga_competition_receipts_v1;
    alter table public.pachanga_competition_roster_revisions disable trigger guard_pachanga_competition_roster_revision_v1;
    alter table public.pachanga_competition_rule_revisions disable trigger guard_pachanga_competition_rule_history_v1;
    alter table public.pachanga_competition_discipline_rule_catalogs disable trigger guard_pachanga_discipline_rule_catalog_v1;
    ${restoreFlags}
    delete from public.pachanga_user_notifications where recipient_user_id = any(array[${users.map((id) => `${quote(id)}::uuid`).join(",")}]) and dedupe_key like 'league:%';
    delete from public.pachanga_competition_invalidations where competition_id = ${quote(ids.competition)}::uuid;
    delete from private.pachanga_competition_events where competition_id = ${quote(ids.competition)}::uuid;
    delete from private.pachanga_competition_operation_receipts where operation_id = any(array[${operationIds.map((id) => `${quote(id)}::uuid`).join(",")}]::uuid[]);
    delete from private.pachanga_competition_credential_evidence where credential_id in (select id from public.pachanga_player_competition_credentials where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_eligibility_waivers where roster_member_id in (select id from public.pachanga_competition_roster_members where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid));
    delete from public.pachanga_competition_player_jersey_numbers where roster_revision_id in (select id from public.pachanga_competition_roster_revisions where roster_id in (select id from public.pachanga_competition_rosters where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid)));
    delete from public.pachanga_competition_roster_members where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    update public.pachanga_competition_rosters set current_revision_id = null
    where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_roster_revisions where roster_id in (select id from public.pachanga_competition_rosters where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid));
    delete from public.pachanga_competition_rosters where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_player_competition_credentials where competition_id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competition_team_kits where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_team_availability_constraints where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_team_schedule_preferences where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_stage_memberships where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_team_delegates where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_entry_invitations where entry_id in (select id from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid);
    delete from public.pachanga_competition_entries where competition_id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competition_groups where stage_id in (select id from public.pachanga_competition_stages where edition_id in (${quote(ids.edition)}::uuid, ${quote(ids.closeEdition)}::uuid));
    delete from public.pachanga_competition_divisions where stage_id in (select id from public.pachanga_competition_stages where edition_id in (${quote(ids.edition)}::uuid, ${quote(ids.closeEdition)}::uuid));
    delete from public.pachanga_competition_stages where edition_id in (${quote(ids.edition)}::uuid, ${quote(ids.closeEdition)}::uuid);
    delete from public.pachanga_competition_categories where edition_id in (${quote(ids.edition)}::uuid, ${quote(ids.closeEdition)}::uuid);
    delete from public.pachanga_competition_editions where competition_id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competition_discipline_rule_catalogs
    where rule_revision_id in (select id from public.pachanga_competition_rule_revisions where rule_set_id = ${quote(ids.ruleSet)}::uuid);
    delete from public.pachanga_competition_rule_revisions where rule_set_id = ${quote(ids.ruleSet)}::uuid;
    delete from public.pachanga_competition_rule_sets where competition_id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competition_staff_assignments where competition_id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competitions where id = ${quote(ids.competition)}::uuid;
    delete from public.pachanga_competition_entitlement_grants where organizer_group_id = ${quote(ids.organizerGroup)}::uuid;
    delete from public.pachanga_player_profiles where id in (${[ids.sharedProfile, ids.rosterProfile, ids.reviewProfile, ids.jerseyProfileA, ids.jerseyProfileB].map((id) => `${quote(id)}::uuid`).join(",")});
    delete from public.pachanga_group_members where group_id = any(array[${teams.map(([id]) => `${quote(id)}::uuid`).join(",")}]);
    delete from public.pachanga_groups where id = any(array[${teams.map(([id]) => `${quote(id)}::uuid`).join(",")}]);
    delete from private.pachanga_platform_admin_roles where user_id = ${quote(ids.platform)}::uuid;
    delete from auth.users where id = any(array[${users.map((id) => `${quote(id)}::uuid`).join(",")}]);
    alter table public.pachanga_competition_discipline_rule_catalogs enable trigger guard_pachanga_discipline_rule_catalog_v1;
    alter table public.pachanga_competition_rule_revisions enable trigger guard_pachanga_competition_rule_history_v1;
    alter table public.pachanga_competition_roster_revisions enable trigger guard_pachanga_competition_roster_revision_v1;
    alter table private.pachanga_competition_events enable trigger guard_pachanga_competition_events_v1;
    alter table private.pachanga_competition_operation_receipts enable trigger guard_pachanga_competition_receipts_v1;
    commit;
  `, "R4A concurrency cleanup");
}
