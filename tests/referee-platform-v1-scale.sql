\set ON_ERROR_STOP on
\pset pager off

begin;
set local statement_timeout = '240s';
set local lock_timeout = '5s';
set local synchronous_commit = off;
set local work_mem = '128MB';

create or replace function pg_temp.r3_scale_uuid(namespace text, value bigint)
returns uuid
language sql
immutable
strict
as $$
  select (
    substring(hash from 1 for 8) || '-' || substring(hash from 9 for 4) || '-' ||
    substring(hash from 13 for 4) || '-' || substring(hash from 17 for 4) || '-' ||
    substring(hash from 21 for 12)
  )::uuid
  from (select md5(namespace || ':' || value::text) as hash) source;
$$;

create or replace function pg_temp.r3_scale_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table r3_scale_timings (
  metric text not null,
  elapsed_ms numeric not null
) on commit drop;

create or replace function pg_temp.r3_scale_measure(metric_name text, statement text, runs integer)
returns void
language plpgsql
as $$
declare
  started_at timestamptz;
  run integer;
begin
  for run in 1..runs loop
    started_at := clock_timestamp();
    execute statement;
    insert into r3_scale_timings(metric, elapsed_ms)
    values (metric_name, extract(epoch from clock_timestamp() - started_at) * 1000);
  end loop;
end;
$$;

-- The whole dataset is synthetic and transaction-scoped. The final ROLLBACK
-- leaves auth, product data, feature flags, and sequence-backed authorities untouched.
insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  pg_temp.r3_scale_uuid('r3-scale-user', profile_number),
  'r3-scale-' || profile_number || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'R3 Scale Referee ' || profile_number)
from generate_series(1, 10000) profile_number;

insert into public.pachanga_referee_profiles(
  id, user_id, slug, public_display_name_snapshot, bio, experience_since_year,
  experience_summary, operational_status, verification_status, visibility,
  marketplace_status, availability_status, available_for_assignments,
  share_recurring_availability, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  pg_temp.r3_scale_uuid('r3-scale-user', profile_number),
  'r3-scale-referee-' || profile_number,
  'R3 Scale Referee ' || profile_number,
  'Perfil sintético de escala para validar el dominio arbitral.',
  2000 + (profile_number % 20),
  'Experiencia declarada para pruebas locales de rendimiento.',
  'draft', case when profile_number % 5 = 0 then 'verified' else 'unverified' end,
  'private', 'not_listed', case when profile_number % 4 = 0 then 'LIMITED' else 'AVAILABLE' end,
  true, true, 1, 1000000000 + profile_number
from generate_series(1, 10000) profile_number;

insert into public.pachanga_referee_modalities(
  id, referee_profile_id, modality, active, experience_since_year, public_note,
  revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-modality', (profile_number - 1) * 5 + modality_number),
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  (array['FOOTBALL_11', 'FOOTBALL_7', 'FOOTBALL_5', 'FUTSAL', 'OTHER'])[modality_number],
  true, 2005 + modality_number, '', 1,
  1010000000 + (profile_number - 1) * 5 + modality_number
from generate_series(1, 5000) profile_number
cross join generate_series(1, 5) modality_number;

insert into public.pachanga_referee_service_areas(
  id, referee_profile_id, country_code, province, municipality, general_area,
  travel_radius_km, status, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-area', (profile_number - 1) * 5 + area_number),
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  'ES', 'Barcelona', 'Municipio ' || area_number,
  'R3 Scale Zone ' || area_number, 10 + area_number, 'active', 1,
  1020000000 + (profile_number - 1) * 5 + area_number
from generate_series(1, 5000) profile_number
cross join generate_series(1, 5) area_number;

insert into public.pachanga_referee_availability_windows(
  id, referee_profile_id, weekday, start_local_time, end_local_time, timezone,
  public_visible, status, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-window', (profile_number - 1) * 10 + window_number),
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  ((window_number - 1) % 7) + 1,
  make_time(7 + window_number, 0, 0), make_time(8 + window_number, 0, 0),
  'Europe/Madrid', window_number <= 3, 'active', 1,
  1030000000 + (profile_number - 1) * 10 + window_number
from generate_series(1, 10000) profile_number
cross join generate_series(1, 10) window_number;

insert into private.pachanga_publication_consents(
  operation_id, subject_kind, subject_id, actor_id, content_fingerprint,
  information_correct, unverified_not_certification, public_zones_availability,
  subject_revision
)
select
  pg_temp.r3_scale_uuid('r3-scale-consent', profile_number),
  'REFEREE_PROFILE',
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  pg_temp.r3_scale_uuid('r3-scale-user', profile_number),
  private.pachanga_referee_public_content_fingerprint_v1(pg_temp.r3_scale_uuid('r3-scale-profile', profile_number)),
  true, true, true, 1
from generate_series(1, 10000) profile_number;

update public.pachanga_referee_profiles profiles
set operational_status = 'active',
    visibility = 'public',
    marketplace_status = 'listed',
    revision = 2,
    server_sequence = 1090000000 + numbers.profile_number
from generate_series(1, 10000) as numbers(profile_number)
where profiles.id = pg_temp.r3_scale_uuid('r3-scale-profile', numbers.profile_number);

insert into public.pachanga_clubs(
  id, name, slug, description, club_type, primary_owner_id, created_by,
  visibility, operational_status, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-club', club_number),
  'R3 Scale Club ' || club_number, 'r3-scale-club-' || club_number,
  'Club sintético de escala', 'FOOTBALL_CLUB', pg_temp.r3_scale_uuid('r3-scale-user', 1),
  pg_temp.r3_scale_uuid('r3-scale-user', 1), 'private', 'active', 1,
  1040000000 + club_number
from generate_series(1, 2) club_number;

insert into public.pachanga_club_memberships(
  id, club_id, user_id, role, status, accepted_at, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-club-membership', club_number),
  pg_temp.r3_scale_uuid('r3-scale-club', club_number),
  pg_temp.r3_scale_uuid('r3-scale-user', 1), 'club_owner', 'active',
  clock_timestamp(), 1, 1041000000 + club_number
from generate_series(1, 2) club_number;

insert into public.pachanga_club_referee_relationships(
  id, club_id, referee_profile_id, target_kind, target_user_id,
  relationship_type, initiated_by, status, started_at, created_by,
  revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-relationship', (profile_number - 1) * 2 + club_number),
  pg_temp.r3_scale_uuid('r3-scale-club', club_number),
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  'registered_user', pg_temp.r3_scale_uuid('r3-scale-user', profile_number),
  case when club_number = 1 then 'REGULAR' else 'COLLABORATOR' end,
  'CLUB', 'active', clock_timestamp(), pg_temp.r3_scale_uuid('r3-scale-user', 1),
  1, 1050000000 + (profile_number - 1) * 2 + club_number
from generate_series(1, 10000) profile_number
cross join generate_series(1, 2) club_number;

insert into public.pachanga_canonical_matches(id, status, revision, server_sequence, created_by)
select
  pg_temp.r3_scale_uuid('r3-scale-match', assignment_number),
  'active', 1, 1060000000 + assignment_number,
  pg_temp.r3_scale_uuid('r3-scale-user', 1)
from generate_series(1, 100000) assignment_number;

insert into public.pachanga_referee_assignments(
  id, referee_profile_id, canonical_match_id, assignment_role, requester_kind,
  requester_club_id, source_kind, source_id, status, scheduled_start,
  scheduled_end, timezone, schedule_source_revision, proposed_by,
  authority_used, proposal_message, response_deadline, accepted_at,
  confirmed_at, revision, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-assignment', (profile_number - 1) * 10 + assignment_number),
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  pg_temp.r3_scale_uuid('r3-scale-match', (profile_number - 1) * 10 + assignment_number),
  'MAIN_REFEREE', 'CLUB',
  pg_temp.r3_scale_uuid('r3-scale-club', ((profile_number + assignment_number) % 2) + 1),
  'external_match', pg_temp.r3_scale_uuid('r3-scale-match', (profile_number - 1) * 10 + assignment_number)::text,
  case assignment_number when 1 then 'accepted' when 2 then 'confirmed' else 'proposed' end,
  timestamptz '2030-01-01 08:00:00+00' + (((profile_number - 1) * 10 + assignment_number) * interval '2 hours'),
  timestamptz '2030-01-01 09:30:00+00' + (((profile_number - 1) * 10 + assignment_number) * interval '2 hours'),
  'Europe/Madrid', 1, pg_temp.r3_scale_uuid('r3-scale-user', 1),
  'club_owner', '', timestamptz '2029-12-31 00:00:00+00',
  case when assignment_number in (1, 2) then clock_timestamp() else null end,
  case when assignment_number = 2 then clock_timestamp() else null end,
  1, 1070000000 + (profile_number - 1) * 10 + assignment_number
from generate_series(1, 10000) profile_number
cross join generate_series(1, 10) assignment_number;

insert into public.pachanga_referee_statistics_snapshots(
  referee_profile_id, proposals_received, assignments_accepted,
  assignments_confirmed, matches_completed, individual_matches_completed,
  competition_matches_completed, active_club_relationships,
  discipline_stats_status, revision, checksum, server_sequence
)
select
  pg_temp.r3_scale_uuid('r3-scale-profile', profile_number),
  10, 2, 1, 0, 0, 0, 2, 'NOT_AVAILABLE', 1, repeat('a', 64),
  1080000000 + profile_number
from generate_series(1, 10000) profile_number;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (pg_temp.r3_scale_uuid('r3-scale-user', 1), 'platform_owner', true);

update private.pachanga_referee_foundation_settings set
  referee_foundation_enabled = true,
  referee_self_service_enabled = true,
  referee_public_profiles_enabled = true,
  referee_marketplace_enabled = true,
  referee_club_relationships_enabled = true,
  referee_assignments_enabled = true
where singleton;

analyze public.pachanga_referee_profiles;
analyze public.pachanga_referee_modalities;
analyze public.pachanga_referee_service_areas;
analyze public.pachanga_referee_availability_windows;
analyze public.pachanga_club_referee_relationships;
analyze public.pachanga_referee_assignments;
analyze public.pachanga_referee_statistics_snapshots;

select pg_temp.r3_scale_assert((select count(*) from public.pachanga_referee_profiles where slug like 'r3-scale-referee-%') = 10000, 'Expected 10,000 RefereeProfiles');
select pg_temp.r3_scale_assert((
  select count(*) from public.pachanga_referee_modalities modalities
  join public.pachanga_referee_profiles profiles on profiles.id = modalities.referee_profile_id
  where profiles.slug like 'r3-scale-referee-%'
) + (
  select count(*) from public.pachanga_referee_service_areas areas
  join public.pachanga_referee_profiles profiles on profiles.id = areas.referee_profile_id
  where profiles.slug like 'r3-scale-referee-%'
) = 50000, 'Expected 50,000 modality/area rows');
select pg_temp.r3_scale_assert((select count(*) from public.pachanga_club_referee_relationships where server_sequence between 1050000001 and 1050020000) = 20000, 'Expected 20,000 Club-Referee relationships');
select pg_temp.r3_scale_assert((select count(*) from public.pachanga_referee_assignments where server_sequence between 1070000001 and 1070100000) = 100000, 'Expected 100,000 assignments');
select pg_temp.r3_scale_assert((select count(*) from public.pachanga_referee_availability_windows where server_sequence between 1030000001 and 1030100000) = 100000, 'Expected 100,000 availability windows');
select pg_temp.r3_scale_assert((select count(*) from public.pachanga_referee_statistics_snapshots where server_sequence between 1080000001 and 1080010000) = 10000, 'Expected 10,000 statistics snapshots');

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', pg_temp.r3_scale_uuid('r3-scale-user', 1), 'role', 'authenticated')::text,
  true
);

select pg_temp.r3_scale_measure('public_profile', $sql$
  select public.get_pachanga_public_referee_v1('r3-scale-referee-2500')
$sql$, 25);
select pg_temp.r3_scale_measure('private_profile', format($sql$
  select private.pachanga_referee_private_snapshot_v1(%L::uuid, %L::uuid)
$sql$, pg_temp.r3_scale_uuid('r3-scale-profile', 2500), pg_temp.r3_scale_uuid('r3-scale-user', 2500)), 20);
select pg_temp.r3_scale_measure('market_search', $sql$
  select public.search_pachanga_referee_market_v1('{"province":"Barcelona","modality":"FOOTBALL_7","availability":"AVAILABLE"}'::jsonb, 1, 24)
$sql$, 20);
select pg_temp.r3_scale_measure('club_relationship_lookup', format($sql$
  select public.get_pachanga_referee_club_v1(%L::uuid)
$sql$, pg_temp.r3_scale_uuid('r3-scale-club', 1)), 10);
select pg_temp.r3_scale_measure('admin_referee_list', $sql$
  select public.get_pachanga_platform_referees_v1('{"status":"active","modality":"FOOTBALL_7"}'::jsonb, 1, 50)
$sql$, 15);
select pg_temp.r3_scale_measure('assignment_conflict_check', format($sql$
  select exists (
    select 1 from public.pachanga_referee_assignments assignments
    where assignments.referee_profile_id = %L::uuid
      and assignments.status in ('accepted', 'confirmed')
      and tstzrange(assignments.scheduled_start, assignments.scheduled_end, '[)')
          && tstzrange(timestamptz '2030-01-02 00:00:00+00', timestamptz '2030-01-02 02:00:00+00', '[)')
  )
$sql$, pg_temp.r3_scale_uuid('r3-scale-profile', 2500)), 30);
select pg_temp.r3_scale_measure('stats_rebuild_query', format($sql$
  select count(*) filter (where status = 'completed'), count(*) filter (where status = 'confirmed')
  from public.pachanga_referee_assignments where referee_profile_id = %L::uuid
$sql$, pg_temp.r3_scale_uuid('r3-scale-profile', 2500)), 30);

create temporary table r3_scale_percentiles on commit drop as
select
  metric,
  round(percentile_cont(0.50) within group (order by elapsed_ms)::numeric, 3) as p50_ms,
  round(percentile_cont(0.95) within group (order by elapsed_ms)::numeric, 3) as p95_ms,
  count(*) as samples
from r3_scale_timings
group by metric;

table r3_scale_percentiles;

select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'public_profile') < 1000, 'Public profile p95 exceeded 1,000 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'private_profile') < 1500, 'Private profile p95 exceeded 1,500 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'market_search') < 2500, 'Market search p95 exceeded 2,500 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'club_relationship_lookup') < 5000, 'Club lookup p95 exceeded 5,000 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'admin_referee_list') < 3000, 'Admin list p95 exceeded 3,000 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'assignment_conflict_check') < 250, 'Conflict check p95 exceeded 250 ms');
select pg_temp.r3_scale_assert((select p95_ms from r3_scale_percentiles where metric = 'stats_rebuild_query') < 250, 'Stats rebuild query p95 exceeded 250 ms');

explain (analyze, buffers, format text)
select id from public.pachanga_referee_assignments
where referee_profile_id = pg_temp.r3_scale_uuid('r3-scale-profile', 2500)
  and status in ('accepted', 'confirmed')
order by scheduled_start desc, id desc
limit 20;

explain (analyze, buffers, format text)
select referee_profile_id from public.pachanga_referee_modalities
where modality = 'FOOTBALL_7' and active
order by referee_profile_id
limit 50;

rollback;
