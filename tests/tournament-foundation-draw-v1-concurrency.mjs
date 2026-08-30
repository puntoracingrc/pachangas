import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.TOURNAMENT_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_r6a_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r6a-concurrency-${suffix}.sql`);
const caseDatabases = new Set();
const ownerId = "63010000-0000-4000-8000-000000000001";

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R6A_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort()
  .filter((name) => name <= "20260826195040_tournament_draw_hardening_indexes_flags_v1.sql")
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
assert.equal(migrations.length + manifest.absorbedMigrations.length, 163);

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
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(databaseName, sql, label = "query R6A concurrency database") {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], label);
}

function fixtureContext(databaseName) {
  const value = query(databaseName, `
    select jsonb_build_object(
      'competitionId', competitions.id,
      'planId', plans.id,
      'revision', competitions.tournament_revision,
      'constraintId', (
        select constraints.id from public.pachanga_competition_draw_constraints constraints
        where constraints.draw_plan_id=plans.id and constraints.status='active'
        order by constraints.server_sequence, constraints.id limit 1
      ),
      'entries', (
        select jsonb_agg(jsonb_build_object(
          'entryId', entries.id,
          'ownerId', teams.owner_id,
          'groupNumber', placements.group_number,
          'slotNumber', placements.slot_number
        ) order by entries.team_id)
        from public.pachanga_competition_entries entries
        join public.pachanga_groups teams on teams.id=entries.team_id
        left join public.pachanga_competition_draw_placements placements
          on placements.entry_id=entries.id and placements.draw_revision_id=plans.current_revision_id
        where entries.competition_id=competitions.id and entries.status='accepted'
      )
    )::text
    from public.pachanga_competitions competitions
    join public.pachanga_competition_draw_plans plans on plans.competition_id=competitions.id
    where competitions.slug='r6a-concurrency-fixture';
  `);
  return JSON.parse(value);
}

function commandSql(actorId, operationId, competitionId, revision, action, payload = {}) {
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='60s';
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    select public.command_pachanga_tournament_draw_v1(
      ${quote(operationId)}::uuid,
      ${quote(competitionId)}::uuid,
      ${revision},
      ${quote(action)},
      ${quote(JSON.stringify(payload))}::jsonb,
      '{"clientVersion":"6.0.0+r6a-concurrency","serviceWorkerVersion":"r6a-concurrency","installedMode":"standalone","surface":"r6a_concurrency"}'::jsonb
    );
    commit;
  `;
}

function replacementSql(actorId, operationId, competitionId, revision, planId) {
  const secondOperationId = randomUUID();
  return `
    begin;
    set local lock_timeout='15s';
    set local statement_timeout='60s';
    set local role authenticated;
    select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
    do $replacement$
    declare unfreeze_response jsonb;
    begin
      unfreeze_response := public.command_pachanga_tournament_draw_v1(
        ${quote(operationId)}::uuid, ${quote(competitionId)}::uuid, ${revision},
        'participants.unfreeze', ${quote(JSON.stringify({ planId, reason: "R6A concurrent freeze replacement" }))}::jsonb,
        '{"clientVersion":"6.0.0+r6a-concurrency","surface":"r6a_concurrency"}'::jsonb
      );
      perform public.command_pachanga_tournament_draw_v1(
        ${quote(secondOperationId)}::uuid, ${quote(competitionId)}::uuid,
        (unfreeze_response ->> 'confirmedRevision')::bigint,
        'participants.freeze', ${quote(JSON.stringify({ planId, reason: "R6A concurrent freeze replacement" }))}::jsonb,
        '{"clientVersion":"6.0.0+r6a-concurrency","surface":"r6a_concurrency"}'::jsonb
      );
    end;
    $replacement$;
    commit;
  `;
}

function command(databaseName, actorId, action, payload = {}) {
  const context = fixtureContext(databaseName);
  const output = query(databaseName, commandSql(
    actorId,
    randomUUID(),
    context.competitionId,
    context.revision,
    action,
    payload,
  ), `prepare ${action}`);
  const responseLine = output.split("\n").filter(Boolean).at(-1);
  assert.ok(responseLine, `${action} returned no response`);
  return JSON.parse(responseLine);
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

function invariantSnapshot(databaseName) {
  return JSON.parse(query(databaseName, `
    select jsonb_build_object(
      'duplicateEntries', (
        select count(*) from (
          select placements.entry_id
          from public.pachanga_competition_draw_plans plans
          join public.pachanga_competition_draw_placements placements
            on placements.draw_revision_id=plans.current_revision_id
          join public.pachanga_competitions competitions on competitions.id=plans.competition_id
          where competitions.slug='r6a-concurrency-fixture'
          group by placements.entry_id having count(*)>1
        ) duplicates
      ),
      'duplicatePositions', (
        select count(*) from (
          select placements.group_number, placements.slot_number
          from public.pachanga_competition_draw_plans plans
          join public.pachanga_competition_draw_placements placements
            on placements.draw_revision_id=plans.current_revision_id
          join public.pachanga_competitions competitions on competitions.id=plans.competition_id
          where competitions.slug='r6a-concurrency-fixture'
          group by placements.group_number, placements.slot_number having count(*)>1
        ) duplicates
      ),
      'matches', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
        where competitions.slug='r6a-concurrency-fixture'
      )
    )::text;
  `));
}

async function race(databaseName, label, left, right) {
  const results = await Promise.all([
    concurrent(databaseName, left, `${label}:left`),
    concurrent(databaseName, right, `${label}:right`),
  ]);
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} must have exactly one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} must have exactly one stale/conflict loser`);
  assert.match(`${losers[0].stdout}\n${losers[0].stderr}`, /STALE_REVISION|PT409|DRAW_(?:INPUT_STALE|ALREADY_PUBLISHED|POSITION_OCCUPIED)/i, `${label} loser must be stale/conflict`);
  assert.deepEqual(invariantSnapshot(databaseName), { duplicateEntries: 0, duplicatePositions: 0, matches: 0 });
  return {
    label,
    loser: `${losers[0].stdout}\n${losers[0].stderr}`.match(/STALE_REVISION|PT409|DRAW_[A-Z_]+/i)?.[0] ?? "conflict",
    winner: winners[0].label,
  };
}

function cloneDatabase(label) {
  const normalized = label.replaceAll(/[^a-z0-9]+/g, "_").slice(0, 28);
  const name = `pachangas_r6a_${normalized}_${randomBytes(3).toString("hex")}`;
  admin(`create database ${name} template ${templateDatabase}`, `clone ${label}`);
  caseDatabases.add(name);
  return name;
}

function dropDatabase(name) {
  if (admin(`select count(*) from pg_database where datname=${quote(name)}`, `inspect ${name}`) === "0") return;
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  admin(`drop database if exists ${name}`, `drop ${name}`);
  caseDatabases.delete(name);
}

function payloads(context) {
  const [first, second, third, fourth] = context.entries;
  return {
    authoring: {
      name: "R6A Concurrency Fixture",
      slug: "r6a-concurrency-fixture",
      participantCap: 16,
      groupCount: 4,
      qualifiersPerGroup: 2,
      drawTarget: "GROUP_ASSIGNMENT",
      drawMode: "HYBRID",
      reason: "R6A concurrent RuleRevision update",
    },
    constraint: {
      planId: context.planId,
      constraintId: context.constraintId,
      strength: "HARD",
      weight: 100,
      scope: "DRAW",
      parameters: {},
      reason: "R6A concurrent constraint update",
      publicAttribution: true,
    },
    first,
    fourth,
    generate: {
      planId: context.planId,
      seedMode: "CUSTOM_PUBLIC_SEED",
      publicSeed: "R6A-CONCURRENT-SEED",
      reason: "R6A concurrent generation",
    },
    lock: {
      planId: context.planId,
      lockType: "ENTRY_TO_GROUP",
      entryId: second.entryId,
      groupNumber: second.groupNumber,
      slotNumber: second.slotNumber,
      reason: "R6A concurrent lock",
    },
    second,
    third,
  };
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create R6A concurrency template");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump], "restore R6A concurrency infrastructure");
  query(templateDatabase, "create publication supabase_realtime;", "create R6A concurrency Realtime publication");
  const applyArgs = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath)];
  for (const name of migrations) applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  run(psqlBin, applyArgs, "bootstrap R6A concurrency template");
  const fixtureOutput = run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(templateDatabase), "-f", resolve(root, "tests/tournament-foundation-draw-v1-fixture.sql")], "load R6A concurrency fixture");
  assert.match(fixtureOutput, /R6A_FIXTURE_OK/);

  const reports = [];

  {
    const db = cloneDatabase("two_generations");
    const context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "two generations",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.regenerate", p.generate),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.regenerate", p.generate)));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("generate_withdrawal");
    const context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "generate vs participant withdrawal",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.regenerate", p.generate),
      commandSql(p.fourth.ownerId, randomUUID(), context.competitionId, context.revision, "participant.withdraw", {
        entryId: p.fourth.entryId,
        reason: "R6A concurrent withdrawal",
      })));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("generate_constraint");
    const context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "generate vs constraint edit",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.regenerate", p.generate),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw_constraint.update", p.constraint)));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("move_regeneration");
    let context = fixtureContext(db);
    const empty = context.entries[0];
    command(db, ownerId, "draw.entry.remove", { planId: context.planId, entryId: empty.entryId, reason: "Prepare empty position" });
    context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "manual move vs regeneration",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.entry.move", {
        planId: context.planId,
        entryId: p.second.entryId,
        groupNumber: empty.groupNumber,
        slotNumber: empty.slotNumber,
        reason: "R6A concurrent manual move",
      }),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.regenerate", p.generate)));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("two_manual_moves");
    let context = fixtureContext(db);
    const firstEmpty = context.entries[0];
    const secondEmpty = context.entries[2];
    command(db, ownerId, "draw.entry.remove", { planId: context.planId, entryId: firstEmpty.entryId, reason: "Prepare first empty position" });
    context = fixtureContext(db);
    command(db, ownerId, "draw.entry.remove", { planId: context.planId, entryId: secondEmpty.entryId, reason: "Prepare second empty position" });
    context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "two manual moves",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.entry.move", {
        planId: context.planId, entryId: p.second.entryId,
        groupNumber: firstEmpty.groupNumber, slotNumber: firstEmpty.slotNumber,
        reason: "R6A concurrent manual move one",
      }),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.entry.move", {
        planId: context.planId, entryId: p.fourth.entryId,
        groupNumber: secondEmpty.groupNumber, slotNumber: secondEmpty.slotNumber,
        reason: "R6A concurrent manual move two",
      })));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("lock_move");
    let context = fixtureContext(db);
    const empty = context.entries[0];
    command(db, ownerId, "draw.entry.remove", { planId: context.planId, entryId: empty.entryId, reason: "Prepare empty position" });
    context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "lock vs move",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.lock.create", p.lock),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.entry.move", {
        planId: context.planId, entryId: p.third.entryId,
        groupNumber: empty.groupNumber, slotNumber: empty.slotNumber,
        reason: "R6A concurrent move against lock",
      })));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("validate_entry_change");
    const context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "validate vs entry change",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.validate", {
        planId: context.planId, reason: "R6A concurrent validation",
      }),
      commandSql(p.fourth.ownerId, randomUUID(), context.competitionId, context.revision, "participant.withdraw", {
        entryId: p.fourth.entryId, reason: "R6A concurrent entry change",
      })));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("two_publishes");
    let context = fixtureContext(db);
    command(db, ownerId, "draw.validate", { planId: context.planId, reason: "Prepare publish race" });
    context = fixtureContext(db);
    reports.push(await race(db, "two publishes",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.publish", { planId: context.planId, reason: "R6A publish one" }),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.publish", { planId: context.planId, reason: "R6A publish two" })));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("publish_rule_revision");
    let context = fixtureContext(db);
    command(db, ownerId, "draw.validate", { planId: context.planId, reason: "Prepare RuleRevision race" });
    context = fixtureContext(db);
    const p = payloads(context);
    reports.push(await race(db, "publish vs RuleRevision change",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.publish", { planId: context.planId, reason: "R6A concurrent publish" }),
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "tournament.authoring.save", p.authoring)));
    dropDatabase(db);
  }

  {
    const db = cloneDatabase("publish_freeze_replacement");
    let context = fixtureContext(db);
    command(db, ownerId, "draw.validate", { planId: context.planId, reason: "Prepare freeze replacement race" });
    context = fixtureContext(db);
    reports.push(await race(db, "publish vs participant freeze replacement",
      commandSql(ownerId, randomUUID(), context.competitionId, context.revision, "draw.publish", { planId: context.planId, reason: "R6A concurrent publish" }),
      replacementSql(ownerId, randomUUID(), context.competitionId, context.revision, context.planId)));
    dropDatabase(db);
  }

  assert.equal(reports.length, 10);
  process.stdout.write(`${JSON.stringify({
    database: "temporary-clones",
    races: reports,
    result: "10/10 one winner and one stale/conflict",
    tournamentMatches: 0,
  })}\n`);
} finally {
  let cleanupError;
  for (const name of [...caseDatabases, templateDatabase]) {
    try {
      dropDatabase(name);
    } catch (error) {
      cleanupError ??= error;
      process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    }
  }
  rmSync(infrastructureDump, { force: true });
  if (cleanupError) throw cleanupError;
}
