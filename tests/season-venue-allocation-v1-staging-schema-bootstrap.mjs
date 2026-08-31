import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const confirmation = process.env.SEASON_VENUE_STAGING_CONFIRM;
const databasePassword = process.env.SEASON_VENUE_STAGING_DATABASE_PASSWORD;
const databaseUri = process.env.SEASON_VENUE_STAGING_DATABASE_URI;
const projectRef = process.env.SEASON_VENUE_STAGING_PROJECT_REF;
const productionRef = "qonbngfrnrqgmxbdfbea";
const expectedSchemaHash = "4f3fa78ef66026dc8e14f45bfc9957b3154daf6b616a4a3f07106776fcb4bd93";

if (!databasePassword || !databaseUri || !projectRef) {
  throw new Error("SEASON_VENUE_STAGING_SCHEMA_ENV_REQUIRED");
}

const target = new URL(databaseUri);
if (
  confirmation !== "SEASON_VENUE_STAGING_ONLY"
  || projectRef === productionRef
  || !target.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(target.username).endsWith(`.${projectRef}`)
  || target.password
) {
  throw new Error("SEASON_VENUE_STAGING_SCHEMA_PRODUCTION_TARGET_FORBIDDEN");
}

const childEnv = { ...process.env, PGPASSWORD: databasePassword };
const migrationFiles = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationFiles.length, 228);
assert.equal(migrationFiles.at(-1), "20260830223014_competition_venue_allocation_hardening_flags_v1.sql");

const baseline = readFileSync(resolve(root, manifest.baselinePath));
assert.equal(createHash("sha256").update(baseline).digest("hex"), manifest.sha256);

function redact(value) {
  return String(value || "")
    .replaceAll(databasePassword, "[REDACTED_DATABASE_PASSWORD]")
    .replaceAll(databaseUri, "[REDACTED_DATABASE_URI]");
}

function run(binary, args, label, options = {}) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: childEnv,
    input: options.input,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label}: ${redact(result.stderr)}${redact(result.stdout)}`);
  }
  return result.stdout || "";
}

function sql(query) {
  return run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUri, "-c", query,
  ], "Wave 9B staging schema readback").trim();
}

function readLedger() {
  return JSON.parse(sql(`select coalesce(json_agg(version order by version),'[]'::json)::text
    from supabase_migrations.schema_migrations`));
}

function normalizedSchemaHash() {
  const dump = run("pg_dump", [
    "--schema-only",
    "--no-owner",
    "--no-privileges",
    "--no-publications",
    "--schema=public",
    "--schema=private",
    databaseUri,
  ], "Wave 9B staging schema dump");
  const normalized = dump
    .split("\n")
    .filter((line) => !/^--/.test(line) && !/^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
  return createHash("sha256").update(normalized).digest("hex");
}

function verifyFinal() {
  const snapshot = JSON.parse(sql(`select json_build_object(
    'ledgerCount',(select count(*) from supabase_migrations.schema_migrations),
    'lastVersion',(select max(version) from supabase_migrations.schema_migrations),
    'teamCodeUnique',(select count(*) from pg_constraint
      where conrelid='public.pachanga_groups'::regclass
        and conname='pachanga_groups_team_code_key'),
    'wave9bPublicTables',(select count(*) from information_schema.tables
      where table_schema='public' and table_name in (
        'pachanga_venue_recurring_series','pachanga_venue_recurring_exceptions',
        'pachanga_venue_recurring_occurrences','pachanga_competition_venue_pools',
        'pachanga_competition_venue_authorizations','pachanga_competition_venue_pool_memberships',
        'pachanga_competition_venue_allocation_plans','pachanga_competition_venue_allocation_revisions',
        'pachanga_competition_venue_allocation_items','pachanga_competition_venue_allocation_constraints',
        'pachanga_competition_venue_allocation_locks','pachanga_competition_venue_allocation_holds'
      )),
    'wave9bRlsTables',(select count(*) from pg_class relations
      join pg_namespace namespaces on namespaces.oid=relations.relnamespace
      where namespaces.nspname='public' and relations.relrowsecurity
        and relations.relname in (
          'pachanga_venue_recurring_series','pachanga_venue_recurring_exceptions',
          'pachanga_venue_recurring_occurrences','pachanga_competition_venue_pools',
          'pachanga_competition_venue_authorizations','pachanga_competition_venue_pool_memberships',
          'pachanga_competition_venue_allocation_plans','pachanga_competition_venue_allocation_revisions',
          'pachanga_competition_venue_allocation_items','pachanga_competition_venue_allocation_constraints',
          'pachanga_competition_venue_allocation_locks','pachanga_competition_venue_allocation_holds'
        )),
    'flagsBornOff',(select not (
      venue_recurring_series_enabled or venue_recurring_materialization_enabled
      or competition_venue_pool_enabled or competition_venue_allocation_foundation_enabled
      or competition_venue_allocation_automatic_enabled or competition_venue_allocation_manual_enabled
      or competition_venue_allocation_hybrid_enabled or competition_venue_allocation_holds_enabled
      or competition_venue_allocation_publish_enabled or demo_world_v35_enabled
    ) from private.pachanga_venue_settings_v1 where singleton)
  )::text`));
  assert.deepEqual(snapshot, {
    flagsBornOff: true,
    lastVersion: "20260830223014",
    ledgerCount: 228,
    teamCodeUnique: 1,
    wave9bPublicTables: 12,
    wave9bRlsTables: 12,
  });
  assert.deepEqual(readLedger(), migrationFiles.map((name) => name.slice(0, 14)));
  const schemaHash = normalizedSchemaHash();
  assert.equal(schemaHash, expectedSchemaHash);
  return { ...snapshot, schemaHash };
}

const initialVersions = readLedger();
if (initialVersions.length === 228) {
  process.stdout.write(`${JSON.stringify({
    status: "SEASON_VENUE_STAGING_SCHEMA_ALREADY_CERTIFIED",
    ...verifyFinal(),
  })}\n`);
  process.exit(0);
}

let absorbedVersionsReconciled = 0;
if (initialVersions.length === 10) {
  assert.deepEqual(initialVersions, manifest.absorbedMigrations.slice(0, 10));
  const prefix = JSON.parse(sql(`select json_build_object(
    'relations',(select coalesce(json_agg(relname order by relname),'[]'::json)
      from pg_class relations join pg_namespace namespaces on namespaces.oid=relations.relnamespace
      where namespaces.nspname='public' and relations.relkind in ('r','p')
        and relations.relname like 'pachanga%'),
    'groups',(select count(*) from public.pachanga_groups),
    'members',(select count(*) from public.pachanga_group_members),
    'backups',(select count(*) from public.pachanga_group_backups)
  )::text`));
  assert.deepEqual(prefix, {
    backups: 0,
    groups: 0,
    members: 0,
    relations: ["pachanga_group_backups", "pachanga_group_members", "pachanga_groups"],
  });

  const resetAndBaseline = Buffer.concat([
    Buffer.from(`begin;
drop table public.pachanga_group_backups;
drop table public.pachanga_group_members;
drop table public.pachanga_groups cascade;
`),
    baseline,
    Buffer.from("\ncommit;\n"),
  ]);
  run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUri,
  ], "rebuild partial staging prefix from signed baseline", { input: resetAndBaseline });

  const absorbedMissing = manifest.absorbedMigrations.slice(initialVersions.length);
  run("supabase", [
    "migration", "repair", ...absorbedMissing,
    "--status", "applied", "--db-url", databaseUri, "--yes",
  ], "repair absorbed staging migration history");
  absorbedVersionsReconciled = absorbedMissing.length;
} else {
  assert.deepEqual(initialVersions, manifest.absorbedMigrations);
  const baselineState = JSON.parse(sql(`select json_build_object(
    'teamCodeUnique',(select count(*) from pg_constraint
      where conrelid='public.pachanga_groups'::regclass
        and conname='pachanga_groups_team_code_key'),
    'groups',(select count(*) from public.pachanga_groups),
    'members',(select count(*) from public.pachanga_group_members),
    'backups',(select count(*) from public.pachanga_group_backups)
  )::text`));
  assert.deepEqual(baselineState, { backups: 0, groups: 0, members: 0, teamCodeUnique: 1 });
}

const applied = new Set(readLedger());
for (const [index, migrationFile] of migrationFiles.entries()) {
  const version = migrationFile.slice(0, 14);
  if (applied.has(version)) continue;
  const name = migrationFile.slice(15, -4);
  let migration = readFileSync(resolve(root, "supabase/migrations", migrationFile), "utf8");
  if (migrationFile === "20260828045324_tournament_knockout_flag_authority_compatibility_v1.sql") {
    migration = migration.replace(/^\s*begin;\s*/i, "").replace(/\s*commit;\s*$/i, "");
  }
  const escapedName = name.replaceAll("'", "''");
  const transactionalMigration = `begin;\n${migration}\ninsert into supabase_migrations.schema_migrations(version, statements, name)\nvalues ('${version}', '{}'::text[], '${escapedName}');\ncommit;\n`;
  run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUri,
  ], `apply staging migration ${version}`, { input: transactionalMigration });
  if ((index + 1) % 32 === 0) {
    process.stderr.write(`Wave 9B staging bootstrap progress: ${index + 1}/${migrationFiles.length}\n`);
  }
}
const finalSnapshot = verifyFinal();

process.stdout.write(`${JSON.stringify({
  status: "SEASON_VENUE_STAGING_SCHEMA_PASS",
  absorbedVersionsReconciled,
  migrationTransport: "PSQL_ATOMIC_LEDGER",
  ...finalSnapshot,
})}\n`);
