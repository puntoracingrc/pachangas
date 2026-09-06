\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email) values
 ('f9610000-0000-4000-8000-000000000001','identity-a@example.test'),
 ('f9610000-0000-4000-8000-000000000002','identity-b@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values
 ('f9610000-0000-4000-8000-000000000010','f9610000-0000-4000-8000-000000000001','Identity QA','IDQA9601',
 '{"players":[{"id":"owned-player","name":"Same display name","ownerUserId":"f9610000-0000-4000-8000-000000000001"}],"matches":[]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
 ('f9610000-0000-4000-8000-000000000010','f9610000-0000-4000-8000-000000000001','owner','Same display name'),
 ('f9610000-0000-4000-8000-000000000010','f9610000-0000-4000-8000-000000000002','player','Same display name');
select set_config('request.jwt.claims','{"sub":"f9610000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
do $$ begin
 begin
   perform public.upsert_pachanga_own_player_profile_authoritative_v2('f9610000-0000-4000-8000-000000000010','owned-player','{"name":"Claimed by B"}','f9610000-0000-4000-8000-000000000020',0,'{}');
   raise exception 'Unexpected successful ownership claim';
 exception when others then
   if sqlerrm <> 'This player profile already belongs to another user' then raise; end if;
 end;
 begin
   perform public.patch_pachanga_player_profile_authoritative_v2('f9610000-0000-4000-8000-000000000010','owned-player','{"name":"Edited by B"}','f9610000-0000-4000-8000-000000000021',0,'{}');
   raise exception 'Unexpected successful edit';
 exception when others then
   if sqlerrm <> 'You can only edit your own player profile' then raise; end if;
 end;
end $$;
reset role;
do $$ begin
 if (select payload->'players'->0->>'name' from public.pachanga_groups where id='f9610000-0000-4000-8000-000000000010') <> 'Same display name' then raise exception 'Player was changed'; end if;
end $$;
rollback;
\echo PASS: same-named second account cannot claim or edit the existing owned player
