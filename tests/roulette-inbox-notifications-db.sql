\set ON_ERROR_STOP on
begin;
create function pg_temp.check_it(ok boolean, message text) returns void language plpgsql as $$ begin if not coalesce(ok,false) then raise exception '%',message; end if; end $$;
insert into auth.users(id,email) values ('b1000000-0000-4000-8000-000000000001','spin-inbox-1@example.test'),('b1000000-0000-4000-8000-000000000002','spin-inbox-2@example.test');
insert into public.pachanga_player_profiles(id,user_id,display_name) values ('b2000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','Spin inbox'),('b2000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000002','Other');
insert into public.pachanga_player_assessments(user_id,assessment_kind,engine_version,questionnaire_version,idempotency_key,input,result,rating)
values ('b1000000-0000-4000-8000-000000000001','initial','football-rating-v1','initial-test-v1',gen_random_uuid(),'{}','{}',5);
set local role authenticated;
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000001',true);
create temporary table qa_notice as select public.get_my_pachanga_social_inbox_v1('pending','REWARD') response;
select pg_temp.check_it((response->>'pendingCount')::int=1 and (response->>'unreadCount')::int=1,'bell sees earned spin before first roulette visit') from qa_notice;
select pg_temp.check_it(response->'items'->0->>'deepLink'='/ruleta' and response->'items'->0->>'sourceDomain'='REWARD','reward links to canonical roulette') from qa_notice;
select pg_temp.check_it(public.get_my_pachanga_social_inbox_v1('pending','REWARD')->'items'->0->>'id'=response->'items'->0->>'id','reload keeps one identical notice') from qa_notice;
select public.command_pachanga_social_inbox_v1('inbox.mark_read',(response->'items'->0->>'id')::uuid,gen_random_uuid(),(response->'items'->0->>'revision')::bigint) from qa_notice;
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'pendingCount')::int=1,'reading does not spend the spin');
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'unreadCount')::int=0,'refresh preserves read receipt');
select public.pachanga_roulette_v1('spin','b3000000-0000-4000-8000-000000000001');
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'pendingCount')::int=0,'spending clears pending bell');
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'unreadCount')::int=0,'spent notice does not become unread');
select pg_temp.check_it(public.get_my_pachanga_social_inbox_v1('all','REWARD')->'items'->0->>'title'='Giro gratis utilizado','history describes used spin');
select pg_temp.check_it(not (public.get_my_pachanga_social_inbox_v1('all','REWARD')->'items'->0 ? 'deepLink'),'spent notice has no stale use CTA');
select public.pachanga_roulette_v1('spin','b3000000-0000-4000-8000-000000000001');
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'pendingCount')::int=0,'spin retry cannot restore notice');
reset role;
insert into public.pachanga_player_assessments(user_id,assessment_kind,engine_version,questionnaire_version,idempotency_key,input,result,rating)
values ('b1000000-0000-4000-8000-000000000001','advanced','football-rating-v1','advanced-test-v1',gen_random_uuid(),'{}','{}',5);
set local role authenticated;
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'pendingCount')::int=1,'advanced test grants a new pending notice');
select pg_temp.check_it(public.get_my_pachanga_social_inbox_v1()->'items'->0->>'summary' like '%test avanzado%','advanced origin explained');
select set_config('request.jwt.claim.sub','b1000000-0000-4000-8000-000000000002',true);
select pg_temp.check_it((public.get_my_pachanga_social_inbox_v1()->>'pendingCount')::int=0,'another user cannot see or reconcile these credits');
reset role;
select pg_temp.check_it((select count(*) from public.pachanga_user_notifications where recipient_user_id='b1000000-0000-4000-8000-000000000001' and kind='roulette_free_spin_reward')=2,'exactly one notice per test');
select pg_temp.check_it(not has_function_privilege('anon','public.get_my_pachanga_social_inbox_v1(text,text,integer,integer,bigint,uuid)','execute'),'anonymous cannot load inbox');
select pg_temp.check_it(not has_function_privilege('authenticated','private.pachanga_roulette_credit_notice_v1(uuid)','execute'),'clients cannot manufacture notifications');
select pg_temp.check_it(not exists(select 1 from private.pachanga_notification_delivery_outbox o join public.pachanga_user_notifications n on n.id=o.notification_id where n.kind='roulette_free_spin_reward'),'only in-app, no email/push');
rollback;
