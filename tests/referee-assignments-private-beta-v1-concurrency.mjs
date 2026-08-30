import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.REFEREE_ASSIGNMENTS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_wave4_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave4-concurrency-${suffix}.sql`);
const caseDatabases = new Set();

const platformOwner = "c4010000-0000-4000-8000-000000000001";
const director = "c4010000-0000-4000-8000-000000000002";
const competitionId = "c4200000-0000-4000-8000-000000000001";
const playerId = "c4300000-0000-4000-8000-000000000001";
const referees = {
  a: { user: "d6010000-0000-4000-8000-000000000001", profile: "d6020000-0000-4000-8000-000000000001" },
  b: { user: "d6010000-0000-4000-8000-000000000002", profile: "d6020000-0000-4000-8000-000000000002" },
  c: { user: "d6010000-0000-4000-8000-000000000003", profile: "d6020000-0000-4000-8000-000000000003" },
};
const matches = {
  j1: { source: "c4400000-0000-4000-8000-000000000005", canonical: "c4400000-0000-4000-8000-000000000006", context: "c4400000-0000-4000-8000-000000000008" },
  j2: { source: "c4500000-0000-4000-8000-000000000005", canonical: "c4500000-0000-4000-8000-000000000006", context: "c4500000-0000-4000-8000-000000000008" },
  j3: { source: "c4600000-0000-4000-8000-000000000005", canonical: "c4600000-0000-4000-8000-000000000006", context: "c4600000-0000-4000-8000-000000000008" },
  j4: { source: "c4700000-0000-4000-8000-000000000005", canonical: "c4700000-0000-4000-8000-000000000006", context: "c4700000-0000-4000-8000-000000000008" },
};
const r4dExceptionPolicy = Object.freeze({
  gracePeriodMinutes: 10,
  maximumMatchDurationMinutes: 120,
  minimumRestHours: 0,
  noShowLoserScore: 0,
  noShowOutcome: "NO_SHOW",
  noShowWinnerScore: 3,
  organizerApprovalRequired: true,
  organizerCanInterveneAfterDeadline: true,
  postponementDeadlinePolicy: "EXPIRE",
  postponementResponseDeadlineHours: 48,
  resumptionEligibilityPolicy: {
    allowOriginalSquad: true,
    allowReplacementForDocumentedInjury: false,
    requireOriginalEligibility: true,
  },
  resumptionPolicy: "SAME_CANONICAL_MATCH",
  stageWindowEnd: "2027-12-31T23:59:59Z",
  stageWindowStart: "2027-01-01T00:00:00Z",
  venuePolicy: {
    allowSavedVenue: true,
    allowTbd: true,
    allowVenueLabel: true,
  },
});

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("WAVE4_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const assignmentBoundary = "20260826105132_referee_assignment_fk_index_hardening_v1.sql";
const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name <= assignmentBoundary);
assert.equal(migrations.length, 152);

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
    maxBuffer: 128 * 1024 * 1024,
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

function query(databaseName, sql, label = "query Wave 4 concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], label);
}

function authenticated(actorId, statement, tail = "") {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
${statement};
${tail}
commit;
`;
}

function assignmentSql(actorId, operationId, assignmentId, expectedRevision, action, payload = {}, tail = "") {
  return authenticated(actorId, `select public.command_pachanga_referee_assignment_beta_v1(
    ${quote(operationId)}::uuid, ${quote(assignmentId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"6.0.0+wave4-concurrency","serviceWorkerVersion":"sw-wave4-concurrency","installedMode":"standalone","surface":"wave4_concurrency"}'::jsonb
  )`, tail);
}

function officiatingSql(actorId, operationId, assignmentId, expectedRevision, action, payload = {}) {
  return authenticated(actorId, `select public.command_pachanga_referee_officiating_v1(
    ${quote(operationId)}::uuid, ${quote(assignmentId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"6.0.0+wave4-concurrency","serviceWorkerVersion":"sw-wave4-concurrency","installedMode":"standalone","surface":"wave4_concurrency"}'::jsonb
  )`);
}

function reconcileSql(operationId, assignmentId, expectedRevision) {
  return authenticated(platformOwner, `select public.reconcile_pachanga_referee_assignment_v1(
    ${quote(operationId)}::uuid, ${quote(assignmentId)}::uuid, ${expectedRevision},
    '{"clientVersion":"6.0.0+wave4-concurrency","surface":"wave4_concurrency"}'::jsonb
  )`);
}

function r4dSql(operationId, expectedRevision, payload, tail = "") {
  return authenticated(director, `select public.command_pachanga_league_operational_exceptions_v1(
    ${quote(operationId)}::uuid, ${quote(matches.j1.context)}::uuid, ${expectedRevision},
    'fixture.reschedule', ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"6.0.0+wave4-concurrency","serviceWorkerVersion":"sw-wave4-concurrency","installedMode":"standalone","surface":"wave4_concurrency"}'::jsonb
  )`, tail);
}

function parseLastJson(output, label) {
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no JSON`);
  return JSON.parse(line);
}

function command(databaseName, sql, label) {
  return parseLastJson(query(databaseName, sql, label), label);
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
  return Promise.all([
    concurrent(databaseName, left.sql, left.label),
    concurrent(databaseName, right.sql, right.label),
  ]);
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} expected one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} expected one explicit loser`);
  assert.match(
    losers[0].stderr,
    /STALE_REVISION|REFEREE_(?:ASSIGNMENT|TERMS|CURRENT|OFFICIATING).*(?:CONFLICT|REQUIRED|TAKEN|ACCEPTABLE|COUNTERABLE|CONFIRMED|CANCELLABLE|REPLACEABLE)|PT409|duplicate key/i,
    `${label} loser was not an explicit stale/conflict`,
  );
  return { winner: winners[0], loser: losers[0] };
}

function cloneCase(label) {
  const safe = label.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase();
  const databaseName = `pachangas_wave4_${safe}_${suffix}`;
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
    if (attempt === 29) throw new Error(`WAVE4_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${databaseName}:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function proposalPayload(refereeProfileId, match, feeMode = "FREE", extra = {}) {
  return {
    refereeProfileId,
    sourceKind: "competition_generated",
    sourceId: match.source,
    requesterKind: "COMPETITION",
    requesterId: competitionId,
    responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
    feeMode,
    ...extra,
  };
}

function propose(databaseName, referee, match, feeMode = "FREE", extra = {}) {
  const assignmentId = randomUUID();
  command(databaseName, assignmentSql(
    director, randomUUID(), assignmentId, 0, "assignment.propose",
    proposalPayload(referee.profile, match, feeMode, extra),
  ), "propose assignment");
  return assignmentId;
}

function accept(databaseName, referee, assignmentId) {
  return command(databaseName, assignmentSql(
    referee.user, randomUUID(), assignmentId, 1, "assignment.accept",
  ), "accept assignment");
}

function confirm(databaseName, assignmentId, expectedRevision = 2) {
  return command(databaseName, assignmentSql(
    director, randomUUID(), assignmentId, expectedRevision, "assignment.confirm",
  ), "confirm assignment");
}

function prepareR4dPolicy(databaseName) {
  query(databaseName, `
    alter table public.pachanga_competition_rule_revisions
      disable trigger guard_pachanga_competition_rule_history_v1;
    with patched as (
      select revisions.id, revisions.schema_version,
        jsonb_set(
          revisions.rule_document,
          '{operations,exceptionPolicy}',
          ${quote(JSON.stringify(r4dExceptionPolicy))}::jsonb,
          true
        ) as document
      from public.pachanga_competition_rule_revisions revisions
      where revisions.id='c4200000-0000-4000-8000-000000000003'::uuid
    )
    update public.pachanga_competition_rule_revisions revisions set
      rule_document=patched.document,
      checksum=private.pachanga_competition_rule_checksum_v1(
        patched.schema_version,
        patched.document
      )
    from patched where revisions.id=patched.id;
    alter table public.pachanga_competition_rule_revisions
      enable trigger guard_pachanga_competition_rule_history_v1;
  `, "prepare canonical R4D policy in disposable fixture");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create Wave 4 concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump], "restore concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create concurrency publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 4 concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", resolve(root, "tests/referee-assignments-private-beta-v1-fixture.sql")], "load Wave 4 concurrency fixture");
  query(templateDatabase, `update private.pachanga_referee_foundation_settings set
    referee_assignment_private_beta_enabled=true,
    referee_assignments_enabled=true,
    revision=revision+1 where singleton`, "enable isolated Wave 4 flags");

  const summaries = {};
  let databaseName = cloneCase("two_referees_one_slot");
  let assignmentA = propose(databaseName, referees.a, matches.j2);
  let assignmentB = propose(databaseName, referees.b, matches.j2);
  let results = await race(databaseName,
    { label: "accept-a", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 1, "assignment.accept") },
    { label: "accept-b", sql: assignmentSql(referees.b.user, randomUUID(), assignmentB, 1, "assignment.accept") });
  assertOneWinner(results, "two referees accept one MAIN slot");
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_referee_assignments where canonical_match_id=${quote(matches.j2.canonical)}::uuid and status='accepted'`)), 1);
  summaries.twoRefereesOneSlot = "1 winner / 1 conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("accept_decline");
  assignmentA = propose(databaseName, referees.a, matches.j1);
  results = await race(databaseName,
    { label: "accept", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 1, "assignment.accept") },
    { label: "decline", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 1, "assignment.decline") });
  assertOneWinner(results, "accept versus decline");
  assert.match(query(databaseName, `select status from public.pachanga_referee_assignments where id=${quote(assignmentA)}::uuid`), /accepted|declined/);
  summaries.acceptVsDecline = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("confirm_cancel");
  assignmentA = propose(databaseName, referees.a, matches.j1);
  accept(databaseName, referees.a, assignmentA);
  results = await race(databaseName,
    { label: "confirm", sql: assignmentSql(director, randomUUID(), assignmentA, 2, "assignment.confirm") },
    { label: "cancel", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 2, "assignment.cancel", { reasonCode: "race_cancel" }) });
  assertOneWinner(results, "confirm versus cancel");
  assert.match(query(databaseName, `select status from public.pachanga_referee_assignments where id=${quote(assignmentA)}::uuid`), /confirmed|cancelled/);
  summaries.confirmVsCancel = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_replacements");
  assignmentA = propose(databaseName, referees.a, matches.j2);
  accept(databaseName, referees.a, assignmentA);
  confirm(databaseName, assignmentA);
  const replacementB = randomUUID();
  const replacementC = randomUUID();
  results = await race(databaseName,
    { label: "replace-b", sql: assignmentSql(director, randomUUID(), assignmentA, 3, "assignment.replace", {
      newRefereeProfileId: referees.b.profile, newAssignmentId: replacementB,
      responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(), feeMode: "FREE",
    }) },
    { label: "replace-c", sql: assignmentSql(director, randomUUID(), assignmentA, 3, "assignment.replace", {
      newRefereeProfileId: referees.c.profile, newAssignmentId: replacementC,
      responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(), feeMode: "VOLUNTEER",
    }) });
  assertOneWinner(results, "two replacements");
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_referee_assignments where replaces_assignment_id=${quote(assignmentA)}::uuid`)), 1);
  summaries.twoReplacements = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("replace_cancel");
  assignmentA = propose(databaseName, referees.a, matches.j2);
  accept(databaseName, referees.a, assignmentA);
  confirm(databaseName, assignmentA);
  assignmentB = randomUUID();
  results = await race(databaseName,
    { label: "replace", sql: assignmentSql(director, randomUUID(), assignmentA, 3, "assignment.replace", {
      newRefereeProfileId: referees.b.profile, newAssignmentId: assignmentB,
      responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(), feeMode: "FREE",
    }) },
    { label: "cancel", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 3, "assignment.cancel", { reasonCode: "race_cancel" }) });
  assertOneWinner(results, "replace versus cancel");
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_referee_assignments where canonical_match_id=${quote(matches.j2.canonical)}::uuid and status in ('accepted','confirmed','completed')`)) <= 1, true);
  summaries.replaceVsCancel = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("assignment_r5");
  assignmentB = propose(databaseName, referees.b, matches.j2);
  accept(databaseName, referees.b, assignmentB);
  confirm(databaseName, assignmentB);
  query(databaseName, `update public.pachanga_competition_match_contexts set status='ready',revision=revision+1 where id=${quote(matches.j2.context)}::uuid`, "make match officiable");
  results = await race(databaseName,
    { label: "discipline", sql: officiatingSql(referees.b.user, randomUUID(), assignmentB, 3, "discipline.record", {
      playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 17,
    }) },
    { label: "cancel", sql: assignmentSql(director, randomUUID(), assignmentB, 3, "assignment.cancel", { reasonCode: "race_cancel" }) });
  assertOneWinner(results, "assignment cancellation versus R5 report");
  const assignmentStatus = query(databaseName, `select status from public.pachanga_referee_assignments where id=${quote(assignmentB)}::uuid`);
  const eventCount = Number(query(databaseName, `select count(*) from public.pachanga_competition_disciplinary_events where referee_assignment_id=${quote(assignmentB)}::uuid`));
  assert.equal(eventCount, assignmentStatus === "confirmed" ? 1 : 0);
  summaries.assignmentVsR5 = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("completion_reconcile");
  assignmentB = propose(databaseName, referees.b, matches.j2);
  accept(databaseName, referees.b, assignmentB);
  confirm(databaseName, assignmentB);
  query(databaseName, `update public.pachanga_competition_match_contexts set status='official',revision=revision+1 where id=${quote(matches.j2.context)}::uuid`, "conclude canonical match");
  const reconcileA = randomUUID();
  const reconcileB = randomUUID();
  results = await race(databaseName,
    { label: "reconcile-a", sql: reconcileSql(reconcileA, assignmentB, 3) },
    { label: "reconcile-b", sql: reconcileSql(reconcileB, assignmentB, 3) });
  const completionRace = assertOneWinner(results, "two completion reconciliations");
  const winningOperation = query(databaseName, `select operation_id from private.pachanga_referee_operation_receipts where operation_id in (${quote(reconcileA)}::uuid,${quote(reconcileB)}::uuid)`);
  command(databaseName, reconcileSql(winningOperation, assignmentB, 3), "replay completion receipt");
  assert.equal(query(databaseName, `select status from public.pachanga_referee_assignments where id=${quote(assignmentB)}::uuid`), "completed");
  assert.ok(completionRace.winner.stdout);
  summaries.completionReconcile = "1 winner / 1 stale / replay canonical";
  dropDatabase(databaseName);

  databaseName = cloneCase("fee_accept_counter");
  assignmentA = propose(databaseName, referees.a, matches.j1, "NEGOTIABLE", { proposedFeeCents: 5000 });
  results = await race(databaseName,
    { label: "accept", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 1, "assignment.accept") },
    { label: "counter", sql: assignmentSql(referees.a.user, randomUUID(), assignmentA, 1, "terms.counter", { counterFeeCents: 6000 }) });
  assertOneWinner(results, "fee accept versus counter");
  assert.match(query(databaseName, `select status||'|'||terms_status from public.pachanga_referee_assignments join private.pachanga_referee_assignment_terms on assignment_id=id where id=${quote(assignmentA)}::uuid`), /accepted\|ACCEPTED|proposed\|COUNTERED/);
  summaries.feeAcceptVsCounter = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("r4d_schedule_vs_r5");
  prepareR4dPolicy(databaseName);
  assignmentA = propose(databaseName, referees.a, matches.j1);
  accept(databaseName, referees.a, assignmentA);
  confirm(databaseName, assignmentA);
  query(databaseName, `update public.pachanga_competition_match_contexts set status='ready',revision=revision+1 where id=${quote(matches.j1.context)}::uuid`, "make R4D race match officiable");
  const officiatingContextRevision = Number(query(databaseName, `select revision from public.pachanga_competition_match_contexts where id=${quote(matches.j1.context)}::uuid`));
  const officiatingSchedulePromise = concurrent(databaseName, r4dSql(randomUUID(), officiatingContextRevision, {
    scheduledStart: "2027-03-01T20:00:00Z",
    scheduledEnd: "2027-03-01T21:10:00Z",
    timezone: "Europe/Madrid",
    venueStatus: "LABEL",
    venueLabel: "Pista R4C",
    reasonCode: "WAVE4_OFFICIATING_CONCURRENCY_RESCHEDULE",
  }, "select pg_sleep(0.35);"), "schedule-before-discipline");
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 80));
  const staleDisciplinePromise = concurrent(databaseName, officiatingSql(
    referees.a.user, randomUUID(), assignmentA, 3, "discipline.record", {
      playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 22,
    },
  ), "discipline-old-schedule");
  results = await Promise.all([officiatingSchedulePromise, staleDisciplinePromise]);
  assertOneWinner(results, "effective schedule change versus R5 report");
  assert.equal(query(databaseName, `select schedule_state from public.pachanga_referee_assignments where id=${quote(assignmentA)}::uuid`), "RECONFIRMATION_REQUIRED");
  assert.equal(Number(query(databaseName, `select count(*) from public.pachanga_competition_disciplinary_events where referee_assignment_id=${quote(assignmentA)}::uuid`)), 0);
  summaries.scheduleChangeVsR5 = "schedule winner / stale report / zero R5 events";
  dropDatabase(databaseName);

  databaseName = cloneCase("confirm_schedule_change");
  prepareR4dPolicy(databaseName);
  assignmentA = propose(databaseName, referees.a, matches.j1);
  accept(databaseName, referees.a, assignmentA);
  const contextRevision = Number(query(databaseName, `select revision from public.pachanga_competition_match_contexts where id=${quote(matches.j1.context)}::uuid`));
  const schedulePromise = concurrent(databaseName, r4dSql(randomUUID(), contextRevision, {
    scheduledStart: "2027-03-01T20:00:00Z",
    scheduledEnd: "2027-03-01T21:10:00Z",
    timezone: "Europe/Madrid",
    venueStatus: "LABEL",
    venueLabel: "Pista R4C",
    reasonCode: "WAVE4_CONCURRENCY_RESCHEDULE",
  }, "select pg_sleep(0.35);"), "schedule-change");
  await new Promise((resolveDelay) => setTimeout(resolveDelay, 80));
  const confirmPromise = concurrent(databaseName, assignmentSql(
    director, randomUUID(), assignmentA, 2, "assignment.confirm",
  ), "confirm-old-schedule");
  results = await Promise.all([schedulePromise, confirmPromise]);
  assertOneWinner(results, "confirm versus effective schedule change");
  assert.equal(query(databaseName, `select schedule_state from public.pachanga_referee_assignments where id=${quote(assignmentA)}::uuid`), "STALE_SCHEDULE");
  summaries.confirmVsScheduleChange = "schedule winner / stale confirmation / new schedule acceptance required";
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({ database: "temporary clones", migrations: 152, races: summaries })}\n`);
} finally {
  for (const databaseName of [...caseDatabases]) dropDatabase(databaseName);
  if (admin(`select count(*) from pg_database where datname=${quote(templateDatabase)}`, "find Wave 4 template") === "1") {
    dropDatabase(templateDatabase);
  }
  rmSync(infrastructureDump, { force: true });
}
