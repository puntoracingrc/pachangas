\set ON_ERROR_STOP on

set local lock_timeout = '5s';
set local statement_timeout = '240s';

create temporary table r6b_scale_cases(
  case_key text primary key,
  participant_count integer not null,
  group_count integer not null,
  fixture_count integer not null,
  date_offset integer not null
);

insert into r6b_scale_cases values
  ('pots16', 16, 4, 24, 0),
  ('manual32', 32, 8, 48, 40),
  ('optimized64', 64, 16, 96, 80);

create temporary table r6b_performance_samples(
  operation text not null,
  sample_number integer not null,
  duration_ms numeric not null,
  primary key (operation, sample_number)
);

create or replace function pg_temp.r6b_scale_actor(actor_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', actor_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.r6b_scale_sample_command(
  target_competition_id uuid,
  target_action text,
  target_payload jsonb,
  target_operation text,
  target_samples integer default 7
)
returns void
language plpgsql
as $$
declare sample_number integer;
declare started_at timestamptz;
declare elapsed_ms numeric;
begin
  if current_setting('pachangas.r6b_performance', true) <> 'on' then return; end if;
  for sample_number in 1..target_samples loop
    begin
      started_at := clock_timestamp();
      perform pg_temp.r6b_scale_command(
        target_competition_id, target_action, target_payload
      );
      elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
      raise exception 'R6B_PERFORMANCE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm <> 'R6B_PERFORMANCE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into r6b_performance_samples values (
      target_operation, sample_number, elapsed_ms
    );
  end loop;
end;
$$;

create or replace function pg_temp.r6b_scale_sample_reads(
  target_competition_id uuid,
  target_suffix text,
  target_samples integer default 7
)
returns void
language plpgsql
as $$
declare sample_number integer;
declare started_at timestamptz;
declare elapsed_ms numeric;
declare round_id_value uuid;
begin
  if current_setting('pachangas.r6b_performance', true) <> 'on' then return; end if;
  perform pg_temp.r6b_scale_actor(md5('r6a-engine-user-1')::uuid);
  select rounds.id into round_id_value
  from public.pachanga_competition_rounds rounds
  join public.pachanga_competition_schedule_revisions revisions
    on revisions.id = rounds.schedule_revision_id
  join public.pachanga_competition_schedule_plans plans
    on plans.id = revisions.schedule_plan_id
  where plans.competition_id = target_competition_id
  order by rounds.round_number, rounds.id
  limit 1;
  for sample_number in 1..target_samples loop
    started_at := clock_timestamp();
    perform public.get_pachanga_tournament_group_hub_v1(target_competition_id);
    elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
    insert into r6b_performance_samples values (
      'Tournament Hub ' || target_suffix, sample_number, elapsed_ms
    );

    started_at := clock_timestamp();
    perform public.get_pachanga_league_round_detail_v1(round_id_value);
    elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
    insert into r6b_performance_samples values (
      'Round Tracker ' || target_suffix, sample_number, elapsed_ms
    );
  end loop;
end;
$$;

create or replace function pg_temp.r6b_scale_command(
  target_competition_id uuid,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
as $$
declare owner_id constant uuid := md5('r6a-engine-user-1')::uuid;
declare expected_revision bigint;
begin
  perform pg_temp.r6b_scale_actor(owner_id);
  select coalesce(states.revision, competitions.tournament_revision)
  into expected_revision
  from public.pachanga_competitions competitions
  left join public.pachanga_tournament_group_stage_states states
    on states.competition_id = competitions.id
  where competitions.id = target_competition_id;
  return public.command_pachanga_tournament_group_stage_v1(
    gen_random_uuid(), target_competition_id, expected_revision,
    target_action, target_payload,
    '{"clientVersion":"6.1.0+r6b-scale","serviceWorkerVersion":"r6b-scale","installedMode":"browser","surface":"sql"}'
  );
end;
$$;

-- R4A/R4B/R4C are production prerequisites. Local scale enables them only in
-- this transaction; R6B itself is activated through the audited platform RPC.
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
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '62010000-0000-4000-8000-000000000090',
  updated_at = clock_timestamp()
where settings.singleton;

select pg_temp.r6b_scale_actor('62010000-0000-4000-8000-000000000090');
select public.command_pachanga_tournament_group_stage_platform_v1(
  gen_random_uuid(),
  '00000000-0000-0000-0000-00000000c6b1',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'tournament.group_stage.flags.set',
  '{"groupStageEnabled":true,"groupSchedulingEnabled":true,"groupMatchGenerationEnabled":true,"groupTrackingEnabled":true,"groupStandingsEnabled":true,"qualificationEnabled":true,"bracketTemplateEnabled":true,"reason":"R6B local scale matrix"}',
  '{"clientVersion":"6.1.0+r6b-scale","serviceWorkerVersion":"r6b-scale","installedMode":"browser","surface":"sql"}'
);

do $body$
declare scale_case r6b_scale_cases%rowtype;
declare engine_case r6a_engine_cases%rowtype;
declare current_plan public.pachanga_competition_draw_plans%rowtype;
declare entry_row record;
declare roster_id uuid;
declare roster_revision_id uuid;
declare group_row record;
declare slots_value jsonb;
begin
  for scale_case in select * from r6b_scale_cases order by participant_count
  loop
    select * into engine_case
    from r6a_engine_cases cases where cases.case_key = scale_case.case_key;

    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'tournament.authoring.save',
      jsonb_build_object(
        'participantCap', scale_case.participant_count,
        'groupCount', scale_case.group_count,
        'qualifiersPerGroup', 2,
        'drawTarget', 'GROUPS_THEN_KNOCKOUT',
        'drawMode', engine_case.mode,
        'modality', 'FUTBOL_7',
        'reason', 'R6B scale qualification contract'
      )
    );
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'participants.unfreeze',
      jsonb_build_object('planId', engine_case.plan_id, 'reason', 'R6B scale refresh')
    );
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'participants.freeze',
      jsonb_build_object('planId', engine_case.plan_id, 'reason', 'R6B scale freeze')
    );
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'draw.generate',
      jsonb_build_object(
        'planId', engine_case.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6B-SCALE-' || upper(scale_case.case_key),
        'reason', 'R6B scale draw generation'
      )
    );
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'draw.validate',
      jsonb_build_object('planId', engine_case.plan_id, 'reason', 'R6B scale draw validation')
    );
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      engine_case.competition_id,
      'draw.publish',
      jsonb_build_object('planId', engine_case.plan_id, 'reason', 'R6B scale draw publication')
    );

    select * into current_plan
    from public.pachanga_competition_draw_plans plans
    where plans.id = engine_case.plan_id;

    for entry_row in
      select entries.id, entries.category_id, entries.created_by
      from public.pachanga_competition_entries entries
      where entries.competition_id = engine_case.competition_id
        and entries.status = 'accepted'
      order by entries.id
    loop
      roster_id := gen_random_uuid();
      roster_revision_id := gen_random_uuid();
      insert into public.pachanga_competition_rosters(
        id, entry_id, category_id, rule_revision_id, status, revision, created_by
      ) values (
        roster_id, entry_row.id, entry_row.category_id,
        current_plan.rule_revision_id, 'locked', 1, entry_row.created_by
      );
      insert into public.pachanga_competition_roster_revisions(
        id, roster_id, revision_number, roster_status, rule_revision_id,
        member_count, eligibility_summary, member_set_checksum, reason, created_by
      ) values (
        roster_revision_id, roster_id, 1, 'locked', current_plan.rule_revision_id,
        0, '{"eligible":0,"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}',
        encode(extensions.digest(convert_to(roster_id::text, 'UTF8'), 'sha256'), 'hex'),
        'R6B scale locked roster', entry_row.created_by
      );
      update public.pachanga_competition_rosters rosters
      set current_revision_id = roster_revision_id
      where rosters.id = roster_id;
    end loop;

    perform pg_temp.r6b_scale_sample_command(
      engine_case.competition_id, 'group_stage.prepare', '{}'::jsonb,
      'stage prepare ' || scale_case.participant_count
    );
    perform pg_temp.r6b_scale_command(engine_case.competition_id, 'group_stage.prepare');

    for group_row in
      select groups.id, groups.group_order
      from public.pachanga_competition_groups groups
      join public.pachanga_competition_stages stages on stages.id = groups.stage_id
      join public.pachanga_competition_editions editions on editions.id = stages.edition_id
      where editions.competition_id = engine_case.competition_id
      order by groups.group_order, groups.id
    loop
      select jsonb_agg(jsonb_build_object(
        'startsAt', date_trunc('day', statement_timestamp()) + interval '30 days'
          + make_interval(days => scale_case.date_offset + slot_number),
        'endsAt', date_trunc('day', statement_timestamp()) + interval '30 days'
          + make_interval(days => scale_case.date_offset + slot_number, mins => 90),
        'timezone', 'Europe/Madrid',
        'venueLabel', 'R6B ' || scale_case.case_key || ' Group ' || group_row.group_order
      ) order by slot_number)
      into slots_value
      from generate_series(1, 6) slot_number;
      perform pg_temp.r6b_scale_command(
        engine_case.competition_id,
        'group_schedule.create',
        jsonb_build_object('groupId', group_row.id, 'slots', slots_value)
      );
    end loop;

    perform pg_temp.r6b_scale_sample_command(
      engine_case.competition_id, 'group_schedule.generate', '{}'::jsonb,
      'schedule generation ' || scale_case.participant_count
    );
    perform pg_temp.r6b_scale_command(engine_case.competition_id, 'group_schedule.generate');
    perform pg_temp.r6b_scale_sample_command(
      engine_case.competition_id, 'group_schedule.validate', '{}'::jsonb,
      'schedule validation ' || scale_case.participant_count
    );
    perform pg_temp.r6b_scale_command(engine_case.competition_id, 'group_schedule.validate');
    perform pg_temp.r6b_scale_sample_command(
      engine_case.competition_id, 'group_schedule.publish', '{}'::jsonb,
      'canonical match publication ' || scale_case.participant_count
    );
    perform pg_temp.r6b_scale_command(engine_case.competition_id, 'group_schedule.publish');
    perform pg_temp.r6b_scale_sample_reads(
      engine_case.competition_id, scale_case.participant_count::text
    );
  end loop;
end;
$body$;

select 'R6B_SCALE_MATRIX_REPORT|' || jsonb_build_object(
  'scenarios', (
    select jsonb_agg(jsonb_build_object(
      'teams', scale_cases.participant_count,
      'groups', scale_cases.group_count,
      'expectedFixtures', scale_cases.fixture_count,
      'schedulePlans', (
        select count(*)
        from public.pachanga_tournament_group_schedule_plans mappings
        join public.pachanga_tournament_group_stage_states states
          on states.id = mappings.group_stage_state_id
        where states.competition_id = engine_cases.competition_id
      ),
      'fixtures', (
        select count(*)
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_schedule_revisions revisions
          on revisions.id = items.schedule_revision_id
        join public.pachanga_competition_schedule_plans plans
          on plans.id = revisions.schedule_plan_id
        where plans.competition_id = engine_cases.competition_id
          and items.status = 'published'
      ),
      'canonicalMatches', (
        select count(*)
        from public.pachanga_competition_match_contexts contexts
        where contexts.competition_id = engine_cases.competition_id
      ),
      'matchContexts', (
        select count(distinct contexts.canonical_match_id)
        from public.pachanga_competition_match_contexts contexts
        where contexts.competition_id = engine_cases.competition_id
      )
    ) order by scale_cases.participant_count)
    from r6b_scale_cases scale_cases
    join r6a_engine_cases engine_cases using (case_key)
  ),
  'knockoutMatches', 0,
  'boundedStatementTimeoutMs', 240000
)::text;
