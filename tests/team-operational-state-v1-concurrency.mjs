import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TEAM_OPERATIONAL_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave8b_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave8b-concurrency-${suffix}.sql`);
const owner = "8b000000-0000-4000-8000-000000000001";
const nextOwner = "8b000000-0000-4000-8000-000000000008";
const platformOwner = "8b000000-0000-4000-8000-000000000020";
const teams = Array.from({ length: 18 }, (_, index) =>
  `8b000000-0000-4000-8000-${String(201 + index).padStart(12, "0")}`);
const organizerApplicationSubmitId = "8b200000-0000-4000-8000-000000000001";
const organizerApplicationApproveId = "8b200000-0000-4000-8000-000000000002";
const publicationId = "8b200000-0000-4000-8000-000000000010";
const registrationSubmitId = "8b200000-0000-4000-8000-000000000011";
const registrationAcceptId = "8b200000-0000-4000-8000-000000000012";
const acceptedEntryId = "8b200000-0000-4000-8000-000000000013";
const challengeId = "8b200000-0000-4000-8000-000000000014";
const sportingResultId = "8b200000-0000-4000-8000-000000000020";
const continuitySportingResultId = "8b200000-0000-4000-8000-000000000024";
const fixtureCompetitionId = "c4200000-0000-4000-8000-000000000001";
const fixtureRuleRevisionId = "c4200000-0000-4000-8000-000000000003";
const fixtureEditionId = "c4200000-0000-4000-8000-000000000004";
const fixtureCategoryId = "c4200000-0000-4000-8000-000000000005";
const fixtureHomeEntryId = "c4200000-0000-4000-8000-000000000011";
const fixtureAwayEntryId = "c4200000-0000-4000-8000-000000000012";
const fixtureHomeTeamId = "c4100000-0000-4000-8000-000000000002";
const fixtureAwayTeamId = "c4100000-0000-4000-8000-000000000003";
const fixtureContextId = "c4400000-0000-4000-8000-000000000008";
const fixtureCanonicalMatchId = "c4400000-0000-4000-8000-000000000006";
const fixtureDirector = "c4010000-0000-4000-8000-000000000002";
let summary;
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("TEAM_OPERATIONAL_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 212);
assert.equal(migrations.at(-1), "20260829221312_team_operational_hardening_indexes_flags_v1.sql");

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label = "query Wave 8B concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function authenticated(actorId, statement, role = "authenticated") {
  return `begin;
set local role ${role};
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role, sub: actorId }))}, true);
${statement};
commit;`;
}

function concurrent(sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()],
      { cwd: root, env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.stdin.end(sql);
  });
}

function lastJson(output) {
  const line = output.split("\n").map((item) => item.trim()).filter(Boolean).at(-1);
  return JSON.parse(line);
}

function assertOneWinner(results, loserPattern = /STALE_REVISION|CONFLICT|NOT_FOUND|PLATFORM_DECISION/) {
  assert.equal(results.filter((result) => result.code === 0).length, 1, JSON.stringify(results));
  assert.equal(results.filter((result) => result.code !== 0 && loserPattern.test(result.stderr)).length, 1, JSON.stringify(results));
}

function assertCrossProductConvergence(results) {
  const successes = results.filter((result) => result.code === 0).length;
  assert.ok(successes === 1 || successes === 2, JSON.stringify(results));
  for (const result of results.filter((item) => item.code !== 0)) {
    assert.match(
      result.stderr,
      /TEAM_OPERATIONALLY_RESTRICTED|STALE_REVISION|Server revision is newer|Only the current owner|lock timeout|deadlock detected/i,
      JSON.stringify(results),
    );
  }
  return successes === 1 ? "REJECTED_AFTER_SERIALIZATION" : "CONFIRMED_BEFORE_RESTRICTION_AND_RECONCILED";
}

function command(actorId, operationId, teamId, revision, action, payload, role = "authenticated") {
  return authenticated(actorId, `select public.command_pachanga_team_operational_state_v1(
    ${quote(operationId)}::uuid, ${quote(teamId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"8.1.0+concurrency","serviceWorkerVersion":"sw-wave8b","installedMode":"standalone","surface":"wave8b_concurrency"}'::jsonb
  )`, role);
}

function restrictionPayload(reason, extra = {}) {
  return {
    confirm: true,
    preset: "SOCIAL_ONLY",
    continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
    reasonCode: reason,
    publicMessage: "Synthetic concurrent restriction.",
    ...extra,
  };
}

function suspensionPayload(reason) {
  return {
    confirm: true,
    preset: "FULL_PLATFORM_SUSPENSION",
    continuityPolicy: "FREEZE_FUTURE_SPORTING_WRITES",
    reasonCode: reason,
    publicMessage: "Synthetic concurrent suspension.",
  };
}

function cleanup() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Wave 8B concurrency DB");
  if (exists === "1") {
    admin(`alter database ${databaseName} with allow_connections false`, "close Wave 8B concurrency DB");
    admin("select pg_sleep(0.25)", "wait for Wave 8B concurrency clients");
    admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
      join pg_roles roles on roles.oid=activity.usesysid
      where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`, "terminate Wave 8B concurrency clients");
    admin(`drop database ${databaseName}`, "drop Wave 8B concurrency DB");
  }
  rmSync(infrastructureDump, { force: true });
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 8B concurrency DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump],
    "restore Wave 8B concurrency infrastructure");
  query("create publication supabase_realtime", "create Wave 8B concurrency Realtime publication");
  const applyArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 8B concurrency schema");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/team-operational-state-v1-fixture.sql")], "load Wave 8B concurrency actors");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-f", resolve(root, "tests/league-match-operations-v1-fixture.sql")], "load Wave 8B canonical League graph");

  query(authenticated(platformOwner, `select public.command_pachanga_team_operational_settings_v1(
    ${quote(randomUUID())}::uuid, 1,
    '{"foundationEnabled":true,"enforcementEnabled":true,"restrictionsEnabled":true,"continuityEnabled":true,"appealsEnabled":true,"crossProductGuardsEnabled":true,"publicProjectionEnabled":true,"demoWorldV31Enabled":true,"reason":"Wave 8B concurrency activation"}'::jsonb
  )`), "activate Wave 8B concurrency flags");

  query(`
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    select team_id, ${quote(owner)}::uuid, 'Wave 8B Race ' || ordinal,
      'W8C' || lpad(ordinal::text, 3, '0'),
      jsonb_build_object('name','Wave 8B Race ' || ordinal,'matches','[]'::jsonb,'players','[]'::jsonb,'siteSettings','{}'::jsonb,'venues','[]'::jsonb), 1
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) with ordinality seeded(team_id, ordinal);
    insert into public.pachanga_group_members(group_id,user_id,role,display_name)
    select team_id, ${quote(owner)}::uuid, 'owner', 'Synthetic Owner A'
    from unnest(array[${teams.map((team) => `${quote(team)}::uuid`).join(",")}]) seeded(team_id);
    insert into public.pachanga_group_members(group_id,user_id,role,display_name)
    values (${quote(teams[6])}::uuid, ${quote(nextOwner)}::uuid, 'admin', 'Synthetic Next Owner');

    insert into private.pachanga_organizer_access_applications_v1(
      id, organizer_kind, organizer_group_id, requested_plan_code,
      requested_access_mode, status, intent, expected_competition_type,
      expected_team_count, municipality, area, field_relationship, summary, created_by, submitted_at
    ) values
      (${quote(organizerApplicationSubmitId)}::uuid, 'TEAM', ${quote(teams[7])}::uuid,
        (select plan_code from public.pachanga_organizer_plan_catalog order by plan_code limit 1),
        'PARTNERSHIP_REVIEW', 'draft', 'BOTH', 'BOTH', 8, 'Synthetic City', 'Synthetic Area',
        'Synthetic venue relationship', 'Synthetic concurrent submit', ${quote(owner)}::uuid, null),
      (${quote(organizerApplicationApproveId)}::uuid, 'TEAM', ${quote(teams[8])}::uuid,
        (select plan_code from public.pachanga_organizer_plan_catalog order by plan_code limit 1),
        'PARTNERSHIP_REVIEW', 'under_review', 'BOTH', 'BOTH', 8, 'Synthetic City', 'Synthetic Area',
        'Synthetic venue relationship', 'Synthetic concurrent approval', ${quote(owner)}::uuid, clock_timestamp());

    insert into public.pachanga_competition_publications(
      id, competition_id, edition_id, category_id, slug, visibility,
      lifecycle_status, public_profile, content_fingerprint, created_by
    ) values (
      ${quote(publicationId)}::uuid, ${quote(fixtureCompetitionId)}::uuid,
      ${quote(fixtureEditionId)}::uuid, ${quote(fixtureCategoryId)}::uuid,
      'wave-8b-concurrency-publication', 'private', 'draft', '{}'::jsonb,
      repeat('8', 64), ${quote(fixtureDirector)}::uuid
    );

    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source, status,
      rule_revision_id, accepted_by, accepted_at, reason_code, created_by
    ) values (
      ${quote(acceptedEntryId)}::uuid, ${quote(fixtureCompetitionId)}::uuid,
      ${quote(fixtureEditionId)}::uuid, ${quote(fixtureCategoryId)}::uuid,
      ${quote(teams[10])}::uuid, 'PUBLIC_APPLICATION', 'accepted',
      ${quote(fixtureRuleRevisionId)}::uuid, ${quote(fixtureDirector)}::uuid,
      clock_timestamp(), 'wave8b.concurrent.prepared.entry', ${quote(fixtureDirector)}::uuid
    );

    insert into public.pachanga_competition_registration_requests(
      id, publication_id, competition_id, edition_id, category_id, team_id,
      requested_by, status, message, team_snapshot, capacity_snapshot,
      rule_revision_id, reason_code, created_operation_id
    ) values (
      ${quote(registrationAcceptId)}::uuid, ${quote(publicationId)}::uuid,
      ${quote(fixtureCompetitionId)}::uuid, ${quote(fixtureEditionId)}::uuid,
      ${quote(fixtureCategoryId)}::uuid, ${quote(teams[10])}::uuid,
      ${quote(owner)}::uuid, 'under_review', 'Synthetic acceptance race',
      '{}'::jsonb, '{}'::jsonb, ${quote(fixtureRuleRevisionId)}::uuid,
      'wave8b.concurrent.request.review', ${quote(randomUUID())}::uuid
    );

  `, "seed Wave 8B race Teams");

  const duplicateOperation = randomUUID();
  const duplicatePayload = restrictionPayload("synthetic.duplicate.operation");
  const duplicateRace = await Promise.all([
    concurrent(command(platformOwner, duplicateOperation, teams[0], 1, "team.restriction.apply", duplicatePayload), "duplicate operation A"),
    concurrent(command(platformOwner, duplicateOperation, teams[0], 1, "team.restriction.apply", duplicatePayload), "duplicate operation B"),
  ]);
  assert.equal(duplicateRace.filter((result) => result.code === 0).length, 2, JSON.stringify(duplicateRace));
  assert.deepEqual(lastJson(duplicateRace[0].stdout), lastJson(duplicateRace[1].stdout));
  assert.equal(query(`select count(*) from private.pachanga_team_operational_operation_receipts_v1 where operation_id=${quote(duplicateOperation)}::uuid`), "1");

  const suspensionRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[1], 1, "team.suspend", suspensionPayload("synthetic.suspend.a")), "suspend A"),
    concurrent(command(platformOwner, randomUUID(), teams[1], 1, "team.suspend", suspensionPayload("synthetic.suspend.b")), "suspend B"),
  ]);
  assertOneWinner(suspensionRace);
  assert.equal(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[1])}::uuid`), "2");

  const preparedReview = lastJson(query(command(
    platformOwner, randomUUID(), teams[13], 1, "team.review.open", {
      reasonCode: "synthetic.review.race.prepare",
      safeMessage: "Synthetic review race.",
      evidence: { synthetic: true },
    },
  ), "prepare review close race"));
  const reviewId = query(`select id from private.pachanga_team_operational_reviews_v1
    where group_id=${quote(teams[13])}::uuid and status in ('OPEN','NEEDS_INFORMATION')
    order by server_sequence desc, id desc limit 1`, "read review close race id");
  const closeReviewOperationId = randomUUID();
  const restrictReviewedTeamOperationId = randomUUID();
  const reviewCloseRace = await Promise.all([
    concurrent(command(platformOwner, closeReviewOperationId, teams[13], preparedReview.confirmedRevision, "team.review.close", {
      reviewId,
      outcome: "NO_ACTION",
      reasonCode: "synthetic.review.race.close",
      safeMessage: "Synthetic review closed.",
    }), "close review"),
    concurrent(command(platformOwner, restrictReviewedTeamOperationId, teams[13], preparedReview.confirmedRevision, "team.restriction.apply", {
      ...restrictionPayload("synthetic.review.race.restrict"),
    }), "restrict reviewed Team"),
  ]);
  assertOneWinner(reviewCloseRace, /STALE_REVISION/);
  assert.equal(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[13])}::uuid`), "3");
  assert.equal(query(`select count(*) from private.pachanga_team_operational_operation_receipts_v1
    where operation_id in (${quote(closeReviewOperationId)}::uuid,${quote(restrictReviewedTeamOperationId)}::uuid)`), "1");

  const preparedSuspend = lastJson(query(command(
    platformOwner, randomUUID(), teams[2], 1, "team.suspend", suspensionPayload("synthetic.prepare.restore"),
  ), "prepare suspend vs restore"));
  const restoreRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[2], preparedSuspend.confirmedRevision, "team.restore", { confirm: true, reasonCode: "synthetic.restore" }), "restore"),
    concurrent(command(platformOwner, randomUUID(), teams[2], preparedSuspend.confirmedRevision, "team.restriction.modify", restrictionPayload("synthetic.modify")), "modify suspension"),
  ]);
  assertOneWinner(restoreRace);
  assert.equal(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[2])}::uuid`), "3");

  const expiryAt = new Date(Date.now() + 1_500).toISOString();
  const preparedExpiry = lastJson(query(command(
    platformOwner, randomUUID(), teams[3], 1, "team.restriction.apply",
    restrictionPayload("synthetic.prepare.expiry", { effectiveUntil: expiryAt }),
  ), "prepare expiry race"));
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 1_750));
  const expiryRace = await Promise.all([
    concurrent(command(null, randomUUID(), teams[3], preparedExpiry.confirmedRevision, "team.expire", { reasonCode: "restriction.expired" }, "service_role"), "expire"),
    concurrent(command(platformOwner, randomUUID(), teams[3], preparedExpiry.confirmedRevision, "team.restriction.modify", restrictionPayload("synthetic.expiry.modify")), "modify expiring restriction"),
  ]);
  assertOneWinner(expiryRace);
  assert.equal(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[3])}::uuid`), "3");

  const preparedAppeal = lastJson(query(command(
    platformOwner, randomUUID(), teams[4], 1, "team.restriction.apply", restrictionPayload("synthetic.prepare.appeal"),
  ), "prepare appeal race"));
  const appealRace = await Promise.all([
    concurrent(command(owner, randomUUID(), teams[4], preparedAppeal.confirmedRevision, "team.appeal.create", {
      requestedOutcome: "LIFT", message: "Synthetic concurrent appeal", reasonCode: "synthetic.appeal",
    }), "appeal create"),
    concurrent(command(platformOwner, randomUUID(), teams[4], preparedAppeal.confirmedRevision, "team.restore", {
      confirm: true, reasonCode: "synthetic.platform.restore",
    }), "platform restore"),
  ]);
  assertOneWinner(appealRace);
  assert.equal(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[4])}::uuid`), "3");

  const marketRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[5], 1, "team.suspend", suspensionPayload("synthetic.market.race")), "market suspension"),
    concurrent(`begin;
      insert into public.pachanga_open_matches(source_group_id, source_match_id, date, active, created_by)
      values (${quote(teams[5])}::uuid, 'synthetic-market-race', clock_timestamp() + interval '1 day', true, ${quote(owner)}::uuid);
      commit;`, "legacy market insert"),
  ]);
  assert.equal(marketRace.filter((result) => result.code === 0).length >= 1, true, JSON.stringify(marketRace));
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[5])}::uuid`), "SUSPENDED");
  assert.equal(query(`select count(*) from public.pachanga_open_matches where source_group_id=${quote(teams[5])}::uuid and active`), "0");

  const archiveVsTransfer = await Promise.all([
    concurrent(command(owner, randomUUID(), teams[6], 1, "team.lifecycle.archive", {
      confirm: true, continuityPolicy: "HISTORY_ONLY", reasonCode: "synthetic.archive.transfer",
    }), "archive Team"),
    concurrent(authenticated(owner, `select public.transfer_pachanga_group_ownership_authoritative_v1(
      ${quote(teams[6])}::uuid, ${quote(nextOwner)}::uuid, ${quote(randomUUID())}::uuid, 1,
      '{"clientVersion":"8.1.0+concurrency","surface":"wave8b_concurrency"}'::jsonb
    )`), "transfer Team owner"),
  ]);
  assertOneWinner(archiveVsTransfer, /TEAM_OPERATIONALLY_RESTRICTED|Only the current owner|Server revision is newer|lock timeout/i);
  const archiveOwnerState = lastJson(query(`select jsonb_build_object(
    'lifecycle',(select lifecycle_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[6])}::uuid),
    'ownerId',(select owner_id from public.pachanga_groups where id=${quote(teams[6])}::uuid)
  )`));
  assert.ok(
    (archiveOwnerState.lifecycle === "ARCHIVED" && archiveOwnerState.ownerId === owner)
      || (archiveOwnerState.lifecycle === "ACTIVE" && archiveOwnerState.ownerId === nextOwner),
    JSON.stringify(archiveOwnerState),
  );

  const organizerSubmitRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[7], 1, "team.suspend", suspensionPayload("synthetic.organizer.submit")), "suspend organizer submit Team"),
    concurrent(`begin;
      update private.pachanga_organizer_access_applications_v1 set
        status='submitted', submitted_at=clock_timestamp(), revision=revision+1, updated_at=clock_timestamp()
      where id=${quote(organizerApplicationSubmitId)}::uuid;
      commit;`, "submit Organizer Application"),
  ]);
  const organizerSubmitOutcome = assertCrossProductConvergence(organizerSubmitRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[7])}::uuid`), "SUSPENDED");
  assert.equal(query(`select (status='draft') or operational_blocked_at is not null from private.pachanga_organizer_access_applications_v1 where id=${quote(organizerApplicationSubmitId)}::uuid`), "t");

  const organizerApproveRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[8], 1, "team.suspend", suspensionPayload("synthetic.organizer.approve")), "suspend organizer approval Team"),
    concurrent(`begin;
      update private.pachanga_organizer_access_applications_v1 set
        status='approved', terminal_at=clock_timestamp(), revision=revision+1, updated_at=clock_timestamp()
      where id=${quote(organizerApplicationApproveId)}::uuid;
      commit;`, "approve Organizer Application"),
  ]);
  const organizerApproveOutcome = assertCrossProductConvergence(organizerApproveRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[8])}::uuid`), "SUSPENDED");
  assert.match(query(`select status from private.pachanga_organizer_access_applications_v1 where id=${quote(organizerApplicationApproveId)}::uuid`), /^(under_review|approved)$/);

  const registrationSubmitRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[9], 1, "team.suspend", suspensionPayload("synthetic.registration.submit")), "suspend registration submit Team"),
    concurrent(`begin;
      insert into public.pachanga_competition_registration_requests(
        id, publication_id, competition_id, edition_id, category_id, team_id,
        requested_by, status, message, team_snapshot, capacity_snapshot,
        rule_revision_id, reason_code, created_operation_id
      ) values (
        ${quote(registrationSubmitId)}::uuid, ${quote(publicationId)}::uuid,
        ${quote(fixtureCompetitionId)}::uuid, ${quote(fixtureEditionId)}::uuid,
        ${quote(fixtureCategoryId)}::uuid, ${quote(teams[9])}::uuid,
        ${quote(owner)}::uuid, 'submitted', 'Synthetic submit race', '{}'::jsonb, '{}'::jsonb,
        ${quote(fixtureRuleRevisionId)}::uuid, 'wave8b.concurrent.registration.submit', ${quote(randomUUID())}::uuid
      );
      commit;`, "submit Competition Registration"),
  ]);
  const registrationSubmitOutcome = assertCrossProductConvergence(registrationSubmitRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[9])}::uuid`), "SUSPENDED");
  assert.equal(query(`select count(*)=0 or bool_and(operational_blocked_at is not null) from public.pachanga_competition_registration_requests where id=${quote(registrationSubmitId)}::uuid`), "t");

  const requestAcceptRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[10], 1, "team.suspend", suspensionPayload("synthetic.request.accept")), "suspend request acceptance Team"),
    concurrent(`begin;
      update public.pachanga_competition_registration_requests set
        status='accepted', entry_id=${quote(acceptedEntryId)}::uuid,
        accepted_at=clock_timestamp(), reviewed_at=clock_timestamp(), revision=revision+1,
        updated_at=clock_timestamp()
      where id=${quote(registrationAcceptId)}::uuid;
      commit;`, "accept Competition Registration request"),
  ]);
  const requestAcceptOutcome = assertCrossProductConvergence(requestAcceptRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[10])}::uuid`), "SUSPENDED");
  assert.match(query(`select status from public.pachanga_competition_registration_requests where id=${quote(registrationAcceptId)}::uuid`), /^(under_review|accepted)$/);
  assert.equal(query(`select count(*) from public.pachanga_competition_entries where id=${quote(acceptedEntryId)}::uuid`), "1");

  const challengeRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[11], 1, "team.suspend", suspensionPayload("synthetic.challenge.create")), "suspend challenge Team"),
    concurrent(`begin;
      insert into public.pachanga_team_challenges(
        id, sender_group_id, receiver_group_id, status, scheduled_at, modality,
        field_name, field_address, last_proposed_by_group_id, created_by, updated_by
      ) values (
        ${quote(challengeId)}::uuid, ${quote(teams[11])}::uuid, ${quote(teams[16])}::uuid,
        'proposed', clock_timestamp()+interval '2 days', 'futbol7', 'Synthetic Race Field',
        'Synthetic Race Address', ${quote(teams[11])}::uuid, ${quote(owner)}::uuid, ${quote(owner)}::uuid
      );
      commit;`, "create Team Challenge"),
  ]);
  const challengeOutcome = assertCrossProductConvergence(challengeRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[11])}::uuid`), "SUSPENDED");
  if (query(`select count(*) from public.pachanga_team_challenges where id=${quote(challengeId)}::uuid`) === "1") {
    const followUp = await concurrent(`begin;
      update public.pachanga_team_challenges set status='accepted', revision=revision+1
      where id=${quote(challengeId)}::uuid;
      commit;`, "accept challenge after suspension");
    assert.notEqual(followUp.code, 0, JSON.stringify(followUp));
    assert.match(followUp.stderr, /TEAM_OPERATIONALLY_RESTRICTED/);
  }

  const matchRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), teams[12], 1, "team.suspend", suspensionPayload("synthetic.match.create")), "suspend match creation Team"),
    concurrent(`begin;
      update public.pachanga_groups set payload=jsonb_set(
        payload, '{matches}', '[{"id":"wave8b-concurrent-match","status":"draft"}]'::jsonb
      ) where id=${quote(teams[12])}::uuid;
      commit;`, "create group Match"),
  ]);
  const matchOutcome = assertCrossProductConvergence(matchRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(teams[12])}::uuid`), "SUSPENDED");
  assert.match(query(`select jsonb_array_length(payload->'matches') from public.pachanga_groups where id=${quote(teams[12])}::uuid`), /^(0|1)$/);

  const resultRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), fixtureHomeTeamId, 1, "team.suspend", suspensionPayload("synthetic.result.submit")), "suspend result Team"),
    concurrent(`begin;
      insert into public.pachanga_competition_sporting_results(
        id, canonical_match_id, competition_match_context_id, rule_revision_id,
        state, proposed_by_entry_id, pending_response_from_entry_id,
        response_deadline, confirmation_policy, created_by
      ) values (
        ${quote(sportingResultId)}::uuid, ${quote(fixtureCanonicalMatchId)}::uuid,
        ${quote(fixtureContextId)}::uuid, ${quote(fixtureRuleRevisionId)}::uuid,
        'submitted', ${quote(fixtureHomeEntryId)}::uuid, ${quote(fixtureAwayEntryId)}::uuid,
        clock_timestamp()+interval '48 hours', 'BILATERAL', ${quote(fixtureDirector)}::uuid
      );
      commit;`, "submit Competition result"),
  ]);
  const resultOutcome = assertCrossProductConvergence(resultRace);
  assert.equal(query(`select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=${quote(fixtureHomeTeamId)}::uuid`), "SUSPENDED");
  assert.match(query(`select count(*) from public.pachanga_competition_sporting_results where id=${quote(sportingResultId)}::uuid`), /^(0|1)$/);

  const homeRevision = Number(query(`select current_revision from private.pachanga_team_operational_states_v1 where group_id=${quote(fixtureHomeTeamId)}::uuid`));
  query(command(platformOwner, randomUUID(), fixtureHomeTeamId, homeRevision, "team.restore", {
    confirm: true, reasonCode: "synthetic.result.race.cleanup",
  }), "restore result race Team");
  query(`delete from public.pachanga_competition_sporting_results where id=${quote(sportingResultId)}::uuid`, "remove synthetic result between races");

  const preparedContinuity = lastJson(query(command(
    platformOwner, randomUUID(), fixtureAwayTeamId, 1, "team.suspend", {
      confirm: true,
      preset: "NEW_ACTIVITY_ONLY",
      continuityPolicy: "ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
      reasonCode: "synthetic.continuity.prepare",
      publicMessage: "Synthetic continuity race.",
    },
  ), "prepare continuity race"));
  const continuityRace = await Promise.all([
    concurrent(command(platformOwner, randomUUID(), fixtureAwayTeamId, preparedContinuity.confirmedRevision, "team.continuity.set", {
      competitionId: fixtureCompetitionId,
      policy: "FREEZE_FUTURE_SPORTING_WRITES",
      reasonCode: "synthetic.continuity.freeze",
      publicMessage: "Synthetic competition operations frozen.",
    }), "freeze Competition continuity"),
    concurrent(`begin;
      insert into public.pachanga_competition_sporting_results(
        id, canonical_match_id, competition_match_context_id, rule_revision_id,
        state, proposed_by_entry_id, pending_response_from_entry_id,
        response_deadline, confirmation_policy, created_by
      ) values (
        ${quote(continuitySportingResultId)}::uuid, ${quote(fixtureCanonicalMatchId)}::uuid,
        ${quote(fixtureContextId)}::uuid, ${quote(fixtureRuleRevisionId)}::uuid,
        'submitted', ${quote(fixtureHomeEntryId)}::uuid, ${quote(fixtureAwayEntryId)}::uuid,
        clock_timestamp()+interval '48 hours', 'BILATERAL', ${quote(fixtureDirector)}::uuid
      );
      commit;`, "write sporting result during continuity change"),
  ]);
  const continuityOutcome = assertCrossProductConvergence(continuityRace);
  assert.equal(query(`select policy from private.pachanga_team_operational_continuity_decisions_v1 where group_id=${quote(fixtureAwayTeamId)}::uuid and competition_id=${quote(fixtureCompetitionId)}::uuid order by server_sequence desc, id desc limit 1`), "FREEZE_FUTURE_SPORTING_WRITES");
  assert.match(query(`select count(*) from public.pachanga_competition_sporting_results where id=${quote(continuitySportingResultId)}::uuid`), /^(0|1)$/);

  summary = {
    database: "ephemeral-local",
    duplicateOperationReplay: "PASS",
    twoSuspensions: "PASS",
    reviewCloseVsRestriction: "PASS",
    suspendVsRestore: "PASS",
    restrictVsExpire: "PASS",
    appealVsRestore: "PASS",
    legacyMarketConvergence: "PASS",
    archiveVsOwnerTransfer: "PASS",
    suspendVsOrganizerApplicationSubmit: organizerSubmitOutcome,
    suspendVsApplicationApprove: organizerApproveOutcome,
    suspendVsCompetitionRegistrationSubmit: registrationSubmitOutcome,
    suspendVsRequestAccept: requestAcceptOutcome,
    suspendVsChallengeCreate: challengeOutcome,
    suspendVsMatchCreate: matchOutcome,
    suspendVsCompetitionResult: resultOutcome,
    continuityChangeVsSportingWrite: continuityOutcome,
  };
} finally {
  try {
    cleanup();
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({ ...summary, cleanup: "PASS" })}\n`);
