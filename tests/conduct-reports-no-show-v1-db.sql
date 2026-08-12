\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('91000000-0000-0000-0000-000000000001', 'conduct-owner@example.test'),
  ('91000000-0000-0000-0000-000000000002', 'conduct-target@example.test'),
  ('91000000-0000-0000-0000-000000000003', 'conduct-third@example.test'),
  ('91000000-0000-0000-0000-000000000004', 'conduct-outsider@example.test'),
  ('91000000-0000-0000-0000-000000000005', 'conduct-moderator@example.test');

insert into public.pachanga_player_profiles(id, user_id, source_group_id, source_player_id, display_name) values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', null, 'owner-player', 'Conduct Owner'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', null, 'target-player', 'Conduct Target'),
  ('92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', null, 'third-player', 'Conduct Third');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  '93000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  'Conduct test group',
  'CONDV1TEST',
  jsonb_build_object(
    'activeMatchId', 'conduct-match-1',
    'players', jsonb_build_array(
      jsonb_build_object('id', 'owner-player', 'name', 'Conduct Owner', 'ownerUserId', '91000000-0000-0000-0000-000000000001', 'globalPlayerProfileId', '92000000-0000-0000-0000-000000000001'),
      jsonb_build_object('id', 'target-player', 'name', 'Conduct Target', 'ownerUserId', '91000000-0000-0000-0000-000000000002', 'globalPlayerProfileId', '92000000-0000-0000-0000-000000000002'),
      jsonb_build_object('id', 'third-player', 'name', 'Conduct Third', 'ownerUserId', '91000000-0000-0000-0000-000000000003', 'globalPlayerProfileId', '92000000-0000-0000-0000-000000000003')
    ),
    'matches', jsonb_build_array(jsonb_build_object(
      'id', 'conduct-match-1', 'title', 'Conduct completed match',
      'date', to_char(clock_timestamp() - interval '1 hour', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'kind', 'futbol7', 'configured', true, 'lineupClosed', true, 'closed', true,
      'scoreA', 2, 'scoreB', 1, 'targetPlayers', 3, 'reserveLimit', 0, 'reservesAttend', false,
      'players', jsonb_build_array(
        jsonb_build_object('playerId', 'owner-player', 'status', 'voy', 'joinedAt', to_char(clock_timestamp() - interval '3 hours', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        jsonb_build_object('playerId', 'target-player', 'status', 'voy', 'joinedAt', to_char(clock_timestamp() - interval '2 hours 59 minutes', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        jsonb_build_object('playerId', 'third-player', 'status', 'voy', 'joinedAt', to_char(clock_timestamp() - interval '2 hours 58 minutes', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
      ),
      'teamA', jsonb_build_array('owner-player', 'target-player'),
      'teamB', jsonb_build_array('third-player')
    ))
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'owner', 'Conduct Owner'),
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002', 'player', 'Conduct Target'),
  ('93000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000003', 'player', 'Conduct Third');

update public.pachanga_player_profiles
set source_group_id = '93000000-0000-0000-0000-000000000001'
where id in (
  '92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002',
  '92000000-0000-0000-0000-000000000003'
);

select public.sync_pachanga_match_read_model(
  '93000000-0000-0000-0000-000000000001',
  (select matches.value from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(groups.payload -> 'matches') matches(value)
    where groups.id = '93000000-0000-0000-0000-000000000001'
      and matches.value ->> 'id' = 'conduct-match-1'),
  1
);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  '93000000-0000-0000-0000-000000000002',
  '91000000-0000-0000-0000-000000000003',
  'Second conduct test group',
  'CONDV1TWO',
  jsonb_build_object(
    'activeMatchId', 'conduct-match-2',
    'players', jsonb_build_array(
      jsonb_build_object('id', 'third-player-2', 'name', 'Conduct Third', 'ownerUserId', '91000000-0000-0000-0000-000000000003', 'globalPlayerProfileId', '92000000-0000-0000-0000-000000000003'),
      jsonb_build_object('id', 'target-player-2', 'name', 'Conduct Target', 'ownerUserId', '91000000-0000-0000-0000-000000000002', 'globalPlayerProfileId', '92000000-0000-0000-0000-000000000002')
    ),
    'matches', jsonb_build_array(jsonb_build_object(
      'id', 'conduct-match-2', 'title', 'Second completed match',
      'date', to_char(clock_timestamp() - interval '2 hours', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'kind', 'futbol7', 'configured', true, 'lineupClosed', true, 'closed', true,
      'scoreA', 1, 'scoreB', 1, 'targetPlayers', 2, 'reserveLimit', 0, 'reservesAttend', false,
      'players', jsonb_build_array(
        jsonb_build_object('playerId', 'third-player-2', 'status', 'voy', 'joinedAt', to_char(clock_timestamp() - interval '4 hours', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
        jsonb_build_object('playerId', 'target-player-2', 'status', 'voy', 'joinedAt', to_char(clock_timestamp() - interval '3 hours 59 minutes', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
      ),
      'teamA', jsonb_build_array('third-player-2'),
      'teamB', jsonb_build_array('target-player-2')
    ))
  );
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000003', 'owner', 'Conduct Third'),
  ('93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'player', 'Conduct Target');
select public.sync_pachanga_match_read_model(
  '93000000-0000-0000-0000-000000000002',
  (select matches.value from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(groups.payload -> 'matches') matches(value)
    where groups.id = '93000000-0000-0000-0000-000000000002'
      and matches.value ->> 'id' = 'conduct-match-2'),
  1
);

update private.pachanga_conduct_settings set
  attendance_closure_enabled = true,
  conduct_reports_enabled = true,
  attendance_effective_from = clock_timestamp(),
  conduct_effective_from = clock_timestamp(),
  social_restrictions_enabled = false,
  updated_at = clock_timestamp()
where singleton;

create temporary table feature_activation_zero_backfill_before as
select jsonb_build_object(
  'closures', (select count(*) from private.pachanga_attendance_closures),
  'attendance', (select count(*) from private.pachanga_post_match_attendance),
  'reports', (select count(*) from private.pachanga_conduct_reports),
  'cases', (select count(*) from private.pachanga_moderation_cases),
  'notifications', (select count(*) from public.pachanga_user_notifications),
  'receipts', (select count(*) from private.pachanga_conduct_operation_receipts)
) as snapshot;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform public.close_pachanga_post_match_attendance_v1(
    '93000000-0000-0000-0000-000000000001',
    'conduct-match-1',
    '[{"playerId":"owner-player","outcome":"played"},{"playerId":"target-player","outcome":"unexcused_no_show"},{"playerId":"third-player","outcome":"excused_absence"}]'::jsonb,
    '94000000-0000-0000-0000-000000000025', 0, '{}'::jsonb
  );
  raise exception 'Historical attendance unexpectedly crossed its activation frontier';
exception when others then
  if sqlerrm = 'Historical attendance unexpectedly crossed its activation frontier' then raise; end if;
  if sqlerrm <> 'Match predates Attendance activation' then raise; end if;
end;
$$;
do $$
begin
  perform public.submit_pachanga_conduct_report_v1(
    '92000000-0000-0000-0000-000000000002',
    '93000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001',
    'match', 'conduct-match-1', 'other', null,
    '94000000-0000-0000-0000-000000000026',
    (select greatest(match_version, 1) from public.pachanga_match_read_model
      where group_id = '93000000-0000-0000-0000-000000000001' and match_id = 'conduct-match-1'),
    '{}'::jsonb
  );
  raise exception 'Historical conduct unexpectedly crossed its activation frontier';
exception when others then
  if sqlerrm = 'Historical conduct unexpectedly crossed its activation frontier' then raise; end if;
  if sqlerrm <> 'Sporting context predates Conduct activation' then raise; end if;
end;
$$;
reset role;

select pg_temp.assert_true(
  (select snapshot from feature_activation_zero_backfill_before) = jsonb_build_object(
    'closures', (select count(*) from private.pachanga_attendance_closures),
    'attendance', (select count(*) from private.pachanga_post_match_attendance),
    'reports', (select count(*) from private.pachanga_conduct_reports),
    'cases', (select count(*) from private.pachanga_moderation_cases),
    'notifications', (select count(*) from public.pachanga_user_notifications),
    'receipts', (select count(*) from private.pachanga_conduct_operation_receipts)
  ),
  'Activation frontiers must reject historical writes without facts, cases, notifications or receipts'
);

update private.pachanga_conduct_settings set
  attendance_effective_from = clock_timestamp() - interval '3 hours',
  conduct_effective_from = clock_timestamp() - interval '3 hours'
where singleton;

create temporary table conduct_sport_before as
select jsonb_build_object(
  'profile', (select to_jsonb(profiles) - array['created_at', 'updated_at']
    from public.pachanga_player_profiles profiles where id = '92000000-0000-0000-0000-000000000002'),
  'ratingEvidence', (select count(*) from public.pachanga_individual_rating_evidence),
  'ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots),
  'achievements', (select count(*) from public.pachanga_achievement_grants),
  'rewards', (select count(*) from public.pachanga_reward_grants)
) as snapshot;

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_conduct_reports', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_moderation_cases', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_post_match_attendance', 'SELECT'),
  'Authenticated users must not read private conduct identities or facts directly'
);
select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.submit_pachanga_conduct_report_v1(uuid,uuid,uuid,text,text,text,text,uuid,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.submit_pachanga_conduct_report_v1(uuid,uuid,uuid,text,text,text,text,uuid,bigint,jsonb)', 'EXECUTE'),
  'Only authenticated clients may invoke the report intention'
);

select set_config('conduct_test.match_revision', (
  select greatest(match_version, 1)::text from public.pachanga_match_read_model
  where group_id = '93000000-0000-0000-0000-000000000001' and match_id = 'conduct-match-1'
), true);
select set_config('conduct_test.match_2_revision', (
  select greatest(match_version, 1)::text from public.pachanga_match_read_model
  where group_id = '93000000-0000-0000-0000-000000000002' and match_id = 'conduct-match-2'
), true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform count(*) from private.pachanga_conduct_reports;
  raise exception 'An authenticated group owner unexpectedly read private conduct tables';
exception when insufficient_privilege then null;
end;
$$;
do $$
begin
  perform public.close_pachanga_post_match_attendance_v1(
    '93000000-0000-0000-0000-000000000001',
    'conduct-match-1',
    '[{"playerId":"owner-player","outcome":"played"},{"playerId":"target-player","outcome":"unexcused_no_show"}]'::jsonb,
    '94000000-0000-0000-0000-000000000024', 0, '{}'::jsonb
  );
  raise exception 'An incomplete attendance roster unexpectedly closed';
exception when others then
  if sqlerrm = 'An incomplete attendance roster unexpectedly closed' then raise; end if;
  if sqlerrm <> 'Attendance closure must include every canonical match participant exactly once' then raise; end if;
end;
$$;
select public.close_pachanga_post_match_attendance_v1(
  '93000000-0000-0000-0000-000000000001',
  'conduct-match-1',
  '[{"playerId":"owner-player","outcome":"played"},{"playerId":"target-player","outcome":"unexcused_no_show"},{"playerId":"third-player","outcome":"excused_absence"}]'::jsonb,
  '94000000-0000-0000-0000-000000000001', 0,
  '{"clientVersion":"1.0.0+db","serviceWorkerVersion":"db-test","displayMode":"browser","sessionId":"attendance-admin","surface":"sql"}'::jsonb
) as attendance_closed \gset
select public.close_pachanga_post_match_attendance_v1(
  '93000000-0000-0000-0000-000000000001',
  'conduct-match-1',
  '[{"playerId":"owner-player","outcome":"played"},{"playerId":"target-player","outcome":"unexcused_no_show"},{"playerId":"third-player","outcome":"excused_absence"}]'::jsonb,
  '94000000-0000-0000-0000-000000000001', 0, '{}'::jsonb
) as attendance_replayed \gset
reset role;

select pg_temp.assert_true(:'attendance_closed'::jsonb = :'attendance_replayed'::jsonb,
  'Attendance retries must replay the exact canonical response');
select pg_temp.assert_true(jsonb_array_length(:'attendance_closed'::jsonb -> 'facts') = 3,
  'Attendance closure must certify the complete canonical roster');
select set_config('conduct_test.attendance_id', (
  select facts.value ->> 'id' from jsonb_array_elements(:'attendance_closed'::jsonb -> 'facts') facts(value)
  where facts.value ->> 'playerId' = 'target-player'
), true);

-- Regression PFA-002/PFA-003: the real reliability path must count only the
-- selected user and upsert one open case when the third no-show is confirmed.
insert into private.pachanga_attendance_closures(
  id, group_id, match_id, match_occurred_at, state, policy_version, revision,
  opened_by, closed_by, closed_at
) values
  ('95100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'reliability-1', clock_timestamp() - interval '1 hour', 'closed', 'conduct-v1-experimental', 1, '91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', clock_timestamp()),
  ('95100000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', 'reliability-2', clock_timestamp() - interval '1 hour', 'closed', 'conduct-v1-experimental', 1, '91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', clock_timestamp()),
  ('95100000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000001', 'reliability-3', clock_timestamp() - interval '1 hour', 'closed', 'conduct-v1-experimental', 1, '91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', clock_timestamp()),
  ('95100000-0000-0000-0000-000000000004', '93000000-0000-0000-0000-000000000001', 'reliability-other', clock_timestamp() - interval '1 hour', 'closed', 'conduct-v1-experimental', 1, '91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', clock_timestamp());

insert into private.pachanga_post_match_attendance(
  id, closure_id, group_id, match_id, local_player_id, target_profile_id,
  target_user_id, display_name_snapshot, initial_match_status, original_outcome,
  current_outcome, response_state, dispute_deadline, responded_at, certified_by
) values
  ('95200000-0000-0000-0000-000000000001', '95100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'reliability-1', 'target-reliability-1', '92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Conduct Target', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000002', '95100000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', 'reliability-2', 'target-reliability-2', '92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Conduct Target', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000003', '95100000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000001', 'reliability-3', 'target-reliability-3', '92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Conduct Target', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'pending', clock_timestamp() + interval '1 day', null, '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000004', '95100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'reliability-1', 'third-reliability-1', '92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', 'Conduct Third', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000005', '95100000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', 'reliability-2', 'third-reliability-2', '92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', 'Conduct Third', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000006', '95100000-0000-0000-0000-000000000003', '93000000-0000-0000-0000-000000000001', 'reliability-3', 'third-reliability-3', '92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', 'Conduct Third', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000007', '95100000-0000-0000-0000-000000000004', '93000000-0000-0000-0000-000000000001', 'reliability-other', 'third-reliability-4', '92000000-0000-0000-0000-000000000003', '91000000-0000-0000-0000-000000000003', 'Conduct Third', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'agreed', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000008', '95100000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001', 'reliability-1', 'target-dispute-1', '92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Conduct Target', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'under_review', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001'),
  ('95200000-0000-0000-0000-000000000009', '95100000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', 'reliability-2', 'target-dispute-2', '92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002', 'Conduct Target', 'voy', 'unexcused_no_show', 'unexcused_no_show', 'under_review', clock_timestamp() + interval '1 day', clock_timestamp(), '91000000-0000-0000-0000-000000000001');

insert into private.pachanga_attendance_reviews(id, attendance_id, target_user_id, state, player_note)
values
  ('95300000-0000-0000-0000-000000000001', '95200000-0000-0000-0000-000000000008', '91000000-0000-0000-0000-000000000002', 'submitted', 'Synthetic dispute one'),
  ('95300000-0000-0000-0000-000000000002', '95200000-0000-0000-0000-000000000009', '91000000-0000-0000-0000-000000000002', 'submitted', 'Synthetic dispute two');

select private.pachanga_evaluate_attendance_reliability_v1(
  '91000000-0000-0000-0000-000000000002',
  '95000000-0000-0000-0000-000000000001'
);
select pg_temp.assert_true(
  not exists (select 1 from private.pachanga_moderation_cases
    where target_user_id = '91000000-0000-0000-0000-000000000002'
      and source_type = 'attendance_reliability'),
  'No-shows from another user must not push the target over the review threshold'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select public.respond_pachanga_post_match_attendance_v1(
  '95200000-0000-0000-0000-000000000003', 'agree', null,
  '95000000-0000-0000-0000-000000000002', 1, '{}'
) as reliability_threshold_confirmed \gset
reset role;

select pg_temp.assert_true(
  (select count(*) from private.pachanga_moderation_cases
    where target_user_id = '91000000-0000-0000-0000-000000000002'
      and source_type = 'attendance_reliability') = 1,
  'The third confirmed no-show must create one review case'
);
select private.pachanga_evaluate_attendance_reliability_v1(
  '91000000-0000-0000-0000-000000000002',
  '95000000-0000-0000-0000-000000000003'
);
select pg_temp.assert_true(
  (select count(*) = 1 and min(revision) = 2
    from private.pachanga_moderation_cases
    where target_user_id = '91000000-0000-0000-0000-000000000002'
      and source_type = 'attendance_reliability')
  and (select count(*) from private.pachanga_moderation_events events
    join private.pachanga_moderation_cases cases on cases.id = events.case_id
    where cases.target_user_id = '91000000-0000-0000-0000-000000000002'
      and cases.source_type = 'attendance_reliability'
      and events.event_type = 'attendance_review_recommended') = 2
  and (select count(*) from public.pachanga_user_notifications
    where recipient_user_id = '91000000-0000-0000-0000-000000000002'
      and kind = 'attendance_warning_reminder') = 1
  and (select count(*) from private.pachanga_social_restrictions) = 0,
  'Repeated reliability evaluation must update one case, deduplicate reminders and never auto-restrict'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select public.resolve_pachanga_attendance_review_v1(
  '95300000-0000-0000-0000-000000000001', 'escalate', null,
  'Escalation regression one', '95000000-0000-0000-0000-000000000004', 1, '{}'
) as attendance_escalation_one \gset
select public.resolve_pachanga_attendance_review_v1(
  '95300000-0000-0000-0000-000000000002', 'escalate', null,
  'Escalation regression two', '95000000-0000-0000-0000-000000000005', 1, '{}'
) as attendance_escalation_two \gset
reset role;

select pg_temp.assert_true(
  (select count(*) = 1 and min(revision) = 2
    from private.pachanga_moderation_cases
    where target_user_id = '91000000-0000-0000-0000-000000000002'
      and source_type = 'attendance_dispute')
  and (select count(*) from private.pachanga_social_restrictions) = 0,
  'Repeated dispute escalation must update one open case and never auto-restrict'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select public.respond_pachanga_post_match_attendance_v1(
  current_setting('conduct_test.attendance_id')::uuid, 'dispute',
  'Avise al responsable antes del partido.',
  '94000000-0000-0000-0000-000000000002', 1,
  '{"clientVersion":"1.0.0+db","sessionId":"target-device"}'::jsonb
) as attendance_disputed \gset
reset role;

select set_config('conduct_test.review_id', (
  select id::text from private.pachanga_attendance_reviews
  where attendance_id = current_setting('conduct_test.attendance_id')::uuid
), true);
select pg_temp.assert_true(
  (select original_outcome = 'unexcused_no_show' and current_outcome = 'unexcused_no_show'
    and response_state = 'under_review'
    from private.pachanga_post_match_attendance where id = current_setting('conduct_test.attendance_id')::uuid),
  'A dispute must preserve the original no-show while opening a review'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select public.resolve_pachanga_attendance_review_v1(
  current_setting('conduct_test.review_id')::uuid, 'correct', 'excused_absence',
  'La baja justificada se registró fuera del flujo.',
  '94000000-0000-0000-0000-000000000003', 1,
  '{"clientVersion":"1.0.0+db","sessionId":"attendance-admin"}'::jsonb
) as attendance_corrected \gset
reset role;

select pg_temp.assert_true(
  (select original_outcome = 'unexcused_no_show' and current_outcome = 'excused_absence'
    and response_state = 'corrected'
    from private.pachanga_post_match_attendance where id = current_setting('conduct_test.attendance_id')::uuid),
  'A correction must change only the canonical current outcome and preserve the original fact'
);
select pg_temp.assert_true(
  (select count(*) from private.pachanga_attendance_events
    where attendance_id = current_setting('conduct_test.attendance_id')::uuid) = 3,
  'Certification, dispute and correction must remain immutable attendance events'
);
select pg_temp.assert_true(
  exists (select 1 from public.pachanga_user_notifications
    where recipient_user_id = '91000000-0000-0000-0000-000000000002'
      and kind = 'attendance_warning_no_show' and mandatory_in_app),
  'A negative attendance fact must create a mandatory in-app notice'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000004', true);
do $$
begin
  perform public.submit_pachanga_conduct_report_v1(
    '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'other', null,
    '94000000-0000-0000-0000-000000000004', current_setting('conduct_test.match_revision')::bigint, '{}'
  );
  raise exception 'An unrelated outsider unexpectedly reported a player';
exception when others then
  if sqlerrm = 'An unrelated outsider unexpectedly reported a player' then raise; end if;
  if sqlerrm <> 'Reporter must currently belong to the reporting group' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform public.submit_pachanga_conduct_report_v1(
    '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'deliberate_cheating', null,
    '94000000-0000-0000-0000-000000000025', current_setting('conduct_test.match_revision')::bigint + 1, '{}'
  );
  raise exception 'A stale sporting-context revision unexpectedly created a report';
exception when others then
  if sqlerrm = 'A stale sporting-context revision unexpectedly created a report' then raise; end if;
  if sqlstate <> 'PT409' then raise; end if;
end;
$$;
do $$
begin
  perform public.submit_pachanga_conduct_report_v1(
    '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'other', null,
    '94000000-0000-0000-0000-000000000005', current_setting('conduct_test.match_revision')::bigint, '{}'
  );
  raise exception 'A player unexpectedly reported themselves';
exception when others then
  if sqlerrm = 'A player unexpectedly reported themselves' then raise; end if;
  if sqlerrm <> 'Self-reporting is not allowed' then raise; end if;
end;
$$;

select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'abusive_behavior',
  'Comentario privado de prueba.', '94000000-0000-0000-0000-000000000006',
  current_setting('conduct_test.match_revision')::bigint,
  '{"clientVersion":"1.0.0+db","sessionId":"reporter-device","surface":"sql","email":"must-drop@example.test"}'::jsonb
) as report_created \gset
select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'abusive_behavior',
  'Comentario privado de prueba.', '94000000-0000-0000-0000-000000000006',
  current_setting('conduct_test.match_revision')::bigint, '{}'
) as report_replayed \gset
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'abusive_behavior',
  null, '94000000-0000-0000-0000-000000000013',
  current_setting('conduct_test.match_revision')::bigint, '{}'
) as same_team_report \gset
select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002',
  '93000000-0000-0000-0000-000000000002', 'match', 'conduct-match-2', 'abusive_behavior',
  null, '94000000-0000-0000-0000-000000000014',
  current_setting('conduct_test.match_2_revision')::bigint, '{}'
) as independent_team_report \gset
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000001', '93000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'harassment',
  null, '94000000-0000-0000-0000-000000000015',
  current_setting('conduct_test.match_revision')::bigint, '{}'
) as reciprocal_report \gset
reset role;

select set_config('conduct_test.case_reference', (
  select cases.opaque_reference::text
  from private.pachanga_conduct_reports reports
  join private.pachanga_moderation_cases cases on cases.id = reports.case_id
  where reports.operation_id = '94000000-0000-0000-0000-000000000006'
), true);
select set_config('conduct_test.case_revision', (
  select cases.revision::text from private.pachanga_moderation_cases cases
  where cases.opaque_reference = current_setting('conduct_test.case_reference')::uuid
), true);
select set_config('conduct_test.reciprocal_case_reference', (
  select cases.opaque_reference::text
  from private.pachanga_conduct_reports reports
  join private.pachanga_moderation_cases cases on cases.id = reports.case_id
  where reports.operation_id = '94000000-0000-0000-0000-000000000015'
), true);

select pg_temp.assert_true(:'report_created'::jsonb = :'report_replayed'::jsonb,
  'Report retries must replay the exact canonical response');
select pg_temp.assert_true(
  (select count(*) from private.pachanga_conduct_reports where operation_id = '94000000-0000-0000-0000-000000000006') = 1,
  'An idempotent report must create one private report'
);
select pg_temp.assert_true(
  not exists (select 1 from private.pachanga_conduct_operation_receipts
    where operation_id = '94000000-0000-0000-0000-000000000006'
      and client_metadata ? 'email'),
  'Conduct telemetry metadata must drop PII-like fields'
);
select pg_temp.assert_true(
  (select report_count = 3 and independent_source_count = 2
      and correlated_source_count = 1 and source_cluster_count = 2
    from private.pachanga_moderation_cases
    where opaque_reference = current_setting('conduct_test.case_reference')::uuid),
  'Same-team reports must collapse while a second group remains an independent source'
);
select pg_temp.assert_true(
  (select mutual_retaliation from private.pachanga_moderation_cases
    where opaque_reference = current_setting('conduct_test.reciprocal_case_reference')::uuid),
  'A reciprocal report inside the retaliation window must be marked for contextual review'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform public.submit_pachanga_conduct_report_v1(
    '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
    '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'abusive_behavior', null,
    '94000000-0000-0000-0000-000000000007', current_setting('conduct_test.match_revision')::bigint, '{}'
  );
  raise exception 'A duplicate report unexpectedly created another opinion';
exception when others then
  if sqlerrm = 'A duplicate report unexpectedly created another opinion' then raise; end if;
  if sqlerrm <> 'This report already exists' then raise; end if;
end;
$$;
do $$
begin
  perform public.get_pachanga_moderation_case_evidence_v1(current_setting('conduct_test.case_reference')::uuid);
  raise exception 'A group owner unexpectedly read internal reporter identity';
exception when others then
  if sqlerrm = 'A group owner unexpectedly read internal reporter identity' then raise; end if;
  if sqlerrm <> 'Security moderator required' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select public.get_pachanga_my_conduct_v1() as target_conduct \gset
select pg_temp.assert_true(
  :'target_conduct'::jsonb -> 'privacy' ->> 'reporterIdentityVisibleToTarget' = 'false'
  and jsonb_array_length(:'target_conduct'::jsonb -> 'submittedReports') = 1
  and position('91000000-0000-0000-0000-000000000001' in :'target_conduct'::text) = 0
  and position('91000000-0000-0000-0000-000000000003' in :'target_conduct'::text) = 0,
  'The target read model must never reveal reporter identity'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.get_pachanga_moderation_case_evidence_v1(current_setting('conduct_test.case_reference')::uuid) as moderator_evidence \gset
select pg_temp.assert_true(
  :'moderator_evidence'::jsonb -> 'reports' -> 0 ->> 'reporterUserId' = '91000000-0000-0000-0000-000000000001',
  'Only the internal moderator role may resolve private reporter identity'
);
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.case_reference')::uuid, 'start_review', null, '{}', null,
  '94000000-0000-0000-0000-000000000008', current_setting('conduct_test.case_revision')::bigint, '{}'
) as case_reviewing \gset
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.case_reference')::uuid, 'confirm', 'Evidencia contextual confirmada.', '{}', null,
  '94000000-0000-0000-0000-000000000009', (:'case_reviewing'::jsonb ->> 'confirmedRevision')::bigint, '{}'
) as case_confirmed \gset
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.case_reference')::uuid, 'issue_warning', 'Aviso formal revisado.', '{}', null,
  '94000000-0000-0000-0000-000000000010', (:'case_confirmed'::jsonb ->> 'confirmedRevision')::bigint, '{}'
) as warning_issued \gset
select set_config('conduct_test.warning_reference', :'warning_issued'::jsonb -> 'actions' -> 0 ->> 'reference', true);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000002","app_metadata":{}}', true);
select public.appeal_pachanga_conduct_action_v1(
  current_setting('conduct_test.warning_reference')::uuid, 'warning', 'Solicito revisión del contexto.',
  '94000000-0000-0000-0000-000000000011', 1, '{}'
) as warning_appealed \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.resolve_pachanga_conduct_appeal_v1(
  (:'warning_appealed'::jsonb ->> 'appealReference')::uuid, 'correct', 'La apelación aporta contexto suficiente.',
  '94000000-0000-0000-0000-000000000012', 1, '{}'
) as warning_corrected \gset
reset role;

select pg_temp.assert_true(
  (select state from private.pachanga_conduct_warnings where opaque_reference = current_setting('conduct_test.warning_reference')::uuid) = 'corrected',
  'A successful appeal must correct the warning without deleting audit history'
);
select pg_temp.assert_true(
  exists (select 1 from public.pachanga_user_notifications
    where recipient_user_id = '91000000-0000-0000-0000-000000000002'
      and kind in ('conduct_warning_moderation', 'conduct_warning_corrected') and mandatory_in_app),
  'Warnings and corrections must remain mandatory in-app notices'
);

select set_config('conduct_test.reciprocal_case_revision', (
  select revision::text from private.pachanga_moderation_cases
  where opaque_reference = current_setting('conduct_test.reciprocal_case_reference')::uuid
), true);
set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.reciprocal_case_reference')::uuid, 'confirm', 'Caso recíproco revisado.', '{}', null,
  '94000000-0000-0000-0000-000000000016', current_setting('conduct_test.reciprocal_case_revision')::bigint, '{}'
) as reciprocal_confirmed \gset
select set_config('conduct_test.reciprocal_confirmed_revision', :'reciprocal_confirmed'::jsonb ->> 'confirmedRevision', true);
do $$
begin
  perform public.moderate_pachanga_conduct_case_v1(
    current_setting('conduct_test.reciprocal_case_reference')::uuid, 'apply_restrictions',
    'No debe aplicarse con la bandera apagada.', array['public_market'], 7,
    '94000000-0000-0000-0000-000000000017',
    current_setting('conduct_test.reciprocal_confirmed_revision')::bigint, '{}'
  );
  raise exception 'A social restriction unexpectedly bypassed its feature flag';
exception when others then
  if sqlerrm = 'A social restriction unexpectedly bypassed its feature flag' then raise; end if;
  if sqlerrm <> 'Social restrictions are not enabled' then raise; end if;
end;
$$;
reset role;

select pg_temp.assert_true(
  (select count(*) from private.pachanga_social_restrictions) = 0,
  'Reports, triage and confirmation must never create an automatic restriction'
);
update private.pachanga_conduct_settings set social_restrictions_enabled = true where singleton;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.reciprocal_case_reference')::uuid, 'apply_restrictions',
  'Restricción social explícita de prueba.', array['public_market', 'receive_public_challenges', 'public_guest_access'], 7,
  '94000000-0000-0000-0000-000000000018',
  current_setting('conduct_test.reciprocal_confirmed_revision')::bigint, '{}'
) as restriction_applied \gset
reset role;

select set_config('conduct_test.restriction_reference', (
  select opaque_reference::text from private.pachanga_social_restrictions
  where target_user_id = '91000000-0000-0000-0000-000000000001'
    and restriction_type = 'public_market' and state = 'active'
), true);
insert into public.pachanga_team_challenges(
  sender_group_id, receiver_group_id, status, scheduled_at, modality,
  field_name, field_address, last_proposed_by_group_id, created_by, updated_by
) values (
  '93000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001', 'proposed',
  clock_timestamp() + interval '7 days', 'futbol7', 'Conduct challenge field', 'Synthetic address',
  '93000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000003',
  '91000000-0000-0000-0000-000000000003'
) returning id::text as restricted_challenge_id \gset
select set_config('conduct_test.restricted_challenge_id', :'restricted_challenge_id', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","app_metadata":{}}', true);
select public.get_pachanga_social_action_gate_v1() as restricted_gate \gset
select pg_temp.assert_true(
  coalesce((:'restricted_gate'::jsonb -> 'blocked' ->> 'public_market')::boolean, false),
  'An explicitly applied public-market restriction must close only that social gate'
);
do $$
begin
  perform public.respond_pachanga_team_challenge_authoritative(
    '93000000-0000-0000-0000-000000000001', current_setting('conduct_test.restricted_challenge_id')::uuid, 'accept',
    null::timestamptz, null::text, null::text, null::text, null::text, null::text, null::text,
    '94000000-0000-0000-0000-000000000026', 1, '{}'::jsonb
  );
  raise exception 'A receive-challenge restriction unexpectedly allowed acceptance';
exception when others then
  if sqlerrm = 'A receive-challenge restriction unexpectedly allowed acceptance' then raise; end if;
  if sqlerrm <> 'SOCIAL_ACTION_RESTRICTED: receive public challenges' then raise; end if;
end;
$$;
reset role;

do $$
begin
  insert into public.pachanga_match_guest_access(
    group_id, match_id, guest_user_id, player_id, source_kind, source_id, status
  ) values (
    '93000000-0000-0000-0000-000000000002', 'conduct-match-2',
    '91000000-0000-0000-0000-000000000001', 'restricted-guest', 'open_request',
    '94000000-0000-0000-0000-000000000027', 'accepted'
  );
  raise exception 'A public-guest restriction unexpectedly allowed accepted access';
exception when others then
  if sqlerrm = 'A public-guest restriction unexpectedly allowed accepted access' then raise; end if;
  if sqlerrm <> 'SOCIAL_ACTION_RESTRICTED: public guest access' then raise; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","app_metadata":{}}', true);
select public.appeal_pachanga_conduct_action_v1(
  current_setting('conduct_test.restriction_reference')::uuid, 'restriction', 'Solicito revisar la limitación.',
  '94000000-0000-0000-0000-000000000019', 1, '{}'
) as restriction_appealed \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.resolve_pachanga_conduct_appeal_v1(
  (:'restriction_appealed'::jsonb ->> 'appealReference')::uuid, 'correct', 'La restricción queda revocada.',
  '94000000-0000-0000-0000-000000000020', 1, '{}'
) as restriction_corrected \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","app_metadata":{}}', true);
select public.get_pachanga_social_action_gate_v1() as corrected_gate \gset
select pg_temp.assert_true(
  not coalesce((:'corrected_gate'::jsonb -> 'blocked' ->> 'public_market')::boolean, false),
  'A corrected appeal must reopen the affected social capability'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","app_metadata":{}}', true);
select public.submit_pachanga_conduct_report_v1(
  '92000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000001', 'match', 'conduct-match-1', 'threats_or_violence',
  null, '94000000-0000-0000-0000-000000000021',
  current_setting('conduct_test.match_revision')::bigint, '{}'
) as urgent_report \gset
reset role;
select set_config('conduct_test.urgent_case_reference', (
  select cases.opaque_reference::text from private.pachanga_conduct_reports reports
  join private.pachanga_moderation_cases cases on cases.id = reports.case_id
  where reports.operation_id = '94000000-0000-0000-0000-000000000021'
), true);
select set_config('conduct_test.urgent_case_revision', (
  select revision::text from private.pachanga_moderation_cases
  where opaque_reference = current_setting('conduct_test.urgent_case_reference')::uuid
), true);
select pg_temp.assert_true(
  (select priority = 'urgent_review' and state <> 'restricted'
    from private.pachanga_moderation_cases where opaque_reference = current_setting('conduct_test.urgent_case_reference')::uuid),
  'A threat report may become urgent review but must never become an automatic ban'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.urgent_case_reference')::uuid, 'confirm', 'Incidente urgente revisado.', '{}', null,
  '94000000-0000-0000-0000-000000000022', current_setting('conduct_test.urgent_case_revision')::bigint, '{}'
) as urgent_confirmed \gset
select public.moderate_pachanga_conduct_case_v1(
  current_setting('conduct_test.urgent_case_reference')::uuid, 'apply_restrictions',
  'Limitación temporal revisada.', array['public_guest_access'], 7,
  '94000000-0000-0000-0000-000000000023', (:'urgent_confirmed'::jsonb ->> 'confirmedRevision')::bigint, '{}'
) as expiring_restriction \gset
select set_config('conduct_test.expiring_restriction_reference', :'expiring_restriction'::jsonb -> 'actions' -> 0 ->> 'reference', true);
reset role;

update private.pachanga_social_restrictions set effective_until = clock_timestamp() - interval '1 second'
where opaque_reference = current_setting('conduct_test.expiring_restriction_reference')::uuid;
set local role service_role;
select public.run_pachanga_social_restriction_expiry_v1('91000000-0000-0000-0000-000000000002') as restriction_expired \gset
reset role;
select pg_temp.assert_true(
  (:'restriction_expired'::jsonb ->> 'expired')::integer = 1
  and (select state from private.pachanga_social_restrictions
    where opaque_reference = current_setting('conduct_test.expiring_restriction_reference')::uuid) = 'expired',
  'A finite social restriction must expire without deleting its history'
);

select pg_temp.assert_true(
  (select snapshot from conduct_sport_before) = jsonb_build_object(
    'profile', (select to_jsonb(profiles) - array['created_at', 'updated_at']
      from public.pachanga_player_profiles profiles where id = '92000000-0000-0000-0000-000000000002'),
    'ratingEvidence', (select count(*) from public.pachanga_individual_rating_evidence),
    'ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots),
    'achievements', (select count(*) from public.pachanga_achievement_grants),
    'rewards', (select count(*) from public.pachanga_reward_grants)
  ),
  'Attendance, reports, warnings and appeals must not alter Rating V2, facets, achievements or rewards'
);
select pg_temp.assert_true(
  not exists (select 1 from private.pachanga_moderation_events
    where coalesce((payload ->> 'affectsSportRating')::boolean, false)),
  'Every moderation event must remain explicitly outside sporting rating'
);

rollback;
