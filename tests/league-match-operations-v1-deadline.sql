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
    raise exception 'R4C_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4C_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
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
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_actor_id, 'role', 'authenticated')::text,
    true
  );
  return public.command_pachanga_league_match_operations_v1(
    target_operation_id,
    'c4400000-0000-4000-8000-000000000008',
    target_expected_revision,
    target_action,
    target_payload,
    '{"clientVersion":"4.0.0+r4c-deadline","serviceWorkerVersion":"sw-r4c-deadline","installedMode":"standalone","surface":"r4c_deadline"}'::jsonb
  );
end;
$$;

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_public_calendar_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_public_standings_enabled = true
where singleton;

do $body$
declare context_id constant uuid := 'c4400000-0000-4000-8000-000000000008';
declare home_entry constant uuid := 'c4200000-0000-4000-8000-000000000011';
declare away_entry constant uuid := 'c4200000-0000-4000-8000-000000000012';
declare director constant uuid := 'c4010000-0000-4000-8000-000000000002';
declare home_owner constant uuid := 'c4010000-0000-4000-8000-000000000003';
declare away_owner constant uuid := 'c4010000-0000-4000-8000-000000000004';
declare current_revision bigint;
declare home_squad_id uuid;
declare away_squad_id uuid;
declare sporting_result_id uuid;
declare batch_operation_id constant uuid := 'c4800000-0000-4000-8000-000000000020';
declare child_operation_id uuid;
declare target_now timestamptz;
declare response jsonb;
declare replay jsonb;
declare notification_count integer;
begin
  perform pg_temp.assert_true(
    private.pachanga_league_match_policy_v1('c4200000-0000-4000-8000-000000000003')
      ->> 'confirmationPolicy' = 'AUTO_CONFIRM_AFTER_DEADLINE',
    'Deadline fixture did not use a frozen AUTO_CONFIRM_AFTER_DEADLINE policy'
  );

  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(home_owner, 'c4800000-0000-4000-8000-000000000001', current_revision, 'squad.create', jsonb_build_object('entryId', home_entry));
  select id into home_squad_id from public.pachanga_competition_match_squads where competition_match_context_id = context_id and side = 'HOME';
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(home_owner, 'c4800000-0000-4000-8000-000000000002', current_revision, 'squad.member.add', jsonb_build_object('squadId', home_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000019', 'memberRole', 'STARTER', 'shirtNumber', 9, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(home_owner, 'c4800000-0000-4000-8000-000000000003', current_revision, 'squad.submit', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000004', current_revision, 'squad.validate', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000005', current_revision, 'squad.lock', jsonb_build_object('squadId', home_squad_id));

  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(away_owner, 'c4800000-0000-4000-8000-000000000006', current_revision, 'squad.create', jsonb_build_object('entryId', away_entry));
  select id into away_squad_id from public.pachanga_competition_match_squads where competition_match_context_id = context_id and side = 'AWAY';
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(away_owner, 'c4800000-0000-4000-8000-000000000007', current_revision, 'squad.member.add', jsonb_build_object('squadId', away_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000020', 'memberRole', 'STARTER', 'shirtNumber', 10, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(away_owner, 'c4800000-0000-4000-8000-000000000008', current_revision, 'squad.submit', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000009', current_revision, 'squad.validate', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000010', current_revision, 'squad.lock', jsonb_build_object('squadId', away_squad_id));

  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command('c4010000-0000-4000-8000-000000000005', 'c4800000-0000-4000-8000-000000000011', current_revision, 'attendance.set', jsonb_build_object('entryId', home_entry, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000019', 'status', 'going'));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command('c4010000-0000-4000-8000-000000000006', 'c4800000-0000-4000-8000-000000000012', current_revision, 'attendance.set', jsonb_build_object('entryId', away_entry, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000020', 'status', 'going'));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(home_owner, 'c4800000-0000-4000-8000-000000000013', current_revision, 'attendance.close', jsonb_build_object('entryId', home_entry));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(away_owner, 'c4800000-0000-4000-8000-000000000014', current_revision, 'attendance.close', jsonb_build_object('entryId', away_entry));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000015', current_revision, 'match.mark_ready');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000016', current_revision, 'match.start');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  perform pg_temp.command(director, 'c4800000-0000-4000-8000-000000000017', current_revision, 'match.mark_played');

  select revision into current_revision from public.pachanga_competition_match_contexts where id = context_id;
  response := pg_temp.command(home_owner, 'c4800000-0000-4000-8000-000000000018', current_revision, 'sporting_result.submit', jsonb_build_object(
    'entryId', home_entry,
    'scoreHome', 3,
    'scoreAway', 2,
    'scorers', jsonb_build_array(jsonb_build_object('rosterMemberId', 'c4200000-0000-4000-8000-000000000019', 'goals', 3))
  ));
  select id into sporting_result_id from public.pachanga_competition_sporting_results where competition_match_context_id = context_id;

  update public.pachanga_competition_sporting_results
  set response_deadline = clock_timestamp() - interval '1 minute'
  where id = sporting_result_id;
  target_now := clock_timestamp();

  perform set_config('request.jwt.claims', jsonb_build_object('sub', home_owner, 'role', 'authenticated')::text, true);
  perform pg_temp.expect_failure(
    format(
      'select public.process_pachanga_league_result_deadlines_v1(%L::uuid,%L::timestamptz,10,%L::jsonb)',
      batch_operation_id, target_now, '{}'
    ),
    'SERVICE_AUTHORITY_REQUIRED'
  );
  perform pg_temp.assert_true(
    not has_function_privilege('authenticated', 'public.process_pachanga_league_result_deadlines_v1(uuid,timestamptz,integer,jsonb)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.process_pachanga_league_result_deadlines_v1(uuid,timestamptz,integer,jsonb)', 'EXECUTE'),
    'Deadline processor grants are not service-only'
  );

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  response := public.process_pachanga_league_result_deadlines_v1(
    batch_operation_id,
    target_now,
    10,
    '{"clientVersion":"service-r4c-deadline","surface":"deadline_processor","ignoredPii":"must-not-persist"}'::jsonb
  );
  select receipts.operation_id into child_operation_id
  from private.pachanga_competition_operation_receipts receipts
  where receipts.action = 'sporting_result.deadline_auto_confirm'
    and receipts.aggregate_id = context_id::text;
  select count(*) into notification_count
  from public.pachanga_user_notifications notifications
  where notifications.dedupe_key like 'r4c:' || child_operation_id::text || ':%';
  replay := public.process_pachanga_league_result_deadlines_v1(
    batch_operation_id,
    target_now,
    10,
    '{"clientVersion":"service-r4c-deadline","surface":"deadline_processor","ignoredPii":"must-not-persist"}'::jsonb
  );

  perform pg_temp.assert_true(response = replay, 'Deadline batch replay diverged');
  perform pg_temp.assert_true(response ->> 'processedCount' = '1' and response ->> 'skippedCount' = '0', 'Deadline batch did not process exactly one result');
  perform pg_temp.assert_true(
    (select events.event_payload ->> 'autoOfficial'
      from private.pachanga_competition_events events
      where events.operation_id = child_operation_id) = 'true',
    'Deadline policy did not auto-officialize'
  );
  perform pg_temp.assert_true(
    response #> '{results,0,invalidations}' @> jsonb_build_array(
      jsonb_build_object('entityType', 'round', 'entityId', 'c4400000-0000-4000-8000-000000000003')
    ),
    'Deadline auto-officialization omitted the round invalidation'
  );
  perform pg_temp.assert_true(
    (select state from public.pachanga_competition_sporting_results where id = sporting_result_id) = 'official'
      and (select status from public.pachanga_competition_match_contexts where id = context_id) = 'official'
      and (select count(*) from public.pachanga_competition_official_result_decisions where competition_match_context_id = context_id) = 1,
    'Deadline auto-confirm did not converge to one official decision'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_standing_states where stage_id = 'c4200000-0000-4000-8000-000000000006') = 1
      and (select count(*) from public.pachanga_competition_standing_rows) = 2,
    'Deadline auto-officialization did not materialize standings'
  );
  perform pg_temp.assert_true(
    notification_count = (
      select count(*)
      from public.pachanga_user_notifications notifications
      where notifications.dedupe_key like 'r4c:' || child_operation_id::text || ':%'
    ),
    'Deadline replay duplicated notifications'
  );
  perform pg_temp.assert_true(
    (select receipts.client_metadata ? 'ignoredPii'
      from private.pachanga_competition_operation_receipts receipts
      where receipts.operation_id = batch_operation_id) = false,
    'Deadline processor persisted metadata outside the allowlist'
  );
end;
$body$;
