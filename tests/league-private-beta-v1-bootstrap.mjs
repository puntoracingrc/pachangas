import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_PRIVATE_BETA_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const freshName = `pachangas_league_beta_fresh_${suffix}`;
const upgradeName = `pachangas_league_beta_upgrade_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-league-beta-infra-${suffix}.sql`);
const freshSchemaDump = resolve(tmpdir(), `pachangas-league-beta-fresh-${suffix}.sql`);
const upgradeSchemaDump = resolve(tmpdir(), `pachangas-league-beta-upgrade-${suffix}.sql`);
const betaMigrations = [
  "20260825074304_league_private_beta_schema_v1.sql",
  "20260825074353_league_private_beta_commands_v1.sql",
  "20260825074358_league_private_beta_access_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_PRIVATE_BETA_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("LEAGUE_PRIVATE_BETA_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 139);
assert.deepEqual(migrationNames.slice(-3), betaMigrations);
const incrementals = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const preBetaIncrementals = incrementals.filter((name) => !betaMigrations.includes(name));
assert.equal(migrationNames.filter((name) => !betaMigrations.includes(name)).length, 136);

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
  if (result.status !== 0) throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
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
      'wizardTable', to_regclass('private.pachanga_league_private_beta_wizards') is not null,
      'receiptTable', to_regclass('private.pachanga_league_private_beta_operation_receipts') is not null,
      'invalidationTable', to_regclass('public.pachanga_league_private_beta_invalidations') is not null,
      'userCommand', to_regprocedure('public.command_pachanga_league_private_beta_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'platformCommand', to_regprocedure('public.command_pachanga_league_private_beta_platform_v1(uuid,uuid,bigint,text,jsonb,jsonb)') is not null,
      'myRead', to_regprocedure('public.get_my_pachanga_league_private_beta_v1()') is not null,
      'platformRead', to_regprocedure('public.get_pachanga_platform_league_private_beta_v1(text,integer,integer)') is not null,
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.league_private_beta_enabled
          or settings.league_private_beta_creation_enabled
          or settings.league_private_beta_public_discovery_enabled
      ),
      'productRows', (select count(*) from public.pachanga_competitions where product_key='LEAGUE_PRIVATE_BETA_V1'),
      'betaGrants', (select count(*) from public.pachanga_competition_entitlement_grants where program_key='LEAGUE_PRIVATE_BETA_V1'),
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
    from pg_stat_activity activity join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(name)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${name}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    if (Number(admin(`select count(*) from pg_stat_activity where datname=${quote(name)}`, `inspect ${name}`)) === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`LEAGUE_PRIVATE_BETA_BOOTSTRAP_CONNECTIONS_REMAIN:${name}`);
  }
  admin(`drop database if exists ${name}`, `drop ${name}`);
}

function dumpProductSchema(name, output) {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--file", output, targetUrl(name),
  ], `dump product schema ${name}`);
}

function normalizedSchema(file) {
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
  admin(`create database ${freshName} template template0`, "create fresh beta database");
  admin(`create database ${upgradeName} template template0`, "create upgrade beta database");
  provision(freshName);
  provision(upgradeName);

  const baseline = resolve(root, manifest.baselinePath);
  apply(freshName, [baseline, ...incrementals.map((name) => resolve(root, "supabase/migrations", name))], "fresh 139 bootstrap");
  apply(upgradeName, [baseline, ...preBetaIncrementals.map((name) => resolve(root, "supabase/migrations", name))], "prepare exact 136 ledger");
  assert.equal(query(upgradeName, "select to_regclass('private.pachanga_league_private_beta_wizards') is null"), "t");
  apply(upgradeName, betaMigrations.map((name) => resolve(root, "supabase/migrations", name)), "upgrade 136 to beta");

  const freshContract = contract(freshName);
  const upgradeContract = contract(upgradeName);
  assert.deepEqual(upgradeContract, freshContract, "Fresh and upgraded beta contracts diverged");
  assert.deepEqual(freshContract, {
    betaGrants: 0,
    canonicalMatches: 0,
    flagsOff: true,
    invalidationTable: true,
    myRead: true,
    platformCommand: true,
    platformRead: true,
    productRows: 0,
    receiptTable: true,
    userCommand: true,
    wizardTable: true,
  });

  dumpProductSchema(freshName, freshSchemaDump);
  dumpProductSchema(upgradeName, upgradeSchemaDump);
  assert.equal(normalizedSchema(upgradeSchemaDump), normalizedSchema(freshSchemaDump), "Fresh and upgraded beta schemas diverged");

  process.stdout.write(`${JSON.stringify({
    betaMigrations: 3,
    flagsOff: true,
    freshLedger: 139,
    productRows: 0,
    schemasEqual: true,
    upgradeFromLedger: 136,
  })}\n`);
} finally {
  dropDatabase(freshName);
  dropDatabase(upgradeName);
  rmSync(infrastructureDump, { force: true });
  rmSync(freshSchemaDump, { force: true });
  rmSync(upgradeSchemaDump, { force: true });
}
