\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '240s';

begin;

\ir tournament-foundation-draw-v1-fixture.sql

create temporary table r6b_test_state(
  key text primary key,
  value jsonb not null
);

create or replace function pg_temp.r6b_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception 'R6B_ASSERTION_FAILED: %', message;
  end if;
end;
$$;

-- The shared R6A fixture deliberately stops before validation/publication.
-- Reproduce a real authoring revision after participant acceptance, then
-- rebuild the frozen draw through R6A commands. Entries intentionally keep
-- their acceptance-time RuleRevision until R6B prepares the published stage.
insert into r6b_test_state values (
  'acceptance_rule',
  jsonb_build_object('id', (
    select editions.rule_revision_id
    from public.pachanga_competition_editions editions
    join public.pachanga_competitions competitions
      on competitions.id = editions.competition_id
    where competitions.slug = 'r6a-concurrency-fixture'
  ))
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000101',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'tournament.authoring.save',
  '{"participantCap":16,"groupCount":4,"qualifiersPerGroup":2,"drawTarget":"GROUPS_THEN_KNOCKOUT","drawMode":"HYBRID","modality":"FUTBOL_7","reason":"R6B stale acceptance RuleRevision regression"}',
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000102',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'participants.unfreeze',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'reason', 'R6B rebuild after authoring revision'
  ),
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000103',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'participants.freeze',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'reason', 'R6B freeze current authoring revision'
  ),
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000104',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'draw.generate',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'seedMode', 'CUSTOM_PUBLIC_SEED',
    'publicSeed', 'R6A-CONCURRENCY-FIXTURE',
    'reason', 'R6B regenerate after authoring revision'
  ),
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000001',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'draw.validate',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'reason', 'R6B fixture draw validation'
  ),
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

select public.command_pachanga_tournament_draw_v1(
  '64030000-0000-4000-8000-000000000002',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'draw.publish',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'reason', 'R6B fixture draw publication'
  ),
  '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
);

-- R4A/R4B/R4C are already active in production. These local fixture switches
-- reproduce that prerequisite without changing any product migration default.
update private.pachanga_competition_foundation_settings settings set
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '63010000-0000-4000-8000-000000000090',
  updated_at = clock_timestamp()
where settings.singleton;

-- R6B flags may only be activated through the audited platform RPC.
select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000090","role":"authenticated"}',
  false
);

insert into r6b_test_state values (
  'flags',
  public.command_pachanga_tournament_group_stage_platform_v1(
    '64030000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-00000000c6b1',
    (select revision from private.pachanga_competition_foundation_settings where singleton),
    'tournament.group_stage.flags.set',
    '{"groupStageEnabled":true,"groupSchedulingEnabled":true,"groupMatchGenerationEnabled":true,"groupTrackingEnabled":true,"groupStandingsEnabled":true,"qualificationEnabled":true,"bracketTemplateEnabled":true,"reason":"R6B local full-story test"}',
    '{"clientVersion":"6.1.0+r6b-test","serviceWorkerVersion":"r6b-test","installedMode":"browser","surface":"sql"}'
  )
);

select pg_temp.r6b_assert(
  (select tournament_group_stage_enabled
      and tournament_group_scheduling_enabled
      and tournament_group_match_generation_enabled
      and tournament_match_generation_enabled
      and tournament_group_tracking_enabled
      and tournament_group_standings_enabled
      and tournament_qualification_enabled
      and tournament_bracket_template_enabled
      and not tournament_knockout_match_generation_enabled
      and not tournament_bracket_progression_enabled
      and not tournament_public_discovery_enabled
    from private.pachanga_competition_foundation_settings where singleton),
  'R6B flags must activate narrowly while R6C and discovery remain off'
);

-- R6B preparation refuses entries without an approved/locked R4A roster.
do $$
declare entry_row record;
declare roster_id uuid;
declare roster_revision_id uuid;
begin
  for entry_row in
    select entries.id, entries.category_id, plans.rule_revision_id, entries.created_by
    from public.pachanga_competition_entries entries
    join public.pachanga_competitions competitions on competitions.id = entries.competition_id
    join public.pachanga_competition_draw_plans plans on plans.competition_id = competitions.id
    where competitions.slug = 'r6a-concurrency-fixture'
      and entries.status = 'accepted'
    order by entries.team_id
  loop
    roster_id := gen_random_uuid();
    roster_revision_id := gen_random_uuid();
    insert into public.pachanga_competition_rosters(
      id, entry_id, category_id, rule_revision_id, status, revision, created_by
    ) values (
      roster_id, entry_row.id, entry_row.category_id, entry_row.rule_revision_id,
      'locked', 1, entry_row.created_by
    );
    insert into public.pachanga_competition_roster_revisions(
      id, roster_id, revision_number, roster_status, rule_revision_id,
      member_count, eligibility_summary, member_set_checksum, reason, created_by
    ) values (
      roster_revision_id, roster_id, 1, 'locked', entry_row.rule_revision_id,
      7, '{"eligible":7,"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}',
      encode(extensions.digest(convert_to(roster_id::text, 'UTF8'), 'sha256'), 'hex'),
      'R6B canonical test roster', entry_row.created_by
    );
    update public.pachanga_competition_rosters rosters
    set current_revision_id = roster_revision_id
    where rosters.id = roster_id;
  end loop;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

select pg_temp.r6b_assert(
  (select count(*) = 16
    from public.pachanga_competition_entries entries
    join public.pachanga_competitions competitions on competitions.id = entries.competition_id
    join public.pachanga_competition_draw_plans plans on plans.competition_id = competitions.id
    where competitions.slug = 'r6a-concurrency-fixture'
      and entries.status = 'accepted'
      and entries.rule_revision_id = (select (value ->> 'id')::uuid from r6b_test_state where key='acceptance_rule')
      and entries.rule_revision_id is distinct from plans.rule_revision_id),
  'accepted entries must retain a non-null pre-publication RuleRevision before prepare'
);

insert into r6b_test_state values (
  'prepare_expected',
  jsonb_build_object(
    'revision', (select tournament_revision from public.pachanga_competitions
      where slug='r6a-concurrency-fixture')
  )
);

insert into r6b_test_state values (
  'prepare',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000004',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='prepare_expected'),
    'group_stage.prepare', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='prepare') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000004',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='prepare_expected'),
    'group_stage.prepare', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'group-stage prepare replay must return the byte-equivalent receipt'
);

select pg_temp.r6b_assert(
  (select count(*) = 1 from public.pachanga_tournament_group_stage_states),
  'prepare must create exactly one group-stage aggregate'
);
select pg_temp.r6b_assert(
  (select count(*) = 4 from public.pachanga_tournament_group_schedule_plans),
  'prepare must create one canonical R4B schedule plan per group'
);
select pg_temp.r6b_assert(
  not exists (
    select 1
    from public.pachanga_tournament_group_stage_states states
    join public.pachanga_competition_participant_freezes freezes
      on freezes.id = states.participant_freeze_id
    join public.pachanga_competition_entries entries
      on entries.id = any(freezes.entry_ids)
    where entries.rule_revision_id is distinct from states.rule_revision_id
  ),
  'prepare must promote frozen accepted entries to the published sporting rule'
);
select pg_temp.r6b_assert(
  (select count(*) = 0 from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'prepare must not create matches'
);

-- Six globally compatible slots per four-team group.
do $$
declare group_row record;
declare slots_value jsonb;
begin
  for group_row in
    select groups.id, groups.group_order
    from public.pachanga_competition_groups groups
    join public.pachanga_competition_stages stages on stages.id=groups.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture'
    order by groups.group_order
  loop
    select jsonb_agg(jsonb_build_object(
      'startsAt', date_trunc('day', statement_timestamp()) + interval '30 days'
        + make_interval(days => slot_number),
      'endsAt', date_trunc('day', statement_timestamp()) + interval '30 days'
        + make_interval(days => slot_number, mins => 90),
      'timezone', 'Europe/Madrid',
      'venueLabel', 'R6B Group ' || group_row.group_order || ' Field'
    ) order by slot_number)
    into slots_value
    from generate_series(1, 6) slot_number;
    perform public.command_pachanga_tournament_group_stage_v1(
      gen_random_uuid(),
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
      (select revision from public.pachanga_tournament_group_stage_states),
      'group_schedule.create',
      jsonb_build_object('groupId', group_row.id, 'slots', slots_value),
      '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
    );
  end loop;
end;
$$;

insert into r6b_test_state values (
  'generate_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_group_stage_states))
);
insert into r6b_test_state values (
  'generate',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000010',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='generate_expected'),
    'group_schedule.generate', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='generate') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000010',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='generate_expected'),
    'group_schedule.generate', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'group schedule generation replay must return the byte-equivalent receipt'
);

insert into r6b_test_state values (
  'validate',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000011',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select revision from public.pachanga_tournament_group_stage_states),
    'group_schedule.validate', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

insert into r6b_test_state values (
  'publish_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_group_stage_states))
);
insert into r6b_test_state values (
  'publish',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000012',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='publish_expected'),
    'group_schedule.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);
insert into r6b_test_state values (
  'publish_notification_count',
  jsonb_build_object('count', (select count(*) from public.pachanga_user_notifications))
);

select pg_temp.r6b_assert(
  (select count(*) = 24 from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_schedule_plans plans on plans.current_revision_id=items.schedule_revision_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='r6a-concurrency-fixture' and items.status='published'),
  'four groups of four teams must publish 24 fixtures'
);
select pg_temp.r6b_assert(
  (select count(*) = 24 and count(distinct contexts.canonical_match_id)=24
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'publication must create exactly one MatchContext and CanonicalMatch per fixture'
);
select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='publish') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000012',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='publish_expected'),
    'group_schedule.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'schedule publish replay must return the byte-equivalent receipt'
);
select pg_temp.r6b_assert(
  (select count(*) from public.pachanga_user_notifications) =
    (select (value ->> 'count')::bigint from r6b_test_state where key='publish_notification_count'),
  'schedule publish replay must not duplicate notifications'
);

insert into r6b_test_state values (
  'activate',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000013',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select revision from public.pachanga_tournament_group_stage_states),
    'group_stage.activate', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

-- Runtime regression for R6B-TEST-003: the organizer only belongs to Team 1,
-- but can read the public shield projection of every participating team.
select pg_temp.r6b_assert(
  jsonb_array_length(public.get_pachanga_tournament_group_hub_v1(
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture')
  ) -> 'groups') = 4,
  'Tournament Hub must execute for an organizer who is not member of all teams'
);
select pg_temp.r6b_assert(
  (select bool_and(
      (group_item -> 'schedule' ->> 'status') = 'published'
      and (group_item -> 'schedule' ->> 'slotCount')::integer = 6
      and (group_item -> 'schedule' ->> 'fixtureCount')::integer = 6
    )
    from jsonb_array_elements(public.get_pachanga_tournament_group_hub_v1(
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture')
    ) -> 'groups') groups(group_item)),
  'Tournament Hub must expose canonical per-group schedule readiness'
);

-- R6B-PRODUCT-018 / R6B-SIMULATION-019: TeamJourney is one canonical,
-- participant-safe projection. Its stable match contract includes the R4C,
-- R4D, R5 and Referee Assignment context without leaking private evidence,
-- internal actors or fee data.
select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

with hub as (
  select public.get_pachanga_tournament_group_hub_v1(
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture')
  ) snapshot
), journey_matches as (
  select match_item
  from hub
  cross join lateral jsonb_array_elements(snapshot -> 'teamJourneys') journeys(journey)
  cross join lateral jsonb_array_elements(journey -> 'nextMatches') matches(match_item)
)
select pg_temp.r6b_assert(
  (select count(*) > 0
      and bool_and(match_item ?& array[
        'contextId', 'canonicalMatchId', 'attendance', 'squad', 'sanctions',
        'referee', 'incidents'
      ])
      and bool_and((match_item -> 'attendance') ?& array[
        'going', 'doubt', 'notGoing', 'playing', 'reserve', 'closed',
        'revision', 'serverSequence'
      ])
      and bool_and(not (lower(match_item::text) ~
        '(evidence|reportedby|createdby|decision_reason_private|fee)'))
    from journey_matches),
  'TeamJourney must expose canonical operations context without private data'
);

-- Build a real R4C result lifecycle for every canonical group match. The test
-- fixture enters at the already-played boundary; result proposal, bilateral
-- acceptance, official decision and StandingSnapshot are all real R4C paths.
insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
) values (
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  '63010000-0000-4000-8000-000000000001',
  'competition_director', 'active',
  '63010000-0000-4000-8000-000000000001'
) on conflict do nothing;

do $$
declare match_row record;
declare score_home integer;
declare score_away integer;
declare processed_matches integer := 0;
declare result_operation_id uuid;
declare result_expected_revision bigint;
declare result_payload jsonb;
declare result_response jsonb;
begin
  for match_row in
    select contexts.id, contexts.canonical_match_id, contexts.competition_group_id,
      contexts.home_entry_id, contexts.away_entry_id,
      home_teams.owner_id as home_owner_id,
      away_teams.owner_id as away_owner_id,
      substring(home_teams.team_code from 3)::integer as home_number,
      substring(away_teams.team_code from 3)::integer as away_number
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_entries home_entries on home_entries.id=contexts.home_entry_id
    join public.pachanga_groups home_teams on home_teams.id=home_entries.team_id
    join public.pachanga_competition_entries away_entries on away_entries.id=contexts.away_entry_id
    join public.pachanga_groups away_teams on away_teams.id=away_entries.team_id
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'
    order by contexts.server_sequence, contexts.id
  loop
    score_home := case when match_row.home_number < match_row.away_number then 2 else 0 end;
    score_away := case when match_row.away_number < match_row.home_number then 2 else 0 end;
    update public.pachanga_competition_match_contexts contexts set
      status='played', revision=contexts.revision+1,
      server_sequence=nextval('private.pachanga_competition_sequence'),
      updated_at=clock_timestamp()
    where contexts.id=match_row.id;
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id, created_by
    ) values (
      match_row.canonical_match_id, match_row.id,
      '63010000-0000-4000-8000-000000000001'
    );
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', match_row.home_owner_id, 'role', 'authenticated'
    )::text, true);
    perform public.command_pachanga_league_match_operations_v1(
      gen_random_uuid(), match_row.id,
      (select revision from public.pachanga_competition_match_contexts where id=match_row.id),
      'sporting_result.submit', jsonb_build_object(
        'entryId', match_row.home_entry_id,
        'scoreHome', score_home, 'scoreAway', score_away
      ), '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
    );
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', match_row.away_owner_id, 'role', 'authenticated'
    )::text, true);
    perform public.command_pachanga_league_match_operations_v1(
      gen_random_uuid(), match_row.id,
      (select revision from public.pachanga_competition_match_contexts where id=match_row.id),
      'sporting_result.accept', jsonb_build_object('entryId', match_row.away_entry_id),
      '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
    );
    perform set_config(
      'request.jwt.claims',
      '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
      true
    );
    result_operation_id := case when processed_matches = 0
      then '64030000-0000-4000-8000-000000000019'::uuid
      else gen_random_uuid() end;
    select revision into result_expected_revision
    from public.pachanga_competition_match_contexts where id=match_row.id;
    result_payload := jsonb_build_object(
      'outcome', 'MIRROR_SPORTING_RESULT',
      'reasonCode', 'r6b.test.official',
      'publicExplanation', 'Resultado bilateral confirmado.'
    );
    result_response := public.command_pachanga_league_match_operations_v1(
      result_operation_id, match_row.id, result_expected_revision,
      'official_result.publish', result_payload,
      '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
    );
    if processed_matches = 0 then
      insert into r6b_test_state values (
        'official_result',
        jsonb_build_object(
          'operationId', result_operation_id,
          'contextId', match_row.id,
          'expectedRevision', result_expected_revision,
          'payload', result_payload,
          'response', result_response
        )
      );
    end if;
    processed_matches := processed_matches + 1;
    if processed_matches = 1 then
      perform pg_temp.r6b_assert(
        (select count(*) = 4
          and count(distinct rows.position) < 4
          from public.pachanga_competition_standing_states states
          join public.pachanga_competition_standing_rows rows
            on rows.standing_snapshot_id = states.current_snapshot_id
          where states.stage_id = (
              select stage_id from public.pachanga_competition_match_contexts
              where id = match_row.id
            )
            and states.competition_group_id = match_row.competition_group_id
            and states.health_status = 'CURRENT'),
        'a partial group must persist provisional standings with shared positions'
      );
      perform pg_temp.r6b_assert(
        (select count(*) > 0
          from public.pachanga_competition_standing_states states
          join public.pachanga_competition_tie_break_explanations explanations
            on explanations.standing_snapshot_id = states.current_snapshot_id
          where states.stage_id = (
              select stage_id from public.pachanga_competition_match_contexts
              where id = match_row.id
            )
            and states.competition_group_id = match_row.competition_group_id
            and explanations.resolved = false),
        'a partial group must expose unresolved provisional tie evidence'
      );
    end if;
  end loop;
end;
$$;

insert into r6b_test_state values (
  'official_result_effect_counts',
  jsonb_build_object(
    'notifications', (select count(*) from public.pachanga_user_notifications),
    'decisions', (select count(*) from public.pachanga_competition_official_result_decisions)
  )
);
select pg_temp.r6b_assert(
  (select value -> 'response' from r6b_test_state where key='official_result') =
  public.command_pachanga_league_match_operations_v1(
    (select (value ->> 'operationId')::uuid from r6b_test_state where key='official_result'),
    (select (value ->> 'contextId')::uuid from r6b_test_state where key='official_result'),
    (select (value ->> 'expectedRevision')::bigint from r6b_test_state where key='official_result'),
    'official_result.publish',
    (select value -> 'payload' from r6b_test_state where key='official_result'),
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'official result replay must return the byte-equivalent R4C receipt'
);
select pg_temp.r6b_assert(
  (select count(*) from public.pachanga_user_notifications) =
    (select (value ->> 'notifications')::bigint from r6b_test_state where key='official_result_effect_counts')
  and (select count(*) from public.pachanga_competition_official_result_decisions) =
    (select (value ->> 'decisions')::bigint from r6b_test_state where key='official_result_effect_counts'),
  'official result replay must not duplicate notifications or decisions'
);

select pg_temp.r6b_assert(
  (select count(*) = 24 from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture' and contexts.status='official'),
  'all 24 canonical group matches must reach official through R4C'
);
select pg_temp.r6b_assert(
  (select count(*) = 4 from public.pachanga_competition_standing_states states
    join public.pachanga_competition_stages stages on stages.id=states.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture'
      and states.health_status='CURRENT' and states.current_snapshot_id is not null),
  'R4C must own one current StandingSnapshot per group'
);
select pg_temp.r6b_assert(
  not exists (
    select 1
    from public.pachanga_competition_standing_states states
    join public.pachanga_competition_standing_rows rows
      on rows.standing_snapshot_id = states.current_snapshot_id
    join public.pachanga_competition_stages stages on stages.id=states.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture'
    group by states.id, rows.position
    having count(*) > 1
  ),
  'completed groups must not retain shared final positions'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

insert into r6b_test_state values (
  'qualification_rebuild_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_group_stage_states))
);
insert into r6b_test_state values (
  'qualification_rebuild',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000014',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='qualification_rebuild_expected'),
    'qualification.rebuild', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='qualification_rebuild') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000014',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='qualification_rebuild_expected'),
    'qualification.rebuild', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'qualification rebuild replay must return the byte-equivalent receipt'
);

-- Regression R6B-PRODUCT-001: all four healthy source snapshots survive the
-- health aggregation and remain ordered by canonical group order.
select pg_temp.r6b_assert(
  (select status='READY' and cardinality(source_standing_snapshot_ids)=4
    from public.pachanga_tournament_qualification_snapshots snapshots
    order by snapshots.server_sequence desc, snapshots.id desc limit 1),
  'qualification must retain every healthy source StandingSnapshot'
);
select pg_temp.r6b_assert(
  (select count(*)=8 from public.pachanga_tournament_qualification_rows rows
    join public.pachanga_tournament_qualification_snapshots snapshots
      on snapshots.id=rows.qualification_snapshot_id
    where snapshots.status='READY' and rows.outcome='DIRECT_QUALIFIER'),
  'TOP_N_PER_GROUP must select exactly eight direct qualifiers'
);
select pg_temp.r6b_assert(
  (select count(*)=8 from public.pachanga_tournament_qualification_rows rows
    join public.pachanga_tournament_qualification_snapshots snapshots
      on snapshots.id=rows.qualification_snapshot_id
    where snapshots.status='READY' and rows.outcome='ELIMINATED'
      and rows.target_bracket_slot is null),
  'qualification must retain all eight eliminated entries without target slots'
);
select pg_temp.r6b_assert(
  (select count(*)=16 and count(distinct rows.server_sequence)=16
    from public.pachanga_tournament_qualification_rows rows
    join public.pachanga_tournament_qualification_snapshots snapshots
      on snapshots.id=rows.qualification_snapshot_id
    where snapshots.status='READY'),
  'every READY QualificationRow must own a distinct server sequence'
);

insert into r6b_test_state values (
  'qualification_validate',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000015',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select revision from public.pachanga_tournament_group_stage_states),
    'qualification.validate', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

insert into r6b_test_state values (
  'qualification_publish_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_group_stage_states))
);
insert into r6b_test_state values (
  'qualification_publish',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000016',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='qualification_publish_expected'),
    'qualification.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);
insert into r6b_test_state values (
  'qualification_publish_notification_count',
  jsonb_build_object('count', (select count(*) from public.pachanga_user_notifications))
);
select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='qualification_publish') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000016',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='qualification_publish_expected'),
    'qualification.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'qualification publish replay must return the byte-equivalent receipt'
);
select pg_temp.r6b_assert(
  (select count(*) from public.pachanga_user_notifications) =
    (select (value ->> 'count')::bigint from r6b_test_state where key='qualification_publish_notification_count'),
  'qualification publish replay must not duplicate notifications'
);

select pg_temp.r6b_assert(
  (select count(*)=16 and count(distinct rows.server_sequence)=16
    from public.pachanga_tournament_qualification_rows rows
    join public.pachanga_tournament_qualification_snapshots snapshots
      on snapshots.id=rows.qualification_snapshot_id
    where snapshots.status='PUBLISHED'),
  'published QualificationRows must be complete and independently sequenced'
);

insert into r6b_test_state values (
  'bracket_create',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000017',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select revision from public.pachanga_tournament_group_stage_states),
    'bracket_template.create', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);

insert into r6b_test_state values (
  'bracket_publish_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_group_stage_states))
);
insert into r6b_test_state values (
  'bracket_publish',
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000018',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='bracket_publish_expected'),
    'bracket_template.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  )
);
insert into r6b_test_state values (
  'bracket_publish_notification_count',
  jsonb_build_object('count', (select count(*) from public.pachanga_user_notifications))
);
select pg_temp.r6b_assert(
  (select value from r6b_test_state where key='bracket_publish') =
  public.command_pachanga_tournament_group_stage_v1(
    '64030000-0000-4000-8000-000000000018',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6b_test_state where key='bracket_publish_expected'),
    'bracket_template.publish', '{}',
    '{"clientVersion":"6.1.0+r6b-test","surface":"sql"}'
  ),
  'bracket template publish replay must return the byte-equivalent receipt'
);
select pg_temp.r6b_assert(
  (select count(*) from public.pachanga_user_notifications) =
    (select (value ->> 'count')::bigint from r6b_test_state where key='bracket_publish_notification_count'),
  'bracket template publish replay must not duplicate notifications'
);

select pg_temp.r6b_assert(
  (select status='PUBLISHED' and bracket_size=8 and slot_count=8
    from public.pachanga_tournament_bracket_templates templates
    order by templates.server_sequence desc, templates.id desc limit 1),
  'published bracket template must freeze eight resolved source slots'
);
select pg_temp.r6b_assert(
  (select count(*)=8 and count(distinct slots.server_sequence)=8
    from public.pachanga_tournament_bracket_slots slots
    join public.pachanga_tournament_bracket_templates templates
      on templates.id=slots.bracket_template_id
    where templates.status='PUBLISHED'),
  'published BracketSlots must be complete and independently sequenced'
);
select pg_temp.r6b_assert(
  (select count(*)=24 from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'bracket publication must create zero knockout MatchContexts'
);
select pg_temp.r6b_assert(
  (select count(*)=24 from public.pachanga_canonical_matches matches
    join public.pachanga_competition_match_contexts contexts on contexts.canonical_match_id=matches.id
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'bracket publication must create zero knockout CanonicalMatches'
);
select pg_temp.r6b_assert(
  (select count(*) = 7 and count(distinct operation_id) = 7
    from private.pachanga_competition_operation_receipts receipts
    where receipts.operation_id = any(array[
      '64030000-0000-4000-8000-000000000004'::uuid,
      '64030000-0000-4000-8000-000000000010'::uuid,
      '64030000-0000-4000-8000-000000000012'::uuid,
      '64030000-0000-4000-8000-000000000014'::uuid,
      '64030000-0000-4000-8000-000000000016'::uuid,
      '64030000-0000-4000-8000-000000000018'::uuid,
      '64030000-0000-4000-8000-000000000019'::uuid
    ])),
  'critical R6B/R4C replays must retain exactly one durable receipt each'
);
select pg_temp.r6b_assert(
  (select count(*) = 7 and count(distinct operation_id) = 7
    from private.pachanga_competition_events events
    where events.operation_id = any(array[
      '64030000-0000-4000-8000-000000000004'::uuid,
      '64030000-0000-4000-8000-000000000010'::uuid,
      '64030000-0000-4000-8000-000000000012'::uuid,
      '64030000-0000-4000-8000-000000000014'::uuid,
      '64030000-0000-4000-8000-000000000016'::uuid,
      '64030000-0000-4000-8000-000000000018'::uuid,
      '64030000-0000-4000-8000-000000000019'::uuid
    ])),
  'critical R6B/R4C replays must retain exactly one audit event each'
);

-- Authenticated clients have no direct write path to R6B evidence.
set role authenticated;
do $$
begin
  begin
    insert into public.pachanga_tournament_qualification_snapshots(
      id, group_stage_state_id, competition_id, edition_id, stage_id,
      rule_revision_id, preparation_id, status, source_standings_revision,
      source_standing_snapshot_ids, policy_snapshot, health_snapshot,
      group_qualifiers, cross_group_qualifiers, eliminated_entries,
      target_bracket_slots, checksum, operation_id, generated_by
    ) values (
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
      gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'READY', 0,
      array[gen_random_uuid()], '{}', '{}', '[]', '[]', '[]', '[]', repeat('0',64),
      gen_random_uuid(), '63010000-0000-4000-8000-000000000001'
    );
    raise exception 'DIRECT_WRITE_UNEXPECTEDLY_SUCCEEDED';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- R6B-PRODUCT-002: the Tournament adapter must materialize the exact canonical
-- R5 policy key and checksum, without an alternate discipline engine.
select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);
select private.pachanga_competition_discipline_ensure_catalog_v1(
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select rule_revision_id from public.pachanga_tournament_group_stage_states),
  '63010000-0000-4000-8000-000000000001'
);
select pg_temp.r6b_assert(
  (select card_type_catalog = private.pachanga_competition_discipline_default_policy_v1() -> 'cardTypeCatalog'
      and cycle_policy = private.pachanga_competition_discipline_default_policy_v1() -> 'cyclePolicy'
      and sanction_policy = private.pachanga_competition_discipline_default_policy_v1() -> 'sanctionPolicy'
      and appeal_policy = private.pachanga_competition_discipline_default_policy_v1() -> 'appealPolicy'
      and public_reason_categories = private.pachanga_competition_discipline_default_policy_v1() -> 'publicReasonCategories'
      and checksum = encode(extensions.digest(convert_to(
        private.pachanga_competition_discipline_default_policy_v1()::text,
        'UTF8'
      ),'sha256'),'hex')
    from public.pachanga_competition_discipline_rule_catalogs catalogs
    where catalogs.competition_id=(select id from public.pachanga_competitions where slug='r6a-concurrency-fixture')),
  'Tournament discipline catalog must use the canonical R5 policy and checksum'
);

select 'R6B_DB_REPORT|' || jsonb_build_object(
  'groups', (select count(*) from public.pachanga_tournament_group_schedule_plans),
  'fixtures', (select fixture_count from public.pachanga_tournament_group_stage_states),
  'canonicalMatches', (select count(*) from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'standingSnapshots', (select count(*) from public.pachanga_competition_standing_snapshots snapshots
    join public.pachanga_competition_standing_states states on states.current_snapshot_id=snapshots.id
    join public.pachanga_competition_stages stages on stages.id=states.stage_id
    join public.pachanga_competition_editions editions on editions.id=stages.edition_id
    join public.pachanga_competitions competitions on competitions.id=editions.competition_id
    where competitions.slug='r6a-concurrency-fixture'),
  'qualificationStatus', (select status from public.pachanga_tournament_qualification_snapshots
    order by server_sequence desc, id desc limit 1),
  'bracketStatus', (select status from public.pachanga_tournament_bracket_templates
    order by server_sequence desc, id desc limit 1),
  'bracketSlots', (select count(*) from public.pachanga_tournament_bracket_slots slots
    join public.pachanga_tournament_bracket_templates templates on templates.id=slots.bracket_template_id
    where templates.status='PUBLISHED'),
  'knockoutMatches', 0,
  'directWrites', 0
)::text;

rollback;
