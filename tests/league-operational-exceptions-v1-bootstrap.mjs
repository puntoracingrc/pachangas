import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const freshName = `pachangas_r4d_fresh_${suffix}`;
const upgradeName = `pachangas_r4d_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4d-bootstrap-${suffix}.sql`);
const freshSchemaDump = resolve(tmpdir(), `pachangas-r4d-fresh-schema-${suffix}.sql`);
const upgradeSchemaDump = resolve(tmpdir(), `pachangas-r4d-upgrade-schema-${suffix}.sql`);
const r4dMigrations = [
  "20260824230726_league_operational_exceptions_schema_v1.sql",
  "20260824230732_league_operational_exceptions_commands_v1.sql",
  "20260824230733_league_operational_exceptions_access_v1.sql",
  "20260824230734_league_operational_exceptions_hardening_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4D_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 135);
assert.deepEqual(migrationNames.slice(-4), r4dMigrations);
const incremental = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const preR4dIncremental = incremental.filter((name) => !r4dMigrations.includes(name));
assert.equal(preR4dIncremental.length + r4dMigrations.length + 36, 135);

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
          and relations.relname in (
            'pachanga_competition_fixture_changes','pachanga_competition_fixture_change_revisions',
            'pachanga_competition_postponement_requests','pachanga_competition_postponement_responses',
            'pachanga_competition_venue_change_requests','pachanga_competition_venue_condition_decisions',
            'pachanga_competition_late_arrival_incidents','pachanga_competition_no_show_incidents',
            'pachanga_competition_match_suspensions','pachanga_competition_match_resumption_decisions',
            'pachanga_competition_administrative_decisions','pachanga_competition_administrative_effects'
          )),
      'privateEvidence', to_regclass('private.pachanga_competition_operational_evidence') is not null,
      'command', to_regprocedure('public.command_pachanga_league_operational_exceptions_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'platformCommand', to_regprocedure('public.command_pachanga_league_operational_exceptions_platform_v1(uuid,uuid,bigint,jsonb,jsonb)') is not null,
      'matchRead', to_regprocedure('public.get_pachanga_league_operational_match_v1(uuid,uuid)') is not null,
      'publicRead', to_regprocedure('public.get_pachanga_public_league_fixture_status_v1(uuid,uuid)') is not null,
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.league_operational_exceptions_foundation_enabled
          or settings.league_postponements_enabled
          or settings.league_rescheduling_enabled
          or settings.league_venue_changes_enabled
          or settings.league_late_arrival_enabled
          or settings.league_no_show_enabled
          or settings.league_match_suspensions_enabled
          or settings.league_administrative_decisions_enabled
          or settings.league_public_exception_status_enabled
      ),
      'r4dRows', (
        (select count(*) from public.pachanga_competition_fixture_changes)
        + (select count(*) from public.pachanga_competition_postponement_requests)
        + (select count(*) from public.pachanga_competition_late_arrival_incidents)
        + (select count(*) from public.pachanga_competition_no_show_incidents)
        + (select count(*) from public.pachanga_competition_match_suspensions)
        + (select count(*) from public.pachanga_competition_administrative_decisions)
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
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(name)}`,
      `inspect ${name}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4D_BOOTSTRAP_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
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
  admin(`create database ${freshName} template template0`, "create fresh R4D database");
  admin(`create database ${upgradeName} template template0`, "create upgrade R4D database");
  provision(freshName);
  provision(upgradeName);

  const baseline = resolve(root, manifest.baselinePath);
  apply(freshName, [baseline, ...incremental.map((name) => resolve(root, "supabase/migrations", name))], "fresh R4D bootstrap");
  apply(upgradeName, [baseline, ...preR4dIncremental.map((name) => resolve(root, "supabase/migrations", name))], "prepare exact 131 ledger");
  assert.equal(query(upgradeName, "select to_regclass('public.pachanga_competition_fixture_changes') is null"), "t");
  apply(upgradeName, r4dMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 131 to R4D");

  const freshContract = contract(freshName);
  const upgradeContract = contract(upgradeName);
  assert.deepEqual(upgradeContract, freshContract, "Fresh and upgraded R4D contracts diverged");
  assert.deepEqual(freshContract, {
    canonicalMatches: 0,
    command: true,
    flagsOff: true,
    matchRead: true,
    platformCommand: true,
    privateEvidence: true,
    publicRead: true,
    publicTables: 12,
    r4dRows: 0,
  });

  dumpProductSchema(freshName, freshSchemaDump);
  dumpProductSchema(upgradeName, upgradeSchemaDump);
  assert.equal(
    normalizedSchemaDump(upgradeSchemaDump),
    normalizedSchemaDump(freshSchemaDump),
    "Fresh and upgraded R4D schemas diverged",
  );

  process.stdout.write(`${JSON.stringify({
    freshLedger: 135,
    upgradeFromLedger: 131,
    r4dMigrations: 4,
    schemasEqual: true,
    flagsOff: true,
    r4dRows: 0,
    canonicalMatches: 0,
  })}\n`);
} finally {
  dropDatabase(freshName);
  dropDatabase(upgradeName);
  rmSync(infrastructureDump, { force: true });
  rmSync(freshSchemaDump, { force: true });
  rmSync(upgradeSchemaDump, { force: true });
}
