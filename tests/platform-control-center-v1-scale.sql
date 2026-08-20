create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table platform_scale_users as
select
  index,
  md5('platform-control-center-scale-user-' || index::text)::uuid as user_id
from generate_series(1, 10000) index;

insert into auth.users(id, email, raw_user_meta_data)
select
  user_id,
  'platform-scale-' || lpad(index::text, 5, '0') || '@example.test',
  jsonb_build_object('full_name', 'Platform Scale User ' || lpad(index::text, 5, '0'))
from platform_scale_users;

create temporary table platform_scale_teams as
select
  index,
  md5('platform-control-center-scale-team-' || index::text)::uuid as group_id,
  (select users.user_id from platform_scale_users users where users.index = teams.index) as owner_id
from generate_series(1, 1000) teams(index);

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, billing_status,
  billing_trial_finalized_matches, ratings_enabled, externally_calibrated_level
)
select
  group_id,
  owner_id,
  'Platform Scale Team ' || lpad(index::text, 4, '0'),
  'SC' || lpad(index::text, 7, '0'),
  '{"players":[],"matches":[]}'::jsonb,
  case when index % 10 = 0 then 'past_due' else 'active' end,
  index % 5,
  true,
  50 + (index % 20)
from platform_scale_teams;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select group_id, owner_id, 'owner', 'Platform Scale Owner ' || lpad(index::text, 4, '0')
from platform_scale_teams;

insert into public.pachanga_challengeable_team_profiles(
  group_id, enabled, zone_label, zone_place_id, zone_lat, zone_lng,
  travel_radius_km, min_opponent_level, max_opponent_level, modalities,
  revision, created_by, updated_by
)
select
  group_id,
  index <= 500,
  case when index <= 500 then 'Madrid Scale' else null end,
  case when index <= 500 then 'scale-place-' || index::text else null end,
  case when index <= 500 then 40.4168 else null end,
  case when index <= 500 then -3.7038 else null end,
  20, 40, 80,
  case when index <= 500 then array['futbol7']::text[] else '{}'::text[] end,
  1, owner_id, owner_id
from platform_scale_teams;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
select user_id, 'platform_owner', true from platform_scale_users where index = 1;

grant select on platform_scale_users, platform_scale_teams to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select user_id from platform_scale_users where index = 1),
    'role', 'authenticated'
  )::text,
  true
);

create temporary table platform_scale_measurements(
  operation text primary key,
  duration_ms numeric not null,
  returned_items integer not null,
  total_items integer not null
);

create temporary table platform_scale_user_started as select clock_timestamp() as measured_at;
create temporary table platform_scale_user_page_one as
select public.list_pachanga_platform_users_v1('platform-scale-', 'all', null, null, 'created_desc', 100, 0) as response;
insert into platform_scale_measurements
select
  'users_first_page',
  extract(epoch from (clock_timestamp() - measured_at)) * 1000,
  jsonb_array_length((select response -> 'items' from platform_scale_user_page_one)),
  ((select response ->> 'total' from platform_scale_user_page_one))::integer
from platform_scale_user_started;

create temporary table platform_scale_user_last_started as select clock_timestamp() as measured_at;
create temporary table platform_scale_user_last_page as
select public.list_pachanga_platform_users_v1('platform-scale-', 'all', null, null, 'created_desc', 100, 9900) as response;
insert into platform_scale_measurements
select
  'users_last_page',
  extract(epoch from (clock_timestamp() - measured_at)) * 1000,
  jsonb_array_length((select response -> 'items' from platform_scale_user_last_page)),
  ((select response ->> 'total' from platform_scale_user_last_page))::integer
from platform_scale_user_last_started;

create temporary table platform_scale_team_started as select clock_timestamp() as measured_at;
create temporary table platform_scale_team_page as
select public.list_pachanga_platform_teams_v1(
  'Platform Scale Team', 'all', 'enabled', 'Madrid', null,
  'active', 'clean', 50, 70, null, null, 'updated_desc', 100, 0
) as response;
insert into platform_scale_measurements
select
  'teams_filtered_page',
  extract(epoch from (clock_timestamp() - measured_at)) * 1000,
  jsonb_array_length((select response -> 'items' from platform_scale_team_page)),
  ((select response ->> 'total' from platform_scale_team_page))::integer
from platform_scale_team_started;

select pg_temp.assert_true(
  (select returned_items = 100 and total_items = 10000
   from platform_scale_measurements where operation = 'users_first_page')
  and (select returned_items = 100 and total_items = 10000
       from platform_scale_measurements where operation = 'users_last_page'),
  '10,000 users must remain server-paginated with exact totals'
);
select pg_temp.assert_true(
  (select returned_items <= 100 and total_items = 500
   from platform_scale_measurements where operation = 'teams_filtered_page'),
  '1,000 teams must be filtered before pagination with an exact 500-row total'
);
select pg_temp.assert_true(
  not exists (
    select first_page.item ->> 'id'
    from jsonb_array_elements((select response -> 'items' from platform_scale_user_page_one)) first_page(item)
    intersect
    select last_page.item ->> 'id'
    from jsonb_array_elements((select response -> 'items' from platform_scale_user_last_page)) last_page(item)
  ),
  'Stable ordering must keep first and last user pages disjoint'
);
select pg_temp.assert_true(
  (select max(duration_ms) < 10000 from platform_scale_measurements),
  'Each representative 10k/1k page must complete below the 10 second stop threshold'
);
select pg_temp.assert_true(
  not exists (select 1 from pg_catalog.pg_locks where pid = pg_backend_pid() and not granted),
  'The volume run must leave no waiting lock in its backend'
);

select jsonb_build_object(
  'fixtureUsers', 10000,
  'fixtureTeams', 1000,
  'measurements', (
    select jsonb_object_agg(operation, jsonb_build_object(
      'durationMs', round(duration_ms, 2),
      'returnedItems', returned_items,
      'totalItems', total_items
    )) from platform_scale_measurements
  ),
  'stopThresholdMs', 10000,
  'waitingLocks', 0,
  'cpu', 'not exposed by local PostgreSQL'
) as platform_control_center_scale_result;
