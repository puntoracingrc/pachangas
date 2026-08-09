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

insert into auth.users(id, email, raw_app_meta_data) values
  ('a1000000-0000-0000-0000-000000000001', 'triage-target@example.test', '{}'::jsonb),
  ('a1000000-0000-0000-0000-000000000002', 'triage-reporter-1@example.test', '{}'::jsonb),
  ('a1000000-0000-0000-0000-000000000003', 'triage-reporter-2@example.test', '{}'::jsonb),
  ('a1000000-0000-0000-0000-000000000004', 'triage-reporter-3@example.test', '{}'::jsonb),
  ('a1000000-0000-0000-0000-000000000005', 'triage-moderator@example.test', '{"pachangas_security_role":"moderator"}'::jsonb),
  ('a1000000-0000-0000-0000-000000000006', 'triage-correlated-2@example.test', '{}'::jsonb),
  ('a1000000-0000-0000-0000-000000000007', 'triage-correlated-3@example.test', '{}'::jsonb);

insert into public.pachanga_player_profiles(id, user_id, source_player_id, display_name) values
  ('a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'triage-target', 'Triage Target');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('a3000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 'Triage group one', 'TRIAGE01', '{}'::jsonb),
  ('a3000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000003', 'Triage group two', 'TRIAGE02', '{}'::jsonb),
  ('a3000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000004', 'Triage group three', 'TRIAGE03', '{}'::jsonb);

update private.pachanga_conduct_settings set
  conduct_triage_enabled = false,
  conduct_triage_shadow_mode = true,
  social_restrictions_enabled = false
where singleton;

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_conduct_triage_category_policy', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_moderation_case_relations', 'SELECT'),
  'Triage policy and lineage must remain private'
);
select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.get_pachanga_moderation_queue_v1_1(text,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.merge_pachanga_conduct_cases_v1_1(uuid,uuid,uuid,bigint,bigint,jsonb)', 'EXECUTE'),
  'Only authenticated actors may reach guarded triage RPCs'
);

-- One isolated, non-serious signal remains record-only as a recommendation.
insert into private.pachanga_moderation_cases(
  id, opaque_reference, target_profile_id, target_user_id, source_type, category
) values (
  'a4000000-0000-0000-0000-000000000001', 'a4100000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'conduct_report', 'abusive_behavior'
);
insert into private.pachanga_report_source_clusters(
  id, case_id, source_group_id, context_kind, context_id
) values (
  'a5000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001', 'match', 'triage-match-1'
);
insert into private.pachanga_conduct_reports(
  id, opaque_reference, case_id, source_cluster_id, reporter_user_id, reporter_group_id,
  target_profile_id, target_user_id, target_group_id, context_kind, context_id,
  context_revision, category, operation_id
) values (
  'a6000000-0000-0000-0000-000000000001', 'a6100000-0000-0000-0000-000000000001',
  'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001',
  'a1000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'a3000000-0000-0000-0000-000000000001', 'match', 'triage-match-1', 1,
  'abusive_behavior', 'a7000000-0000-0000-0000-000000000001'
);
select private.pachanga_recount_conduct_case_v1_1('a4000000-0000-0000-0000-000000000001');
select private.pachanga_recompute_conduct_triage_v1_1('a4000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(
  (select triage_recommendation = 'record_only' and operational_queue = 'review'
    and triage_reason_codes @> array['ISOLATED_NON_SERIOUS_SIGNAL']
    from private.pachanga_moderation_cases where id = 'a4000000-0000-0000-0000-000000000001'),
  'Shadow mode must calculate record-only while preserving the V1 human queue'
);
select pg_temp.assert_true(
  not exists (select 1 from private.pachanga_conduct_warnings where target_user_id = 'a1000000-0000-0000-0000-000000000001'),
  'Triage must never create a warning or sanction'
);

-- Active mode suppresses immediate moderator notification for record-only, but shadow mode does not.
update private.pachanga_conduct_settings set conduct_triage_enabled = true, conduct_triage_shadow_mode = false where singleton;
select private.pachanga_recompute_conduct_triage_v1_1('a4000000-0000-0000-0000-000000000001');
select private.pachanga_conduct_notify_moderators_v1(
  'conduct_warning_review', 'Test', 'Test', '/admin/conduct',
  '{"caseReference":"a4100000-0000-0000-0000-000000000001"}'::jsonb, 'triage-active-test'
);
select pg_temp.assert_true(
  not exists (select 1 from public.pachanga_user_notifications where recipient_user_id = 'a1000000-0000-0000-0000-000000000005'),
  'Active record-only triage must not immediately notify a moderator'
);
update private.pachanga_conduct_settings set conduct_triage_shadow_mode = true where singleton;
select private.pachanga_recompute_conduct_triage_v1_1('a4000000-0000-0000-0000-000000000001');
select private.pachanga_conduct_notify_moderators_v1(
  'conduct_warning_review', 'Test', 'Test', '/admin/conduct',
  '{"caseReference":"a4100000-0000-0000-0000-000000000001"}'::jsonb, 'triage-shadow-test'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.pachanga_user_notifications where recipient_user_id = 'a1000000-0000-0000-0000-000000000005'),
  'Shadow mode must preserve the V1 moderator flow'
);

-- Correlated clicks from one team remain one independent source.
insert into private.pachanga_conduct_reports(
  opaque_reference, case_id, source_cluster_id, reporter_user_id, reporter_group_id,
  target_profile_id, target_user_id, target_group_id, context_kind, context_id,
  context_revision, category, operation_id
) values
  ('a6100000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000006', 'a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'match', 'triage-match-1', 1,
   'abusive_behavior', 'a7000000-0000-0000-0000-000000000002'),
  ('a6100000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000007', 'a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'match', 'triage-match-1', 1,
   'abusive_behavior', 'a7000000-0000-0000-0000-000000000003');
select private.pachanga_recount_conduct_case_v1_1('a4000000-0000-0000-0000-000000000001');
select private.pachanga_recompute_conduct_triage_v1_1('a4000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(
  (select report_count = 3 and independent_source_count = 1 and correlated_source_count = 2
    and triage_recommendation = 'record_only'
    from private.pachanga_moderation_cases where id = 'a4000000-0000-0000-0000-000000000001'),
  'Raw same-team reports must not multiply independent priority'
);

-- Three independent teams in different contexts reach priority review.
insert into private.pachanga_report_source_clusters(id, case_id, source_group_id, context_kind, context_id) values
  ('a5000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'match', 'triage-match-2'),
  ('a5000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'match', 'triage-match-3');
insert into private.pachanga_conduct_reports(
  opaque_reference, case_id, source_cluster_id, reporter_user_id, reporter_group_id,
  target_profile_id, target_user_id, target_group_id, context_kind, context_id,
  context_revision, category, operation_id
) values
  ('a6100000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000002',
   'a1000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002', 'match', 'triage-match-2', 1,
   'abusive_behavior', 'a7000000-0000-0000-0000-000000000004'),
  ('a6100000-0000-0000-0000-000000000005', 'a4000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000003',
   'a1000000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000003', 'match', 'triage-match-3', 1,
   'abusive_behavior', 'a7000000-0000-0000-0000-000000000005');
select private.pachanga_recount_conduct_case_v1_1('a4000000-0000-0000-0000-000000000001');
select private.pachanga_recompute_conduct_triage_v1_1('a4000000-0000-0000-0000-000000000001');
select pg_temp.assert_true(
  (select triage_recommendation = 'priority_review'
    and triage_reason_codes @> array['INDEPENDENT_SOURCES_3','DISTINCT_CONTEXTS_3']
    from private.pachanga_moderation_cases where id = 'a4000000-0000-0000-0000-000000000001'),
  'Three independent teams across contexts must reach explainable priority review'
);

-- One grave report is urgent, never guilty and never automatically sanctioned.
insert into private.pachanga_moderation_cases(
  id, opaque_reference, target_profile_id, target_user_id, source_type, category, priority
) values (
  'a4000000-0000-0000-0000-000000000002', 'a4100000-0000-0000-0000-000000000002',
  'a2000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
  'conduct_report', 'threats_or_violence', 'urgent_review'
);
select pg_temp.assert_true(
  (select triage_recommendation = 'urgent_review' and state = 'submitted'
    from private.pachanga_moderation_cases where id = 'a4000000-0000-0000-0000-000000000002')
  and not exists (select 1 from private.pachanga_social_restrictions where target_user_id = 'a1000000-0000-0000-0000-000000000001'),
  'Urgent review must not imply guilt or automatic restriction'
);

-- Moderator-only queue is explainable; normal users cannot inspect it.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000002","app_metadata":{}}', true);
do $$
begin
  perform public.get_pachanga_moderation_queue_v1_1(null, 100);
  raise exception 'A normal user unexpectedly read the moderation queue';
exception when others then
  if sqlerrm = 'A normal user unexpectedly read the moderation queue' then raise; end if;
  if sqlerrm <> 'Security moderator required' then raise; end if;
end;
$$;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.get_pachanga_moderation_queue_v1_1(null, 100) as triage_queue \gset
reset role;
select pg_temp.assert_true(
  (:'triage_queue'::jsonb -> 'counts' ->> 'urgent_review')::integer >= 1
  and jsonb_array_length(:'triage_queue'::jsonb -> 'cases') >= 2,
  'Moderator queue must expose queue counts and explainable cases'
);

-- Split and merge preserve evidence, revisions and immutable lineage.
select set_config('conduct_test.source_revision', (
  select revision::text from private.pachanga_moderation_cases where id = 'a4000000-0000-0000-0000-000000000001'
), true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.split_pachanga_conduct_case_v1_1(
  'a4100000-0000-0000-0000-000000000001', array['a6100000-0000-0000-0000-000000000005'::uuid],
  'a7000000-0000-0000-0000-000000000010', current_setting('conduct_test.source_revision')::bigint, '{}'
) as split_result \gset
select public.split_pachanga_conduct_case_v1_1(
  'a4100000-0000-0000-0000-000000000001', array['a6100000-0000-0000-0000-000000000005'::uuid],
  'a7000000-0000-0000-0000-000000000010', current_setting('conduct_test.source_revision')::bigint, '{}'
) as split_replay \gset
reset role;
select pg_temp.assert_true(:'split_result'::jsonb = :'split_replay'::jsonb,
  'Split retries must replay the canonical receipt');
select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_moderation_case_relations
    where operation_id = 'a7000000-0000-0000-0000-000000000010'),
  'A split must create exactly one immutable lineage record'
);
select set_config('conduct_test.split_reference', :'split_result'::jsonb ->> 'splitCaseReference', true);
select set_config('conduct_test.source_revision_after_split', (
  select revision::text from private.pachanga_moderation_cases where opaque_reference = 'a4100000-0000-0000-0000-000000000001'
), true);
select set_config('conduct_test.split_revision', (
  select revision::text from private.pachanga_moderation_cases where opaque_reference = current_setting('conduct_test.split_reference')::uuid
), true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
select public.merge_pachanga_conduct_cases_v1_1(
  current_setting('conduct_test.split_reference')::uuid, 'a4100000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000011', current_setting('conduct_test.split_revision')::bigint,
  current_setting('conduct_test.source_revision_after_split')::bigint, '{}'
) as merge_result \gset
select public.merge_pachanga_conduct_cases_v1_1(
  current_setting('conduct_test.split_reference')::uuid, 'a4100000-0000-0000-0000-000000000001',
  'a7000000-0000-0000-0000-000000000011', current_setting('conduct_test.split_revision')::bigint,
  current_setting('conduct_test.source_revision_after_split')::bigint, '{}'
) as merge_replay \gset
reset role;
select pg_temp.assert_true(:'merge_result'::jsonb = :'merge_replay'::jsonb,
  'Merge retries must replay the canonical receipt');
select pg_temp.assert_true(
  (select state = 'closed' and merged_into_case_id is not null
    from private.pachanga_moderation_cases where opaque_reference = current_setting('conduct_test.split_reference')::uuid)
  and (select report_count = 5 from private.pachanga_moderation_cases where opaque_reference = 'a4100000-0000-0000-0000-000000000001'),
  'Merge must preserve every report while closing only the source branch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-0000-0000-000000000005","app_metadata":{"pachangas_security_role":"moderator"}}', true);
do $$
begin
  perform public.merge_pachanga_conduct_cases_v1_1(
    'a4100000-0000-0000-0000-000000000002', 'a4100000-0000-0000-0000-000000000001',
    'a7000000-0000-0000-0000-000000000012',
    (select revision from private.pachanga_moderation_cases where opaque_reference = 'a4100000-0000-0000-0000-000000000002'),
    (select revision from private.pachanga_moderation_cases where opaque_reference = 'a4100000-0000-0000-0000-000000000001'), '{}'
  );
  raise exception 'A grave incident was unexpectedly merged';
exception when others then
  if sqlerrm = 'A grave incident was unexpectedly merged' then raise; end if;
end;
$$;
reset role;

select pg_temp.assert_true(
  not exists (select 1 from private.pachanga_moderation_events
    where coalesce((payload ->> 'affectsSportRating')::boolean, false))
  and not exists (select 1 from private.pachanga_moderation_events
    where coalesce((payload ->> 'automaticSanctionApplied')::boolean, false)),
  'Triage lineage must stay outside sport and never apply an automatic sanction'
);

rollback;
