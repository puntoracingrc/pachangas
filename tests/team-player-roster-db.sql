\set ON_ERROR_STOP on
begin;
-- Synthetic, rolled-back coverage: four players but only two account memberships.
alter table public.pachanga_groups add column if not exists social_modality text;
\ir ../supabase/migrations/20260906150359_team_player_roster_read_v1.sql
insert into auth.users(id,email) values
 ('f9600000-0000-4000-8000-000000000001','roster-owner@example.test'),
 ('f9600000-0000-4000-8000-000000000002','roster-old-access@example.test'),
 ('f9600000-0000-4000-8000-000000000003','roster-outsider@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,social_modality,payload)
values ('f9600000-0000-4000-8000-000000000010','f9600000-0000-4000-8000-000000000001','Roster QA','RSTQA601','futbol7',
'{"players":[{"id":"p1","name":"Jugador uno","ownerUserId":"f9600000-0000-4000-8000-000000000001","avatar":"/qa-avatar.png","position":"DEL","phone":"PRIVATE-PHONE","birthDate":"PRIVATE-DATE","rating":77}, {"id":"p2","name":"Jugador dos"},{"id":"p3","name":"Jugador tres"},{"id":"p4","name":"Jugador cuatro"},{"id":"p5","name":"Baja","inactive":true}]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
 ('f9600000-0000-4000-8000-000000000010','f9600000-0000-4000-8000-000000000001','owner','Old Google name'),
 ('f9600000-0000-4000-8000-000000000010','f9600000-0000-4000-8000-000000000002','player','Old access without player');
select set_config('request.jwt.claims','{"sub":"f9600000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
do $$ declare roster jsonb; begin
 roster := public.get_pachanga_team_players_v1('f9600000-0000-4000-8000-000000000010');
 if jsonb_array_length(roster) <> 4 then raise exception 'Expected four active players'; end if;
 if roster->0->>'displayName' <> 'Jugador uno' or roster->0->>'avatarRef' <> '/qa-avatar.png' then raise exception 'Wrong sporting identity'; end if;
 if roster->0->>'isCurrentUser' <> 'true' or roster->0->>'role' <> 'owner' then raise exception 'Linked owner not resolved'; end if;
 if roster::text ~ 'PRIVATE-|phone|birthDate|ownerUserId|rating|Old access|Old Google|Baja' then raise exception 'Private fields, access accounts or inactive player exposed'; end if;
 if roster->1->>'role' <> 'player' or roster->1->>'isCurrentUser' <> 'false' then raise exception 'Unregistered player missing'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"f9600000-0000-4000-8000-000000000003","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.get_pachanga_team_players_v1('f9600000-0000-4000-8000-000000000010'); raise exception 'Outsider admitted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"f9600000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}',true);
set local role authenticated;
do $$ begin
 begin perform public.get_pachanga_team_players_v1('f9600000-0000-4000-8000-000000000010'); raise exception 'Anonymous user admitted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.get_pachanga_team_players_v1('f9600000-0000-4000-8000-000000000010'); raise exception 'Anon role admitted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"f9600000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
update public.pachanga_groups set payload='{"players":[]}' where id='f9600000-0000-4000-8000-000000000010';
set local role authenticated;
do $$ begin
 if public.get_pachanga_team_players_v1('f9600000-0000-4000-8000-000000000010') <> '[]'::jsonb then raise exception 'An empty playing roster must not fabricate players from account access'; end if;
end $$;
reset role;
rollback;
\echo PASS: roster, identity, privacy, outsider, anonymous, empty and rollback
