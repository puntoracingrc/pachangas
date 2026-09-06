\set ON_ERROR_STOP on
begin;
update private.pachanga_social_team_settings_v1 set social_profile_foundation_enabled=true,
 social_profile_independent_write_enabled=true,social_team_creation_enabled=true,social_team_home_v3f_enabled=true where singleton;
insert into auth.users(id,email) values
('f9650000-0000-4000-8000-000000000001','team-home-member@example.test'),
('f9650000-0000-4000-8000-000000000002','team-home-outsider@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values
('f9650000-0000-4000-8000-000000000010','f9650000-0000-4000-8000-000000000001','Team home QA','THQA9601',
'{"activeMatchId":"past","players":[],"venues":[],"siteSettings":{},"matches":[
{"id":"draft","date":"2090-01-01T21:00","configured":false},
{"id":"unconfigured","date":"2090-01-02T21:00"},
{"id":"closed","date":"2090-01-03T21:00","configured":true,"closed":true},
{"id":"scored","date":"2090-01-04T21:00","configured":true,"scoreA":0,"scoreB":0},
{"id":"future","date":"2099-01-01T21:00","configured":true,"title":"Future match"},
{"id":"past","date":"2020-08-24T21:00","configured":true,"title":"Pending match","players":[{"playerId":"p1","status":"duda"}]}]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
('f9650000-0000-4000-8000-000000000010','f9650000-0000-4000-8000-000000000001','owner','Member');
insert into public.pachanga_social_team_states_v1(group_id,last_operation_id) values('f9650000-0000-4000-8000-000000000010',gen_random_uuid());
select set_config('test.original',(select payload::text from public.pachanga_groups where team_code='THQA9601'),true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f9650000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$ begin
 if public.get_pachanga_social_team_home_v1('f9650000-0000-4000-8000-000000000010')#>>'{nextMatch,matchId}' is distinct from 'past' then raise exception 'Past open match disappeared';end if;
end $$;
reset role;
do $$ begin
 if (select payload from public.pachanga_groups where team_code='THQA9601') is distinct from current_setting('test.original')::jsonb then raise exception 'Read mutated match data';end if;
end $$;
update public.pachanga_groups set payload=jsonb_set(payload,'{matches,5,closed}','true') where team_code='THQA9601';
set local role authenticated;
do $$ begin
 if public.get_pachanga_social_team_home_v1('f9650000-0000-4000-8000-000000000010')#>>'{nextMatch,matchId}' is distinct from 'future' then raise exception 'Draft, closed or scored selected';end if;
end $$;
reset role;
update public.pachanga_groups set payload=jsonb_set(payload,'{matches,4,scoreA}','0') where team_code='THQA9601';
set local role authenticated;
do $$ begin
 if public.get_pachanga_social_team_home_v1('f9650000-0000-4000-8000-000000000010')->'nextMatch' is distinct from 'null'::jsonb then raise exception 'Empty open calendar incorrect';end if;
end $$;
select set_config('request.jwt.claims','{"sub":"f9650000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
do $$ begin
 begin perform public.get_pachanga_social_team_home_v1('f9650000-0000-4000-8000-000000000010');raise exception 'Outsider read team';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.get_pachanga_social_team_home_v1(uuid)','execute') then raise exception 'Anon execute';end if;
end $$;
rollback;
\echo PASS: past open match, future fallback, no draft/result/closed, empty calendar, no mutation, membership/anon restrictions
