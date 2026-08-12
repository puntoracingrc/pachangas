create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text
language plpgsql
as $$
declare
  failure text;
begin
  begin
    execute statement;
    raise exception 'PLATFORM_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'PLATFORM_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.platform_ledger_count(target_operation_id uuid)
returns bigint
language sql
security definer
set search_path = pg_catalog
as $$
  select count(*)
  from private.pachanga_platform_admin_action_ledger ledger
  where ledger.operation_id = target_operation_id;
$$;

create or replace function pg_temp.platform_user_state(target_user_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object('status', states.status, 'revision', states.revision)
  from private.pachanga_platform_user_states states
  where states.user_id = target_user_id;
$$;

create or replace function pg_temp.team_policy_event_count(target_operation_id uuid)
returns bigint
language sql
security definer
set search_path = pg_catalog
as $$
  select count(*)
  from private.pachanga_team_cosmetic_reward_policy_events events
  where events.operation_id = target_operation_id;
$$;

create or replace function pg_temp.telemetry_occurrences(target_fingerprint text, target_route text)
returns bigint
language sql
security definer
set search_path = pg_catalog
as $$
  select coalesce(sum(errors.occurrence_count), 0)
  from private.pachanga_client_error_telemetry errors
  where errors.fingerprint = target_fingerprint and errors.route = target_route;
$$;

create or replace function pg_temp.notification_count(target_user_id uuid, target_kind text)
returns bigint
language sql
security definer
set search_path = pg_catalog
as $$
  select count(*)
  from public.pachanga_user_notifications notifications
  where notifications.recipient_user_id = target_user_id
    and notifications.kind = target_kind;
$$;

insert into auth.users(id, email, raw_user_meta_data) values
  ('aa100000-0000-4000-8000-000000000001', 'platform-owner@example.test', '{"full_name":"Platform Owner"}'),
  ('aa100000-0000-4000-8000-000000000002', 'platform-admin@example.test', '{"full_name":"Platform Admin"}'),
  ('aa100000-0000-4000-8000-000000000003', 'platform-moderator@example.test', '{"full_name":"Platform Moderator"}'),
  ('aa100000-0000-4000-8000-000000000004', 'platform-support@example.test', '{"full_name":"Platform Support"}'),
  ('aa100000-0000-4000-8000-000000000005', 'platform-finance@example.test', '{"full_name":"Platform Finance"}'),
  ('aa100000-0000-4000-8000-000000000006', 'platform-ops@example.test', '{"full_name":"Platform Ops"}'),
  ('aa100000-0000-4000-8000-000000000007', 'platform-normal@example.test', '{"full_name":"Normal Person"}'),
  ('aa100000-0000-4000-8000-000000000008', 'platform-team-admin@example.test', '{"full_name":"Team Admin Only"}');

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, billing_status,
  billing_trial_finalized_matches, ratings_enabled, externally_calibrated_level,
  stripe_customer_id, stripe_subscription_id
) values
  (
    'aa300000-0000-4000-8000-000000000001',
    'aa100000-0000-4000-8000-000000000008',
    'Platform Test Team Madrid', 'PCCV101',
    '{"players":[],"matches":[{"id":"platform-match-1","title":"Partido interno de prueba","date":"2026-08-20","kind":"futbol7","place":"Campo Norte"}]}',
    'active', 2, true, 65, 'cus_platform_control_test', 'sub_platform_control_test'
  ),
  (
    'aa300000-0000-4000-8000-000000000002',
    'aa100000-0000-4000-8000-000000000002',
    'Platform Test Team Closed', 'PCCV102', '{"players":[],"matches":[]}',
    'trial', 0, false, null, null, null
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('aa300000-0000-4000-8000-000000000001', 'aa100000-0000-4000-8000-000000000008', 'owner', 'Team Admin Only'),
  ('aa300000-0000-4000-8000-000000000001', 'aa100000-0000-4000-8000-000000000007', 'player', 'Normal Person');

insert into public.pachanga_match_read_model(
  group_id, match_id, match_state, match_version, configured, lineup_closed,
  finalized, target_players, reserve_limit, source_payload_revision
) values (
  'aa300000-0000-4000-8000-000000000001', 'platform-match-1', 'lineup_open', 3,
  true, false, false, 14, 2, 1
);

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, status, revision, proposal_number,
  scheduled_at, modality, field_name, field_address, last_proposed_by_group_id,
  created_by, updated_by, accepted_at
) values (
  'aa600000-0000-4000-8000-000000000001',
  'aa300000-0000-4000-8000-000000000001',
  'aa300000-0000-4000-8000-000000000002',
  'accepted', 2, 1, '2026-08-21 19:00:00+00', 'futbol7',
  'Campo del Reto', 'Dirección sintética',
  'aa300000-0000-4000-8000-000000000001',
  'aa100000-0000-4000-8000-000000000008',
  'aa100000-0000-4000-8000-000000000008', clock_timestamp()
);

insert into public.pachanga_external_matches(
  id, challenge_id, home_group_id, away_group_id, scheduled_at, modality,
  field_snapshot, state, revision, canonical_score_home, canonical_score_away
) values (
  'aa610000-0000-4000-8000-000000000001',
  'aa600000-0000-4000-8000-000000000001',
  'aa300000-0000-4000-8000-000000000001',
  'aa300000-0000-4000-8000-000000000002',
  '2026-08-21 19:00:00+00', 'futbol7', '{"name":"Campo del Reto"}',
  'confirmed', 2, 3, 2
);

insert into public.pachanga_stripe_webhook_events(
  event_id, event_type, processing_status, processed_at, error_message, payload
) values (
  'evt_platform_control_test', 'invoice.payment_failed', 'failed', clock_timestamp(),
  'Stripe sk_live_platformsecret Bearer token.value person@example.test?secret=private',
  '{}'
);

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name,
  current_overall, base_overall, calibrated_overall, current_facets,
  rating_reliability, rating_engine_version
) values
  (
    'aa200000-0000-4000-8000-000000000007',
    'aa100000-0000-4000-8000-000000000007',
    'aa300000-0000-4000-8000-000000000001', 'normal-player', 'Normal Person',
    60, 60, 60,
    '{"pace":60,"shooting":60,"passing":60,"dribbling":60,"defending":60,"physical":60}',
    70, 'pachangas-rating-v2'
  ),
  (
    'aa200000-0000-4000-8000-000000000008',
    'aa100000-0000-4000-8000-000000000008',
    'aa300000-0000-4000-8000-000000000001', 'team-admin-player', 'Team Admin Only',
    62, 62, 62,
    '{"pace":62,"shooting":62,"passing":62,"dribbling":62,"defending":62,"physical":62}',
    70, 'pachangas-rating-v2'
  );

insert into public.pachanga_challengeable_team_profiles(
  group_id, enabled, zone_label, zone_place_id, zone_lat, zone_lng,
  travel_radius_km, min_opponent_level, max_opponent_level, modalities,
  revision, created_by, updated_by
) values (
  'aa300000-0000-4000-8000-000000000001', true, 'Madrid Centro', 'test-place',
  40.4168, -3.7038, 20, 40, 80, array['futbol7'], 1,
  'aa100000-0000-4000-8000-000000000008', 'aa100000-0000-4000-8000-000000000008'
);

insert into private.pachanga_moderation_cases(
  id, target_profile_id, target_user_id, source_type, category, state,
  report_count, source_cluster_count, independent_source_count
) values (
  'aa500000-0000-4000-8000-000000000001',
  'aa200000-0000-4000-8000-000000000007',
  'aa100000-0000-4000-8000-000000000007',
  'conduct_report', 'other', 'restricted', 2, 2, 2
);
insert into private.pachanga_social_restrictions(
  id, case_id, target_user_id, restriction_type, duration_days, state,
  applied_by, effective_until
) values (
  'aa510000-0000-4000-8000-000000000001',
  'aa500000-0000-4000-8000-000000000001',
  'aa100000-0000-4000-8000-000000000007',
  'public_market', 7, 'active',
  'aa100000-0000-4000-8000-000000000003', clock_timestamp() + interval '7 days'
);

-- Bootstrap is service-only, idempotent, and cannot silently appoint a second first owner.
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table platform_bootstrap as
select public.bootstrap_pachanga_platform_owner_v1(
  'aa100000-0000-4000-8000-000000000001',
  'aa400000-0000-4000-8000-000000000001',
  'Initial staging owner fixture'
) as response;
select pg_temp.assert_true(
  public.bootstrap_pachanga_platform_owner_v1(
    'aa100000-0000-4000-8000-000000000001',
    'aa400000-0000-4000-8000-000000000001',
    'Initial staging owner fixture'
  ) = (select response from platform_bootstrap),
  'Owner bootstrap replay must return the original response'
);
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa400000-0000-4000-8000-000000000001') = 1,
  'Owner bootstrap must emit one audit event'
);
select pg_temp.expect_failure(
  $$select public.bootstrap_pachanga_platform_owner_v1(
    'aa100000-0000-4000-8000-000000000002',
    'aa400000-0000-4000-8000-000000000002',
    'Second bootstrap must fail'
  )$$,
  'already bootstrapped'
);
reset role;

-- The owner grants all operational roles through the canonical RPC.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000002', 'platform_admin', true, 0, 'aa410000-0000-4000-8000-000000000002', 'Platform admin fixture');
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000003', 'moderator', true, 0, 'aa410000-0000-4000-8000-000000000003', 'Moderator fixture');
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000004', 'support', true, 0, 'aa410000-0000-4000-8000-000000000004', 'Support fixture');
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000005', 'finance', true, 0, 'aa410000-0000-4000-8000-000000000005', 'Finance fixture');
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000006', 'ops', true, 0, 'aa410000-0000-4000-8000-000000000006', 'Ops fixture');
select public.set_pachanga_platform_role_v1('aa100000-0000-4000-8000-000000000004', 'support', true, 0, 'aa410000-0000-4000-8000-000000000004', 'Support fixture');
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa410000-0000-4000-8000-000000000004') = 1,
  'Role replay must not duplicate audit events'
);

select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_role_v1(
    'aa100000-0000-4000-8000-000000000001', 'platform_owner', false, 1,
    'aa410000-0000-4000-8000-000000000010', 'Attempt to remove final owner'
  )$$,
  'last platform owner'
);
select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_user_state_v1(
    'aa100000-0000-4000-8000-000000000001', 'banned', null, 0,
    'aa420000-0000-4000-8000-000000000010', 'Self suspension is forbidden'
  )$$,
  'cannot suspend themselves'
);

-- Visitor, normal user and team owner have no platform authority.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.expect_failure('select public.get_my_pachanga_platform_access_v1()', 'permission denied|Authentication required|Platform access required');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000007","role":"authenticated"}', true);
select pg_temp.expect_failure('select public.get_my_pachanga_platform_access_v1()', 'Platform access required');
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000008","role":"authenticated"}', true);
select pg_temp.expect_failure('select public.get_pachanga_platform_overview_v1(''today'')', 'Platform access required');

-- Every platform role gets only its own server-side capabilities.
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'moderation.write'
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'billing.read')
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'users.pii.read'),
  'Moderator capability matrix must exclude billing and PII'
);
select pg_temp.expect_failure(
  $$select public.get_pachanga_platform_section_v1('billing', 10, 0)$$,
  'Platform capability required'
);
select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_role_v1(
    'aa100000-0000-4000-8000-000000000007', 'support', true, 0,
    'aa410000-0000-4000-8000-000000000011', 'Moderator cannot grant roles'
  )$$,
  'Platform capability required'
);

select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000005","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'billing.read'
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'moderation.write'),
  'Finance capability matrix must be read-only outside billing'
);
select pg_temp.expect_failure(
  $$select public.get_pachanga_platform_section_v1('moderation', 10, 0)$$,
  'Platform capability required'
);
select pg_temp.assert_true(
  position('sk_live_platformsecret' in public.get_pachanga_platform_section_v1('billing', 10, 0)::text) = 0
  and position('person@example.test' in public.get_pachanga_platform_section_v1('billing', 10, 0)::text) = 0
  and position('[redacted-key]' in public.get_pachanga_platform_section_v1('billing', 10, 0)::text) > 0,
  'Finance sees a useful but sanitized Stripe webhook error'
);

select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'users.pii.read'
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'flags.write'),
  'Support may diagnose users but cannot change flags'
);
select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_flag_v1(
    'attendance', true, 1, 'aa430000-0000-4000-8000-000000000011', 'Support cannot change flags'
  )$$,
  'Platform capability required'
);

select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'system.read'
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'users.read'),
  'Ops capability matrix must stay focused on system health'
);
select pg_temp.expect_failure(
  $$select public.list_pachanga_platform_users_v1('', 'all', null, null, 'created_desc', 10, 0)$$,
  'Platform capability required'
);

select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'flags.write'
  and (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'users.suspend'
  and not ((public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'roles.manage'),
  'Platform admin can operate but cannot grant platform roles'
);

select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'roles.manage'
  and (public.get_my_pachanga_platform_access_v1() -> 'capabilities') ? 'labs.read',
  'Platform owner must have owner-only capabilities'
);
select pg_temp.assert_true(
  (public.get_pachanga_platform_overview_v1('today') #>> '{moderation,restrictedUsers}')::bigint = 1,
  'Platform overview must read active restrictions from canonical effective_until'
);

-- PII is role-gated in the database, not merely hidden by React.
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.list_pachanga_platform_users_v1('platform-normal@example.test', 'all', null, null, 'created_desc', 10, 0) ->> 'total')::integer = 0,
  'Moderator must not search users by email'
);
select pg_temp.assert_true(
  public.list_pachanga_platform_users_v1('Normal Person', 'all', null, null, 'name_asc', 10, 0) #>> '{items,0,email}' is null,
  'Moderator user rows must not expose email'
);
select pg_temp.assert_true(
  (public.list_pachanga_platform_users_v1('Platform Owner', 'all', null, null, 'name_asc', 10, 0) ->> 'total')::integer = 1
  and public.list_pachanga_platform_users_v1('Platform Owner', 'all', null, null, 'name_asc', 10, 0) #>> '{items,0,name}' = 'Platform Owner',
  'Users without a universal profile must remain searchable by their safe Auth display name'
);
select pg_temp.assert_true(
  public.search_pachanga_platform_v1('Platform Owner', 20) #>> '{0,label}' = 'Platform Owner',
  'Global search must resolve the safe Auth display name without requiring a player profile'
);
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select pg_temp.assert_true(
  public.list_pachanga_platform_users_v1('platform-normal@example.test', 'all', null, null, 'created_desc', 10, 0) #>> '{items,0,email}' = 'platform-normal@example.test',
  'Support user rows may expose email for diagnosis'
);
select pg_temp.assert_true(
  jsonb_array_length(public.search_pachanga_platform_v1('cus_platform_control_test', 20)) = 0,
  'Support must not locate teams through Stripe identifiers'
);
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000005","role":"authenticated"}', true);
select pg_temp.assert_true(
  jsonb_array_length(public.search_pachanga_platform_v1('cus_platform_control_test', 20)) = 1,
  'Finance may resolve a team from its Stripe customer identifier'
);
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000004","role":"authenticated"}', true);

-- Team filters, totals and privacy are resolved before pagination in PostgreSQL.
create temporary table platform_team_page as
select public.list_pachanga_platform_teams_v1(
  'Platform Test Team', 'active', 'enabled', 'Madrid',
  'aa100000-0000-4000-8000-000000000008', 'active', 'restricted',
  40, 80, null, null, 'level_desc', 10, 0
) as response;
select pg_temp.assert_true(
  (select (response ->> 'total')::integer = 1 from platform_team_page)
  and (select response #>> '{items,0,id}' = 'aa300000-0000-4000-8000-000000000001' from platform_team_page)
  and (select (response #>> '{items,0,activeRestrictionCount}')::integer = 1 from platform_team_page),
  'Team filters must return the exact canonical page and total'
);
select pg_temp.assert_true(
  not (select (response #> '{items,0,market}') ? 'zoneLat' from platform_team_page)
  and not (select (response #> '{items,0,market}') ? 'zoneLng' from platform_team_page)
  and not (select (response #> '{items,0,market}') ? 'zonePlaceId' from platform_team_page),
  'Team listing must not expose precise market coordinates or place identifiers'
);

-- Match and challenge filters run before pagination and include canonical Reto matches.
create temporary table platform_match_page as
select public.list_pachanga_platform_matches_v1(
  'Platform Test Team', 'aa300000-0000-4000-8000-000000000001',
  '2026-08-20', '2026-08-21', 'futbol7', 'all', 'all', 'date_asc', 10, 0
) as response;
select pg_temp.assert_true(
  (select (response ->> 'total')::integer = 2 from platform_match_page)
  and (select response #>> '{items,0,scope}' = 'internal' from platform_match_page)
  and (select response #>> '{items,1,scope}' = 'challenge' from platform_match_page)
  and (select response #>> '{items,1,challengeId}' = 'aa600000-0000-4000-8000-000000000001' from platform_match_page),
  'Internal and Reto matches must share one filtered, stable administrative read model'
);
create temporary table platform_challenge_page as
select public.list_pachanga_platform_challenges_v1(
  'Campo del Reto', 'aa300000-0000-4000-8000-000000000002',
  '2026-08-21', '2026-08-21', 'accepted', 'date_asc', 10, 0
) as response;
select pg_temp.assert_true(
  (select (response ->> 'total')::integer = 1 from platform_challenge_page)
  and (select response #>> '{items,0,id}' = 'aa600000-0000-4000-8000-000000000001' from platform_challenge_page)
  and (select response #>> '{items,0,sender,name}' = 'Platform Test Team Madrid' from platform_challenge_page),
  'Challenge search, team, date and status filters must resolve before pagination'
);

-- Ban/unban is explicit, revisioned, reversible and one-event idempotent.
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
create temporary table platform_ban as
select public.set_pachanga_platform_user_state_v1(
  'aa100000-0000-4000-8000-000000000007', 'banned', null, 0,
  'aa420000-0000-4000-8000-000000000001', 'Manual abuse investigation'
) as response;
select pg_temp.assert_true(
  public.set_pachanga_platform_user_state_v1(
    'aa100000-0000-4000-8000-000000000007', 'banned', null, 0,
    'aa420000-0000-4000-8000-000000000001', 'Manual abuse investigation'
  ) = (select response from platform_ban),
  'Ban replay must return the first canonical response'
);
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa420000-0000-4000-8000-000000000001') = 1,
  'Ban retry must produce one audit event'
);
select public.set_pachanga_platform_user_state_v1(
  'aa100000-0000-4000-8000-000000000007', 'active', null, 1,
  'aa420000-0000-4000-8000-000000000002', 'Manual review completed'
);
select public.set_pachanga_platform_user_state_v1(
  'aa100000-0000-4000-8000-000000000007', 'active', null, 1,
  'aa420000-0000-4000-8000-000000000002', 'Manual review completed'
);
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa420000-0000-4000-8000-000000000002') = 1
  and pg_temp.platform_user_state('aa100000-0000-4000-8000-000000000007')
    @> '{"status":"active","revision":2}'::jsonb,
  'Unban must be reversible and idempotent'
);
select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_user_state_v1(
    'aa100000-0000-4000-8000-000000000007', 'suspended', clock_timestamp() + interval '1 day', 1,
    'aa420000-0000-4000-8000-000000000003', 'Stale suspension attempt'
  )$$,
  'changed before saving'
);
select pg_temp.expect_failure(
  $$select public.set_pachanga_platform_user_state_v1(
    'aa100000-0000-4000-8000-000000000007', 'banned', null, 2,
    'aa410000-0000-4000-8000-000000000004', 'Cross action operation replay'
  )$$,
  'different platform action'
);

-- Suspending an administrator removes platform access immediately at the DB authority.
select public.set_pachanga_platform_user_state_v1(
  'aa100000-0000-4000-8000-000000000002', 'suspended', clock_timestamp() + interval '1 day', 0,
  'aa420000-0000-4000-8000-000000000004', 'Temporary admin suspension'
);
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select pg_temp.assert_true(
  public.get_pachanga_platform_access_service_v1('aa100000-0000-4000-8000-000000000002') is null,
  'Service access lookup must also respect a platform suspension'
);
select public.confirm_pachanga_platform_user_auth_sync_v1('aa420000-0000-4000-8000-000000000004', true, null);
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select public.set_pachanga_platform_user_state_v1(
  'aa100000-0000-4000-8000-000000000002', 'active', null, 1,
  'aa420000-0000-4000-8000-000000000005', 'Admin suspension reversed'
);

-- Activating product candidates is non-retroactive and fully auditable.
reset role;
create temporary table production_activation_before as
select
  jsonb_build_object(
    'closures', (select count(*) from private.pachanga_attendance_closures),
    'attendance', (select count(*) from private.pachanga_post_match_attendance),
    'reports', (select count(*) from private.pachanga_conduct_reports),
    'cases', (select count(*) from private.pachanga_moderation_cases),
    'notifications', (select count(*) from public.pachanga_user_notifications),
    'ratingEvidence', (select count(*) from public.pachanga_individual_rating_evidence),
    'ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots),
    'rewards', (select count(*) from public.pachanga_reward_grants),
    'billingEvents', (select count(*) from public.pachanga_stripe_webhook_events)
  ) as snapshot,
  (select platform_revision from private.pachanga_conduct_settings where singleton) as revision;
grant select on production_activation_before to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);

create temporary table attendance_activation as
select public.set_pachanga_platform_flag_v1(
  'attendance', true, revision,
  'aa430000-0000-4000-8000-000000000010',
  'Production Feature Activation Audit V1 - Attendance staging activation'
) as response
from production_activation_before;

create temporary table conduct_activation as
select public.set_pachanga_platform_flag_v1(
  'conduct', true, (select (response ->> 'revision')::bigint from attendance_activation),
  'aa430000-0000-4000-8000-000000000011',
  'Production Feature Activation Audit V1 - Conduct staging activation'
) as response;

reset role;
select pg_temp.assert_true(
  (select snapshot from production_activation_before) = jsonb_build_object(
    'closures', (select count(*) from private.pachanga_attendance_closures),
    'attendance', (select count(*) from private.pachanga_post_match_attendance),
    'reports', (select count(*) from private.pachanga_conduct_reports),
    'cases', (select count(*) from private.pachanga_moderation_cases),
    'notifications', (select count(*) from public.pachanga_user_notifications),
    'ratingEvidence', (select count(*) from public.pachanga_individual_rating_evidence),
    'ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots),
    'rewards', (select count(*) from public.pachanga_reward_grants),
    'billingEvents', (select count(*) from public.pachanga_stripe_webhook_events)
  ),
  'Turning Attendance and Conduct on must not backfill or mutate sport, reward, billing or notifications'
);
select pg_temp.assert_true(
  (select response ->> 'effectiveFrom' is not null from attendance_activation)
  and (select response ->> 'effectiveFrom' is not null from conduct_activation)
  and (select attendance_effective_from is not null and conduct_effective_from is not null
    from private.pachanga_conduct_settings where singleton),
  'Both production candidates must receive authoritative activation frontiers'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true(
  exists (
    select 1 from jsonb_array_elements(public.get_pachanga_platform_flags_v1()) flag
    where flag ->> 'key' = 'attendance'
      and flag ->> 'classification' = 'ACTIVE_PRODUCT'
      and flag ->> 'effectiveFrom' is not null
  )
  and exists (
    select 1 from jsonb_array_elements(public.get_pachanga_platform_flags_v1()) flag
    where flag ->> 'key' = 'conduct'
      and flag ->> 'classification' = 'ACTIVE_PRODUCT'
      and flag ->> 'effectiveFrom' is not null
  ),
  'Control Center must render the real DB state and activation frontiers'
);
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa430000-0000-4000-8000-000000000010') = 1
  and pg_temp.platform_ledger_count('aa430000-0000-4000-8000-000000000011') = 1,
  'Each activation must emit one authoritative audit event'
);

create temporary table conduct_deactivation as
select public.set_pachanga_platform_flag_v1(
  'conduct', false, (select (response ->> 'revision')::bigint from conduct_activation),
  'aa430000-0000-4000-8000-000000000012', 'Controlled Conduct rollback test'
) as response;
select public.set_pachanga_platform_flag_v1(
  'attendance', false, (select (response ->> 'revision')::bigint from conduct_deactivation),
  'aa430000-0000-4000-8000-000000000013', 'Controlled Attendance rollback test'
);

reset role;
select pg_temp.assert_true(
  (select not attendance_closure_enabled and not conduct_reports_enabled
    and attendance_effective_from is not null and conduct_effective_from is not null
    from private.pachanga_conduct_settings where singleton),
  'Rollback must disable writes while preserving activation evidence'
);

-- Sensitive flag change delegates Team Rewards to its canonical policy helper.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
create temporary table platform_flag_before as
select
  (flag ->> 'enabled')::boolean as enabled,
  (flag ->> 'revision')::bigint as revision
from jsonb_array_elements(public.get_pachanga_platform_flags_v1()) flag
where flag ->> 'key' = 'team_cosmetic_rewards';
create temporary table platform_flag as
select public.set_pachanga_platform_flag_v1(
  'team_cosmetic_rewards', not enabled, revision,
  'aa430000-0000-4000-8000-000000000001', 'Controlled staging flag test'
) as response
from platform_flag_before;
select pg_temp.assert_true(
  public.set_pachanga_platform_flag_v1(
    'team_cosmetic_rewards', not before.enabled, before.revision,
    'aa430000-0000-4000-8000-000000000001', 'Controlled staging flag test'
  ) = flag.response,
  'Flag replay must return the original response'
)
from platform_flag_before before cross join platform_flag flag;
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa430000-0000-4000-8000-000000000001') = 1
  and pg_temp.team_policy_event_count('aa430000-0000-4000-8000-000000000001') = 1,
  'Team Reward flag change must emit one platform event and one canonical policy event'
);

-- Announcement flow is draft -> preview -> confirmed send, never global by accident.
create temporary table platform_announcement as
select public.create_pachanga_platform_announcement_v1(
  'user', 'aa100000-0000-4000-8000-000000000007',
  'Aviso de prueba', 'Mensaje administrativo de staging', '/avisos',
  'aa440000-0000-4000-8000-000000000001', 'Controlled notification fixture'
) as response;
select pg_temp.assert_true(
  public.create_pachanga_platform_announcement_v1(
    'user', 'aa100000-0000-4000-8000-000000000007',
    'Aviso de prueba', 'Mensaje administrativo de staging', '/avisos',
    'aa440000-0000-4000-8000-000000000001', 'Controlled notification fixture'
  ) = (select response from platform_announcement),
  'Announcement draft replay must be idempotent'
);
select pg_temp.assert_true(
  (public.preview_pachanga_platform_announcement_v1(
    (select (response ->> 'id')::uuid from platform_announcement)
  ) ->> 'recipientCount')::integer = 1,
  'Announcement preview must disclose the exact recipient count before send'
);
create temporary table platform_announcement_send as
select public.send_pachanga_platform_announcement_v1(
  (select (response ->> 'id')::uuid from platform_announcement), 1,
  'aa440000-0000-4000-8000-000000000002', 'Confirmed notification send'
) as response;
select pg_temp.assert_true(
  public.send_pachanga_platform_announcement_v1(
    (select (response ->> 'id')::uuid from platform_announcement), 1,
    'aa440000-0000-4000-8000-000000000002', 'Confirmed notification send'
  ) = (select response from platform_announcement_send),
  'Announcement send replay must return the canonical result'
);
select pg_temp.assert_true(
  pg_temp.platform_ledger_count('aa440000-0000-4000-8000-000000000001') = 1
  and pg_temp.platform_ledger_count('aa440000-0000-4000-8000-000000000002') = 1
  and pg_temp.notification_count(
    'aa100000-0000-4000-8000-000000000007', 'platform_announcement'
  ) = 1
  and (select count(*) from public.pachanga_user_notifications
       where recipient_user_id = 'aa100000-0000-4000-8000-000000000007') = 0,
  'Announcement draft and send must each audit once and notify once'
);
select pg_temp.expect_failure(
  $$select public.create_pachanga_platform_announcement_v1(
    'all', 'aa100000-0000-4000-8000-000000000007', 'Global', 'Forbidden global send', '/',
    'aa440000-0000-4000-8000-000000000003', 'Global send must remain disabled'
  )$$,
  'supported audience'
);

-- Client errors are aggregated and incident state is manual, never a sanction.
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.record_pachanga_client_error_v1(
  repeat('a', 64), '/partido', '2.0.0+test', 'render', 'Chrome', 'Android',
  'aa450000-0000-4000-8000-000000000001'
);
select public.record_pachanga_client_error_v1(
  repeat('a', 64), '/partido', '2.0.0+test', 'render', 'Chrome', 'Android',
  'aa450000-0000-4000-8000-000000000001'
);
select pg_temp.assert_true(
  pg_temp.telemetry_occurrences(repeat('a', 64), '/partido') = 1,
  'Telemetry operation replay must not inflate occurrence count'
);
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aa100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
create temporary table platform_incident as
select public.set_pachanga_platform_incident_v1(
  repeat('a', 64), 'investigating', 'Reproducción en curso', 0,
  'aa450000-0000-4000-8000-000000000002', 'Manual incident triage'
) as response;
select pg_temp.assert_true(
  public.set_pachanga_platform_incident_v1(
    repeat('a', 64), 'investigating', 'Reproducción en curso', 0,
    'aa450000-0000-4000-8000-000000000002', 'Manual incident triage'
  ) = (select response from platform_incident)
  and pg_temp.platform_user_state('aa100000-0000-4000-8000-000000000008') is null,
  'Incident handling must be idempotent and must never auto-ban a user'
);

-- Private authority and service-only sinks cannot be reached directly by clients.
reset role;
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_platform_admin_roles', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_platform_user_states', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_platform_admin_action_ledger', 'SELECT')
  and not has_function_privilege(
    'authenticated',
    'public.bootstrap_pachanga_platform_owner_v1(uuid,uuid,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.record_pachanga_client_error_v1(text,text,text,text,text,text,uuid)',
    'EXECUTE'
  ),
  'Clients must not read private authority or call service-only functions'
);
