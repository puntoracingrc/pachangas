import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
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
const freshName = `pachangas_r4c_fresh_${suffix}`;
const upgradeName = `pachangas_r4c_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4c-bootstrap-${suffix}.sql`);
const freshSchemaDump = resolve(tmpdir(), `pachangas-r4c-fresh-schema-${suffix}.sql`);
const upgradeSchemaDump = resolve(tmpdir(), `pachangas-r4c-upgrade-schema-${suffix}.sql`);
const r4cMigrations = [
  "20260824165759_league_match_operations_schema_v1.sql",
  "20260824165804_league_match_operations_commands_v1.sql",
  "20260824165810_league_match_operations_access_v1.sql",
  "20260824165815_league_match_operations_hardening_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_MATCH_OPERATIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4C_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 131);
assert.deepEqual(migrationNames.slice(-4), r4cMigrations);
const incremental = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const preR4cIncremental = incremental.filter((name) => !r4cMigrations.includes(name));

function targetUrl(name) {
  const value = new URL(adminUrl);
  value.pathname = `/${name}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
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

function query(name, sql) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(name), "-c", sql], `query ${name}`);
}

function apply(name, files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(name)];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function provision(name) {
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(name), "-f", infrastructureDump], `restore infrastructure ${name}`);
  query(name, "create publication supabase_realtime;");
}

function contract(name) {
  return JSON.parse(query(name, `
    select jsonb_build_object(
      'publicTables', (select count(*) from pg_class relations
        join pg_namespace namespaces on namespaces.oid=relations.relnamespace
        where namespaces.nspname='public' and relations.relkind='r'
          and relations.relname like 'pachanga_competition_%'
          and relations.relname in (
            'pachanga_competition_match_squads','pachanga_competition_match_squad_revisions',
            'pachanga_competition_match_squad_members','pachanga_competition_match_sheets',
            'pachanga_competition_sporting_results','pachanga_competition_sporting_result_revisions',
            'pachanga_competition_sporting_result_scorers','pachanga_competition_result_responses',
            'pachanga_competition_official_result_decisions','pachanga_competition_standing_states',
            'pachanga_competition_standing_snapshots','pachanga_competition_standing_rows',
            'pachanga_competition_tie_break_explanations','pachanga_competition_persisted_draw_lots',
            'pachanga_competition_standing_rebuild_receipts'
          )),
      'privateEvidence', to_regclass('private.pachanga_competition_official_result_evidence') is not null,
      'command', to_regprocedure('public.command_pachanga_league_match_operations_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'platformCommand', to_regprocedure('public.command_pachanga_league_match_operations_platform_v1(uuid,uuid,bigint,jsonb,jsonb)') is not null,
      'matchRead', to_regprocedure('public.get_pachanga_league_canonical_match_v1(uuid,uuid)') is not null,
      'standingsRead', to_regprocedure('public.get_pachanga_league_standings_v1(uuid,uuid,uuid,uuid)') is not null,
      'publicStandingsRead', to_regprocedure('public.get_pachanga_public_league_standings_v1(uuid,uuid,uuid,uuid)') is not null,
      'resultDesk', to_regprocedure('public.get_pachanga_league_result_desk_v1(uuid,text,integer,integer)') is not null,
      'deadlineProcessor', to_regprocedure('public.process_pachanga_league_result_deadlines_v1(uuid,timestamptz,integer,jsonb)') is not null,
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.league_match_operations_foundation_enabled
          or settings.league_match_squads_enabled
          or settings.league_match_attendance_enabled
          or settings.league_sporting_results_enabled
          or settings.league_result_confirmation_enabled
          or settings.league_official_results_enabled
          or settings.league_standings_enabled
          or settings.league_public_standings_enabled
      ),
      'r4cRows', (
        (select count(*) from public.pachanga_competition_match_squads)
        + (select count(*) from public.pachanga_competition_sporting_results)
        + (select count(*) from public.pachanga_competition_official_result_decisions)
        + (select count(*) from public.pachanga_competition_standing_snapshots)
      ),
      'canonicalMatches', (select count(*) from public.pachanga_canonical_matches)
    )::text;
  `));
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function dropDatabase(name) {
  admin(`alter database ${name} with allow_connections false`, `close ${name}`);
  admin(`select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(`select count(*) from pg_stat_activity where datname=${quote(name)}`, `inspect ${name}`));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4C_BOOTSTRAP_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

function dumpProductSchema(name, file) {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--file", file, targetUrl(name),
  ], `dump product schema ${name}`);
}

function normalizedSchemaDump(file) {
  return readFileSync(file, "utf8")
    .replace(/^\\restrict .+$/gm, "\\restrict <normalized>")
    .replace(/^\\unrestrict .+$/gm, "\\unrestrict <normalized>");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export Supabase infrastructure");
  admin(`create database ${freshName} template template0`, "create fresh R4C database");
  admin(`create database ${upgradeName} template template0`, "create upgrade R4C database");
  provision(freshName);
  provision(upgradeName);

  const baseline = resolve(root, manifest.baselinePath);
  apply(freshName, [baseline, ...incremental.map((name) => resolve(root, "supabase/migrations", name))], "fresh R4C bootstrap");
  apply(upgradeName, [baseline, ...preR4cIncremental.map((name) => resolve(root, "supabase/migrations", name))], "prepare exact 127 ledger");
  assert.equal(query(upgradeName, "select to_regclass('public.pachanga_competition_match_squads') is null"), "t");
  apply(upgradeName, r4cMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 127 to R4C");

  const freshContract = contract(freshName);
  const upgradeContract = contract(upgradeName);
  assert.deepEqual(upgradeContract, freshContract, "Fresh and upgraded R4C contracts diverged");
  assert.equal(freshContract.publicTables, 15);
  assert.equal(freshContract.privateEvidence, true);
  assert.equal(freshContract.command, true);
  assert.equal(freshContract.platformCommand, true);
  assert.equal(freshContract.matchRead, true);
  assert.equal(freshContract.standingsRead, true);
  assert.equal(freshContract.publicStandingsRead, true);
  assert.equal(freshContract.resultDesk, true);
  assert.equal(freshContract.deadlineProcessor, true);
  assert.equal(freshContract.flagsOff, true);
  assert.equal(freshContract.r4cRows, 0);
  assert.equal(freshContract.canonicalMatches, 0);

  dumpProductSchema(freshName, freshSchemaDump);
  dumpProductSchema(upgradeName, upgradeSchemaDump);
  assert.equal(
    normalizedSchemaDump(upgradeSchemaDump),
    normalizedSchemaDump(freshSchemaDump),
    "Fresh and upgraded R4C schemas diverged",
  );

  process.stdout.write(`${JSON.stringify({
    freshLedger: 131,
    upgradeFromLedger: 127,
    r4cMigrations: 4,
    schemasEqual: true,
    flagsOff: true,
    r4cRows: 0,
    canonicalMatches: 0,
  })}\n`);
} finally {
  dropDatabase(freshName);
  dropDatabase(upgradeName);
  rmSync(infrastructureDump, { force: true });
  rmSync(freshSchemaDump, { force: true });
  rmSync(upgradeSchemaDump, { force: true });
}
