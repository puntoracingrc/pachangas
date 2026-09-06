\set ON_ERROR_STOP on
begin;
create function pg_temp.age_assert(ok boolean, label text) returns void language plpgsql as $$
begin if not coalesce(ok,false) then raise exception '%',label; end if; end; $$;
create function pg_temp.age_denied(statement text) returns void language plpgsql as $$
begin
 execute statement;
 raise exception 'Expected age rejection: %',statement;
exception when insufficient_privilege then
 if sqlerrm not like '%MARKET_ADULT_REQUIRED%' then raise; end if;
end; $$;
insert into auth.users(id,email) values
 ('aa000000-0000-4000-8000-000000000001','age-minor@example.test'),
 ('aa000000-0000-4000-8000-000000000002','age-adult-admin@example.test'),
 ('aa000000-0000-4000-8000-000000000003','age-rival@example.test'),
 ('aa000000-0000-4000-8000-000000000004','age-unknown@example.test');
update private.pachanga_social_team_settings_v1 set social_profile_foundation_enabled=true,
 social_profile_independent_write_enabled=true,social_team_creation_enabled=true;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select public.command_pachanga_social_profile_v1('profile.create',0,'aa100000-0000-4000-8000-000000000001',
 jsonb_build_object('birthDate',to_char(current_date-interval '17 years','YYYY-MM-DD'),'displayName','Menor QA','primaryPosition','Portero','preferredModality','futbol7','generalArea','Barcelona')) as minor_profile \gset
select pg_temp.age_assert(:'minor_profile'::jsonb->>'birthDate'=to_char(current_date-interval '17 years','YYYY-MM-DD'),'Private birth date returned to owner');
select pg_temp.age_assert(public.get_my_pachanga_market_age_access_v1()->>'access'='minor','Minor recognized');
select pg_temp.age_denied('select public.search_pachanga_open_matches_v1()');
select pg_temp.age_denied($s$select public.review_pachanga_open_match_request_authoritative_v2(null,null,'accepted',null,0,'{}')$s$);
select pg_temp.age_denied($s$select public.command_pachanga_free_agent_market_v1('market.publish',1,'aa200000-0000-4000-8000-000000000001','{}','{}')$s$);
-- Creating a team is allowed for minors.
select public.command_pachanga_social_team_v1('team.create',0,'aa300000-0000-4000-8000-000000000001',
 '{"name":"Age Internal Team QA","modality":"futbol7","generalArea":"Barcelona","shieldKey":"team.shield.shape.round"}','{}') as minor_team \gset
reset role;
select id as minor_group from public.pachanga_groups where owner_id='aa000000-0000-4000-8000-000000000001' \gset
select pg_temp.age_assert(not private.pachanga_team_has_adult_admin_v1(:'minor_group'),'Minor-only team has no external access');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
select public.command_pachanga_social_profile_v1('profile.create',0,'aa100000-0000-4000-8000-000000000002',
 '{"birthDate":"1990-01-01","displayName":"Adulto QA","primaryPosition":"Portero","preferredModality":"futbol7","generalArea":"Barcelona","usualDays":["L"],"approximateTime":"20:00-22:00"}');
select public.command_pachanga_free_agent_market_v1('market.publish',1,'aa200000-0000-4000-8000-000000000002','{}','{}');
select pg_temp.age_assert(exists(select 1 from public.pachanga_market_profiles where user_id='aa000000-0000-4000-8000-000000000002' and active),'Adult can publish and read market');
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select pg_temp.age_assert(not exists(select 1 from public.pachanga_market_profiles),'Minor cannot read market through direct REST table');
select pg_temp.age_assert(not exists(select 1 from public.pachanga_social_player_profiles_v1 where user_id='aa000000-0000-4000-8000-000000000002'),'Cannot read another birthday');
reset role;
update public.pachanga_social_player_profiles_v1 set birth_date=current_date-interval '17 years' where user_id='aa000000-0000-4000-8000-000000000002';
select pg_temp.age_assert(not exists(select 1 from public.pachanga_market_profiles where user_id='aa000000-0000-4000-8000-000000000002' and active),'Changing birth date removes discoverability');
update public.pachanga_social_player_profiles_v1 set birth_date='1990-01-01' where user_id='aa000000-0000-4000-8000-000000000002';
insert into public.pachanga_group_members(group_id,user_id,role) values(:'minor_group','aa000000-0000-4000-8000-000000000002','admin');
select pg_temp.age_assert(private.pachanga_team_has_adult_admin_v1(:'minor_group'),'Adult admin enables external organization despite minor creator');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',true);
select public.command_pachanga_social_profile_v1('profile.create',0,'aa100000-0000-4000-8000-000000000003',
 '{"birthDate":"1990-01-01","displayName":"Rival QA","primaryPosition":"Portero","preferredModality":"futbol7","generalArea":"Barcelona"}');
select public.command_pachanga_social_team_v1('team.create',0,'aa300000-0000-4000-8000-000000000003',
 '{"name":"Age Rival Team QA","modality":"futbol7","generalArea":"Barcelona","shieldKey":"team.shield.shape.round"}','{}');
reset role;
select id as rival_group,team_code as rival_code from public.pachanga_groups where owner_id='aa000000-0000-4000-8000-000000000003' \gset
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select pg_temp.age_denied(format($s$select public.create_pachanga_team_challenge_authoritative(%L,%L,now()+interval '7 days','futbol7','Campo QA','Ciudad QA',null,null,null,'aa400000-0000-4000-8000-000000000001',0,'{}')$s$,:'minor_group',:'rival_code'));
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
select public.create_pachanga_team_challenge_authoritative(:'minor_group',:'rival_code',now()+interval '7 days','futbol7','Campo QA','Ciudad QA',null,null,null,'aa400000-0000-4000-8000-000000000002',0,'{}') as adult_challenge \gset
reset role;
select pg_temp.age_assert(exists(select 1 from public.pachanga_team_challenges where sender_group_id=:'minor_group'),'Adult admin can create external challenge for minor-created team');
select pg_temp.age_assert(exists(select 1 from public.pachanga_group_members where group_id=:'minor_group' and user_id='aa000000-0000-4000-8000-000000000001'),'Minor keeps team membership');
select id as challenge_id from public.pachanga_team_challenges where sender_group_id=:'minor_group' and receiver_group_id=:'rival_group' \gset
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}',true);
select public.respond_pachanga_team_challenge_authoritative(:'rival_group',:'challenge_id','accept',null,null,null,null,null,null,null,
 'aa400000-0000-4000-8000-000000000003',1,'{}');
reset role;
select pg_temp.age_assert(exists(select 1 from public.pachanga_team_challenges where id=:'challenge_id' and status='accepted'),'External challenge can be accepted for a team with minors');
select pg_temp.age_assert(exists(select 1 from public.pachanga_external_matches where challenge_id=:'challenge_id' and home_group_id=:'minor_group'),'Accepted external match remains in the minor-created team');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
select pg_temp.age_assert(exists(select 1 from public.pachanga_external_matches where challenge_id=:'challenge_id' and home_group_id=:'minor_group'),'Minor member can still read the team and its external match');
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aa000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}',true);
select pg_temp.age_assert(public.get_my_pachanga_market_age_access_v1()->>'access'='missing','Unknown birth date requires completion');
select pg_temp.age_denied('select public.search_pachanga_open_matches_v1()');
select pg_temp.age_denied($s$select public.review_pachanga_open_match_request_authoritative_v2(null,null,'accepted',null,0,'{}')$s$);
reset role;
-- Exact adulthood boundary, evaluated by the database date.
update public.pachanga_social_player_profiles_v1 set birth_date=(current_date-interval '18 years')::date+1 where user_id='aa000000-0000-4000-8000-000000000002';
select pg_temp.age_assert(not private.pachanga_market_adult_v1('aa000000-0000-4000-8000-000000000002'),'Day before 18 is restricted');
update public.pachanga_social_player_profiles_v1 set birth_date=(current_date-interval '18 years')::date where user_id='aa000000-0000-4000-8000-000000000002';
select pg_temp.age_assert(private.pachanga_market_adult_v1('aa000000-0000-4000-8000-000000000002'),'18th birthday allows access');
rollback;
