create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.capture_social_inbox_error(target_notice uuid)
returns text
language plpgsql
as $$
begin
  perform public.command_pachanga_social_inbox_v1(
    'inbox.mark_read', target_notice,
    'a3000000-0000-0000-0000-000000000099', 1, null
  );
  return 'NO_ERROR';
exception when others then
  return sqlstate;
end;
$$;

insert into auth.users(id, email) values
  ('a1000000-0000-0000-0000-000000000001', 'inbox-owner-a@example.test'),
  ('a1000000-0000-0000-0000-000000000002', 'inbox-owner-b@example.test'),
  ('a1000000-0000-0000-0000-000000000003', 'inbox-player-b@example.test');

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, social_modality,
  social_general_area, social_target_player_count
) values
  (
    'a2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'Inbox Local A', 'INBOXA', '{"players":[],"matches":[]}'::jsonb,
    'futbol7', 'Barcelona', 14
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000002',
    'Inbox Local B', 'INBOXB', '{"players":[],"matches":[]}'::jsonb,
    'futbol7', 'Barcelona', 14
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'owner', 'Owner A'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000002', 'owner', 'Owner B'),
  ('a2000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'player', 'Player B');

delete from public.pachanga_user_notifications
where recipient_user_id in (
  'a1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002',
  'a1000000-0000-0000-0000-000000000003'
);

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, scheduled_at, modality,
  field_name, field_address, last_proposed_by_group_id, created_by, updated_by
) values (
  'a4000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000002',
  clock_timestamp() + interval '5 days', 'futbol7',
  'Campo Inbox', 'Carrer Test, 1',
  'a2000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000001'
);

select private.pachanga_notify_v1(
  'a1000000-0000-0000-0000-000000000002',
  'team_challenge_created', 'Nuevo reto recibido',
  'Inbox Local A os ha retado.', 'javascript:alert(1)',
  jsonb_build_object('challengeId', 'a4000000-0000-0000-0000-000000000001'),
  'social-inbox-test:challenge'
);

select private.pachanga_notify_v1(
  'a1000000-0000-0000-0000-000000000002',
  'group_member_joined', 'Nuevo jugador', 'Player B se ha unido.',
  'https://evil.example.test/redirect',
  jsonb_build_object(
    'groupId', 'a2000000-0000-0000-0000-000000000002',
    'memberUserId', 'a1000000-0000-0000-0000-000000000003'
  ),
  'social-inbox-test:member'
);

select private.pachanga_notify_v1(
  'a1000000-0000-0000-0000-000000000002',
  'league_fixture_changed', 'Jornada modificada', 'Aviso avanzado.',
  '/ligas/secret', '{"competitionId":"private"}'::jsonb,
  'social-inbox-test:advanced'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);

create temporary table social_inbox_test_results (
  key text primary key,
  value jsonb not null
) on commit drop;

insert into social_inbox_test_results values
  ('initial', public.get_my_pachanga_social_inbox_v1('pending', null, 25, null, null, null));

select pg_temp.assert_true(
  (select (value ->> 'pendingCount')::integer = 1 from social_inbox_test_results where key = 'initial'),
  'One unresolved challenge must be pending'
);
select pg_temp.assert_true(
  (select (value ->> 'unreadCount')::integer = 2 from social_inbox_test_results where key = 'initial'),
  'Advanced notices must not contribute to the social unread count'
);
select pg_temp.assert_true(
  (select value #>> '{items,0,deepLink}' = '/retos?view=active&reto=a4000000-0000-0000-0000-000000000001'
   from social_inbox_test_results where key = 'initial'),
  'The server must replace a forged action URL with an allowlisted deep link'
);
select pg_temp.assert_true(
  (select value::text not like '%payload%' and value::text not like '%recipient_user_id%'
   from social_inbox_test_results where key = 'initial'),
  'The read model must not return raw payloads or recipient identifiers'
);

create temporary table social_inbox_notice_ids as
select dedupe_key, id, revision, server_sequence
from public.pachanga_user_notifications
where dedupe_key in ('social-inbox-test:challenge', 'social-inbox-test:member');

insert into social_inbox_test_results
select 'marked_read', public.command_pachanga_social_inbox_v1(
  'inbox.mark_read', ids.id,
  'a3000000-0000-0000-0000-000000000001', ids.revision, null
)
from social_inbox_notice_ids ids where ids.dedupe_key = 'social-inbox-test:challenge';

insert into social_inbox_test_results
select 'marked_read_replay', public.command_pachanga_social_inbox_v1(
  'inbox.mark_read', ids.id,
  'a3000000-0000-0000-0000-000000000001', ids.revision, null
)
from social_inbox_notice_ids ids where ids.dedupe_key = 'social-inbox-test:challenge';

select pg_temp.assert_true(
  (select left_result.value = right_result.value
   from social_inbox_test_results left_result
   join social_inbox_test_results right_result on right_result.key = 'marked_read_replay'
   where left_result.key = 'marked_read'),
  'Replaying a command must return the exact receipt'
);
select pg_temp.assert_true(
  (select (value #>> '{inbox,pendingCount}')::integer = 1
      and (value #>> '{inbox,unreadCount}')::integer = 1
   from social_inbox_test_results where key = 'marked_read'),
  'Reading an item must not resolve its domain action'
);

insert into social_inbox_test_results
select 'marked_unread', public.command_pachanga_social_inbox_v1(
  'inbox.mark_unread', notifications.id,
  'a3000000-0000-0000-0000-000000000002', notifications.revision, null
)
from public.pachanga_user_notifications notifications
where notifications.dedupe_key = 'social-inbox-test:challenge';

insert into social_inbox_test_results
select 'archived', public.command_pachanga_social_inbox_v1(
  'inbox.archive', notifications.id,
  'a3000000-0000-0000-0000-000000000003', notifications.revision, null
)
from public.pachanga_user_notifications notifications
where notifications.dedupe_key = 'social-inbox-test:challenge';

select pg_temp.assert_true(
  (select (value #>> '{inbox,pendingCount}')::integer = 1
   from social_inbox_test_results where key = 'archived'),
  'Archiving a pending item must not hide the domain obligation from Pending'
);

update public.pachanga_team_challenges
set status = 'accepted', accepted_at = clock_timestamp(), revision = revision + 1
where id = 'a4000000-0000-0000-0000-000000000001';

insert into social_inbox_test_results values
  ('resolved', public.get_my_pachanga_social_inbox_v1('pending', null, 25, null, null, null));
select pg_temp.assert_true(
  (select (value ->> 'pendingCount')::integer = 0 from social_inbox_test_results where key = 'resolved'),
  'Canonical Challenge resolution must clear the pending action'
);

insert into social_inbox_test_results values
  ('before_mark_all', public.get_my_pachanga_social_inbox_v1('all', null, 25, null, null, null));

select private.pachanga_notify_v1(
  'a1000000-0000-0000-0000-000000000002',
  'team_shield_updated', 'Escudo actualizado', 'El equipo tiene una nueva identidad.',
  '/equipo', jsonb_build_object('groupId', 'a2000000-0000-0000-0000-000000000002'),
  'social-inbox-test:concurrent'
);

insert into social_inbox_test_results
select 'mark_all', public.command_pachanga_social_inbox_v1(
  'inbox.mark_all_read', null,
  'a3000000-0000-0000-0000-000000000004', null,
  (value ->> 'serverSequence')::bigint
)
from social_inbox_test_results where key = 'before_mark_all';

select pg_temp.assert_true(
  (select read_at is null from public.pachanga_user_notifications
   where dedupe_key = 'social-inbox-test:concurrent'),
  'A notice created after the confirmed snapshot must remain unread'
);

update public.pachanga_user_notifications
set created_at = '2026-09-02 08:00:00+00'
where dedupe_key in ('social-inbox-test:member', 'social-inbox-test:concurrent');

insert into social_inbox_test_results values
  ('page_one', public.get_my_pachanga_social_inbox_v1('all', 'TEAM', 1, null, null, null));

insert into social_inbox_test_results
select 'page_two', public.get_my_pachanga_social_inbox_v1(
  'all', 'TEAM', 1,
  (value #>> '{nextCursor,sortRank}')::integer,
  (value #>> '{nextCursor,serverSequence}')::bigint,
  (value #>> '{nextCursor,notificationId}')::uuid
)
from social_inbox_test_results where key = 'page_one';

select pg_temp.assert_true(
  (select first.value #>> '{items,0,id}' <> second.value #>> '{items,0,id}'
   from social_inbox_test_results first
   join social_inbox_test_results second on second.key = 'page_two'
   where first.key = 'page_one'),
  'Stable cursor pagination must not repeat rows sharing a timestamp'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000001', true);
select pg_temp.assert_true(
  pg_temp.capture_social_inbox_error((
    select id from public.pachanga_user_notifications
    where dedupe_key = 'social-inbox-test:concurrent'
  )) = 'P0002',
  'A user must not mutate another recipient notification'
);
select pg_temp.assert_true(
  (public.get_my_pachanga_social_inbox_v1('all', null, 25, null, null, null) ->> 'unreadCount')::integer = 0,
  'An owner or platform role must still receive only its own social Inbox'
);

select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.get_my_pachanga_social_inbox_v1(text,text,integer,integer,bigint,uuid)', 'EXECUTE'),
  'Authenticated users need read RPC access'
);
select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.command_pachanga_social_inbox_v1(text,uuid,uuid,bigint,bigint)', 'EXECUTE'),
  'Authenticated users need command RPC access'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_user_notifications', 'UPDATE'),
  'Clients must not update notification rows directly'
);
select pg_temp.assert_true(
  not has_table_privilege('anon', 'public.pachanga_user_notifications', 'SELECT'),
  'Anonymous clients must not read private notifications'
);
select pg_temp.assert_true(
  (select count(*) = 4 from private.pachanga_social_inbox_command_receipts_v1
   where actor_user_id = 'a1000000-0000-0000-0000-000000000002'),
  'Each unique write must retain one audit receipt'
);
