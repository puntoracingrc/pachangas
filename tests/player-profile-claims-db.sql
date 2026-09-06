\set ON_ERROR_STOP on
begin;
\ir ../supabase/migrations/20260901214523_social_profile_foundation_v1.sql
\ir ../supabase/migrations/20260902064632_social_inbox_authority_v1.sql
\ir ../supabase/migrations/20260906155901_player_profile_claim_approval_v1.sql
insert into auth.users(id,email) values
('f9620000-0000-4000-8000-000000000001','claim-admin@example.test'),
('f9620000-0000-4000-8000-000000000002','claim-player@example.test'),
('f9620000-0000-4000-8000-000000000003','claim-rival@example.test'),
('f9620000-0000-4000-8000-000000000004','claim-outsider@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values
('f9620000-0000-4000-8000-000000000010','f9620000-0000-4000-8000-000000000001','Claim QA','CLQA9601',
'{"players":[{"id":"manual","name":"Alberto M","avatar":"https://example.test/photo.png","rating":6,"goals":5,"appearances":3},{"id":"other-manual","name":"Otro"}],"matches":[{"id":"match-history","configured":true,"date":"2099-09-06T18:00:00Z","teamA":["manual"],"players":[{"playerId":"manual","status":"voy"}],"scorers":[{"playerId":"manual","goals":5}]}]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
('f9620000-0000-4000-8000-000000000010','f9620000-0000-4000-8000-000000000001','owner','Admin'),
('f9620000-0000-4000-8000-000000000010','f9620000-0000-4000-8000-000000000002','player','Same name'),
('f9620000-0000-4000-8000-000000000010','f9620000-0000-4000-8000-000000000003','player','Same name');
-- Existing canonical profile must survive approval unchanged, including its rating.
insert into public.pachanga_player_profiles(id,user_id,display_name,rating,avatar,stats) values
('f9620000-0000-4000-8000-000000000030','f9620000-0000-4000-8000-000000000002','My existing profile',7,'https://example.test/own.png','{"goals":9}');
-- Even the owner cannot approve their own identity request.
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','other-manual')->>'requestId' as self_claim \gset
select set_config('test.claim', :'self_claim',true);
do $$ begin
 begin perform public.decide_pachanga_player_claim_v1(current_setting('test.claim')::uuid,'approve'); raise exception 'Self approval succeeded'; exception when others then if sqlerrm<>'ANOTHER_ADMIN_REQUIRED' then raise; end if; end;
end $$;
select public.decide_pachanga_player_claim_v1(:'self_claim','cancel');
reset role;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
-- Old direct claim RPC must be blocked before approval, even for an unowned player.
do $$ begin
 begin
  perform public.upsert_pachanga_own_player_profile_authoritative_v2('f9620000-0000-4000-8000-000000000010','manual','{"name":"stolen"}','f9620000-0000-4000-8000-000000000020',0,'{}');
  raise exception 'Old RPC bypassed approval';
 exception when others then if sqlerrm<>'PLAYER_CLAIM_APPROVAL_REQUIRED' then raise; end if; end;
end $$;
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','manual')->>'requestId' as claim_a \gset
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','manual')->>'requestId' = :'claim_a' as idempotent \gset
\if :idempotent
\else
 \quit 1
\endif
select public.get_pachanga_player_claims_v1('f9620000-0000-4000-8000-000000000010');
reset role;
do $$ begin
 if not exists(select 1 from public.pachanga_user_notifications n where n.kind='player_profile_claim_requested' and n.payload->>'groupId'='f9620000-0000-4000-8000-000000000010' and private.pachanga_social_inbox_descriptor_v1(n.id,n.recipient_user_id)->>'attentionState'='ACTION_REQUIRED') then raise exception 'No actionable inbox notice'; end if;
end $$;
set local role authenticated;

select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',true);
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','manual')->>'requestId' as claim_b \gset
-- A normal member cannot review another account's request.
select set_config('test.claim', :'claim_a',true);
do $$ begin
 begin perform public.decide_pachanga_player_claim_v1(current_setting('test.claim')::uuid,'approve'); raise exception 'Member approved a claim';
 exception when others then if sqlerrm<>'TEAM_ADMIN_REQUIRED' then raise; end if; end;
 if jsonb_array_length(public.get_pachanga_player_claims_v1('f9620000-0000-4000-8000-000000000010')->'requests')<>1 then raise exception 'Leaked other requester'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}',true);
do $$ begin
 begin perform public.get_pachanga_player_claims_v1('f9620000-0000-4000-8000-000000000010'); raise exception 'Outsider read claims'; exception when others then if sqlerrm<>'TEAM_MEMBERSHIP_REQUIRED' then raise; end if; end;
 begin perform public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','manual'); raise exception 'Outsider requested'; exception when others then if sqlerrm<>'TEAM_MEMBERSHIP_REQUIRED' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select public.decide_pachanga_player_claim_v1(:'claim_a','approve');
select public.decide_pachanga_player_claim_v1(:'claim_a','approve');
reset role;
do $$ declare g jsonb; p public.pachanga_player_profiles%rowtype; begin
 select payload into g from public.pachanga_groups where id='f9620000-0000-4000-8000-000000000010';
 if g->'players'->0->>'ownerUserId'<>'f9620000-0000-4000-8000-000000000002' or g->'players'->0->>'globalPlayerProfileId'<>'f9620000-0000-4000-8000-000000000030' then raise exception 'Wrong binding'; end if;
 if g->'players'->0->>'goals'<>'5' or g->'players'->0->>'appearances'<>'3' or g->'players'->0->>'name'<>'Alberto M' or g->'matches'->0->'teamA'->>0<>'manual' then raise exception 'Lost history'; end if;
 select * into p from public.pachanga_player_profiles where user_id='f9620000-0000-4000-8000-000000000002';
 if p.rating<>7 or p.display_name<>'My existing profile' or p.stats->>'goals'<>'9' then raise exception 'Existing profile overwritten'; end if;
 if (select count(*) from public.pachanga_player_profiles where user_id=p.user_id)<>1 then raise exception 'Duplicate canonical profile'; end if;
 if (select state from private.pachanga_player_claims_v1 where requester_id='f9620000-0000-4000-8000-000000000003')<>'SUPERSEDED' then raise exception 'Competitor not closed'; end if;
 -- Even a raw server-side mutation cannot reassign an approved owner.
 begin update public.pachanga_groups set payload=jsonb_set(payload,'{players,0,ownerUserId}','"f9620000-0000-4000-8000-000000000003"') where id='f9620000-0000-4000-8000-000000000010'; raise exception 'Reassigned owner'; exception when others then if sqlerrm<>'PLAYER_OWNER_IMMUTABLE' then raise; end if; end;
 -- Ordinary administrative edits remain possible after linking.
 update public.pachanga_groups set payload=jsonb_set(payload,'{players,0,injured}','true') where id='f9620000-0000-4000-8000-000000000010';
 if (select count(*) from public.pachanga_user_notifications where kind='player_profile_claim_requested' and payload->>'groupId'='f9620000-0000-4000-8000-000000000010')<>2 then raise exception 'Missing admin notices'; end if;
 if exists(select 1 from public.pachanga_user_notifications where kind='player_profile_claim_requested' and payload->>'groupId'='f9620000-0000-4000-8000-000000000010' and read_at is null) then raise exception 'Pending admin notice not closed'; end if;
end $$;
-- Admin can still cancel and restore attendance for the now-owned player.
update public.pachanga_groups set payload=jsonb_set(payload,'{players,0,injured}','false') where id='f9620000-0000-4000-8000-000000000010';
select payload_revision as attendance_revision from public.pachanga_groups where id='f9620000-0000-4000-8000-000000000010' \gset
set local role authenticated;
select public.patch_pachanga_match_player_status_authoritative_v2('f9620000-0000-4000-8000-000000000010','match-history','manual','no','f9620000-0000-4000-8000-000000000051',:attendance_revision,'{}');
reset role;
select payload_revision as attendance_revision from public.pachanga_groups where id='f9620000-0000-4000-8000-000000000010' \gset
set local role authenticated;
select public.patch_pachanga_match_player_status_authoritative_v2('f9620000-0000-4000-8000-000000000010','match-history','manual','voy','f9620000-0000-4000-8000-000000000052',:attendance_revision,'{}');
reset role;
do $$ begin
 if (select payload->'matches'->0->'players'->0->>'status' from public.pachanga_groups where id='f9620000-0000-4000-8000-000000000010')<>'voy' then raise exception 'Admin attendance failed'; end if;
end $$;

-- Cancellation / retry / rejection / requester leaving are safe and don't bind ownership.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',true);
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','other-manual')->>'requestId' as retry_claim \gset
select public.decide_pachanga_player_claim_v1(:'retry_claim','cancel');
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','other-manual')->>'requestId' as retry_claim \gset
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select public.decide_pachanga_player_claim_v1(:'retry_claim','reject');
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',true);
select public.request_pachanga_player_claim_v1('f9620000-0000-4000-8000-000000000010','other-manual')->>'requestId' as retry_claim \gset
reset role;
delete from public.pachanga_group_members where group_id='f9620000-0000-4000-8000-000000000010' and user_id='f9620000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select set_config('test.claim', :'retry_claim',true);
do $$ begin
 begin perform public.decide_pachanga_player_claim_v1(current_setting('test.claim')::uuid,'approve'); raise exception 'Approved departed user'; exception when others then if sqlerrm<>'REQUESTER_LEFT_TEAM' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"f9620000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}',true);
do $$ begin
 begin perform public.get_pachanga_player_claims_v1('f9620000-0000-4000-8000-000000000010'); raise exception 'Anonymous read'; exception when others then if sqlerrm<>'REGISTERED_USER_REQUIRED' then raise; end if; end;
end $$;
reset role;
rollback;
\echo PASS: approved claims preserve history and existing profiles; bypass, privacy, competing claims, retries and revoked membership verified
