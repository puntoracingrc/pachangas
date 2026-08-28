import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const databaseUrl = process.env.PUBLIC_COMPETITIONS_STAGING_DATABASE_URL;
const projectRef = process.env.PUBLIC_COMPETITIONS_STAGING_PROJECT_REF;
const confirmation = process.env.PUBLIC_COMPETITIONS_STAGING_CONFIRM;
const productionRef = "qonbngfrnrqgmxbdfbea";
const expectedProjectRef = "cvoeasffqzpnbcnbgssn";
const expectedInitialLedger = 10;
const expectedInitialLastMigration = "20260728191429";
const expectedSchemaHash = "7273cef0f24cc4881179475c81c7196dde8d084c9af39316ecf250a33e8e708d";
const expectedInitialExtensions = [
  "pg_net",
  "pg_stat_statements",
  "pgcrypto",
  "plpgsql",
  "supabase_vault",
  "uuid-ossp",
];
const expectedFinalExtensions = ["btree_gist", ...expectedInitialExtensions];
const temporaryDirectory = mkdtempSync(resolve(tmpdir(), "pachangas-wave7a-staging-bootstrap-"));
const waveMigrations = [
  "20260828072045_tournament_knockout_fk_index_hardening_v1.sql",
  "20260828072047_public_competition_publication_consent_v1.sql",
  "20260828072048_competition_registration_requests_waitlist_v1.sql",
  "20260828072049_public_competition_read_models_directory_v1.sql",
  "20260828072051_public_competition_commands_authority_v1.sql",
  "20260828072052_public_competition_access_realtime_v1.sql",
  "20260828072053_public_competition_product_flags_hardening_v1.sql",
];

if (!databaseUrl) throw new Error("PUBLIC_COMPETITIONS_STAGING_DATABASE_URL_REQUIRED");
if (!projectRef) throw new Error("PUBLIC_COMPETITIONS_STAGING_PROJECT_REF_REQUIRED");
if (confirmation !== "PUBLIC_COMPETITIONS_STAGING_ONLY") {
  throw new Error("PUBLIC_COMPETITIONS_STAGING_CONFIRMATION_REQUIRED");
}

const parsedUrl = new URL(databaseUrl);
const databaseUser = decodeURIComponent(parsedUrl.username);
if (
  !["postgres:", "postgresql:"].includes(parsedUrl.protocol)
  || !parsedUrl.hostname.endsWith(".pooler.supabase.com")
  || parsedUrl.pathname !== "/postgres"
  || projectRef !== expectedProjectRef
  || projectRef === productionRef
  || !databaseUser.endsWith(`.${projectRef}`)
  || databaseUser.includes(productionRef)
) {
  throw new Error("PUBLIC_COMPETITIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 183);
assert.deepEqual(migrations.slice(-waveMigrations.length), waveMigrations);

const preWaveMigrations = migrations.slice(0, -waveMigrations.length);
const absorbedMigrationFiles = migrations.filter((name) => (
  manifest.absorbedMigrations.includes(name.slice(0, 14))
));
const preWaveIncremental = preWaveMigrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough);
const explicitTransactionMigrations = preWaveIncremental.filter((name) => (
  /^\s*begin\s*;/im.test(readFileSync(resolve(root, "supabase/migrations", name), "utf8"))
));
assert.equal(preWaveMigrations.length, 176);
assert.deepEqual(absorbedMigrationFiles.map((name) => name.slice(0, 14)), manifest.absorbedMigrations);
assert.equal(preWaveIncremental.length + manifest.absorbedMigrations.length, 176);
assert.deepEqual(explicitTransactionMigrations, [
  "20260828045324_tournament_knockout_flag_authority_compatibility_v1.sql",
]);

const baselineContents = readFileSync(resolve(root, manifest.baselinePath));
assert.equal(createHash("sha256").update(baselineContents).digest("hex"), manifest.sha256);

function run(binary, args, label, options = {}) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=900s",
    },
    maxBuffer: 512 * 1024 * 1024,
    ...options,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function query(sql, label) {
  return run("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl, "-c", sql,
  ], label);
}

function apply(files, label, singleTransaction = true) {
  const args = ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q"];
  if (singleTransaction) args.push("--single-transaction");
  args.push(databaseUrl);
  for (const file of files) args.push("-f", file);
  run("psql", args, label);
}

function ledgerSql(names) {
  const rows = names.map((name) => {
    const version = name.slice(0, 14);
    const migrationName = name.slice(15, -4).replaceAll("'", "''");
    return `('${version}', array[]::text[], '${migrationName}')`;
  }).join(",\n");
  return `
insert into supabase_migrations.schema_migrations(version, statements, name)
values ${rows}
on conflict (version) do update
set statements=excluded.statements, name=excluded.name;
`;
}

function writeLedger(name, migrationNames) {
  const path = resolve(temporaryDirectory, name);
  writeFileSync(path, ledgerSql(migrationNames), "utf8");
  return path;
}

function infrastructureReadback() {
  return JSON.parse(query(`
    select jsonb_build_object(
      'authRelations', (
        select count(*) from pg_class classes
        join pg_namespace namespaces on namespaces.oid=classes.relnamespace
        where namespaces.nspname='auth' and classes.relkind in ('r','p','v','m','S')
      ),
      'storageRelations', (
        select count(*) from pg_class classes
        join pg_namespace namespaces on namespaces.oid=classes.relnamespace
        where namespaces.nspname='storage' and classes.relkind in ('r','p','v','m','S')
      ),
      'realtimeRelations', (
        select count(*) from pg_class classes
        join pg_namespace namespaces on namespaces.oid=classes.relnamespace
        where namespaces.nspname='realtime' and classes.relkind in ('r','p','v','m','S')
      ),
      'extensions', (
        select jsonb_agg(extensions.extname order by extensions.extname)
        from pg_extension extensions
      ),
      'publicSchemaOwner', (
        select pg_get_userbyid(namespaces.nspowner)
        from pg_namespace namespaces where namespaces.nspname='public'
      ),
      'publicSchemaAcl', (
        select namespaces.nspacl::text
        from pg_namespace namespaces where namespaces.nspname='public'
      ),
      'publicDefaultAcl', (
        select jsonb_agg(jsonb_build_object(
          'role', pg_get_userbyid(defaults.defaclrole),
          'objectType', defaults.defaclobjtype::text,
          'acl', defaults.defaclacl::text
        ) order by pg_get_userbyid(defaults.defaclrole), defaults.defaclobjtype::text)
        from pg_default_acl defaults
        join pg_namespace namespaces on namespaces.oid=defaults.defaclnamespace
        where namespaces.nspname='public'
      ),
      'authUsers', (select count(*) from auth.users),
      'storageObjects', (select count(*) from storage.objects)
    )::text;
  `, "read managed infrastructure"));
}

function stagingReadback() {
  return JSON.parse(query(`
    select jsonb_build_object(
      'database', current_database(),
      'databaseUser', current_user,
      'ledgerCount', (select count(*) from supabase_migrations.schema_migrations),
      'ledgerMax', (select max(version) from supabase_migrations.schema_migrations),
      'publicObjects', (
        select coalesce(jsonb_agg(
          jsonb_build_object('kind', classes.relkind::text, 'name', classes.relname)
          order by classes.relname
        ), '[]'::jsonb)
        from pg_class classes
        join pg_namespace namespaces on namespaces.oid=classes.relnamespace
        where namespaces.nspname='public' and classes.relkind in ('r','p','v','m','S')
      ),
      'publicRoutines', (
        select coalesce(jsonb_agg(
          jsonb_build_object('kind', routines.prokind::text, 'name', routines.oid::regprocedure::text)
          order by routines.oid::regprocedure::text
        ), '[]'::jsonb)
        from pg_proc routines
        join pg_namespace namespaces on namespaces.oid=routines.pronamespace
        where namespaces.nspname='public'
      ),
      'privateSchema', to_regnamespace('private') is not null,
      'simulationSchema', to_regnamespace('simulation') is not null,
      'outsideClassDependencies', (
        select count(*)
        from pg_depend dependencies
        join pg_class sources on sources.oid=dependencies.objid
        join pg_namespace source_namespaces on source_namespaces.oid=sources.relnamespace
        join pg_class targets on targets.oid=dependencies.refobjid
        join pg_namespace target_namespaces on target_namespaces.oid=targets.relnamespace
        where target_namespaces.nspname='public'
          and source_namespaces.nspname not in ('public','pg_toast')
      ),
      'realtimePublicationTables', (
        select coalesce(jsonb_agg(
          format('%I.%I', publication_tables.schemaname, publication_tables.tablename)
          order by publication_tables.schemaname, publication_tables.tablename
        ), '[]'::jsonb)
        from pg_publication_tables publication_tables
        where publication_tables.pubname='supabase_realtime'
      )
    )::text;
  `, "read staging bootstrap target"));
}

function normalizedSchema() {
  return run("pg_dump", [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--schema=public", "--schema=private", "--schema=simulation", databaseUrl,
  ], "export staging product schema")
    .split("\n")
    .filter((line) => !/^--|^\\(?:un)?restrict\b/.test(line))
    .join("\n")
    .trim();
}

function verifyLedger(expectedCount, expectedLastMigration, label) {
  const ledger = JSON.parse(query(`
    select jsonb_build_object(
      'count', count(*),
      'lastMigration', max(version),
      'duplicateVersions', count(*) - count(distinct version)
    )::text
    from supabase_migrations.schema_migrations;
  `, label));
  assert.deepEqual(ledger, {
    count: expectedCount,
    duplicateVersions: 0,
    lastMigration: expectedLastMigration,
  });
  return ledger;
}

function verifyLedgerPrefix() {
  const prefix = JSON.parse(query(`
    select jsonb_build_object(
      'count', count(*),
      'lastMigration', max(version),
      'duplicateVersions', count(*) - count(distinct version)
    )::text
    from supabase_migrations.schema_migrations
    where version <= '20260828045324';
  `, "verify exact Wave 7A base ledger prefix"));
  assert.deepEqual(prefix, {
    count: 176,
    duplicateVersions: 0,
    lastMigration: "20260828045324",
  });
  return prefix;
}

function ledgerEntries() {
  return JSON.parse(query(`
    select coalesce(jsonb_agg(
      migrations.version || '|' || coalesce(migrations.name, '')
      order by migrations.version
    ), '[]'::jsonb)::text
    from supabase_migrations.schema_migrations migrations;
  `, "read exact staging migration ledger"));
}

function expectedLedgerEntries() {
  return migrations.map((name) => `${name.slice(0, 14)}|${name.slice(15, -4)}`);
}

function withoutExtensions(readback) {
  const copy = { ...readback };
  delete copy.extensions;
  return copy;
}

try {
  const initialInfrastructure = infrastructureReadback();
  const initial = stagingReadback();
  assert.equal(initial.database, "postgres");
  assert.equal(initial.databaseUser, "postgres");
  assert.equal(initialInfrastructure.authUsers, 0);
  assert.equal(initialInfrastructure.storageObjects, 0);
  const alreadyBootstrapped = initial.ledgerCount === 183
    && initial.ledgerMax === "20260828072053";
  assert.ok(
    alreadyBootstrapped || (
      initial.ledgerCount === expectedInitialLedger
      && initial.ledgerMax === expectedInitialLastMigration
    ),
    "staging branch must be either the known ten-migration seed or exact Wave 7A ledger",
  );

  let baseLedger;
  let reconciledLedgerNames = false;
  if (!alreadyBootstrapped) {
    assert.deepEqual(initialInfrastructure.extensions, expectedInitialExtensions);
    assert.deepEqual(initial.publicObjects, [
      { kind: "r", name: "pachanga_group_backups" },
      { kind: "r", name: "pachanga_group_members" },
      { kind: "r", name: "pachanga_groups" },
    ]);
    assert.deepEqual(initial.publicRoutines.map((routine) => routine.name), [
      "append_pachanga_player_rating(uuid,text,jsonb)",
      "create_pachanga_group_backup(uuid,text,jsonb)",
      "is_pachanga_group_admin(uuid)",
      "is_pachanga_group_member(uuid)",
      "is_pachanga_group_owner(uuid)",
      "join_pachanga_group(uuid)",
      "join_pachanga_team(uuid,text)",
      "new_pachanga_team_code()",
      "patch_pachanga_match_player_paid(uuid,text,text,boolean)",
      "patch_pachanga_match_player_status(uuid,text,text,text)",
      "patch_pachanga_match_scorers(uuid,text,integer,integer,jsonb,text[],text[])",
      "patch_pachanga_player_profile(uuid,text,jsonb)",
      "restore_pachanga_group_backup(uuid)",
      "save_pachanga_payload_if_current(uuid,bigint,jsonb)",
      "set_updated_at()",
      "update_pachanga_member_name(uuid,text)",
    ]);
    assert.equal(initial.privateSchema, false);
    assert.equal(initial.simulationSchema, false);
    assert.equal(initial.outsideClassDependencies, 0);
    assert.deepEqual(initial.realtimePublicationTables, ["public.pachanga_groups"]);

    query(`
    begin;
    set local lock_timeout='5s';
    set local statement_timeout='60s';
    drop schema if exists simulation cascade;
    drop schema if exists private cascade;
    drop table public.pachanga_group_backups,
      public.pachanga_group_members,
      public.pachanga_groups cascade;
    do $reset$
    declare routine record;
    begin
      for routine in
        select procedures.prokind, procedures.oid::regprocedure::text as signature
        from pg_proc procedures
        join pg_namespace namespaces on namespaces.oid=procedures.pronamespace
        where namespaces.nspname='public'
      loop
        execute format(
          'drop %s if exists %s cascade',
          case when routine.prokind='p' then 'procedure' else 'function' end,
          routine.signature
        );
      end loop;
    end;
    $reset$;
    delete from supabase_migrations.schema_migrations;
    do $verify$
    begin
      if exists (
        select 1 from pg_class classes
        join pg_namespace namespaces on namespaces.oid=classes.relnamespace
        where namespaces.nspname='public' and classes.relkind in ('r','p','v','m','S','f')
      ) or exists (
        select 1 from pg_proc procedures
        join pg_namespace namespaces on namespaces.oid=procedures.pronamespace
        where namespaces.nspname='public'
      ) then
        raise exception 'PUBLIC_COMPETITIONS_STAGING_PRODUCT_RESET_INCOMPLETE';
      end if;
    end;
    $verify$;
    commit;
    `, "reset isolated staging product schemas");

    const absorbedLedger = writeLedger(
      "absorbed-ledger.sql",
      absorbedMigrationFiles,
    );
    apply([
      resolve(root, manifest.baselinePath),
      absorbedLedger,
    ], "install canonical product baseline");

    const explicitMigration = explicitTransactionMigrations[0];
    const regularPreWaveMigrations = preWaveIncremental.filter((name) => name !== explicitMigration);
    const preWaveLedger = writeLedger("pre-wave-ledger.sql", regularPreWaveMigrations);
    apply([
      ...regularPreWaveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
      preWaveLedger,
    ], "install canonical migrations through R6C compatibility");

    apply([resolve(root, "supabase/migrations", explicitMigration)],
      "install final explicit-transaction R6C compatibility migration", false);
    query(ledgerSql([explicitMigration]), "record final R6C migration");

    baseLedger = verifyLedger(176, "20260828045324", "verify exact Wave 7A base ledger");
    assert.equal(query(
      "select to_regclass('public.pachanga_competition_publications') is null",
      "verify Wave 7A objects absent at base",
    ), "t");

    const waveLedger = writeLedger("wave-ledger.sql", waveMigrations);
    apply([
      ...waveMigrations.map((name) => resolve(root, "supabase/migrations", name)),
      waveLedger,
    ], "apply exact Wave 7A migrations");
  } else {
    baseLedger = verifyLedgerPrefix();
    const currentEntries = ledgerEntries();
    const expectedEntries = expectedLedgerEntries();
    const currentVersions = currentEntries.map((entry) => entry.slice(0, 14));
    const expectedVersions = expectedEntries.map((entry) => entry.slice(0, 14));
    assert.deepEqual(currentVersions, expectedVersions);
    const mismatches = currentEntries
      .map((entry, index) => ({ actual: entry, expected: expectedEntries[index], index }))
      .filter(({ actual, expected }) => actual !== expected);
    if (mismatches.length > 0) {
      assert.equal(mismatches.length, absorbedMigrationFiles.length);
      assert.ok(mismatches.every(({ actual, index }) => (
        index < absorbedMigrationFiles.length && actual.endsWith("|absorbed_by_product_baseline")
      )));
      query(ledgerSql(absorbedMigrationFiles), "reconcile absorbed staging migration names");
      reconciledLedgerNames = true;
    }
  }

  const finalLedger = verifyLedger(183, "20260828072053", "verify final Wave 7A ledger");
  assert.deepEqual(ledgerEntries(), expectedLedgerEntries());
  const finalInfrastructure = infrastructureReadback();
  assert.deepEqual(finalInfrastructure.extensions, expectedFinalExtensions);
  if (!alreadyBootstrapped) {
    assert.deepEqual(withoutExtensions(finalInfrastructure), withoutExtensions(initialInfrastructure));
  }

  const flags = JSON.parse(query(`
    select jsonb_build_object(
      'foundation', public_competition_foundation_enabled,
      'publication', public_competition_publication_enabled,
      'discovery', public_competition_discovery_enabled,
      'registrationRequests', public_competition_registration_requests_enabled,
      'waitlist', public_competition_waitlist_enabled,
      'calendar', public_competition_calendar_enabled,
      'results', public_competition_results_enabled,
      'standings', public_competition_standings_enabled,
      'bracket', public_competition_bracket_enabled,
      'exceptionStatus', public_competition_exception_status_enabled,
      'referees', public_competition_referee_display_enabled,
      'discipline', public_competition_discipline_enabled,
      'autoAccept', public_competition_auto_accept_enabled
    )::text
    from private.pachanga_competition_foundation_settings
    where singleton;
  `, "verify Wave 7A flags install OFF"));
  assert.deepEqual(flags, {
    autoAccept: false,
    bracket: false,
    calendar: false,
    discipline: false,
    discovery: false,
    exceptionStatus: false,
    foundation: false,
    publication: false,
    referees: false,
    registrationRequests: false,
    results: false,
    standings: false,
    waitlist: false,
  });

  const schemaHash = createHash("sha256").update(normalizedSchema()).digest("hex");
  assert.equal(schemaHash, expectedSchemaHash, "staging product schema must match the locally certified schema");

  process.stdout.write(`${JSON.stringify({
    baseLedger,
    finalLedger,
    flagsDefaultOff: true,
    managedInfrastructurePreserved: true,
    mode: alreadyBootstrapped
      ? (reconciledLedgerNames ? "RECONCILE_AND_VERIFY" : "VERIFY_ONLY")
      : "BOOTSTRAP_AND_VERIFY",
    reconciledLedgerNames,
    projectRef,
    schemaHash,
    status: "PUBLIC_COMPETITIONS_STAGING_BOOTSTRAP_OK",
  })}\n`);
} finally {
  rmSync(temporaryDirectory, { force: true, recursive: true });
}
