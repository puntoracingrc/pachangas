import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.LEAGUE_SCHEDULING_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r4b_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4b-db-infrastructure-${suffix}.sql`);
const r4bMigrations = [
  "20260823224156_league_scheduling_schema_v1.sql",
  "20260823224218_league_scheduling_commands_v1.sql",
  "20260823224235_league_scheduling_access_v1.sql",
  "20260823224236_league_scheduling_hardening_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_SCHEDULING_DATABASE_URL is required");
const parsedAdmin = new URL(adminUrl);
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsedAdmin.hostname)) {
  throw new Error("R4B_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
const r4bBoundary = r4bMigrations.at(-1);
const historicalMigrations = migrationNames.filter((name) => name <= r4bBoundary);
assert.deepEqual(historicalMigrations.slice(-4), r4bMigrations);
const preR4bIncremental = historicalMigrations.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !r4bMigrations.includes(name)
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
    `alter database ${databaseName} with allow_connections false`,
    "close R4B DB test database",
  );
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname = activity.usename
      where activity.datname='${databaseName}'
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`,
    "terminate R4B DB test database",
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname='${databaseName}'`,
      "inspect R4B DB test database",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) {
      throw new Error(`R4B_DB_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
    }
  }
  admin(`drop database if exists ${databaseName}`, "drop R4B DB test database");
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
  admin(`create database ${databaseName} template template0`, "create R4B DB test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preR4bIncremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 119-migration R4B base");

  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-c", "begin",
    ...r4bMigrations.flatMap((name) => ["-f", resolve(root, "supabase/migrations", name)]),
    "-f", resolve(root, "tests/league-scheduling-v1-db.sql"),
    "-c", "rollback",
  ];
  run(psqlBin, args, "R4B SQL and RLS suite");
  process.stdout.write(`${JSON.stringify({
    baseLedger: 119,
    database: "temporary",
    r4bMigrations: 4,
    sqlRls: "PASS",
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
