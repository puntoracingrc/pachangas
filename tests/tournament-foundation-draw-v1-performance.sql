\set ON_ERROR_STOP on

set local lock_timeout = '5s';
set local statement_timeout = '180s';

create temporary table r6a_performance_samples(
  operation text not null,
  sample integer not null,
  duration_ms numeric not null,
  primary key(operation, sample)
);

select pg_temp.r6a_create_case('perf_pure8', 8, 2, 'PURE_RANDOM');
select pg_temp.r6a_generate('perf_pure8', 'R6A-PERF-PURE-8');

select pg_temp.r6a_create_case('perf_optimized32', 32, 8, 'CONSTRAINT_OPTIMIZED');
select pg_temp.r6a_command(
  md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='perf_optimized32'),
  'draw_constraint.create',
  jsonb_build_object(
    'planId', (select plan_id from r6a_engine_cases where case_key='perf_optimized32'),
    'constraintType', 'TEAM_LEVEL_BALANCE',
    'strength', 'SOFT',
    'weight', 2,
    'scope', 'DRAW',
    'parameters', jsonb_build_object('maxGap', 6),
    'reason', 'R6A performance balance',
    'publicAttribution', true
  )
);
select pg_temp.r6a_generate('perf_optimized32', 'R6A-PERF-OPTIMIZED-32');

do $$
declare
  sample_number integer;
  started_at timestamptz;
  case_row r6a_engine_cases%rowtype;
  first_entry uuid;
  second_entry uuid;
begin
  for sample_number in 1..20 loop
    select * into case_row from r6a_engine_cases where case_key='perf_pure8';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.regenerate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6A-PERF-PURE-8',
        'reason', 'R6A performance sample'
      )
    );
    insert into r6a_performance_samples values (
      '8 teams pure random', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='pots16';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.regenerate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6A-PERF-POTS-16',
        'reason', 'R6A performance sample'
      )
    );
    insert into r6a_performance_samples values (
      '16 teams seeded pots', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='perf_optimized32';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.regenerate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6A-PERF-OPTIMIZED-32',
        'reason', 'R6A performance sample'
      )
    );
    insert into r6a_performance_samples values (
      '32 teams constraint optimized', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='optimized64';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.regenerate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6A-PERF-OPTIMIZED-64',
        'reason', 'R6A performance sample'
      )
    );
    insert into r6a_performance_samples values (
      '64 teams engine capacity', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='manual32';
    first_entry := case_row.entry_ids[1];
    second_entry := case_row.entry_ids[2];
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.entry.swap',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'entryId', first_entry,
        'otherEntryId', second_entry,
        'reason', 'R6A performance manual swap'
      )
    );
    insert into r6a_performance_samples values (
      'manual swap', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='hybrid24';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.regenerate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'seedMode', 'CUSTOM_PUBLIC_SEED',
        'publicSeed', 'R6A-PERF-HYBRID-24',
        'reason', 'R6A performance hybrid fill'
      )
    );
    insert into r6a_performance_samples values (
      'hybrid complete', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    select * into case_row from r6a_engine_cases where case_key='manual32';
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.validate',
      jsonb_build_object(
        'planId', case_row.plan_id,
        'reason', 'R6A performance validation'
      )
    );
    insert into r6a_performance_samples values (
      'validate', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );
  end loop;
end;
$$;

do $$
declare
  sample_number integer;
  target_case_key text;
  case_row r6a_engine_cases%rowtype;
  started_at timestamptz;
begin
  for sample_number in 1..20 loop
    target_case_key := 'perf_publish_' || sample_number;
    perform pg_temp.r6a_create_case(target_case_key, 4, 2, 'PURE_RANDOM');
    perform pg_temp.r6a_generate(target_case_key, 'R6A-PERF-PUBLISH-' || sample_number);
    select * into case_row from r6a_engine_cases
    where r6a_engine_cases.case_key=target_case_key;
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.validate',
      jsonb_build_object('planId', case_row.plan_id, 'reason', 'R6A prepare publish sample')
    );
    started_at := clock_timestamp();
    perform pg_temp.r6a_command(
      md5('r6a-engine-user-1')::uuid,
      case_row.competition_id,
      'draw.publish',
      jsonb_build_object('planId', case_row.plan_id, 'reason', 'R6A performance publish')
    );
    insert into r6a_performance_samples values (
      'publish', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );
  end loop;
end;
$$;

do $$
declare
  sample_number integer;
  case_row r6a_engine_cases%rowtype := (
    select cases from r6a_engine_cases cases where case_key='perf_publish_1'
  );
  started_at timestamptz;
  sink jsonb;
begin
  perform pg_temp.r6a_actor(md5('r6a-engine-user-1')::uuid);
  for sample_number in 1..50 loop
    started_at := clock_timestamp();
    sink := public.get_pachanga_tournament_snapshot_v1(case_row.competition_id);
    insert into r6a_performance_samples values (
      'organizer desk', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );

    started_at := clock_timestamp();
    sink := public.get_pachanga_tournament_draw_audit_v1(
      case_row.competition_id, case_row.plan_id
    );
    insert into r6a_performance_samples values (
      'audit view', sample_number,
      extract(epoch from (clock_timestamp()-started_at))*1000
    );
  end loop;
end;
$$;

select 'R6A_PERFORMANCE_REPORT|' || jsonb_build_object(
  'samples', (select count(*) from r6a_performance_samples),
  'operations', (
    select jsonb_object_agg(operation, jsonb_build_object(
      'count', sample_count,
      'p50Ms', round(p50_ms, 3),
      'p95Ms', round(p95_ms, 3),
      'maxMs', round(max_ms, 3)
    ) order by operation)
    from (
      select operation,
        count(*) sample_count,
        percentile_cont(0.50) within group(order by duration_ms)::numeric p50_ms,
        percentile_cont(0.95) within group(order by duration_ms)::numeric p95_ms,
        max(duration_ms) max_ms
      from r6a_performance_samples
      group by operation
    ) metrics
  ),
  'solverAttemptCap', 128,
  'tournamentMatches', (
    select count(*) from public.pachanga_competition_match_contexts contexts
    join r6a_engine_cases cases on cases.competition_id=contexts.competition_id
  )
)::text;
