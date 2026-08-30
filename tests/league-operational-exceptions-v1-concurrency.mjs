import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { leagueOperationalFixtureSql } from "./league-operational-exceptions-v1-fixture.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_r4d_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4d-concurrency-${suffix}.sql`);
const caseDatabases = new Set();
const r4dMigrations = [
  "20260824230726_league_operational_exceptions_schema_v1.sql",
  "20260824230732_league_operational_exceptions_commands_v1.sql",
  "20260824230733_league_operational_exceptions_access_v1.sql",
  "20260824230734_league_operational_exceptions_hardening_v1.sql",
  "20260825021800_league_operational_exceptions_venue_status_fix_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4D_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name <= r4dMigrations.at(-1))
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
assert.equal(migrations.length + 36, 136);
assert.deepEqual(migrations.slice(-r4dMigrations.length), r4dMigrations);

const contextId = "c4400000-0000-4000-8000-000000000008";
const homeEntry = "c4200000-0000-4000-8000-000000000011";
const awayEntry = "c4200000-0000-4000-8000-000000000012";
const director = "c4010000-0000-4000-8000-000000000002";
const homeOwner = "c4010000-0000-4000-8000-000000000003";
const awayOwner = "c4010000-0000-4000-8000-000000000004";
const operationsManager = "d4010000-0000-4000-8000-000000000010";

function targetUrl(databaseName) {
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
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(databaseName, sql, label = "query R4D concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], label);
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function r4dCommandSql(actorId, operationId, revision, action, payload = {}) {
  return `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_league_operational_exceptions_v1(
      ${quote(operationId)}::uuid, ${quote(contextId)}::uuid, ${revision},
      ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"4.0.0+r4d-concurrency","serviceWorkerVersion":"sw-r4d-concurrency","installedMode":"standalone","surface":"r4d_concurrency"}'::jsonb
    );
    commit;
  `;
}

function r4cCommandSql(actorId, operationId, revision, action, payload = {}) {
  return `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_league_match_operations_v1(
      ${quote(operationId)}::uuid, ${quote(contextId)}::uuid, ${revision},
      ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"4.0.0+r4d-concurrency","surface":"r4d_concurrency_setup"}'::jsonb
    );
    commit;
  `;
}

function revision(databaseName) {
  return Number(query(
    databaseName,
    `select revision from public.pachanga_competition_match_contexts where id=${quote(contextId)}::uuid`,
  ));
}

function command(databaseName, actorId, action, payload = {}, kind = "r4d") {
  const sql = kind === "r4c"
    ? r4cCommandSql(actorId, randomUUID(), revision(databaseName), action, payload)
    : r4dCommandSql(actorId, randomUUID(), revision(databaseName), action, payload);
  const output = query(databaseName, sql, `${kind}:${action}`);
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${action} returned no response`);
  return JSON.parse(line);
}

function concurrent(databaseName, sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName)], {
      cwd: root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

async function race(databaseName, left, right) {
  const currentRevision = revision(databaseName);
  const sqlFor = (side) => side.kind === "r4c"
    ? r4cCommandSql(side.actor, randomUUID(), currentRevision, side.action, side.payload)
    : r4dCommandSql(side.actor, randomUUID(), currentRevision, side.action, side.payload);
  return Promise.all([
    concurrent(databaseName, sqlFor(left), left.action),
    concurrent(databaseName, sqlFor(right), right.action),
  ]);
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one loser`);
  assert.match(
    losers[0].stderr,
    /STALE_REVISION|IDEMPOTENCY|R4D_.+_(?:PENDING|ALLOWED|CONFIRMABLE|FOUND|EXISTS)|R4C_.+_(?:FOUND|REQUIRED)|PT409/,
    `${label} loser must be an explicit conflict`,
  );
}

function cloneCase(label) {
  const safe = label.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase();
  const databaseName = `pachangas_r4d_${safe}_${suffix}`;
  admin(`create database ${databaseName} template ${templateDatabase}`, `clone ${label}`);
  caseDatabases.add(databaseName);
  return databaseName;
}

function dropDatabase(databaseName) {
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${databaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      `inspect ${databaseName}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4D_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${databaseName}:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function prepareInProgress(databaseName) {
  for (const side of [
    { actor: homeOwner, entry: homeEntry, member: "c4200000-0000-4000-8000-000000000019", shirt: 9, side: "HOME" },
    { actor: awayOwner, entry: awayEntry, member: "c4200000-0000-4000-8000-000000000020", shirt: 10, side: "AWAY" },
  ]) {
    command(databaseName, side.actor, "squad.create", { entryId: side.entry }, "r4c");
    const squadId = query(databaseName, `select id from public.pachanga_competition_match_squads where competition_match_context_id=${quote(contextId)}::uuid and side=${quote(side.side)}`);
    command(databaseName, side.actor, "squad.member.add", {
      squadId, rosterMemberId: side.member, memberRole: "STARTER",
      shirtNumber: side.shirt, positionOrder: 1, isCaptain: true,
    }, "r4c");
    command(databaseName, side.actor, "squad.submit", { squadId }, "r4c");
    command(databaseName, director, "squad.validate", { squadId }, "r4c");
    command(databaseName, director, "squad.lock", { squadId }, "r4c");
  }
  for (const attendance of [
    { actor: "c4010000-0000-4000-8000-000000000005", entry: homeEntry, member: "c4200000-0000-4000-8000-000000000019" },
    { actor: "c4010000-0000-4000-8000-000000000006", entry: awayEntry, member: "c4200000-0000-4000-8000-000000000020" },
  ]) command(databaseName, attendance.actor, "attendance.set", {
    entryId: attendance.entry, rosterMemberId: attendance.member, status: "going",
  }, "r4c");
  command(databaseName, homeOwner, "attendance.close", { entryId: homeEntry }, "r4c");
  command(databaseName, awayOwner, "attendance.close", { entryId: awayEntry }, "r4c");
  command(databaseName, director, "match.mark_ready", {}, "r4c");
  command(databaseName, director, "match.start", {}, "r4c");
}

function reportAndConfirmSuspension(databaseName) {
  prepareInProgress(databaseName);
  command(databaseName, homeOwner, "suspension.report", {
    reportingEntryId: homeEntry, reportedMinute: 37,
    partialScoreHome: 1, partialScoreAway: 0,
    reasonCode: "CONCURRENCY_SUSPENSION", reasonText: "Suspensión concurrente.",
  });
  const suspensionId = query(databaseName, "select id from public.pachanga_competition_match_suspensions order by server_sequence desc,id desc limit 1");
  command(databaseName, operationsManager, "suspension.confirm", {
    suspensionId, reasonCode: "CONCURRENCY_CONFIRMED",
  });
  return suspensionId;
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create R4D concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump], "restore concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create concurrency publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R4D concurrency template");
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase)],
    "load R4D concurrency fixture",
    `begin;\n${leagueOperationalFixtureSql({ enableFlags: true })}\ncommit;\n`,
  );

  const summaries = {};
  let databaseName = cloneCase("two_requests");
  let results = await race(databaseName,
    { actor: homeOwner, action: "postponement.request", payload: { requestingEntryId: homeEntry, reasonCode: "RACE_REQUEST_A" } },
    { actor: homeOwner, action: "postponement.request", payload: { requestingEntryId: homeEntry, reasonCode: "RACE_REQUEST_B" } });
  assertOneWinner(results, "two postponement requests");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_postponement_requests")), 1);
  summaries.twoRequests = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("accept_reject");
  command(databaseName, homeOwner, "postponement.request", { requestingEntryId: homeEntry, reasonCode: "RACE_RESPONSE" });
  let requestId = query(databaseName, "select id from public.pachanga_competition_postponement_requests order by server_sequence desc,id desc limit 1");
  results = await race(databaseName,
    { actor: awayOwner, action: "postponement.respond", payload: { requestId, responseKind: "ACCEPT", reasonCode: "RACE_ACCEPT" } },
    { actor: awayOwner, action: "postponement.respond", payload: { requestId, responseKind: "REJECT", reasonCode: "RACE_REJECT" } });
  assertOneWinner(results, "accept versus reject");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_postponement_responses")), 1);
  summaries.acceptVsReject = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("reschedule_cancel");
  results = await race(databaseName,
    { actor: operationsManager, action: "fixture.reschedule", payload: { scheduledStart: "2027-03-03T19:00:00Z", scheduledEnd: "2027-03-03T20:10:00Z", timezone: "Europe/Madrid", reasonCode: "RACE_RESCHEDULE" } },
    { actor: operationsManager, action: "fixture.cancel", payload: { cancellationOutcome: "NO_RESULT", reasonCode: "RACE_CANCEL" } });
  assertOneWinner(results, "reschedule versus cancel");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_fixture_changes")), 1);
  summaries.rescheduleVsCancel = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("venue_reschedule");
  results = await race(databaseName,
    { actor: operationsManager, action: "fixture.change_venue", payload: { venueStatus: "LABEL", venueLabel: "Pista carrera R4D", reasonCode: "PITCH_UNAVAILABLE" } },
    { actor: operationsManager, action: "fixture.reschedule", payload: { scheduledStart: "2027-03-04T19:00:00Z", scheduledEnd: "2027-03-04T20:10:00Z", timezone: "Europe/Madrid", reasonCode: "RACE_RESCHEDULE" } });
  assertOneWinner(results, "venue change versus reschedule");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_fixture_changes")), 1);
  summaries.venueVsReschedule = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("arrival_no_show");
  query(databaseName, `update public.pachanga_competition_match_contexts set status='ready', scheduled_start=clock_timestamp()-interval '20 minutes', scheduled_end=clock_timestamp()+interval '50 minutes' where id=${quote(contextId)}::uuid`);
  command(databaseName, homeOwner, "late_arrival.report", { responsibleEntryId: awayEntry, reasonCode: "RACE_DELAY", reasonText: "Retraso concurrente." });
  const lateIncidentId = query(databaseName, "select id from public.pachanga_competition_late_arrival_incidents order by server_sequence desc,id desc limit 1");
  results = await race(databaseName,
    { actor: awayOwner, action: "late_arrival.confirm_arrival", payload: { incidentId: lateIncidentId, reasonCode: "RACE_ARRIVAL" } },
    { actor: homeOwner, action: "no_show.report", payload: { responsibleEntryId: awayEntry, reasonCode: "RACE_NO_SHOW", reasonText: "No comparece tras el margen." } });
  assertOneWinner(results, "arrival versus no-show");
  summaries.arrivalVsNoShow = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_no_show_confirmations");
  query(databaseName, `update public.pachanga_competition_match_contexts set status='ready', scheduled_start=clock_timestamp()-interval '20 minutes', scheduled_end=clock_timestamp()+interval '50 minutes' where id=${quote(contextId)}::uuid`);
  command(databaseName, homeOwner, "no_show.report", { responsibleEntryId: awayEntry, reasonCode: "RACE_NO_SHOW", reasonText: "No comparece." });
  const noShowIncidentId = query(databaseName, "select id from public.pachanga_competition_no_show_incidents order by server_sequence desc,id desc limit 1");
  results = await race(databaseName,
    { actor: operationsManager, action: "no_show.confirm", payload: { incidentId: noShowIncidentId, reasonCode: "RACE_CONFIRM_A" } },
    { actor: director, action: "no_show.confirm", payload: { incidentId: noShowIncidentId, reasonCode: "RACE_CONFIRM_B" } });
  assertOneWinner(results, "two no-show confirmations");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_official_result_decisions")), 1);
  summaries.noShowConfirmations = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("resume_replay");
  const suspensionId = reportAndConfirmSuspension(databaseName);
  results = await race(databaseName,
    { actor: operationsManager, action: "suspension.schedule_resume", payload: { suspensionId, resumeMinute: 37, scheduledStart: "2027-03-05T19:00:00Z", scheduledEnd: "2027-03-05T20:10:00Z", timezone: "Europe/Madrid", venueStatus: "TBD", reasonCode: "RACE_RESUME" } },
    { actor: operationsManager, action: "suspension.order_replay", payload: { suspensionId, scheduledStart: "2027-03-05T19:00:00Z", scheduledEnd: "2027-03-05T20:10:00Z", timezone: "Europe/Madrid", venueStatus: "TBD", reasonCode: "RACE_REPLAY" } });
  assertOneWinner(results, "resume versus replay");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_match_resumption_decisions")), 1);
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_canonical_matches")), 1);
  summaries.resumeVsReplay = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_admin_decisions");
  results = await race(databaseName,
    { actor: operationsManager, action: "administrative_decision.publish", payload: { decisionType: "RESCHEDULE_MATCH", scheduledStart: "2027-03-06T19:00:00Z", scheduledEnd: "2027-03-06T20:10:00Z", timezone: "Europe/Madrid", reasonCode: "RACE_ADMIN_A" } },
    { actor: director, action: "administrative_decision.publish", payload: { decisionType: "RESCHEDULE_MATCH", scheduledStart: "2027-03-07T19:00:00Z", scheduledEnd: "2027-03-07T20:10:00Z", timezone: "Europe/Madrid", reasonCode: "RACE_ADMIN_B" } });
  assertOneWinner(results, "two administrative decisions");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_administrative_decisions")), 1);
  summaries.adminDecisions = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("decision_result_correction");
  query(databaseName, `update public.pachanga_competition_match_contexts set status='ready', scheduled_start=clock_timestamp()-interval '20 minutes', scheduled_end=clock_timestamp()+interval '50 minutes' where id=${quote(contextId)}::uuid`);
  command(databaseName, homeOwner, "no_show.report", { responsibleEntryId: awayEntry, reasonCode: "RACE_NO_SHOW", reasonText: "No comparece." });
  requestId = query(databaseName, "select id from public.pachanga_competition_no_show_incidents order by server_sequence desc,id desc limit 1");
  command(databaseName, operationsManager, "no_show.confirm", { incidentId: requestId, reasonCode: "RACE_NO_SHOW_CONFIRMED" });
  const adminDecisionId = query(databaseName, "select id from public.pachanga_competition_administrative_decisions order by server_sequence desc,id desc limit 1");
  results = await race(databaseName,
    { actor: director, action: "administrative_decision.annul", payload: { decisionId: adminDecisionId, reasonCode: "RACE_ANNUL" } },
    { actor: director, kind: "r4c", action: "official_result.supersede", payload: { outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 2, scoreAway: 0, reasonCode: "RACE_RESULT_CORRECTION", publicExplanation: "Corrección concurrente." } });
  assertOneWinner(results, "administrative decision versus result correction");
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_competition_match_contexts where canonical_match_id='c4400000-0000-4000-8000-000000000006'::uuid`)), 1);
  summaries.decisionVsResultCorrection = "1 winner / 1 stale";
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({ ...summaries, canonicalMatches: 1 })}\n`);
} finally {
  for (const databaseName of [...caseDatabases]) dropDatabase(databaseName);
  dropDatabase(templateDatabase);
  rmSync(infrastructureDump, { force: true });
}
