\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('91000000-0000-0000-0000-000000000001', 'core-owner@example.test'),
  ('91000000-0000-0000-0000-000000000002', 'core-admin@example.test'),
  ('91000000-0000-0000-0000-000000000003', 'core-player@example.test'),
  ('91000000-0000-0000-0000-000000000004', 'core-reserve@example.test'),
  ('91000000-0000-0000-0000-000000000005', 'core-outsider@example.test'),
  ('91000000-0000-0000-0000-000000000006', 'core-invitee@example.test'),
  ('91000000-0000-0000-0000-000000000007', 'core-rival-owner@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, invite_token, payload) values
  (
    '92000000-0000-0000-0000-000000000001',
    '91000000-0000-0000-0000-000000000001',
    'Core Social Local', 'COREA1', '93000000-0000-0000-0000-000000000001',
    jsonb_build_object(
      'activeMatchId', 'core-future',
      'players', jsonb_build_array(
        jsonb_build_object('id','p-owner','name','Owner','ownerUserId','91000000-0000-0000-0000-000000000001','rating',7,'inactive',false),
        jsonb_build_object('id','p-admin','name','Admin','ownerUserId','91000000-0000-0000-0000-000000000002','rating',7,'inactive',false),
        jsonb_build_object('id','p-player','name','Player','ownerUserId','91000000-0000-0000-0000-000000000003','rating',6,'inactive',false),
        jsonb_build_object('id','p-reserve','name','Reserve','ownerUserId','91000000-0000-0000-0000-000000000004','rating',6,'inactive',false)
      ),
      'matches', jsonb_build_array(
        jsonb_build_object(
          'id','core-history','title','Historico','date',to_char(clock_timestamp() - interval '30 days','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'configured',true,'closed',true,'scoreA',2,'scoreB',1,'targetPlayers',1,
          'players',jsonb_build_array(jsonb_build_object('playerId','p-player','status','voy','paid',true)),
          'teamA',jsonb_build_array('p-player'),'teamB','[]'::jsonb,
          'scorers',jsonb_build_array(jsonb_build_object('playerId','p-player','goals',2))
        ),
        jsonb_build_object(
          'id','core-future','title','Futuro','date',to_char(clock_timestamp() + interval '7 days','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
          'configured',true,'lineupClosed',false,'targetPlayers',1,'reserveLimit',1,'reservesAttend',true,
          'players',jsonb_build_array(
            jsonb_build_object('playerId','p-player','status','voy','paid',false,'joinedAt','2030-01-01T10:00:00.000Z'),
            jsonb_build_object('playerId','p-reserve','status','voy','paid',false,'joinedAt','2030-01-01T10:01:00.000Z')
          ),
          'teamA',jsonb_build_array('p-player'),'teamB','[]'::jsonb,
          'scorers','[]'::jsonb,'payerId','p-player','publicOpen',false,'publicOpenSlots',0
        )
      ),
      'siteSettings','{}'::jsonb,'venues','[]'::jsonb
    )
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    '91000000-0000-0000-0000-000000000007',
    'Core Social Rival', 'COREB1', '93000000-0000-0000-0000-000000000002',
    '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','owner','Owner'),
  ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002','admin','Admin'),
  ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003','player','Player'),
  ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000004','player','Reserve'),
  ('92000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000007','owner','Rival owner');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name,
  calibrated_overall, current_overall, calibrated_facets, current_facets, rating_engine_version
) values (
  '94000000-0000-0000-0000-000000000003','91000000-0000-0000-0000-000000000003',
  '92000000-0000-0000-0000-000000000001','p-player','Player',66,66,
  '{"pace":66,"shooting":66,"passing":66,"dribbling":66,"defending":66,"physical":66}'::jsonb,
  '{"pace":66,"shooting":66,"passing":66,"dribbling":66,"defending":66,"physical":66}'::jsonb,
  'pachangas-rating-v2'
);

insert into private.pachanga_moderation_cases(
  id, target_profile_id, target_user_id, source_type, category, state
) values (
  '95000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000003',
  '91000000-0000-0000-0000-000000000003','conduct_report','other','restricted'
);
insert into private.pachanga_social_restrictions(
  id, case_id, target_user_id, restriction_type, duration_days, state, applied_by, effective_until
) values (
  '95000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000003','public_market',7,'active',
  '91000000-0000-0000-0000-000000000001',clock_timestamp() + interval '7 days'
);

select payload_revision as leave_revision
from public.pachanga_groups where id = '92000000-0000-0000-0000-000000000001' \gset

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000003',true);
select public.leave_pachanga_group_authoritative_v1(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001',
  :leave_revision,'{"sessionId":"leave-device-a"}'::jsonb
) as leave_response \gset
select public.leave_pachanga_group_authoritative_v1(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001',
  :leave_revision,'{"sessionId":"leave-device-a"}'::jsonb
) as leave_replay \gset
reset role;

select pg_temp.assert_true(:'leave_response'::jsonb = :'leave_replay'::jsonb, 'Leave retry must replay exactly');
select pg_temp.assert_true(not exists (
  select 1 from public.pachanga_group_members where group_id='92000000-0000-0000-0000-000000000001' and user_id='91000000-0000-0000-0000-000000000003'
), 'Player membership must be removed');
select pg_temp.assert_true((select current_overall from public.pachanga_player_profiles where id='94000000-0000-0000-0000-000000000003')=66, 'Rating V2 must survive leaving');
select pg_temp.assert_true((select state from private.pachanga_social_restrictions where id='95000000-0000-0000-0000-000000000002')='active', 'Social restriction must survive leaving');
select pg_temp.assert_true((select count(*) from public.pachanga_player_profiles where user_id='91000000-0000-0000-0000-000000000003')=1, 'Universal identity must remain unique');
select pg_temp.assert_true((select players.value->>'status' from public.pachanga_groups groups cross join lateral jsonb_array_elements(groups.payload->'matches') matches(value) cross join lateral jsonb_array_elements(matches.value->'players') players(value) where groups.id='92000000-0000-0000-0000-000000000001' and matches.value->>'id'='core-future' and players.value->>'playerId'='p-player')='no', 'Future attendance must be withdrawn');
select pg_temp.assert_true((select matches.value->'teamA' from public.pachanga_groups groups cross join lateral jsonb_array_elements(groups.payload->'matches') matches(value) where groups.id='92000000-0000-0000-0000-000000000001' and matches.value->>'id'='core-future')='[]'::jsonb, 'Future lineup must remove the departed player');
select pg_temp.assert_true((select matches.value->'teamA' from public.pachanga_groups groups cross join lateral jsonb_array_elements(groups.payload->'matches') matches(value) where groups.id='92000000-0000-0000-0000-000000000001' and matches.value->>'id'='core-history')=jsonb_build_array('p-player'), 'Historical lineup must remain immutable');
select pg_temp.assert_true((select count(*) from public.pachanga_group_events where operation_id='96000000-0000-0000-0000-000000000001')=1, 'Leave must emit one event');
select pg_temp.assert_true(exists (select 1 from public.pachanga_user_notifications where kind='group_member_left' and payload->>'memberUserId'='91000000-0000-0000-0000-000000000003'), 'Team must receive a non-security leave notification');

select payload_revision as owner_leave_revision from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001' \gset
select set_config('core.owner_leave_revision', :'owner_leave_revision', true);
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$ begin
  perform public.leave_pachanga_group_authoritative_v1('92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000002',current_setting('core.owner_leave_revision',true)::bigint,'{}'::jsonb);
exception when others then
  if sqlerrm not like 'Transfer ownership%' then raise; end if;
end $$;
reset role;

select payload_revision as transfer_revision from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
select public.transfer_pachanga_group_ownership_authoritative_v1(
  '92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000002',
  '96000000-0000-0000-0000-000000000003',:transfer_revision,'{"sessionId":"owner-device"}'::jsonb
) as transfer_response \gset
reset role;
select pg_temp.assert_true((select owner_id from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001')='91000000-0000-0000-0000-000000000002', 'Ownership must transfer explicitly');
select pg_temp.assert_true((select role from public.pachanga_group_members where group_id='92000000-0000-0000-0000-000000000001' and user_id='91000000-0000-0000-0000-000000000001')='admin', 'Previous owner must remain admin');

select payload_revision as former_owner_leave_revision from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
select public.leave_pachanga_group_authoritative_v1(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000004',
  :former_owner_leave_revision,'{"sessionId":"former-owner-device"}'::jsonb
);
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000003',true);
select public.join_pachanga_team('93000000-0000-0000-0000-000000000001','Player');
reset role;

select pg_temp.assert_true((select count(*) from public.pachanga_group_members where group_id='92000000-0000-0000-0000-000000000001' and user_id='91000000-0000-0000-0000-000000000003')=1, 'Rejoin must restore exactly one membership');
select pg_temp.assert_true((select count(*) from public.pachanga_player_profiles where user_id='91000000-0000-0000-0000-000000000003')=1, 'Rejoin must not duplicate universal identity');
select pg_temp.assert_true(not (select (players.value->>'inactive')::boolean from public.pachanga_groups groups cross join lateral jsonb_array_elements(groups.payload->'players') players(value) where groups.id='92000000-0000-0000-0000-000000000001' and players.value->>'id'='p-player'), 'Rejoin must reactivate the existing local player');
select pg_temp.assert_true((select state from private.pachanga_social_restrictions where id='95000000-0000-0000-0000-000000000002')='active', 'Rejoin must not evade person-bound restrictions');

-- Existing lineup authority: reserves can pay, closed lineups block attendance, and reopening is explicit.
select payload_revision as attendance_revision from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001' \gset
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
select public.patch_pachanga_match_player_status_authoritative_v2(
  '92000000-0000-0000-0000-000000000001','core-future','p-player','voy',
  '96000000-0000-0000-0000-000000000005',:attendance_revision,'{"sessionId":"lineup-admin"}'::jsonb
) as attendance_response \gset
select public.patch_pachanga_match_lineup_authoritative_v2(
  '92000000-0000-0000-0000-000000000001','core-future',true,
  array['p-player']::text[],array[]::text[],'p-reserve',
  '96000000-0000-0000-0000-000000000006',
  ((:'attendance_response'::jsonb->>'confirmedRevision')::bigint),'{"sessionId":"lineup-admin"}'::jsonb
) as lineup_closed \gset
select set_config('core.closed_revision', (:'lineup_closed'::jsonb->>'confirmedRevision'), true);
do $$ begin
  perform public.patch_pachanga_match_player_status_authoritative_v2(
    '92000000-0000-0000-0000-000000000001','core-future','p-player','no',
    '96000000-0000-0000-0000-000000000007',
    (current_setting('core.closed_revision'))::bigint,'{}'::jsonb
  );
  raise exception 'Closed lineup unexpectedly accepted attendance mutation';
exception when others then
  if sqlerrm = 'Closed lineup unexpectedly accepted attendance mutation' then raise; end if;
  if sqlerrm not like '%lineup is closed%'
    and sqlerrm not like '%Open the lineup before changing attendance%'
    and sqlerrm not like '%alineaci%n%cerrada%'
  then raise; end if;
end $$;
reset role;

select pg_temp.assert_true((:'lineup_closed'::jsonb->>'confirmedRevision')::bigint > (:'attendance_response'::jsonb->>'confirmedRevision')::bigint, 'Lineup close must advance the canonical revision');

-- Admin invitation keeps one transition under same-operation and different-device replay.
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
select public.create_pachanga_admin_invite(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000008'
) as admin_token \gset
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000006',true);
select public.accept_pachanga_admin_invite_authoritative_v1(
  :'admin_token'::uuid,'Invitee','96000000-0000-0000-0000-000000000009',1,
  '{"sessionId":"invite-device-a"}'::jsonb
) as admin_accepted \gset
select public.accept_pachanga_admin_invite_authoritative_v1(
  :'admin_token'::uuid,'Invitee','96000000-0000-0000-0000-000000000009',1,
  '{"sessionId":"invite-device-a"}'::jsonb
) as admin_replay \gset
select public.accept_pachanga_admin_invite_authoritative_v1(
  :'admin_token'::uuid,'Invitee','96000000-0000-0000-0000-000000000010',1,
  '{"sessionId":"invite-device-b"}'::jsonb
) as admin_second_device \gset
reset role;

select pg_temp.assert_true(:'admin_accepted'::jsonb=:'admin_replay'::jsonb, 'Admin invite operation retry must replay exactly');
select pg_temp.assert_true((select role from public.pachanga_group_members where group_id='92000000-0000-0000-0000-000000000001' and user_id='91000000-0000-0000-0000-000000000006')='admin', 'Admin invite must grant admin, never owner');
select pg_temp.assert_true((select count(*) from public.pachanga_group_events where event_type='admin_invite_accepted' and payload->>'inviteId'=(select id::text from public.pachanga_admin_invites where token=:'admin_token'::uuid))=1, 'Admin invite acceptance must emit one event');
select set_config('core.used_admin_token', :'admin_token', true);

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000005',true);
do $$ begin
  perform public.accept_pachanga_admin_invite_authoritative_v1(
    current_setting('core.used_admin_token')::uuid,'Outsider','96000000-0000-0000-0000-000000000011',2,'{}'::jsonb
  );
  raise exception 'Another user unexpectedly reused an accepted admin token';
exception when others then
  if sqlerrm = 'Another user unexpectedly reused an accepted admin token' then raise; end if;
  if sqlerrm not like '%another user%' then raise; end if;
end $$;
reset role;

-- Server-time challenge expiry is lazy, auditable and does not create sporting evidence.
insert into public.pachanga_team_challenges(
  id,sender_group_id,receiver_group_id,status,scheduled_at,modality,field_name,field_address,
  last_proposed_by_group_id,created_by,updated_by
) values (
  '97000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000002','proposed',clock_timestamp()-interval '1 minute',
  'futbol7','Camp expiry','Carrer expiry 1','92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002'
);

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
select public.get_pachanga_team_social_snapshot('92000000-0000-0000-0000-000000000001') as expired_snapshot \gset
select public.get_pachanga_team_social_snapshot('92000000-0000-0000-0000-000000000001');
reset role;

select pg_temp.assert_true((select status from public.pachanga_team_challenges where id='97000000-0000-0000-0000-000000000001')='expired', 'Due challenge must expire by server time');
select pg_temp.assert_true((select count(*) from public.pachanga_team_challenge_events where challenge_id='97000000-0000-0000-0000-000000000001' and event_type='expired')=1, 'Repeated reconciliation must emit one expiry event');
select pg_temp.assert_true((select actor_user_id from public.pachanga_team_challenge_events where challenge_id='97000000-0000-0000-0000-000000000001' and event_type='expired') is null, 'Lazy expiry must be recorded as a system transition');
select pg_temp.assert_true((select count(*) from public.pachanga_known_opponents where group_id in ('92000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000002'))=0, 'Expired challenge must not create a known opponent');
select pg_temp.assert_true((select count(*) from public.pachanga_match_rating_snapshots where match_id='97000000-0000-0000-0000-000000000001')=0, 'Expired challenge must create no Rating or Season evidence');
select pg_temp.assert_true(exists (select 1 from public.pachanga_user_notifications where kind='team_challenge_expired' and payload->>'challengeId'='97000000-0000-0000-0000-000000000001'), 'Challenge admins must receive one expiry notification');

-- A stale active marketplace row is closed and every pending request is resolved server-side.
insert into public.pachanga_open_matches(
  id,source_group_id,source_match_id,source_payload_revision,group_name,title,date,modality,
  field_name,target_players,confirmed_count,open_slots,active,created_by
) values (
  '98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  'cancelled-or-started',0,'Core Social Local','Started match',clock_timestamp()-interval '1 minute',
  'futbol7','Past field',7,4,3,true,'91000000-0000-0000-0000-000000000002'
);
insert into public.pachanga_market_profiles(
  id,user_id,source_player_id,display_name,position,modalities,active
) values (
  '98000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000005',
  'market-outsider','Outsider','Defensa central',array['futbol7'],true
);
insert into public.pachanga_open_match_requests(
  id,open_match_id,source_group_id,source_match_id,requester_user_id,requester_profile_id,
  requester_name,status
) values (
  '98000000-0000-0000-0000-000000000003','98000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001','cancelled-or-started','91000000-0000-0000-0000-000000000005',
  '98000000-0000-0000-0000-000000000002','Outsider','pending'
);
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000005',true);
select public.search_pachanga_open_matches_v1();
reset role;
select pg_temp.assert_true(not (select active from public.pachanga_open_matches where id='98000000-0000-0000-0000-000000000001'), 'Started market row must close');
select pg_temp.assert_true((select status from public.pachanga_open_match_requests where id='98000000-0000-0000-0000-000000000003')='rejected', 'Pending request must close with the market');

select pg_temp.assert_true(not has_function_privilege('authenticated','private.pachanga_depart_group_member_v1(uuid,uuid,uuid,bigint,text,jsonb)','EXECUTE'), 'Private membership mutation must not be client-callable');
select pg_temp.assert_true(not has_function_privilege('authenticated','private.pachanga_expire_team_challenge_v1(uuid,uuid)','EXECUTE'), 'Private expiry must not be client-callable');
select pg_temp.assert_true(has_function_privilege('authenticated','public.leave_pachanga_group_authoritative_v1(uuid,uuid,bigint,jsonb)','EXECUTE'), 'Authenticated client needs canonical self-leave RPC');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.pachanga_group_members','DELETE'), 'Direct membership DELETE must remain closed');

-- Expired tokens, existing owners and adversarial actors cannot escalate authority.
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
select public.create_pachanga_admin_invite(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000012'
) as expired_admin_token \gset
select public.create_pachanga_admin_invite(
  '92000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000013'
) as owner_admin_token \gset
select public.accept_pachanga_admin_invite_authoritative_v1(
  :'owner_admin_token'::uuid,'Current owner','96000000-0000-0000-0000-000000000014',1,'{}'::jsonb
) as owner_admin_accept \gset
reset role;
update public.pachanga_admin_invites set expires_at=clock_timestamp()-interval '1 second' where token=:'expired_admin_token'::uuid;
select pg_temp.assert_true(:'owner_admin_accept'::jsonb->>'role'='owner', 'An existing owner must never be demoted by an admin invite');

select set_config('core.expired_admin_token', :'expired_admin_token', true);
select set_config('core.adversarial_revision', (select payload_revision::text from public.pachanga_groups where id='92000000-0000-0000-0000-000000000001'), true);
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000005',true);
do $$ begin
  perform public.accept_pachanga_admin_invite_authoritative_v1(
    current_setting('core.expired_admin_token')::uuid,'Outsider','96000000-0000-0000-0000-000000000015',1,'{}'::jsonb
  );
  raise exception 'Expired admin invite unexpectedly accepted';
exception when others then
  if sqlerrm='Expired admin invite unexpectedly accepted' then raise; end if;
end $$;
do $$ begin
  perform public.remove_pachanga_group_member_authoritative_v1(
    '92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003',
    '96000000-0000-0000-0000-000000000016',current_setting('core.adversarial_revision')::bigint,'{}'::jsonb
  );
  raise exception 'Unrelated player unexpectedly removed a member';
exception when others then
  if sqlerrm='Unrelated player unexpectedly removed a member' then raise; end if;
end $$;
do $$ begin
  perform public.transfer_pachanga_group_ownership_authoritative_v1(
    '92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003',
    '96000000-0000-0000-0000-000000000017',current_setting('core.adversarial_revision')::bigint,'{}'::jsonb
  );
  raise exception 'Unrelated player unexpectedly transferred ownership';
exception when others then
  if sqlerrm='Unrelated player unexpectedly transferred ownership' then raise; end if;
end $$;
do $$ begin
  perform public.reconcile_pachanga_team_challenge_expiry_v1(
    '92000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000001',
    '96000000-0000-0000-0000-000000000018',2,'{}'::jsonb
  );
  raise exception 'Unrelated player unexpectedly reconciled a challenge';
exception when others then
  if sqlerrm='Unrelated player unexpectedly reconciled a challenge' then raise; end if;
end $$;
do $$ begin
  perform public.patch_pachanga_match_lineup_authoritative_v2(
    '92000000-0000-0000-0000-000000000001','core-future',false,array['p-player']::text[],array[]::text[],'p-reserve',
    '96000000-0000-0000-0000-000000000019',current_setting('core.adversarial_revision')::bigint,'{}'::jsonb
  );
  raise exception 'Unrelated player unexpectedly edited a lineup';
exception when others then
  if sqlerrm='Unrelated player unexpectedly edited a lineup' then raise; end if;
end $$;
do $$ begin
  perform public.review_pachanga_open_match_request_authoritative_v2(
    '92000000-0000-0000-0000-000000000001','98000000-0000-0000-0000-000000000003','accepted',
    '96000000-0000-0000-0000-000000000020',current_setting('core.adversarial_revision')::bigint,'{}'::jsonb
  );
  raise exception 'Unrelated player unexpectedly accepted another team request';
exception when others then
  if sqlerrm='Unrelated player unexpectedly accepted another team request' then raise; end if;
end $$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
do $$ begin
  perform public.sync_pachanga_open_match_authoritative_v2(
    '92000000-0000-0000-0000-000000000001','cancelled-or-started',
    '{"active":true,"targetPlayers":7,"openSlots":3}'::jsonb,
    '96000000-0000-0000-0000-000000000021',current_setting('core.adversarial_revision')::bigint,'{}'::jsonb
  );
  raise exception 'Past market unexpectedly reopened';
exception when others then
  if sqlerrm='Past market unexpectedly reopened' then raise; end if;
end $$;
reset role;

rollback;
