import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.COMPETITION_DISCIPLINE_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_r5_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r5-concurrency-${suffix}.sql`);
const caseDatabases = new Set();

const competitionId = "c4200000-0000-4000-8000-000000000001";
const director = "c4010000-0000-4000-8000-000000000002";
const playerUser = "c4010000-0000-4000-8000-000000000005";
const playerId = "c4300000-0000-4000-8000-000000000001";
const alternateId = "c4300000-0000-4000-8000-000000000003";
const matches = [
  "c4400000-0000-4000-8000-000000000006",
  "c4500000-0000-4000-8000-000000000006",
  "c4600000-0000-4000-8000-000000000006",
  "c4700000-0000-4000-8000-000000000006",
];
const j4ContextId = "c4700000-0000-4000-8000-000000000008";
const j4SquadId = "c4800000-0000-4000-8000-000000000014";

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R5_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

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

function query(databaseName, sql, label = "query R5 concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], label);
}

function disciplineRevision(databaseName) {
  return Number(query(databaseName, `select discipline_revision from public.pachanga_competitions where id=${quote(competitionId)}::uuid`));
}

function matchRevision(databaseName, contextId = j4ContextId) {
  return Number(query(databaseName, `select revision from public.pachanga_competition_match_contexts where id=${quote(contextId)}::uuid`));
}

function r5CommandSql(actorId, operationId, aggregateId, revision, action, payload = {}) {
  return `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_competition_discipline_v1(
      ${quote(operationId)}::uuid, ${quote(competitionId)}::uuid,
      ${quote(aggregateId)}::uuid, ${revision}, ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"5.0.0+r5-concurrency","serviceWorkerVersion":"sw-r5-concurrency","installedMode":"standalone","surface":"r5_concurrency"}'::jsonb
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
      ${quote(operationId)}::uuid, ${quote(j4ContextId)}::uuid, ${revision},
      ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"5.0.0+r5-concurrency","serviceWorkerVersion":"sw-r5-concurrency","installedMode":"standalone","surface":"r5_lineup_race"}'::jsonb
    );
    commit;
  `;
}

function command(databaseName, actorId, aggregateId, action, payload = {}) {
  const output = query(databaseName, r5CommandSql(
    actorId, randomUUID(), aggregateId, disciplineRevision(databaseName), action, payload,
  ), `R5 ${action}`);
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

async function raceR5(databaseName, left, right) {
  const revision = disciplineRevision(databaseName);
  return Promise.all([
    concurrent(databaseName, r5CommandSql(left.actor ?? director, randomUUID(), left.aggregateId, revision, left.action, left.payload), left.action),
    concurrent(databaseName, r5CommandSql(right.actor ?? director, randomUUID(), right.aggregateId, revision, right.action, right.payload), right.action),
  ]);
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one canonical winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one explicit loser`);
  assert.match(losers[0].stderr, /STALE_REVISION|DISCIPLINE_.+CONFLICT|DISCIPLINARY_INELIGIBLE|PT409/);
}

function cloneCase(label) {
  const databaseName = `pachangas_r5_${label.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase()}_${suffix}`;
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
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(databaseName)}`, `inspect ${databaseName}`));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R5_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${databaseName}:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function recordCard(databaseName, matchId, cardTypeCode = "YELLOW", minute = 12) {
  return command(databaseName, director, matchId, "event.record", {
    cardTypeCode,
    context: "in_match",
    minute,
    playerProfileId: playerId,
    publicReasonCategory: cardTypeCode === "YELLOW" ? "accumulation" : "dismissal",
    publicSummary: `${cardTypeCode} concurrency setup`,
  });
}

function prepareThreshold(databaseName) {
  const responses = [
    recordCard(databaseName, matches[0], "YELLOW", 11),
    recordCard(databaseName, matches[1], "YELLOW", 22),
    recordCard(databaseName, matches[2], "YELLOW", 33),
  ];
  const sanctionId = query(databaseName, `select id from public.pachanga_competition_sanctions where player_profile_id=${quote(playerId)}::uuid and status='active'`);
  const eventId = query(databaseName, `select id from public.pachanga_competition_disciplinary_events where canonical_match_id=${quote(matches[2])}::uuid`);
  return { eventId, responses, sanctionId };
}

function preparePlayableJ4(databaseName) {
  query(databaseName, `
    insert into public.pachanga_competition_match_squad_revisions(
      id, squad_id, version, squad_status, roster_revision_id, rule_revision_id,
      member_count, starter_count, substitute_count, captain_player_profile_id,
      member_set_checksum, lineup_checksum, reason, created_by
    ) values (
      'd5900000-0000-4000-8000-000000000024', ${quote(j4SquadId)}::uuid, 2, 'submitted',
      'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003',
      1, 1, 0, ${quote(alternateId)}::uuid, repeat('5', 64), repeat('e', 64),
      'R5 concurrency eligible replacement', ${quote(director)}::uuid
    );
    insert into public.pachanga_competition_match_squad_members(
      id, squad_revision_id, roster_member_id, player_profile_id, member_role,
      shirt_number, position_order, is_captain, public_snapshot
    ) values (
      'd5a00000-0000-4000-8000-000000000024',
      'd5900000-0000-4000-8000-000000000024',
      'c4200000-0000-4000-8000-000000000021', ${quote(alternateId)}::uuid,
      'STARTER', 4, 1, true, '{"displayName":"Home alternate"}'
    );
    update public.pachanga_competition_match_squads set
      current_revision_id='d5900000-0000-4000-8000-000000000024', revision=2
    where id=${quote(j4SquadId)}::uuid;
    update public.pachanga_competition_match_squads set status='locked'
    where id=${quote(j4SquadId)}::uuid;
    update public.pachanga_competition_match_contexts set status='played'
    where id=${quote(j4ContextId)}::uuid;
  `, "prepare eligible played J4");
}

function prepareCommitteeSanction(databaseName) {
  recordCard(databaseName, matches[2], "RED", 64);
  return query(databaseName, `select id from public.pachanga_competition_sanctions where player_profile_id=${quote(playerId)}::uuid and status='provisional'`);
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create R5 concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump], "restore concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create concurrency publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R5 concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", resolve(root, "tests/competition-discipline-v1-fixture.sql")], "load R5 concurrency fixture");

  const summaries = {};
  let databaseName = cloneCase("two_cards");
  let startRevision = disciplineRevision(databaseName);
  let results = await raceR5(databaseName,
    { action: "event.record", aggregateId: matches[0], payload: { playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 14 } },
    { action: "event.record", aggregateId: matches[0], payload: { playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 15 } });
  assertOneWinner(results, "two simultaneous cards");
  assert.equal(Number(query(databaseName, "select count(*) from public.pachanga_competition_disciplinary_events")), 1);
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.twoCards = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("card_vs_correction");
  recordCard(databaseName, matches[0]);
  const firstEventId = query(databaseName, "select id from public.pachanga_competition_disciplinary_events limit 1");
  startRevision = disciplineRevision(databaseName);
  results = await raceR5(databaseName,
    { action: "event.record", aggregateId: matches[1], payload: { playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 21 } },
    { action: "event.correct", aggregateId: firstEventId, payload: { cardTypeCode: "BLUE", context: "in_match", minute: 12, correctionReason: "Concurrent official correction." } });
  assertOneWinner(results, "card versus correction");
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.cardVsCorrection = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("rebuild_vs_event");
  recordCard(databaseName, matches[0]);
  const cycleId = query(databaseName, "select cycle_id from public.pachanga_competition_disciplinary_events limit 1");
  startRevision = disciplineRevision(databaseName);
  results = await raceR5(databaseName,
    { action: "counter.rebuild", aggregateId: cycleId, payload: { playerProfileId: playerId } },
    { action: "event.record", aggregateId: matches[1], payload: { playerProfileId: playerId, cardTypeCode: "YELLOW", context: "in_match", minute: 24 } });
  assertOneWinner(results, "counter rebuild versus new event");
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.rebuildVsEvent = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("two_decisions");
  const decisionSanctionId = prepareCommitteeSanction(databaseName);
  startRevision = disciplineRevision(databaseName);
  results = await raceR5(databaseName,
    { action: "sanction.decide", aggregateId: decisionSanctionId, payload: { decisionOutcome: "FIXED_SANCTION", units: 2, privateReason: "Concurrent committee decision A." } },
    { action: "sanction.decide", aggregateId: decisionSanctionId, payload: { decisionOutcome: "NO_SANCTION", privateReason: "Concurrent committee decision B." } });
  assertOneWinner(results, "two sanction decisions");
  assert.equal(Number(query(databaseName, `select revision from public.pachanga_competition_sanctions where id=${quote(decisionSanctionId)}::uuid`)), 2);
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.twoDecisions = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("appeal_vs_service");
  let threshold = prepareThreshold(databaseName);
  preparePlayableJ4(databaseName);
  startRevision = disciplineRevision(databaseName);
  results = await raceR5(databaseName,
    { actor: playerUser, action: "appeal.submit", aggregateId: threshold.sanctionId, payload: { statement: "Concurrent appeal before service." } },
    { action: "service.record", aggregateId: threshold.sanctionId, payload: {} });
  assertOneWinner(results, "appeal versus service");
  assert.equal(Number(query(databaseName, "select (select count(*) from public.pachanga_competition_sanction_appeals) + (select count(*) from public.pachanga_competition_sanction_service_events)")), 1);
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.appealVsService = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("service_vs_correction");
  threshold = prepareThreshold(databaseName);
  preparePlayableJ4(databaseName);
  startRevision = disciplineRevision(databaseName);
  results = await raceR5(databaseName,
    { action: "service.record", aggregateId: threshold.sanctionId, payload: {} },
    { action: "event.correct", aggregateId: threshold.eventId, payload: { cardTypeCode: "BLUE", context: "in_match", minute: 33, correctionReason: "Concurrent source correction." } });
  assertOneWinner(results, "service versus correction");
  assert.equal(disciplineRevision(databaseName), startRevision + 1);
  summaries.serviceVsCorrection = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("lineup_vs_activation");
  const lineupSanctionId = prepareCommitteeSanction(databaseName);
  query(databaseName, `
    update public.pachanga_competition_sanctions set status='under_review'
    where id=${quote(lineupSanctionId)}::uuid;
    update public.pachanga_competition_match_squads set status='validated'
    where id=${quote(j4SquadId)}::uuid;
  `, "prepare lineup activation race");
  const r5Revision = disciplineRevision(databaseName);
  const r4cRevision = matchRevision(databaseName);
  results = await Promise.all([
    concurrent(databaseName, r4cCommandSql(director, randomUUID(), r4cRevision, "squad.lock", { squadId: j4SquadId }), "squad.lock"),
    concurrent(databaseName, r5CommandSql(director, randomUUID(), lineupSanctionId, r5Revision, "sanction.decide", { decisionOutcome: "FIXED_SANCTION", units: 2, privateReason: "Concurrent activation decision." }), "sanction.decide"),
  ]);
  assertOneWinner(results, "lineup lock versus sanction activation");
  const lineupStatus = query(databaseName, `select status from public.pachanga_competition_match_squads where id=${quote(j4SquadId)}::uuid`);
  const sanctionStatus = query(databaseName, `select status from public.pachanga_competition_sanctions where id=${quote(lineupSanctionId)}::uuid`);
  assert.equal((lineupStatus === "locked") !== (sanctionStatus === "active"), true);
  summaries.lineupVsActivation = "1 winner / 1 conflict";
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({ database: "temporary clones", races: summaries })}\n`);
} finally {
  for (const databaseName of [...caseDatabases]) dropDatabase(databaseName);
  dropDatabase(templateDatabase);
  rmSync(infrastructureDump, { force: true });
}
