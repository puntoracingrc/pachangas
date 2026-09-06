\set ON_ERROR_STOP on
begin;
\ir ../supabase/migrations/20260906170801_configure_match_v1.sql
insert into auth.users(id,email) values
('f9630000-0000-4000-8000-000000000001','draft-admin@example.test'),
('f9630000-0000-4000-8000-000000000002','draft-member@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000001','Discard QA','DRQA9601',
'{"activeMatchId":"draft","players":[{"id":"manual","name":"Keep me","rating":6.1234567890123456789,"ratingVotes":[]}],"siteSettings":{"keep":"exactly"},"venues":[{"id":"venue","name":"Campo QA"}],"matches":[{"id":"draft","configured":false},{"id":"published","configured":true},{"id":"closed","configured":false,"closed":true},{"id":"scored","configured":false,"scoreB":1},{"id":"market","configured":false,"publicOpen":true}]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000001','owner','Admin'),
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000002','player','Member');
select set_config('test.before',(select payload::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
select set_config('test.revision',(select payload_revision::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
select set_config('test.config','{"title":"Partido QA","date":"2099-09-12T10:20","venueId":"venue","kind":"futbol7","targetPlayers":14,"fieldCost":72.5,"reservesAttend":true,"reserveLimit":3,"publicOpenSlots":2,"publicGuestsPay":true,"publicRequiresApproval":true}',true);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"f9630000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
do $$ begin
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb,gen_random_uuid(),current_setting('test.revision')::bigint);raise exception 'Member created';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"f9630000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$ declare mid text; begin
 begin perform public.save_pachanga_payload_authoritative_v2('f9630000-0000-4000-8000-000000000010',current_setting('test.revision')::bigint,jsonb_set(current_setting('test.before')::jsonb,'{players,0,rating}','6.123456789012346'),gen_random_uuid());raise exception 'Rounded rating accepted';exception when sqlstate 'PT422' then null;end;
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb,gen_random_uuid(),-1);raise exception 'Stale accepted';exception when sqlstate 'PT409' then null;end;
 foreach mid in array array['closed','scored'] loop
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010',mid,current_setting('test.config')::jsonb,gen_random_uuid(),current_setting('test.revision')::bigint);raise exception 'Final result changed';exception when sqlstate 'PT422' then null;end;
 end loop;
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb || '{"players":[],"scoreA":5}',gen_random_uuid(),current_setting('test.revision')::bigint);raise exception 'Extra fields accepted';exception when invalid_parameter_value then null;end;
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb || '{"fieldCost":-1}',gen_random_uuid(),current_setting('test.revision')::bigint);raise exception 'Negative price accepted';exception when invalid_parameter_value then null;end;
end $$;
select public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb,'f9630000-0000-4000-8000-000000000021',current_setting('test.revision')::bigint)->>'configuredMatchId';
select public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','new',current_setting('test.config')::jsonb,'f9630000-0000-4000-8000-000000000021',current_setting('test.revision')::bigint)->>'configuredMatchId';
do $$ begin
 begin perform public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','different',current_setting('test.config')::jsonb,'f9630000-0000-4000-8000-000000000021',current_setting('test.revision')::bigint);raise exception 'Reused command accepted';exception when invalid_parameter_value then null;end;
end $$;
reset role;
do $$ declare saved jsonb; original jsonb:=current_setting('test.before')::jsonb; begin
 select payload into saved from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010';
 if saved - 'matches' - 'activeMatchId' is distinct from original - 'matches' - 'activeMatchId' then raise exception 'Unrelated data changed';end if;
 if (saved->'matches') - 0 is distinct from original->'matches' then raise exception 'Existing matches changed';end if;
 if saved#>'{matches,0,configured}' <> 'true' or saved#>'{matches,0,fieldCost}' <> '72.5' or saved#>'{matches,0,players}' <> '[]' then raise exception 'Wrong configured match';end if;
 if (select count(*) from public.pachanga_group_events where group_id='f9630000-0000-4000-8000-000000000010' and event_type='match_configured_v1')<>1 then raise exception 'Duplicate event';end if;
end $$;
select set_config('test.revision',(select payload_revision::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
set local role authenticated;
select public.configure_pachanga_match_v1('f9630000-0000-4000-8000-000000000010','draft',current_setting('test.config')::jsonb,gen_random_uuid(),current_setting('test.revision')::bigint)->>'configuredMatchId';
reset role;
do $$ begin
 if (select jsonb_array_length(payload->'matches') from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010')<>6 then raise exception 'Draft duplicated';end if;
 if has_function_privilege('anon','public.configure_pachanga_match_v1(uuid,text,jsonb,uuid,bigint,jsonb)','execute') then raise exception 'Anon execute';end if;
end $$;
rollback;
\echo PASS: new match, draft, precision preservation, replay, conflict, permissions, results and field validation
