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
  ('91000000-0000-0000-0000-000000000001', 'notification-owner-a@example.test'),
  ('91000000-0000-0000-0000-000000000002', 'notification-player-a@example.test'),
  ('91000000-0000-0000-0000-000000000003', 'notification-owner-b@example.test'),
  ('91000000-0000-0000-0000-000000000004', 'notification-new-member@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    '92000000-0000-0000-0000-000000000001',
    '91000000-0000-0000-0000-000000000001',
    'Avisos Local', 'AVISOA',
    '{"players":[{"id":"p1","name":"Ana","ownerUserId":"91000000-0000-0000-0000-000000000001"},{"id":"p2","name":"Pablo","ownerUserId":"91000000-0000-0000-0000-000000000002"}],"matches":[{"id":"match-alert-1","name":"Jueves 21:00","configured":true,"players":[]}]}'::jsonb
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    '91000000-0000-0000-0000-000000000003',
    'Avisos Rival', 'AVISOB',
    '{"players":[],"matches":[]}'::jsonb
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 'owner', 'Ana'),
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002', 'player', 'Pablo'),
  ('92000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000003', 'owner', 'Berta');

select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_notification_preferences', 'SELECT'),
  'Authenticated users need read access to their own preference rows'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_notification_preferences', 'UPDATE'),
  'Clients must not update notification preferences directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_notification_delivery_outbox', 'SELECT'),
  'The delivery outbox must remain private'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
reset role;

create temporary table notification_test_preference_results (
  default_preferences jsonb not null,
  preference_saved jsonb not null,
  preference_replayed jsonb not null
) on commit drop;
grant select, insert on table notification_test_preference_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
insert into notification_test_preference_results(
  default_preferences,
  preference_saved,
  preference_replayed
)
select
  public.get_pachanga_notification_preferences_v1(),
  public.update_pachanga_notification_preferences_v1(
    'group', false, false, false, 0,
    '93000000-0000-0000-0000-000000000001'
  ),
  public.update_pachanga_notification_preferences_v1(
    'group', false, false, false, 0,
    '93000000-0000-0000-0000-000000000001'
  );
reset role;

select pg_temp.assert_true(
  (select jsonb_array_length(default_preferences)
   from notification_test_preference_results) = 6,
  'The preference read model must always expose all six categories'
);
select pg_temp.assert_true(
  (select preference_saved = preference_replayed
   from notification_test_preference_results),
  'Repeating one preference operation must replay the exact canonical response'
);
select pg_temp.assert_true(
  (select count(*) from private.pachanga_notification_preference_receipts
   where operation_id = '93000000-0000-0000-0000-000000000001') = 1,
  'An idempotent preference update must create one receipt'
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000004', 'player', 'Nico');

select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000001'
      and notifications.kind = 'group_member_joined'
      and notifications.payload ->> 'memberUserId' = '91000000-0000-0000-0000-000000000004'
      and not notifications.visible_in_app
  ),
  'Optional group notices must respect an explicit in-app opt-out'
);

delete from public.pachanga_group_members
where group_id = '92000000-0000-0000-0000-000000000001'
  and user_id = '91000000-0000-0000-0000-000000000004';

select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000001'
      and notifications.kind = 'group_member_removed'
      and notifications.mandatory_in_app
      and notifications.visible_in_app
  ),
  'Critical membership changes must remain visible despite the category opt-out'
);

insert into public.pachanga_group_events(
  group_id, match_id, operation_id, actor_id, event_type, payload
) values (
  '92000000-0000-0000-0000-000000000001', 'match-alert-1',
  '93000000-0000-0000-0000-000000000010', '91000000-0000-0000-0000-000000000002',
  'match_attendance_changed', '{"playerId":"p2","status":"no","payloadRevision":1}'::jsonb
);

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.dedupe_key like 'attendance-event:%'
      and notifications.payload ->> 'status' = 'no'
  ),
  'A direct No voy without a previous Voy must not notify the group'
);

insert into public.pachanga_group_events(
  group_id, match_id, operation_id, actor_id, event_type, payload
) values
  (
    '92000000-0000-0000-0000-000000000001', 'match-alert-1',
    '93000000-0000-0000-0000-000000000011', '91000000-0000-0000-0000-000000000002',
    'match_attendance_changed', '{"playerId":"p2","status":"voy","payloadRevision":2}'::jsonb
  ),
  (
    '92000000-0000-0000-0000-000000000001', 'match-alert-1',
    '93000000-0000-0000-0000-000000000012', '91000000-0000-0000-0000-000000000002',
    'match_attendance_changed', '{"playerId":"p2","status":"voy","payloadRevision":3}'::jsonb
  ),
  (
    '92000000-0000-0000-0000-000000000001', 'match-alert-1',
    '93000000-0000-0000-0000-000000000013', '91000000-0000-0000-0000-000000000002',
    'match_attendance_changed', '{"playerId":"p2","status":"no","payloadRevision":4}'::jsonb
  );

select pg_temp.assert_true(
  (select count(*) from public.pachanga_user_notifications notifications
   where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000001'
     and notifications.kind = 'match_attendance_joined') = 1,
  'Repeated Voy events must not create duplicate attendance notices'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_user_notifications notifications
   where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000001'
     and notifications.kind = 'match_attendance_cancelled') = 1,
  'Voy to No voy must create exactly one attendance change notice'
);

insert into public.pachanga_player_profiles(id, user_id, source_group_id, display_name, position)
values (
  '94000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002',
  '92000000-0000-0000-0000-000000000001',
  'Pablo', 'Mediocentro / pivote'
);
update public.pachanga_player_profiles
set injured = true
where id = '94000000-0000-0000-0000-000000000001';

select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000001'
      and notifications.kind = 'player_availability_unavailable'
      and notifications.body = 'Pablo no está disponible.'
  ),
  'Availability changes must notify without medical details'
);

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, scheduled_at, modality,
  field_name, field_address, last_proposed_by_group_id, created_by, updated_by
) values (
  '95000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002',
  clock_timestamp() + interval '5 days', 'futbol7', 'Campo Avisos', 'Carrer Test, 1',
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001'
);
insert into public.pachanga_team_challenge_events(
  challenge_id, operation_id, actor_user_id, actor_group_id,
  event_type, challenge_revision, snapshot
) values (
  '95000000-0000-0000-0000-000000000001',
  '93000000-0000-0000-0000-000000000020',
  '91000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  'created', 1, '{}'::jsonb
);

select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000003'
      and notifications.kind = 'team_challenge_created'
      and notifications.priority = 'critical'
      and notifications.mandatory_in_app
  ),
  'A new challenge must notify the opposing admins as a critical action'
);

select private.pachanga_notify_v1(
  '91000000-0000-0000-0000-000000000001',
  'personal_achievement_reward', 'Texto filtrado', 'Logro secreto filtrado',
  '/equipo/identidad?reward=test', '{"rewardGrantId":"test"}'::jsonb,
  'notification-test-achievement'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.dedupe_key = 'notification-test-achievement'
      and notifications.title = 'Nuevo logro desbloqueado'
      and notifications.body = 'Toca para descubrirlo.'
      and notifications.category = 'achievement'
  ),
  'Achievement notifications must not reveal the reward before opening'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = '91000000-0000-0000-0000-000000000003'
  ),
  'RLS must hide notifications belonging to another user'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.kind = 'group_member_joined'
      and notifications.payload ->> 'memberUserId' = '91000000-0000-0000-0000-000000000004'
  ),
  'RLS must hide optional notifications disabled by the recipient'
);
reset role;

rollback;
