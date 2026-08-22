\set ON_ERROR_STOP on
\pset pager off

begin;
set local statement_timeout = '300s';
set local lock_timeout = '5s';
set local synchronous_commit = off;
set local work_mem = '192MB';

create or replace function pg_temp.r4a_scale_uuid(namespace text, value bigint)
returns uuid language sql immutable strict as $$
  select (
    substring(hash from 1 for 8) || '-' || substring(hash from 9 for 4) || '-' ||
    substring(hash from 13 for 4) || '-' || substring(hash from 17 for 4) || '-' ||
    substring(hash from 21 for 12)
  )::uuid
  from (select md5(namespace || ':' || value::text) as hash) source;
$$;

create or replace function pg_temp.r4a_scale_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table r4a_scale_timings(
  metric text not null,
  elapsed_ms numeric not null
) on commit drop;

create or replace function pg_temp.r4a_scale_measure(metric_name text, statement text, runs integer)
returns void language plpgsql as $$
declare started_at timestamptz; run integer;
begin
  for run in 1..runs loop
    started_at := clock_timestamp();
    execute statement;
    insert into r4a_scale_timings(metric, elapsed_ms)
    values (metric_name, extract(epoch from clock_timestamp() - started_at) * 1000);
  end loop;
end;
$$;

-- Synthetic scale data is isolated by this transaction. No sequence, flag,
-- auth record or product row survives the final rollback.
insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  pg_temp.r4a_scale_uuid('r4a-scale-user', user_number),
  'r4a-scale-' || user_number || '@example.test',
  clock_timestamp(), jsonb_build_object('full_name', 'R4A Scale User ' || user_number)
from generate_series(1, 150000) user_number;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select
  pg_temp.r4a_scale_uuid('r4a-scale-team', team_number),
  pg_temp.r4a_scale_uuid('r4a-scale-user', team_number),
  'R4A Scale Team ' || team_number,
  'R4S' || lpad(team_number::text, 5, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb, 1
from generate_series(1, 200) team_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  pg_temp.r4a_scale_uuid('r4a-scale-team', team_number),
  pg_temp.r4a_scale_uuid('r4a-scale-user', team_number),
  'owner', 'R4A Scale Owner ' || team_number
from generate_series(1, 200) team_number;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name, birth_date,
  rating, current_overall, base_facets, calibrated_facets, current_facets, position
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-profile', profile_number),
  pg_temp.r4a_scale_uuid('r4a-scale-user', profile_number),
  case when profile_number <= 200 then pg_temp.r4a_scale_uuid('r4a-scale-team', profile_number) else null end,
  'r4a-scale-player-' || profile_number,
  'R4A Scale Player ' || profile_number,
  date '1990-01-01' + ((profile_number % 5000)::integer),
  6.5, 65, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 'Mediocentro / pivote'
from generate_series(1, 150000) profile_number;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (pg_temp.r4a_scale_uuid('r4a-scale-user', 1), 'platform_owner', true);

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_public_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true
where singleton;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  pg_temp.r4a_scale_uuid('r4a-scale-competition', 1), 'TEAM',
  pg_temp.r4a_scale_uuid('r4a-scale-team', 1), 'R4A Scale League',
  'r4a-scale-league', 'LEAGUE', 'public', 'draft',
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
);

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source,
  status, reason, granted_by
) values (
  'TEAM', pg_temp.r4a_scale_uuid('r4a-scale-team', 1),
  'competition_manage', 'platform_grant', 'active',
  'R4A transaction-scoped scale entitlement',
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
);

insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values (
  pg_temp.r4a_scale_uuid('r4a-scale-ruleset', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-competition', 1),
  'R4A Scale Rules', 'active', pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
);

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-ruleset', 1), 1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'published', 1,
  'R4A transaction-scoped scale rules', pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{
    "registrationPolicy":{"teamLimits":{"minimum":0,"maximum":100}},
    "rosterPolicy":{"minimumSize":1,"maximumSize":25,"multiTeamPolicy":"FORBIDDEN_SAME_EDITION_CATEGORY","closeRequiresApprovedRosters":false},
    "identityRequirements":{"credentialRequired":false},
    "kitPolicy":{"jerseyRequired":false,"jerseyNumberMinimum":1,"jerseyNumberMaximum":99},
    "publicSummary":{"approval":"manual","teamLimits":{"minimum":0,"maximum":100}}
  },
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}}
}'::jsonb)) source(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_opens_at,
  registration_closes_at, registration_rule_revision_id,
  revision, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-edition', edition_number),
  pg_temp.r4a_scale_uuid('r4a-scale-competition', 1),
  'R4A Scale Edition ' || edition_number, 'S' || edition_number,
  date '2030-01-01' + ((edition_number - 1) * 370),
  date '2030-12-31' + ((edition_number - 1) * 370),
  'registration_open', pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  'PUBLIC_APPROVAL', clock_timestamp() - interval '1 day',
  clock_timestamp() + interval '365 days',
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  1, 2000000000 + edition_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 1000) edition_number;

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, age_reference_date,
  eligibility_policy, visibility, status, rule_revision_id,
  revision, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-category', category_number),
  pg_temp.r4a_scale_uuid('r4a-scale-edition', ((category_number - 1) / 10) + 1),
  'R4A Scale Category ' || category_number,
  'category-' || (((category_number - 1) % 10) + 1),
  'FOOTBALL_7', date '2030-01-01', '{}'::jsonb, 'public', 'active',
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  1, 2010000000 + category_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 10000) category_number;

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source,
  status, rule_revision_id, submitted_by, accepted_by, submitted_at,
  accepted_at, reason_code, revision, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-entry', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-competition', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-edition', ((((entry_number - 1) % 10000)) / 10) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-category', ((entry_number - 1) % 10000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-team', case
    when entry_number <= 10000 then ((entry_number - 1) % 100) + 1
    else ((entry_number - 10001) % 100) + 101
  end),
  'PUBLIC_APPLICATION', 'accepted', pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1), pg_temp.r4a_scale_uuid('r4a-scale-user', 1),
  clock_timestamp(), clock_timestamp(), 'scale.accepted', 1,
  2020000000 + entry_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 20000) entry_number;

insert into public.pachanga_competition_team_delegates(
  id, entry_id, user_id, delegate_role, status, valid_from,
  revision, server_sequence, invited_by, accepted_at
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-delegate', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-user', ((entry_number - 1) % 150000) + 1),
  'PRIMARY_DELEGATE', 'active', clock_timestamp(), 1,
  2030000000 + entry_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1), clock_timestamp()
from generate_series(1, 20000) entry_number;

insert into public.pachanga_competition_rosters(
  id, entry_id, category_id, rule_revision_id, status,
  current_revision_id, revision, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-roster', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-category', ((entry_number - 1) % 10000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  'submitted', null, 1, 2040000000 + entry_number,
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 20000) entry_number;

insert into public.pachanga_competition_roster_revisions(
  id, roster_id, revision_number, roster_status, rule_revision_id,
  member_count, eligibility_summary, member_set_checksum, effective_from,
  reason, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-roster-revision', entry_number),
  pg_temp.r4a_scale_uuid('r4a-scale-roster', entry_number), 1, 'submitted',
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  case when entry_number <= 10000 then 8 else 7 end,
  jsonb_build_object('eligible', case when entry_number <= 10000 then 8 else 7 end),
  repeat('0', 64), clock_timestamp(), 'R4A scale revision',
  2050000000 + entry_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 20000) entry_number;

update public.pachanga_competition_rosters rosters
set current_revision_id = revisions.id
from public.pachanga_competition_roster_revisions revisions
where revisions.roster_id = rosters.id
  and rosters.id in (
    select pg_temp.r4a_scale_uuid('r4a-scale-roster', entry_number)
    from generate_series(1, 20000) entry_number
  );

insert into public.pachanga_player_competition_credentials(
  id, player_profile_id, competition_id, edition_id, category_id,
  status, verification_method, verified_by, verified_at, reason_code,
  rule_revision_id, revision, server_sequence
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-credential', credential_number),
  pg_temp.r4a_scale_uuid('r4a-scale-profile', credential_number),
  pg_temp.r4a_scale_uuid('r4a-scale-competition', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-edition', (((((credential_number - 1) % 20000) % 10000)) / 10) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-category', (((credential_number - 1) % 20000) % 10000) + 1),
  'verified', 'SCALE', pg_temp.r4a_scale_uuid('r4a-scale-user', 1),
  clock_timestamp(), 'credential.scale_verified',
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1), 1,
  2060000000 + credential_number
from generate_series(1, 100000) credential_number;

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  eligibility_status, credential_id, effective_from, public_snapshot,
  reason_code, server_sequence
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-member', member_number),
  pg_temp.r4a_scale_uuid('r4a-scale-roster', ((member_number - 1) % 20000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-roster-revision', ((member_number - 1) % 20000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', ((member_number - 1) % 20000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-profile', member_number),
  'eligible', case when member_number <= 100000
    then pg_temp.r4a_scale_uuid('r4a-scale-credential', member_number) else null end,
  clock_timestamp(), jsonb_build_object(
    'playerProfileId', pg_temp.r4a_scale_uuid('r4a-scale-profile', member_number),
    'displayName', 'R4A Scale Player ' || member_number
  ), 'eligibility.valid', 2070000000 + member_number
from generate_series(1, 150000) member_number;

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-stage', edition_number),
  pg_temp.r4a_scale_uuid('r4a-scale-edition', edition_number),
  'R4A Scale Stage ' || edition_number, 'LEAGUE_STAGE', 1, false,
  'draft', pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 1000) edition_number;

insert into public.pachanga_competition_divisions(
  id, stage_id, name, division_order, level_label, status, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-division', edition_number),
  pg_temp.r4a_scale_uuid('r4a-scale-stage', edition_number),
  'Division ' || edition_number, 1, 'Open', 'draft',
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 1000) edition_number;

insert into public.pachanga_competition_groups(
  id, stage_id, division_id, name, group_order, status, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-competition-group', edition_number),
  pg_temp.r4a_scale_uuid('r4a-scale-stage', edition_number),
  pg_temp.r4a_scale_uuid('r4a-scale-division', edition_number),
  'Group ' || edition_number, 1, 'draft', pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 1000) edition_number;

insert into public.pachanga_competition_stage_memberships(
  id, entry_id, stage_id, division_id, competition_group_id,
  rule_revision_id, valid_from, valid_until, status, reason,
  revision, server_sequence, assigned_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-membership', membership_number),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', ((membership_number - 1) % 20000) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-stage', (((((membership_number - 1) % 20000) % 10000)) / 10) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-division', (((((membership_number - 1) % 20000) % 10000)) / 10) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-competition-group', (((((membership_number - 1) % 20000) % 10000)) / 10) + 1),
  pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1),
  clock_timestamp() - interval '2 days',
  case when membership_number > 20000 then clock_timestamp() - interval '1 day' else null end,
  case when membership_number > 20000 then 'closed' else 'active' end,
  'R4A scale stage membership', 1, 2080000000 + membership_number,
  pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 30000) membership_number;

insert into public.pachanga_team_availability_constraints(
  id, entry_id, weekday, start_local_time, end_local_time, timezone,
  reason, status, revision, server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-hard-window', window_number),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', ((window_number - 1) % 20000) + 1),
  ((window_number - 1) % 7) + 1, time '18:00', time '19:00',
  'Europe/Madrid', 'R4A scale hard constraint', 'active', 1,
  2090000000 + window_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 50000) window_number;

insert into public.pachanga_team_schedule_preferences(
  id, entry_id, weekday, start_local_time, end_local_time, timezone,
  weight, preferred_area, venue_reference, status, revision,
  server_sequence, created_by
)
select
  pg_temp.r4a_scale_uuid('r4a-scale-soft-window', window_number),
  pg_temp.r4a_scale_uuid('r4a-scale-entry', ((window_number - 1) % 20000) + 1),
  ((window_number - 1) % 7) + 1, time '19:00', time '20:00',
  'Europe/Madrid', 50, 'Barcelona', null, 'active', 1,
  2100000000 + window_number, pg_temp.r4a_scale_uuid('r4a-scale-user', 1)
from generate_series(1, 50000) window_number;

analyze public.pachanga_competition_editions;
analyze public.pachanga_competition_categories;
analyze public.pachanga_competition_entries;
analyze public.pachanga_competition_team_delegates;
analyze public.pachanga_competition_rosters;
analyze public.pachanga_competition_roster_revisions;
analyze public.pachanga_competition_roster_members;
analyze public.pachanga_player_competition_credentials;
analyze public.pachanga_competition_stage_memberships;
analyze public.pachanga_team_availability_constraints;
analyze public.pachanga_team_schedule_preferences;

select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_editions where competition_id = pg_temp.r4a_scale_uuid('r4a-scale-competition', 1)) = 1000, 'Expected 1,000 Editions');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_categories where id in (select pg_temp.r4a_scale_uuid('r4a-scale-category', value) from generate_series(1,10000) value)) = 10000, 'Expected 10,000 Categories');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_entries where competition_id = pg_temp.r4a_scale_uuid('r4a-scale-competition', 1)) = 20000, 'Expected 20,000 Entries');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_team_delegates where id in (select pg_temp.r4a_scale_uuid('r4a-scale-delegate', value) from generate_series(1,20000) value)) = 20000, 'Expected 20,000 Delegates');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_roster_members where server_sequence between 2070000001 and 2070150000) = 150000, 'Expected 150,000 Roster Members');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_player_competition_credentials where server_sequence between 2060000001 and 2060100000) = 100000, 'Expected 100,000 Credentials');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_competition_stage_memberships where server_sequence between 2080000001 and 2080030000) = 30000, 'Expected 30,000 Stage Memberships');
select pg_temp.r4a_scale_assert((select count(*) from public.pachanga_team_availability_constraints where server_sequence between 2090000001 and 2090050000) + (select count(*) from public.pachanga_team_schedule_preferences where server_sequence between 2100000001 and 2100050000) = 100000, 'Expected 100,000 Availability/Preference rows');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.r4a_scale_uuid('r4a-scale-user', 1), 'role', 'authenticated'
)::text, true);

select pg_temp.r4a_scale_measure('public_registration_read', format($sql$
  select public.get_pachanga_league_public_registration_v1(%L::uuid)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-competition', 1)), 12);
select pg_temp.r4a_scale_measure('organizer_entry_list', format($sql$
  select public.get_pachanga_competition_registration_desk_v1(%L::uuid, null, null, 500, 50)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-competition', 1)), 12);
select pg_temp.r4a_scale_measure('entry_detail', format($sql$
  select public.get_pachanga_competition_entry_v1(%L::uuid)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-entry', 12500)), 15);
select pg_temp.r4a_scale_measure('roster_detail', format($sql$
  select public.get_pachanga_competition_roster_v1(%L::uuid, 0, 25)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-roster', 12500)), 15);
select pg_temp.r4a_scale_measure('eligibility_validation', format($sql$
  select private.pachanga_league_member_eligibility_v1(%L::uuid,%L::uuid,%L::uuid,%L::uuid)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-profile', 75000), pg_temp.r4a_scale_uuid('r4a-scale-category', 5000), pg_temp.r4a_scale_uuid('r4a-scale-rule-revision', 1), pg_temp.r4a_scale_uuid('r4a-scale-credential', 75000)), 20);
select pg_temp.r4a_scale_measure('duplicate_player_check', format($sql$
  select exists(select 1 from public.pachanga_competition_roster_members where roster_revision_id=%L::uuid and player_profile_id=%L::uuid)
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-roster-revision', 12500), pg_temp.r4a_scale_uuid('r4a-scale-profile', 12500)), 25);
select pg_temp.r4a_scale_measure('multi_team_conflict', format($sql$
  select exists(
    select 1 from public.pachanga_competition_roster_members members
    join public.pachanga_competition_rosters rosters on rosters.id=members.roster_id and rosters.current_revision_id=members.roster_revision_id
    join public.pachanga_competition_entries entries on entries.id=rosters.entry_id
    where members.player_profile_id=%L::uuid and entries.edition_id=%L::uuid and entries.category_id=%L::uuid
      and entries.status='accepted'
  )
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-profile', 75000), pg_temp.r4a_scale_uuid('r4a-scale-edition', 500), pg_temp.r4a_scale_uuid('r4a-scale-category', 5000)), 25);
select pg_temp.r4a_scale_measure('delegate_lookup', format($sql$
  select id from public.pachanga_competition_team_delegates where entry_id=%L::uuid and status='active' order by server_sequence desc,id desc limit 1
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-entry', 12500)), 25);
select pg_temp.r4a_scale_measure('stage_membership_lookup', format($sql$
  select id from public.pachanga_competition_stage_memberships where entry_id=%L::uuid and status='active' order by server_sequence desc,id desc limit 1
$sql$, pg_temp.r4a_scale_uuid('r4a-scale-entry', 12500)), 25);

create temporary table r4a_scale_percentiles on commit drop as
select metric,
  round(percentile_cont(0.50) within group (order by elapsed_ms)::numeric, 3) as p50_ms,
  round(percentile_cont(0.95) within group (order by elapsed_ms)::numeric, 3) as p95_ms,
  count(*) as samples
from r4a_scale_timings group by metric;

table r4a_scale_percentiles;

select pg_temp.r4a_scale_assert(not exists(
  select 1 from r4a_scale_percentiles where p95_ms >= case
    when metric in ('public_registration_read','organizer_entry_list') then 2500
    when metric in ('entry_detail','roster_detail') then 1500
    else 500 end
), 'R4A scale p95 threshold exceeded');

select 'r4a_index_bytes' as metric, pg_size_pretty(sum(pg_relation_size(indexrelid))) as value
from pg_stat_user_indexes
where relname in (
  'pachanga_competition_categories', 'pachanga_competition_entries',
  'pachanga_competition_team_delegates', 'pachanga_competition_roster_members',
  'pachanga_player_competition_credentials', 'pachanga_competition_stage_memberships',
  'pachanga_team_availability_constraints', 'pachanga_team_schedule_preferences'
);

explain (analyze, buffers, format text)
select id from public.pachanga_competition_entries
where competition_id=pg_temp.r4a_scale_uuid('r4a-scale-competition',1) and status='accepted'
order by server_sequence desc,id desc offset 500 limit 50;

explain (analyze, buffers, format text)
select id from public.pachanga_competition_roster_members
where roster_revision_id=pg_temp.r4a_scale_uuid('r4a-scale-roster-revision',12500)
order by server_sequence desc,id desc limit 25;

explain (analyze, buffers, format text)
select id from public.pachanga_competition_stage_memberships
where entry_id=pg_temp.r4a_scale_uuid('r4a-scale-entry',12500) and status='active'
order by server_sequence desc,id desc limit 1;

rollback;
