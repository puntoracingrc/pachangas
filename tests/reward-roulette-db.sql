\set ON_ERROR_STOP on
begin;
create function pg_temp.check_it(ok boolean, message text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception '%',message; end if; end $$;
create function pg_temp.fails(q text) returns void language plpgsql as $$ begin execute q; raise exception 'expected failure'; exception when others then if sqlerrm='expected failure' then raise; end if; end $$;
insert into auth.users(id,email) values ('a1000000-0000-0000-0000-000000000001','roulette-1@example.test'),('a1000000-0000-0000-0000-000000000002','roulette-2@example.test');
insert into public.pachanga_player_profiles(id,user_id,display_name) values ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','Roulette QA'),('a2000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002','Roulette Other');
insert into public.pachanga_player_assessments(user_id,assessment_kind,engine_version,questionnaire_version,idempotency_key,input,result,rating)
select 'a1000000-0000-0000-0000-000000000001',kind,'football-rating-v1',kind||'-test-v1',gen_random_uuid(),'{}','{}',5 from unnest(array['initial','advanced'])kind;
grant usage on schema public,auth to authenticated;
grant execute on function auth.uid() to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select pg_temp.check_it((public.pachanga_roulette_v1()->>'freeSpins')::int=2,'two tests give exactly two credits');
select pg_temp.check_it((public.pachanga_roulette_v1()->>'freeSpins')::int=2,'reload does not grant again');
select pg_temp.fails('select * from private.pachanga_roulette_boxes');
select pg_temp.fails('select * from private.pachanga_roulette_credits');
create temporary table qa_spin as select public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000001') response;
select pg_temp.check_it((response->'snapshot'->>'balance')::int=0 and (response->'snapshot'->>'freeSpins')::int=1,'free spin never charges points') from qa_spin;
select pg_temp.check_it(not ((response->'chest') ? 'sealed') and not ((response->'chest') ? 'roll'),'spin response does not leak content') from qa_spin;
select pg_temp.check_it(public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000001')->'chest'=response->'chest','spin retry preserves winner') from qa_spin;
select public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000002');
select pg_temp.fails($q$select public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000003')$q$);
select pg_temp.check_it(jsonb_array_length(public.pachanga_roulette_v1()->'queue')=2,'insufficient funds rolls back box creation');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select pg_temp.fails($q$select public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000001')$q$);
select pg_temp.fails('select public.pachanga_roulette_v1(''open'',gen_random_uuid(),array['||quote_literal((select response->'chest'->>'id' from qa_spin))||'::uuid])');
reset role;
-- Force a combo and its duplicate to verify the grant path deterministically.
update private.pachanga_roulette_boxes set sealed=jsonb_build_object('key','player.frame.barrio.steel','points',3,'duplicatePoints',4)
 where user_id='a1000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
create temporary table qa_open as select public.pachanga_roulette_v1('open_all','a4000000-0000-0000-0000-000000000001') response;
select pg_temp.check_it((response->>'points')::int=10,'combo keeps base points and duplicate compensation') from qa_open;
select pg_temp.check_it(jsonb_array_length(response->'entries')=2 and jsonb_array_length(response->'snapshot'->'owned')=1,'batch grants one cosmetic and two results') from qa_open;
select pg_temp.check_it((public.pachanga_roulette_v1('open_all','a4000000-0000-0000-0000-000000000001')->'snapshot'->>'balance')::int=10,'batch retry cannot grant twice');
select pg_temp.check_it((public.pachanga_roulette_v1('open',gen_random_uuid(),array[(select (response->'chest'->>'id')::uuid from qa_spin)])->'snapshot'->>'balance')::int=10,'opening an opened box cannot grant twice');
reset role;
select private.pachanga_apply_player_points_v1('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001',5,'admin_adjustment',gen_random_uuid(),null,null,null,'roulette-qa-funding');
set local role authenticated;
select pg_temp.check_it((public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000003')->'snapshot'->>'balance')::int=0,'paid spin debits exactly fifteen');
select pg_temp.check_it((public.pachanga_roulette_v1('spin','a3000000-0000-0000-0000-000000000003')->'snapshot'->>'balance')::int=0,'paid replay does not debit twice');
reset role;
-- Weekly reconciliation across missed visits and inactivity; retain existing credits.
update private.pachanga_roulette_config set activated_at=date_trunc('week',now() at time zone 'Europe/Madrid') at time zone 'Europe/Madrid' - interval '70 days';
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values('a5000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001','Roulette QA','RLTQA','{}');
insert into public.pachanga_progression_match_facts(id,source_kind,source_match_id,source_revision,group_id,match_scope,outcome,goals_for,goals_against,clean_sheet,close_win,big_win,scoreless_draw,source_snapshot,played_at)
values('a6000000-0000-0000-0000-000000000001','internal_snapshot','roulette-qa',1,'a5000000-0000-0000-0000-000000000001','internal','social',0,0,false,false,false,false,'{}',(select activated_at from private.pachanga_roulette_config));
insert into public.pachanga_progression_player_match_facts(match_fact_id,group_id,player_profile_id,local_player_id,team_side,outcome)
values('a6000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','qa','A','draw');
set local role authenticated;
select pg_temp.check_it((public.pachanga_roulette_v1()->>'freeSpins')::int=5,'five eligible calendar weeks accumulate; inactive weeks do not');
select pg_temp.check_it((public.pachanga_roulette_v1()->>'freeSpins')::int=5,'inactivity preserves bank and reload cannot duplicate');
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select pg_temp.check_it((public.pachanga_roulette_v1()->>'freeSpins')::int=0,'nonparticipant does not receive weekly credit');
reset role;
select pg_temp.check_it(not has_function_privilege('anon','public.pachanga_roulette_v1(text,uuid,uuid[])','execute'),'anonymous role cannot invoke');
select pg_temp.check_it((select count(*) from public.pachanga_player_reward_inventory where player_profile_id='a2000000-0000-0000-0000-000000000001' and source_grant_id is null and source_roulette_box_id is not null)=1,'cosmetic has roulette origin, no fake achievement');
rollback;
