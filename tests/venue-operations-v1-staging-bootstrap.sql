\set ON_ERROR_STOP on

-- Staging-only dependency bootstrap. Product guards are restored before any
-- Wave 9A command or read model is exercised.
begin;

delete from auth.users
where id in (
  'e9010000-0000-4000-8000-000000000001',
  'e9010000-0000-4000-8000-000000000002',
  'e9010000-0000-4000-8000-000000000003',
  'e9010000-0000-4000-8000-000000000004',
  'e9010000-0000-4000-8000-000000000005'
);

set local session_replication_role = replica;
\ir venue-operations-v1-fixture.sql
set local session_replication_role = origin;

\ir venue-operations-v1-db.sql

commit;

select 'VENUE_OPERATIONS_V1_STAGING_BOOTSTRAP_PASS';
