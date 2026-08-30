import assert from "node:assert/strict";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.PUBLIC_COMPETITIONS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_wave7a_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave7a-concurrency-${suffix}.sql`);
const caseDatabases = new Set();

const competitionId = "7a040000-0000-4000-8000-000000000001";
const editionId = "7a070000-0000-4000-8000-000000000001";
const categoryId = "7a0b0000-0000-4000-8000-000000000001";
const stageId = "7a080000-0000-4000-8000-000000000001";
const ruleRevisionId = "7a060000-0000-4000-8000-000000000001";

function stableUuid(value) {
  const hex = createHash("md5").update(value).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const user = (number) => stableUuid(`wave7a-user-${number}`);
const team = (number) => stableUuid(`wave7a-team-${number}`);
const organizer = user(0);
const platform = user(10);

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("PUBLIC_COMPETITIONS_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const publicCompetitionsBoundary = "20260828072053_public_competition_product_flags_hardening_v1.sql";
const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name <= publicCompetitionsBoundary);
assert.equal(migrations.length, 183);

function databaseUrl(name) {
  const value = new URL(adminUrl);
  value.pathname = `/${name}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 192 * 1024 * 1024,
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

function query(databaseName, sql, label = "query Wave 7A concurrency database") {
  return run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(databaseName), "-c", sql,
  ], label);
}

function authenticated(actorId, statement) {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
${statement};
commit;
`;
}

function publicationSql(actorId, operationId, aggregateId, revision, action, payload = {}) {
  return authenticated(actorId, `select public.command_pachanga_competition_publication_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"7.0.0+concurrency","serviceWorkerVersion":"sw-wave7a","installedMode":"standalone","surface":"wave7a_concurrency"}'::jsonb
  )`);
}

function moderationSql(operationId, aggregateId, revision, action, payload = {}) {
  return authenticated(platform, `select public.command_pachanga_public_competition_moderation_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"7.0.0+concurrency","surface":"wave7a_control_center"}'::jsonb
  )`);
}

function registrationSql(actorId, operationId, aggregateId, revision, action, payload = {}) {
  return authenticated(actorId, `select public.command_pachanga_competition_registration_request_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${revision}, ${quote(action)},
    ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"7.0.0+concurrency","serviceWorkerVersion":"sw-wave7a","installedMode":"standalone","surface":"wave7a_concurrency"}'::jsonb
  )`);
}

function parseLastJson(output, label) {
  const line = output.split("\n").filter((candidate) => candidate.trim().startsWith("{")).at(-1);
  assert.ok(line, `${label} returned no JSON: ${output}`);
  return JSON.parse(line);
}

function command(databaseName, sql, label) {
  return parseLastJson(query(databaseName, sql, label), label);
}

function concurrent(databaseName, sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(databaseName)],
      { cwd: root, env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

function assertOneWinner(results, label, loserPattern) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} expected one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} expected one explicit conflict`);
  assert.match(losers[0].stderr, loserPattern, `${label} returned an unexpected loser: ${losers[0].stderr}`);
}

function cloneCase(label) {
  const safeLabel = label.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase();
  const databaseName = `pachangas_wave7a_${safeLabel}_${suffix}`;
  admin(`create database ${databaseName} template ${templateDatabase}`, `clone ${label}`);
  caseDatabases.add(databaseName);
  return databaseName;
}

function dropDatabase(databaseName) {
  if (admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, `inspect ${databaseName}`) === "0") {
    caseDatabases.delete(databaseName);
    return;
  }
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    where activity.datname=${quote(databaseName)} and activity.backend_type='client backend'
      and activity.pid<>pg_backend_pid()`, `terminate ${databaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      `inspect connections for ${databaseName}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`WAVE7A_CONCURRENCY_CLEANUP_CONNECTIONS:${databaseName}:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function publicationState(databaseName) {
  return JSON.parse(query(databaseName, `select jsonb_build_object(
    'id',publications.id,'revision',publications.revision,'status',publications.lifecycle_status
  )::text from public.pachanga_competition_publications publications
  where publications.competition_id=${quote(competitionId)}::uuid`, "read publication state"));
}

function createRequest(databaseName, teamNumber) {
  const publication = publicationState(databaseName);
  const response = command(databaseName, registrationSql(
    user(teamNumber), randomUUID(), publication.id, publication.revision, "registration.submit",
    { teamId: team(teamNumber), message: `Concurrency request ${teamNumber}`, reason: "Concurrency request" },
  ), `submit Team ${teamNumber}`);
  return { id: response.snapshot.id, revision: response.confirmedRevision };
}

function transitionRequest(databaseName, actorId, request, action, payload = {}) {
  return command(databaseName, registrationSql(
    actorId, randomUUID(), request.id, request.revision, action, payload,
  ), `${action} ${request.id}`);
}

function setupPublishedCompetition(databaseName) {
  const settingsRevision = Number(query(databaseName,
    "select revision from private.pachanga_competition_foundation_settings where singleton",
    "read Wave 7A flag revision"));
  command(databaseName, authenticated(platform, `select public.set_pachanga_public_competition_flags_v1(
    ${quote(randomUUID())}::uuid, ${settingsRevision},
    '{"foundation":true,"publication":true,"discovery":true,"registrationRequests":true,"waitlist":true,"calendar":true,"results":true,"standings":true,"bracket":true,"exceptionStatus":true,"referees":true,"discipline":false,"autoAccept":false}'::jsonb,
    'Wave 7A concurrency activation',
    '{"clientVersion":"7.0.0+concurrency","surface":"wave7a_concurrency"}'::jsonb
  )`), "activate Wave 7A flags");

  let response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, 0, "publication.prepare", {
      editionId,
      categoryId,
      slug: "liga-publica-wave-7a",
      visibility: "public",
      publicProfile: {
        name: "Liga Pública Wave 7A",
        description: "Liga pública para las carreras de autoridad.",
        municipality: "Barcelona",
        generalArea: "Barcelona",
        format: "Liga",
        badge: "BETA",
        rulesSummary: "Capacidad limitada y resultado oficial.",
      },
      publicSections: {
        teams: true,
        calendar: true,
        results: true,
        standings: true,
        bracket: false,
        referees: true,
        venueDetail: false,
        discipline: false,
      },
      reason: "Prepare concurrency publication",
    },
  ), "prepare concurrency publication");
  const publicationId = response.snapshot.publication.id;

  response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, response.confirmedRevision, "registration.configure", {
      mode: "REQUEST_APPROVAL",
      opensAt: "2026-01-01T00:00:00Z",
      closesAt: "2029-01-01T00:00:00Z",
      reason: "Open registration for concurrency",
    },
  ), "configure concurrency registration");
  response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, response.confirmedRevision, "publication.consent", {
      statements: {
        authorizedRepresentative: true,
        informationAccurate: true,
        teamAssetsAuthorized: true,
        indexingAccepted: true,
      },
      purpose: "Concurrency verification",
      reason: "Consent for concurrency publication",
    },
  ), "consent concurrency publication");
  response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, response.confirmedRevision, "publication.submit",
    { reason: "Submit concurrency publication" },
  ), "submit concurrency publication");
  response = command(databaseName, moderationSql(
    randomUUID(), publicationId, response.confirmedRevision, "publication.approve",
    { reason: "Independent concurrency review", publicReason: "Publicación aprobada." },
  ), "approve concurrency publication");
  command(databaseName, moderationSql(
    randomUUID(), publicationId, response.confirmedRevision, "publication.publish",
    { reason: "Publish concurrency fixture", publicReason: "Competición publicada." },
  ), "publish concurrency publication");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create Wave 7A concurrency template");
  caseDatabases.add(templateDatabase);
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(templateDatabase),
    "-f", infrastructureDump,
  ], "restore Wave 7A concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create Wave 7A Realtime publication");
  const applyArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    databaseUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 7A concurrency schema");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(templateDatabase),
    "-f", resolve(root, "tests/public-competitions-v1-fixture.sql"),
  ], "load Wave 7A concurrency fixture");
  setupPublishedCompetition(templateDatabase);

  const summaries = {};
  let databaseName = cloneCase("same_team_submit");
  let publication = publicationState(databaseName);
  let results = await Promise.all([
    concurrent(databaseName, registrationSql(
      user(1), randomUUID(), publication.id, publication.revision, "registration.submit",
      { teamId: team(1), message: "Device A", reason: "Same Team race" },
    ), "same Team device A"),
    concurrent(databaseName, registrationSql(
      user(1), randomUUID(), publication.id, publication.revision, "registration.submit",
      { teamId: team(1), message: "Device B", reason: "Same Team race" },
    ), "same Team device B"),
  ]);
  assertOneWinner(results, "two requests from the same Team", /REGISTRATION_REQUEST_(?:ALREADY_EXISTS|CONFLICT)|PT409/i);
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_competition_registration_requests
    where team_id=${quote(team(1))}::uuid`, "count duplicate Team requests")), 1);
  summaries.sameTeam = "1 winner / 1 conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("last_place");
  let request = createRequest(databaseName, 1);
  transitionRequest(databaseName, organizer, request, "registration.accept", { reason: "Fill first place" });
  const leftRequest = createRequest(databaseName, 2);
  const rightRequest = createRequest(databaseName, 3);
  results = await Promise.all([
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), leftRequest.id, leftRequest.revision, "registration.accept",
      { reason: "Last place A" },
    ), "last place A"),
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), rightRequest.id, rightRequest.revision, "registration.accept",
      { reason: "Last place B" },
    ), "last place B"),
  ]);
  assertOneWinner(results, "two Teams for the last place", /COMPETITION_CAPACITY_REACHED|STALE_REVISION|PT409/i);
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_competition_entries
    where competition_id=${quote(competitionId)}::uuid and status='accepted'`, "count accepted capacity")), 2);
  summaries.lastPlace = "1 winner / 1 capacity conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("accept_vs_withdraw");
  request = createRequest(databaseName, 1);
  results = await Promise.all([
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), request.id, request.revision, "registration.accept", { reason: "Accept race" },
    ), "accept request"),
    concurrent(databaseName, registrationSql(
      user(1), randomUUID(), request.id, request.revision, "registration.withdraw", { reason: "Withdraw race" },
    ), "withdraw request"),
  ]);
  assertOneWinner(results, "accept versus withdraw", /STALE_REVISION|REGISTRATION_(?:ACCEPT|WITHDRAW)_STATE_INVALID|PT409/i);
  assert.match(query(databaseName, `select status from public.pachanga_competition_registration_requests
    where id=${quote(request.id)}::uuid`, "read accept/withdraw state"), /^(accepted|withdrawn)$/);
  summaries.acceptVsWithdraw = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("accept_vs_close");
  request = createRequest(databaseName, 1);
  publication = publicationState(databaseName);
  results = await Promise.all([
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), request.id, request.revision, "registration.accept", { reason: "Accept before close" },
    ), "accept while closing"),
    concurrent(databaseName, publicationSql(
      organizer, randomUUID(), competitionId, publication.revision, "registration.configure",
      { mode: "CLOSED", reason: "Close while accepting" },
    ), "close while accepting"),
  ]);
  assertOneWinner(results, "accept versus registration close", /STALE_REVISION|PUBLIC_REGISTRATION_NOT_OPEN|PT409|deadlock/i);
  summaries.acceptVsClose = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("waitlist_reorder_vs_accept");
  const firstWaitlisted = createRequest(databaseName, 1);
  let waitlistedResponse = transitionRequest(databaseName, organizer, firstWaitlisted, "registration.waitlist", {
    reason: "Waitlist first", publicReason: "Lista de espera.", privateReason: "Concurrency fixture",
  });
  assert.equal(waitlistedResponse.snapshot.waitlistPosition, 1);
  const secondWaitlisted = createRequest(databaseName, 2);
  waitlistedResponse = transitionRequest(databaseName, organizer, secondWaitlisted, "registration.waitlist", {
    reason: "Waitlist second", publicReason: "Lista de espera.", privateReason: "Concurrency fixture",
  });
  const secondWaitlistedRevision = waitlistedResponse.confirmedRevision;
  results = await Promise.all([
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), secondWaitlisted.id, secondWaitlistedRevision, "waitlist.reorder",
      { position: 1, reason: "Reorder race", privateReason: "Concurrency fixture" },
    ), "reorder waitlist"),
    concurrent(databaseName, registrationSql(
      organizer, randomUUID(), secondWaitlisted.id, secondWaitlistedRevision, "registration.accept",
      { reason: "Accept waitlisted race" },
    ), "accept waitlisted"),
  ]);
  assertOneWinner(results, "waitlist reorder versus accept", /STALE_REVISION|REGISTRATION_(?:WAITLIST|ACCEPT)_STATE_INVALID|PT409/i);
  summaries.reorderVsAccept = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("publish_vs_suspend");
  publication = publicationState(databaseName);
  command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, publication.revision, "publication.unpublish",
    { reason: "Prepare publish/suspend race" },
  ), "unpublish before moderation race");
  publication = publicationState(databaseName);
  results = await Promise.all([
    concurrent(databaseName, moderationSql(
      randomUUID(), publication.id, publication.revision, "publication.publish",
      { reason: "Publish race", publicReason: "Publicada." },
    ), "publish race"),
    concurrent(databaseName, moderationSql(
      randomUUID(), publication.id, publication.revision, "publication.suspend",
      { reason: "Suspend race", publicReason: "Suspendida." },
    ), "suspend race"),
  ]);
  assertOneWinner(results, "publish versus suspend", /STALE_REVISION|PUBLICATION_(?:PUBLISH|SUSPEND)_STATE_INVALID|PT409/i);
  summaries.publishVsSuspend = "1 winner / 1 stale or state conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("profile_edit_vs_approval");
  publication = publicationState(databaseName);
  let response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, publication.revision, "publication.update", {
      publicProfile: {
        name: "Liga Pública Wave 7A",
        description: "Contenido listo para revisión concurrente.",
        municipality: "Barcelona",
        generalArea: "Barcelona",
        format: "Liga",
        badge: "BETA",
        rulesSummary: "Capacidad limitada y resultado oficial.",
      },
      reason: "Prepare approval race",
    },
  ), "edit before approval race");
  response = command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, response.confirmedRevision, "publication.consent", {
      statements: {
        authorizedRepresentative: true,
        informationAccurate: true,
        teamAssetsAuthorized: true,
        indexingAccepted: true,
      },
      purpose: "Approval concurrency",
      reason: "Consent approval race",
    },
  ), "consent approval race");
  command(databaseName, publicationSql(
    organizer, randomUUID(), competitionId, response.confirmedRevision, "publication.submit",
    { reason: "Submit approval race" },
  ), "submit approval race");
  publication = publicationState(databaseName);
  results = await Promise.all([
    concurrent(databaseName, publicationSql(
      organizer, randomUUID(), competitionId, publication.revision, "publication.update", {
        publicProfile: {
          name: "Liga Pública Wave 7A",
          description: "Cambio concurrente que invalida el consentimiento.",
          municipality: "Barcelona",
          generalArea: "Barcelona",
          format: "Liga",
        },
        reason: "Concurrent public profile edit",
      },
    ), "public profile edit"),
    concurrent(databaseName, moderationSql(
      randomUUID(), publication.id, publication.revision, "publication.approve",
      { reason: "Concurrent approval", publicReason: "Aprobada." },
    ), "platform approval"),
  ]);
  assertOneWinner(results, "public profile edit versus approval", /STALE_REVISION|PUBLICATION_MODERATION_STATE_INVALID|PT409/i);
  summaries.profileVsApproval = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("archive_vs_submit");
  publication = publicationState(databaseName);
  results = await Promise.all([
    concurrent(databaseName, moderationSql(
      randomUUID(), publication.id, publication.revision, "publication.archive",
      { reason: "Archive request race", publicReason: "Archivada." },
    ), "archive Competition"),
    concurrent(databaseName, registrationSql(
      user(1), randomUUID(), publication.id, publication.revision, "registration.submit",
      { teamId: team(1), message: "Submit while archiving", reason: "Archive race" },
    ), "submit while archiving"),
  ]);
  assertOneWinner(results, "Competition archive versus request submit", /STALE_REVISION|PUBLIC_REGISTRATION_NOT_AVAILABLE|PUBLICATION_ACTIVE_REGISTRATION_REQUESTS|PT409/i);
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_competition_publications publications
    join public.pachanga_competition_registration_requests requests
      on requests.publication_id=publications.id
    where publications.lifecycle_status='archived'
      and requests.status in ('submitted','under_review','waitlisted')`, "verify archive/request exclusion")), 0);
  summaries.archiveVsSubmit = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("result_publish_vs_public_read");
  const canonicalMatchId = randomUUID();
  const contextId = randomUUID();
  const matchSheetId = randomUUID();
  const decisionId = randomUUID();
  query(databaseName, `insert into public.pachanga_canonical_matches(id,status,created_by)
      values (${quote(canonicalMatchId)}::uuid,'active',${quote(organizer)}::uuid);
    insert into public.pachanga_competition_match_contexts(
      id,canonical_match_id,competition_id,edition_id,stage_id,category_id,
      rule_revision_id,status,scheduled_start,scheduled_end,timezone,source_kind,created_by
    ) values (
      ${quote(contextId)}::uuid,${quote(canonicalMatchId)}::uuid,${quote(competitionId)}::uuid,
      ${quote(editionId)}::uuid,${quote(stageId)}::uuid,${quote(categoryId)}::uuid,
      ${quote(ruleRevisionId)}::uuid,'result_pending','2027-10-20T18:00:00Z',
      '2027-10-20T19:15:00Z','Europe/Madrid','LEGACY_LAB',${quote(organizer)}::uuid
    );
    insert into public.pachanga_competition_match_sheets(
      id,canonical_match_id,competition_match_context_id,created_by
    ) values (
      ${quote(matchSheetId)}::uuid,${quote(canonicalMatchId)}::uuid,${quote(contextId)}::uuid,
      ${quote(organizer)}::uuid
    )`, "prepare public result race");
  const writer = `begin;
    insert into public.pachanga_competition_official_result_decisions(
      id,canonical_match_id,competition_match_context_id,outcome,effective_score_home,
      effective_score_away,public_explanation,reason_code,operation_id,authority_role,decided_by
    ) values (
      ${quote(decisionId)}::uuid,${quote(canonicalMatchId)}::uuid,${quote(contextId)}::uuid,
      'CORRECTED_EFFECTIVE_SCORE',4,2,'Resultado oficial concurrente.',
      'result.concurrent_publish',${quote(randomUUID())}::uuid,'competition_director',${quote(organizer)}::uuid
    );
    insert into private.pachanga_competition_official_result_evidence(
      official_result_decision_id,evidence,created_by
    ) values (
      ${quote(decisionId)}::uuid,'{"privateReason":"WAVE7A_PRIVATE_RESULT_EVIDENCE"}'::jsonb,
      ${quote(organizer)}::uuid
    );
    select pg_sleep(0.15);
    update public.pachanga_competition_match_sheets sheets set
      active_official_decision_id=${quote(decisionId)}::uuid,
      revision=sheets.revision+1,updated_at=clock_timestamp()
    where sheets.id=${quote(matchSheetId)}::uuid;
    commit;`;
  const reader = `begin;
    set local role anon;
    select set_config('request.jwt.claims','{"role":"anon"}',true);
    select pg_sleep(0.05);
    select public.get_pachanga_public_competition_calendar_v1('liga-publica-wave-7a');
    commit;`;
  const readRace = await Promise.all([
    concurrent(databaseName, writer, "publish official result"),
    concurrent(databaseName, reader, "read public result"),
  ]);
  assert.equal(readRace[0].code, 0, readRace[0].stderr);
  assert.equal(readRace[1].code, 0, readRace[1].stderr);
  const concurrentSnapshot = parseLastJson(readRace[1].stdout, "concurrent public calendar");
  const concurrentResult = concurrentSnapshot.items.at(-1).result;
  assert.ok(["PENDING", "OFFICIAL"].includes(concurrentResult.status));
  if (concurrentResult.status === "OFFICIAL") {
    assert.deepEqual([concurrentResult.scoreHome, concurrentResult.scoreAway], [4, 2]);
  }
  const finalCalendar = command(databaseName, `select public.get_pachanga_public_competition_calendar_v1(
    'liga-publica-wave-7a',100,0
  )`, "read converged public result");
  const finalFixture = finalCalendar.items.find((item) => item.contextId === contextId);
  assert.equal(finalFixture.result.status, "OFFICIAL");
  assert.deepEqual([finalFixture.result.scoreHome, finalFixture.result.scoreAway], [4, 2]);
  assert.equal(JSON.stringify(finalFixture).includes("WAVE7A_PRIVATE_RESULT_EVIDENCE"), false);
  summaries.resultVsRead = `coherent ${concurrentResult.status.toLowerCase()} / converged official`;
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({
    database: "temporary",
    migrations: 183,
    races: summaries,
    privateEvidenceExposed: false,
  })}\n`);
} finally {
  for (const databaseName of [...caseDatabases].reverse()) {
    try {
      dropDatabase(databaseName);
    } catch (error) {
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    }
  }
  try {
    unlinkSync(infrastructureDump);
  } catch (error) {
    if (!(error instanceof Error) || error.code !== "ENOENT") throw error;
  }
}
