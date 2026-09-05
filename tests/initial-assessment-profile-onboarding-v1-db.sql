\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;
grant select on public.pachanga_player_profiles to service_role;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.initial_input(seed integer default 0)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'age', 30 + seed,
    'primaryPosition', 'central_midfielder',
    'secondaryPositions', '[]'::jsonb,
    'modeShares', jsonb_build_array(
      jsonb_build_object('mode', 'futsal_5', 'percentage', 0),
      jsonb_build_object('mode', 'football_7', 'percentage', 100),
      jsonb_build_object('mode', 'football_11', 'percentage', 0)
    ),
    'experienceLevel', 'regular_pachangas',
    'yearsSinceLevel', 0,
    'frequency', 'weekly',
    'answers', jsonb_build_object(
      'controlUnderPressure', 3, 'ballCarrying', 3, 'passingExecution', 3,
      'decisionMaking', 3, 'finishing', 3, 'attackingMovement', 3,
      'defensivePositioning', 3, 'defensiveDuels', 3,
      'paceComparison', 3, 'physicalIntensity', 3
    ),
    'calculatedAt', '2026-09-05T08:00:00.000Z',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'initial-test-v1'
  );
$$;

create or replace function pg_temp.assessment_result(kind text default 'initial')
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'calculatedAt', '2026-09-05T08:00:00.000Z',
    'engineResult', '{}'::jsonb,
    'engineVersion', 'football-rating-v1',
    'facets', jsonb_build_object('ritmo',5.5,'tiro',5.5,'pase',5.5,'regate',5.5,'defensa',5.5,'fisico',5.5),
    'position', 'Mediocentro / pivote',
    'primaryPosition', 'central_midfielder',
    'questionnaireVersion', case when kind = 'advanced' then 'advanced-test-v1' else 'initial-test-v1' end,
    'rating', 5.5,
    'reliability', case when kind = 'advanced' then 55 else 41.5625 end,
    'v2Facets', jsonb_build_object('pace',55,'shooting',55,'passing',55,'dribbling',55,'defending',55,'physical',55),
    'v2CurrentModifiers', jsonb_build_object('pace',0,'shooting',0,'passing',0,'dribbling',0,'defending',0,'physical',0)
  );
$$;

insert into auth.users(id, email) values
  ('18100000-0000-4000-8000-000000000001', 'onboarding-1@example.test'),
  ('18100000-0000-4000-8000-000000000002', 'onboarding-2@example.test'),
  ('18100000-0000-4000-8000-000000000003', 'onboarding-3@example.test'),
  ('18100000-0000-4000-8000-000000000004', 'onboarding-4@example.test');

insert into public.pachanga_social_player_profiles_v1(
  user_id, display_name, avatar_ref, primary_position, preferred_modality
) values (
  '18100000-0000-4000-8000-000000000001', 'Jugador universal', 'https://assets.example.test/player.png', 'Mediocentro / pivote', 'futbol7'
);

select pg_temp.assert_true(
  not has_function_privilege('anon', 'public.persist_pachanga_player_assessment_self_authoritative_v1(uuid,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'),
  'Anonymous clients must not execute standalone assessment authority'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated', 'public.persist_pachanga_player_assessment_self_authoritative_v1(uuid,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'),
  'Authenticated clients must use the server API'
);
select pg_temp.assert_true(
  has_function_privilege('service_role', 'public.persist_pachanga_player_assessment_self_authoritative_v1(uuid,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'),
  'Server role must execute standalone assessment authority'
);
select pg_temp.assert_true(
  not has_function_privilege('service_role', 'private.persist_pachanga_player_assessment_self_authoritative_v1_impl(uuid,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'),
  'Server role must not bypass the public wrapper'
);
select pg_temp.assert_true(
  not has_table_privilege('service_role', 'private.pachanga_player_assessment_self_receipts_v1', 'SELECT')
  and not has_table_privilege('service_role', 'private.pachanga_player_assessment_self_events_v1', 'INSERT'),
  'Server role must not access private evidence directly'
);

set local role authenticated;
select pg_catalog.set_config('request.jwt.claim.sub', '18100000-0000-4000-8000-000000000002', true);
select pg_catalog.set_config('onboarding.profile_dml_blocked', 'false', true);
select pg_catalog.set_config('onboarding.assessment_dml_blocked', 'false', true);
do $$ begin
  insert into public.pachanga_player_profiles(user_id) values ('18100000-0000-4000-8000-000000000002');
exception when insufficient_privilege then
  perform pg_catalog.set_config('onboarding.profile_dml_blocked', 'true', true);
end $$;
do $$ begin
  insert into public.pachanga_player_assessments(
    user_id, assessment_kind, engine_version, questionnaire_version,
    idempotency_key, input, result, rating
  ) values (
    '18100000-0000-4000-8000-000000000002', 'initial', 'forged', 'forged',
    '28100000-0000-4000-8000-000000000002', '{}'::jsonb, '{}'::jsonb, 10
  );
exception when insufficient_privilege then
  perform pg_catalog.set_config('onboarding.assessment_dml_blocked', 'true', true);
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.profile_dml_blocked') = 'true', 'Direct profile DML must remain blocked');
select pg_temp.assert_true(current_setting('onboarding.assessment_dml_blocked') = 'true', 'Direct assessment DML must remain blocked');

create temporary table first_response(value jsonb) on commit drop;
grant select, insert on first_response to service_role;
set local role service_role;
insert into first_response(value)
select public.persist_pachanga_player_assessment_self_authoritative_v1(
  '18100000-0000-4000-8000-000000000001', 'initial', pg_temp.initial_input(),
  pg_temp.assessment_result(), '28100000-0000-4000-8000-000000000001', 0,
  '{"clientVersion":"1.0.0","surface":"test","email":"must-not-persist@example.test"}'::jsonb
);
reset role;

select pg_temp.assert_true((select count(*) from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001') = 1, 'Initial test must create one universal profile');
select pg_temp.assert_true((select source_group_id is null and source_player_id is null from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001'), 'Standalone profile must not invent a team');
select pg_temp.assert_true((select display_name = 'Jugador universal' from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001'), 'Canonical social display name must be preserved');
select pg_temp.assert_true((select avatar = 'https://assets.example.test/player.png' from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001'), 'Canonical social avatar must be preserved');
select pg_temp.assert_true((select count(*) from public.pachanga_player_assessments where user_id = '18100000-0000-4000-8000-000000000001' and assessment_kind = 'initial') = 1, 'Initial assessment must be unique');
select pg_temp.assert_true((select count(*) from public.pachanga_player_rating_snapshots snapshots join public.pachanga_player_profiles profiles on profiles.id = snapshots.player_profile_id where profiles.user_id = '18100000-0000-4000-8000-000000000001') = 1, 'Initial test must create one Rating V2 snapshot');
select pg_temp.assert_true((select count(*) from private.pachanga_player_assessment_self_receipts_v1 where user_id = '18100000-0000-4000-8000-000000000001') = 1, 'Initial test must have one receipt');
select pg_temp.assert_true((select count(*) from private.pachanga_player_assessment_self_events_v1 where user_id = '18100000-0000-4000-8000-000000000001') = 1, 'Initial test must have one event');
select pg_temp.assert_true((select count(*) from public.pachanga_social_invalidations_v1 where audience_user_id = '18100000-0000-4000-8000-000000000001' and entity_type = 'rating_profile') = 1, 'Initial test must emit one scoped Realtime invalidation');
select pg_temp.assert_true((select not (client_metadata ? 'email') from private.pachanga_player_assessment_self_receipts_v1 where user_id = '18100000-0000-4000-8000-000000000001'), 'Unapproved client metadata must not persist');
select pg_temp.assert_true((select (value ->> 'confirmedRevision')::bigint = (select profile_version from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001') from first_response), 'Response must contain the canonical profile revision');

select pg_catalog.set_config('onboarding.receipt_immutable', 'false', true);
select pg_catalog.set_config('onboarding.event_immutable', 'false', true);
do $$ begin
  update private.pachanga_player_assessment_self_receipts_v1 set client_metadata = '{}'::jsonb
  where user_id = '18100000-0000-4000-8000-000000000001';
exception when sqlstate '55000' then
  perform pg_catalog.set_config('onboarding.receipt_immutable', 'true', true);
end $$;
do $$ begin
  delete from private.pachanga_player_assessment_self_events_v1
  where user_id = '18100000-0000-4000-8000-000000000001';
exception when sqlstate '55000' then
  perform pg_catalog.set_config('onboarding.event_immutable', 'true', true);
end $$;
select pg_temp.assert_true(current_setting('onboarding.receipt_immutable') = 'true', 'Receipts must be immutable');
select pg_temp.assert_true(current_setting('onboarding.event_immutable') = 'true', 'Events must be immutable');

create temporary table replay_response(value jsonb) on commit drop;
grant select, insert on replay_response to service_role;
set local role service_role;
insert into replay_response(value)
select public.persist_pachanga_player_assessment_self_authoritative_v1(
  '18100000-0000-4000-8000-000000000001', 'initial', pg_temp.initial_input(),
  pg_temp.assessment_result(), '28100000-0000-4000-8000-000000000001', 0, '{}'::jsonb
);
reset role;
select pg_temp.assert_true((select value from replay_response) = (select value from first_response), 'Exact retry must replay the identical canonical response');
select pg_temp.assert_true((select count(*) from public.pachanga_player_assessments where user_id = '18100000-0000-4000-8000-000000000001') = 1, 'Retry must not duplicate assessments');

select pg_catalog.set_config('onboarding.fingerprint_conflict', 'false', true);
set local role service_role;
do $$ begin
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000001', 'initial', pg_temp.initial_input(1),
    pg_temp.assessment_result(), '28100000-0000-4000-8000-000000000001', 0, '{}'::jsonb
  );
exception when sqlstate 'PT409' then
  perform pg_catalog.set_config('onboarding.fingerprint_conflict', 'true', true);
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.fingerprint_conflict') = 'true', 'Same operation with another payload must conflict');

select pg_catalog.set_config('onboarding.second_initial_blocked', 'false', true);
set local role service_role;
do $$ declare current_revision bigint; begin
  select profile_version into current_revision from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001';
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000001', 'initial', pg_temp.initial_input(),
    pg_temp.assessment_result(), '28100000-0000-4000-8000-000000000011', current_revision, '{}'::jsonb
  );
exception when others then
  if sqlerrm ilike '%already completed%' then perform pg_catalog.set_config('onboarding.second_initial_blocked', 'true', true); else raise; end if;
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.second_initial_blocked') = 'true', 'Initial test may only be emitted once');

select pg_catalog.set_config('onboarding.advanced_without_initial', 'false', true);
set local role service_role;
do $$ begin
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000002', 'advanced', '{"answers":{"RIT-1":3}}'::jsonb,
    pg_temp.assessment_result('advanced'), '28100000-0000-4000-8000-000000000021', 0, '{}'::jsonb
  );
exception when others then
  if sqlerrm ilike '%Initial player assessment is required%' then perform pg_catalog.set_config('onboarding.advanced_without_initial', 'true', true); else raise; end if;
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.advanced_without_initial') = 'true', 'Advanced test must never replace the initial test');
select pg_temp.assert_true((select count(*) from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000002') = 0, 'Failed advanced test must roll back profile creation');

set local role service_role;
do $$ declare current_revision bigint; begin
  select profile_version into current_revision from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000001';
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000001', 'advanced', '{"answers":{"RIT-1":3}}'::jsonb,
    pg_temp.assessment_result('advanced'), '28100000-0000-4000-8000-000000000031', current_revision, '{}'::jsonb
  );
end $$;
reset role;
select pg_temp.assert_true((select count(*) from public.pachanga_player_assessments where user_id = '18100000-0000-4000-8000-000000000001') = 2, 'Optional advanced test must append exactly one assessment');
select pg_temp.assert_true((select count(*) from public.pachanga_player_rating_snapshots snapshots join public.pachanga_player_profiles profiles on profiles.id = snapshots.player_profile_id where profiles.user_id = '18100000-0000-4000-8000-000000000001') = 2, 'Advanced test must create one further Rating V2 snapshot');

select pg_catalog.set_config('onboarding.stale_revision', 'false', true);
set local role service_role;
do $$ begin
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000003', 'initial', pg_temp.initial_input(),
    pg_temp.assessment_result(), '28100000-0000-4000-8000-000000000041', 1, '{}'::jsonb
  );
exception when sqlstate 'PT409' then
  perform pg_catalog.set_config('onboarding.stale_revision', 'true', true);
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.stale_revision') = 'true', 'A stale revision must fail closed');
select pg_temp.assert_true((select count(*) from public.pachanga_player_assessments where user_id = '18100000-0000-4000-8000-000000000003') = 0, 'Stale writes must leave no assessment');

select pg_catalog.set_config('onboarding.invalid_result_rolled_back', 'false', true);
set local role service_role;
do $$ begin
  perform public.persist_pachanga_player_assessment_self_authoritative_v1(
    '18100000-0000-4000-8000-000000000004', 'initial', pg_temp.initial_input(),
    pg_temp.assessment_result() || '{"rating":100}'::jsonb,
    '28100000-0000-4000-8000-000000000051', 0, '{}'::jsonb
  );
exception when others then
  perform pg_catalog.set_config('onboarding.invalid_result_rolled_back', 'true', true);
end $$;
reset role;
select pg_temp.assert_true(current_setting('onboarding.invalid_result_rolled_back') = 'true', 'Invalid server result must be rejected');
select pg_temp.assert_true((select count(*) from public.pachanga_player_profiles where user_id = '18100000-0000-4000-8000-000000000004') = 0, 'Rejected write must not leave a profile');
select pg_temp.assert_true((select count(*) from public.pachanga_player_assessments where user_id = '18100000-0000-4000-8000-000000000004') = 0, 'Rejected write must not leave an assessment');

rollback;
