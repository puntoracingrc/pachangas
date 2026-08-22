import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_PARTICIPATION_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4a_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4a-db-infrastructure-${suffix}.sql`);
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
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsedAdmin.hostname)) {
  throw new Error("R4A_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 119);
assert.deepEqual(migrationNames.slice(-6), r4aMigrations);
const preR4aIncremental = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !r4aMigrations.includes(name)
));

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
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

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function dropDatabase() {
  admin(
    `select pg_terminate_backend(pid) from pg_stat_activity where datname='${databaseName}' and pid<>pg_backend_pid()`,
    "terminate R4A DB test database",
  );
  admin(`drop database if exists ${databaseName}`, "drop R4A DB test database");
}

try {
  run(pgDumpBin, [
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
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R4A DB test database");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q",
    targetUrl(), "-f", infrastructureDump,
  ], "restore Supabase infrastructure");
  run(psqlBin, [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q",
    targetUrl(), "-c", "create publication supabase_realtime;",
  ], "create Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preR4aIncremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 113-migration R4A base");

  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-c", "begin",
    ...r4aMigrations.flatMap((name) => ["-f", resolve(root, "supabase/migrations", name)]),
    "-f", resolve(root, "tests/league-participation-v1-db.sql"),
    "-f", resolve(root, "tests/league-participation-v1-adversarial.sql"),
    "-c", "rollback",
  ];
  run(psqlBin, args, "R4A SQL, RLS and adversarial suite");
  process.stdout.write(`${JSON.stringify({
    adversarial: "PASS",
    baseLedger: 113,
    database: "temporary",
    r4aMigrations: 6,
    sqlRls: "PASS",
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
