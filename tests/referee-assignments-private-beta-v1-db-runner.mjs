import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.REFEREE_ASSIGNMENTS_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const scaleMode = process.argv.includes("--scale");
const scaleAssignmentCount = Number(process.env.WAVE4_SCALE_ASSIGNMENTS || 10000);
const scaleDisciplinaryEventCount = Number(process.env.WAVE4_SCALE_DISCIPLINARY_EVENTS || 50000);
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave4_${scaleMode ? "scale" : "db"}_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave4-infrastructure-${suffix}.sql`);
let databaseDropped = false;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("WAVE4_DB_TEST_LOCAL_DATABASE_REQUIRED");
}
assert.ok(Number.isInteger(scaleAssignmentCount) && scaleAssignmentCount >= 1 && scaleAssignmentCount <= 10000);
assert.ok(Number.isInteger(scaleDisciplinaryEventCount)
  && scaleDisciplinaryEventCount >= 1 && scaleDisciplinaryEventCount <= 50000);

const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrationNames.length, 152);
assert.deepEqual(migrationNames.slice(-5), [
  "20260826014905_referee_assignment_private_beta_schema_v1.sql",
  "20260826014910_referee_assignment_private_beta_authority_v1.sql",
  "20260826014916_referee_match_officiating_commands_v1.sql",
  "20260826014920_referee_assignment_private_beta_access_v1.sql",
  "20260826105132_referee_assignment_fk_index_hardening_v1.sql",
]);

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

function runSqlFile(file, label, variables = {}) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq"];
  for (const [key, value] of Object.entries(variables)) {
    args.push("-v", `${key}=${value}`);
  }
  args.push(targetUrl(), "-f", resolve(root, file));
  return run(
    psqlBin,
    args,
    label,
  );
}

function parseReport(output, prefix) {
  const reportLine = output.split("\n").map((line) => line.trim())
    .find((line) => line.startsWith(prefix));
  assert.ok(reportLine, `${prefix} report missing: ${output}`);
  return JSON.parse(reportLine.slice(prefix.length));
}

function dropDatabase() {
  const exists = Number(admin(
    `select count(*) from pg_database where datname=${quote(databaseName)}`,
    "inspect Wave 4 DB existence",
  ));
  if (exists === 0) {
    databaseDropped = true;
    return;
  }
  admin(`alter database ${databaseName} with allow_connections false`, "close Wave 4 DB");
  admin(
    `select pg_terminate_backend(activity.pid)
       from pg_stat_activity activity
      where activity.datname=${quote(databaseName)}
        and activity.pid<>pg_backend_pid()`,
    "terminate Wave 4 DB sessions",
  );
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      "inspect Wave 4 DB sessions",
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`WAVE4_DB_CLEANUP_CONNECTIONS_REMAIN:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, "drop Wave 4 DB");
  databaseDropped = true;
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Wave 4 DB");
  run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), "-f", infrastructureDump], "restore Supabase infrastructure");
  query("create publication supabase_realtime;", "create Wave 4 Realtime publication");

  apply([
    resolve(root, manifest.baselinePath),
    ...migrationNames
      .filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => resolve(root, "supabase/migrations", name)),
  ], "install exact 152-migration Wave 4 ledger");

  const defaultState = JSON.parse(query(`
    select jsonb_build_object(
      'assignments', settings.referee_assignments_enabled,
      'privateBeta', settings.referee_assignment_private_beta_enabled,
      'rows', (select count(*) from public.pachanga_referee_assignments),
      'directAuthenticatedWrite', has_table_privilege(
        'authenticated', 'public.pachanga_referee_assignments', 'INSERT,UPDATE,DELETE'
      )
    )::text
    from private.pachanga_referee_foundation_settings settings where settings.singleton;
  `, "verify inert Wave 4 install"));
  assert.deepEqual(defaultState, {
    assignments: false,
    directAuthenticatedWrite: false,
    privateBeta: false,
    rows: 0,
  });

  if (scaleMode) {
    const scaleStartedAt = Date.now();
    const orchestratorCpuStartedAt = process.cpuUsage();

    runSqlFile("tests/referee-platform-v1-scale.sql", "R3 minimum scale corpus with rollback");
    const r3Rollback = JSON.parse(query(`
      select jsonb_build_object(
        'profiles', (select count(*) from public.pachanga_referee_profiles where slug like 'r3-scale-referee-%'),
        'assignments', (select count(*) from public.pachanga_referee_assignments where server_sequence between 1070000001 and 1070100000),
        'relationships', (select count(*) from public.pachanga_club_referee_relationships where server_sequence between 1050000001 and 1050020000),
        'availabilityWindows', (select count(*) from public.pachanga_referee_availability_windows where server_sequence between 1030000001 and 1030100000)
      )::text;
    `, "verify R3 scale rollback"));
    assert.deepEqual(r3Rollback, {
      assignments: 0,
      availabilityWindows: 0,
      profiles: 0,
      relationships: 0,
    });

    runSqlFile("tests/referee-assignments-private-beta-v1-fixture.sql", "load Wave 4 scale fixture");
    const output = runSqlFile(
      "tests/referee-assignments-private-beta-v1-scale.sql",
      "Wave 4 assignment reconciliation and R5 scale rollback",
      {
        assignment_count: scaleAssignmentCount,
        disciplinary_event_count: scaleDisciplinaryEventCount,
      },
    );
    const report = parseReport(output, "WAVE4_SCALE_REPORT|");
    assert.deepEqual({
      assignmentReconciliations: report.assignmentReconciliations,
      profiles: report.profiles,
      r5LinkedEvents: report.r5LinkedEvents,
    }, {
      assignmentReconciliations: scaleAssignmentCount,
      profiles: 10000,
      r5LinkedEvents: scaleDisciplinaryEventCount,
    });
    assert.ok(report.reconcileDurationMs < 600000, "10,000 reconciliations exceeded 600 seconds");
    assert.ok(report.r5InsertDurationMs < 180000, "50,000 R5 inserts exceeded 180 seconds");
    assert.ok(report.r5RebuildDurationMs < 180000, "R5 statistics rebuild exceeded 180 seconds");
    assert.ok(report.assignmentIndexBytes > 0);
    assert.ok(report.disciplineIndexBytes > 0);
    assert.ok(report.locksHeldAtReport > 0);

    const wave4Corpus = JSON.parse(query(`
      select jsonb_build_object(
        'users', (select count(*) from auth.users where email like 'w4-scale-referee-%@example.test'),
        'profiles', (select count(*) from public.pachanga_referee_profiles where slug like 'w4-scale-referee-%'),
        'assignments', (select count(*) from public.pachanga_referee_assignments where proposal_message = 'W4 scale confirmed assignment'),
        'anchorAssignments', (select count(*) from public.pachanga_referee_assignments where id = 'd604ffff-0000-4000-8000-000000000001'),
        'disciplinaryEvents', (select count(*) from public.pachanga_competition_disciplinary_events where server_sequence between 2300000001 and 2300000000 + ${scaleDisciplinaryEventCount}),
        'disciplinaryRevisions', (select count(*) from public.pachanga_competition_disciplinary_event_revisions where server_sequence between 2400000001 and 2400000000 + ${scaleDisciplinaryEventCount}),
        'receipts', (select count(*) from private.pachanga_referee_operation_receipts where client_metadata ->> 'surface' = 'wave4_scale')
      )::text;
    `, "verify Wave 4 scale corpus before teardown"));
    assert.deepEqual(wave4Corpus, {
      anchorAssignments: 1,
      assignments: scaleAssignmentCount,
      disciplinaryEvents: scaleDisciplinaryEventCount,
      disciplinaryRevisions: scaleDisciplinaryEventCount,
      profiles: 10000,
      receipts: scaleAssignmentCount,
      users: 10000,
    });

    const orchestratorCpu = process.cpuUsage(orchestratorCpuStartedAt);
    dropDatabase();
    const temporaryDatabaseCount = Number(admin(
      `select count(*) from pg_database where datname=${quote(databaseName)}`,
      "verify Wave 4 scale database teardown",
    ));
    assert.equal(temporaryDatabaseCount, 0);
    process.stdout.write(`${JSON.stringify({
      database: "temporary",
      migrations: migrationNames.length,
      flagsDefaultOff: true,
      minimumCorpus: {
        assignments: 100000,
        availabilityWindows: 100000,
        profiles: 10000,
        refereeClubRelationships: 20000,
      },
      report,
      rollback: {
        r3: r3Rollback,
        wave4TemporaryDatabaseDropped: temporaryDatabaseCount === 0,
      },
      runnerWallMs: Date.now() - scaleStartedAt,
      orchestratorCpuMs: Math.round((orchestratorCpu.user + orchestratorCpu.system) / 1000),
    })}\n`);
  } else {
    runSqlFile("tests/referee-assignments-private-beta-v1-fixture.sql", "load Wave 4 fixture");
    const output = runSqlFile(
      "tests/referee-assignments-private-beta-v1-db.sql",
      "Wave 4 SQL, RLS and idempotency suite",
    );
    const report = parseReport(output, "WAVE4_DB_REPORT|");
    assert.equal(report.invariants, "IDENTICAL");
    assert.equal(report.oneMainReferee, true);
    assert.equal(report.replacementSafe, true);

    process.stdout.write(`${JSON.stringify({
      database: "temporary",
      migrations: migrationNames.length,
      flagsDefaultOff: true,
      sqlRlsIdempotency: "PASS",
      report,
    })}\n`);
  }
} finally {
  if (!databaseDropped) dropDatabase();
  rmSync(infrastructureDump, { force: true });
}
