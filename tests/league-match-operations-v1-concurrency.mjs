import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_MATCH_OPERATIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4c_concurrency_${suffix}`;
const scorerRaceDatabaseName = `pachangas_r4c_scorer_race_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4c-concurrency-${suffix}.sql`);
let scorerRaceDatabaseCreated = false;

if (!adminUrl) throw new Error("LEAGUE_MATCH_OPERATIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4C_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);

function targetUrl(targetDatabaseName = databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${targetDatabaseName}`;
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

function query(sql, label = "query R4C concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function commandSql(actorId, operationId, aggregateId, revision, action, payload = {}) {
  return `
    begin;
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_league_match_operations_v1(
      ${quote(operationId)}::uuid,
      ${quote(aggregateId)}::uuid,
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"4.0.0+r4c-concurrency","serviceWorkerVersion":"sw-r4c-concurrency","installedMode":"standalone","surface":"r4c_concurrency"}'::jsonb
    );
    commit;
  `;
}

function command(actorId, aggregateId, revision, action, payload = {}) {
  const output = query(commandSql(actorId, randomUUID(), aggregateId, revision, action, payload), action);
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${action} returned no response`);
  return JSON.parse(line);
}

function concurrent(sql, label, targetDatabaseName = databaseName) {
  return new Promise((resolveResult) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(targetDatabaseName)], {
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

async function raceSame(actorId, aggregateId, revision, action, payload) {
  return Promise.all([
    concurrent(commandSql(actorId, randomUUID(), aggregateId, revision, action, payload), `${action}:a`),
    concurrent(commandSql(actorId, randomUUID(), aggregateId, revision, action, payload), `${action}:b`),
  ]);
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have one loser`);
  assert.match(losers[0].stderr, /STALE_REVISION|R4C_.+_(?:EXISTS|EDITABLE|PENDING|COMPLETED)|PT409/);
}

function revision(table, id) {
  return Number(query(`select revision from ${table} where id=${quote(id)}::uuid`));
}

function dropDatabase(targetDatabaseName) {
  admin(`alter database ${targetDatabaseName} with allow_connections false`, `close ${targetDatabaseName}`);
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(targetDatabaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${targetDatabaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(targetDatabaseName)}`, `inspect ${targetDatabaseName}`));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4C_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${targetDatabaseName}:${connections}`);
  }
  admin(`drop database if exists ${targetDatabaseName}`, `drop ${targetDatabaseName}`);
}

const contextId = "c4400000-0000-4000-8000-000000000008";
const roundId = "c4400000-0000-4000-8000-000000000003";
const homeEntry = "c4200000-0000-4000-8000-000000000011";
const awayEntry = "c4200000-0000-4000-8000-000000000012";
const director = "c4010000-0000-4000-8000-000000000002";
const homeOwner = "c4010000-0000-4000-8000-000000000003";
const awayOwner = "c4010000-0000-4000-8000-000000000004";

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create concurrency DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore concurrency infrastructure");
  query("create publication supabase_realtime;", "create concurrency publication");
  apply([resolve(root, manifest.baselinePath), ...migrations.map((name) => resolve(root, "supabase/migrations", name))], "bootstrap concurrency DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", resolve(root, "tests/league-match-operations-v1-fixture.sql")], "load R4C concurrency fixture");
  query(`update private.pachanga_competition_foundation_settings set
    foundation_enabled=true, creation_enabled=true, context_binding_enabled=true,
    league_participation_foundation_enabled=true, league_registration_enabled=true,
    league_delegates_enabled=true, league_rosters_enabled=true,
    league_schedule_preferences_enabled=true, league_scheduling_foundation_enabled=true,
    league_schedule_generation_enabled=true, league_schedule_editing_enabled=true,
    league_schedule_publication_enabled=true, league_public_calendar_enabled=true,
    league_canonical_fixture_creation_enabled=true,
    league_match_operations_foundation_enabled=true, league_match_squads_enabled=true,
    league_match_attendance_enabled=true, league_sporting_results_enabled=true,
    league_result_confirmation_enabled=true, league_official_results_enabled=true,
    league_standings_enabled=true, league_public_standings_enabled=true
    where singleton`, "enable disposable R4C flags");

  let currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const createRace = await raceSame(homeOwner, contextId, currentRevision, "squad.create", { entryId: homeEntry });
  assertOneWinner(createRace, "squad create race");
  const homeSquad = query(`select id from public.pachanga_competition_match_squads where competition_match_context_id=${quote(contextId)}::uuid and side='HOME'`);
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(homeOwner, contextId, currentRevision, "squad.member.add", { squadId: homeSquad, rosterMemberId: "c4200000-0000-4000-8000-000000000019", memberRole: "STARTER", shirtNumber: 9, positionOrder: 1, isCaptain: true });
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const submitRace = await raceSame(homeOwner, contextId, currentRevision, "squad.submit", { squadId: homeSquad });
  assertOneWinner(submitRace, "squad submit race");
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(director, contextId, currentRevision, "squad.validate", { squadId: homeSquad });
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const lockEditRace = await Promise.all([
    concurrent(commandSql(director, randomUUID(), contextId, currentRevision, "squad.lock", { squadId: homeSquad }), "squad:lock"),
    concurrent(commandSql(homeOwner, randomUUID(), contextId, currentRevision, "squad.member.add", {
      squadId: homeSquad,
      rosterMemberId: "c4200000-0000-4000-8000-000000000019",
      memberRole: "STARTER",
      shirtNumber: 9,
      positionOrder: 1,
    }), "squad:edit"),
  ]);
  assertOneWinner(lockEditRace, "squad lock vs edit race");

  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(awayOwner, contextId, currentRevision, "squad.create", { entryId: awayEntry });
  const awaySquad = query(`select id from public.pachanga_competition_match_squads where competition_match_context_id=${quote(contextId)}::uuid and side='AWAY'`);
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(awayOwner, contextId, currentRevision, "squad.member.add", { squadId: awaySquad, rosterMemberId: "c4200000-0000-4000-8000-000000000020", memberRole: "STARTER", shirtNumber: 10, positionOrder: 1, isCaptain: true });
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(awayOwner, contextId, currentRevision, "squad.submit", { squadId: awaySquad });
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(director, contextId, currentRevision, "squad.validate", { squadId: awaySquad });
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  command(director, contextId, currentRevision, "squad.lock", { squadId: awaySquad });

  for (const [actorId, entryId, memberId] of [
    ["c4010000-0000-4000-8000-000000000005", homeEntry, "c4200000-0000-4000-8000-000000000019"],
    ["c4010000-0000-4000-8000-000000000006", awayEntry, "c4200000-0000-4000-8000-000000000020"],
  ]) {
    currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
    command(actorId, contextId, currentRevision, "attendance.set", { entryId, rosterMemberId: memberId, status: "going" });
  }
  for (const [actorId, entryId] of [[homeOwner, homeEntry], [awayOwner, awayEntry]]) {
    currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
    command(actorId, contextId, currentRevision, "attendance.close", { entryId });
  }
  for (const action of ["match.mark_ready", "match.start", "match.mark_played"]) {
    currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
    command(director, contextId, currentRevision, action);
  }

  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const resultRace = await raceSame(homeOwner, contextId, currentRevision, "sporting_result.submit", {
    entryId: homeEntry, scoreHome: 3, scoreAway: 2,
    scorers: [{ rosterMemberId: "c4200000-0000-4000-8000-000000000019", goals: 3 }],
  });
  assertOneWinner(resultRace, "result submission race");

  admin(`create database ${scorerRaceDatabaseName} template ${databaseName}`, "clone pending result for scorer race");
  scorerRaceDatabaseCreated = true;
  const scorerRaceRevision = Number(run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(scorerRaceDatabaseName), "-c",
      `select revision from public.pachanga_competition_match_contexts where id=${quote(contextId)}::uuid`],
    "read scorer race revision",
  ));
  const officializeScorerRace = await Promise.all([
    concurrent(commandSql(awayOwner, randomUUID(), contextId, scorerRaceRevision, "sporting_result.accept", {
      entryId: awayEntry,
      scorers: [{ rosterMemberId: "c4200000-0000-4000-8000-000000000020", goals: 2 }],
    }), "result:auto-officialize", scorerRaceDatabaseName),
    concurrent(commandSql(awayOwner, randomUUID(), contextId, scorerRaceRevision, "sporting_result.propose_change", {
      entryId: awayEntry,
      scoreHome: 3,
      scoreAway: 2,
      reason: "Correct scorer attribution before confirmation",
      scorers: [{ rosterMemberId: "c4200000-0000-4000-8000-000000000020", goals: 1 }],
    }), "result:scorer-correction", scorerRaceDatabaseName),
  ]);
  assertOneWinner(officializeScorerRace, "officialize vs scorer correction race");
  const scorerRaceState = run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(scorerRaceDatabaseName), "-c",
      `select jsonb_build_object(
        'contextStatus', contexts.status,
        'resultState', results.state,
        'activeDecisions', (select count(*) from public.pachanga_competition_official_result_decisions decisions where decisions.competition_match_context_id=contexts.id)
      )::text
      from public.pachanga_competition_match_contexts contexts
      join public.pachanga_competition_sporting_results results on results.competition_match_context_id=contexts.id
      where contexts.id=${quote(contextId)}::uuid`],
    "read scorer race result",
  );
  const scorerRaceSnapshot = JSON.parse(scorerRaceState);
  assert.ok(
    (scorerRaceSnapshot.contextStatus === "official" && scorerRaceSnapshot.resultState === "official" && scorerRaceSnapshot.activeDecisions === 1)
      || (scorerRaceSnapshot.contextStatus === "result_pending" && scorerRaceSnapshot.resultState === "change_proposed" && scorerRaceSnapshot.activeDecisions === 0),
    `Scorer race did not converge canonically: ${scorerRaceState}`,
  );

  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const responseRace = await Promise.all([
    concurrent(commandSql(awayOwner, randomUUID(), contextId, currentRevision, "sporting_result.accept", {
      entryId: awayEntry,
      scorers: [{ rosterMemberId: "c4200000-0000-4000-8000-000000000020", goals: 2 }],
    }), "result:accept"),
    concurrent(commandSql(awayOwner, randomUUID(), contextId, currentRevision, "sporting_result.dispute", {
      entryId: awayEntry, scoreHome: 3, scoreAway: 3, reason: "Concurrent dispute",
    }), "result:dispute"),
  ]);
  assertOneWinner(responseRace, "accept vs dispute race");
  const resultState = query(`select state from public.pachanga_competition_sporting_results where competition_match_context_id=${quote(contextId)}::uuid`);
  if (resultState === "disputed") {
    currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
    command(director, contextId, currentRevision, "official_result.publish", {
      outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 3, scoreAway: 2,
      reasonCode: "concurrency.dispute_resolved", publicExplanation: "Resolución QA.",
    });
  }

  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const officialRace = await raceSame(director, contextId, currentRevision, "official_result.supersede", {
    outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 2, scoreAway: 2,
    reasonCode: "concurrency.official_decision", publicExplanation: "Corrección concurrente.",
  });
  assertOneWinner(officialRace, "official decision race");

  const standingRevision = Number(query("select revision from public.pachanga_competition_standing_states limit 1"));
  const rebuildRace = await raceSame(director, contextId, standingRevision, "standings.rebuild", { rebuildKind: "FULL_AUDIT" });
  assertOneWinner(rebuildRace, "standings rebuild race");

  let roundRevision = revision("public.pachanga_competition_rounds", roundId);
  command(director, roundId, roundRevision, "round.complete");
  roundRevision = revision("public.pachanga_competition_rounds", roundId);
  currentRevision = revision("public.pachanga_competition_match_contexts", contextId);
  const lockCorrectionRace = await Promise.all([
    concurrent(commandSql(director, randomUUID(), roundId, roundRevision, "round.lock", {}), "round:lock"),
    concurrent(commandSql(director, randomUUID(), contextId, currentRevision, "official_result.supersede", {
      outcome: "CORRECTED_EFFECTIVE_SCORE", scoreHome: 3, scoreAway: 2,
      reasonCode: "concurrency.post_lock_correction", publicExplanation: "Corrección auditada.",
    }), "result:correction"),
  ]);
  assertOneWinner(lockCorrectionRace, "round lock vs result correction race");

  const finalState = JSON.parse(query(`select jsonb_build_object(
    'activeDecisions', (select count(*) from public.pachanga_competition_match_sheets where active_official_decision_id is not null),
    'contexts', (select count(*) from public.pachanga_competition_match_contexts where canonical_match_id='c4400000-0000-4000-8000-000000000006'),
    'receipts', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type='league_match_operations'),
    'standingStates', (select count(*) from public.pachanga_competition_standing_states),
    'roundStatus', (select status from public.pachanga_competition_rounds where id=${quote(roundId)}::uuid)
  )::text`));
  assert.equal(finalState.activeDecisions, 1);
  assert.equal(finalState.contexts, 1);
  assert.equal(finalState.standingStates, 1);
  process.stdout.write(`${JSON.stringify({
    squadCreate: "1 winner / 1 conflict",
    squadSubmit: "1 winner / 1 stale",
    squadLockVsEdit: "1 winner / 1 conflict",
    resultSubmit: "1 winner / 1 stale",
    acceptVsDispute: "1 winner / 1 stale",
    officializeVsScorerCorrection: "1 winner / 1 stale",
    officialDecision: "1 winner / 1 stale",
    standingsRebuild: "1 winner / 1 stale",
    roundLockVsCorrection: "1 winner / 1 stale",
    finalState,
  })}\n`);
} finally {
  if (scorerRaceDatabaseCreated) dropDatabase(scorerRaceDatabaseName);
  dropDatabase(databaseName);
  rmSync(infrastructureDump, { force: true });
}
