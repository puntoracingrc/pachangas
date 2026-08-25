\set ON_ERROR_STOP on

begin;
set local lock_timeout = '3s';
set local statement_timeout = '90s';
set local synchronous_commit = off;

create temporary table r4d_scale_metrics(
  label text primary key,
  rows_inserted integer not null,
  duration_ms numeric not null
) on commit drop;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_postponement_requests(
    competition_id, canonical_match_id, competition_match_context_id,
    requesting_entry_id, responding_entry_id, rule_revision_id, status,
    proposed_venue_status, reason_code, response_deadline, deadline_policy,
    organizer_approval_required, team_response, organizer_response,
    operation_id, requested_by, resolved_at
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4200000-0000-4000-8000-000000000011',
    'c4200000-0000-4000-8000-000000000012',
    'c4200000-0000-4000-8000-000000000003',
    'expired', 'TBD', 'SCALE_EXPIRED', clock_timestamp(), 'EXPIRE',
    true, 'PENDING', 'PENDING', gen_random_uuid(),
    'c4010000-0000-4000-8000-000000000003', clock_timestamp()
  from generate_series(1, 10000);
  insert into r4d_scale_metrics values (
    'postponement_requests', 10000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_fixture_changes(
    competition_id, canonical_match_id, competition_match_context_id,
    schedule_item_id, rule_revision_id, change_type, status, source_type,
    original_scheduled_start, original_scheduled_end, original_timezone,
    original_venue_label, original_venue_status, creation_operation_id,
    created_by
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4400000-0000-4000-8000-000000000005',
    'c4200000-0000-4000-8000-000000000003',
    'RESCHEDULE', 'superseded', 'DIRECT_OPERATION',
    '2027-03-01T19:00:00Z', '2027-03-01T20:10:00Z', 'Europe/Madrid',
    'Pista Demo R4D', 'CONFIRMED', gen_random_uuid(),
    'd4010000-0000-4000-8000-000000000010'
  from generate_series(1, 10000);
  insert into r4d_scale_metrics values (
    'fixture_changes', 10000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_late_arrival_incidents(
    competition_id, canonical_match_id, competition_match_context_id,
    responsible_entry_id, rule_revision_id, scheduled_start, grace_deadline,
    status, operation_id, reported_by
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    case when series % 2 = 0
      then 'c4200000-0000-4000-8000-000000000011'::uuid
      else 'c4200000-0000-4000-8000-000000000012'::uuid end,
    'c4200000-0000-4000-8000-000000000003',
    '2027-03-01T19:00:00Z', '2027-03-01T19:10:00Z',
    'dismissed', gen_random_uuid(),
    'd4010000-0000-4000-8000-000000000010'
  from generate_series(1, 5000) series;
  insert into r4d_scale_metrics values (
    'late_arrival_incidents', 5000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_no_show_incidents(
    competition_id, canonical_match_id, competition_match_context_id,
    responsible_entry_id, rule_revision_id, status, scheduled_start,
    grace_deadline, reason_code, operation_id, reported_by, resolved_at
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    case when series % 2 = 0
      then 'c4200000-0000-4000-8000-000000000011'::uuid
      else 'c4200000-0000-4000-8000-000000000012'::uuid end,
    'c4200000-0000-4000-8000-000000000003',
    'rejected', '2027-03-01T19:00:00Z', '2027-03-01T19:10:00Z',
    'SCALE_REJECTED', gen_random_uuid(),
    'd4010000-0000-4000-8000-000000000010', clock_timestamp()
  from generate_series(1, 2000) series;
  insert into r4d_scale_metrics values (
    'no_show_incidents', 2000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_match_suspensions(
    competition_id, canonical_match_id, competition_match_context_id,
    rule_revision_id, reported_minute, sporting_score_home,
    sporting_score_away, reason_code, status, operation_id, reported_by,
    resolved_at
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4200000-0000-4000-8000-000000000003',
    series % 90, series % 5, series % 4,
    'SCALE_ABANDONED', 'abandoned', gen_random_uuid(),
    'd4010000-0000-4000-8000-000000000010', clock_timestamp()
  from generate_series(1, 2000) series;
  insert into r4d_scale_metrics values (
    'match_suspensions', 2000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

do $body$
declare started_at timestamptz := clock_timestamp();
begin
  insert into public.pachanga_competition_administrative_decisions(
    competition_id, decision_type, target_type, target_id, rule_revision_id,
    reason_code, status, operation_id, decided_by
  )
  select
    'c4200000-0000-4000-8000-000000000001',
    'CANCEL_MATCH', 'MATCH_CONTEXT',
    'c4400000-0000-4000-8000-000000000008',
    'c4200000-0000-4000-8000-000000000003',
    'SCALE_ANNULLED', 'annulled', gen_random_uuid(),
    'd4010000-0000-4000-8000-000000000010'
  from generate_series(1, 5000);
  insert into r4d_scale_metrics values (
    'administrative_decisions', 5000,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

set constraints all immediate;

do $body$
begin
  if (select count(*) from public.pachanga_competition_postponement_requests) <> 10000
    or (select count(*) from public.pachanga_competition_fixture_changes) <> 10000
    or (select count(*) from public.pachanga_competition_late_arrival_incidents) <> 5000
    or (select count(*) from public.pachanga_competition_no_show_incidents) <> 2000
    or (select count(*) from public.pachanga_competition_match_suspensions) <> 2000
    or (select count(*) from public.pachanga_competition_administrative_decisions) <> 5000 then
    raise exception 'R4D_SCALE_COUNTS_MISMATCH';
  end if;
end;
$body$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d4010000-0000-4000-8000-000000000010","role":"authenticated"}',
  true
);

do $body$
declare started_at timestamptz;
declare result jsonb;
begin
  started_at := clock_timestamp();
  result := public.get_pachanga_public_league_fixture_status_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006'
  );
  insert into r4d_scale_metrics values (
    'public_fixture_status', 1,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );

  started_at := clock_timestamp();
  result := public.get_pachanga_league_postponement_desk_v1(
    'c4200000-0000-4000-8000-000000000001', null, 100, 0
  );
  insert into r4d_scale_metrics values (
    'postponement_desk', 100,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );

  started_at := clock_timestamp();
  result := public.get_pachanga_league_incident_desk_v1(
    'c4200000-0000-4000-8000-000000000001', 100, 0
  );
  insert into r4d_scale_metrics values (
    'incident_desk', 100,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );

  started_at := clock_timestamp();
  result := public.get_pachanga_league_administrative_decision_desk_v1(
    'c4200000-0000-4000-8000-000000000001', null, 100, 0
  );
  insert into r4d_scale_metrics values (
    'administrative_decision_desk', 100,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$body$;

select 'R4D_SCALE|' || jsonb_build_object(
  'volumes', jsonb_build_object(
    'postponementRequests', 10000,
    'fixtureChanges', 10000,
    'lateArrivalIncidents', 5000,
    'noShowIncidents', 2000,
    'matchSuspensions', 2000,
    'administrativeDecisions', 5000
  ),
  'insertMetricsMs', (
    select jsonb_object_agg(label, round(duration_ms, 3))
    from r4d_scale_metrics
    where label in (
      'postponement_requests', 'fixture_changes', 'late_arrival_incidents',
      'no_show_incidents', 'match_suspensions', 'administrative_decisions'
    )
  ),
  'readMetricsMs', (
    select jsonb_object_agg(label, round(duration_ms, 3))
    from r4d_scale_metrics
    where label in (
      'public_fixture_status', 'postponement_desk', 'incident_desk',
      'administrative_decision_desk'
    )
  ),
  'indexBytes', (
    select coalesce(sum(pg_relation_size(indexes.indexrelid)), 0)
    from pg_index indexes
    join pg_class tables on tables.oid = indexes.indrelid
    join pg_namespace namespaces on namespaces.oid = tables.relnamespace
    where namespaces.nspname = 'public'
      and tables.relname in (
        'pachanga_competition_postponement_requests',
        'pachanga_competition_fixture_changes',
        'pachanga_competition_late_arrival_incidents',
        'pachanga_competition_no_show_incidents',
        'pachanga_competition_match_suspensions',
        'pachanga_competition_administrative_decisions'
      )
  ),
  'locksHeld', (
    select count(*) from pg_locks locks where locks.pid = pg_backend_pid()
  ),
  'rollback', true
)::text;

rollback;
