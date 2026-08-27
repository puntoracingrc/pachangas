\set ON_ERROR_STOP on

select 'R6B_PERFORMANCE_MATRIX_REPORT|' || jsonb_build_object(
  'samples', (select count(*) from r6b_performance_samples),
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
      from r6b_performance_samples
      group by operation
    ) metrics
  )
)::text;
