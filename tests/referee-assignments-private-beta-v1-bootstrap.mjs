import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
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
const suffix = randomBytes(5).toString("hex");
const databaseNames = {
  fresh: `pachangas_wave4_bootstrap_fresh_${suffix}`,
  upgrade: `pachangas_wave4_bootstrap_upgrade_${suffix}`,
};
const infrastructureDump = resolve(tmpdir(), `pachangas-wave4-bootstrap-infrastructure-${suffix}.sql`);
const schemaDumps = {
  fresh: resolve(tmpdir(), `pachangas-wave4-bootstrap-fresh-${suffix}.sql`),
  upgrade: resolve(tmpdir(), `pachangas-wave4-bootstrap-upgrade-${suffix}.sql`),
};
const wave4Migrations = [
  "20260826014905_referee_assignment_private_beta_schema_v1.sql",
  "20260826014910_referee_assignment_private_beta_authority_v1.sql",
  "20260826014916_referee_match_officiating_commands_v1.sql",
  "20260826014920_referee_assignment_private_beta_access_v1.sql",
];
const migrationNames = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
const incrementalMigrations = migrationNames.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const preWave4Migrations = migrationNames.slice(0, -wave4Migrations.length);
const preWave4Incremental = preWave4Migrations
  .filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const createdDatabases = new Set();

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("WAVE4_BOOTSTRAP_LOCAL_DATABASE_REQUIRED");
}
assert.equal(migrationNames.length, 151);
assert.equal(preWave4Migrations.length, 147);
assert.deepEqual(migrationNames.slice(-4), wave4Migrations);

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

function databaseUrl(databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(databaseName, sql, label) {
  return run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl(databaseName), "-c", sql],
    label,
  );
}

function apply(databaseName, files, label) {
  const args = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction", databaseUrl(databaseName),
  ];
  for (const file of files) args.push("-f", file);
  run(psqlBin, args, label);
}

function recordLedger(databaseName, names, label) {
  const values = names.map((name) => (
    `(${quote(name.slice(0, 14))}, array[]::text[], ${quote(name.slice(15, -4))})`
  )).join(",\n");
  query(databaseName, `
    insert into supabase_migrations.schema_migrations(version, statements, name)
    values ${values}
    on conflict (version) do update
      set statements = excluded.statements, name = excluded.name;
  `, label);
}

function createDatabase(databaseName) {
  admin(`create database ${databaseName} template template0`, `create ${databaseName}`);
  createdDatabases.add(databaseName);
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", databaseUrl(databaseName), "-f", infrastructureDump],
    `restore Supabase infrastructure in ${databaseName}`,
  );
  query(databaseName, "create publication supabase_realtime;", `create Realtime publication in ${databaseName}`);
}

function dropDatabase(databaseName) {
  const exists = Number(admin(
    `select count(*) from pg_database where datname=${quote(databaseName)}`,
    `inspect ${databaseName}`,
  ));
  if (exists === 0) {
    createdDatabases.delete(databaseName);
    return;
  }
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(`
    select pg_terminate_backend(activity.pid)
    from pg_stat_activity activity
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid();
  `, `terminate sessions in ${databaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      `inspect sessions in ${databaseName}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) throw new Error(`WAVE4_BOOTSTRAP_CLEANUP_CONNECTIONS_REMAIN:${databaseName}:${connections}`);
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  createdDatabases.delete(databaseName);
}

function protectedCounts(databaseName, label) {
  return JSON.parse(query(databaseName, `
    select jsonb_build_object(
      'ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots),
      'assessments', (select count(*) from public.pachanga_player_assessments),
      'rewardGrants', (select count(*) from public.pachanga_reward_grants),
      'conductReports', (select count(*) from private.pachanga_conduct_reports),
      'stripeWebhookEvents', (select count(*) from public.pachanga_stripe_webhook_events)
    )::text;
  `, label));
}

function seedPreWave4Assignment(databaseName) {
  query(databaseName, `
    begin;
    set local session_replication_role = replica;
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    values
      ('d6100000-0000-4000-8000-000000000001', 'wave4-upgrade-owner@example.test', clock_timestamp(), '{"full_name":"Wave 4 Upgrade Owner"}'::jsonb),
      ('d6100000-0000-4000-8000-000000000002', 'wave4-upgrade-referee@example.test', clock_timestamp(), '{"full_name":"Wave 4 Upgrade Referee"}'::jsonb);
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    values (
      'd6100000-0000-4000-8000-000000000010',
      'd6100000-0000-4000-8000-000000000001',
      'Wave 4 Upgrade Team',
      'W4UPGRADE',
      '{"matches":[{"id":"wave4-upgrade-match","date":"2031-01-01T19:00:00Z","kind":"futbol7"}],"players":[],"siteSettings":{"timezone":"Europe/Madrid"},"venues":[]}'::jsonb,
      7
    );
    insert into public.pachanga_group_members(group_id, user_id, role, display_name)
    values (
      'd6100000-0000-4000-8000-000000000010',
      'd6100000-0000-4000-8000-000000000001',
      'owner',
      'Wave 4 Upgrade Owner'
    );
    insert into public.pachanga_canonical_matches(id, created_by)
    values ('d6100000-0000-4000-8000-000000000020', 'd6100000-0000-4000-8000-000000000001');
    insert into public.pachanga_canonical_match_bindings(
      id, canonical_match_id, source_kind, source_group_id, source_id, relation_kind, created_by
    ) values (
      'd6100000-0000-4000-8000-000000000021',
      'd6100000-0000-4000-8000-000000000020',
      'group_match',
      'd6100000-0000-4000-8000-000000000010',
      'wave4-upgrade-match',
      'authoritative_source',
      'd6100000-0000-4000-8000-000000000001'
    );
    insert into public.pachanga_referee_profiles(
      id, user_id, slug, public_display_name_snapshot, bio, operational_status,
      visibility, availability_status, available_for_assignments
    ) values (
      'd6100000-0000-4000-8000-000000000030',
      'd6100000-0000-4000-8000-000000000002',
      'wave4-upgrade-referee',
      'Wave 4 Upgrade Referee',
      'Pre-Wave 4 referee assignment migration fixture.',
      'active',
      'private',
      'AVAILABLE',
      true
    );
    insert into public.pachanga_referee_assignments(
      id, referee_profile_id, canonical_match_id, assignment_role, requester_kind,
      requester_team_id, source_kind, source_group_id, source_id, status,
      scheduled_start, scheduled_end, timezone, schedule_source_revision,
      proposed_by, authority_used, proposal_message, response_deadline
    ) values (
      'd6100000-0000-4000-8000-000000000040',
      'd6100000-0000-4000-8000-000000000030',
      'd6100000-0000-4000-8000-000000000020',
      'MAIN_REFEREE',
      'TEAM',
      'd6100000-0000-4000-8000-000000000010',
      'group_match',
      'd6100000-0000-4000-8000-000000000010',
      'wave4-upgrade-match',
      'proposed',
      '2031-01-01T19:00:00Z',
      '2031-01-01T21:00:00Z',
      'Europe/Madrid',
      7,
      'd6100000-0000-4000-8000-000000000001',
      'team_owner',
      'Pre-Wave 4 canonical assignment',
      '2030-12-31T19:00:00Z'
    );
    commit;
  `, "seed valid pre-Wave 4 assignment");
}

function wave4Contract(databaseName, label) {
  return JSON.parse(query(databaseName, `
    select jsonb_build_object(
      'ledger', (select count(*) from supabase_migrations.schema_migrations),
      'lastMigration', (select max(version) from supabase_migrations.schema_migrations),
      'flagsOff', not exists (
        select 1 from private.pachanga_referee_foundation_settings settings
        where settings.referee_assignments_enabled or settings.referee_assignment_private_beta_enabled
      ),
      'productRows', (select count(*) from public.pachanga_referee_assignments),
      'directAuthenticatedWrite', has_table_privilege(
        'authenticated', 'public.pachanga_referee_assignments', 'INSERT,UPDATE,DELETE'
      ),
      'commandFunction', to_regprocedure(
        'public.command_pachanga_referee_assignment_beta_v1(uuid,uuid,bigint,text,jsonb,jsonb)'
      ) is not null,
      'readFunction', to_regprocedure(
        'public.get_pachanga_referee_assignment_beta_v1(uuid)'
      ) is not null,
      'termsTable', to_regclass('private.pachanga_referee_assignment_terms') is not null,
      'revisionsTable', to_regclass('public.pachanga_referee_assignment_revisions') is not null,
      'effectiveScheduleColumn', exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='pachanga_referee_assignments'
          and column_name='effective_scheduled_start' and is_nullable='NO'
      )
    )::text;
  `, label));
}

function dumpSchema(databaseName, outputPath, label) {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--schema=public", "--schema=private",
    "--file", outputPath, databaseUrl(databaseName),
  ], label);
  const normalized = readFileSync(outputPath, "utf8")
    .split("\n")
    .filter((line) => !/^\\(?:un)?restrict\s/.test(line))
    .join("\n")
    .replaceAll(databaseName, "pachangas_wave4_bootstrap");
  return {
    hash: createHash("sha256").update(normalized).digest("hex"),
    normalized,
  };
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=realtime", "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");

  createDatabase(databaseNames.fresh);
  apply(databaseNames.fresh, [
    resolve(root, manifest.baselinePath),
    ...incrementalMigrations.map((name) => resolve(root, "supabase/migrations", name)),
  ], "install fresh exact 151-migration ledger");
  recordLedger(databaseNames.fresh, migrationNames, "record fresh migration ledger");

  createDatabase(databaseNames.upgrade);
  apply(databaseNames.upgrade, [
    resolve(root, manifest.baselinePath),
    ...preWave4Incremental.map((name) => resolve(root, "supabase/migrations", name)),
  ], "install exact pre-Wave 4 147-migration ledger");
  recordLedger(databaseNames.upgrade, preWave4Migrations, "record pre-Wave 4 migration ledger");
  assert.equal(Number(query(
    databaseNames.upgrade,
    "select count(*) from supabase_migrations.schema_migrations;",
    "verify pre-Wave 4 ledger count",
  )), 147);
  seedPreWave4Assignment(databaseNames.upgrade);
  const protectedBefore = protectedCounts(databaseNames.upgrade, "capture protected domains before Wave 4");
  const assignmentBefore = JSON.parse(query(databaseNames.upgrade, `
    select jsonb_build_object(
      'id', id,
      'status', status,
      'scheduledStart', scheduled_start,
      'scheduledEnd', scheduled_end,
      'timezone', timezone,
      'scheduleRevision', schedule_source_revision,
      'canonicalMatchId', canonical_match_id,
      'sourceId', source_id,
      'revision', revision
    )::text
    from public.pachanga_referee_assignments
    where id='d6100000-0000-4000-8000-000000000040';
  `, "capture pre-Wave 4 assignment"));

  apply(
    databaseNames.upgrade,
    wave4Migrations.map((name) => resolve(root, "supabase/migrations", name)),
    "upgrade exact 147 ledger to Wave 4 151",
  );
  recordLedger(databaseNames.upgrade, wave4Migrations, "record Wave 4 migration ledger");

  const protectedAfter = protectedCounts(databaseNames.upgrade, "verify protected domains after Wave 4");
  assert.deepEqual(protectedAfter, protectedBefore);
  const assignmentAfter = JSON.parse(query(databaseNames.upgrade, `
    select jsonb_build_object(
      'id', id,
      'status', status,
      'scheduledStart', scheduled_start,
      'scheduledEnd', scheduled_end,
      'timezone', timezone,
      'scheduleRevision', schedule_source_revision,
      'canonicalMatchId', canonical_match_id,
      'sourceId', source_id,
      'revision', revision,
      'effectiveScheduledStart', effective_scheduled_start,
      'effectiveScheduledEnd', effective_scheduled_end,
      'effectiveTimezone', effective_timezone,
      'effectiveScheduleRevision', effective_schedule_revision,
      'scheduleState', schedule_state
    )::text
    from public.pachanga_referee_assignments
    where id='d6100000-0000-4000-8000-000000000040';
  `, "verify Wave 4 assignment backfill"));
  assert.deepEqual({
    canonicalMatchId: assignmentAfter.canonicalMatchId,
    id: assignmentAfter.id,
    revision: assignmentAfter.revision,
    scheduleRevision: assignmentAfter.scheduleRevision,
    scheduledEnd: assignmentAfter.scheduledEnd,
    scheduledStart: assignmentAfter.scheduledStart,
    sourceId: assignmentAfter.sourceId,
    status: assignmentAfter.status,
    timezone: assignmentAfter.timezone,
  }, assignmentBefore);
  assert.equal(assignmentAfter.effectiveScheduledStart, assignmentBefore.scheduledStart);
  assert.equal(assignmentAfter.effectiveScheduledEnd, assignmentBefore.scheduledEnd);
  assert.equal(assignmentAfter.effectiveTimezone, assignmentBefore.timezone);
  assert.equal(assignmentAfter.effectiveScheduleRevision, assignmentBefore.scheduleRevision);
  assert.equal(assignmentAfter.scheduleState, "CURRENT");

  const freshContract = wave4Contract(databaseNames.fresh, "verify fresh Wave 4 contract");
  const upgradeContract = wave4Contract(databaseNames.upgrade, "verify upgraded Wave 4 contract");
  assert.deepEqual({ ...upgradeContract, productRows: 0 }, freshContract);
  assert.deepEqual({
    commandFunction: freshContract.commandFunction,
    directAuthenticatedWrite: freshContract.directAuthenticatedWrite,
    effectiveScheduleColumn: freshContract.effectiveScheduleColumn,
    flagsOff: freshContract.flagsOff,
    lastMigration: freshContract.lastMigration,
    ledger: freshContract.ledger,
    readFunction: freshContract.readFunction,
    revisionsTable: freshContract.revisionsTable,
    termsTable: freshContract.termsTable,
  }, {
    commandFunction: true,
    directAuthenticatedWrite: false,
    effectiveScheduleColumn: true,
    flagsOff: true,
    lastMigration: "20260826014920",
    ledger: 151,
    readFunction: true,
    revisionsTable: true,
    termsTable: true,
  });

  const freshSchema = dumpSchema(databaseNames.fresh, schemaDumps.fresh, "dump fresh Wave 4 schema");
  const upgradeSchema = dumpSchema(databaseNames.upgrade, schemaDumps.upgrade, "dump upgraded Wave 4 schema");
  assert.equal(upgradeSchema.normalized, freshSchema.normalized);

  process.stdout.write(`${JSON.stringify({
    freshLedger: freshContract.ledger,
    upgradeFromLedger: 147,
    upgradedLedger: upgradeContract.ledger,
    wave4Migrations: wave4Migrations.length,
    schemaEquivalent: true,
    schemaSha256: freshSchema.hash,
    assignmentBackfill: {
      identityPreserved: true,
      effectiveSchedulePreserved: true,
      scheduleState: assignmentAfter.scheduleState,
      revisionPreserved: assignmentAfter.revision === assignmentBefore.revision,
    },
    protectedDomains: {
      rating: "IDENTICAL",
      rewards: "IDENTICAL",
      conduct: "IDENTICAL",
      billing: "IDENTICAL",
    },
    flagsDefaultOff: true,
    directAuthenticatedWrite: false,
  })}\n`);
} finally {
  for (const databaseName of [...createdDatabases]) dropDatabase(databaseName);
  for (const file of [infrastructureDump, ...Object.values(schemaDumps)]) rmSync(file, { force: true });
  const residual = Number(admin(`
    select count(*) from pg_database
    where datname in (${Object.values(databaseNames).map(quote).join(",")});
  `, "verify Wave 4 bootstrap cleanup"));
  assert.equal(residual, 0);
}
