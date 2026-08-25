\set ON_ERROR_STOP on

begin;

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
    jsonb_strip_nulls(jsonb_build_object('sub', target_user_id, 'role', target_role))::text,
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
    raise exception 'R4D_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4D_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.context_revision()
returns bigint language sql stable as $$
  select revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
$$;

create or replace function pg_temp.command(
  target_actor_id uuid,
  target_operation_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.actor(target_actor_id);
  return public.command_pachanga_league_operational_exceptions_v1(
    target_operation_id,
    'c4400000-0000-4000-8000-000000000008',
    target_expected_revision,
    target_action,
    target_payload,
    jsonb_build_object(
      'clientVersion', '4.0.0+r4d-db',
      'serviceWorkerVersion', 'sw-r4d-db',
      'installedMode', 'standalone',
      'surface', 'r4d_db',
      'sessionId', 'must-not-persist'
    )
  );
end;
$$;

create or replace function pg_temp.expect_command_failure(
  target_actor_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb,
  expected_pattern text
)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    perform pg_temp.command(
      target_actor_id, gen_random_uuid(), target_expected_revision,
      target_action, target_payload
    );
    raise exception 'R4D_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4D_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected command failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.command_replay(
  target_actor_id uuid,
  target_operation_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare response jsonb;
declare replay jsonb;
declare receipt_count_before bigint;
declare event_count_before bigint;
declare notification_count_before bigint;
begin
  response := pg_temp.command(
    target_actor_id, target_operation_id, target_expected_revision,
    target_action, target_payload
  );
  select count(*) into receipt_count_before
  from private.pachanga_competition_operation_receipts
  where operation_id = target_operation_id;
  select count(*) into event_count_before
  from private.pachanga_competition_events
  where operation_id = target_operation_id;
  select count(*) into notification_count_before
  from public.pachanga_user_notifications
  where dedupe_key like 'r4d:' || target_operation_id::text || ':%';
  replay := pg_temp.command(
    target_actor_id, target_operation_id, target_expected_revision,
    target_action, target_payload
  );
  perform pg_temp.assert_true(response = replay, target_action || ' replay changed its response');
  perform pg_temp.assert_true(
    receipt_count_before = 1 and event_count_before = 1
      and (select count(*) from private.pachanga_competition_operation_receipts
        where operation_id = target_operation_id) = 1
      and (select count(*) from private.pachanga_competition_events
        where operation_id = target_operation_id) = 1
      and (select count(*) from public.pachanga_user_notifications
        where dedupe_key like 'r4d:' || target_operation_id::text || ':%') = notification_count_before,
    target_action || ' replay duplicated a receipt, event or notification'
  );
  return response;
end;
$$;

create or replace function pg_temp.service_command_replay(
  target_operation_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare response jsonb;
declare replay jsonb;
begin
  perform pg_temp.actor(null, 'service_role');
  response := public.command_pachanga_league_operational_exceptions_v1(
    target_operation_id, 'c4400000-0000-4000-8000-000000000008',
    target_expected_revision, target_action, target_payload,
    '{"clientVersion":"service+r4d-db","surface":"r4d_deadline"}'::jsonb
  );
  replay := public.command_pachanga_league_operational_exceptions_v1(
    target_operation_id, 'c4400000-0000-4000-8000-000000000008',
    target_expected_revision, target_action, target_payload,
    '{"clientVersion":"service+r4d-db","surface":"r4d_deadline"}'::jsonb
  );
  perform pg_temp.assert_true(response = replay, target_action || ' service replay changed its response');
  return response;
end;
$$;

create or replace function pg_temp.r4c_command(
  target_actor_id uuid,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.actor(target_actor_id);
  return public.command_pachanga_league_match_operations_v1(
    gen_random_uuid(), 'c4400000-0000-4000-8000-000000000008',
    pg_temp.context_revision(), target_action, target_payload,
    '{"clientVersion":"4.0.0+r4d-db","surface":"r4d_fixture_setup"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.prepare_in_progress_match()
returns void language plpgsql as $$
declare home_squad_id uuid;
declare away_squad_id uuid;
begin
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000003', 'squad.create',
    '{"entryId":"c4200000-0000-4000-8000-000000000011"}'::jsonb
  );
  select id into home_squad_id from public.pachanga_competition_match_squads
  where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008'
    and side = 'HOME';
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000003', 'squad.member.add',
    jsonb_build_object(
      'squadId', home_squad_id,
      'rosterMemberId', 'c4200000-0000-4000-8000-000000000019',
      'memberRole', 'STARTER', 'shirtNumber', 9,
      'positionOrder', 1, 'isCaptain', true
    )
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000003', 'squad.submit',
    jsonb_build_object('squadId', home_squad_id)
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'squad.validate',
    jsonb_build_object('squadId', home_squad_id)
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'squad.lock',
    jsonb_build_object('squadId', home_squad_id)
  );

  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000004', 'squad.create',
    '{"entryId":"c4200000-0000-4000-8000-000000000012"}'::jsonb
  );
  select id into away_squad_id from public.pachanga_competition_match_squads
  where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008'
    and side = 'AWAY';
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000004', 'squad.member.add',
    jsonb_build_object(
      'squadId', away_squad_id,
      'rosterMemberId', 'c4200000-0000-4000-8000-000000000020',
      'memberRole', 'STARTER', 'shirtNumber', 10,
      'positionOrder', 1, 'isCaptain', true
    )
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000004', 'squad.submit',
    jsonb_build_object('squadId', away_squad_id)
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'squad.validate',
    jsonb_build_object('squadId', away_squad_id)
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'squad.lock',
    jsonb_build_object('squadId', away_squad_id)
  );

  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000005', 'attendance.set',
    '{"entryId":"c4200000-0000-4000-8000-000000000011","rosterMemberId":"c4200000-0000-4000-8000-000000000019","status":"going"}'::jsonb
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000006', 'attendance.set',
    '{"entryId":"c4200000-0000-4000-8000-000000000012","rosterMemberId":"c4200000-0000-4000-8000-000000000020","status":"going"}'::jsonb
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000003', 'attendance.close',
    '{"entryId":"c4200000-0000-4000-8000-000000000011"}'::jsonb
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000004', 'attendance.close',
    '{"entryId":"c4200000-0000-4000-8000-000000000012"}'::jsonb
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'match.mark_ready'
  );
  perform pg_temp.r4c_command(
    'c4010000-0000-4000-8000-000000000002', 'match.start'
  );
end;
$$;

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

create temporary table r4d_invariants_before(table_name text primary key, digest text not null);
insert into r4d_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_competition_schedule_items'),
  ('public.pachanga_competition_schedule_revisions'),
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_stripe_webhook_events')
) tables(table_name);

do $body$
declare flags jsonb;
declare private_read jsonb;
declare public_read jsonb;
begin
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  flags := public.get_pachanga_league_operational_exceptions_flags_v1();
  perform pg_temp.assert_true(
    flags #>> '{foundationEnabled}' = 'true'
      and flags #>> '{noShowEnabled}' = 'true'
      and flags #>> '{publicExceptionStatusEnabled}' = 'true',
    'R4D disposable fixture flags were not enabled'
  );
  private_read := public.get_pachanga_league_operational_match_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006'
  );
  perform pg_temp.assert_true(
    private_read #>> '{originalSchedule,scheduledStart}' = '2027-03-01T19:00:00+00:00'
      and private_read::text not like '%evidenceRefs%'
      and private_read::text not like '%reasonText%',
    'Private operational match read lost original schedule or leaked evidence'
  );
  public_read := public.get_pachanga_public_league_fixture_status_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006'
  );
  perform pg_temp.assert_true(
    public_read #>> '{statusLabel}' = 'Programado'
      and public_read::text not like '%requestedBy%'
      and public_read::text not like '%reportedBy%'
      and public_read::text not like '%evidence%',
    'Public fixture status leaked private operational details'
  );
end;
$body$;

savepoint r4d_direct_write_guard;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"c4010000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select pg_temp.expect_failure(
  $$insert into public.pachanga_competition_postponement_requests(
    competition_id, canonical_match_id, competition_match_context_id,
    requesting_entry_id, responding_entry_id, rule_revision_id,
    proposed_venue_status, reason_code, response_deadline, deadline_policy,
    organizer_approval_required, operation_id, requested_by
  ) values (
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4200000-0000-4000-8000-000000000011',
    'c4200000-0000-4000-8000-000000000012',
    'c4200000-0000-4000-8000-000000000003',
    'TBD', 'FORBIDDEN_DIRECT_WRITE', clock_timestamp(), 'EXPIRE', true,
    gen_random_uuid(), 'c4010000-0000-4000-8000-000000000003'
  )$$,
  'permission denied'
);
reset role;
rollback to savepoint r4d_direct_write_guard;

savepoint r4d_rbac_matrix;
do $body$
declare revision bigint := pg_temp.context_revision();
declare payload jsonb := '{
  "requestingEntryId":"c4200000-0000-4000-8000-000000000011",
  "reasonCode":"TEAM_REQUEST","publicSummary":"Solicitud de prueba."
}'::jsonb;
begin
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000005', gen_random_uuid(), %s,
      'postponement.request', %L::jsonb
    )$sql$, revision, payload::text),
    'TEAM_OWNER_OR_PRIMARY_DELEGATE_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'd4010000-0000-4000-8000-000000000018', gen_random_uuid(), %s,
      'postponement.request', %L::jsonb
    )$sql$, revision, payload::text),
    'TEAM_OWNER_OR_PRIMARY_DELEGATE_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000007', gen_random_uuid(), %s,
      'postponement.request', %L::jsonb
    )$sql$, revision, payload::text),
    'TEAM_OWNER_OR_PRIMARY_DELEGATE_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'd4010000-0000-4000-8000-000000000014', gen_random_uuid(), %s,
      'fixture.cancel', '{"reasonCode":"OTHER","cancellationOutcome":"NO_RESULT"}'::jsonb
    )$sql$, revision),
    'COMPETITION_OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'd4010000-0000-4000-8000-000000000017', gen_random_uuid(), %s,
      'fixture.cancel', '{"reasonCode":"OTHER","cancellationOutcome":"NO_RESULT"}'::jsonb
    )$sql$, revision),
    'COMPETITION_OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000008', gen_random_uuid(), %s,
      'fixture.cancel', '{"reasonCode":"OTHER","cancellationOutcome":"NO_RESULT"}'::jsonb
    )$sql$, revision),
    'COMPETITION_OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'd4010000-0000-4000-8000-000000000011', gen_random_uuid(), %s,
      'fixture.cancel', '{"reasonCode":"OTHER","cancellationOutcome":"NO_RESULT"}'::jsonb
    )$sql$, revision),
    'COMPETITION_OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'd4010000-0000-4000-8000-000000000012', gen_random_uuid(), %s,
      'fixture.cancel', '{"reasonCode":"OTHER","cancellationOutcome":"NO_RESULT"}'::jsonb
    )$sql$, revision),
    'COMPETITION_OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000013',
    'd4500000-0000-4000-8000-000000000001', revision,
    'postponement.request', payload
  );
end;
$body$;
rollback to savepoint r4d_rbac_matrix;

savepoint r4d_postponement_accepted;
do $body$
declare response jsonb;
declare request_id uuid;
declare original_item jsonb;
declare public_read jsonb;
begin
  select to_jsonb(items) into original_item
  from public.pachanga_competition_schedule_items items
  where items.id = 'c4400000-0000-4000-8000-000000000005';
  response := pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4510000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'postponement.request',
    '{
      "requestingEntryId":"c4200000-0000-4000-8000-000000000011",
      "reasonCode":"TEAM_CONFLICT",
      "reasonText":"La instalación no estará disponible.",
      "evidenceRefs":["fixture://private/postponement"],
      "publicSummary":"El local solicita aplazar el partido."
    }'::jsonb
  );
  select id into request_id
  from public.pachanga_competition_postponement_requests
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000004',
    'd4510000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'postponement.respond',
    jsonb_build_object(
      'requestId', request_id, 'responseKind', 'ACCEPT',
      'reasonCode', 'RIVAL_ACCEPTED',
      'publicSummary', 'El rival acepta el aplazamiento.'
    )
  );
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000002',
    'd4510000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'postponement.respond',
    jsonb_build_object(
      'requestId', request_id, 'responseKind', 'APPROVE',
      'reasonCode', 'ORGANIZER_APPROVED',
      'publicSummary', 'Partido aplazado por la organización.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_postponement_requests where id = request_id) = 'approved'
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'postponed'
      and (select change_type from public.pachanga_competition_fixture_changes
        where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008') = 'POSTPONEMENT'
      and (select to_jsonb(items) from public.pachanga_competition_schedule_items items
        where items.id = 'c4400000-0000-4000-8000-000000000005') = original_item,
    'Approved postponement did not preserve the original R4B fixture'
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4510000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'fixture.reschedule',
    '{
      "scheduledStart":"2027-03-03T19:00:00Z",
      "scheduledEnd":"2027-03-03T20:10:00Z",
      "timezone":"Europe/Madrid",
      "reasonCode":"NEW_DATE",
      "publicSummary":"Nueva fecha confirmada."
    }'::jsonb
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'scheduled'
      and (select scheduled_start from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = '2027-03-03T19:00:00Z'::timestamptz
      and (select count(*) from public.pachanga_competition_fixture_change_revisions) = 2
      and (select scheduled_start from public.pachanga_competition_schedule_items
        where id = 'c4400000-0000-4000-8000-000000000005') = '2027-03-01T19:00:00Z'::timestamptz,
    'Rescheduling lost the original schedule or effective revision lineage'
  );
  public_read := public.get_pachanga_public_league_fixture_status_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006'
  );
  perform pg_temp.assert_true(
    public_read #>> '{originalSchedule,scheduledStart}' = '2027-03-01T19:00:00+00:00'
      and public_read #>> '{effectiveSchedule,scheduledStart}' = '2027-03-03T19:00:00+00:00'
      and public_read::text not like '%fixture://private/postponement%',
    'Public read did not apply the canonical fixture overlay safely'
  );
end;
$body$;
rollback to savepoint r4d_postponement_accepted;

savepoint r4d_postponement_rejected_and_withdrawn;
do $body$
declare request_id uuid;
begin
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4520000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"REQUEST_REJECT","publicSummary":"Solicitud a rechazar."}'::jsonb
  );
  select id into request_id from public.pachanga_competition_postponement_requests
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000004',
    'd4520000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'postponement.respond',
    jsonb_build_object('requestId', request_id, 'responseKind', 'REJECT',
      'reasonCode', 'RIVAL_REJECTED', 'publicSummary', 'Solicitud rechazada.')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_postponement_requests where id = request_id) = 'denied'
      and (select scheduled_start from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = '2027-03-01T19:00:00Z'::timestamptz
      and not exists (select 1 from public.pachanga_competition_fixture_changes),
    'Rejected postponement changed the fixture'
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000013',
    'd4520000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"REQUEST_WITHDRAW","publicSummary":"Solicitud a retirar."}'::jsonb
  );
  select id into request_id from public.pachanga_competition_postponement_requests
  where status = 'awaiting_response' order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000013',
    'd4520000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'postponement.withdraw',
    jsonb_build_object('requestId', request_id, 'reasonCode', 'WITHDRAWN_BY_TEAM')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_postponement_requests where id = request_id) = 'withdrawn',
    'Postponement withdrawal did not close the request'
  );
end;
$body$;
rollback to savepoint r4d_postponement_rejected_and_withdrawn;

savepoint r4d_deadline_policies;
do $body$
declare request_id uuid;
begin
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4530000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"DEADLINE_EXPIRE"}'::jsonb
  );
  select id into request_id from public.pachanga_competition_postponement_requests
  where status = 'awaiting_response';
  update public.pachanga_competition_postponement_requests
  set response_deadline = clock_timestamp() - interval '1 minute'
  where id = request_id;
  perform pg_temp.service_command_replay(
    'd4530000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'postponement.expire', jsonb_build_object('requestId', request_id, 'reasonCode', 'DEADLINE_PROCESSOR')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_postponement_requests where id = request_id) = 'expired',
    'EXPIRE policy did not expire the request'
  );

  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4530000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"DEADLINE_AUTO_DENY"}'::jsonb
  );
  select id into request_id from public.pachanga_competition_postponement_requests
  where status = 'awaiting_response';
  update public.pachanga_competition_postponement_requests
  set response_deadline = clock_timestamp() - interval '1 minute', deadline_policy = 'AUTO_DENY'
  where id = request_id;
  perform pg_temp.service_command_replay(
    'd4530000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'postponement.expire', jsonb_build_object('requestId', request_id, 'reasonCode', 'DEADLINE_PROCESSOR')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_postponement_requests where id = request_id) = 'denied',
    'AUTO_DENY policy did not deny the request'
  );

  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4530000-0000-4000-8000-000000000005', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"DEADLINE_ESCALATE"}'::jsonb
  );
  select id into request_id from public.pachanga_competition_postponement_requests
  where status = 'awaiting_response';
  update public.pachanga_competition_postponement_requests
  set response_deadline = clock_timestamp() - interval '1 minute', deadline_policy = 'ESCALATE_TO_ORGANIZER'
  where id = request_id;
  perform pg_temp.service_command_replay(
    'd4530000-0000-4000-8000-000000000006', pg_temp.context_revision(),
    'postponement.expire', jsonb_build_object('requestId', request_id, 'reasonCode', 'DEADLINE_PROCESSOR')
  );
  perform pg_temp.assert_true(
    (select status = 'awaiting_response' and organizer_response = 'ESCALATED'
      from public.pachanga_competition_postponement_requests where id = request_id),
    'ESCALATE_TO_ORGANIZER policy did not preserve the pending request'
  );
end;
$body$;
rollback to savepoint r4d_deadline_policies;

savepoint r4d_fixture_manager_actions;
do $body$
declare original_item jsonb;
begin
  select to_jsonb(items) into original_item from public.pachanga_competition_schedule_items items
  where items.id = 'c4400000-0000-4000-8000-000000000005';
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4540000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'fixture.change_venue',
    '{"venueLabel":"Pista alternativa R4D","venueStatus":"LABEL","reasonCode":"PITCH_UNAVAILABLE","reasonText":"La pista original está cerrada.","publicSummary":"Cambio de campo confirmado."}'::jsonb
  );
  perform pg_temp.assert_true(
    (select venue_label from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'Pista alternativa R4D'
      and (select outcome from public.pachanga_competition_venue_condition_decisions) = 'venue_changed'
      and (select to_jsonb(items) from public.pachanga_competition_schedule_items items
        where items.id = 'c4400000-0000-4000-8000-000000000005') = original_item,
    'Venue change did not create its request/decision overlay'
  );
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000002',
    'd4540000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'fixture.cancel',
    '{"cancellationOutcome":"NO_RESULT","reasonCode":"FACILITY_CLOSED","publicSummary":"Partido cancelado sin resultado."}'::jsonb
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'cancelled'
      and not exists (
        select 1 from public.pachanga_competition_official_result_decisions
      ),
    'Fixture cancellation invented a sporting result'
  );
end;
$body$;
rollback to savepoint r4d_fixture_manager_actions;

savepoint r4d_late_arrival_within_policy;
do $body$
declare incident_id uuid;
begin
  update public.pachanga_competition_match_contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() - interval '5 minutes',
    scheduled_end = clock_timestamp() + interval '65 minutes'
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4550000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'late_arrival.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"TEAM_DELAY","reasonText":"El visitante comunica retraso.","publicSummary":"Retraso reportado."}'::jsonb
  );
  select id into incident_id from public.pachanga_competition_late_arrival_incidents;
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000004',
    'd4550000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'late_arrival.confirm_arrival',
    jsonb_build_object('incidentId', incident_id, 'reasonCode', 'ARRIVED')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_late_arrival_incidents where id = incident_id) = 'arrived_within_policy'
      and not exists (select 1 from public.pachanga_competition_no_show_incidents)
      and not exists (select 1 from public.pachanga_competition_official_result_decisions),
    'Arrival inside grace policy created a no-show or result'
  );
end;
$body$;
rollback to savepoint r4d_late_arrival_within_policy;

savepoint r4d_no_show_rejected;
do $body$
declare incident_id uuid;
begin
  update public.pachanga_competition_match_contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() - interval '20 minutes',
    scheduled_end = clock_timestamp() + interval '50 minutes'
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4560000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'no_show.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"NO_SHOW_REPORTED","reasonText":"El visitante no está presente.","evidenceRefs":["fixture://private/no-show"],"publicSummary":"Incomparecencia en revisión."}'::jsonb
  );
  select id into incident_id from public.pachanga_competition_no_show_incidents;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4560000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'no_show.reject',
    jsonb_build_object('incidentId', incident_id, 'reasonCode', 'EVIDENCE_INSUFFICIENT',
      'publicSummary', 'Incidencia rechazada.')
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_no_show_incidents where id = incident_id) = 'rejected'
      and not exists (select 1 from public.pachanga_competition_official_result_decisions),
    'Rejected no-show created an official result'
  );
end;
$body$;
rollback to savepoint r4d_no_show_rejected;

savepoint r4d_no_show_confirmed;
do $body$
declare incident_id uuid;
declare admin_decision_id uuid;
declare official_decision_id uuid;
begin
  update public.pachanga_competition_match_contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() - interval '20 minutes',
    scheduled_end = clock_timestamp() + interval '50 minutes'
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4570000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'no_show.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"NO_SHOW_REPORTED","reasonText":"El visitante no comparece tras el margen.","evidenceRefs":["fixture://private/no-show-confirmed"],"publicSummary":"Incomparecencia en revisión."}'::jsonb
  );
  select id into incident_id from public.pachanga_competition_no_show_incidents;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4570000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'no_show.confirm',
    jsonb_build_object('incidentId', incident_id, 'reasonCode', 'NO_SHOW_CONFIRMED',
      'reasonText', 'La autoridad valida la evidencia.',
      'publicSummary', 'Incomparecencia confirmada.')
  );
  select decisions.id into admin_decision_id
  from public.pachanga_competition_administrative_decisions decisions
  where decisions.target_type = 'NO_SHOW_INCIDENT';
  select decisions.id into official_decision_id
  from public.pachanga_competition_official_result_decisions decisions
  where decisions.operational_source_type = 'NO_SHOW_INCIDENT';
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'official'
      and (select outcome = 'NO_SHOW' and effective_score_home = 3 and effective_score_away = 0
        from public.pachanga_competition_official_result_decisions where id = official_decision_id)
      and exists (select 1 from public.pachanga_competition_standing_snapshots)
      and not exists (select 1 from private.pachanga_conduct_reports)
      and not exists (select 1 from private.pachanga_moderation_cases),
    'Confirmed no-show did not derive the RuleRevision result safely'
  );
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000002',
    'd4570000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'no_show.resolve',
    jsonb_build_object('incidentId', incident_id, 'reasonCode', 'CASE_RESOLVED')
  );
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000002',
    'd4570000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'administrative_decision.annul',
    jsonb_build_object('decisionId', admin_decision_id, 'reasonCode', 'DECISION_ANNULLED',
      'publicSummary', 'Resultado administrativo anulado.')
  );
  perform pg_temp.assert_true(
    (select outcome from public.pachanga_competition_official_result_decisions
      order by server_sequence desc, id desc limit 1) = 'ANNULLED'
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'administrative_review',
    'Administrative annul did not rebuild the canonical result state'
  );
end;
$body$;
rollback to savepoint r4d_no_show_confirmed;

savepoint r4d_late_arrival_escalation;
do $body$
declare late_incident_id uuid;
declare no_show_incident_id uuid;
begin
  update public.pachanga_competition_match_contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() - interval '20 minutes',
    scheduled_end = clock_timestamp() + interval '50 minutes'
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4580000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'late_arrival.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"TEAM_DELAY","reasonText":"El visitante sigue sin llegar.","publicSummary":"Retraso reportado."}'::jsonb
  );
  select id into late_incident_id
  from public.pachanga_competition_late_arrival_incidents
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4580000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'late_arrival.escalate',
    jsonb_build_object(
      'incidentId', late_incident_id,
      'reasonCode', 'GRACE_EXPIRED',
      'reasonText', 'El margen reglamentario ha vencido.',
      'publicSummary', 'Retraso escalado a incomparecencia.'
    )
  );
  select escalated_no_show_incident_id into no_show_incident_id
  from public.pachanga_competition_late_arrival_incidents
  where id = late_incident_id;
  perform pg_temp.assert_true(
    no_show_incident_id is not null
      and (select status from public.pachanga_competition_late_arrival_incidents
        where id = late_incident_id) = 'escalated_to_no_show'
      and (select status from public.pachanga_competition_no_show_incidents
        where id = no_show_incident_id) = 'under_review'
      and not exists (select 1 from public.pachanga_competition_official_result_decisions),
    'Late-arrival escalation did not create exactly one reviewable no-show'
  );
end;
$body$;
rollback to savepoint r4d_late_arrival_escalation;

savepoint r4d_suspension_resume;
do $body$
declare suspension_id uuid;
declare original_item jsonb;
begin
  select to_jsonb(items) into original_item
  from public.pachanga_competition_schedule_items items
  where items.id = 'c4400000-0000-4000-8000-000000000005';
  perform pg_temp.prepare_in_progress_match();
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd4590000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'suspension.report',
    '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":37,"partialScoreHome":1,"partialScoreAway":0,"reasonCode":"SAFETY_STOP","reasonText":"El árbitro detiene el partido por seguridad.","evidenceRefs":["fixture://private/suspension-37"],"publicSummary":"Partido suspendido en el minuto 37."}'::jsonb
  );
  select id into suspension_id
  from public.pachanga_competition_match_suspensions
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'administrative_review'
      and (select sporting_score_home = 1 and sporting_score_away = 0
        and sporting_result_revision_id is null
        from public.pachanga_competition_match_suspensions where id = suspension_id)
      and not exists (select 1 from public.pachanga_competition_official_result_decisions)
      and not exists (select 1 from public.pachanga_competition_standing_snapshots),
    'Suspension report did not preserve a non-official partial score'
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4590000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'suspension.confirm',
    jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'SUSPENSION_CONFIRMED')
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4590000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'suspension.schedule_resume',
    jsonb_build_object(
      'suspensionId', suspension_id, 'resumeMinute', 37,
      'scheduledStart', '2027-03-04T19:00:00Z',
      'scheduledEnd', '2027-03-04T20:10:00Z',
      'timezone', 'Europe/Madrid', 'venueStatus', 'LABEL',
      'venueLabel', 'Pista reanudacion R4D',
      'reasonCode', 'RESUMPTION_APPROVED',
      'publicSummary', 'El partido se reanudará desde el minuto 37.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_suspensions
      where id = suspension_id) = 'resume_scheduled'
      and (select decision_type = 'RESUME' and resume_minute = 37
        and initial_score_home = 1 and initial_score_away = 0
        and reuse_canonical_match
        from public.pachanga_competition_match_resumption_decisions
        where match_suspension_id = suspension_id)
      and (select count(*) from public.pachanga_canonical_matches) = 1
      and (select to_jsonb(items) from public.pachanga_competition_schedule_items items
        where items.id = 'c4400000-0000-4000-8000-000000000005') = original_item,
    'Resume scheduling duplicated CanonicalMatch or rewrote R4B'
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd4590000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'suspension.resume',
    jsonb_build_object(
      'suspensionId', suspension_id, 'reasonCode', 'MATCH_RESUMED',
      'publicSummary', 'Partido reanudado.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_suspensions
      where id = suspension_id) = 'resumed'
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'in_progress'
      and not exists (select 1 from public.pachanga_competition_official_result_decisions),
    'Resume did not continue the same match without inventing a result'
  );
end;
$body$;
rollback to savepoint r4d_suspension_resume;

savepoint r4d_suspension_replay;
do $body$
declare suspension_id uuid;
begin
  perform pg_temp.prepare_in_progress_match();
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd45a0000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'suspension.report',
    '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":22,"partialScoreHome":0,"partialScoreAway":0,"reasonCode":"LIGHTING_FAILURE","reasonText":"Fallo completo de iluminación.","publicSummary":"Partido suspendido."}'::jsonb
  );
  select id into suspension_id from public.pachanga_competition_match_suspensions
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45a0000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'suspension.confirm',
    jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'SUSPENSION_CONFIRMED')
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45a0000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'suspension.order_replay',
    jsonb_build_object(
      'suspensionId', suspension_id,
      'scheduledStart', '2027-03-05T19:00:00Z',
      'scheduledEnd', '2027-03-05T20:10:00Z',
      'timezone', 'Europe/Madrid', 'venueStatus', 'TBD',
      'reasonCode', 'FULL_REPLAY', 'publicSummary', 'Se ordena repetir el encuentro.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_suspensions
      where id = suspension_id) = 'replay_ordered'
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'scheduled'
      and (select decision_type = 'REPLAY' and resume_minute = 0
        and initial_score_home = 0 and initial_score_away = 0
        and reuse_canonical_match
        from public.pachanga_competition_match_resumption_decisions
        where match_suspension_id = suspension_id)
      and (select count(*) from public.pachanga_canonical_matches) = 1
      and (select change_type from public.pachanga_competition_fixture_changes
        order by server_sequence desc, id desc limit 1) = 'REPLAY',
    'Replay did not preserve same-CanonicalMatch lineage'
  );
end;
$body$;
rollback to savepoint r4d_suspension_replay;

savepoint r4d_suspension_administrative_result;
do $body$
declare suspension_id uuid;
declare admin_decision_id uuid;
declare official_decision_id uuid;
begin
  perform pg_temp.prepare_in_progress_match();
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd45b0000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'suspension.report',
    '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":37,"partialScoreHome":1,"partialScoreAway":0,"reasonCode":"SAFETY_STOP","reasonText":"El partido no puede continuar.","publicSummary":"Partido suspendido 1-0."}'::jsonb
  );
  select id into suspension_id from public.pachanga_competition_match_suspensions
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45b0000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'suspension.confirm',
    jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'SUSPENSION_CONFIRMED')
  );
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45b0000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'suspension.resolve',
    jsonb_build_object(
      'suspensionId', suspension_id,
      'resolutionType', 'PENDING_ADMINISTRATIVE_DECISION',
      'reasonCode', 'NO_RESUMPTION_POSSIBLE',
      'publicSummary', 'Pendiente de resolución administrativa.'
    )
  );
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000002',
    'd45b0000-0000-4000-8000-000000000004', pg_temp.context_revision(),
    'administrative_decision.publish',
    jsonb_build_object(
      'decisionType', 'SET_OFFICIAL_RESULT',
      'suspensionId', suspension_id,
      'reasonCode', 'PARTIAL_RESULT_CONFIRMED',
      'reasonText', 'La autoridad valida el marcador parcial conservado por el servidor.',
      'publicSummary', 'Resultado administrativo: 1-0.'
    )
  );
  select decisions.id into admin_decision_id
  from public.pachanga_competition_administrative_decisions decisions
  where decisions.target_type = 'MATCH_SUSPENSION'
    and decisions.decision_type = 'SET_OFFICIAL_RESULT'
  order by decisions.server_sequence desc, decisions.id desc limit 1;
  select decisions.id into official_decision_id
  from public.pachanga_competition_official_result_decisions decisions
  where decisions.operational_source_type = 'MATCH_SUSPENSION'
  order by decisions.server_sequence desc, decisions.id desc limit 1;
  perform pg_temp.assert_true(
    admin_decision_id is not null and official_decision_id is not null
      and (select outcome = 'SUSPENDED_MATCH_DECISION' and effective_score_home = 1
        and effective_score_away = 0 and sporting_result_revision_id is null
        from public.pachanga_competition_official_result_decisions
        where id = official_decision_id)
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'official'
      and exists (select 1 from public.pachanga_competition_standing_snapshots)
      and (select count(*) from public.pachanga_canonical_matches) = 1
      and not exists (select 1 from private.pachanga_conduct_reports)
      and not exists (select 1 from private.pachanga_moderation_cases),
    'Administrative suspension result was not derived from the server snapshot'
  );
end;
$body$;
rollback to savepoint r4d_suspension_administrative_result;

savepoint r4d_suspension_cancel;
do $body$
declare suspension_id uuid;
begin
  perform pg_temp.prepare_in_progress_match();
  perform pg_temp.command_replay(
    'c4010000-0000-4000-8000-000000000003',
    'd45c0000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'suspension.report',
    '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":8,"partialScoreHome":0,"partialScoreAway":0,"reasonCode":"FACILITY_CLOSED","reasonText":"La instalación ordena el cierre.","publicSummary":"Partido suspendido."}'::jsonb
  );
  select id into suspension_id from public.pachanga_competition_match_suspensions
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45c0000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'suspension.cancel',
    jsonb_build_object(
      'suspensionId', suspension_id, 'cancellationOutcome', 'NO_RESULT',
      'reasonCode', 'MATCH_CANCELLED', 'publicSummary', 'Partido cancelado sin resultado.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_suspensions
      where id = suspension_id) = 'cancelled'
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'cancelled'
      and not exists (select 1 from public.pachanga_competition_official_result_decisions),
    'Suspension cancellation invented a result'
  );
end;
$body$;
rollback to savepoint r4d_suspension_cancel;

savepoint r4d_administrative_supersession;
do $body$
declare first_decision_id uuid;
begin
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45d0000-0000-4000-8000-000000000001', pg_temp.context_revision(),
    'administrative_decision.publish',
    '{"decisionType":"RESCHEDULE_MATCH","scheduledStart":"2027-03-06T19:00:00Z","scheduledEnd":"2027-03-06T20:10:00Z","timezone":"Europe/Madrid","reasonCode":"ADMIN_RESCHEDULE","publicSummary":"Nueva fecha administrativa."}'::jsonb
  );
  select id into first_decision_id
  from public.pachanga_competition_administrative_decisions
  order by server_sequence desc, id desc limit 1;
  perform pg_temp.command_replay(
    'd4010000-0000-4000-8000-000000000010',
    'd45d0000-0000-4000-8000-000000000002', pg_temp.context_revision(),
    'administrative_decision.supersede',
    jsonb_build_object(
      'decisionType', 'RESCHEDULE_MATCH', 'previousDecisionId', first_decision_id,
      'scheduledStart', '2027-03-07T19:00:00Z',
      'scheduledEnd', '2027-03-07T20:10:00Z',
      'timezone', 'Europe/Madrid', 'reasonCode', 'ADMIN_RESCHEDULE_CORRECTED',
      'publicSummary', 'Fecha administrativa corregida.'
    )
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_administrative_decisions
      where id = first_decision_id) = 'superseded'
      and (select count(*) from public.pachanga_competition_administrative_decisions
        where status = 'published') = 1
      and (select scheduled_start from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = '2027-03-07T19:00:00Z'::timestamptz
      and (select count(*) from public.pachanga_competition_fixture_change_revisions) = 2,
    'Administrative supersession did not preserve decision lineage'
  );
end;
$body$;
rollback to savepoint r4d_administrative_supersession;

savepoint r4d_negative_authority;
do $body$
declare reused_operation uuid := 'd45e0000-0000-4000-8000-000000000001';
begin
  update public.pachanga_competition_match_contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() + interval '30 minutes',
    scheduled_end = clock_timestamp() + interval '100 minutes'
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.expect_command_failure(
    'c4010000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'late_arrival.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"TOO_EARLY"}'::jsonb,
    'R4D_LATE_ARRIVAL_NOT_REPORTABLE'
  );
  perform pg_temp.expect_command_failure(
    'c4010000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'no_show.report',
    '{"responsibleEntryId":"c4200000-0000-4000-8000-000000000012","reasonCode":"TOO_EARLY","reasonText":"Aún no ha vencido el margen."}'::jsonb,
    'R4D_GRACE_DEADLINE_NOT_REACHED'
  );
  perform pg_temp.expect_command_failure(
    'c4010000-0000-4000-8000-000000000003', pg_temp.context_revision(),
    'suspension.report',
    '{"reportingEntryId":"c4200000-0000-4000-8000-000000000011","reportedMinute":1,"partialScoreHome":0,"partialScoreAway":0,"reasonCode":"NOT_STARTED","reasonText":"No iniciado."}'::jsonb,
    'R4D_SUSPENSION_REQUIRES_STARTED_MATCH'
  );
  perform pg_temp.expect_command_failure(
    'c4010000-0000-4000-8000-000000000007', pg_temp.context_revision(),
    'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"OUTSIDER"}'::jsonb,
    'TEAM_OWNER_OR_PRIMARY_DELEGATE_REQUIRED|FORBIDDEN'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000011', pg_temp.context_revision(),
    'fixture.cancel',
    '{"cancellationOutcome":"NO_RESULT","reasonCode":"SCHEDULE_MANAGER"}'::jsonb,
    'OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000012', pg_temp.context_revision(),
    'fixture.cancel',
    '{"cancellationOutcome":"NO_RESULT","reasonCode":"RESULT_MANAGER"}'::jsonb,
    'OPERATIONS_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision() - 1,
    'fixture.cancel',
    '{"cancellationOutcome":"NO_RESULT","reasonCode":"STALE"}'::jsonb,
    'STALE_REVISION'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'fixture.reschedule',
    '{"scheduledStart":"2028-01-02T19:00:00Z","scheduledEnd":"2028-01-02T20:10:00Z","timezone":"Europe/Madrid","reasonCode":"OUTSIDE_STAGE"}'::jsonb,
    'OUTSIDE_STAGE|OUTSIDE_EDITION'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'fixture.reschedule',
    '{"scheduledStart":"2027-03-08T20:00:00Z","scheduledEnd":"2027-03-08T19:00:00Z","timezone":"Europe/Madrid","reasonCode":"INVALID_DURATION"}'::jsonb,
    'INVALID|DURATION'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'administrative_decision.publish',
    '{"decisionType":"SET_OFFICIAL_RESULT","scoreHome":9,"scoreAway":0,"reasonCode":"CLIENT_SCORE"}'::jsonb,
    'R4D_CLIENT_AUTHORITY_FIELD_FORBIDDEN'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'administrative_decision.publish',
    '{"decisionType":"DEDUCT_POINTS","reasonCode":"R5_FORBIDDEN"}'::jsonb,
    'FEATURE_NOT_AVAILABLE_UNTIL_R5'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'administrative_decision.publish',
    '{"decisionType":"CREATE_COMPETITION_CHARGE","reasonCode":"BILLING_FORBIDDEN"}'::jsonb,
    'FEATURE_NOT_AVAILABLE_UNTIL_R5'
  );
  perform pg_temp.expect_command_failure(
    'd4010000-0000-4000-8000-000000000010', pg_temp.context_revision(),
    'fixture.cancel',
    '{"actorId":"c4010000-0000-4000-8000-000000000001","cancellationOutcome":"NO_RESULT","reasonCode":"SPOOF"}'::jsonb,
    'R4D_CLIENT_AUTHORITY_FIELD_FORBIDDEN'
  );

  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000003', reused_operation,
    pg_temp.context_revision(), 'postponement.request',
    '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"IDEMPOTENT_BASE"}'::jsonb
  );
  perform pg_temp.expect_failure(
    format(
      'select pg_temp.command(%L::uuid,%L::uuid,%s,%L,%L::jsonb)',
      'c4010000-0000-4000-8000-000000000003', reused_operation,
      pg_temp.context_revision(), 'postponement.request',
      '{"requestingEntryId":"c4200000-0000-4000-8000-000000000011","reasonCode":"MUTATED_REPLAY"}'
    ),
    'IDEMPOTENCY_KEY_REUSED'
  );
end;
$body$;
rollback to savepoint r4d_negative_authority;

do $body$
declare row record;
begin
  for row in
    select before.table_name, before.digest, pg_temp.table_digest(before.table_name::regclass) as current_digest
    from r4d_invariants_before before
  loop
    perform pg_temp.assert_true(
      row.digest = row.current_digest,
      'R4D changed protected authority ' || row.table_name
    );
  end loop;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_canonical_matches) = 1,
    'R4D duplicated CanonicalMatch outside a rolled-back story'
  );
end;
$body$;

rollback;
