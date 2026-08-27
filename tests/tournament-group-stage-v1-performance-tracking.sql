\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '120s';

create temporary table r6b_tracking_performance_samples(
  operation text not null,
  sample_number integer not null,
  duration_ms numeric not null,
  primary key (operation, sample_number)
);

create or replace function pg_temp.r6b_tracking_actor()
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );
end;
$$;

create or replace function pg_temp.r6b_tracking_command(
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
as $$
declare competition_id_value uuid;
declare expected_revision bigint;
begin
  perform pg_temp.r6b_tracking_actor();
  select competitions.id, states.revision
  into competition_id_value, expected_revision
  from public.pachanga_competitions competitions
  join public.pachanga_tournament_group_stage_states states
    on states.competition_id = competitions.id
  where competitions.slug = 'r6a-concurrency-fixture';
  return public.command_pachanga_tournament_group_stage_v1(
    gen_random_uuid(), competition_id_value, expected_revision,
    target_action, target_payload,
    '{"clientVersion":"6.1.0+r6b-performance","serviceWorkerVersion":"r6b-performance","installedMode":"browser","surface":"sql"}'
  );
end;
$$;

create or replace function pg_temp.r6b_tracking_sample_command(
  target_action text,
  target_operation text,
  target_samples integer default 11
)
returns void
language plpgsql
as $$
declare sample_number integer;
declare started_at timestamptz;
declare elapsed_ms numeric;
begin
  for sample_number in 1..target_samples loop
    begin
      started_at := clock_timestamp();
      perform pg_temp.r6b_tracking_command(target_action);
      elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
      raise exception 'R6B_PERFORMANCE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm <> 'R6B_PERFORMANCE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into r6b_tracking_performance_samples values (
      target_operation, sample_number, elapsed_ms
    );
  end loop;
end;
$$;

create or replace function pg_temp.r6b_tracking_sample_reads(target_samples integer default 21)
returns void
language plpgsql
as $$
declare sample_number integer;
declare started_at timestamptz;
declare elapsed_ms numeric;
declare competition_id_value uuid;
declare group_id_value uuid;
declare round_id_value uuid;
begin
  perform pg_temp.r6b_tracking_actor();
  select competitions.id into competition_id_value
  from public.pachanga_competitions competitions
  where competitions.slug = 'r6a-concurrency-fixture';
  select groups.id into group_id_value
  from public.pachanga_competition_groups groups
  join public.pachanga_competition_stages stages on stages.id = groups.stage_id
  join public.pachanga_competition_editions editions on editions.id = stages.edition_id
  where editions.competition_id = competition_id_value
  order by groups.group_order, groups.id limit 1;
  select rounds.id into round_id_value
  from public.pachanga_competition_rounds rounds
  join public.pachanga_competition_schedule_revisions revisions
    on revisions.id = rounds.schedule_revision_id
  join public.pachanga_competition_schedule_plans plans
    on plans.id = revisions.schedule_plan_id
  where plans.competition_id = competition_id_value
  order by rounds.round_number, rounds.id limit 1;

  for sample_number in 1..target_samples loop
    started_at := clock_timestamp();
    perform public.get_pachanga_tournament_group_hub_v1(competition_id_value);
    elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
    insert into r6b_tracking_performance_samples values (
      'Tournament Hub populated', sample_number, elapsed_ms
    );

    started_at := clock_timestamp();
    perform public.get_pachanga_league_round_detail_v1(round_id_value);
    elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
    insert into r6b_tracking_performance_samples values (
      'Round Tracker populated', sample_number, elapsed_ms
    );

    started_at := clock_timestamp();
    perform public.get_pachanga_league_standings_v1(
      competition_id_value,
      (select stage_id from public.pachanga_tournament_group_stage_states
        where competition_id = competition_id_value),
      null,
      group_id_value
    );
    elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
    insert into r6b_tracking_performance_samples values (
      'Group Standings', sample_number, elapsed_ms
    );
  end loop;
end;
$$;

select pg_temp.r6b_tracking_sample_reads();
select pg_temp.r6b_tracking_sample_command(
  'qualification.rebuild', 'Qualification rebuild'
);
select pg_temp.r6b_tracking_command('qualification.rebuild');
select pg_temp.r6b_tracking_command('qualification.validate');
select pg_temp.r6b_tracking_sample_command(
  'qualification.publish', 'Qualification publish'
);

select 'R6B_PERFORMANCE_TRACKING_REPORT|' || jsonb_build_object(
  'samples', (select count(*) from r6b_tracking_performance_samples),
  'operations', (
    select jsonb_object_agg(operation, jsonb_build_object(
      'samples', sample_count,
      'p50Ms', round(p50_ms, 3),
      'p95Ms', round(p95_ms, 3),
      'maxMs', round(max_ms, 3)
    ) order by operation)
    from (
      select operation, count(*)::integer as sample_count,
        percentile_cont(0.50) within group (order by duration_ms)::numeric as p50_ms,
        percentile_cont(0.95) within group (order by duration_ms)::numeric as p95_ms,
        max(duration_ms) as max_ms
      from r6b_tracking_performance_samples
      group by operation
    ) metrics
  )
)::text;
