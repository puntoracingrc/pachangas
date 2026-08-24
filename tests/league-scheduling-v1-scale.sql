\set ON_ERROR_STOP on

set local lock_timeout = '5s';
set local statement_timeout = '180s';

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select md5('r4b-scale-team-' || value)::uuid,
  'e4010000-0000-4000-8000-000000000002'::uuid,
  'R4B Scale Team ' || value,
  'R4BS' || lpad(value::text, 4, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb,
  1
from generate_series(1, 20) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select md5('r4b-scale-team-' || value)::uuid,
  'e4010000-0000-4000-8000-000000000002'::uuid,
  'admin',
  'Scale manager'
from generate_series(1, 20) value;

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source, status,
  rule_revision_id, accepted_by, accepted_at, reason_code, created_by
)
select md5('r4b-scale-entry-' || value)::uuid,
  'e4040000-0000-4000-8000-000000000001'::uuid,
  'e4070000-0000-4000-8000-000000000001'::uuid,
  'e40b0000-0000-4000-8000-000000000001'::uuid,
  md5('r4b-scale-team-' || value)::uuid,
  'ORGANIZER_INVITATION', 'accepted',
  'e4060000-0000-4000-8000-000000000001'::uuid,
  'e4010000-0000-4000-8000-000000000002'::uuid,
  clock_timestamp(), 'r4b.scale.accepted',
  'e4010000-0000-4000-8000-000000000002'::uuid
from generate_series(1, 20) value;

insert into public.pachanga_team_availability_constraints(
  id, entry_id, weekday, start_local_time, end_local_time, timezone,
  valid_from_date, valid_until_date, reason, created_by
)
select md5('r4b-scale-constraint-' || value)::uuid,
  md5('r4b-scale-entry-' || ((value - 1) % 20 + 1))::uuid,
  ((value - 1) % 7 + 1), '08:00'::time, '09:00'::time, 'Europe/Madrid',
  '2027-01-01'::date, '2027-12-31'::date, 'Scale hard constraint',
  'e4010000-0000-4000-8000-000000000002'::uuid
from generate_series(1, 5000) value;

insert into public.pachanga_team_schedule_preferences(
  id, entry_id, weekday, start_local_time, end_local_time, timezone,
  weight, preferred_area, status, created_by
)
select md5('r4b-scale-preference-' || value)::uuid,
  md5('r4b-scale-entry-' || ((value - 1) % 20 + 1))::uuid,
  ((value - 1) % 7 + 1), '18:00'::time, '22:00'::time, 'Europe/Madrid',
  ((value - 1) % 100 + 1), 'Barcelona', 'active',
  'e4010000-0000-4000-8000-000000000002'::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_schedule_plans(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, rule_revision_id, engine_version, legs, entry_count,
  status, revision, created_by
)
select md5('r4b-scale-plan-' || value)::uuid,
  'e4040000-0000-4000-8000-000000000001'::uuid,
  'e4070000-0000-4000-8000-000000000001'::uuid,
  'e40b0000-0000-4000-8000-000000000001'::uuid,
  'e4080000-0000-4000-8000-000000000001'::uuid,
  'e4090000-0000-4000-8000-000000000001'::uuid,
  'e40a0000-0000-4000-8000-000000000001'::uuid,
  'e4060000-0000-4000-8000-000000000001'::uuid,
  'league-round-robin-v1', 2, 20, 'superseded', 1,
  'e4010000-0000-4000-8000-000000000003'::uuid
from generate_series(1, 250) value;

insert into public.pachanga_competition_schedule_revisions(
  id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
  input_checksum, rule_revision_id, entry_snapshot_checksum, slot_snapshot_checksum,
  constraint_snapshot_checksum, preference_snapshot_checksum, entry_order,
  quality_score, validation_status, generated_by
)
select md5('r4b-scale-revision-' || value)::uuid,
  md5('r4b-scale-plan-' || value)::uuid,
  1, 'generated', 'superseded', 'league-round-robin-v1', 'scale-' || value,
  repeat('a', 64), 'e4060000-0000-4000-8000-000000000001'::uuid,
  repeat('b', 64), repeat('c', 64), repeat('d', 64), repeat('e', 64),
  (select jsonb_agg(md5('r4b-scale-entry-' || entry)::uuid order by entry) from generate_series(1, 20) entry),
  88.5, 'VALID', 'e4010000-0000-4000-8000-000000000003'::uuid
from generate_series(1, 250) value;

insert into public.pachanga_competition_rounds(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, schedule_revision_id, round_number, leg_number,
  display_name, status, rule_revision_id, created_by
)
select md5('r4b-scale-round-' || plan || '-' || round_number)::uuid,
  'e4040000-0000-4000-8000-000000000001'::uuid,
  'e4070000-0000-4000-8000-000000000001'::uuid,
  'e40b0000-0000-4000-8000-000000000001'::uuid,
  'e4080000-0000-4000-8000-000000000001'::uuid,
  'e4090000-0000-4000-8000-000000000001'::uuid,
  'e40a0000-0000-4000-8000-000000000001'::uuid,
  md5('r4b-scale-revision-' || plan)::uuid,
  round_number,
  case when round_number <= 19 then 1 else 2 end,
  'Jornada ' || round_number,
  'draft',
  'e4060000-0000-4000-8000-000000000001'::uuid,
  'e4010000-0000-4000-8000-000000000003'::uuid
from generate_series(1, 250) plan
cross join generate_series(1, 38) round_number;

create temporary table r4b_scale_pairs on commit drop as
select home, away, leg,
  row_number() over (order by leg, home, away) as fixture_number,
  least(md5('r4b-scale-entry-' || home)::uuid, md5('r4b-scale-entry-' || away)::uuid)::text
    || ':' ||
  greatest(md5('r4b-scale-entry-' || home)::uuid, md5('r4b-scale-entry-' || away)::uuid)::text as pairing_key
from generate_series(1, 20) home
join generate_series(1, 20) away on away > home
cross join generate_series(1, 2) leg;

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, division_id, competition_group_id,
  starts_at, ends_at, timezone, venue_label, resource_key, status, created_by
)
select md5('r4b-scale-slot-' || plan || '-' || pairs.fixture_number)::uuid,
  'e4040000-0000-4000-8000-000000000001'::uuid,
  'e4070000-0000-4000-8000-000000000001'::uuid,
  'e4080000-0000-4000-8000-000000000001'::uuid,
  'e4090000-0000-4000-8000-000000000001'::uuid,
  'e40a0000-0000-4000-8000-000000000001'::uuid,
  '2027-02-01T18:00:00Z'::timestamptz + ((plan * 400 + pairs.fixture_number) * interval '2 hours'),
  '2027-02-01T19:30:00Z'::timestamptz + ((plan * 400 + pairs.fixture_number) * interval '2 hours'),
  'Europe/Madrid', 'Scale venue',
  'scale-resource-' || plan || '-' || pairs.fixture_number,
  'assigned', 'e4010000-0000-4000-8000-000000000003'::uuid
from generate_series(1, 250) plan
cross join r4b_scale_pairs pairs;

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id, pairing_key,
  leg_number, slot_id, scheduled_start, scheduled_end, timezone, venue_label,
  venue_status, status
)
select md5('r4b-scale-item-' || plan || '-' || pairs.fixture_number)::uuid,
  md5('r4b-scale-revision-' || plan)::uuid,
  md5('r4b-scale-round-' || plan || '-' || (((pairs.fixture_number - 1) % 38) + 1))::uuid,
  md5('r4b-scale-entry-' || case when pairs.leg = 1 then pairs.home else pairs.away end)::uuid,
  md5('r4b-scale-entry-' || case when pairs.leg = 1 then pairs.away else pairs.home end)::uuid,
  pairs.pairing_key, pairs.leg,
  md5('r4b-scale-slot-' || plan || '-' || pairs.fixture_number)::uuid,
  slots.starts_at, slots.ends_at, slots.timezone, slots.venue_label,
  'CONFIRMED', 'validated'
from generate_series(1, 250) plan
cross join r4b_scale_pairs pairs
join public.pachanga_competition_schedule_slots slots
  on slots.id = md5('r4b-scale-slot-' || plan || '-' || pairs.fixture_number)::uuid;

analyze public.pachanga_competition_schedule_plans;
analyze public.pachanga_competition_schedule_revisions;
analyze public.pachanga_competition_schedule_slots;
analyze public.pachanga_competition_rounds;
analyze public.pachanga_competition_schedule_items;
analyze public.pachanga_team_availability_constraints;
analyze public.pachanga_team_schedule_preferences;

create or replace function pg_temp.r4b_explain(target_query text)
returns jsonb language plpgsql as $$
declare result jsonb;
begin
  execute 'explain (analyze, buffers, format json) ' || target_query into result;
  return result -> 0;
end;
$$;

create temporary table r4b_scale_query_plans(
  name text primary key,
  evidence jsonb not null
) on commit drop;

insert into r4b_scale_query_plans(name, evidence)
select source.name, jsonb_build_object(
  'actualRows', (source.plan #>> '{Plan,Actual Rows}')::numeric,
  'executionMs', (source.plan ->> 'Execution Time')::numeric,
  'indexes', jsonb_path_query_array(source.plan, 'strict $.**."Index Name"'),
  'planningMs', (source.plan ->> 'Planning Time')::numeric,
  'rootNode', source.plan #>> '{Plan,Node Type}'
)
from (
  select 'pairLookup' as name, pg_temp.r4b_explain($query$
    select id from public.pachanga_competition_schedule_items
    where schedule_revision_id = md5('r4b-scale-revision-1')::uuid
      and pairing_key = least(md5('r4b-scale-entry-1')::uuid, md5('r4b-scale-entry-2')::uuid)::text
        || ':' || greatest(md5('r4b-scale-entry-1')::uuid, md5('r4b-scale-entry-2')::uuid)::text
      and leg_number = 1
  $query$) as plan
  union all
  select 'slotConflict', pg_temp.r4b_explain($query$
    select id from public.pachanga_competition_schedule_slots
    where resource_key = 'scale-resource-1-1'
      and status <> 'retired'
  $query$)
  union all
  select 'teamOverlap', pg_temp.r4b_explain($query$
    select id from public.pachanga_competition_schedule_items
    where schedule_revision_id = md5('r4b-scale-revision-1')::uuid
      and (home_entry_id = md5('r4b-scale-entry-1')::uuid
        or away_entry_id = md5('r4b-scale-entry-1')::uuid)
  $query$)
  union all
  select 'constraints', pg_temp.r4b_explain($query$
    select id from public.pachanga_team_availability_constraints
    where entry_id = md5('r4b-scale-entry-1')::uuid
      and valid_from_date <= '2027-06-01'::date
      and valid_until_date >= '2027-06-01'::date
  $query$)
  union all
  select 'preferences', pg_temp.r4b_explain($query$
    select id from public.pachanga_team_schedule_preferences
    where entry_id = md5('r4b-scale-entry-1')::uuid and status = 'active'
  $query$)
  union all
  select 'roundRead', pg_temp.r4b_explain($query$
    select id from public.pachanga_competition_schedule_items
    where schedule_revision_id = md5('r4b-scale-revision-1')::uuid
      and round_id = md5('r4b-scale-round-1-1')::uuid
  $query$)
) source;

select jsonb_build_object(
  'stages', 250,
  'teamsPerStage', 20,
  'legs', 2,
  'items', (select count(*) from public.pachanga_competition_schedule_items where id::text is not null and schedule_revision_id in (select md5('r4b-scale-revision-' || value)::uuid from generate_series(1, 250) value)),
  'slots', (select count(*) from public.pachanga_competition_schedule_slots where resource_key like 'scale-resource-%'),
  'constraints', (select count(*) from public.pachanga_team_availability_constraints where reason = 'Scale hard constraint'),
  'preferences', (select count(*) from public.pachanga_team_schedule_preferences where preferred_area = 'Barcelona' and entry_id in (select md5('r4b-scale-entry-' || value)::uuid from generate_series(1, 20) value)),
  'planLookup', (select count(*) from public.pachanga_competition_schedule_plans where status = 'superseded'),
  'teamCalendarLookup', (select count(*) from public.pachanga_competition_schedule_items where home_entry_id = md5('r4b-scale-entry-1')::uuid or away_entry_id = md5('r4b-scale-entry-1')::uuid),
  'roundLookup', (select count(*) from public.pachanga_competition_schedule_items where round_id = md5('r4b-scale-round-1-1')::uuid),
  'queryPlans', (select jsonb_object_agg(name, evidence order by name) from r4b_scale_query_plans)
)::text;
