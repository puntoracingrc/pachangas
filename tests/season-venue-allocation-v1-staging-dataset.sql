-- Wave 9B authenticated staging topology.
-- All rows are synthetic, non-indexed and confined to a disposable Supabase branch.

\set ON_ERROR_STOP on

begin;

do $$
begin
  if exists (select 1 from public.pachanga_groups)
     or exists (select 1 from public.pachanga_clubs)
     or exists (select 1 from public.pachanga_player_profiles)
     or exists (select 1 from public.pachanga_competitions)
     or exists (select 1 from public.pachanga_canonical_matches) then
    raise exception 'WAVE9B_STAGING_DATASET_REQUIRES_EMPTY_BRANCH';
  end if;
end;
$$;

\ir season-venue-allocation-v1-fixture.sql

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values (
  'e9b90000-0000-4000-8000-000000000100',
  'wave9b-staging-platform-authority@pachangasiq.test',
  clock_timestamp(),
  '{"full_name":"Wave 9B Staging Platform Authority","qaFixture":"SEASON_VENUE_ALLOCATION_V1"}'
);
insert into private.pachanga_platform_admin_roles(user_id, role, active, granted_by)
values (
  'e9b90000-0000-4000-8000-000000000100', 'platform_admin', true,
  'e9b90000-0000-4000-8000-000000000100'
);
select set_config('request.jwt.claim.sub', 'e9b90000-0000-4000-8000-000000000100', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"e9b90000-0000-4000-8000-000000000100","role":"authenticated"}',
  true
);

do $$
declare settings_revision bigint;
declare referee_revision bigint;
begin
  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_competition_platform_v1(
    'e9b90000-0000-4000-8000-000000000101',
    '00000000-0000-0000-0000-00000000c001',
    settings_revision,
    'foundation_flags.set',
    jsonb_build_object(
      'foundationEnabled', true,
      'creationEnabled', true,
      'contextBindingEnabled', true,
      'reason', 'Wave 9B synthetic staging setup'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_league_participation_platform_v1(
    'e9b90000-0000-4000-8000-000000000103',
    '00000000-0000-0000-0000-00000000c4a1',
    settings_revision,
    jsonb_build_object(
      'foundationEnabled', true,
      'registrationEnabled', true,
      'publicRegistrationEnabled', false,
      'delegatesEnabled', true,
      'rostersEnabled', true,
      'schedulePreferencesEnabled', true,
      'reason', 'Wave 9B synthetic participation dependencies'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_league_scheduling_platform_v1(
    'e9b90000-0000-4000-8000-000000000104',
    '00000000-0000-0000-0000-00000000c4b1',
    settings_revision,
    jsonb_build_object(
      'foundationEnabled', true,
      'generationEnabled', true,
      'editingEnabled', true,
      'publicationEnabled', true,
      'publicCalendarEnabled', false,
      'canonicalFixtureCreationEnabled', true,
      'reason', 'Wave 9B synthetic scheduling dependencies'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_league_match_operations_platform_v1(
    'e9b90000-0000-4000-8000-000000000105',
    '00000000-0000-0000-0000-00000000c4c1',
    settings_revision,
    jsonb_build_object(
      'foundationEnabled', true,
      'squadsEnabled', true,
      'attendanceEnabled', true,
      'sportingResultsEnabled', true,
      'resultConfirmationEnabled', true,
      'officialResultsEnabled', true,
      'standingsEnabled', true,
      'publicStandingsEnabled', false,
      'reason', 'Wave 9B synthetic match operation dependencies'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_league_operational_exceptions_platform_v1(
    'e9b90000-0000-4000-8000-000000000106',
    '00000000-0000-0000-0000-00000000c4d1',
    settings_revision,
    jsonb_build_object(
      'foundationEnabled', true,
      'postponementsEnabled', true,
      'reschedulingEnabled', true,
      'venueChangesEnabled', true,
      'lateArrivalEnabled', true,
      'noShowEnabled', true,
      'matchSuspensionsEnabled', true,
      'administrativeDecisionsEnabled', true,
      'publicExceptionStatusEnabled', false,
      'reason', 'Wave 9B synthetic operational dependencies'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into referee_revision
  from private.pachanga_referee_foundation_settings
  where singleton;
  perform public.command_pachanga_referee_assignment_beta_admin_v1(
    'e9b90000-0000-4000-8000-000000000108',
    referee_revision,
    'assignment_beta.flags.set',
    jsonb_build_object(
      'assignmentPrivateBetaEnabled', false,
      'assignmentsEnabled', false,
      'reason', 'Wave 9B synthetic League creation dependency'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into settings_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  perform public.command_pachanga_league_private_beta_platform_v1(
    'e9b90000-0000-4000-8000-000000000107',
    '00000000-0000-0000-0000-00000000b201',
    settings_revision,
    'beta.flags.set',
    jsonb_build_object(
      'enabled', true,
      'creationEnabled', true,
      'publicDiscoveryEnabled', false,
      'reason', 'Wave 9B synthetic beta creation after dependencies'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );

  select revision into referee_revision
  from private.pachanga_referee_foundation_settings
  where singleton;
  perform public.command_pachanga_referee_assignment_beta_admin_v1(
    'e9b90000-0000-4000-8000-000000000109',
    referee_revision,
    'assignment_beta.flags.set',
    jsonb_build_object(
      'assignmentPrivateBetaEnabled', true,
      'assignmentsEnabled', true,
      'reason', 'Wave 9B synthetic referee assignment verification'
    ),
    '{"clientVersion":"wave9b-staging","operationSource":"simulation_world"}'::jsonb
  );
  perform set_config('pachangas.league_private_beta_authorized', 'on', true);
end;
$$;

do $$
begin
  if (select count(*) from public.pachanga_clubs) <> 1
     or (select count(*) from public.pachanga_groups) <> 3
     or (select count(*) from public.pachanga_player_profiles) <> 3
     or (select count(*) from public.pachanga_referee_profiles) <> 4
     or (select count(*) from public.pachanga_club_venues) <> 1
     or (select count(*) from public.pachanga_venue_pitches) <> 2
     or (select count(*) from public.pachanga_competitions where competition_type = 'LEAGUE') <> 1
     or (select count(*) from public.pachanga_competitions where competition_type = 'TOURNAMENT') <> 0
     or (select count(*) from public.pachanga_canonical_matches) <> 6 then
    raise exception 'WAVE9B_STAGING_BASE_TOPOLOGY_CHANGED';
  end if;
end;
$$;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  md5('wave9b-staging-team-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'Wave 9B Synthetic Team ' || number,
  'W9B' || lpad(number::text, 7, '0'),
  jsonb_build_object(
    'matches', '[]'::jsonb,
    'players', '[]'::jsonb,
    'siteSettings', jsonb_build_object('synthetic', true),
    'venues', '[]'::jsonb
  )
from generate_series(1, 9) number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  md5('wave9b-staging-team-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'owner',
  'Wave 9B Synthetic Owner'
from generate_series(1, 9) number;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  md5('wave9b-staging-player-' || number)::uuid,
  'wave9b-staging-player-' || number || '@pachangasiq.test',
  clock_timestamp(),
  jsonb_build_object(
    'full_name', 'Wave 9B Player ' || number,
    'qaFixture', 'SEASON_VENUE_ALLOCATION_V1'
  )
from generate_series(1, 117) number;

insert into public.pachanga_player_profiles(id, user_id, display_name)
select
  md5('wave9b-staging-player-profile-' || number)::uuid,
  md5('wave9b-staging-player-' || number)::uuid,
  'Wave 9B Player ' || number
from generate_series(1, 117) number;

with numbered_teams as (
  select id, row_number() over (order by id) as team_number
  from public.pachanga_groups
), players as (
  select
    number,
    md5('wave9b-staging-player-' || number)::uuid as user_id,
    ((number - 1) % 12) + 1 as team_number
  from generate_series(1, 117) number
)
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select teams.id, players.user_id, 'player', 'Wave 9B Player ' || players.number
from players
join numbered_teams teams using (team_number);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  md5('wave9b-staging-referee-' || number)::uuid,
  'wave9b-staging-referee-' || number || '@pachangasiq.test',
  clock_timestamp(),
  jsonb_build_object(
    'full_name', 'Wave 9B Referee ' || number,
    'qaFixture', 'SEASON_VENUE_ALLOCATION_V1'
  )
from generate_series(1, 2) number;

insert into public.pachanga_referee_profiles(
  id, user_id, slug, public_display_name_snapshot
)
select
  md5('wave9b-staging-referee-profile-' || number)::uuid,
  md5('wave9b-staging-referee-' || number)::uuid,
  'wave9b-staging-referee-' || number,
  'Wave 9B Referee ' || number
from generate_series(1, 2) number;

insert into public.pachanga_clubs(
  id, name, slug, description, club_type, country_code, province,
  municipality, general_area, visibility, operational_status,
  verification_status, partnership_status, primary_owner_id, created_by
)
select
  md5('wave9b-staging-club-' || number)::uuid,
  'Wave 9B Synthetic Club ' || number,
  'wave9b-staging-club-' || number,
  'Synthetic Club confined to the disposable Wave 9B staging branch.',
  'SPORTS_CENTER', 'ES', 'Synthetic Province', 'Synthetic Municipality',
  'Synthetic Zone ' || number, 'private', 'active', 'unverified', 'none',
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid
from generate_series(2, 3) number;

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, accepted_at, invited_by
)
select
  md5('wave9b-staging-club-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'club_owner', 'active', clock_timestamp(),
  'e9010000-0000-4000-8000-000000000001'::uuid
from generate_series(2, 3) number;

with clubs as (
  select id, row_number() over (order by id) as club_number
  from public.pachanga_clubs
)
insert into public.pachanga_club_venues(
  id, club_id, name, slug, description, municipality, general_area,
  timezone, private_address, visibility, lifecycle, operation_id,
  created_by, updated_by
)
select
  md5('wave9b-staging-venue-' || number)::uuid,
  clubs.id,
  'Wave 9B Synthetic Venue ' || number,
  'wave9b-staging-venue-' || number,
  'Synthetic Venue confined to the disposable Wave 9B staging branch.',
  'Synthetic Municipality', 'Synthetic Zone ' || number, 'Europe/Madrid',
  'Synthetic private address ' || number, 'PRIVATE', 'ACTIVE',
  md5('wave9b-staging-venue-operation-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid
from generate_series(2, 6) number
join clubs on clubs.club_number = ((number - 1) % 3) + 1;

insert into public.pachanga_venue_pitches(
  id, venue_id, conflict_scope_id, name, slug, modalities, surface,
  environment, has_lighting, status, visibility, minimum_slot_minutes,
  buffer_minutes, operation_id, created_by, updated_by
)
select
  md5('wave9b-staging-pitch-' || number)::uuid,
  md5('wave9b-staging-venue-' || (((number - 1) / 2) + 2))::uuid,
  md5('wave9b-staging-pitch-' || number)::uuid,
  'Wave 9B Pitch ' || number,
  'wave9b-pitch-' || number,
  array['F7']::text[], 'ARTIFICIAL_GRASS', 'OUTDOOR', true,
  'ACTIVE', 'PRIVATE', 60, 5,
  md5('wave9b-staging-pitch-operation-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10) number;

insert into public.pachanga_venue_availability_templates(
  id, venue_id, pitch_id, weekday, start_local_time, end_local_time,
  slot_minutes, buffer_minutes, valid_from, valid_until, timezone,
  modalities, capacity, visibility, status, operation_id, created_by, updated_by
)
select
  md5('wave9b-staging-availability-' || number)::uuid,
  md5('wave9b-staging-venue-' || (((number - 1) / 2) + 2))::uuid,
  md5('wave9b-staging-pitch-' || number)::uuid,
  1, '17:00'::time, '23:00'::time, 60, 5,
  '2027-01-01'::date, '2027-12-31'::date, 'Europe/Madrid',
  array['F7']::text[], 1, 'PRIVATE', 'ACTIVE',
  md5('wave9b-staging-availability-operation-' || number)::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid,
  'e9010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10) number;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by, description, product_key
) values (
  'e9b90000-0000-4000-8000-000000000001', 'TEAM',
  'c4100000-0000-4000-8000-000000000001',
  'Wave 9B Synthetic Tournament', 'wave9b-synthetic-tournament',
  'TOURNAMENT', 'private', 'draft',
  'c4010000-0000-4000-8000-000000000002',
  'Synthetic tournament confined to the disposable Wave 9B staging branch.',
  'TOURNAMENT_PRIVATE_BETA_V1'
);

insert into public.pachanga_canonical_matches(id, status, revision, created_by)
select
  md5('wave9b-staging-canonical-match-' || number)::uuid,
  'active', 1,
  'c4010000-0000-4000-8000-000000000002'::uuid
from generate_series(1, 44) number;

do $$
declare topology jsonb;
begin
  topology := jsonb_build_object(
    'clubs', (select count(*) from public.pachanga_clubs),
    'teams', (select count(*) from public.pachanga_groups),
    'players', (select count(*) from public.pachanga_player_profiles),
    'referees', (select count(*) from public.pachanga_referee_profiles),
    'venues', (select count(*) from public.pachanga_club_venues),
    'pitches', (select count(*) from public.pachanga_venue_pitches),
    'leagues', (select count(*) from public.pachanga_competitions where competition_type = 'LEAGUE'),
    'tournaments', (select count(*) from public.pachanga_competitions where competition_type = 'TOURNAMENT'),
    'matches', (select count(*) from public.pachanga_canonical_matches)
  );
  if topology <> '{"clubs":3,"teams":12,"players":120,"referees":6,"venues":6,"pitches":12,"leagues":1,"tournaments":1,"matches":50}'::jsonb then
    raise exception 'WAVE9B_STAGING_TOPOLOGY_INVALID: %', topology;
  end if;
end;
$$;

select json_build_object(
  'status', 'WAVE9B_STAGING_DATASET_PASS',
  'clubs', (select count(*) from public.pachanga_clubs),
  'teams', (select count(*) from public.pachanga_groups),
  'players', (select count(*) from public.pachanga_player_profiles),
  'referees', (select count(*) from public.pachanga_referee_profiles),
  'venues', (select count(*) from public.pachanga_club_venues),
  'pitches', (select count(*) from public.pachanga_venue_pitches),
  'leagues', (select count(*) from public.pachanga_competitions where competition_type = 'LEAGUE'),
  'tournaments', (select count(*) from public.pachanga_competitions where competition_type = 'TOURNAMENT'),
  'matches', (select count(*) from public.pachanga_canonical_matches)
) as result;

commit;
