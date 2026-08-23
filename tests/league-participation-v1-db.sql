\set ON_ERROR_STOP on

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
    raise exception 'R4A_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4A_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
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



create or replace function pg_temp.table_digest(target_table regclass)
returns text language plpgsql as $$
declare result text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(rows)::text, E''\\n'' order by to_jsonb(rows)::text), '''')) from %s rows',
    target_table
  ) into result;
  return result;
end;
$$;

create temporary table r4a_command_log(
  operation_id uuid primary key,
  actor_id uuid not null,
  aggregate_id uuid not null,
  expected_revision bigint not null,
  action text not null,
  payload jsonb not null,
  response jsonb not null
);
create temporary table r4a_ids(key text primary key, value uuid not null);
create temporary table r4a_invariants_before(table_name text primary key, digest text not null);
grant select on r4a_command_log, r4a_ids to authenticated;

create or replace function pg_temp.run_command(
  target_actor_id uuid,
  target_operation_id uuid,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare response jsonb;
begin
  perform pg_temp.actor(target_actor_id);
  response := public.command_pachanga_league_participation_v1(
    target_operation_id,
    target_aggregate_id,
    target_expected_revision,
    target_action,
    target_payload,
    jsonb_build_object(
      'clientVersion', '4.0.0+r4a-db',
      'serviceWorkerVersion', 'sw-r4a-db',
      'installedMode', 'standalone',
      'surface', 'r4a_db'
    )
  );
  insert into r4a_command_log values (
    target_operation_id, target_actor_id, target_aggregate_id,
    target_expected_revision, target_action, target_payload, response
  );
  return response;
end;
$$;

create or replace function pg_temp.expect_command_failure(
  target_actor_id uuid,
  target_operation_id uuid,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb,
  expected_pattern text
)
returns text language plpgsql as $$
declare failure text;
begin
  perform pg_temp.actor(target_actor_id);
  begin
    perform public.command_pachanga_league_participation_v1(
      target_operation_id, target_aggregate_id, target_expected_revision,
      target_action, target_payload,
      '{"clientVersion":"4.0.0+r4a-db","installedMode":"browser","surface":"r4a_db"}'::jsonb
    );
    raise exception 'R4A_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4A_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected command failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('d4010000-0000-4000-8000-000000000001', 'r4a-platform-owner@example.test', clock_timestamp(), '{"full_name":"Platform Owner"}'),
  ('d4010000-0000-4000-8000-000000000002', 'r4a-club-owner@example.test', clock_timestamp(), '{"full_name":"Club Owner"}'),
  ('d4010000-0000-4000-8000-000000000003', 'r4a-director@example.test', clock_timestamp(), '{"full_name":"Competition Director"}'),
  ('d4010000-0000-4000-8000-000000000004', 'r4a-registration@example.test', clock_timestamp(), '{"full_name":"Registration Manager"}'),
  ('d4010000-0000-4000-8000-000000000005', 'r4a-rosters@example.test', clock_timestamp(), '{"full_name":"Roster Manager"}'),
  ('d4010000-0000-4000-8000-000000000006', 'r4a-viewer@example.test', clock_timestamp(), '{"full_name":"Competition Viewer"}'),
  ('d4010000-0000-4000-8000-000000000007', 'r4a-club-admin@example.test', clock_timestamp(), '{"full_name":"Club Admin"}'),
  ('d4010000-0000-4000-8000-000000000008', 'r4a-outsider@example.test', clock_timestamp(), '{"full_name":"Outsider"}'),
  ('d4010000-0000-4000-8000-000000000010', 'r4a-team-a-owner@example.test', clock_timestamp(), '{"full_name":"Team A Owner"}'),
  ('d4010000-0000-4000-8000-000000000011', 'r4a-team-a-admin@example.test', clock_timestamp(), '{"full_name":"Team A Admin"}'),
  ('d4010000-0000-4000-8000-000000000012', 'r4a-shared-player@example.test', clock_timestamp(), '{"full_name":"Shared Player"}'),
  ('d4010000-0000-4000-8000-000000000013', 'r4a-team-a-player@example.test', clock_timestamp(), '{"full_name":"Team A Player"}'),
  ('d4010000-0000-4000-8000-000000000014', 'r4a-team-b-old-owner@example.test', clock_timestamp(), '{"full_name":"Team B Old Owner"}'),
  ('d4010000-0000-4000-8000-000000000015', 'r4a-team-b-new-owner@example.test', clock_timestamp(), '{"full_name":"Team B New Owner"}'),
  ('d4010000-0000-4000-8000-000000000016', 'r4a-team-b-player-1@example.test', clock_timestamp(), '{"full_name":"Team B Player 1"}'),
  ('d4010000-0000-4000-8000-000000000017', 'r4a-team-b-player-2@example.test', clock_timestamp(), '{"full_name":"Team B Player 2"}'),
  ('d4010000-0000-4000-8000-000000000018', 'r4a-team-c-owner@example.test', clock_timestamp(), '{"full_name":"Team C Owner"}'),
  ('d4010000-0000-4000-8000-000000000019', 'r4a-delegate-a@example.test', clock_timestamp(), '{"full_name":"Delegate A"}'),
  ('d4010000-0000-4000-8000-000000000020', 'r4a-delegate-b@example.test', clock_timestamp(), '{"full_name":"Delegate B"}'),
  ('d4010000-0000-4000-8000-000000000021', 'r4a-team-d-owner@example.test', clock_timestamp(), '{"full_name":"Team D Owner"}'),
  ('d4010000-0000-4000-8000-000000000022', 'r4a-team-a-player-3@example.test', clock_timestamp(), '{"full_name":"Team A Player 3"}'),
  ('d4010000-0000-4000-8000-000000000023', 'r4a-team-b-player-3@example.test', clock_timestamp(), '{"full_name":"Team B Player 3"}'),
  ('d4010000-0000-4000-8000-000000000024', 'r4a-team-b-player-4@example.test', clock_timestamp(), '{"full_name":"Team B Player 4"}'),
  ('d4010000-0000-4000-8000-000000000025', 'r4a-team-b-player-5@example.test', clock_timestamp(), '{"full_name":"Team B Player 5"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('d4010000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision) values
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000010', 'R4A Team A', 'R4ATEA1', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000014', 'R4A Team B', 'R4ATEB1', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('d4020000-0000-4000-8000-000000000003', 'd4010000-0000-4000-8000-000000000018', 'R4A Team C', 'R4ATEC1', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('d4020000-0000-4000-8000-000000000004', 'd4010000-0000-4000-8000-000000000021', 'R4A Team D', 'R4ATED1', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000010', 'owner', 'Team A Owner'),
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000011', 'admin', 'Team A Admin'),
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000012', 'player', 'Shared Player'),
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000013', 'player', 'Team A Player'),
  ('d4020000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000022', 'player', 'Team A Player 3'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000014', 'owner', 'Team B Old Owner'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000015', 'admin', 'Team B New Owner'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000012', 'player', 'Shared Player'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000016', 'player', 'Team B Player 1'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000017', 'player', 'Team B Player 2'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000023', 'player', 'Team B Player 3'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000024', 'player', 'Team B Player 4'),
  ('d4020000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000025', 'player', 'Team B Player 5'),
  ('d4020000-0000-4000-8000-000000000003', 'd4010000-0000-4000-8000-000000000018', 'owner', 'Team C Owner'),
  ('d4020000-0000-4000-8000-000000000004', 'd4010000-0000-4000-8000-000000000021', 'owner', 'Team D Owner');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name, birth_date,
  rating, current_overall, base_facets, calibrated_facets, current_facets, position
) values
  ('d4110000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000012', 'd4020000-0000-4000-8000-000000000001', 'r4a-shared', 'Shared Player', '1985-04-10', 7.2, 72, '{"pace":72}', '{"pace":72}', '{"pace":72}', 'Mediocentro / pivote'),
  ('d4110000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000013', 'd4020000-0000-4000-8000-000000000001', 'r4a-a2', 'Team A Player', '1992-03-08', 6.8, 68, '{"pace":68}', '{"pace":68}', '{"pace":68}', 'Defensa central'),
  ('d4110000-0000-4000-8000-000000000003', 'd4010000-0000-4000-8000-000000000022', 'd4020000-0000-4000-8000-000000000001', 'r4a-a3', 'Team A Player 3', '1995-01-15', 6.6, 66, '{"pace":66}', '{"pace":66}', '{"pace":66}', 'Delantero centro'),
  ('d4110000-0000-4000-8000-000000000004', 'd4010000-0000-4000-8000-000000000016', 'd4020000-0000-4000-8000-000000000002', 'r4a-b1', 'Team B Player 1', '1990-02-02', 6.5, 65, '{"pace":65}', '{"pace":65}', '{"pace":65}', 'Portero'),
  ('d4110000-0000-4000-8000-000000000005', 'd4010000-0000-4000-8000-000000000017', 'd4020000-0000-4000-8000-000000000002', 'r4a-b2', 'Team B Player 2', '1988-05-12', 6.4, 64, '{"pace":64}', '{"pace":64}', '{"pace":64}', 'Lateral derecho'),
  ('d4110000-0000-4000-8000-000000000006', 'd4010000-0000-4000-8000-000000000023', 'd4020000-0000-4000-8000-000000000002', 'r4a-b3', 'Team B Player 3', '1987-06-12', 6.3, 63, '{"pace":63}', '{"pace":63}', '{"pace":63}', 'Mediocentro / pivote'),
  ('d4110000-0000-4000-8000-000000000007', 'd4010000-0000-4000-8000-000000000024', 'd4020000-0000-4000-8000-000000000002', 'r4a-b4', 'Team B Player 4', '1986-07-12', 6.2, 62, '{"pace":62}', '{"pace":62}', '{"pace":62}', 'Extremo derecho'),
  ('d4110000-0000-4000-8000-000000000008', 'd4010000-0000-4000-8000-000000000025', 'd4020000-0000-4000-8000-000000000002', 'r4a-b5', 'Team B Player 5', '1984-08-12', 6.1, 61, '{"pace":61}', '{"pace":61}', '{"pace":61}', 'Delantero centro');

insert into public.pachanga_clubs(
  id, name, slug, club_type, country_code, province, municipality, general_area,
  visibility, operational_status, verification_status, partnership_status,
  primary_owner_id, created_by
) values (
  'd4030000-0000-4000-8000-000000000001', 'R4A Club Organizer', 'r4a-club-organizer',
  'INDEPENDENT_ORGANIZER', 'ES', 'Barcelona', 'Barcelona', 'Barcelona',
  'private', 'active', 'verified', 'active',
  'd4010000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000002'
);
insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, accepted_at, invited_by
) values
  ('d4030000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000002', 'club_owner', 'active', clock_timestamp(), 'd4010000-0000-4000-8000-000000000002'),
  ('d4030000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000003', 'club_competition_manager', 'active', clock_timestamp(), 'd4010000-0000-4000-8000-000000000002'),
  ('d4030000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000007', 'club_admin', 'active', clock_timestamp(), 'd4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, organizer_club_id, name, slug,
  competition_type, visibility, status, created_by
) values (
  'd4040000-0000-4000-8000-000000000001', 'CLUB', null,
  'd4030000-0000-4000-8000-000000000001', 'R4A League 2027', 'r4a-league-2027',
  'LEAGUE', 'public', 'draft', 'd4010000-0000-4000-8000-000000000003'
);
insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, organizer_club_id, capability, grant_source,
  status, reason, granted_by
) values (
  'CLUB', null, 'd4030000-0000-4000-8000-000000000001', 'competition_manage',
  'platform_grant', 'active', 'R4A isolated test entitlement',
  'd4010000-0000-4000-8000-000000000001'
);
insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values ('d4050000-0000-4000-8000-000000000001', 'd4040000-0000-4000-8000-000000000001', 'R4A QA Rules', 'active', 'd4010000-0000-4000-8000-000000000003');

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select
  'd4060000-0000-4000-8000-000000000001',
  'd4050000-0000-4000-8000-000000000001', 1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'published', 3,
  'Explicit isolated R4A test rules', 'd4010000-0000-4000-8000-000000000003'
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{
    "registrationPolicy":{"teamLimits":{"minimum":1,"maximum":3}},
    "rosterPolicy":{"minimumSize":2,"maximumSize":4,"multiTeamPolicy":"FORBIDDEN_SAME_EDITION_CATEGORY","closeRequiresApprovedRosters":false},
    "identityRequirements":{"credentialRequired":true},
    "kitPolicy":{"jerseyRequired":true,"jerseyNumberMinimum":1,"jerseyNumberMaximum":99},
    "publicSummary":{"teamLimits":{"minimum":1,"maximum":3},"approval":"manual"}
  },
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
  "results":{"scoringPolicy":{},"tieBreakCriteria":[]},
  "operations":{"hardAvailabilityPolicy":{"mode":"required"},"schedulePreferencePolicy":{"mode":"preferred"}},
  "discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb)) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at,
  status, rule_revision_id, revision, created_by
) values
  ('d4070000-0000-4000-8000-000000000001', 'd4040000-0000-4000-8000-000000000001', 'Season 2027', '2027', '2027-01-01', '2027-12-31', 'draft', 'd4060000-0000-4000-8000-000000000001', 1, 'd4010000-0000-4000-8000-000000000003'),
  ('d4070000-0000-4000-8000-000000000002', 'd4040000-0000-4000-8000-000000000001', 'Second registration test', '2028', '2028-01-01', '2028-12-31', 'draft', 'd4060000-0000-4000-8000-000000000001', 1, 'd4010000-0000-4000-8000-000000000003');

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, created_by
) values ('d4080000-0000-4000-8000-000000000001', 'd4070000-0000-4000-8000-000000000001', 'League Stage', 'LEAGUE_STAGE', 0, false, 'draft', 'd4060000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000003');
insert into public.pachanga_competition_divisions(
  id, stage_id, name, division_order, level_label, status, created_by
) values ('d4090000-0000-4000-8000-000000000001', 'd4080000-0000-4000-8000-000000000001', 'Division 1', 0, 'Open', 'draft', 'd4010000-0000-4000-8000-000000000003');
insert into public.pachanga_competition_groups(
  id, stage_id, division_id, name, group_order, status, created_by
) values
  ('d40a0000-0000-4000-8000-000000000001', 'd4080000-0000-4000-8000-000000000001', 'd4090000-0000-4000-8000-000000000001', 'Group A', 0, 'draft', 'd4010000-0000-4000-8000-000000000003'),
  ('d40a0000-0000-4000-8000-000000000002', 'd4080000-0000-4000-8000-000000000001', 'd4090000-0000-4000-8000-000000000001', 'Group B', 1, 'draft', 'd4010000-0000-4000-8000-000000000003');

insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
) values
  ('d4040000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000003', 'competition_director', 'active', 'd4010000-0000-4000-8000-000000000002'),
  ('d4040000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000004', 'competition_registration_manager', 'active', 'd4010000-0000-4000-8000-000000000002'),
  ('d4040000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000005', 'competition_roster_manager', 'active', 'd4010000-0000-4000-8000-000000000002'),
  ('d4040000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000006', 'viewer', 'active', 'd4010000-0000-4000-8000-000000000002');

insert into r4a_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('public.pachanga_match_read_model'),
  ('public.pachanga_match_participants'),
  ('public.pachanga_match_scorers'),
  ('public.pachanga_canonical_matches'),
  ('public.pachanga_competition_match_contexts'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('public.pachanga_team_cosmetic_inventory'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_provincial_ranking_entries'),
  ('public.pachanga_stripe_webhook_events')
) tables(table_name);

do $$
declare
  response jsonb;
  foundation_revision bigint;
  flags_revision bigint;
  edition_revision bigint;
  category_revision bigint;
  entry_revision bigint;
  open_category_id uuid;
  veterans_category_id uuid;
  entry_a_id uuid;
  entry_b_id uuid;
  entry_b_veterans_id uuid;
  entry_c_id uuid;
  entry_c_veterans_id uuid;
  entry_d_veterans_id uuid;
begin
  -- R4A must remain unreachable until both the R1 foundation and R4A flags allow it.
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000003',
    'd4200000-0000-4000-8000-000000000001',
    'd4070000-0000-4000-8000-000000000001',
    1,
    'category.create',
    '{"name":"Disabled","slug":"disabled","sportFormat":"FOOTBALL_7","ruleRevisionId":"d4060000-0000-4000-8000-000000000001"}'::jsonb,
    'COMPETITION_FOUNDATION_DISABLED|LEAGUE_PARTICIPATION_DISABLED'
  );

  select revision into foundation_revision
  from private.pachanga_competition_foundation_settings where singleton;
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_competition_platform_v1(
    'd4200000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000c001',
    foundation_revision,
    'foundation_flags.set',
    '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":false,"reason":"R4A isolated fixture"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-db","installedMode":"browser","surface":"r4a_db"}'::jsonb
  );
  select revision into flags_revision
  from private.pachanga_competition_foundation_settings where singleton;
  response := public.command_pachanga_league_participation_platform_v1(
    'd4200000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-00000000c4a1',
    flags_revision,
    '{"foundationEnabled":true,"registrationEnabled":true,"publicRegistrationEnabled":true,"delegatesEnabled":true,"rostersEnabled":true,"schedulePreferencesEnabled":true,"reason":"R4A isolated QA"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-db","serviceWorkerVersion":"sw-r4a-db","installedMode":"standalone","surface":"r4a_db","secret":"discard-me"}'::jsonb
  );
  perform pg_temp.assert_true(
    (response #>> '{snapshot,foundationEnabled}')::boolean
    and (response #>> '{snapshot,publicRegistrationEnabled}')::boolean
    and (response #>> '{snapshot,rostersEnabled}')::boolean,
    'R4A flags did not enable as a coherent dependency set'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from private.pachanga_competition_operation_receipts receipts
    where receipts.operation_id = 'd4200000-0000-4000-8000-000000000003'
      and receipts.client_metadata ? 'secret'
  ), 'R4A flag receipt persisted unknown client metadata');

  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000001';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4200000-0000-4000-8000-000000000010',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'category.create',
    '{"name":"Open","slug":"open","description":"Open category","sportFormat":"FOOTBALL_7","levelLabel":"Open","minimumAge":18,"ageReferenceDate":"2027-01-01","visibility":"public","eligibilityPolicy":{"age":"adult"},"ruleRevisionId":"d4060000-0000-4000-8000-000000000001","reason":"Create open category"}'::jsonb
  );
  open_category_id := (response #>> '{snapshot,id}')::uuid;
  insert into r4a_ids values ('open_category', open_category_id);

  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000001';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4200000-0000-4000-8000-000000000011',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'category.create',
    '{"name":"Veterans","slug":"veterans","description":"Veterans test category","sportFormat":"FOOTBALL_7","levelLabel":"Veterans","minimumAge":35,"ageReferenceDate":"2027-01-01","visibility":"public","eligibilityPolicy":{"minimumAge":35},"ruleRevisionId":"d4060000-0000-4000-8000-000000000001","reason":"Create veterans category"}'::jsonb
  );
  veterans_category_id := (response #>> '{snapshot,id}')::uuid;
  insert into r4a_ids values ('veterans_category', veterans_category_id);

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4200000-0000-4000-8000-000000000012', open_category_id, 1,
    'category.activate', '{"reason":"Activate open category"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4200000-0000-4000-8000-000000000013', veterans_category_id, 1,
    'category.activate', '{"reason":"Activate veterans category"}'::jsonb
  );
  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000001';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000014',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'registration.open',
    jsonb_build_object(
      'registrationMode', 'PUBLIC_APPROVAL',
      'closesAt', clock_timestamp() + interval '30 days',
      'ruleRevisionId', 'd4060000-0000-4000-8000-000000000001',
      'reason', 'Open public registration'
    )
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,status}' = 'registration_open'
    and response #>> '{snapshot,registrationMode}' = 'PUBLIC_APPROVAL',
    'Registration did not open with the server-confirmed mode'
  );

  select revision into category_revision from public.pachanga_competition_categories
  where id = open_category_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000011',
    'd4200000-0000-4000-8000-000000000020', open_category_id,
    category_revision, 'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000001","reason":"Admin cannot submit"}'::jsonb,
    'TEAM_OWNER_REQUIRED'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000021', open_category_id,
    category_revision, 'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000001","reason":"Team A public application"}'::jsonb
  );
  entry_a_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_a', entry_a_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000022', entry_a_id, 1,
    'entry.accept', '{"reason":"Accept Team A"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,entry,status}' = 'accepted'
    and response #> '{snapshot,roster}' is not null,
    'Accepting Team A did not create its empty canonical roster'
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000023', open_category_id,
    category_revision, 'entry.invite',
    jsonb_build_object(
      'teamId', 'd4020000-0000-4000-8000-000000000002',
      'expiresAt', clock_timestamp() + interval '20 days',
      'reason', 'Invite Team B privately'
    )
  );
  entry_b_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_b', entry_b_id);

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000014');
  response := public.transfer_pachanga_group_ownership_authoritative_v1(
    'd4020000-0000-4000-8000-000000000002',
    'd4010000-0000-4000-8000-000000000015',
    'd4200000-0000-4000-8000-000000000024',
    (select payload_revision from public.pachanga_groups where id = 'd4020000-0000-4000-8000-000000000002'),
    '{"clientVersion":"4.0.0+r4a-db","installedMode":"browser","surface":"owner-transfer"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select owner_id from public.pachanga_groups where id = 'd4020000-0000-4000-8000-000000000002')
      = 'd4010000-0000-4000-8000-000000000015',
    'Team B owner transfer did not change the ultimate authority'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000014',
    'd4200000-0000-4000-8000-000000000025', entry_b_id, 1,
    'entry.accept', '{"reason":"Old owner must fail"}'::jsonb,
    'TEAM_OWNER_REQUIRED'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000015',
    'd4200000-0000-4000-8000-000000000026', entry_b_id, 1,
    'entry.accept', '{"reason":"New owner accepts invitation"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,entry,status}' = 'accepted'
    and (select count(*) from public.pachanga_competition_rosters where entry_id = entry_b_id) = 1,
    'Team B invitation or roster did not survive owner transfer'
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000018',
    'd4200000-0000-4000-8000-000000000027', open_category_id,
    category_revision, 'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000003","reason":"Team C public application"}'::jsonb
  );
  entry_c_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_c', entry_c_id);
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000021',
    'd4200000-0000-4000-8000-000000000028', open_category_id,
    category_revision, 'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000004","reason":"Capacity must reject Team D"}'::jsonb,
    'REGISTRATION_TEAM_LIMIT_REACHED'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000029', entry_c_id, 1,
    'entry.reject',
    '{"reason":"Private organizer rejection reason","reasonCode":"entry.capacity_review"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,entry,status}' = 'rejected'
    and response #>> '{snapshot,entry,privateReason}' = 'Private organizer rejection reason',
    'Organizer rejection did not preserve its private reason'
  );

  select revision into category_revision from public.pachanga_competition_categories
  where id = veterans_category_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000030', veterans_category_id,
    category_revision, 'entry.invite',
    '{"teamId":"d4020000-0000-4000-8000-000000000002","reason":"Invite Team B to veterans"}'::jsonb
  );
  entry_b_veterans_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_b_veterans', entry_b_veterans_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000015',
    'd4200000-0000-4000-8000-000000000031', entry_b_veterans_id, 1,
    'entry.accept', '{"reason":"Accept veterans invitation"}'::jsonb
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000032', veterans_category_id,
    category_revision, 'entry.invite',
    '{"teamId":"d4020000-0000-4000-8000-000000000004","reason":"Invite Team D to veterans"}'::jsonb
  );
  entry_d_veterans_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_d_veterans', entry_d_veterans_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000021',
    'd4200000-0000-4000-8000-000000000033', entry_d_veterans_id, 1,
    'entry.decline', '{"reason":"Team D declines"}'::jsonb
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4200000-0000-4000-8000-000000000034', veterans_category_id,
    category_revision, 'entry.invite',
    '{"teamId":"d4020000-0000-4000-8000-000000000003","reason":"Pending invitation for close test"}'::jsonb
  );
  entry_c_veterans_id := (response #>> '{snapshot,entry,id}')::uuid;
  insert into r4a_ids values ('entry_c_veterans', entry_c_veterans_id);

  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_entries
      where edition_id = 'd4070000-0000-4000-8000-000000000001') = 6,
    'Entry stories did not preserve all accepted, rejected, declined and pending history'
  );
end;
$$;

do $$
declare
  response jsonb;
  entry_a_id uuid := (select value from r4a_ids where key = 'entry_a');
  entry_b_id uuid := (select value from r4a_ids where key = 'entry_b');
  entry_revision bigint;
  roster_b_id uuid;
  primary_a_id uuid;
  roster_manager_b_id uuid;
  extra_primary_id uuid;
  viewer_id uuid;
begin
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000040', entry_a_id, entry_revision,
    'delegate.invite',
    '{"userId":"d4010000-0000-4000-8000-000000000019","role":"PRIMARY_DELEGATE","reason":"Invite primary delegate A"}'::jsonb
  );
  select id into primary_a_id
  from public.pachanga_competition_team_delegates
  where entry_id = entry_a_id and user_id = 'd4010000-0000-4000-8000-000000000019'
    and delegate_role = 'PRIMARY_DELEGATE' and status = 'invited';
  insert into r4a_ids values ('primary_a', primary_a_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000019',
    'd4200000-0000-4000-8000-000000000041', primary_a_id, 1,
    'delegate.accept', '{"reason":"Delegate A accepts"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,actorScope}' = 'PRIMARY_DELEGATE'
    and not (response::text like '%d4010000-0000-4000-8000-000000000019%'),
    'Delegate acceptance failed or leaked its Auth UUID in the social snapshot'
  );

  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000042', entry_a_id, entry_revision,
    'delegate.invite',
    '{"userId":"d4010000-0000-4000-8000-000000000020","role":"ROSTER_MANAGER","reason":"Invite roster manager B"}'::jsonb
  );
  select id into roster_manager_b_id
  from public.pachanga_competition_team_delegates
  where entry_id = entry_a_id and user_id = 'd4010000-0000-4000-8000-000000000020'
    and delegate_role = 'ROSTER_MANAGER' and status = 'invited';
  insert into r4a_ids values ('roster_manager_b', roster_manager_b_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4200000-0000-4000-8000-000000000043', roster_manager_b_id, 1,
    'delegate.accept', '{"reason":"Roster manager accepts"}'::jsonb
  );

  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000044', entry_a_id, entry_revision,
    'delegate.invite',
    '{"userId":"d4010000-0000-4000-8000-000000000011","role":"PRIMARY_DELEGATE","reason":"Conflicting primary invitation"}'::jsonb
  );
  select id into extra_primary_id
  from public.pachanga_competition_team_delegates
  where entry_id = entry_a_id and user_id = 'd4010000-0000-4000-8000-000000000011'
    and delegate_role = 'PRIMARY_DELEGATE' and status = 'invited';
  insert into r4a_ids values ('extra_primary', extra_primary_id);
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000011',
    'd4200000-0000-4000-8000-000000000045', extra_primary_id, 1,
    'delegate.accept', '{"reason":"Second active primary must fail"}'::jsonb,
    'LEAGUE_PARTICIPATION_CONFLICT'
  );

  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000046', entry_a_id, entry_revision,
    'delegate.primary.transfer',
    jsonb_build_object(
      'targetDelegateId', roster_manager_b_id,
      'reason', 'Transfer primary authority to Delegate B'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_team_delegates where id = primary_a_id) = 'replaced'
    and (select replaced_by_delegate_id is not null
      from public.pachanga_competition_team_delegates where id = primary_a_id)
    and (select count(*) from public.pachanga_competition_team_delegates
      where entry_id = entry_a_id and delegate_role = 'PRIMARY_DELEGATE' and status = 'active') = 1,
    'Primary delegate transfer did not preserve history and one active primary'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000011',
    'd4200000-0000-4000-8000-000000000047', extra_primary_id, 1,
    'delegate.decline', '{"reason":"Conflicting invitation declined"}'::jsonb
  );

  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000048', entry_a_id, entry_revision,
    'delegate.invite',
    '{"userId":"d4010000-0000-4000-8000-000000000008","role":"VIEWER","reason":"Invite external viewer"}'::jsonb
  );
  select id into viewer_id
  from public.pachanga_competition_team_delegates
  where entry_id = entry_a_id and user_id = 'd4010000-0000-4000-8000-000000000008'
    and delegate_role = 'VIEWER' and status = 'invited';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000008',
    'd4200000-0000-4000-8000-000000000049', viewer_id, 1,
    'delegate.accept', '{"reason":"External viewer accepts"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4200000-0000-4000-8000-000000000050', viewer_id, 2,
    'delegate.revoke', '{"reason":"Owner revokes viewer"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_team_delegates where id = viewer_id) = 'revoked'
    and not exists (
      select 1 from public.pachanga_group_members
      where group_id = 'd4020000-0000-4000-8000-000000000001'
        and user_id in ('d4010000-0000-4000-8000-000000000019', 'd4010000-0000-4000-8000-000000000020')
    ),
    'Competition delegates leaked into global team membership'
  );

  select id into roster_b_id from public.pachanga_competition_rosters where entry_id = entry_b_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000020',
    'd4200000-0000-4000-8000-000000000051', roster_b_id,
    (select revision from public.pachanga_competition_rosters where id = roster_b_id),
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000004","reason":"Cross-team delegate attempt"}'::jsonb,
    'ROSTER_MANAGER_REQUIRED'
  );
  perform pg_temp.assert_true(
    private.pachanga_league_entry_actor_scope_v1(entry_a_id, 'd4010000-0000-4000-8000-000000000010') = 'TEAM_OWNER'
    and private.pachanga_league_entry_actor_scope_v1(entry_a_id, 'd4010000-0000-4000-8000-000000000020') = 'PRIMARY_DELEGATE',
    'Owner authority or bounded delegate scope was not preserved'
  );
end;
$$;

do $$
declare
  response jsonb;
  entry_a_id uuid := (select value from r4a_ids where key = 'entry_a');
  entry_b_id uuid := (select value from r4a_ids where key = 'entry_b');
  entry_b_veterans_id uuid := (select value from r4a_ids where key = 'entry_b_veterans');
  roster_a_id uuid;
  roster_b_id uuid;
  roster_b_veterans_id uuid;
  roster_revision bigint;
  entry_revision bigint;
  shared_credential_id uuid;
  a2_credential_id uuid;
  a3_credential_id uuid;
  immutable_revision_id uuid;
begin
  select id into roster_a_id from public.pachanga_competition_rosters where entry_id = entry_a_id;
  select id into roster_b_id from public.pachanga_competition_rosters where entry_id = entry_b_id;
  select id into roster_b_veterans_id from public.pachanga_competition_rosters
  where entry_id = entry_b_veterans_id;
  insert into r4a_ids values
    ('roster_a', roster_a_id), ('roster_b', roster_b_id),
    ('roster_b_veterans', roster_b_veterans_id);

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000001', roster_a_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","reason":"Add shared player"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4210000-0000-4000-8000-000000000002', roster_a_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000002","reason":"Add Team A player"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000003', roster_a_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000003","reason":"Add third player"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010',
    'd4210000-0000-4000-8000-000000000004', roster_a_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","reason":"Duplicate member"}'::jsonb,
    'ROSTER_MEMBER_ALREADY_EXISTS'
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000005', roster_a_id, roster_revision,
    'jersey.assign',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","number":7,"reason":"Shared player jersey"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000006', roster_a_id, roster_revision,
    'jersey.assign',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000002","number":7,"reason":"Duplicate jersey"}'::jsonb,
    'LEAGUE_PARTICIPATION_CONFLICT'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000007', roster_a_id, roster_revision,
    'jersey.assign',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000002","number":8,"reason":"Team A jersey 8"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000008', roster_a_id, roster_revision,
    'jersey.assign',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000003","number":9,"reason":"Team A jersey 9"}'::jsonb
  );

  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000010',
    'd4210000-0000-4000-8000-000000000009', entry_a_id, entry_revision,
    'kit.set',
    '{"kitType":"HOME","primaryColor":"#0E5BD8","secondaryColor":"#FFFFFF","pattern":"SOLID","assetReference":"team-kit://r4a-a-home","reason":"Register home kit"}'::jsonb
  );
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000010', entry_a_id, entry_revision,
    'availability.set',
    '{"weekday":1,"startLocalTime":"19:00","endLocalTime":"23:00","timezone":"Europe/Madrid","validFromDate":"2027-01-01","validUntilDate":"2027-12-31","reason":"NO PUEDO JUGAR lunes noche"}'::jsonb
  );
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000011', entry_a_id, entry_revision,
    'preference.set',
    '{"weekday":6,"startLocalTime":"16:00","endLocalTime":"20:00","timezone":"Europe/Madrid","weight":80,"preferredArea":"Barcelona","venueReference":"venue://future-r4a","reason":"PREFERIRIA JUGAR sabado tarde"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_team_availability_constraints where entry_id = entry_a_id) = 1
    and (select count(*) from public.pachanga_team_schedule_preferences where entry_id = entry_a_id) = 1,
    'Hard availability and soft preference were not stored as distinct domains'
  );

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000012', roster_a_id, roster_revision,
    'roster.submit', '{"reason":"Initial roster submission"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000013', roster_a_id, roster_revision,
    'roster.request_changes', '{"reason":"Check credentials before approval"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000014', roster_a_id, roster_revision,
    'roster.reopen', '{"reason":"Reopen requested roster"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000015', roster_a_id, roster_revision,
    'roster.submit', '{"reason":"Corrected roster submission"}'::jsonb
  );

  select id into shared_credential_id from public.pachanga_player_competition_credentials
  where player_profile_id = 'd4110000-0000-4000-8000-000000000001'
    and category_id = (select value from r4a_ids where key = 'open_category');
  select id into a2_credential_id from public.pachanga_player_competition_credentials
  where player_profile_id = 'd4110000-0000-4000-8000-000000000002'
    and category_id = (select value from r4a_ids where key = 'open_category');
  select id into a3_credential_id from public.pachanga_player_competition_credentials
  where player_profile_id = 'd4110000-0000-4000-8000-000000000003'
    and category_id = (select value from r4a_ids where key = 'open_category');
  insert into r4a_ids values
    ('credential_shared_open', shared_credential_id),
    ('credential_a2_open', a2_credential_id),
    ('credential_a3_open', a3_credential_id);

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000016', shared_credential_id, 1,
    'credential.review',
    '{"status":"pending","verificationMethod":"MANUAL_REVIEW","reasonCode":"credential.pending_review","reason":"Review opened"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000017', shared_credential_id, 2,
    'credential.review',
    jsonb_build_object(
      'status', 'verified', 'verificationMethod', 'MANUAL_REVIEW',
      'expiresAt', clock_timestamp() + interval '2 years',
      'evidenceReference', 'vault://r4a/opaque/shared',
      'reasonCode', 'credential.verified', 'reason', 'Identity verified'
    )
  );
  perform pg_temp.assert_true(
    not (response::text like '%vault://r4a/opaque/shared%')
    and (select evidence_reference from private.pachanga_competition_credential_evidence
      where credential_id = shared_credential_id) = 'vault://r4a/opaque/shared',
    'Credential evidence was not private and opaque'
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000018', a2_credential_id, 1,
    'credential.review',
    '{"status":"rejected","verificationMethod":"MANUAL_REVIEW","reasonCode":"credential.insufficient","reason":"Insufficient credential"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4210000-0000-4000-8000-000000000019', a2_credential_id, 2,
    'eligibility.waive',
    jsonb_build_object(
      'validUntil', clock_timestamp() + interval '1 year',
      'reasonCode', 'eligibility.organizer_waiver',
      'reason', 'Explicit organizer eligibility waiver'
    )
  );

  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000020', a3_credential_id, 1,
    'credential.review',
    '{"status":"pending","verificationMethod":"MANUAL_REVIEW","reasonCode":"credential.pending_review","reason":"Pending credential"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000021', a3_credential_id, 2,
    'credential.review',
    '{"status":"expired","verificationMethod":"MANUAL_REVIEW","reasonCode":"credential.expired","reason":"Expired credential"}'::jsonb
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000022', a3_credential_id, 3,
    'credential.review',
    jsonb_build_object(
      'status', 'verified', 'verificationMethod', 'MANUAL_REVIEW',
      'expiresAt', clock_timestamp() + interval '2 years',
      'reasonCode', 'credential.verified', 'reason', 'Renewed credential'
    )
  );

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000023', roster_a_id, roster_revision,
    'roster.approve', '{"reason":"All eligibility resolved"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000024', roster_a_id, roster_revision,
    'roster.lock', '{"reason":"Lock approved roster"}'::jsonb
  );
  immutable_revision_id := (select current_revision_id from public.pachanga_competition_rosters where id = roster_a_id);
  perform pg_temp.expect_failure(
    format('update public.pachanga_competition_roster_revisions set reason = %L where id = %L',
      'Forbidden rewrite', immutable_revision_id),
    'ROSTER_REVISION_IMMUTABLE'
  );

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000025', roster_a_id, roster_revision,
    'roster.amend', '{"reason":"Authorized post-lock amendment"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000026', roster_a_id, roster_revision,
    'roster.member.remove',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000003","reason":"Remove third player in amendment"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000020',
    'd4210000-0000-4000-8000-000000000027', roster_a_id, roster_revision,
    'roster.submit', '{"reason":"Submit amended roster"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000028', roster_a_id, roster_revision,
    'roster.approve', '{"reason":"Approve amended roster"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000005',
    'd4210000-0000-4000-8000-000000000029', roster_a_id, roster_revision,
    'roster.lock', '{"reason":"Lock amended roster"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,roster,status}' = 'locked'
    and (response #>> '{snapshot,currentRevision,memberCount}')::integer = 2
    and (response #>> '{snapshot,currentRevision,eligibilitySummary,eligible}')::integer = 1
    and (response #>> '{snapshot,currentRevision,eligibilitySummary,waived}')::integer = 1,
    'Final Team A roster does not match its canonical eligibility snapshot'
  );

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000015',
    'd4210000-0000-4000-8000-000000000030', roster_b_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","reason":"Same category multi-team conflict"}'::jsonb,
    'PLAYER_MULTI_TEAM_CONFLICT'
  );

  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_veterans_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000015',
    'd4210000-0000-4000-8000-000000000031', roster_b_veterans_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","reason":"Different category allowed"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_veterans_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000015',
    'd4210000-0000-4000-8000-000000000032', roster_b_veterans_id, roster_revision,
    'jersey.assign',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000001","number":12,"reason":"Veterans jersey"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_veterans_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000015',
    'd4210000-0000-4000-8000-000000000033', roster_b_veterans_id, roster_revision,
    'roster.submit', '{"reason":"Below minimum roster"}'::jsonb,
    'ROSTER_BELOW_MINIMUM'
  );

  -- Four members are allowed, while the fifth is rejected by the frozen rule revision.
  for shared_credential_id in
    select unnest(array[
      'd4110000-0000-4000-8000-000000000004'::uuid,
      'd4110000-0000-4000-8000-000000000005'::uuid,
      'd4110000-0000-4000-8000-000000000006'::uuid,
      'd4110000-0000-4000-8000-000000000007'::uuid
    ])
  loop
    select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_id;
    response := pg_temp.run_command(
      'd4010000-0000-4000-8000-000000000015', gen_random_uuid(), roster_b_id,
      roster_revision, 'roster.member.add',
      jsonb_build_object('playerProfileId', shared_credential_id, 'reason', 'Fill Team B roster')
    );
  end loop;
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_b_id;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000015',
    'd4210000-0000-4000-8000-000000000034', roster_b_id, roster_revision,
    'roster.member.add',
    '{"playerProfileId":"d4110000-0000-4000-8000-000000000008","reason":"Above maximum roster"}'::jsonb,
    'ROSTER_ABOVE_MAXIMUM'
  );
end;
$$;

-- Stage membership, canonical reads, closure semantics and historical membership preservation.
do $$
declare
  response jsonb;
  public_snapshot jsonb;
  entry_a_id uuid := (select value from r4a_ids where key = 'entry_a');
  entry_b_id uuid := (select value from r4a_ids where key = 'entry_b');
  roster_a_id uuid := (select value from r4a_ids where key = 'roster_a');
  entry_revision bigint;
  edition_revision bigint;
  category_revision bigint;
  second_category_id uuid;
  second_entry_id uuid;
  second_roster_id uuid;
begin
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_a_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000001', entry_a_id, entry_revision,
    'stage_membership.assign',
    '{"stageId":"d4080000-0000-4000-8000-000000000001","divisionId":"d4090000-0000-4000-8000-000000000001","groupId":"d40a0000-0000-4000-8000-000000000001","reason":"Assign Team A to Group A"}'::jsonb
  );
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_b_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000002', entry_b_id, entry_revision,
    'stage_membership.assign',
    '{"stageId":"d4080000-0000-4000-8000-000000000001","divisionId":"d4090000-0000-4000-8000-000000000001","groupId":"d40a0000-0000-4000-8000-000000000001","reason":"Assign Team B to Group A"}'::jsonb
  );
  select revision into entry_revision from public.pachanga_competition_entries where id = entry_b_id;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000003', entry_b_id, entry_revision,
    'stage_membership.assign',
    '{"stageId":"d4080000-0000-4000-8000-000000000001","divisionId":"d4090000-0000-4000-8000-000000000001","groupId":"d40a0000-0000-4000-8000-000000000002","reason":"Reassign Team B before fixtures"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_stage_memberships
      where entry_id = entry_b_id and status = 'closed') = 1
    and (select count(*) from public.pachanga_competition_stage_memberships
      where entry_id = entry_b_id and status = 'active'
        and competition_group_id = 'd40a0000-0000-4000-8000-000000000002') = 1,
    'Stage reassignment did not close the previous membership and preserve history'
  );

  perform pg_temp.actor(null, 'anon');
  public_snapshot := public.get_pachanga_league_public_registration_v1(
    'd4040000-0000-4000-8000-000000000001'
  );
  perform pg_temp.assert_true(
    public_snapshot #>> '{competition,type}' = 'LEAGUE'
    and (public_snapshot #>> '{teamLimits,minimum}')::integer = 1
    and (public_snapshot #>> '{teamLimits,maximum}')::integer = 3
    and not (public_snapshot::text like '%Private organizer rejection reason%')
    and not (public_snapshot::text like '%rejected%'),
    'Public registration read model leaked private entry data or ignored frozen team limits'
  );

  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000001';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000004',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'registration.notify_closing', '{"reason":"Notify closing once"}'::jsonb
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000005',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'registration.notify_closing', '{"reason":"Duplicate closing notice"}'::jsonb,
    'REGISTRATION_CLOSING_ALREADY_NOTIFIED'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000006',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'registration.close', '{"reason":"Pending invitation must block close"}'::jsonb,
    'REGISTRATION_PENDING_ENTRIES'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000007',
    'd4070000-0000-4000-8000-000000000001', edition_revision,
    'registration.close_and_expire_pending',
    '{"reason":"Close and expire unresolved invitations"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,status}' = 'registration_closed'
    and (response #>> '{snapshot,expiredPendingCount}')::integer = 1
    and (select status from public.pachanga_competition_entries
      where id = (select value from r4a_ids where key = 'entry_c_veterans')) = 'expired',
    'Registration close-and-expire did not resolve every pending entry'
  );

  select revision into category_revision from public.pachanga_competition_categories
  where id = (select value from r4a_ids where key = 'open_category');
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4220000-0000-4000-8000-000000000008',
    (select value from r4a_ids where key = 'open_category'), category_revision,
    'category.close', '{"reason":"Close category after registration"}'::jsonb
  );
  category_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000021',
    'd4220000-0000-4000-8000-000000000009',
    (select value from r4a_ids where key = 'open_category'), category_revision,
    'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000004","reason":"Closed category application"}'::jsonb,
    'CATEGORY_NOT_ACTIVE'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4220000-0000-4000-8000-000000000010',
    (select value from r4a_ids where key = 'open_category'), category_revision,
    'category.archive', '{"reason":"Archive closed category"}'::jsonb
  );

  -- A second edition proves INVITE_ONLY and the normal close path without pending entries.
  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000002';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4220000-0000-4000-8000-000000000011',
    'd4070000-0000-4000-8000-000000000002', edition_revision,
    'category.create',
    '{"name":"Second Open","slug":"second-open","sportFormat":"FOOTBALL_7","visibility":"public","minimumAge":18,"ageReferenceDate":"2028-01-01","ruleRevisionId":"d4060000-0000-4000-8000-000000000001","reason":"Second edition category"}'::jsonb
  );
  second_category_id := (response #>> '{snapshot,id}')::uuid;
  insert into r4a_ids values ('second_category', second_category_id);
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000003',
    'd4220000-0000-4000-8000-000000000012', second_category_id, 1,
    'category.activate', '{"reason":"Activate second category"}'::jsonb
  );
  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000002';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000013',
    'd4070000-0000-4000-8000-000000000002', edition_revision,
    'registration.open',
    jsonb_build_object(
      'registrationMode', 'INVITE_ONLY',
      'closesAt', clock_timestamp() + interval '60 days',
      'ruleRevisionId', 'd4060000-0000-4000-8000-000000000001',
      'reason', 'Open invite-only registration'
    )
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000021',
    'd4220000-0000-4000-8000-000000000014', second_category_id, 2,
    'entry.submit',
    '{"teamId":"d4020000-0000-4000-8000-000000000004","reason":"Public application unavailable"}'::jsonb,
    'PUBLIC_REGISTRATION_NOT_AVAILABLE'
  );
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000015', second_category_id, 2,
    'entry.invite',
    '{"teamId":"d4020000-0000-4000-8000-000000000004","reason":"Invite Team D to second edition"}'::jsonb
  );
  second_entry_id := (response #>> '{snapshot,entry,id}')::uuid;
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000021',
    'd4220000-0000-4000-8000-000000000016', second_entry_id, 1,
    'entry.accept', '{"reason":"Team D accepts second edition"}'::jsonb
  );
  select id into second_roster_id from public.pachanga_competition_rosters where entry_id = second_entry_id;
  perform pg_temp.assert_true(second_roster_id is not null, 'Second invitation did not create a roster');
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000021',
    'd4220000-0000-4000-8000-000000000017', second_entry_id, 2,
    'entry.withdraw', '{"reason":"Team D withdraws correctly"}'::jsonb
  );
  select revision into edition_revision from public.pachanga_competition_editions
  where id = 'd4070000-0000-4000-8000-000000000002';
  response := pg_temp.run_command(
    'd4010000-0000-4000-8000-000000000004',
    'd4220000-0000-4000-8000-000000000018',
    'd4070000-0000-4000-8000-000000000002', edition_revision,
    'registration.close', '{"reason":"Close resolved invite-only registration"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,status}' = 'registration_closed'
    and (response #>> '{snapshot,expiredPendingCount}')::integer = 0,
    'Normal registration.close did not finish the resolved edition'
  );

  insert into public.pachanga_competitions(
    id, organizer_kind, organizer_group_id, organizer_club_id, name, slug,
    competition_type, visibility, status, created_by
  ) values (
    'd4040000-0000-4000-8000-000000000002', 'CLUB', null,
    'd4030000-0000-4000-8000-000000000001', 'R4A Tournament Guard',
    'r4a-tournament-guard', 'TOURNAMENT', 'private', 'draft',
    'd4010000-0000-4000-8000-000000000003'
  );
  insert into public.pachanga_competition_editions(
    id, competition_id, name, season_label, starts_at, ends_at,
    status, rule_revision_id, revision, created_by
  ) values (
    'd4070000-0000-4000-8000-000000000003',
    'd4040000-0000-4000-8000-000000000002', 'Tournament guard', '2027',
    '2027-01-01', '2027-12-31', 'draft', null, 1,
    'd4010000-0000-4000-8000-000000000003'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000003',
    'd4220000-0000-4000-8000-000000000019',
    'd4070000-0000-4000-8000-000000000003', 1,
    'category.create',
    '{"name":"Unavailable","slug":"unavailable","sportFormat":"FOOTBALL_7","ruleRevisionId":"d4060000-0000-4000-8000-000000000001","reason":"Tournament must remain unavailable"}'::jsonb,
    'FEATURE_NOT_AVAILABLE'
  );

  -- Membership departure keeps prior locked revisions and marks only the new snapshot.
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000010');
  response := public.remove_pachanga_group_member_authoritative_v1(
    'd4020000-0000-4000-8000-000000000001',
    'd4010000-0000-4000-8000-000000000012',
    'd4220000-0000-4000-8000-000000000020',
    (select payload_revision from public.pachanga_groups
      where id = 'd4020000-0000-4000-8000-000000000001'),
    '{"clientVersion":"4.0.0+r4a-db","installedMode":"standalone","surface":"team-members"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_rosters where id = roster_a_id) = 'amended'
    and exists (
      select 1 from public.pachanga_competition_roster_members members
      join public.pachanga_competition_rosters rosters
        on rosters.current_revision_id = members.roster_revision_id
      where rosters.id = roster_a_id
        and members.player_profile_id = 'd4110000-0000-4000-8000-000000000001'
        and members.eligibility_status = 'review_required'
        and members.reason_code = 'eligibility.team_membership_ended'
    )
    and exists (
      select 1 from public.pachanga_competition_roster_members members
      join public.pachanga_competition_roster_revisions revisions
        on revisions.id = members.roster_revision_id
      where revisions.roster_id = roster_a_id and revisions.roster_status = 'locked'
        and members.player_profile_id = 'd4110000-0000-4000-8000-000000000001'
        and members.eligibility_status = 'eligible'
    )
    and exists (
      select 1 from public.pachanga_group_members
      where group_id = 'd4020000-0000-4000-8000-000000000002'
        and user_id = 'd4010000-0000-4000-8000-000000000012'
    ),
    'Player departure did not preserve historical eligibility or leaked across teams'
  );
end;
$$;

do $$
declare
  snapshot jsonb;
  roster_a_id uuid := (select value from r4a_ids where key = 'roster_a');
  entry_a_id uuid := (select value from r4a_ids where key = 'entry_a');
  notification_count_before integer;
  notification_count_after integer;
  replay_row record;
  replay_response jsonb;
  flags_revision bigint;
begin
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000008');
  snapshot := public.get_my_pachanga_competition_entries_v1(0, 10);
  perform pg_temp.assert_true(
    (snapshot ->> 'total')::integer = 0,
    'A normal user or revoked delegate can still read private entries'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000013');
  snapshot := public.get_my_pachanga_competition_entries_v1(0, 10);
  perform pg_temp.assert_true(
    (snapshot ->> 'total')::integer >= 1
    and snapshot::text like '%' || entry_a_id::text || '%',
    'A current team player cannot discover their team entry'
  );
  snapshot := public.get_pachanga_competition_roster_v1(roster_a_id, 0, 100);
  perform pg_temp.assert_true(
    snapshot #>> '{actorScope}' = 'TEAM_PLAYER'
    and (snapshot #>> '{memberPagination,total}')::integer = 1
    and snapshot #>> '{members,0,playerProfileId}' = 'd4110000-0000-4000-8000-000000000002',
    'A team player can read members other than their own permitted roster record'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000020');
  snapshot := public.get_pachanga_competition_entry_v1(entry_a_id);
  perform pg_temp.assert_true(
    snapshot #>> '{actorScope}' = 'PRIMARY_DELEGATE'
    and snapshot #>> '{entry,id}' = entry_a_id::text,
    'The active primary delegate cannot read their bounded entry'
  );
  perform pg_temp.expect_failure(
    format('select public.get_pachanga_competition_entry_v1(%L)',
      (select value from r4a_ids where key = 'entry_b')),
    'ENTRY_READ_FORBIDDEN'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000004');
  snapshot := public.get_pachanga_competition_registration_desk_v1(
    'd4040000-0000-4000-8000-000000000001', null, null, 0, 3
  );
  perform pg_temp.assert_true(
    (snapshot ->> 'total')::integer >= 7
    and jsonb_array_length(snapshot -> 'items') = 3,
    'Organizer desk does not paginate server-side or misses entry history'
  );
  snapshot := public.get_pachanga_competition_registration_desk_v1(
    'd4040000-0000-4000-8000-000000000001', 'rejected', null, 0, 10
  );
  perform pg_temp.assert_true(
    snapshot #>> '{items,0,privateReason}' = 'Private organizer rejection reason',
    'Authorized organizer cannot inspect the private rejection reason'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000007');
  perform pg_temp.expect_failure(
    $sql$select public.get_pachanga_competition_registration_desk_v1(
      'd4040000-0000-4000-8000-000000000001', null, null, 0, 10
    )$sql$,
    'REGISTRATION_DESK_FORBIDDEN'
  );
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000006');
  perform pg_temp.expect_failure(
    $sql$select public.get_pachanga_competition_registration_desk_v1(
      'd4040000-0000-4000-8000-000000000001', null, null, 0, 10
    )$sql$,
    'REGISTRATION_DESK_FORBIDDEN'
  );
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  snapshot := public.get_pachanga_platform_league_participation_v1(0, 2);
  perform pg_temp.assert_true(
    (snapshot #>> '{metrics,entries}')::integer >= 7
    and jsonb_array_length(snapshot -> 'items') = 2
    and snapshot #>> '{flags,foundationEnabled}' = 'true',
    'Control Center read model is not paginated or platform-authorized'
  );

  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.dedupe_key like 'league:d42%'
      and (
        notifications.body like '%Private organizer rejection reason%'
        or notifications.payload::text like '%vault://r4a/opaque/shared%'
        or notifications.payload::text like '%@example.test%'
      )
  ), 'League notifications leaked private reasons, evidence or email');
  perform pg_temp.assert_true(not exists (
    select notifications.dedupe_key
    from public.pachanga_user_notifications notifications
    where notifications.dedupe_key like 'league:d42%'
    group by notifications.dedupe_key having count(*) > 1
  ), 'League notification fan-out is not deduplicated');

  select count(*) into notification_count_before
  from public.pachanga_user_notifications where dedupe_key like 'league:%';
  for replay_row in select * from r4a_command_log order by operation_id
  loop
    perform pg_temp.actor(replay_row.actor_id);
    replay_response := public.command_pachanga_league_participation_v1(
      replay_row.operation_id, replay_row.aggregate_id,
      replay_row.expected_revision, replay_row.action,
      replay_row.payload,
      '{"clientVersion":"4.0.0+r4a-db","serviceWorkerVersion":"sw-r4a-db","installedMode":"standalone","surface":"r4a_db"}'::jsonb
    );
    perform pg_temp.assert_true(
      replay_response = replay_row.response,
      'Idempotent replay diverged for ' || replay_row.action
    );
    perform pg_temp.assert_true(
      (select count(*) from private.pachanga_competition_operation_receipts receipts
        where receipts.operation_id = replay_row.operation_id) = 1,
      'Idempotent replay duplicated a receipt for ' || replay_row.action
    );
  end loop;
  select count(*) into notification_count_after
  from public.pachanga_user_notifications where dedupe_key like 'league:%';
  perform pg_temp.assert_true(
    notification_count_after = notification_count_before,
    'Idempotent replay duplicated notification fan-out'
  );

  perform pg_temp.assert_true(not exists (
    select events.server_sequence
    from private.pachanga_competition_events events
    group by events.server_sequence
    having count(*) > 1
  ), 'Server event ordering is not unique');

  insert into private.pachanga_competition_events(
    id, operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values
    (
      'd4250000-0000-4000-8000-000000000001',
      'd4240000-0000-4000-8000-000000000001',
      'd4010000-0000-4000-8000-000000000001', 'authenticated',
      'competition_entry', 'same-time-order-a',
      'd4040000-0000-4000-8000-000000000001', 'test.same_time.a', 900,
      nextval('private.pachanga_competition_sequence'),
      'test.same_time.a', '{}'::jsonb, '2030-01-01 12:00:00+00'
    ),
    (
      'd4250000-0000-4000-8000-000000000002',
      'd4240000-0000-4000-8000-000000000002',
      'd4010000-0000-4000-8000-000000000001', 'authenticated',
      'competition_entry', 'same-time-order-b',
      'd4040000-0000-4000-8000-000000000001', 'test.same_time.b', 901,
      nextval('private.pachanga_competition_sequence'),
      'test.same_time.b', '{}'::jsonb, '2030-01-01 12:00:00+00'
    );
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  snapshot := public.get_pachanga_platform_league_participation_v1(0, 2);
  perform pg_temp.assert_true(
    snapshot #>> '{events,0,id}' = 'd4250000-0000-4000-8000-000000000002'
    and snapshot #>> '{events,1,id}' = 'd4250000-0000-4000-8000-000000000001',
    'Canonical event selection depended on a tied timestamp'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_invalidations invalidations
    where invalidations.server_sequence is null or invalidations.revision is null
  ), 'Realtime invalidation lacks server ordering or canonical revision');

  select revision into flags_revision
  from private.pachanga_competition_foundation_settings where singleton;
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  snapshot := public.command_pachanga_league_participation_platform_v1(
    'd4230000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c4a1', flags_revision,
    '{"foundationEnabled":false,"reason":"Finish isolated R4A QA with flags off"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-db","installedMode":"browser","surface":"r4a_db"}'::jsonb
  );
  perform pg_temp.assert_true(
    snapshot #>> '{snapshot,foundationEnabled}' = 'false'
    and snapshot #>> '{snapshot,registrationEnabled}' = 'false'
    and snapshot #>> '{snapshot,publicRegistrationEnabled}' = 'false'
    and snapshot #>> '{snapshot,delegatesEnabled}' = 'false'
    and snapshot #>> '{snapshot,rostersEnabled}' = 'false'
    and snapshot #>> '{snapshot,schedulePreferencesEnabled}' = 'false',
    'R4A flags did not return to the required OFF state'
  );
  perform pg_temp.actor(null, 'anon');
  perform pg_temp.expect_failure(
    $sql$select public.get_pachanga_league_public_registration_v1(
      'd4040000-0000-4000-8000-000000000001'
    )$sql$,
    'LEAGUE_PUBLIC_REGISTRATION_DISABLED'
  );

  perform pg_temp.assert_true(not exists (
    select 1 from r4a_invariants_before baseline
    where pg_temp.table_digest(baseline.table_name::regclass) <> baseline.digest
  ), 'R4A modified a protected Rating, match, reward, conduct, billing or ranking authority');
  perform pg_temp.assert_true(
    to_regclass('public.pachanga_competition_rounds') is null
    and to_regclass('public.pachanga_league_fixtures') is null
    and to_regclass('public.pachanga_competition_standings') is null,
    'R4A accidentally introduced rounds, fixtures or standings'
  );
end;
$$;

-- Exercise grants and RLS under the actual Data API roles, not only as postgres.
set local role anon;
select pg_temp.actor(null, 'anon');
select pg_temp.expect_failure(
  $$select public.command_pachanga_league_participation_v1(
    'd4230000-0000-4000-8000-000000000010',
    'd4070000-0000-4000-8000-000000000001', 1,
    'round.create', '{}'::jsonb, '{}'::jsonb
  )$$,
  'permission denied|Authentication required'
);
reset role;

set local role authenticated;
select pg_temp.actor('d4010000-0000-4000-8000-000000000013');
select pg_temp.expect_failure(
  $$select count(*) from public.pachanga_competition_entries$$,
  'permission denied'
);
select pg_temp.expect_failure(
  $$insert into public.pachanga_competition_entries(
    competition_id, edition_id, category_id, team_id, entry_source,
    status, rule_revision_id, reason_code, created_by
  ) values (
    'd4040000-0000-4000-8000-000000000001',
    'd4070000-0000-4000-8000-000000000001',
    (select value from r4a_ids where key = 'veterans_category'),
    'd4020000-0000-4000-8000-000000000001',
    'PUBLIC_APPLICATION', 'submitted',
    'd4060000-0000-4000-8000-000000000001',
    'direct.write.forbidden',
    'd4010000-0000-4000-8000-000000000013'
  )$$,
  'permission denied'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_invalidations
    where target_group_id = 'd4020000-0000-4000-8000-000000000001') > 0
  and (select count(*) from public.pachanga_competition_invalidations
    where target_group_id = 'd4020000-0000-4000-8000-000000000002') = 0,
  'Team player Realtime policy crossed team scope'
);

select pg_temp.actor('d4010000-0000-4000-8000-000000000020');
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_invalidations
    where target_group_id = 'd4020000-0000-4000-8000-000000000001') > 0
  and (select count(*) from public.pachanga_competition_invalidations
    where target_group_id = 'd4020000-0000-4000-8000-000000000002') = 0,
  'Delegate Realtime policy crossed entry/team scope'
);

select pg_temp.actor('d4010000-0000-4000-8000-000000000008');
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_invalidations
    where competition_id is not null) > 0
  and not exists (
    select 1 from public.pachanga_competition_invalidations
    where competition_id is not null
      and target_user_id is distinct from 'd4010000-0000-4000-8000-000000000008'
  ),
  'Normal user can read competition invalidations outside their personal target scope'
);
reset role;

select pg_temp.assert_true(
  (select count(*) from public.pachanga_canonical_matches) = 0
  and (select count(*) from public.pachanga_competition_match_contexts) = 0,
  'R4A created canonical matches or competition match contexts'
);
