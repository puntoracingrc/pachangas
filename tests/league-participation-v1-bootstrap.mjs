import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_PARTICIPATION_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const freshName = `pachangas_r4a_fresh_${suffix}`;
const upgradeName = `pachangas_r4a_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4a-supabase-infrastructure-${suffix}.sql`);
const r4aMigrations = [
  "20260822192929_league_participation_schema_v1.sql",
  "20260822192935_league_participation_commands_v1.sql",
  "20260822192941_league_participation_access_v1.sql",
  "20260822193624_club_competition_rule_entitlement_bridge_v1.sql",
  "20260822194325_club_competition_manage_entitlement_bridge_v1.sql",
  "20260822195054_league_team_owner_scope_precedence_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_PARTICIPATION_DATABASE_URL is required");
const parsedAdmin = new URL(adminUrl);
if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(parsedAdmin.hostname)) {
  throw new Error("R4A_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 119, "R4A repository ledger must contain 119 migrations");
assert.deepEqual(migrationNames.slice(-6), r4aMigrations, "R4A migrations must be the final forward-only ledger entries");
assert.equal(migrationNames.filter((name) => !r4aMigrations.includes(name)).length, 113);

const incremental = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const preR4aIncremental = incremental.filter((name) => !r4aMigrations.includes(name));

function targetUrl(databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(args, label, capture = false, binary = psqlBin) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    stdio: capture ? ["ignore", "pipe", "pipe"] : "pipe",
    maxBuffer: 64 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function admin(sql, label) {
  return run(["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label, true);
}

function query(databaseName, sql) {
  return run(["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql], `query ${databaseName}`, true);
}

function apply(databaseName, files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(databaseName)];
  for (const file of files) args.push("-f", file);
  run(args, label);
}

function exportSupabaseInfrastructure() {
  run([
    "--schema-only",
    "--no-owner",
    "--no-privileges",
    "--no-publications",
    "--exclude-schema=public",
    "--exclude-schema=private",
    "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations",
    "--exclude-schema=realtime",
    "--file", infrastructureDump,
    adminUrl,
  ], "export local Supabase infrastructure", false, pgDumpBin);
}

function provisionSupabaseInfrastructure(databaseName) {
  run([
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q",
    targetUrl(databaseName), "-f", infrastructureDump,
  ], `provision Supabase infrastructure in ${databaseName}`);
  query(databaseName, "create publication supabase_realtime;");
}

function contract(databaseName) {
  return JSON.parse(query(databaseName, `
    select jsonb_build_object(
      'tables', (
        select jsonb_agg(relname order by relname)
        from pg_class relations join pg_namespace namespaces on namespaces.oid=relations.relnamespace
        where namespaces.nspname='public' and relations.relkind='r'
          and relations.relname in (
            'pachanga_competition_categories','pachanga_competition_entries',
            'pachanga_competition_entry_invitations','pachanga_competition_team_delegates',
            'pachanga_competition_stage_memberships','pachanga_competition_rosters',
            'pachanga_competition_roster_revisions','pachanga_competition_roster_members',
            'pachanga_player_competition_credentials','pachanga_competition_team_kits',
            'pachanga_competition_player_jersey_numbers','pachanga_team_availability_constraints',
            'pachanga_team_schedule_preferences'
          )
      ),
      'command', to_regprocedure('public.command_pachanga_league_participation_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'platformCommand', to_regprocedure('public.command_pachanga_league_participation_platform_v1(uuid,uuid,bigint,jsonb,jsonb)') is not null,
      'publicRead', to_regprocedure('public.get_pachanga_league_public_registration_v1(uuid)') is not null,
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings
        where settings.league_participation_foundation_enabled
          or settings.league_registration_enabled
          or settings.league_public_registration_enabled
          or settings.league_delegates_enabled
          or settings.league_rosters_enabled
          or settings.league_schedule_preferences_enabled
      ),
      'roundsAbsent', to_regclass('public.pachanga_competition_rounds') is null,
      'fixturesAbsent', to_regclass('public.pachanga_league_fixtures') is null,
      'canonicalMatches', (select count(*) from public.pachanga_canonical_matches),
      'matchContexts', (select count(*) from public.pachanga_competition_match_contexts)
    )::text;
  `));
}

function dropDatabase(name) {
  admin(`select pg_terminate_backend(pid) from pg_stat_activity where datname=${literal(name)} and pid<>pg_backend_pid()`, `terminate ${name}`);
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

function literal(value) { return `'${String(value).replaceAll("'", "''")}'`; }

try {
  exportSupabaseInfrastructure();
  admin(`create database ${freshName} template template0`, "create fresh database");
  admin(`create database ${upgradeName} template template0`, "create upgrade database");
  provisionSupabaseInfrastructure(freshName);
  provisionSupabaseInfrastructure(upgradeName);

  const baseline = resolve(root, manifest.baselinePath);
  apply(freshName, [baseline, ...incremental.map((name) => resolve(root, "supabase/migrations", name))], "fresh bootstrap");

  apply(upgradeName, [baseline, ...preR4aIncremental.map((name) => resolve(root, "supabase/migrations", name))], "113 migration upgrade base");
  assert.equal(query(upgradeName, `select to_regclass('public.pachanga_competition_rosters') is null`), "t", "R4A leaked into the 113-migration base");
  apply(upgradeName, r4aMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 113 to R4A");

  const freshContract = contract(freshName);
  const upgradeContract = contract(upgradeName);
  assert.deepEqual(upgradeContract, freshContract, "Fresh and upgraded R4A schemas diverged");
  assert.equal(freshContract.tables.length, 13);
  assert.equal(freshContract.command, true);
  assert.equal(freshContract.platformCommand, true);
  assert.equal(freshContract.publicRead, true);
  assert.equal(freshContract.flagsOff, true);
  assert.equal(freshContract.roundsAbsent, true);
  assert.equal(freshContract.fixturesAbsent, true);
  assert.equal(freshContract.canonicalMatches, 0);
  assert.equal(freshContract.matchContexts, 0);

  process.stdout.write(`${JSON.stringify({
    freshLedger: 119,
    upgradeFromLedger: 113,
    r4aMigrations: r4aMigrations.length,
    schemasEqual: true,
    flagsOff: true,
    canonicalMatches: 0,
  })}\n`);
} finally {
  dropDatabase(freshName);
  dropDatabase(upgradeName);
  rmSync(infrastructureDump, { force: true });
}
