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

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'R4B_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4B_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.command(
  target_actor_id uuid,
  target_operation_id uuid,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.actor(target_actor_id);
  return public.command_pachanga_league_scheduling_v1(
    target_operation_id,
    target_aggregate_id,
    target_expected_revision,
    target_action,
    target_payload,
    jsonb_build_object(
      'clientVersion', '4.0.0+r4b-db',
      'serviceWorkerVersion', 'sw-r4b-db',
      'installedMode', 'standalone',
      'surface', 'r4b_db'
    )
  );
end;
$$;

create temporary table r4b_invariants_before(table_name text primary key, digest text not null);
create or replace function pg_temp.table_digest(target_table regclass)
returns text language plpgsql as $$
declare result text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(rows)::text, E''\n'' order by to_jsonb(rows)::text), '''')) from %s rows',
    target_table
  ) into result;
  return result;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('e4010000-0000-4000-8000-000000000001', 'r4b-platform@example.test', clock_timestamp(), '{"full_name":"Platform"}'),
  ('e4010000-0000-4000-8000-000000000002', 'r4b-director@example.test', clock_timestamp(), '{"full_name":"Director"}'),
  ('e4010000-0000-4000-8000-000000000003', 'r4b-schedule@example.test', clock_timestamp(), '{"full_name":"Schedule manager"}'),
  ('e4010000-0000-4000-8000-000000000004', 'r4b-viewer@example.test', clock_timestamp(), '{"full_name":"Viewer"}'),
  ('e4010000-0000-4000-8000-000000000005', 'r4b-outsider@example.test', clock_timestamp(), '{"full_name":"Outsider"}');

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select md5('r4b-owner-' || value)::uuid,
  'r4b-owner-' || value || '@example.test', clock_timestamp(),
  jsonb_build_object('full_name', 'Team ' || value || ' owner')
from generate_series(0, 6) value;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('e4010000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select md5('r4b-team-' || value)::uuid, md5('r4b-owner-' || value)::uuid,
  case when value = 0 then 'R4B Organizer' else 'R4B Team ' || value end,
  'R4B' || lpad(value::text, 5, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb, 1
from generate_series(0, 6) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select md5('r4b-team-' || value)::uuid, md5('r4b-owner-' || value)::uuid,
  'owner', case when value = 0 then 'Organizer owner' else 'Team ' || value || ' owner' end
from generate_series(0, 6) value;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  'e4040000-0000-4000-8000-000000000001', 'TEAM', md5('r4b-team-0')::uuid,
  'R4B League 2027', 'r4b-qa-league-2027', 'LEAGUE', 'public', 'draft',
  'e4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  reason, granted_by
) values
  ('TEAM', md5('r4b-team-0')::uuid, 'competition_manage', 'platform_grant', 'active', 'R4B DB test', 'e4010000-0000-4000-8000-000000000001'),
  ('TEAM', md5('r4b-team-0')::uuid, 'competition_schedule', 'platform_grant', 'active', 'R4B DB test', 'e4010000-0000-4000-8000-000000000001');

insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values ('e4050000-0000-4000-8000-000000000001', 'e4040000-0000-4000-8000-000000000001', 'R4B Rules', 'active', 'e4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select 'e4060000-0000-4000-8000-000000000001',
  'e4050000-0000-4000-8000-000000000001', 1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'frozen', 1, 'R4B deterministic test rules',
  'e4010000-0000-4000-8000-000000000002'
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{"rosterPolicy":{"minimumSize":0,"maximumSize":30,"closeRequiresApprovedRosters":true}},
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
  "operations":{"schedulePolicy":{
    "format":"ROUND_ROBIN","legs":1,"matchDurationMinutes":70,
    "requiredBufferMinutes":10,"minimumRestMinutes":0,
    "homeAwayPolicy":"BALANCED","venueRequired":false,
    "maximumHomeAwayStreak":3,"hardHomeAwayStreak":false,
    "windowStartsAt":"2027-01-15T00:00:00Z","windowEndsAt":"2027-11-30T23:59:59Z",
    "rosterStatuses":["approved","locked"],
    "softPreferenceWeights":{"day":60,"time":30,"homeAway":10}
  }},
  "results":{},"discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb)) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_closed_at,
  registration_rule_revision_id, revision, created_by
) values (
  'e4070000-0000-4000-8000-000000000001', 'e4040000-0000-4000-8000-000000000001',
  'Season 2027', '2027', '2027-01-01', '2027-12-31', 'registration_closed',
  'e4060000-0000-4000-8000-000000000001', 'CLOSED', clock_timestamp(),
  'e4060000-0000-4000-8000-000000000001', 1, 'e4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
) values (
  'e40b0000-0000-4000-8000-000000000001', 'e4070000-0000-4000-8000-000000000001',
  'Senior', 'senior', 'FOOTBALL_7', 'public', 'active',
  'e4060000-0000-4000-8000-000000000001', 1, 'e4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
) values (
  'e4080000-0000-4000-8000-000000000001', 'e4070000-0000-4000-8000-000000000001',
  'Liga regular', 'LEAGUE_STAGE', 0, false, 'draft',
  'e4060000-0000-4000-8000-000000000001', 1, 'e4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_divisions(id, stage_id, name, division_order, level_label, status, created_by)
values ('e4090000-0000-4000-8000-000000000001', 'e4080000-0000-4000-8000-000000000001', 'División 1', 0, 'Open', 'draft', 'e4010000-0000-4000-8000-000000000002');
insert into public.pachanga_competition_groups(id, stage_id, division_id, name, group_order, status, created_by)
values ('e40a0000-0000-4000-8000-000000000001', 'e4080000-0000-4000-8000-000000000001', 'e4090000-0000-4000-8000-000000000001', 'Grupo A', 0, 'draft', 'e4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_staff_assignments(competition_id, user_id, staff_role, status, assigned_by) values
  ('e4040000-0000-4000-8000-000000000001', 'e4010000-0000-4000-8000-000000000002', 'competition_director', 'active', 'e4010000-0000-4000-8000-000000000002'),
  ('e4040000-0000-4000-8000-000000000001', 'e4010000-0000-4000-8000-000000000003', 'competition_schedule_manager', 'active', 'e4010000-0000-4000-8000-000000000002'),
  ('e4040000-0000-4000-8000-000000000001', 'e4010000-0000-4000-8000-000000000004', 'viewer', 'active', 'e4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source, status,
  rule_revision_id, accepted_by, accepted_at, reason_code, created_by
)
select md5('r4b-entry-' || value)::uuid, 'e4040000-0000-4000-8000-000000000001',
  'e4070000-0000-4000-8000-000000000001', 'e40b0000-0000-4000-8000-000000000001',
  md5('r4b-team-' || value)::uuid, 'ORGANIZER_INVITATION', 'accepted',
  'e4060000-0000-4000-8000-000000000001', 'e4010000-0000-4000-8000-000000000002',
  clock_timestamp(), 'r4b.fixture.accepted', 'e4010000-0000-4000-8000-000000000002'
from generate_series(1, 6) value;

insert into public.pachanga_competition_stage_memberships(
  id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
  status, reason, assigned_by
)
select md5('r4b-membership-' || value)::uuid, md5('r4b-entry-' || value)::uuid,
  'e4080000-0000-4000-8000-000000000001', 'e4090000-0000-4000-8000-000000000001',
  'e40a0000-0000-4000-8000-000000000001', 'e4060000-0000-4000-8000-000000000001',
  'active', 'R4B fixture membership', 'e4010000-0000-4000-8000-000000000002'
from generate_series(1, 6) value;

insert into public.pachanga_competition_rosters(
  id, entry_id, category_id, rule_revision_id, status, revision, created_by
)
select md5('r4b-roster-' || value)::uuid, md5('r4b-entry-' || value)::uuid,
  'e40b0000-0000-4000-8000-000000000001', 'e4060000-0000-4000-8000-000000000001',
  'locked', 1, 'e4010000-0000-4000-8000-000000000002'
from generate_series(1, 6) value;

insert into public.pachanga_competition_roster_revisions(
  id, roster_id, revision_number, roster_status, rule_revision_id, member_count,
  eligibility_summary, member_set_checksum, reason, created_by
)
select md5('r4b-roster-revision-' || value)::uuid, md5('r4b-roster-' || value)::uuid,
  1, 'locked', 'e4060000-0000-4000-8000-000000000001', 0,
  '{"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}'::jsonb,
  encode(extensions.digest(convert_to('r4b-roster-' || value, 'UTF8'), 'sha256'), 'hex'),
  'R4B locked fixture', 'e4010000-0000-4000-8000-000000000002'
from generate_series(1, 6) value;

update public.pachanga_competition_rosters rosters set current_revision_id = revisions.id
from public.pachanga_competition_roster_revisions revisions
where revisions.roster_id = rosters.id and rosters.id in (
  select md5('r4b-roster-' || value)::uuid from generate_series(1, 6) value
);

insert into public.pachanga_team_availability_constraints(
  id, entry_id, weekday, start_local_time, end_local_time, timezone,
  valid_from_date, valid_until_date, reason, created_by
) values (
  'e4120000-0000-4000-8000-000000000001', md5('r4b-entry-1')::uuid,
  1, '19:00', '23:00', 'Europe/Madrid', '2027-01-01', '2027-12-31',
  'Team 1 unavailable on Monday', md5('r4b-owner-1')::uuid
);

insert into public.pachanga_team_schedule_preferences(
  id, entry_id, weekday, start_local_time, end_local_time, timezone, weight,
  preferred_area, status, created_by
) values
  ('e4130000-0000-4000-8000-000000000001', md5('r4b-entry-2')::uuid, 6, '16:00', '22:00', 'Europe/Madrid', 80, 'Barcelona', 'active', md5('r4b-owner-2')::uuid),
  ('e4130000-0000-4000-8000-000000000002', md5('r4b-entry-3')::uuid, 7, '09:00', '14:00', 'Europe/Madrid', 40, 'Barcelona', 'active', md5('r4b-owner-3')::uuid);

insert into r4b_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('public.pachanga_match_read_model'),
  ('public.pachanga_match_participants'),
  ('public.pachanga_match_scorers'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('public.pachanga_team_cosmetic_inventory'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_provincial_ranking_entries'),
  ('public.pachanga_stripe_webhook_events')
) tables(table_name);

do $body$
declare response jsonb;
declare replay jsonb;
declare plan_id uuid;
declare first_revision_id uuid;
declare regenerated_revision_id uuid;
declare first_signature text;
declare regenerated_signature text;
declare item_a uuid;
declare item_b uuid;
declare slot_a uuid;
declare slot_b uuid;
declare target_slot uuid;
declare current_revision bigint;
declare flag_revision bigint;
declare cleanup_plan_id uuid;
declare cleanup_archive jsonb;
begin
  perform pg_temp.actor('e4010000-0000-4000-8000-000000000003');
  perform pg_temp.assert_true(
    ('2027-03-27'::date + '20:00'::time) at time zone 'Europe/Madrid' = '2027-03-27T19:00:00Z'::timestamptz
      and ('2027-03-28'::date + '20:00'::time) at time zone 'Europe/Madrid' = '2027-03-28T18:00:00Z'::timestamptz
      and ('2027-10-30'::date + '20:00'::time) at time zone 'Europe/Madrid' = '2027-10-30T18:00:00Z'::timestamptz
      and ('2027-10-31'::date + '20:00'::time) at time zone 'Europe/Madrid' = '2027-10-31T19:00:00Z'::timestamptz,
    'Europe/Madrid DST conversion drifted for March or October'
  );
  perform pg_temp.assert_true(
    ((('2027-03-29'::date + '00:30'::time) at time zone 'Europe/Madrid') at time zone 'Europe/Madrid')::date = '2027-03-29'::date
      and ((('2027-10-31'::date + '00:30'::time) at time zone 'Europe/Madrid') at time zone 'Europe/Madrid')::date = '2027-10-31'::date,
    'Europe/Madrid local date crossed midnight incorrectly'
  );
  perform pg_temp.expect_failure(
    $$select public.command_pachanga_league_scheduling_v1(
      'e4200000-0000-4000-8000-000000000000',
      'e4080000-0000-4000-8000-000000000001', 1,
      'schedule_plan.create',
      '{"categoryId":"e40b0000-0000-4000-8000-000000000001","divisionId":"e4090000-0000-4000-8000-000000000001","groupId":"e40a0000-0000-4000-8000-000000000001","ruleRevisionId":"e4060000-0000-4000-8000-000000000001","legs":1}'::jsonb,
      '{}'::jsonb
    )$$,
    'SCHEDULING_FOUNDATION_DISABLED'
  );

  perform pg_temp.actor('e4010000-0000-4000-8000-000000000001');
  select revision into flag_revision
  from private.pachanga_competition_foundation_settings
  where singleton;
  response := public.command_pachanga_league_scheduling_platform_v1(
    'e4200000-0000-4000-8000-000000000099',
    '00000000-0000-0000-0000-00000000c4b1',
    flag_revision,
    '{"foundationEnabled":true,"reason":"R4B global invalidation regression"}'::jsonb,
    '{"clientVersion":"4.0.0+r4b-db","serviceWorkerVersion":"sw-r4b-db","installedMode":"browser","surface":"r4b_db"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,foundationEnabled}' = 'true'
      and exists (
        select 1
        from public.pachanga_competition_invalidations invalidations
        where invalidations.server_sequence = (response ->> 'serverSequence')::bigint
          and invalidations.competition_id is null
          and invalidations.organizer_group_id is null
          and invalidations.organizer_club_id is null
          and invalidations.entity_type = 'league_scheduling_flags'
      ),
    'R4B platform flags did not persist a valid global invalidation'
  );

  update private.pachanga_competition_foundation_settings set
    foundation_enabled = true,
    league_participation_foundation_enabled = true,
    league_registration_enabled = true,
    league_rosters_enabled = true,
    league_scheduling_foundation_enabled = true,
    league_schedule_generation_enabled = true,
    league_schedule_editing_enabled = true,
    league_schedule_publication_enabled = true,
    league_public_calendar_enabled = true,
    league_canonical_fixture_creation_enabled = true
  where singleton;

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000092',
    'e4080000-0000-4000-8000-000000000001', 1,
    'schedule_plan.create',
    '{"categoryId":"e40b0000-0000-4000-8000-000000000001","divisionId":"e4090000-0000-4000-8000-000000000001","groupId":"e40a0000-0000-4000-8000-000000000001","ruleRevisionId":"e4060000-0000-4000-8000-000000000001","legs":1,"reason":"R4B unpublished cleanup regression"}'::jsonb
  );
  cleanup_plan_id := (response #>> '{snapshot,plan,id}')::uuid;
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000093', cleanup_plan_id, 1,
    'schedule_slot.bulk_create',
    '{"startDate":"2027-03-01","endDate":"2027-03-21","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista QA sin publicar","resourceKey":"pitch-unpublished"}'::jsonb
  );
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000094', cleanup_plan_id, 2,
    'schedule.generate', '{"seed":"r4b-unpublished-cleanup"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,plan,status}' = 'generated'
      and (response #>> '{snapshot,counts,rounds}')::integer = 5
      and (response #>> '{snapshot,counts,items}')::integer = 15,
    'Unpublished cleanup fixture was not generated'
  );
  perform pg_temp.actor(null, 'service_role');
  cleanup_archive := public.archive_pachanga_league_schedule_qa_v1(
    'e4200000-0000-4000-8000-000000000095', cleanup_plan_id,
    (response ->> 'confirmedRevision')::bigint,
    'R4B_STAGING_QA_ARCHIVE: unpublished failure cleanup regression',
    '{"clientVersion":"4.0.0+r4b-db","installedMode":"browser","surface":"r4b_db_failure_cleanup"}'::jsonb
  );
  perform pg_temp.assert_true(
    cleanup_archive #>> '{snapshot,status}' = 'cancelled'
      and (cleanup_archive #>> '{snapshot,retiredContexts}')::integer = 0
      and (cleanup_archive #>> '{snapshot,retiredBindings}')::integer = 0
      and (cleanup_archive #>> '{snapshot,retiredCanonicalMatches}')::integer = 0
      and (cleanup_archive #>> '{snapshot,retiredSlots}')::integer = 21
      and (cleanup_archive #>> '{snapshot,cancelledRounds}')::integer = 5,
    'Unpublished QA archive did not retire all generated scheduling state'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_slots slots
    where slots.competition_id = 'e4040000-0000-4000-8000-000000000001'
      and slots.status <> 'retired'
  ), 'Unpublished QA archive left active slots');
  perform pg_temp.actor('e4010000-0000-4000-8000-000000000003');

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000001',
    'e4080000-0000-4000-8000-000000000001', 1,
    'schedule_plan.create',
    '{"categoryId":"e40b0000-0000-4000-8000-000000000001","divisionId":"e4090000-0000-4000-8000-000000000001","groupId":"e40a0000-0000-4000-8000-000000000001","ruleRevisionId":"e4060000-0000-4000-8000-000000000001","legs":1,"reason":"R4B DB plan"}'::jsonb
  );
  plan_id := (response #>> '{snapshot,plan,id}')::uuid;
  perform pg_temp.assert_true(
    plan_id is not null and response #>> '{snapshot,plan,engineVersion}' = 'league-round-robin-v1'
      and (response #>> '{snapshot,plan,entryCount}')::integer = 6,
    'Schedule plan was not created from canonical R4A inputs'
  );

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000002', plan_id, 1,
    'schedule_slot.bulk_create',
    '{"startDate":"2027-02-01","endDate":"2027-02-21","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista QA","resourceKey":"pitch-1"}'::jsonb
  );
  perform pg_temp.assert_true(
    jsonb_array_length(response #> '{snapshot,affectedSlotIds}') = 21
      and (response ->> 'confirmedRevision')::integer = 2,
    'Weekly slot expansion did not persist 21 canonical UTC slots'
  );
  replay := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000002', plan_id, 1,
    'schedule_slot.bulk_create',
    '{"startDate":"2027-02-01","endDate":"2027-02-21","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista QA","resourceKey":"pitch-1"}'::jsonb
  );
  perform pg_temp.assert_true(replay = response and (
    select count(*) from public.pachanga_competition_schedule_slots slots
    where slots.competition_id = 'e4040000-0000-4000-8000-000000000001'
      and slots.status <> 'retired'
  ) = 21, 'Slot replay duplicated effects');

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000003', plan_id, 2,
    'schedule.generate', '{"seed":"r4b-reproducible-seed"}'::jsonb
  );
  first_revision_id := (response #>> '{snapshot,revision,id}')::uuid;
  select md5(string_agg(
    rounds.round_number || ':' || items.home_entry_id || ':' || items.away_entry_id || ':' || items.slot_id,
    '|' order by rounds.round_number, items.pairing_key
  )) into first_signature
  from public.pachanga_competition_schedule_items items
  join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
  where items.schedule_revision_id = first_revision_id;
  perform pg_temp.assert_true(
    (response #>> '{snapshot,counts,rounds}')::integer = 5
      and (response #>> '{snapshot,counts,items}')::integer = 15
      and (response #>> '{snapshot,counts,byes}')::integer = 0
      and (response #>> '{snapshot,counts,unassigned}')::integer = 0,
    'Six-team single-leg schedule topology is incorrect'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = first_revision_id
      and items.home_entry_id = md5('r4b-entry-1')::uuid
      and extract(isodow from items.scheduled_start at time zone 'Europe/Madrid')::integer = 1
      and (items.scheduled_start at time zone 'Europe/Madrid')::time < '23:00'::time
      and (items.scheduled_end at time zone 'Europe/Madrid')::time > '19:00'::time
  ), 'Hard team availability was violated');

  replay := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000003', plan_id, 2,
    'schedule.generate', '{"seed":"r4b-reproducible-seed"}'::jsonb
  );
  perform pg_temp.assert_true(replay = response and (
    select count(*) from public.pachanga_competition_schedule_revisions revisions
    where revisions.schedule_plan_id = plan_id
  ) = 1, 'Generate replay created a second revision');

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000004', plan_id, 3,
    'schedule.regenerate', '{"seed":"r4b-reproducible-seed"}'::jsonb
  );
  regenerated_revision_id := (response #>> '{snapshot,revision,id}')::uuid;
  select md5(string_agg(
    rounds.round_number || ':' || items.home_entry_id || ':' || items.away_entry_id || ':' || items.slot_id,
    '|' order by rounds.round_number, items.pairing_key
  )) into regenerated_signature
  from public.pachanga_competition_schedule_items items
  join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
  where items.schedule_revision_id = regenerated_revision_id;
  perform pg_temp.assert_true(
    first_signature = regenerated_signature
      and (response #>> '{snapshot,revision,supersedesRevisionId}')::uuid = first_revision_id,
    'Same inputs and seed did not reproduce pairings and slots'
  );

  select rounds.id into item_a
  from public.pachanga_competition_rounds rounds
  where rounds.schedule_revision_id = regenerated_revision_id
  order by rounds.round_number limit 1;
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000005', plan_id, 4,
    'round.rename', jsonb_build_object('roundId', item_a, 'displayName', 'Jornada inaugural')
  );
  perform pg_temp.assert_true(
    exists (select 1 from public.pachanga_competition_rounds rounds
      where rounds.schedule_revision_id = (response #>> '{snapshot,revision,id}')::uuid
        and rounds.round_number = 1 and rounds.display_name = 'Jornada inaugural'),
    'Round rename did not create a lineage revision'
  );

  regenerated_revision_id := (response #>> '{snapshot,revision,id}')::uuid;
  select items.id into item_a from public.pachanga_competition_schedule_items items
  join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
  where items.schedule_revision_id = regenerated_revision_id
  order by rounds.round_number, items.pairing_key limit 1;
  select slots.id into target_slot
  from public.pachanga_competition_schedule_slots slots
  where slots.status = 'available'
    and not exists (select 1 from public.pachanga_competition_schedule_items used
      where used.schedule_revision_id = regenerated_revision_id and used.slot_id = slots.id)
    and (private.pachanga_league_schedule_slot_check_v1(
      regenerated_revision_id,
      (select home_entry_id from public.pachanga_competition_schedule_items where id = item_a),
      (select away_entry_id from public.pachanga_competition_schedule_items where id = item_a),
      slots.id, array[item_a]
    ) ->> 'eligible')::boolean
  order by slots.starts_at desc, slots.id limit 1;
  perform pg_temp.assert_true(target_slot is not null, 'No eligible spare slot found for move regression');
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000006', plan_id, 5,
    'schedule_item.move_slot', jsonb_build_object('itemId', item_a, 'slotId', target_slot)
  );
  perform pg_temp.assert_true(
    (response #>> '{snapshot,revision,kind}') = 'manual_move'
      and (response #>> '{snapshot,revision,supersedesRevisionId}')::uuid = regenerated_revision_id,
    'Move slot did not create an immutable child revision'
  );

  regenerated_revision_id := (response #>> '{snapshot,revision,id}')::uuid;
  select first_item.id, second_item.id, first_item.slot_id, second_item.slot_id
    into item_a, item_b, slot_a, slot_b
  from public.pachanga_competition_schedule_items first_item
  join public.pachanga_competition_schedule_items second_item
    on second_item.schedule_revision_id = first_item.schedule_revision_id
    and second_item.id > first_item.id
  where first_item.schedule_revision_id = regenerated_revision_id
    and (private.pachanga_league_schedule_slot_check_v1(
      regenerated_revision_id, first_item.home_entry_id, first_item.away_entry_id,
      second_item.slot_id, array[first_item.id, second_item.id]
    ) ->> 'eligible')::boolean
    and (private.pachanga_league_schedule_slot_check_v1(
      regenerated_revision_id, second_item.home_entry_id, second_item.away_entry_id,
      first_item.slot_id, array[first_item.id, second_item.id]
    ) ->> 'eligible')::boolean
  order by first_item.server_sequence, first_item.id, second_item.id limit 1;
  perform pg_temp.assert_true(item_a is not null and item_b is not null, 'No eligible fixture pair found for atomic swap');
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000007', plan_id, 6,
    'schedule_item.swap_slot', jsonb_build_object('itemId', item_a, 'otherItemId', item_b)
  );
  regenerated_revision_id := (response #>> '{snapshot,revision,id}')::uuid;
  perform pg_temp.assert_true(
    exists (select 1 from public.pachanga_competition_schedule_items items
      join public.pachanga_competition_schedule_items source on source.id = item_a
      where items.schedule_revision_id = regenerated_revision_id
        and items.pairing_key = source.pairing_key and items.slot_id = slot_b)
    and exists (select 1 from public.pachanga_competition_schedule_items items
      join public.pachanga_competition_schedule_items source on source.id = item_b
      where items.schedule_revision_id = regenerated_revision_id
        and items.pairing_key = source.pairing_key and items.slot_id = slot_a),
    'Slot swap was not atomic'
  );

  select items.id into item_a
  from public.pachanga_competition_schedule_items items
  join (
    select entry_id, sum(side) as balance from (
      select home_entry_id as entry_id, 1 as side from public.pachanga_competition_schedule_items where schedule_revision_id = regenerated_revision_id
      union all
      select away_entry_id, -1 from public.pachanga_competition_schedule_items where schedule_revision_id = regenerated_revision_id
    ) sides group by entry_id
  ) home_balance on home_balance.entry_id = items.home_entry_id and home_balance.balance = 1
  join (
    select entry_id, sum(side) as balance from (
      select home_entry_id as entry_id, 1 as side from public.pachanga_competition_schedule_items where schedule_revision_id = regenerated_revision_id
      union all
      select away_entry_id, -1 from public.pachanga_competition_schedule_items where schedule_revision_id = regenerated_revision_id
    ) sides group by entry_id
  ) away_balance on away_balance.entry_id = items.away_entry_id and away_balance.balance = -1
  where items.schedule_revision_id = regenerated_revision_id
  order by items.pairing_key limit 1;
  perform pg_temp.assert_true(item_a is not null, 'No balanced home-away swap candidate found');
  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000008', plan_id, 7,
    'schedule_item.swap_home_away', jsonb_build_object('itemId', item_a)
  );
  perform pg_temp.assert_true(response #>> '{snapshot,revision,kind}' = 'home_away_swap', 'Home-away swap did not create a revision');

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000009', plan_id, 8,
    'schedule.validate', '{"reason":"Full R4B validation"}'::jsonb
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,validation,status}' = 'VALID'
      and (response #>> '{snapshot,validation,hardViolations}')::integer = 0
      and response #>> '{snapshot,plan,status}' = 'validated',
    'Schedule did not reach fully validated state'
  );

  perform pg_temp.actor('e4010000-0000-4000-8000-000000000005');
  perform pg_temp.expect_failure(
    format('select public.get_pachanga_league_schedule_workbench_v1(%L::uuid,0,200)', plan_id),
    'MANAGER_REQUIRED|FORBIDDEN'
  );

  response := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000010', plan_id, 9,
    'schedule.publish', '{"reason":"Publish canonical R4B fixtures"}'::jsonb
  );
  perform pg_temp.assert_true(
    (response #>> '{snapshot,publication,canonicalMatchCount}')::integer = 15
      and (response #>> '{snapshot,publication,contextCount}')::integer = 15
      and (response #>> '{snapshot,publication,notificationCount}')::integer = 6
      and response #>> '{snapshot,plan,status}' = 'published',
    'Atomic publication did not create the expected canonical fixtures and summaries'
  );
  replay := pg_temp.command(
    'e4010000-0000-4000-8000-000000000003',
    'e4200000-0000-4000-8000-000000000010', plan_id, 9,
    'schedule.publish', '{"reason":"Publish canonical R4B fixtures"}'::jsonb
  );
  perform pg_temp.assert_true(
    replay = response
      and (select count(*) from public.pachanga_canonical_match_bindings bindings where bindings.source_kind = 'competition_generated') = 15
      and (select count(*) from public.pachanga_competition_match_contexts contexts where contexts.source_kind = 'COMPETITION_GENERATED') = 15,
    'Publication replay duplicated canonical authorities'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_items items
    left join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id
    where items.schedule_revision_id = (response #>> '{snapshot,revision,id}')::uuid
      and (items.status <> 'published' or contexts.canonical_match_id <> items.canonical_match_id
        or contexts.round_id <> items.round_id or contexts.home_entry_id <> items.home_entry_id
        or contexts.away_entry_id <> items.away_entry_id or contexts.rule_revision_id <> 'e4060000-0000-4000-8000-000000000001')
  ), 'Schedule item and CompetitionMatchContext diverged');
  perform pg_temp.assert_true((
    select count(*) = count(distinct notifications.recipient_user_id)
    from public.pachanga_user_notifications notifications
    where notifications.kind = 'match_competition_schedule_published'
  ), 'Publication generated a notification storm');

  select plans.revision into current_revision from public.pachanga_competition_schedule_plans plans where plans.id = plan_id;
  perform pg_temp.actor('e4010000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure(
    format($sql$select public.command_pachanga_league_scheduling_v1(
      'e4200000-0000-4000-8000-000000000011', %L::uuid, %s,
      'schedule.regenerate', '{"seed":"forbidden-after-publish"}'::jsonb, '{}'::jsonb
    )$sql$, plan_id, current_revision),
    'POST_PUBLICATION_CHANGE_REQUIRES_R4C'
  );
end;
$body$;

-- Read models and grants are exercised under the Data API roles.
set local role authenticated;
select pg_temp.actor('e4010000-0000-4000-8000-000000000003');
select pg_temp.assert_true(
  (public.get_pachanga_league_schedule_workbench_v1(
    (select id from public.pachanga_competition_schedule_plans where status = 'published' limit 1), 0, 200
  ) #>> '{plan,status}') = 'published',
  'Schedule manager cannot read the canonical workbench'
);
select pg_temp.expect_failure(
  $$insert into public.pachanga_competition_schedule_slots(
    competition_id, edition_id, stage_id, starts_at, ends_at, timezone, created_by
  ) values (
    'e4040000-0000-4000-8000-000000000001', 'e4070000-0000-4000-8000-000000000001',
    'e4080000-0000-4000-8000-000000000001', clock_timestamp(), clock_timestamp() + interval '2 hours',
    'Europe/Madrid', 'e4010000-0000-4000-8000-000000000003'
  )$$,
  'permission denied'
);
select pg_temp.expect_failure(
  $$select public.archive_pachanga_league_schedule_qa_v1(
    'e4200000-0000-4000-8000-000000000090',
    (select id from public.pachanga_competition_schedule_plans where status = 'published' limit 1),
    (select revision from public.pachanga_competition_schedule_plans where status = 'published' limit 1),
    'R4B_STAGING_QA_ARCHIVE: unauthorized client attempt',
    '{}'::jsonb
  )$$,
  'permission denied'
);
select pg_temp.actor(md5('r4b-owner-1')::uuid);
select pg_temp.assert_true(
  jsonb_array_length(public.get_pachanga_my_league_schedule_v1(md5('r4b-entry-1')::uuid) -> 'fixtures') = 5,
  'Team owner cannot read its five published fixtures'
);
select pg_temp.actor('e4010000-0000-4000-8000-000000000005');
select pg_temp.expect_failure(
  $$select public.get_pachanga_my_league_schedule_v1(md5('r4b-entry-1')::uuid)$$,
  'FORBIDDEN'
);
reset role;

set local role anon;
select pg_temp.actor(null, 'anon');
select pg_temp.assert_true(
  jsonb_array_length(public.get_pachanga_public_league_calendar_v1(
    'e4040000-0000-4000-8000-000000000001', 1, 50
  ) -> 'rounds') = 5,
  'Public calendar did not expose five published rounds'
);
select pg_temp.expect_failure(
  $$select public.command_pachanga_league_scheduling_v1(
    'e4200000-0000-4000-8000-000000000012',
    'e4080000-0000-4000-8000-000000000001', 1,
    'schedule_plan.create', '{}'::jsonb, '{}'::jsonb
  )$$,
  'permission denied|AUTHENTICATION_REQUIRED'
);
reset role;

set local role service_role;
select pg_temp.actor(null, 'service_role');
do $body$
declare
  plan_id uuid := (select id from public.pachanga_competition_schedule_plans where status = 'published' limit 1);
  plan_revision bigint := (select revision from public.pachanga_competition_schedule_plans where id = plan_id);
  archived jsonb;
  replay jsonb;
begin
  archived := public.archive_pachanga_league_schedule_qa_v1(
    'e4200000-0000-4000-8000-000000000091', plan_id, plan_revision,
    'R4B_STAGING_QA_ARCHIVE: local database regression',
    '{"clientVersion":"4.0.0+r4b-db","installedMode":"browser","surface":"r4b_db_cleanup"}'::jsonb
  );
  replay := public.archive_pachanga_league_schedule_qa_v1(
    'e4200000-0000-4000-8000-000000000091', plan_id, plan_revision,
    'R4B_STAGING_QA_ARCHIVE: local database regression',
    '{"clientVersion":"4.0.0+r4b-db","installedMode":"browser","surface":"r4b_db_cleanup"}'::jsonb
  );
  perform pg_temp.assert_true(archived = replay, 'QA archive replay changed its confirmed response');
  perform pg_temp.assert_true(
    archived #>> '{snapshot,status}' = 'cancelled'
      and (archived #>> '{snapshot,retiredContexts}')::integer = 15
      and (archived #>> '{snapshot,retiredBindings}')::integer = 15
      and (archived #>> '{snapshot,retiredCanonicalMatches}')::integer = 15
      and (archived #>> '{snapshot,cancelledRounds}')::integer = 5,
    'QA archive did not retire the complete published graph'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_plans plans
    where plans.id = plan_id and plans.status <> 'cancelled'
  ), 'QA schedule plan remained active');
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_revisions revisions
    where revisions.schedule_plan_id = plan_id
      and revisions.status not in ('cancelled', 'superseded')
  ), 'QA schedule revision remained active');
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_schedule_slots slots
    where slots.competition_id = 'e4040000-0000-4000-8000-000000000001'
      and slots.status <> 'retired'
  ), 'QA schedule slot remained active');
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_rounds rounds
    where rounds.schedule_revision_id = (select current_revision_id from public.pachanga_competition_schedule_plans where id = plan_id)
      and rounds.status <> 'cancelled'
  ), 'QA round remained active');
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001'
      and contexts.source_kind = 'COMPETITION_GENERATED'
      and contexts.status <> 'retired'
  ), 'QA CompetitionMatchContext remained active');
end;
$body$;
reset role;

set local role authenticated;
select pg_temp.actor('e4010000-0000-4000-8000-000000000003');
select pg_temp.assert_true(
  (public.get_pachanga_league_schedule_workbench_v1(
    (select id from public.pachanga_competition_schedule_plans
      where status = 'cancelled' and published_at is not null
      order by server_sequence desc, id desc limit 1),
    0, 200
  ) #>> '{inputStatus}') = 'ARCHIVED_SNAPSHOT',
  'Archived workbench tried to recalculate generation inputs'
);
reset role;

select pg_temp.assert_true(not exists (
  select 1 from r4b_invariants_before before
  where before.digest <> pg_temp.table_digest(before.table_name::regclass)
), 'R4B modified Rating, match data, rewards, conduct, billing or ranking');

select pg_temp.assert_true(
  to_regclass('public.pachanga_league_matches') is null
    and to_regclass('public.pachanga_league_results') is null
    and to_regclass('public.pachanga_competition_standings') is null,
  'R4B introduced a parallel sports authority or standings'
);
