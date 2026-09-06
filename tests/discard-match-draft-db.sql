\set ON_ERROR_STOP on
begin;
\ir ../supabase/migrations/20260906162406_discard_match_draft_v1.sql
insert into auth.users(id,email) values
('f9630000-0000-4000-8000-000000000001','draft-admin@example.test'),
('f9630000-0000-4000-8000-000000000002','draft-member@example.test');
insert into public.pachanga_groups(id,owner_id,name,team_code,payload) values
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000001','Discard QA','DRQA9601',
'{"activeMatchId":"draft","players":[{"id":"manual","name":"Keep me","rating":6.1234567890123456789,"ratingVotes":[]}],"siteSettings":{"keep":"exactly"},"venues":[],"matches":[{"id":"draft","configured":false},{"id":"published","configured":true},{"id":"closed","configured":false,"closed":true},{"id":"scored","configured":false,"scoreB":1},{"id":"market","configured":false,"publicOpen":true}]}');
insert into public.pachanga_group_members(group_id,user_id,role,display_name) values
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000001','owner','Admin'),
('f9630000-0000-4000-8000-000000000010','f9630000-0000-4000-8000-000000000002','player','Member');
select set_config('test.before',(select payload::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
select set_config('test.revision',(select payload_revision::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
select set_config('request.jwt.claims','{"sub":"f9630000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
do $$ begin
 begin perform public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','draft',gen_random_uuid(),current_setting('test.revision')::bigint); raise exception 'Member discarded'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"f9630000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true}',true);
do $$ begin
 begin perform public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','draft',gen_random_uuid(),current_setting('test.revision')::bigint); raise exception 'Anonymous discarded'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"f9630000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',true);
do $$ declare mid text; begin
 foreach mid in array array['published','closed','scored','market'] loop
  begin perform public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010',mid,gen_random_uuid(),current_setting('test.revision')::bigint); raise exception 'Protected match discarded'; exception when sqlstate 'PT422' then null; end;
 end loop;
 begin perform public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','draft',gen_random_uuid(),-1); raise exception 'Stale write succeeded'; exception when sqlstate 'PT409' then null; end;
end $$;
-- Regression: a browser's floating-point round-trip must not turn a draft deletion
-- into a rejected attempt to edit server-managed player ratings.
do $$ begin
 begin
  perform public.save_pachanga_payload_authoritative_v2(
    'f9630000-0000-4000-8000-000000000010', current_setting('test.revision')::bigint,
    jsonb_set(current_setting('test.before')::jsonb, '{players,0,rating}', '6.123456789012346'), gen_random_uuid());
  raise exception 'Rounded card write accepted';
 exception when sqlstate 'PT422' then null; end;
end $$;
select public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','draft','f9630000-0000-4000-8000-000000000020',current_setting('test.revision')::bigint)->>'discardedDraftId';
-- Same operation is safe after the revision changes and the draft is gone.
select public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','draft','f9630000-0000-4000-8000-000000000020',current_setting('test.revision')::bigint)->>'discardedDraftId';
do $$ begin
 begin perform public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','published','f9630000-0000-4000-8000-000000000020',current_setting('test.revision')::bigint); raise exception 'Reused command accepted'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
do $$ declare saved jsonb; original jsonb := current_setting('test.before')::jsonb; begin
 select payload into saved from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010';
 if saved - 'matches' - 'activeMatchId' is distinct from original - 'matches' - 'activeMatchId' then raise exception 'Unrelated data changed'; end if;
 if saved->'matches' is distinct from (original->'matches') - 0 or saved->>'activeMatchId'<>'published' then raise exception 'Wrong matches after discard'; end if;
 if (select count(*) from public.pachanga_group_events where group_id='f9630000-0000-4000-8000-000000000010' and event_type='match_draft_discarded_v1')<>1 then raise exception 'Duplicate event'; end if;
end $$;
-- Empty state must be stored, without manufacturing another draft.
update public.pachanga_groups set payload=jsonb_set(payload,'{matches}','[{"id":"last","configured":false}]') where id='f9630000-0000-4000-8000-000000000010';
select set_config('test.revision',(select payload_revision::text from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010'),true);
set local role authenticated;
select public.discard_pachanga_match_draft_v1('f9630000-0000-4000-8000-000000000010','last',gen_random_uuid(),current_setting('test.revision')::bigint)->'payload'->'matches';
reset role;
do $$ begin
 if not exists(select 1 from public.pachanga_groups where id='f9630000-0000-4000-8000-000000000010' and payload->'matches'='[]'::jsonb and payload->>'activeMatchId'='') then raise exception 'Last draft regenerated'; end if;
 if has_function_privilege('anon','public.discard_pachanga_match_draft_v1(uuid,text,uuid,bigint,jsonb)','execute') then raise exception 'Anonymous execute allowed'; end if;
end $$;
rollback;
\echo PASS: discard, replay, permissions, conflicts, published/result protection, unrelated data and empty calendar
