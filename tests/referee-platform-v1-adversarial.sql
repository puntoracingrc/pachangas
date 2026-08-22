\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'REFEREE_ADVERSARIAL_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'REFEREE_ADVERSARIAL_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text,
    true
  );
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('a3110000-0000-4000-8000-000000000001', 'r3-adv-owner@example.test', clock_timestamp(), '{"full_name":"R3 Adversarial Owner"}'),
  ('a3110000-0000-4000-8000-000000000002', 'r3-adv-other@example.test', clock_timestamp(), '{"full_name":"R3 Adversarial Other"}'),
  ('a3110000-0000-4000-8000-000000000003', 'r3-adv-unverified@example.test', null, '{"full_name":"R3 Adversarial Unverified"}'),
  ('a3110000-0000-4000-8000-000000000004', 'r3-adv-platform@example.test', clock_timestamp(), '{"full_name":"R3 Adversarial Platform"}'),
  ('a3110000-0000-4000-8000-000000000005', 'r3-adv-support@example.test', clock_timestamp(), '{"full_name":"R3 Adversarial Support"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('a3110000-0000-4000-8000-000000000004', 'platform_owner', true),
  ('a3110000-0000-4000-8000-000000000005', 'support', true);

-- R3 is fail-closed while its foundation flag is disabled.
select pg_temp.actor('a3110000-0000-4000-8000-000000000001');
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000001',
    'a3130000-0000-4000-8000-000000000001',
    0,
    'profile.create',
    '{"slug":"r3-adv-owner","bio":"Perfil arbitral adversarial completo.","experienceSummary":"Experiencia local declarada."}',
    '{}'
  )
$sql$, 'REFEREE_FOUNDATION_DISABLED');

select pg_temp.actor('a3110000-0000-4000-8000-000000000004');
select public.command_pachanga_referee_platform_admin_v1(
  'a3120000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-00000000a3f3',
  1,
  'referee_flags.set',
  '{"foundationEnabled":true,"selfServiceEnabled":true,"publicProfilesEnabled":true,"marketplaceEnabled":true,"clubRelationshipsEnabled":true,"assignmentsEnabled":true,"reason":"R3 adversarial test"}',
  '{"clientVersion":"3.0.0+adversarial","surface":"sql"}'
);

-- Email verification is resolved from Auth and cannot be forged in the payload.
select pg_temp.actor('a3110000-0000-4000-8000-000000000003');
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000003',
    'a3130000-0000-4000-8000-000000000003',
    0,
    'profile.create',
    '{"slug":"r3-adv-unverified","bio":"Intento con email no verificado.","experienceSummary":"No debe crear el perfil.","emailVerified":true}',
    '{}'
  )
$sql$, 'VERIFIED_EMAIL_REQUIRED');

-- Actor fields supplied by the browser are ignored and sanitized from ledgers.
select pg_temp.actor('a3110000-0000-4000-8000-000000000001');
select public.command_pachanga_referee_platform_v1(
  'a3120000-0000-4000-8000-000000000004',
  'a3130000-0000-4000-8000-000000000001',
  0,
  'profile.create',
  '{"slug":"r3-adv-owner","bio":"Perfil arbitral adversarial completo.","experienceSummary":"Experiencia local declarada.","actorId":"a3110000-0000-4000-8000-000000000002"}',
  '{"clientVersion":"3.0.0+adversarial","serviceWorkerVersion":"sw-r3","installedMode":"standalone","surface":"adversarial","actorId":"a3110000-0000-4000-8000-000000000002","email":"attacker@example.test","token":"plain-secret"}'
);
select pg_temp.assert_true(
  (select user_id from public.pachanga_referee_profiles where id = 'a3130000-0000-4000-8000-000000000001')
    = 'a3110000-0000-4000-8000-000000000001',
  'Client actorId replaced the authenticated profile owner'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from private.pachanga_referee_operation_receipts receipts
    where receipts.operation_id = 'a3120000-0000-4000-8000-000000000004'
      and (
        receipts.client_metadata ? 'actorId'
        or receipts.client_metadata ? 'email'
        or receipts.client_metadata ? 'token'
      )
  ),
  'Sensitive client metadata entered the referee receipt'
);

-- One profile per user and one slug globally remain database-backed invariants.
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000005',
    'a3130000-0000-4000-8000-000000000005',
    0,
    'profile.create',
    '{"slug":"r3-adv-second","bio":"Segundo perfil para la misma cuenta.","experienceSummary":"Debe ser rechazado."}',
    '{}'
  )
$sql$, 'REFEREE_PROFILE_ALREADY_EXISTS');

select pg_temp.actor('a3110000-0000-4000-8000-000000000002');
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000006',
    'a3130000-0000-4000-8000-000000000006',
    0,
    'profile.create',
    '{"slug":"r3-adv-owner","bio":"Intento de apropiarse del slug.","experienceSummary":"Debe ser rechazado."}',
    '{}'
  )
$sql$, 'REFEREE_SLUG_TAKEN|duplicate key');

-- A different user cannot mutate another referee, even with a fresh revision.
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000007',
    'a3130000-0000-4000-8000-000000000001',
    1,
    'profile.update',
    '{"bio":"Third-party overwrite attempt.","reason":"forged"}',
    '{}'
  )
$sql$, 'REFEREE_PROFILE_OWNER_REQUIRED');

-- Revisions and operation IDs cannot be used as last-write-wins primitives.
select pg_temp.actor('a3110000-0000-4000-8000-000000000001');
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000008',
    'a3130000-0000-4000-8000-000000000001',
    0,
    'profile.update',
    '{"bio":"Stale update.","reason":"stale"}',
    '{}'
  )
$sql$, 'STALE_REVISION');

select public.command_pachanga_referee_platform_v1(
  'a3120000-0000-4000-8000-000000000009',
  'a3130000-0000-4000-8000-000000000001',
  1,
  'profile.update',
  '{"bio":"Canonical first update.","reason":"first"}',
  '{}'
);
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000009',
    'a3130000-0000-4000-8000-000000000001',
    1,
    'profile.update',
    '{"bio":"Different replay payload.","reason":"second"}',
    '{}'
  )
$sql$, 'OPERATION_ID_REUSED');

do $$
begin
  perform public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000010',
    'a3130000-0000-4000-8000-000000000001',
    2,
    'profile.update',
    jsonb_build_object('bio', repeat('x', 2001), 'reason', 'oversized'),
    '{}'
  );
end;
$$;
select pg_temp.assert_true(
  (select length(bio) from public.pachanga_referee_profiles where id = 'a3130000-0000-4000-8000-000000000001') = 1200,
  'Oversized profile text escaped the canonical 1200-character limit'
);

-- Support can read the bounded admin surface but cannot perform management actions.
select pg_temp.actor('a3110000-0000-4000-8000-000000000005');
select pg_temp.assert_true(
  public.get_pachanga_platform_referees_v1('{}', 1, 10) ? 'items',
  'Support lost referee read access'
);
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_admin_v1(
    'a3120000-0000-4000-8000-000000000011',
    'a3130000-0000-4000-8000-000000000001',
    3,
    'profile.suspend',
    '{"reason":"Support must not manage"}',
    '{}'
  )
$sql$, 'Platform capability required: referees.manage|PLATFORM_CAPABILITY_REQUIRED|REFEREE_PLATFORM_MANAGE_REQUIRED');

-- Direct product-table writes are closed to authenticated clients.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3110000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select pg_temp.expect_failure($sql$
  update public.pachanga_referee_profiles
  set bio = 'Direct overwrite'
  where id = 'a3130000-0000-4000-8000-000000000001'
$sql$, 'permission denied|row-level security');
select pg_temp.expect_failure($sql$
  delete from public.pachanga_referee_statistics_snapshots
$sql$, 'permission denied|row-level security');
reset role;

-- Anonymous callers cannot invoke write or marketplace RPCs.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000012',
    'a3130000-0000-4000-8000-000000000012',
    0,
    'profile.create',
    '{"slug":"anon-referee","bio":"Anonymous write attempt.","experienceSummary":"Forbidden."}',
    '{}'
  )
$sql$, 'permission denied');
select pg_temp.expect_failure($sql$
  select public.search_pachanga_referee_market_v1('{}', 1, 10)
$sql$, 'permission denied');
reset role;

-- service_role cannot bypass the normal command; only the dedicated reconciliation path accepts service authority.
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.expect_failure($sql$
  select public.command_pachanga_referee_platform_v1(
    'a3120000-0000-4000-8000-000000000013',
    'a3130000-0000-4000-8000-000000000013',
    0,
    'profile.create',
    '{"slug":"service-referee","bio":"Service write attempt.","experienceSummary":"Forbidden."}',
    '{}'
  )
$sql$, 'permission denied');
reset role;

-- A draft/private profile remains absent from the public minimized route.
select pg_temp.assert_true(
  public.get_pachanga_public_referee_v1('r3-adv-owner') is null,
  'Draft referee profile became publicly visible'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from private.pachanga_referee_events events
    where events.event_payload::text ilike '%@example.test%'
       or events.event_payload::text ilike '%plain-secret%'
  ),
  'Referee event payload leaked PII or a secret'
);

rollback;

\echo 'REFEREE_PLATFORM_V1_ADVERSARIAL_OK'
