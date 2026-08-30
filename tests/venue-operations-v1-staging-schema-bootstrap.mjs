import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const databaseUrl = process.env.VENUE_OPERATIONS_STAGING_DATABASE_URL;
const confirmation = process.env.VENUE_OPERATIONS_STAGING_CONFIRM;
const projectRef = process.env.VENUE_OPERATIONS_STAGING_PROJECT_REF;
const productionRef = "qonbngfrnrqgmxbdfbea";

if (!databaseUrl || !projectRef) throw new Error("VENUE_OPERATIONS_STAGING_SCHEMA_ENV_REQUIRED");
const target = new URL(databaseUrl);
if (
  confirmation !== "VENUE_OPERATIONS_STAGING_ONLY"
  || projectRef === productionRef
  || !target.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(target.username).endsWith(`.${projectRef}`)
) throw new Error("VENUE_OPERATIONS_STAGING_SCHEMA_PRODUCTION_TARGET_FORBIDDEN");

const migrationFiles = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationFiles.length, 220);
assert.equal(migrationFiles.at(-1), "20260830145100_venue_hardening_indexes_flags_v1.sql");

function redact(value) {
  return String(value || "").replaceAll(databaseUrl, "[REDACTED_DATABASE_URL]");
}

function run(binary, args, label) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label}: ${redact(result.stderr)}${redact(result.stdout)}`);
  }
  return (result.stdout || "").trim();
}

function sql(query) {
  return run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl, "-c", query,
  ], "Wave 9A staging schema readback");
}

function ledger() {
  return sql(`select coalesce(json_agg(version order by version),'[]'::json)::text
    from supabase_migrations.schema_migrations`);
}

function verifyFinal() {
  const snapshot = JSON.parse(sql(`select json_build_object(
    'ledgerCount',(select count(*) from supabase_migrations.schema_migrations),
    'lastVersion',(select max(version) from supabase_migrations.schema_migrations),
    'venueTables',(select count(*) from information_schema.tables
      where table_schema='public' and table_name like 'pachanga_venue%'),
    'rlsHelper',to_regprocedure('private.pachanga_venue_can_read_invalidation_v1(text,uuid)') is not null,
    'flagsBornOff',(select not (
      venue_foundation_enabled or venue_management_enabled or venue_public_profiles_enabled
      or venue_public_directory_enabled or venue_availability_enabled
      or venue_reservation_requests_enabled or venue_counteroffers_enabled
      or venue_reservation_holds_enabled or venue_canonical_reservations_enabled
      or venue_match_binding_enabled or venue_r4d_integration_enabled
      or demo_world_v3_4_enabled
    ) from private.pachanga_venue_settings_v1 where singleton)
  )::text`));
  assert.deepEqual(snapshot, {
    flagsBornOff: true,
    lastVersion: "20260830145100",
    ledgerCount: 220,
    rlsHelper: true,
    venueTables: 9,
  });
  return snapshot;
}

const initialVersions = JSON.parse(ledger());
if (initialVersions.length === 220) {
  process.stdout.write(`${JSON.stringify({
    status: "VENUE_OPERATIONS_V1_STAGING_SCHEMA_ALREADY_CERTIFIED",
    ...verifyFinal(),
  })}\n`);
  process.exit(0);
}

assert.deepEqual(initialVersions, manifest.absorbedMigrations.slice(0, 10));

run("psql", [
  "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
  databaseUrl, "-f", resolve(root, manifest.baselinePath),
], "apply canonical product baseline to staging");

const absorbedMissing = manifest.absorbedMigrations.slice(initialVersions.length);
run("supabase", [
  "migration", "repair", ...absorbedMissing,
  "--status", "applied", "--db-url", databaseUrl, "--yes",
], "repair absorbed staging migration history");

const cliWorkdir = mkdtempSync(resolve(tmpdir(), "pachangas-wave9a-staging-cli-"));
let finalSnapshot;
try {
  const isolatedSupabase = resolve(cliWorkdir, "supabase");
  mkdirSync(isolatedSupabase, { recursive: true });
  writeFileSync(resolve(isolatedSupabase, "config.toml"), `project_id = "wave9a-staging-bootstrap"

[db.migrations]
enabled = true
schema_paths = []

[db.seed]
enabled = false
sql_paths = []
`);
  symlinkSync(resolve(root, "supabase/migrations"), resolve(isolatedSupabase, "migrations"), "dir");
  run("supabase", [
    "db", "push", "--db-url", databaseUrl, "--include-all", "--yes",
    "--workdir", cliWorkdir,
  ], "apply incremental and Wave 9A staging migrations");
  finalSnapshot = verifyFinal();
} finally {
  rmSync(cliWorkdir, { force: true, recursive: true });
}

process.stdout.write(`${JSON.stringify({
  status: "VENUE_OPERATIONS_V1_STAGING_SCHEMA_PASS",
  absorbedVersionsReconciled: absorbedMissing.length,
  temporaryCliWorkdir: "CLEANED",
  ...finalSnapshot,
})}\n`);
