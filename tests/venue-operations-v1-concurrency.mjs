import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.VENUE_OPERATIONS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave9a_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave9a-concurrency-${suffix}.sql`);
const venueOwner = "e9010000-0000-4000-8000-000000000001";
const venueManager = "e9010000-0000-4000-8000-000000000002";
const bookingManager = "e9010000-0000-4000-8000-000000000003";
const replacementOwner = "e9010000-0000-4000-8000-000000000006";
const homeActor = "c4010000-0000-4000-8000-000000000003";
const awayActor = "c4010000-0000-4000-8000-000000000004";
const competitionDirector = "c4010000-0000-4000-8000-000000000002";
const refereeActor = "d6010000-0000-4000-8000-000000000001";
const clubId = "e9020000-0000-4000-8000-000000000001";
const homeTeamId = "c4100000-0000-4000-8000-000000000002";
const awayTeamId = "c4100000-0000-4000-8000-000000000003";
const canonicalMatchId = "e9070000-0000-4000-8000-000000000006";
const contextId = "e9070000-0000-4000-8000-000000000008";
const scheduleItemId = "e9070000-0000-4000-8000-000000000005";
const ruleRevisionId = "e9050000-0000-4000-8000-000000000001";
const assignmentId = "e9030000-0000-4000-8000-000000000001";
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("VENUE_OPERATIONS_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 220);
assert.equal(migrations.at(-1), "20260830145100_venue_hardening_indexes_flags_v1.sql");

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

function query(sql, label = "query Wave 9A concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function claimsSql(actorId, role = "authenticated") {
  const claims = actorId ? { role, sub: actorId } : { role };
  return `set local role ${role};\nselect set_config('request.jwt.claims', ${quote(JSON.stringify(claims))}, true);`;
}

function venueCommandSql(actorId, operationId, aggregateId, revision, action, payload = {}, options = {}) {
  const role = options.role || "authenticated";
  const aggregate = aggregateId ? `${quote(aggregateId)}::uuid` : "null::uuid";
  return `
    begin;
    ${claimsSql(actorId, role)}
    ${options.delayMs ? `select pg_sleep(${Number(options.delayMs) / 1000});` : ""}
    select public.command_pachanga_venue_reservation_v1(
      ${quote(operationId)}::uuid,
      ${aggregate},
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"9.0.0+wave9a-concurrency","serviceWorkerVersion":"sw-wave9a-concurrency","installedMode":"standalone","surface":"wave9a_concurrency"}'::jsonb
    );
    commit;
  `;
}

function clubCommandSql(actorId, operationId, aggregateId, revision, action, payload = {}, options = {}) {
  return `
    begin;
    ${claimsSql(actorId)}
    ${options.delayMs ? `select pg_sleep(${Number(options.delayMs) / 1000});` : ""}
    select public.command_pachanga_club_foundation_v1(
      ${quote(operationId)}::uuid,
      ${quote(aggregateId)}::uuid,
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"9.0.0+wave9a-concurrency","surface":"wave9a_concurrency"}'::jsonb
    );
    commit;
  `;
}

function refereeCommandSql(actorId, operationId, aggregateId, revision, action, payload = {}, options = {}) {
  return `
    begin;
    ${claimsSql(actorId)}
    ${options.delayMs ? `select pg_sleep(${Number(options.delayMs) / 1000});` : ""}
    select public.command_pachanga_referee_assignment_beta_v1(
      ${quote(operationId)}::uuid,
      ${quote(aggregateId)}::uuid,
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"9.0.0+wave9a-concurrency","surface":"wave9a_concurrency"}'::jsonb
    );
    commit;
  `;
}

function parseResponse(output, label) {
  const line = output.split("\n").map((entry) => entry.trim()).filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no response`);
  return JSON.parse(line);
}

function venueCommand(actorId, aggregateId, revision, action, payload = {}, options = {}) {
  const operationId = options.operationId || randomUUID();
  return parseResponse(
    query(venueCommandSql(actorId, operationId, aggregateId, revision, action, payload, options), action),
    action,
  );
}

function refereeCommand(actorId, aggregateId, revision, action, payload = {}) {
  return parseResponse(
    query(refereeCommandSql(actorId, randomUUID(), aggregateId, revision, action, payload), action),
    action,
  );
}

function concurrent(sql, label) {
  return new Promise((resolvePromise) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl()], {
      cwd: root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolvePromise({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

function assertOneWinner(results, label, loserPattern) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one canonical winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one explicit loser: ${JSON.stringify(results)}`);
  assert.match(losers[0].stderr, loserPattern, `${label} loser was not stale/conflict/forbidden`);
  return parseResponse(winners[0].stdout, label);
}

async function runRace(label, firstSql, secondSql, loserPattern) {
  const results = await Promise.all([
    concurrent(firstSql, `${label}:first`),
    concurrent(secondSql, `${label}:second`),
  ]);
  const winner = assertOneWinner(results, label, loserPattern);
  return { label, winnerAction: winner.action, loser: results.find((result) => result.code !== 0).stderr.split("\n").at(-1) };
}

function createVenue(name, slug) {
  const created = venueCommand(venueOwner, null, 0, "venue.create", {
    clubId,
    name,
    slug,
    municipality: "Barcelona",
    generalArea: "Zona sintética Wave 9A",
    timezone: "Europe/Madrid",
    privateAddress: "Dirección sintética privada",
    visibility: "PRIVATE",
  });
  const venueId = created.aggregateId;
  const activated = venueCommand(venueOwner, venueId, created.confirmedRevision, "venue.activate", {
    reasonCode: "CONCURRENCY_FIXTURE",
  });
  return { id: venueId, revision: activated.confirmedRevision };
}

function createPitch(venueId, index) {
  const created = venueCommand(venueManager, null, 0, "pitch.create", {
    venueId,
    name: `Campo C${index}`,
    slug: `campo-c${index}`,
    modalities: ["F7"],
    surface: "ARTIFICIAL_GRASS",
    environment: "OUTDOOR",
    visibility: "PRIVATE",
    minimumSlotMinutes: 60,
    bufferMinutes: 0,
  });
  const pitchId = created.aggregateId;
  const template = venueCommand(venueManager, null, 0, "availability.template.create", {
    pitchId,
    weekday: 1,
    startLocalTime: "18:00",
    endLocalTime: "23:00",
    slotMinutes: 70,
    bufferMinutes: 0,
    validFrom: "2027-01-01",
    validUntil: "2027-12-31",
    timezone: "Europe/Madrid",
    modalities: ["F7"],
    capacity: 1,
    visibility: "PRIVATE",
  });
  return { id: pitchId, revision: created.confirmedRevision, templateId: template.aggregateId, templateRevision: template.confirmedRevision };
}

function requestPayload(venueId, pitchId, localDate, teamId = homeTeamId, extra = {}) {
  return {
    venueId,
    pitchId,
    requesterKind: "TEAM",
    requesterTeamId: teamId,
    purpose: "STANDALONE_MATCH",
    modality: "F7",
    localStart: `${localDate} 20:00`,
    localEnd: `${localDate} 21:10`,
    timezone: "Europe/Madrid",
    offsetMinutes: 120,
    ...extra,
  };
}

function createRequest(actorId, payload, submit = true) {
  const created = venueCommand(actorId, null, 0, "reservation.request.create", payload);
  if (!submit) return { id: created.aggregateId, revision: created.confirmedRevision };
  const submitted = venueCommand(actorId, created.aggregateId, created.confirmedRevision, "reservation.request.submit");
  return { id: created.aggregateId, revision: submitted.confirmedRevision };
}

function acceptAndConfirm(request, requesterActor = homeActor) {
  const accepted = venueCommand(bookingManager, request.id, request.revision, "reservation.accept", {
    terms: { kind: "CONTACT_CLUB" },
  });
  const confirmed = venueCommand(requesterActor, accepted.aggregateId, accepted.confirmedRevision, "reservation.confirm");
  return { id: accepted.aggregateId, revision: confirmed.confirmedRevision };
}

function dropDatabase() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect concurrency database");
  if (exists !== "1") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close concurrency database");
  admin(`select pg_terminate_backend(pid) from pg_stat_activity where datname=${quote(databaseName)} and pid<>pg_backend_pid()`, "terminate concurrency clients");
  admin(`drop database ${databaseName}`, "drop concurrency database");
}

const raceEvidence = [];
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create concurrency database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore concurrency infrastructure");
  query("create publication supabase_realtime", "create concurrency Realtime publication");
  apply([
    resolve(root, manifest.baselinePath),
    ...migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "bootstrap Wave 9A concurrency database");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, "tests/venue-operations-v1-fixture.sql"),
  ], "load Wave 9A concurrency fixture");
  query(`
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    grant execute on function auth.jwt() to authenticated, anon;
    update private.pachanga_club_foundation_settings set club_foundation_enabled=true where singleton;
    insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
    values('${replacementOwner}','wave9a-replacement-owner@example.test',clock_timestamp(),'{"full_name":"Wave 9A Replacement Owner"}')
    on conflict(id) do nothing;
    insert into public.pachanga_club_memberships(club_id,user_id,role,status,accepted_at,invited_by)
    values('${clubId}','${replacementOwner}','club_owner','active',clock_timestamp(),'${venueOwner}')
    ;
  `, "prepare disposable authorities");
  parseResponse(query(`
    begin;
    ${claimsSql(null, "service_role")}
    select public.set_pachanga_venue_flags_v1(
      '${randomUUID()}',1,
      '{"venueFoundationEnabled":true,"venueManagementEnabled":true,"venuePublicProfilesEnabled":true,"venuePublicDirectoryEnabled":true,"venueAvailabilityEnabled":true,"venueReservationRequestsEnabled":true,"venueCounteroffersEnabled":true,"venueReservationHoldsEnabled":true,"venueCanonicalReservationsEnabled":true,"venueMatchBindingEnabled":true,"venueR4dIntegrationEnabled":true,"demoWorldV34Enabled":true}',
      '{"clientVersion":"9.0.0+wave9a-concurrency","surface":"wave9a_concurrency"}'
    );
    commit;
  `, "enable disposable Venue flags"), "enable Venue flags");

  refereeCommand(competitionDirector, assignmentId, 0, "assignment.propose", {
    refereeProfileId: "d6020000-0000-4000-8000-000000000001",
    sourceKind: "competition_generated",
    sourceId: scheduleItemId,
    requesterKind: "COMPETITION",
    requesterId: "c4200000-0000-4000-8000-000000000001",
    assignmentRole: "MAIN_REFEREE",
    responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    feeMode: "FIXED",
    proposedFeeCents: 6500,
    currency: "EUR",
  });
  refereeCommand(refereeActor, assignmentId, 1, "assignment.accept");
  refereeCommand(competitionDirector, assignmentId, 2, "assignment.confirm");

  const venue = createVenue("Pista Barcelona Concurrencia Wave 9A", `centro-concurrencia-${suffix}`);
  const pitches = Array.from({ length: 13 }, (_, index) => createPitch(venue.id, index + 1));

  const lastSlotA = createRequest(homeActor, requestPayload(venue.id, pitches[0].id, "2027-06-07"));
  const lastSlotB = createRequest(awayActor, requestPayload(venue.id, pitches[0].id, "2027-06-07", awayTeamId));
  raceEvidence.push(await runRace(
    "two requests for last slot",
    venueCommandSql(bookingManager, randomUUID(), lastSlotA.id, lastSlotA.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }),
    venueCommandSql(venueOwner, randomUUID(), lastSlotB.id, lastSlotB.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }),
    /VENUE_SLOT_CONFLICT|conflicting key value violates exclusion constraint|pachanga_venue_pitch_claims_no_overlap/i,
  ));

  const doubleAccept = createRequest(homeActor, requestPayload(venue.id, pitches[1].id, "2027-06-14"));
  raceEvidence.push(await runRace(
    "two accepts",
    venueCommandSql(bookingManager, randomUUID(), doubleAccept.id, doubleAccept.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }),
    venueCommandSql(venueOwner, randomUUID(), doubleAccept.id, doubleAccept.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }),
    /STALE_REVISION|VENUE_ACCEPT_NOT_ALLOWED/i,
  ));

  const acceptReject = createRequest(homeActor, requestPayload(venue.id, pitches[2].id, "2027-06-21"));
  raceEvidence.push(await runRace(
    "accept vs reject",
    venueCommandSql(bookingManager, randomUUID(), acceptReject.id, acceptReject.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }),
    venueCommandSql(venueOwner, randomUUID(), acceptReject.id, acceptReject.revision, "reservation.reject", { reasonCode: "RACE_REJECT" }),
    /STALE_REVISION|VENUE_ACCEPT_NOT_ALLOWED|VENUE_REJECT_NOT_ALLOWED/i,
  ));

  const doubleHold = createRequest(homeActor, requestPayload(venue.id, pitches[3].id, "2027-06-28"));
  raceEvidence.push(await runRace(
    "hold vs hold",
    venueCommandSql(bookingManager, randomUUID(), doubleHold.id, doubleHold.revision, "reservation.hold", { expiresInMinutes: 15 }),
    venueCommandSql(venueOwner, randomUUID(), doubleHold.id, doubleHold.revision, "reservation.hold", { expiresInMinutes: 15 }),
    /STALE_REVISION|VENUE_HOLD_NOT_ALLOWED/i,
  ));

  const expiring = createRequest(homeActor, requestPayload(venue.id, pitches[4].id, "2027-07-05"));
  const held = venueCommand(bookingManager, expiring.id, expiring.revision, "reservation.hold", { expiresInMinutes: 15 });
  query(`update public.pachanga_venue_reservation_holds set created_at=clock_timestamp()-interval '2 minutes',expires_at=clock_timestamp()-interval '1 second' where id=${quote(held.aggregateId)}::uuid`, "expire synthetic hold");
  raceEvidence.push(await runRace(
    "hold expiry vs accept",
    venueCommandSql(null, randomUUID(), held.aggregateId, held.confirmedRevision, "reservation.hold.expire", { reasonCode: "CONCURRENCY_EXPIRY" }, { role: "service_role" }),
    venueCommandSql(bookingManager, randomUUID(), expiring.id, Number(query(`select revision from public.pachanga_venue_reservation_requests where id=${quote(expiring.id)}::uuid`)), "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }, { delayMs: 120 }),
    /STALE_REVISION|VENUE_ACCEPT_NOT_ALLOWED|VENUE_HOLD_EXPIRED/i,
  ));

  const counterWithdraw = createRequest(homeActor, requestPayload(venue.id, pitches[5].id, "2027-07-12"));
  raceEvidence.push(await runRace(
    "counter vs withdraw",
    venueCommandSql(bookingManager, randomUUID(), counterWithdraw.id, counterWithdraw.revision, "reservation.counter", { terms: { kind: "CONTACT_CLUB" } }),
    venueCommandSql(homeActor, randomUUID(), counterWithdraw.id, counterWithdraw.revision, "reservation.request.withdraw", { reasonCode: "RACE_WITHDRAW" }),
    /STALE_REVISION|VENUE_COUNTER_TRANSITION_INVALID|VENUE_REQUEST_WITHDRAW_NOT_ALLOWED/i,
  ));

  const bindRequest = createRequest(homeActor, requestPayload(venue.id, pitches[6].id, "2027-05-17", homeTeamId, {
    purpose: "COMPETITION_MATCH",
    competitionId: "c4200000-0000-4000-8000-000000000001",
    canonicalMatchId,
    ruleRevisionId,
  }));
  const bindReservation = acceptAndConfirm(bindRequest);
  raceEvidence.push(await runRace(
    "reservation cancel vs match binding",
    venueCommandSql(homeActor, randomUUID(), bindReservation.id, bindReservation.revision, "reservation.bind_match", {
      canonicalMatchId,
      competitionMatchContextId: contextId,
      scheduleItemId,
      ruleRevisionId,
    }),
    venueCommandSql(homeActor, randomUUID(), bindReservation.id, bindReservation.revision, "reservation.cancel", { reasonCode: "RACE_CANCEL" }, { delayMs: 120 }),
    /STALE_REVISION|VENUE_CANCEL_TRANSITION_INVALID/i,
  ));

  const replacementRequestB = createRequest(homeActor, requestPayload(venue.id, pitches[7].id, "2027-05-17", homeTeamId, {
    purpose: "COMPETITION_MATCH",
    competitionId: "c4200000-0000-4000-8000-000000000001",
    canonicalMatchId,
    ruleRevisionId,
  }));
  const replacementB = acceptAndConfirm(replacementRequestB);
  const contextRevisionB = Number(query(`select revision from public.pachanga_competition_match_contexts where id=${quote(contextId)}::uuid`));
  venueCommand(competitionDirector, replacementB.id, replacementB.revision, "reservation.replace_venue", {
    competitionMatchContextId: contextId,
    expectedContextRevision: contextRevisionB,
    reasonCode: "PITCH_UNAVAILABLE",
    publicSummary: "Cambio sintético previo a la carrera.",
  });
  const assignmentRevision = Number(query(`select revision from public.pachanga_referee_assignments where id=${quote(assignmentId)}::uuid`));
  refereeCommand(refereeActor, assignmentId, assignmentRevision, "assignment.reconfirm");
  const replacementRequestC = createRequest(homeActor, requestPayload(venue.id, pitches[8].id, "2027-05-17", homeTeamId, {
    purpose: "COMPETITION_MATCH",
    competitionId: "c4200000-0000-4000-8000-000000000001",
    canonicalMatchId,
    ruleRevisionId,
  }));
  const replacementC = acceptAndConfirm(replacementRequestC);
  const contextRevisionC = Number(query(`select revision from public.pachanga_competition_match_contexts where id=${quote(contextId)}::uuid`));
  const refereeRevisionC = Number(query(`select revision from public.pachanga_referee_assignments where id=${quote(assignmentId)}::uuid`));
  raceEvidence.push(await runRace(
    "venue change vs referee confirmation",
    venueCommandSql(competitionDirector, randomUUID(), replacementC.id, replacementC.revision, "reservation.replace_venue", {
      competitionMatchContextId: contextId,
      expectedContextRevision: contextRevisionC,
      reasonCode: "PITCH_UNAVAILABLE",
      publicSummary: "Cambio sintético concurrente.",
    }),
    refereeCommandSql(refereeActor, randomUUID(), assignmentId, refereeRevisionC, "assignment.reconfirm", {}, { delayMs: 120 }),
    /STALE_REVISION|REFEREE_ASSIGNMENT_RECONFIRMATION_NOT_REQUIRED/i,
  ));

  const maintenanceRequest = createRequest(homeActor, requestPayload(venue.id, pitches[9].id, "2027-07-19"));
  raceEvidence.push(await runRace(
    "pitch maintenance vs reservation acceptance",
    venueCommandSql(venueManager, randomUUID(), pitches[9].id, pitches[9].revision, "pitch.maintenance", { reasonCode: "RACE_MAINTENANCE" }),
    venueCommandSql(bookingManager, randomUUID(), maintenanceRequest.id, maintenanceRequest.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }, { delayMs: 120 }),
    /VENUE_PITCH_NOT_AVAILABLE|VENUE_PITCH_NOT_ACTIVE|VENUE_SLOT_NOT_AVAILABLE|VENUE_ACCEPT_NOT_ALLOWED/i,
  ));

  const archiveVenue = createVenue("Centro Archivo Wave 9A", `centro-archivo-${suffix}`);
  raceEvidence.push(await runRace(
    "archive Venue vs future request",
    venueCommandSql(venueOwner, randomUUID(), archiveVenue.id, archiveVenue.revision, "venue.archive", { reasonCode: "RACE_ARCHIVE" }),
    venueCommandSql(homeActor, randomUUID(), null, 0, "reservation.request.create", {
      venueId: archiveVenue.id,
      requesterKind: "TEAM",
      requesterTeamId: homeTeamId,
      purpose: "STANDALONE_MATCH",
      modality: "F7",
      localStart: "2027-07-26 20:00",
      localEnd: "2027-07-26 21:10",
      timezone: "Europe/Madrid",
      offsetMinutes: 120,
    }, { delayMs: 120 }),
    /VENUE_NOT_AVAILABLE/i,
  ));

  const availabilityRequest = createRequest(homeActor, requestPayload(venue.id, pitches[10].id, "2027-08-02"), false);
  raceEvidence.push(await runRace(
    "availability edit vs request submit",
    venueCommandSql(venueManager, randomUUID(), pitches[10].templateId, pitches[10].templateRevision, "availability.template.disable", { reasonCode: "RACE_DISABLE" }),
    venueCommandSql(homeActor, randomUUID(), availabilityRequest.id, availabilityRequest.revision, "reservation.request.submit", {}, { delayMs: 120 }),
    /VENUE_SLOT_OUTSIDE_AVAILABILITY|VENUE_AVAILABILITY_NOT_FOUND|VENUE_SLOT_NOT_AVAILABLE/i,
  ));

  const transferRequest = createRequest(homeActor, requestPayload(venue.id, pitches[11].id, "2027-08-09"));
  const clubRevision = Number(query(`select revision from public.pachanga_clubs where id=${quote(clubId)}::uuid`));
  raceEvidence.push(await runRace(
    "owner transfer vs Club acceptance",
    clubCommandSql(venueOwner, randomUUID(), clubId, clubRevision, "club.primary_owner.transfer", {
      targetUserId: replacementOwner,
      retainPreviousOwner: false,
      reason: "Wave 9A concurrent transfer",
    }),
    venueCommandSql(venueOwner, randomUUID(), transferRequest.id, transferRequest.revision, "reservation.accept", { terms: { kind: "CONTACT_CLUB" } }, { delayMs: 150 }),
    /VENUE_ACCEPT_NOT_ALLOWED|CLUB_CAPABILITY_REQUIRED|VENUE_CLUB_AUTHORITY_REQUIRED/i,
  ));

  const invariants = JSON.parse(query(`select jsonb_build_object(
    'activeOverlapCount', (
      select count(*) from public.pachanga_venue_pitch_claims left_claim
      join public.pachanga_venue_pitch_claims right_claim
        on left_claim.id<right_claim.id
       and left_claim.conflict_scope_id=right_claim.conflict_scope_id
       and left_claim.occupied_range && right_claim.occupied_range
      where left_claim.status='ACTIVE' and right_claim.status='ACTIVE'
    ),
    'activeCanonicalBindings', (
      select count(*) from public.pachanga_venue_match_bindings
      where canonical_match_id=${quote(canonicalMatchId)}::uuid and status='ACTIVE'
    ),
    'activeClaimMaxPerScope', coalesce((
      select max(claim_count) from (
        select conflict_scope_id,occupied_range,count(*) claim_count
        from public.pachanga_venue_pitch_claims where status='ACTIVE'
        group by conflict_scope_id,occupied_range
      ) grouped
    ),0),
    'receiptsWithDuplicateOperation', (
      select count(*) from (
        select operation_id from private.pachanga_venue_operation_receipts
        group by operation_id having count(*)>1
      ) duplicates
    )
  )::text`));
  assert.deepEqual(invariants, {
    activeOverlapCount: 0,
    activeCanonicalBindings: 1,
    activeClaimMaxPerScope: 1,
    receiptsWithDuplicateOperation: 0,
  });

  process.stdout.write(`${JSON.stringify({
    database: "ephemeral-local",
    races: raceEvidence.length,
    outcomes: "12 canonical winners / 12 explicit stale-conflict outcomes",
    doubleBookings: 0,
    activeCanonicalBindings: 1,
    evidence: raceEvidence.map(({ label, winnerAction }) => ({ label, winnerAction })),
    cleanup: "PASS",
  })}\n`);
} finally {
  try {
    dropDatabase();
    rmSync(infrastructureDump, { force: true });
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
