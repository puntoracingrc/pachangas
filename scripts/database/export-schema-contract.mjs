#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const databaseUrl = readDatabaseUrl(process.argv.slice(2));
assertLocalDatabaseUrl(databaseUrl);

const sql = `
with
relations as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', n.nspname,
    'name', c.relname,
    'kind', c.relkind,
    'rls', c.relrowsecurity,
    'forceRls', c.relforcerowsecurity,
    'acl', coalesce(c.relacl::text, '')
  ) order by n.nspname, c.relname), '[]'::jsonb) value
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm', 'S')
),
columns as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', table_schema,
    'table', table_name,
    'position', ordinal_position,
    'name', column_name,
    'type', data_type,
    'udt', udt_schema || '.' || udt_name,
    'nullable', is_nullable,
    'default', coalesce(column_default, ''),
    'generated', is_generated,
    'identity', is_identity
  ) order by table_schema, table_name, ordinal_position), '[]'::jsonb) value
  from information_schema.columns
  where table_schema in ('public', 'private')
),
constraints as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', n.nspname,
    'table', coalesce(c.relname, ''),
    'name', x.conname,
    'type', x.contype,
    'definition', pg_get_constraintdef(x.oid, true)
  ) order by n.nspname, coalesce(c.relname, ''), x.conname), '[]'::jsonb) value
  from pg_constraint x
  join pg_namespace n on n.oid = x.connamespace
  left join pg_class c on c.oid = x.conrelid
  where n.nspname in ('public', 'private')
),
indexes as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', schemaname,
    'table', tablename,
    'name', indexname,
    'definition', indexdef
  ) order by schemaname, tablename, indexname), '[]'::jsonb) value
  from pg_indexes where schemaname in ('public', 'private')
),
policies as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', schemaname,
    'table', tablename,
    'name', policyname,
    'permissive', permissive,
    'roles', roles,
    'command', cmd,
    'using', coalesce(qual, ''),
    'check', coalesce(with_check, '')
  ) order by schemaname, tablename, policyname), '[]'::jsonb) value
  from pg_policies where schemaname in ('public', 'private')
),
functions as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', n.nspname,
    'name', p.proname,
    'identityArguments', pg_get_function_identity_arguments(p.oid),
    'result', pg_get_function_result(p.oid),
    'securityDefiner', p.prosecdef,
    'volatility', p.provolatile,
    'acl', coalesce(p.proacl::text, ''),
    'definition', pg_get_functiondef(p.oid)
  ) order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)), '[]'::jsonb) value
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
),
triggers as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', n.nspname,
    'table', c.relname,
    'name', t.tgname,
    'definition', pg_get_triggerdef(t.oid, true)
  ) order by n.nspname, c.relname, t.tgname), '[]'::jsonb) value
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and not t.tgisinternal
),
schemas as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'schema', nspname,
    'acl', coalesce(nspacl::text, '')
  ) order by nspname), '[]'::jsonb) value
  from pg_namespace where nspname in ('public', 'private')
),
publication_tables as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'publication', pubname,
    'schema', schemaname,
    'table', tablename
  ) order by pubname, schemaname, tablename), '[]'::jsonb) value
  from pg_publication_tables where schemaname in ('public', 'private')
)
select jsonb_pretty(jsonb_build_object(
  'relations', relations.value,
  'columns', columns.value,
  'constraints', constraints.value,
  'indexes', indexes.value,
  'policies', policies.value,
  'functions', functions.value,
  'triggers', triggers.value,
  'schemas', schemas.value,
  'publicationTables', publication_tables.value
))
from relations, columns, constraints, indexes, policies, functions, triggers, schemas, publication_tables;
`;

const result = spawnSync("psql", ["-X", "--tuples-only", "--no-align", databaseUrl, "--command", sql], {
  encoding: "utf8",
  maxBuffer: 128 * 1024 * 1024,
});
if (result.error) throw result.error;
if (result.status !== 0) throw new Error(result.stderr || `psql failed with exit ${result.status}`);
process.stdout.write(result.stdout.trimStart());

function readDatabaseUrl(args) {
  const flagIndex = args.indexOf("--db-url");
  const value = flagIndex >= 0 ? args[flagIndex + 1] : process.env.PACHANGAS_SCHEMA_DATABASE_URL;
  if (!value) throw new Error("PACHANGAS_SCHEMA_DATABASE_URL_OR_DB_URL_REQUIRED");
  return value;
}

function assertLocalDatabaseUrl(value) {
  const parsed = new URL(value);
  if (!["postgres:", "postgresql:"].includes(parsed.protocol)) throw new Error("SCHEMA_POSTGRES_URL_REQUIRED");
  if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(parsed.hostname)) {
    throw new Error("SCHEMA_LOCAL_DATABASE_REQUIRED");
  }
}
