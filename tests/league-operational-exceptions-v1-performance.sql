\set ON_ERROR_STOP on

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

create or replace function pg_temp.actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.context_revision()
returns bigint language sql stable as $$
  select revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
$$;

create or replace function pg_temp.command(
  target_actor_id uuid,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.actor(target_actor_id);
  return public.command_pachanga_league_operational_exceptions_v1(
    gen_random_uuid(), 'c4400000-0000-4000-8000-000000000008',
    pg_temp.context_revision(), target_action, target_payload,
    '{"clientVersion":"4.0.0+r4d-performance","surface":"r4d_performance"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.measure_r4d(
  metric_label text,
  target_actor_id uuid,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare started_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  response := pg_temp.command(target_actor_id, target_action, target_payload);
  return jsonb_build_object(
    'label', metric_label,
    'durationMs', round((extract(epoch from clock_timestamp() - started_at) * 1000)::numeric, 3),
    'confirmedRevision', response -> 'confirmedRevision'
  );
end;
$$;

create or replace function pg_temp.measure_r4c(
  metric_label text,
  target_actor_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare started_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  perform pg_temp.actor(target_actor_id);
  response := public.command_pachanga_league_match_operations_v1(
    gen_random_uuid(), 'c4400000-0000-4000-8000-000000000008',
    target_expected_revision, target_action, target_payload,
    '{"clientVersion":"4.0.0+r4d-performance","surface":"r4d_performance"}'::jsonb
  );
  return jsonb_build_object(
    'label', metric_label,
    'durationMs', round((extract(epoch from clock_timestamp() - started_at) * 1000)::numeric, 3),
    'confirmedRevision', response -> 'confirmedRevision'
  );
end;
$$;

create or replace function pg_temp.seed_match_sheet(target_status text)
returns void language plpgsql as $$
begin
  insert into public.pachanga_competition_match_sheets(
    canonical_match_id, competition_match_context_id, created_by
  ) values (
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4010000-0000-4000-8000-000000000002'
  );
  update public.pachanga_competition_match_contexts set
    status = target_status,
    scheduled_start = case when target_status = 'ready'
      then clock_timestamp() - interval '20 minutes' else scheduled_start end,
    scheduled_end = case when target_status = 'ready'
      then clock_timestamp() + interval '50 minutes' else scheduled_end end
  where id = 'c4400000-0000-4000-8000-000000000008';
end;
$$;

savepoint r4d_perf_postponement;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'request_create',
  'c4010000-0000-4000-8000-000000000003',
  'postponement.request',
  '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"PERF_REQUEST"}'::jsonb
)::text;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'request_respond',
  'c4010000-0000-4000-8000-000000000004',
  'postponement.respond',
  jsonb_build_object(
    'requestId', (select id from public.pachanga_competition_postponement_requests
      order by server_sequence desc, id desc limit 1),
    'responseKind', 'ACCEPT', 'reasonCode', 'PERF_ACCEPT'
  )
)::text;
rollback to savepoint r4d_perf_postponement;

savepoint r4d_perf_reschedule;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'reschedule',
  'd4010000-0000-4000-8000-000000000010',
  'fixture.reschedule',
  '{"scheduledStart":"2027-03-03T19:00:00Z","scheduledEnd":"2027-03-03T20:10:00Z","timezone":"Europe/Madrid","reasonCode":"PERF_RESCHEDULE"}'::jsonb
)::text;
rollback to savepoint r4d_perf_reschedule;

savepoint r4d_perf_venue;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'venue_change',
  'd4010000-0000-4000-8000-000000000010',
  'fixture.change_venue',
  '{"venueStatus":"LABEL","venueLabel":"Pista rendimiento R4D","reasonCode":"PITCH_UNAVAILABLE"}'::jsonb
)::text;
rollback to savepoint r4d_perf_venue;

savepoint r4d_perf_no_show;
select pg_temp.seed_match_sheet('ready');
select pg_temp.command(
  'c4010000-0000-4000-8000-000000000003',
  'no_show.report',
  '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"PERF_NO_SHOW","reasonText":"No comparece tras el margen."}'::jsonb
);
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'no_show_confirmation',
  'd4010000-0000-4000-8000-000000000010',
  'no_show.confirm',
  jsonb_build_object(
    'incidentId', (select id from public.pachanga_competition_no_show_incidents
      order by server_sequence desc, id desc limit 1),
    'reasonCode', 'PERF_NO_SHOW_CONFIRMED'
  )
)::text;
rollback to savepoint r4d_perf_no_show;

savepoint r4d_perf_suspension;
select pg_temp.seed_match_sheet('in_progress');
select pg_temp.command(
  'c4010000-0000-4000-8000-000000000003',
  'suspension.report',
  '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":37,"partialScoreHome":1,"partialScoreAway":0,"reasonCode":"PERF_SUSPENSION","reasonText":"Partido suspendido."}'::jsonb
);
select pg_temp.command(
  'd4010000-0000-4000-8000-000000000010',
  'suspension.confirm',
  jsonb_build_object(
    'suspensionId', (select id from public.pachanga_competition_match_suspensions
      order by server_sequence desc, id desc limit 1),
    'reasonCode', 'PERF_SUSPENSION_CONFIRMED'
  )
);
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'suspension_resolution',
  'd4010000-0000-4000-8000-000000000010',
  'suspension.resolve',
  jsonb_build_object(
    'suspensionId', (select id from public.pachanga_competition_match_suspensions
      order by server_sequence desc, id desc limit 1),
    'resolutionType', 'PENDING_ADMINISTRATIVE_DECISION',
    'reasonCode', 'PERF_ADMIN_REVIEW'
  )
)::text;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4d(
  'administrative_decision',
  'd4010000-0000-4000-8000-000000000010',
  'administrative_decision.publish',
  jsonb_build_object(
    'decisionType', 'SET_OFFICIAL_RESULT',
    'suspensionId', (select id from public.pachanga_competition_match_suspensions
      order by server_sequence desc, id desc limit 1),
    'reasonCode', 'PERF_PARTIAL_RESULT'
  )
)::text;
select 'R4D_PERFORMANCE|' || pg_temp.measure_r4c(
  'standings_rebuild',
  'c4010000-0000-4000-8000-000000000002',
  (select revision from public.pachanga_competition_standing_states limit 1),
  'standings.rebuild',
  '{"rebuildKind":"FULL_AUDIT"}'::jsonb
)::text;
rollback to savepoint r4d_perf_suspension;

rollback;
