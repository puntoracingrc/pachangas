import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.SEASON_VENUE_ALLOCATION_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave9b_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave9b-concurrency-${suffix}.sql`);
const platformOwner = "e9010000-0000-4000-8000-000000000001";
const bookingManager = "e9010000-0000-4000-8000-000000000003";
const competitionDirector = "c4010000-0000-4000-8000-000000000002";
const competitionId = "c4200000-0000-4000-8000-000000000001";
const editionId = "c4200000-0000-4000-8000-000000000004";
const stageId = "c4200000-0000-4000-8000-000000000006";
const schedulePlanId = "e9070000-0000-4000-8000-000000000001";
const scheduleRevisionId = "e9070000-0000-4000-8000-000000000002";
const ruleRevisionId = "e9050000-0000-4000-8000-000000000001";
const canonicalMatchId = "e9070000-0000-4000-8000-000000000006";
const ownerClubId = "e9020000-0000-4000-8000-000000000001";
const venueId = "e9b20000-0000-4000-8000-000000000001";
const pitchAlpha = "e9b20000-0000-4000-8000-000000000011";
const pitchBeta = "e9b20000-0000-4000-8000-000000000012";
let cleanupFailure;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("SEASON_VENUE_ALLOCATION_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 228);
assert.equal(migrations.at(-1), "20260830223014_competition_venue_allocation_hardening_flags_v1.sql");

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

function query(sql, label = "query Wave 9B concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function claimsSql(actorId) {
  return `set local role authenticated;\nselect set_config('request.jwt.claims', ${quote(JSON.stringify({
    role: "authenticated",
    sub: actorId,
  }))}, true);`;
}

function allocationCommandSql(actorId, operationId, aggregateId, revision, action, payload = {}, delayMs = 0) {
  return `
    begin;
    ${claimsSql(actorId)}
    ${delayMs ? `select pg_sleep(${Number(delayMs) / 1000});` : ""}
    select public.command_pachanga_competition_venue_allocation_v1(
      ${quote(operationId)}::uuid,
      ${aggregateId ? `${quote(aggregateId)}::uuid` : "null::uuid"},
      ${Number(revision)},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"9.2.0+wave9b-concurrency","serviceWorkerVersion":"sw-wave9b-concurrency","installedMode":"standalone","surface":"wave9b_concurrency"}'::jsonb
    );
    commit;
  `;
}

function parseResponse(output, label) {
  const line = output.split("\n").map((entry) => entry.trim()).filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no response`);
  return JSON.parse(line);
}

function command(actorId, aggregateId, revision, action, payload = {}, operationId = randomUUID()) {
  return parseResponse(
    query(allocationCommandSql(actorId, operationId, aggregateId, revision, action, payload), action),
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

async function race(label, contenders, loserPattern) {
  const results = await Promise.all(contenders.map((entry) => concurrent(entry.sql, `${label}:${entry.name}`)));
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} requires one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, contenders.length - 1, `${label} requires explicit losers`);
  for (const loser of losers) assert.match(loser.stderr, loserPattern, `${label} loser is not stale/conflict`);
  const winningIndex = results.indexOf(winners[0]);
  return {
    loser: losers.map((entry) => entry.stderr.split("\n").at(-1)),
    operationId: contenders[winningIndex].operationId,
    response: parseResponse(winners[0].stdout, label),
    winner: contenders[winningIndex].name,
  };
}

function dropDatabase() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect concurrency database");
  if (exists !== "1") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close concurrency database");
  admin(
    `select pg_terminate_backend(pid) from pg_stat_activity where datname=${quote(databaseName)} and pid<>pg_backend_pid()`,
    "terminate concurrency clients",
  );
  admin(`drop database ${databaseName}`, "drop concurrency database");
}

function currentRevision(table, id) {
  return Number(query(`select revision from public.${table} where id=${quote(id)}::uuid`, `read ${table} revision`));
}

function createOfferedSeries(label) {
  const created = command(bookingManager, null, 0, "recurring_series.create", {
    bufferMinutes: 5,
    competitionId,
    durationMinutes: 70,
    endDate: "2027-06-28",
    frequency: "WEEKLY",
    localStartTime: "20:00",
    modality: "F7",
    pitchId: pitchAlpha,
    purpose: "COMPETITION_RECURRING_BLOCK",
    startDate: "2027-05-17",
    timezone: "Europe/Madrid",
    weekday: 1,
  });
  const validated = command(bookingManager, created.aggregateId, created.confirmedRevision, "recurring_series.validate", {}, randomUUID());
  const offered = command(bookingManager, created.aggregateId, validated.confirmedRevision, "recurring_series.offer", { reasonCode: label }, randomUUID());
  return { id: created.aggregateId, revision: offered.confirmedRevision };
}

const evidence = [];
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
  ], "bootstrap Wave 9B concurrency database");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(), "-f", resolve(root, "tests/season-venue-allocation-v1-fixture.sql"),
  ], "load Wave 9B concurrency fixture");
  query(`
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    grant execute on function auth.jwt() to authenticated, anon;
    begin;
    ${claimsSql(platformOwner)}
    select public.set_pachanga_venue_flags_v1(
      '${randomUUID()}', 1,
      '{"venueFoundationEnabled":true,"venueManagementEnabled":true,"venueAvailabilityEnabled":true,"venueReservationRequestsEnabled":true,"venueReservationHoldsEnabled":true,"venueCanonicalReservationsEnabled":true,"venueMatchBindingEnabled":true,"venueR4dIntegrationEnabled":true,"venueRecurringSeriesEnabled":true,"venueRecurringMaterializationEnabled":true,"competitionVenuePoolEnabled":true,"competitionVenueAllocationFoundationEnabled":true,"competitionVenueAllocationAutomaticEnabled":true,"competitionVenueAllocationManualEnabled":true,"competitionVenueAllocationHybridEnabled":true,"competitionVenueAllocationHoldsEnabled":true,"competitionVenueAllocationPublishEnabled":true}',
      '{"clientVersion":"9.2.0+wave9b-concurrency","surface":"wave9b_concurrency"}'
    );
    commit;
  `, "activate disposable Wave 9B flags");

  const firstSeries = createOfferedSeries("RACE_SERIES_A");
  const secondSeries = createOfferedSeries("RACE_SERIES_B");
  const firstAcceptOperation = randomUUID();
  const secondAcceptOperation = randomUUID();
  const recurringAcceptance = await race("overlapping recurring acceptance", [
    { name: "series-a", operationId: firstAcceptOperation, sql: allocationCommandSql(competitionDirector, firstAcceptOperation, firstSeries.id, firstSeries.revision, "recurring_series.accept") },
    { name: "series-b", operationId: secondAcceptOperation, sql: allocationCommandSql(competitionDirector, secondAcceptOperation, secondSeries.id, secondSeries.revision, "recurring_series.accept") },
  ], /VENUE_RECURRING_SERIES_CONFLICT|VENUE_ALLOCATION_STALE_REVISION/);
  evidence.push({ race: "overlapping_recurring_acceptance", ...recurringAcceptance });
  assert.equal(query("select count(*) from public.pachanga_venue_recurring_series where status='accepted'", "count accepted recurring series"), "1");
  const acceptedSeriesId = query("select id from public.pachanga_venue_recurring_series where status='accepted'", "select accepted series");
  const published = command(
    bookingManager,
    acceptedSeriesId,
    currentRevision("pachanga_venue_recurring_series", acceptedSeriesId),
    "recurring_series.publish",
  );

  const materializeOperation = randomUUID();
  const updateOperation = randomUUID();
  const materializeUpdate = await race("materialize versus update", [
    { name: "materialize", operationId: materializeOperation, sql: allocationCommandSql(bookingManager, materializeOperation, acceptedSeriesId, published.confirmedRevision, "recurring_series.materialize") },
    { name: "update", operationId: updateOperation, sql: allocationCommandSql(bookingManager, updateOperation, acceptedSeriesId, published.confirmedRevision, "recurring_series.update", { bufferMinutes: 6 }) },
  ], /VENUE_ALLOCATION_STALE_REVISION/);
  evidence.push({ race: "materialize_vs_update", ...materializeUpdate });
  if (query(`select count(*) from public.pachanga_venue_recurring_occurrences where series_id=${quote(acceptedSeriesId)}::uuid`, "count materialized occurrences") === "0") {
    command(
      bookingManager,
      acceptedSeriesId,
      currentRevision("pachanga_venue_recurring_series", acceptedSeriesId),
      "recurring_series.materialize",
    );
  }
  assert.equal(query(`select count(*) from public.pachanga_venue_recurring_occurrences where series_id=${quote(acceptedSeriesId)}::uuid`, "verify occurrence count"), "7");

  const pool = command(competitionDirector, null, 0, "venue_pool.create", {
    competitionId,
    editionId,
    name: "Wave 9B concurrency pool",
    visibility: "competition_staff",
  });
  const offeredPool = command(bookingManager, pool.aggregateId, pool.confirmedRevision, "venue_pool.offer", {
    allowedWeekdays: [1],
    pitchIds: [pitchAlpha, pitchBeta],
    capacityPerSlot: 1,
    localEndTime: "23:00",
    localStartTime: "17:00",
    modalities: ["F7"],
    ownerClubId,
    priority: 10,
    recurringSeriesId: acceptedSeriesId,
    sourceKind: "RECURRING_SERIES",
    validFrom: "2027-01-01",
    validUntil: "2027-12-31",
    venueId,
    visibility: "competition_staff",
  });
  const authorizationId = query(`select id from public.pachanga_competition_venue_authorizations where pool_id=${quote(pool.aggregateId)}::uuid`, "select pool authorization");
  command(competitionDirector, authorizationId, 1, "venue_pool.accept");
  command(competitionDirector, pool.aggregateId, offeredPool.confirmedRevision, "venue_pool.activate");

  const plan = command(competitionDirector, null, 0, "allocation_plan.create", {
    competitionId,
    editionId,
    mode: "HYBRID",
    ruleRevisionId,
    schedulePlanId,
    scheduleRevisionId,
    stageId,
    venuePoolId: pool.aggregateId,
    venueRequired: true,
  });
  const frozen = command(competitionDirector, plan.aggregateId, plan.confirmedRevision, "allocation_inputs.freeze");
  const firstGenerateOperation = randomUUID();
  const secondGenerateOperation = randomUUID();
  const generationRace = await race("two generations", [
    { name: "generator-a", operationId: firstGenerateOperation, sql: allocationCommandSql(competitionDirector, firstGenerateOperation, plan.aggregateId, frozen.confirmedRevision, "allocation.generate", { searchBudget: 100, seed: "wave9b-concurrency" }) },
    { name: "generator-b", operationId: secondGenerateOperation, sql: allocationCommandSql(competitionDirector, secondGenerateOperation, plan.aggregateId, frozen.confirmedRevision, "allocation.generate", { searchBudget: 100, seed: "wave9b-concurrency" }) },
  ], /VENUE_ALLOCATION_STALE_REVISION/);
  evidence.push({ race: "two_generations", ...generationRace });
  assert.equal(query(`select count(*) from public.pachanga_competition_venue_allocation_revisions where allocation_plan_id=${quote(plan.aggregateId)}::uuid`, "count generated revisions"), "1");

  const assignmentRevision = currentRevision("pachanga_competition_venue_allocation_plans", plan.aggregateId);
  const firstAssignOperation = randomUUID();
  const secondAssignOperation = randomUUID();
  const assignmentRace = await race("two manual assignments", [
    { name: "pitch-alpha", operationId: firstAssignOperation, sql: allocationCommandSql(competitionDirector, firstAssignOperation, plan.aggregateId, assignmentRevision, "allocation.item.assign", { canonicalMatchId, pitchId: pitchAlpha }) },
    { name: "pitch-beta", operationId: secondAssignOperation, sql: allocationCommandSql(competitionDirector, secondAssignOperation, plan.aggregateId, assignmentRevision, "allocation.item.assign", { canonicalMatchId, pitchId: pitchBeta }) },
  ], /VENUE_ALLOCATION_STALE_REVISION/);
  evidence.push({ race: "two_manual_assignments", ...assignmentRace });

  const holdRevision = currentRevision("pachanga_competition_venue_allocation_plans", plan.aggregateId);
  const firstHoldOperation = randomUUID();
  const secondHoldOperation = randomUUID();
  const holdRace = await race("two bulk holds", [
    { name: "hold-a", operationId: firstHoldOperation, sql: allocationCommandSql(competitionDirector, firstHoldOperation, plan.aggregateId, holdRevision, "allocation.hold", { expiresInMinutes: 60 }) },
    { name: "hold-b", operationId: secondHoldOperation, sql: allocationCommandSql(competitionDirector, secondHoldOperation, plan.aggregateId, holdRevision, "allocation.hold", { expiresInMinutes: 60 }) },
  ], /VENUE_ALLOCATION_STALE_REVISION|VENUE_ALLOCATION_ACTIVE_HOLDS_EXIST/);
  evidence.push({ race: "two_bulk_holds", ...holdRace });
  assert.equal(query("select count(*) from public.pachanga_competition_venue_allocation_holds where status='active'", "count active allocation holds"), "1");

  const validated = command(
    competitionDirector,
    plan.aggregateId,
    currentRevision("pachanga_competition_venue_allocation_plans", plan.aggregateId),
    "allocation.validate",
  );
  assert.equal(validated.snapshot.result.status, "VALID");
  const firstPublishOperation = randomUUID();
  const secondPublishOperation = randomUUID();
  const publishRace = await race("two publishes", [
    { name: "publish-a", operationId: firstPublishOperation, sql: allocationCommandSql(competitionDirector, firstPublishOperation, plan.aggregateId, validated.confirmedRevision, "allocation.publish") },
    { name: "publish-b", operationId: secondPublishOperation, sql: allocationCommandSql(competitionDirector, secondPublishOperation, plan.aggregateId, validated.confirmedRevision, "allocation.publish") },
  ], /VENUE_ALLOCATION_STALE_REVISION|VENUE_ALLOCATION_PUBLISH_TRANSITION_INVALID/);
  evidence.push({ race: "two_publishes", ...publishRace });
  assert.equal(query(`select count(*) from public.pachanga_venue_reservations where competition_id=${quote(competitionId)}::uuid and status='CONFIRMED'`, "count canonical reservations"), "1");
  assert.equal(query(`select count(*) from public.pachanga_venue_match_bindings where canonical_match_id=${quote(canonicalMatchId)}::uuid and status='ACTIVE'`, "count canonical bindings"), "1");
  const replay = parseResponse(
    query(allocationCommandSql(competitionDirector, publishRace.operationId, plan.aggregateId, validated.confirmedRevision, "allocation.publish"), "replay winning publication"),
    "publication replay",
  );
  assert.deepEqual(replay, publishRace.response);
} finally {
  try {
    dropDatabase();
    rmSync(infrastructureDump, { force: true });
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
process.stdout.write(`${JSON.stringify({
  cleanup: "PASS",
  database: "ephemeral-local",
  races: evidence,
  result: "SEASON_VENUE_ALLOCATION_V1_CONCURRENCY_PASS",
})}\n`);
