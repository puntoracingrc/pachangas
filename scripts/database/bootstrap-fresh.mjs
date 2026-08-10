#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const manifestPath = resolve(repoRoot, "supabase/baselines/manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const requestedDatabaseUrl = readDatabaseUrl(process.argv.slice(2));
const supabaseWorkdir = readSupabaseWorkdir(process.argv.slice(2));
const childEnv = { ...process.env };

if (process.env.PACHANGAS_SUPABASE_HOME) {
  childEnv.HOME = process.env.PACHANGAS_SUPABASE_HOME;
}

assertLocalDatabaseUrl(requestedDatabaseUrl);
const databaseUrl = localDatabaseUrl(requestedDatabaseUrl);
assertSupabaseWorkdirMigrationsMatch();
const localProjectDatabaseUrl = readLocalProjectDatabaseUrl();
assertSameDatabaseTarget(databaseUrl, localProjectDatabaseUrl);
assertBaselineIntegrity();
assertAbsorbedMigrationSet();
assertFreshProductDatabase();

run("psql", [
  "-X",
  "--set",
  "ON_ERROR_STOP=1",
  "--single-transaction",
  databaseUrl,
  "--file",
  resolve(repoRoot, manifest.baselinePath),
]);

run("supabase", [
  "migration",
  "repair",
  "--workdir",
  supabaseWorkdir,
  "--local",
  "--status",
  "applied",
  ...manifest.absorbedMigrations,
]);

run("supabase", ["migration", "up", "--workdir", supabaseWorkdir, "--local", "--include-all"]);

const appliedCount = Number(query("select count(*) from supabase_migrations.schema_migrations;"));
const repositoryMigrationCount = readdirSync(resolve(repoRoot, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name)).length;
const simulationSchemaPresent = query("select (to_regnamespace('simulation') is not null)::int;") === "1";

if (appliedCount !== repositoryMigrationCount) {
  throw new Error(`BOOTSTRAP_MIGRATION_LEDGER_MISMATCH expected=${repositoryMigrationCount} actual=${appliedCount}`);
}
if (simulationSchemaPresent) {
  throw new Error("BOOTSTRAP_LAB_SCHEMA_LEAK");
}

process.stdout.write(`${JSON.stringify({
  appliedMigrations: appliedCount,
  baselineVersion: manifest.baselineVersion,
  firstIncrementalMigration: manifest.firstIncrementalMigration,
  status: "BOOTSTRAP_COMPLETE",
})}\n`);

function readDatabaseUrl(args) {
  const flagIndex = args.indexOf("--db-url");
  const value = flagIndex >= 0 ? args[flagIndex + 1] : process.env.PACHANGAS_BOOTSTRAP_DATABASE_URL;
  if (!value) throw new Error("PACHANGAS_BOOTSTRAP_DATABASE_URL_OR_DB_URL_REQUIRED");
  return value;
}

function readSupabaseWorkdir(args) {
  const flagIndex = args.indexOf("--supabase-workdir");
  return resolve(flagIndex >= 0 ? args[flagIndex + 1] : repoRoot);
}

function assertLocalDatabaseUrl(value) {
  const parsed = new URL(value);
  if (!["postgres:", "postgresql:"].includes(parsed.protocol)) {
    throw new Error("BOOTSTRAP_POSTGRES_URL_REQUIRED");
  }
  if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsed.hostname)) {
    throw new Error("BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
  }
}

function localDatabaseUrl(value) {
  const parsed = new URL(value);
  if (!parsed.searchParams.has("sslmode")) parsed.searchParams.set("sslmode", "disable");
  return parsed.toString();
}

function readLocalProjectDatabaseUrl() {
  const output = run("supabase", ["status", "--workdir", supabaseWorkdir, "--output", "json"], true);
  let status;
  try {
    status = JSON.parse(output);
  } catch {
    throw new Error("BOOTSTRAP_LOCAL_PROJECT_STATUS_INVALID");
  }
  if (typeof status.DB_URL !== "string") {
    throw new Error("BOOTSTRAP_LOCAL_PROJECT_DATABASE_URL_MISSING");
  }
  assertLocalDatabaseUrl(status.DB_URL);
  return localDatabaseUrl(status.DB_URL);
}

function assertSameDatabaseTarget(requestedUrl, projectUrl) {
  const requestedTarget = normalizeDatabaseTarget(requestedUrl);
  const projectTarget = normalizeDatabaseTarget(projectUrl);
  if (requestedTarget !== projectTarget) {
    throw new Error(`BOOTSTRAP_LOCAL_PROJECT_DATABASE_MISMATCH requested=${requestedTarget} project=${projectTarget}`);
  }
}

function normalizeDatabaseTarget(value) {
  const parsed = new URL(value);
  const host = ["localhost", "::1", "[::1]"].includes(parsed.hostname) ? "127.0.0.1" : parsed.hostname;
  const port = parsed.port || "5432";
  const database = decodeURIComponent(parsed.pathname.replace(/^\/+/, ""));
  return `${host}:${port}/${database}`;
}

function assertBaselineIntegrity() {
  const contents = readFileSync(resolve(repoRoot, manifest.baselinePath));
  const actualHash = createHash("sha256").update(contents).digest("hex");
  if (actualHash !== manifest.sha256) {
    throw new Error(`BOOTSTRAP_BASELINE_HASH_MISMATCH expected=${manifest.sha256} actual=${actualHash}`);
  }
}

function assertSupabaseWorkdirMigrationsMatch() {
  const repositoryDirectory = resolve(repoRoot, "supabase/migrations");
  const workdirDirectory = resolve(supabaseWorkdir, "supabase/migrations");
  const repositoryFiles = migrationFiles(repositoryDirectory);
  const workdirFiles = migrationFiles(workdirDirectory);
  if (JSON.stringify(repositoryFiles) !== JSON.stringify(workdirFiles)) {
    throw new Error("BOOTSTRAP_WORKDIR_MIGRATION_SET_MISMATCH");
  }
  for (const file of repositoryFiles) {
    const repositoryHash = createHash("sha256").update(readFileSync(resolve(repositoryDirectory, file))).digest("hex");
    const workdirHash = createHash("sha256").update(readFileSync(resolve(workdirDirectory, file))).digest("hex");
    if (repositoryHash !== workdirHash) {
      throw new Error(`BOOTSTRAP_WORKDIR_MIGRATION_HASH_MISMATCH file=${file}`);
    }
  }
}

function migrationFiles(directory) {
  return readdirSync(directory).filter((name) => /^\d{14}_.+\.sql$/.test(name)).sort();
}

function assertAbsorbedMigrationSet() {
  const actual = migrationFiles(resolve(repoRoot, "supabase/migrations"))
    .map((name) => name.slice(0, 14))
    .filter((version) => version <= manifest.absorbsThrough)
    .sort();
  const expected = [...manifest.absorbedMigrations].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("BOOTSTRAP_ABSORBED_MIGRATIONS_DRIFT");
  }
}

function assertFreshProductDatabase() {
  const productRelationCount = Number(query(`
    select count(*)
    from pg_class relations
    join pg_namespace namespaces on namespaces.oid = relations.relnamespace
    where relations.relkind in ('r', 'p', 'v', 'm', 'S')
      and (
        namespaces.nspname = 'private'
        or (namespaces.nspname = 'public' and relations.relname like 'pachanga%')
      );
  `));
  if (productRelationCount !== 0) {
    throw new Error(`BOOTSTRAP_PRODUCT_DATABASE_NOT_EMPTY relations=${productRelationCount}`);
  }
}

function query(sql) {
  return run("psql", ["-X", "--tuples-only", "--no-align", databaseUrl, "--command", sql], true).trim();
}

function run(command, args, capture = false) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: childEnv,
    stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const details = capture ? `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() : "";
    throw new Error(`${command} failed with exit ${result.status}${details ? `: ${details}` : ""}`);
  }
  return result.stdout ?? "";
}
