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
const databaseName = `pachangas_r4c_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r4c-db-infrastructure-${suffix}.sql`);
const r4cMigrations = [
  "20260824165759_league_match_operations_schema_v1.sql",
  "20260824165804_league_match_operations_commands_v1.sql",
  "20260824165810_league_match_operations_access_v1.sql",
  "20260824165815_league_match_operations_hardening_v1.sql",
];

if (!adminUrl) throw new Error("LEAGUE_MATCH_OPERATIONS_DATABASE_URL is required");
if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R4C_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 131);
assert.deepEqual(migrationNames.slice(-4), r4cMigrations);
const preR4cIncremental = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !r4cMigrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !r4cMigrations.includes(name)).length, 127);

function targetUrl() {
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

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close R4C DB test database");
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname=activity.usename
      where activity.datname=${quote(databaseName)}
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`,
    "terminate R4C DB test database",
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      "inspect R4C DB test database",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R4C_DB_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop R4C DB test database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R4C DB test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-c", "create publication supabase_realtime;"], "create Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preR4cIncremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 127-migration R4C base");

  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(),
    "-c", "begin",
    ...r4cMigrations.flatMap((name) => ["-f", resolve(root, "supabase/migrations", name)]),
    "-f", resolve(root, "tests/league-match-operations-v1-db.sql"),
    "-c", "rollback",
  ];
  const sqlSuiteOutput = run(psqlBin, args, "R4C SQL, RLS and adversarial suite");
  const performanceLine = sqlSuiteOutput.split("\n")
    .map((line) => line.trim())
    .find((line) => line.startsWith("R4C_COMMAND_PERFORMANCE|"));
  assert.ok(performanceLine, `R4C command performance report missing: ${sqlSuiteOutput}`);
  const commandPerformance = JSON.parse(performanceLine.slice("R4C_COMMAND_PERFORMANCE|".length));

  apply(
    r4cMigrations.map((name) => resolve(root, "supabase/migrations", name)),
    "install R4C migrations for deadline policy suite",
  );
  const bilateralFixture = readFileSync(
    resolve(root, "tests/league-match-operations-v1-fixture.sql"),
    "utf8",
  );
  const autoDeadlineFixture = bilateralFixture.replace(
    '"mode":"BILATERAL"',
    '"mode":"AUTO_CONFIRM_AFTER_DEADLINE"',
  );
  assert.notEqual(autoDeadlineFixture, bilateralFixture);
  assert.equal((autoDeadlineFixture.match(/AUTO_CONFIRM_AFTER_DEADLINE/g) ?? []).length, 1);
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl()],
    "load immutable AUTO deadline fixture",
    autoDeadlineFixture,
  );
  run(
    psqlBin,
    [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl(),
      "-f", resolve(root, "tests/league-match-operations-v1-deadline.sql"),
    ],
    "R4C service-only deadline policy suite",
  );
  process.stdout.write(`${JSON.stringify({
    baseLedger: 127,
    database: "temporary",
    r4cMigrations: 4,
    sqlRlsAdversarial: "PASS",
    deadlinePolicy: "PASS",
    commandPerformance,
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
