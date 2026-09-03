\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception '%', message;
  end if;
end;
$$;

create or replace function pg_temp.initial_input(seed integer default 0)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'age', 31 + seed,
    'heightCm', 178,
    'weightKg', 76,
    'primaryPosition', 'central_midfielder',
    'secondaryPositions', jsonb_build_array('attacking_midfielder'),
    'modeShares', jsonb_build_array(
      jsonb_build_object('mode', 'futsal_5', 'percentage', 10),
      jsonb_build_object('mode', 'football_7', 'percentage', 70),
      jsonb_build_object('mode', 'football_11', 'percentage', 20)
    ),
    'experienceLevel', 'social_league',
    'yearsSinceLevel', 0,
    'frequency', 'weekly',
    'answers', jsonb_build_object(
      'controlUnderPressure', 3,
      'ballCarrying', 3,
      'passingExecution', 3,
      'decisionMaking', 3,
      'finishing', 3,
      'attackingMovement', 3,
      'defensivePositioning', 3,
      'defensiveDuels', 3,
      'paceComparison', 3,
      'physicalIntensity', 3
    ),
    'calculatedAt', '2026-09-03T20:00:00.000Z',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'initial-test-v1'
  );
$$;

create or replace function pg_temp.initial_result(calculated_at text default '2026-09-03T20:00:00.000Z')
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'calculatedAt', calculated_at,
    'engineResult', '{}'::jsonb,
    'engineVersion', 'football-rating-v1',
    'facets', jsonb_build_object(
      'ritmo', 5.5,
      'tiro', 5.5,
      'pase', 5.5,
      'regate', 5.5,
      'defensa', 5.5,
      'fisico', 5.5
    ),
    'position', 'Mediocentro / pivote',
    'primaryPosition', 'central_midfielder',
    'questionnaireVersion', 'initial-test-v1',
    'rating', 5.5,
    'reliability', 41.5625,
    'v2Facets', jsonb_build_object(
      'pace', 55,
      'shooting', 55,
      'passing', 55,
      'dribbling', 55,
      'defending', 55,
      'physical', 55
    ),
    'v2CurrentModifiers', jsonb_build_object(
      'pace', 0,
      'shooting', 0,
      'passing', 0,
      'dribbling', 0,
      'defending', 0,
      'physical', 0
    )
  );
$$;

insert into auth.users(id, email)
select
  ('16500000-0000-0000-0000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'rating165-' || value || '@example.test'
from pg_catalog.generate_series(1, 8) value;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  ('26500000-0000-0000-0000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  ('16500000-0000-0000-0000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'Rating 165 group ' || value,
  'R165' || value,
  jsonb_build_object(
    'activeMatchId', null,
    'matches', '[]'::jsonb,
    'players', '[]'::jsonb,
    'siteSettings', '{}'::jsonb,
    'venues', '[]'::jsonb
  )
from pg_catalog.generate_series(1, 7) value;

insert into public.pachanga_group_members(group_id, user_id, role)
select
  ('26500000-0000-0000-0000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  ('16500000-0000-0000-0000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'owner'
from pg_catalog.generate_series(1, 7) value;

select pg_temp.assert_true(
  not has_function_privilege(
    'anon',
    'public.persist_pachanga_player_assessment_authoritative_v2(uuid,uuid,text,text,jsonb,jsonb,uuid,bigint,jsonb)',
    'EXECUTE'
  ),
  'Anonymous clients must not execute the assessment authority'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.persist_pachanga_player_assessment_authoritative_v2(uuid,uuid,text,text,jsonb,jsonb,uuid,bigint,jsonb)',
    'EXECUTE'
  ),
  'Authenticated clients must use the server endpoint'
);
select pg_temp.assert_true(
  has_function_privilege(
    'service_role',
    'public.persist_pachanga_player_assessment_authoritative_v2(uuid,uuid,text,text,jsonb,jsonb,uuid,bigint,jsonb)',
    'EXECUTE'
  ),
  'The server role must execute the assessment authority'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.persist_pachanga_player_assessment_v2(uuid,uuid,text,text,jsonb,jsonb,uuid)',
    'EXECUTE'
  ),
  'The inner assessment helper must remain private'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'service_role',
    'public.persist_pachanga_player_assessment_v2(uuid,uuid,text,text,jsonb,jsonb,uuid)',
    'EXECUTE'
  ),
  'The server role must enter through the authoritative wrapper'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.upsert_pachanga_own_player_profile(uuid,text,jsonb)',
    'EXECUTE'
  ),
  'The guarded profile helper must remain private'
);

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', '16500000-0000-0000-0000-000000000008', true);
select pg_catalog.set_config('rating165.profile_dml_blocked', 'false', true);
select pg_catalog.set_config('rating165.assessment_dml_blocked', 'false', true);

do $$
begin
  insert into public.pachanga_player_profiles(user_id)
  values ('16500000-0000-0000-0000-000000000008');
exception
  when insufficient_privilege then
    perform pg_catalog.set_config('rating165.profile_dml_blocked', 'true', true);
end;
$$;

do $$
begin
  insert into public.pachanga_player_assessments(
    user_id,
    assessment_kind,
    engine_version,
    questionnaire_version,
    idempotency_key,
    input,
    result,
    rating
  ) values (
    '16500000-0000-0000-0000-000000000008',
    'initial',
    'forged',
    'forged',
    '36500000-0000-0000-0000-000000000008',
    '{}'::jsonb,
    '{}'::jsonb,
    10
  );
exception
  when insufficient_privilege then
    perform pg_catalog.set_config('rating165.assessment_dml_blocked', 'true', true);
end;
$$;

reset role;

select pg_temp.assert_true(
  pg_catalog.current_setting('rating165.profile_dml_blocked') = 'true',
  'Direct profile INSERT must fail closed under RLS'
);
select pg_temp.assert_true(
  pg_catalog.current_setting('rating165.assessment_dml_blocked') = 'true',
  'Direct assessment INSERT must fail closed under RLS'
);

do $$
declare
  first_response jsonb;
  replay_response jsonb;
  conflicting_response jsonb;
  current_revision bigint;
  profile_id uuid;
  test_operation_id constant uuid := '36500000-0000-0000-0000-000000000001';
begin
  first_response := public.persist_pachanga_player_assessment_authoritative_v2(
    '16500000-0000-0000-0000-000000000001',
    '26500000-0000-0000-0000-000000000001',
    'rating165-player-1',
    'initial',
    pg_temp.initial_input(),
    pg_temp.initial_result(),
    test_operation_id,
    0,
    '{"clientVersion":"test"}'::jsonb
  );

  perform pg_temp.assert_true((first_response ->> 'confirmedRevision')::bigint > 0, 'Initial assessment must advance the revision');
  perform pg_temp.assert_true(first_response ->> 'operationId' = test_operation_id::text, 'Response must confirm the operation id');
  perform pg_temp.assert_true((first_response ->> 'serverSequence')::bigint > 0, 'Response must include a server sequence');

  select profile.id
  into profile_id
  from public.pachanga_player_profiles profile
  where profile.user_id = '16500000-0000-0000-0000-000000000001';

  perform pg_temp.assert_true(profile_id is not null, 'Fresh user profile must be created');
  perform pg_temp.assert_true(
    (select count(*) = 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000001'),
    'Fresh user must have exactly one profile'
  );
  perform pg_temp.assert_true(
    (
      select count(*) = 1
        and pg_catalog.bool_and(player_profile_id = profile_id)
        and pg_catalog.bool_and(rating = 5.5)
        and pg_catalog.bool_and(facet_ratings = pg_temp.initial_result() -> 'facets')
      from public.pachanga_player_assessments
      where user_id = '16500000-0000-0000-0000-000000000001'
        and assessment_kind = 'initial'
    ),
    'Initial assessment must exist once and link to the new profile'
  );
  perform pg_temp.assert_true(
    (
      select base_facets = pg_temp.initial_result() -> 'v2Facets'
        and rating_reliability = 41.5625
        and rating_engine_version = 'pachangas-rating-v2'
      from public.pachanga_player_profiles
      where id = profile_id
    ),
    'Profile must preserve the canonical Rating V2 result'
  );
  perform pg_temp.assert_true(
    (
      select count(*) = 1
      from public.pachanga_groups groups
      cross join lateral jsonb_array_elements(groups.payload -> 'players') player(value)
      where groups.id = '26500000-0000-0000-0000-000000000001'
        and player.value ->> 'id' = 'rating165-player-1'
        and player.value ->> 'ownerUserId' = '16500000-0000-0000-0000-000000000001'
    ),
    'Canonical group read model must contain the owned player'
  );
  perform pg_temp.assert_true(
    (
      select count(*) = 1
      from public.pachanga_operation_receipts receipts
      where receipts.group_id = '26500000-0000-0000-0000-000000000001'
        and receipts.operation_id = test_operation_id
        and receipts.client_metadata ->> 'assessmentRequestFingerprint' ~ '^[0-9a-f]{64}$'
    ),
    'The existing receipt must bind the operation to a server fingerprint'
  );
  perform pg_temp.assert_true(
    (
      select count(*) = 1
      from public.pachanga_group_events events
      where events.group_id = '26500000-0000-0000-0000-000000000001'
        and events.operation_id = test_operation_id
    ),
    'Successful onboarding must emit exactly one group event'
  );

  replay_response := public.persist_pachanga_player_assessment_authoritative_v2(
    '16500000-0000-0000-0000-000000000001',
    '26500000-0000-0000-0000-000000000001',
    'rating165-player-1',
    'initial',
    pg_temp.initial_input(),
    pg_temp.initial_result('2026-09-03T20:01:00.000Z'),
    test_operation_id,
    0,
    '{"clientVersion":"retry"}'::jsonb
  );
  perform pg_temp.assert_true(replay_response = first_response, 'Exact retry must return the stored canonical response');
  perform pg_temp.assert_true(
    (select count(*) = 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000001'),
    'Exact retry must not duplicate the assessment'
  );
  perform pg_temp.assert_true(
    (select count(*) = 1 from public.pachanga_group_events events where events.operation_id = test_operation_id),
    'Exact retry must not duplicate the event'
  );

  begin
    conflicting_response := public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000001',
      '26500000-0000-0000-0000-000000000001',
      'rating165-player-1',
      'initial',
      pg_temp.initial_input(1),
      pg_temp.initial_result(),
      test_operation_id,
      0,
      '{}'::jsonb
    );
    raise exception 'Expected payload-bound idempotency conflict, got %', conflicting_response;
  exception
    when sqlstate 'PT409' then null;
  end;

  select payload_revision
  into current_revision
  from public.pachanga_groups
  where id = '26500000-0000-0000-0000-000000000001';

  begin
    perform public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000001',
      '26500000-0000-0000-0000-000000000001',
      'rating165-player-1',
      'initial',
      pg_temp.initial_input(),
      pg_temp.initial_result(),
      '36500000-0000-0000-0000-000000000011',
      current_revision,
      '{}'::jsonb
    );
    raise exception 'A second initial assessment must fail';
  exception
    when raise_exception then
      if sqlerrm not like 'Initial player assessment already completed%' then
        raise;
      end if;
  end;
end;
$$;

do $$
declare
  invalid_result jsonb;
begin
  invalid_result := pg_catalog.jsonb_set(pg_temp.initial_result(), '{v2Facets,pace}', '101'::jsonb);
  begin
    perform public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000002',
      '26500000-0000-0000-0000-000000000002',
      'rating165-player-2',
      'initial',
      pg_temp.initial_input(),
      invalid_result,
      '36500000-0000-0000-0000-000000000002',
      0,
      '{}'::jsonb
    );
    raise exception 'Out-of-range facets must fail';
  exception
    when raise_exception then
      if sqlerrm <> 'Invalid shared-engine assessment result' then
        raise;
      end if;
  end;

  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000002'),
    'Invalid facets must not leave a profile'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000002'),
    'Invalid facets must not leave an assessment'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_operation_receipts where group_id = '26500000-0000-0000-0000-000000000002'),
    'Invalid facets must not leave a receipt'
  );
end;
$$;

do $$
begin
  begin
    perform public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000004',
      '26500000-0000-0000-0000-000000000004',
      'rating165-player-4',
      'initial',
      pg_temp.initial_input(),
      pg_temp.initial_result() - 'position',
      '36500000-0000-0000-0000-000000000004',
      0,
      '{}'::jsonb
    );
    raise exception 'Missing required result fields must fail';
  exception
    when raise_exception then
      if sqlerrm <> 'Invalid shared-engine assessment result' then
        raise;
      end if;
  end;

  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000004'),
    'Missing result fields must roll back profile creation'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000004'),
    'Missing result fields must roll back assessment creation'
  );
end;
$$;

do $$
begin
  begin
    perform public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000006',
      '26500000-0000-0000-0000-000000000006',
      'rating165-player-6',
      'initial',
      pg_temp.initial_input(),
      pg_temp.initial_result(),
      '36500000-0000-0000-0000-000000000006',
      1,
      '{}'::jsonb
    );
    raise exception 'Stale revisions must fail';
  exception
    when sqlstate 'PT409' then null;
  end;

  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000006'),
    'Stale revisions must not create a profile'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000006'),
    'Stale revisions must not create an assessment'
  );
end;
$$;

insert into public.pachanga_player_profiles(
  user_id,
  source_group_id,
  source_player_id,
  display_name
) values (
  '16500000-0000-0000-0000-000000000003',
  '26500000-0000-0000-0000-000000000003',
  'rating165-player-3',
  'Existing profile'
);

do $$
declare
  profile_id uuid;
begin
  select id into profile_id
  from public.pachanga_player_profiles
  where user_id = '16500000-0000-0000-0000-000000000003';

  perform public.persist_pachanga_player_assessment_authoritative_v2(
    '16500000-0000-0000-0000-000000000003',
    '26500000-0000-0000-0000-000000000003',
    'rating165-player-3',
    'initial',
    pg_temp.initial_input(),
    pg_temp.initial_result(),
    '36500000-0000-0000-0000-000000000003',
    0,
    '{}'::jsonb
  );

  perform pg_temp.assert_true(
    (select count(*) = 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000003'),
    'Existing profile must not be duplicated'
  );
  perform pg_temp.assert_true(
    (
      select player_profile_id = profile_id
      from public.pachanga_player_assessments
      where user_id = '16500000-0000-0000-0000-000000000003'
        and assessment_kind = 'initial'
    ),
    'Existing profile must receive the canonical assessment'
  );
end;
$$;

create or replace function pg_temp.reject_rating165_profile()
returns trigger
language plpgsql
as $$
begin
  if new.user_id = '16500000-0000-0000-0000-000000000005' then
    raise exception 'rating165 induced profile failure';
  end if;
  return new;
end;
$$;

create trigger rating165_induced_profile_failure
before insert on public.pachanga_player_profiles
for each row execute function pg_temp.reject_rating165_profile();

do $$
begin
  begin
    perform public.persist_pachanga_player_assessment_authoritative_v2(
      '16500000-0000-0000-0000-000000000005',
      '26500000-0000-0000-0000-000000000005',
      'rating165-player-5',
      'initial',
      pg_temp.initial_input(),
      pg_temp.initial_result(),
      '36500000-0000-0000-0000-000000000005',
      0,
      '{}'::jsonb
    );
    raise exception 'Induced profile failure must abort';
  exception
    when raise_exception then
      if sqlerrm <> 'rating165 induced profile failure' then
        raise;
      end if;
  end;

  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000005'),
    'Induced failure must leave no profile'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000005'),
    'Induced failure must roll back the provisional assessment'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_group_events where group_id = '26500000-0000-0000-0000-000000000005'),
    'Induced failure must leave no event'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.pachanga_operation_receipts where group_id = '26500000-0000-0000-0000-000000000005'),
    'Induced failure must leave no receipt'
  );
end;
$$;

drop trigger rating165_induced_profile_failure on public.pachanga_player_profiles;

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', '16500000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  (select count(*) = 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000001'),
  'Owner must read the confirmed profile through RLS'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000001'),
  'Owner must read the confirmed assessment through RLS'
);

select pg_catalog.set_config('request.jwt.claim.sub', '16500000-0000-0000-0000-000000000008', true);
select pg_temp.assert_true(
  not exists (select 1 from public.pachanga_player_profiles where user_id = '16500000-0000-0000-0000-000000000001'),
  'Another user must not read the profile'
);
select pg_temp.assert_true(
  not exists (select 1 from public.pachanga_player_assessments where user_id = '16500000-0000-0000-0000-000000000001'),
  'Another user must not read the assessment'
);

reset role;

select pg_temp.assert_true(
  (
    select count(*) = 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'pachanga_player_profiles'
      and cmd = 'SELECT'
  ),
  'Profile RLS policy surface must remain read-only'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in ('pachanga_player_profiles', 'pachanga_player_assessments')
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ),
  'No direct-write RLS policy may be introduced'
);

rollback;
