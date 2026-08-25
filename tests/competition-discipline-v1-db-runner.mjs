import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.COMPETITION_DISCIPLINE_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_r5_db_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-r5-db-infrastructure-${suffix}.sql`);
const r5Migrations = [
  "20260825165834_competition_discipline_schema_v1.sql",
  "20260825165838_competition_discipline_commands_v1.sql",
  "20260825165843_competition_discipline_access_v1.sql",
  "20260825165849_competition_discipline_hardening_v1.sql",
  "20260825203500_competition_discipline_appeal_service_accounting_v1.sql",
];

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("R5_DB_TEST_LOCAL_DATABASE_REQUIRED");
}

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 146);
assert.deepEqual(migrationNames.slice(-5), r5Migrations);
const preR5Incremental = migrationNames.filter((name) => (
  name.slice(0, 14) > manifest.absorbsThrough && !r5Migrations.includes(name)
));
assert.equal(migrationNames.filter((name) => !r5Migrations.includes(name)).length, 141);

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
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-c", sql], label);
}

function apply(files, label) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", targetUrl()];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function dropDatabase() {
  admin(`alter database ${databaseName} with allow_connections false`, "close R5 DB test database");
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
       join pg_roles roles on roles.rolname=activity.usename
      where activity.datname=${quote(databaseName)}
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`,
    "terminate R5 DB test database",
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      "inspect R5 DB test database",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`R5_DB_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop R5 DB test database");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create R5 DB test database");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  query("create publication supabase_realtime;", "create R5 Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...preR5Incremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "prepare exact 141-migration pre-R5 base");
  assert.equal(query(
    "select to_regclass('public.pachanga_competition_disciplinary_events') is null",
    "verify pre-R5 base",
  ), "t");

  apply(r5Migrations.map((name) => resolve(root, "supabase/migrations", name)), "install R5 migrations");
  const inactive = JSON.parse(query(`
    select jsonb_build_object(
      'flagsOff', not exists (
        select 1 from private.pachanga_competition_foundation_settings settings where
          settings.competition_discipline_foundation_enabled
          or settings.competition_disciplinary_events_enabled
          or settings.competition_disciplinary_counters_enabled
          or settings.competition_sanctions_enabled
          or settings.competition_sanction_service_enabled
          or settings.competition_discipline_appeals_enabled
          or settings.competition_public_discipline_enabled
      ),
      'rows', (
        (select count(*) from public.pachanga_competition_disciplinary_events)
        + (select count(*) from public.pachanga_competition_disciplinary_counters)
        + (select count(*) from public.pachanga_competition_sanctions)
        + (select count(*) from public.pachanga_competition_sanction_service_events)
        + (select count(*) from public.pachanga_competition_sanction_appeals)
      ),
      'directAuthenticatedInsert', has_table_privilege(
        'authenticated', 'public.pachanga_competition_disciplinary_events', 'INSERT'
      )
    )::text;
  `, "verify inert R5 install"));
  assert.deepEqual(inactive, { directAuthenticatedInsert: false, flagsOff: true, rows: 0 });

  const activationOutput = run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-f", resolve(root, "tests/competition-discipline-v1-activation.sql")],
    "R5 legacy bundle upgrade and activation bridge",
  );
  const activationLine = activationOutput.split("\n").map((line) => line.trim())
    .find((line) => line.startsWith("R5_ACTIVATION_REPORT|"));
  assert.ok(activationLine, `R5 activation report missing: ${activationOutput}`);
  const activation = JSON.parse(activationLine.slice("R5_ACTIVATION_REPORT|".length));
  assert.deepEqual(activation, {
    activeCapabilities: 14,
    guardedBeforeUpgrade: true,
    insertedR5Capabilities: 3,
    legacyCapabilities: 11,
    publicDiscipline: false,
    upgradeReplay: true,
  });

  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", resolve(root, "tests/competition-discipline-v1-fixture.sql")],
    "load isolated R5 fixture",
  );
  const output = run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(), "-f", resolve(root, "tests/competition-discipline-v1-db.sql")],
    "R5 SQL, RLS, idempotency and adversarial suite",
  );
  const reportLine = output.split("\n").map((line) => line.trim())
    .find((line) => line.startsWith("R5_DB_REPORT|"));
  assert.ok(reportLine, `R5 DB report missing: ${output}`);
  const report = JSON.parse(reportLine.slice("R5_DB_REPORT|".length));
  assert.equal(report.invariants, "IDENTICAL");
  assert.equal(report.publicDiscipline, false);

  const appealServiceOutput = run(
    psqlBin,
    [
      "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(),
      "-c", "begin",
      "-f", resolve(root, "tests/competition-discipline-v1-appeal-service-regression.sql"),
      "-c", "rollback",
    ],
    "R5 appeal reduction after service regression",
  );
  assert.match(appealServiceOutput, /R5_APPEAL_SERVICE_REGRESSION\|PASS/);

  process.stdout.write(`${JSON.stringify({
    baseLedger: 141,
    database: "temporary",
    r5Migrations: r5Migrations.length,
    flagsDefaultOff: true,
    productRowsDefault: 0,
    activationBridge: activation,
    sqlRlsIdempotencyAdversarial: "PASS",
    appealServiceAccounting: "PASS",
    report,
  })}\n`);
} finally {
  dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
