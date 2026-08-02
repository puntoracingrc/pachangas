\set ON_ERROR_STOP on

begin;

-- The local PostgreSQL harness stubs Supabase Auth. Mirror the Data API roles
-- that can invoke auth.uid()/auth.jwt() in a real Supabase project.
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('10000000-0000-0000-0000-000000000001', 'evaluator@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'target@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'admin@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'evaluator2@example.test'),
  ('10000000-0000-0000-0000-000000000005', 'evaluator3@example.test'),
  ('10000000-0000-0000-0000-000000000006', 'zero@example.test'),
  ('10000000-0000-0000-0000-000000000007', 'outsider@example.test'),
  ('10000000-0000-0000-0000-000000000008', 'opponent@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000003',
    'V2 test group',
    'V2TEST',
    jsonb_build_object(
      'activeMatchId', null,
      'matches', '[]'::jsonb,
      'players', jsonb_build_array(
        jsonb_build_object('id', 'evaluator', 'ownerUserId', '10000000-0000-0000-0000-000000000001', 'name', 'Evaluator', 'appearances', 0, 'goals', 0, 'wins', 0),
        jsonb_build_object('id', 'target', 'ownerUserId', '10000000-0000-0000-0000-000000000002', 'name', 'Target', 'appearances', 0, 'goals', 0, 'wins', 0),
        jsonb_build_object('id', 'admin', 'ownerUserId', '10000000-0000-0000-0000-000000000003', 'name', 'Admin', 'appearances', 0, 'goals', 0, 'wins', 0),
        jsonb_build_object('id', 'evaluator2', 'ownerUserId', '10000000-0000-0000-0000-000000000004', 'name', 'Evaluator Two', 'appearances', 0, 'goals', 0, 'wins', 0),
        jsonb_build_object('id', 'evaluator3', 'ownerUserId', '10000000-0000-0000-0000-000000000005', 'name', 'Evaluator Three', 'appearances', 0, 'goals', 0, 'wins', 0),
        jsonb_build_object('id', 'zero', 'ownerUserId', '10000000-0000-0000-0000-000000000006', 'name', 'No Votes', 'appearances', 0, 'goals', 0, 'wins', 0)
      ),
      'siteSettings', '{}'::jsonb,
      'venues', '[]'::jsonb
    )
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000008',
    'Registered opponent',
    'OPPV2',
    jsonb_build_object('activeMatchId', null, 'matches', '[]'::jsonb, 'players', '[]'::jsonb, 'siteSettings', '{}'::jsonb, 'venues', '[]'::jsonb)
  );

insert into public.pachanga_group_members(group_id, user_id, role) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'player'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', 'admin'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000003', 'owner'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', 'player'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000005', 'player'),
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000006', 'player'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000008', 'owner');

insert into public.pachanga_player_profiles(
  user_id, source_group_id, source_player_id, display_name, base_facets,
  calibrated_facets, current_facets, base_overall, calibrated_overall,
  current_overall, rating_reliability, rating_engine_version
) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'evaluator', 'Evaluator',
    '{"pace":60,"shooting":60,"passing":60,"dribbling":60,"defending":60,"physical":60}',
    '{"pace":60,"shooting":60,"passing":60,"dribbling":60,"defending":60,"physical":60}',
    '{"pace":60,"shooting":60,"passing":60,"dribbling":60,"defending":60,"physical":60}', 60, 60, 60, 80, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'target', 'Target',
    '{"pace":50,"shooting":50,"passing":50,"dribbling":50,"defending":50,"physical":50}',
    '{"pace":50,"shooting":50,"passing":50,"dribbling":50,"defending":50,"physical":50}',
    '{"pace":50,"shooting":50,"passing":50,"dribbling":50,"defending":50,"physical":50}', 50, 50, 50, 40, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'admin', 'Admin',
    '{"pace":55,"shooting":55,"passing":55,"dribbling":55,"defending":55,"physical":55}',
    '{"pace":55,"shooting":55,"passing":55,"dribbling":55,"defending":55,"physical":55}',
    '{"pace":55,"shooting":55,"passing":55,"dribbling":55,"defending":55,"physical":55}', 55, 55, 55, 70, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', 'evaluator2', 'Evaluator Two',
    '{"pace":65,"shooting":65,"passing":65,"dribbling":65,"defending":65,"physical":65}',
    '{"pace":65,"shooting":65,"passing":65,"dribbling":65,"defending":65,"physical":65}',
    '{"pace":65,"shooting":65,"passing":65,"dribbling":65,"defending":65,"physical":65}', 65, 65, 65, 60, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', 'evaluator3', 'Evaluator Three',
    '{"pace":45,"shooting":45,"passing":45,"dribbling":45,"defending":45,"physical":45}',
    '{"pace":45,"shooting":45,"passing":45,"dribbling":45,"defending":45,"physical":45}',
    '{"pace":45,"shooting":45,"passing":45,"dribbling":45,"defending":45,"physical":45}', 45, 45, 45, 50, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', 'zero', 'No Votes',
    '{"pace":40,"shooting":40,"passing":40,"dribbling":40,"defending":40,"physical":40}',
    '{"pace":40,"shooting":40,"passing":40,"dribbling":40,"defending":40,"physical":40}',
    '{"pace":40,"shooting":40,"passing":40,"dribbling":40,"defending":40,"physical":40}', 40, 40, 40, 50, 'pachangas-rating-v2'),
  ('10000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000002', 'opponent', 'Opponent Owner',
    '{"pace":58,"shooting":58,"passing":58,"dribbling":58,"defending":58,"physical":58}',
    '{"pace":58,"shooting":58,"passing":58,"dribbling":58,"defending":58,"physical":58}',
    '{"pace":58,"shooting":58,"passing":58,"dribbling":58,"defending":58,"physical":58}', 58, 58, 58, 70, 'pachangas-rating-v2');

-- One INSERT is one transaction timestamp: the canonical reader must use the
-- stable UUID tie-breaker rather than depending on row-return order.
insert into public.pachanga_player_rating_snapshots(
  id, player_profile_id, snapshot_kind, base_facets, calibrated_facets,
  current_facets, base_overall, calibrated_overall, current_overall,
  reliability, evaluator_count, engine_version, created_at
)
select
  snapshot_ids.id,
  profiles.id,
  'recalculation',
  profiles.base_facets,
  profiles.calibrated_facets,
  profiles.current_facets,
  profiles.base_overall,
  profiles.calibrated_overall,
  profiles.current_overall,
  profiles.rating_reliability,
  profiles.rating_evaluator_count,
  'pachangas-rating-v2',
  '2026-01-01 10:00:00+00'::timestamptz
from public.pachanga_player_profiles profiles
cross join (values
  ('41000000-0000-0000-0000-000000000001'::uuid),
  ('41000000-0000-0000-0000-000000000002'::uuid),
  ('41000000-0000-0000-0000-000000000003'::uuid)
) snapshot_ids(id)
where profiles.user_id = '10000000-0000-0000-0000-000000000002';

select set_config(
  'rating_v2_test.target_profile_id',
  (select profiles.id::text
   from public.pachanga_player_profiles profiles
   where profiles.user_id = '10000000-0000-0000-0000-000000000002'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);

do $$
declare
  target_profile_id uuid;
  server_snapshot jsonb;
  repeated_server_snapshot jsonb;
  client_snapshot_id uuid;
begin
  select profiles.id into target_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = '10000000-0000-0000-0000-000000000002';

  server_snapshot := public.get_latest_pachanga_player_rating_snapshot_v2(target_profile_id);
  repeated_server_snapshot := public.get_latest_pachanga_player_rating_snapshot_v2(target_profile_id);
  select snapshots.id into client_snapshot_id
  from public.pachanga_player_rating_snapshots snapshots
  where snapshots.player_profile_id = target_profile_id
  order by snapshots.created_at desc, snapshots.id desc
  limit 1;

  perform pg_temp.assert_true(
    (select count(distinct snapshots.created_at)
     from public.pachanga_player_rating_snapshots snapshots
     where snapshots.player_profile_id = target_profile_id) = 1,
    'Canonical snapshot fixture must share one created_at'
  );
  perform pg_temp.assert_true(
    server_snapshot ->> 'id' = '41000000-0000-0000-0000-000000000003',
    'Server must select the stable highest UUID when created_at ties'
  );
  perform pg_temp.assert_true(
    (server_snapshot ->> 'id')::uuid = client_snapshot_id,
    'Server and authenticated client ordering must select the same snapshot'
  );
  perform pg_temp.assert_true(
    server_snapshot = repeated_server_snapshot,
    'Repeated canonical snapshot reads must be deterministic'
  );
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);

do $$
declare
  group_id constant uuid := '20000000-0000-0000-0000-000000000001';
  comparisons constant jsonb := '{"pace":"MEJOR","shooting":"PARECIDO","passing":"MEJOR","dribbling":"PEOR","defending":"PARECIDO","physical":"MUCHO_MEJOR"}';
  initial_revision bigint;
  first_result jsonb;
  replay_result jsonb;
  eligibility jsonb;
  summary jsonb;
begin
  select payload_revision into initial_revision from public.pachanga_groups where id = group_id;
  begin
    perform public.get_latest_pachanga_player_rating_snapshot_v2(
      current_setting('rating_v2_test.target_profile_id')::uuid
    );
    raise exception 'Another member unexpectedly read the target canonical snapshot';
  exception when others then
    if sqlerrm = 'Another member unexpectedly read the target canonical snapshot' then raise; end if;
    perform pg_temp.assert_true(
      position('Only the player' in sqlerrm) > 0,
      'Canonical snapshot RPC must preserve private player access'
    );
  end;
  eligibility := public.get_pachanga_rating_eligibility(group_id, 'target');
  perform pg_temp.assert_true((eligibility ->> 'canRate')::boolean and (eligibility ->> 'firstRating')::boolean, 'First rating must be immediate');

  first_result := public.record_pachanga_individual_rating_authoritative_v2(
    group_id, 'target', comparisons, '30000000-0000-0000-0000-000000000001', initial_revision,
    '{"sessionId":"sql-client-a","surface":"db-test"}'
  );
  replay_result := public.record_pachanga_individual_rating_authoritative_v2(
    group_id, 'target', comparisons, '30000000-0000-0000-0000-000000000001', initial_revision,
    '{"sessionId":"sql-client-a","surface":"db-test"}'
  );
  perform pg_temp.assert_true(first_result = replay_result, 'Idempotent replay must return the stored canonical response');
  perform pg_temp.assert_true((first_result ->> 'confirmedRevision')::bigint > initial_revision, 'Authoritative rating must increment the revision');
  perform pg_temp.assert_true((first_result ->> 'serverSequence')::bigint > 0, 'Authoritative rating must return a server sequence');
  perform pg_temp.assert_true(first_result ? 'payload', 'Authoritative rating must return the canonical payload');

  eligibility := public.get_pachanga_rating_eligibility(group_id, 'target');
  perform pg_temp.assert_true(not (eligibility ->> 'canRate')::boolean and (eligibility ->> 'sharedMatches')::integer = 0, 'Replacement must be blocked at 0 shared matches');
  summary := public.get_pachanga_player_rating_summary_v2(group_id, 'target');
  perform pg_temp.assert_true(summary ->> 'state' = 'calibrating' and (summary ->> 'evaluatorCount')::integer = 1, 'One evaluator must remain socially hidden');
  perform pg_temp.assert_true(summary -> 'calibratedFacets' = 'null'::jsonb and summary -> 'calibratedOverall' = 'null'::jsonb, 'Social details must be hidden before three evaluators');
  summary := public.get_pachanga_player_rating_summary_v2(group_id, 'zero');
  perform pg_temp.assert_true((summary ->> 'evaluatorCount')::integer = 0 and summary ->> 'state' = 'calibrating', 'Zero evaluator threshold must be explicit');

  begin
    perform public.record_pachanga_individual_rating_authoritative_v2(
      group_id, 'zero', comparisons, gen_random_uuid(), initial_revision, '{}'
    );
    raise exception 'Stale revision unexpectedly succeeded';
  exception when serialization_failure then null;
  end;
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$
begin
  begin
    perform public.record_pachanga_individual_rating_authoritative_v2(
      '20000000-0000-0000-0000-000000000001', 'zero',
      '{"pace":"PARECIDO","shooting":"PARECIDO","passing":"PARECIDO","dribbling":"PARECIDO","defending":"PARECIDO","physical":"PARECIDO"}',
      '30000000-0000-0000-0000-000000000001',
      (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'), '{}'
    );
    raise exception 'Operation replay by a different actor unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Operation replay by a different actor unexpectedly succeeded' then raise; end if;
    perform pg_temp.assert_true(position('another actor' in sqlerrm) > 0, 'Cross-actor operation reuse must be rejected');
  end;
end;
$$;
reset role;

-- Keep deterministic effective dates so the restoration assertions can prove
-- which action controls the three-match unlock window.
update public.pachanga_individual_rating_evidence
set created_at = '2026-01-01 12:00:00+00',
    opinion_created_at = '2026-01-01 12:00:00+00'
where operation_id = '30000000-0000-0000-0000-000000000001';

do $$
declare
  evaluator_profile uuid;
  target_profile uuid;
  index integer;
  finalized_at timestamptz := '2026-01-02 12:00:00+00';
begin
  select id into evaluator_profile from public.pachanga_player_profiles where user_id = '10000000-0000-0000-0000-000000000001';
  select id into target_profile from public.pachanga_player_profiles where user_id = '10000000-0000-0000-0000-000000000002';
  for index in 1..3 loop
    insert into public.pachanga_match_rating_snapshots(group_id, match_id, engine_version, snapshot, finalized_at)
    values ('20000000-0000-0000-0000-000000000001', 'shared-' || index, 'pachangas-rating-v2', '{}'::jsonb, finalized_at + make_interval(days => index));
    insert into public.pachanga_match_rating_participants(
      group_id, match_id, local_player_id, player_profile_id, team_side, attendance_confirmed, was_reserve, card_snapshot
    ) values
      ('20000000-0000-0000-0000-000000000001', 'shared-' || index, 'evaluator', evaluator_profile, case when index = 1 then 'A' else 'B' end, true, false, '{"currentOverall":60}'),
      ('20000000-0000-0000-0000-000000000001', 'shared-' || index, 'target', target_profile, 'A', true, false, '{"currentOverall":50}');
  end loop;

  insert into public.pachanga_match_rating_snapshots(group_id, match_id, engine_version, snapshot, finalized_at)
  values
    ('20000000-0000-0000-0000-000000000001', 'absence', 'pachangas-rating-v2', '{}', finalized_at + interval '5 days'),
    ('20000000-0000-0000-0000-000000000001', 'reserve', 'pachangas-rating-v2', '{}', finalized_at + interval '6 days'),
    ('20000000-0000-0000-0000-000000000001', 'voided', 'pachangas-rating-v2', '{}', finalized_at + interval '7 days');
  update public.pachanga_match_rating_snapshots set state = 'void' where match_id = 'voided';
  insert into public.pachanga_match_rating_participants(
    group_id, match_id, local_player_id, player_profile_id, team_side, attendance_confirmed, was_reserve, card_snapshot
  ) values
    ('20000000-0000-0000-0000-000000000001', 'absence', 'evaluator', evaluator_profile, 'A', false, false, '{}'),
    ('20000000-0000-0000-0000-000000000001', 'absence', 'target', target_profile, 'A', true, false, '{}'),
    ('20000000-0000-0000-0000-000000000001', 'reserve', 'evaluator', evaluator_profile, 'A', true, true, '{}'),
    ('20000000-0000-0000-0000-000000000001', 'reserve', 'target', target_profile, 'A', true, false, '{}'),
    ('20000000-0000-0000-0000-000000000001', 'voided', 'evaluator', evaluator_profile, 'A', true, false, '{}'),
    ('20000000-0000-0000-0000-000000000001', 'voided', 'target', target_profile, 'A', true, false, '{}');
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
declare
  group_id constant uuid := '20000000-0000-0000-0000-000000000001';
  comparisons constant jsonb := '{"pace":"MEJOR","shooting":"PARECIDO","passing":"MEJOR","dribbling":"PEOR","defending":"PARECIDO","physical":"MUCHO_MEJOR"}';
  eligibility jsonb;
  revision bigint;
  result jsonb;
  active_count integer;
  history_count integer;
begin
  eligibility := public.get_pachanga_rating_eligibility(group_id, 'target');
  perform pg_temp.assert_true((eligibility ->> 'canRate')::boolean and (eligibility ->> 'sharedMatches')::integer = 3, 'Exactly three valid shared matches must unlock replacement');
  select payload_revision into revision from public.pachanga_groups where id = group_id;
  result := public.record_pachanga_individual_rating_authoritative_v2(
    group_id, 'target', comparisons, '30000000-0000-0000-0000-000000000002', revision,
    '{"sessionId":"sql-client-a"}'
  );
  select count(*) into active_count
  from public.pachanga_individual_rating_evidence evidence
  where evidence.operation_id in (
    '30000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002'
  ) and evidence.state = 'active';
  select count(*) into history_count
  from public.pachanga_individual_rating_evidence evidence
  where evidence.operation_id in (
    '30000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000002'
  );
  perform pg_temp.assert_true(
    active_count = 1 and history_count = 2,
    format('Replacement must keep one active opinion and immutable history (active=%s, history=%s)', active_count, history_count)
  );
  perform pg_temp.assert_true((result ->> 'confirmedRevision')::bigint > revision, 'Replacement must return a newer revision');
end;
$$;

reset role;
update public.pachanga_individual_rating_evidence
set created_at = '2026-02-01 12:00:00+00',
    opinion_created_at = '2026-02-01 12:00:00+00'
where operation_id = '30000000-0000-0000-0000-000000000002';
set local role authenticated;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000004', true);
select public.record_pachanga_individual_rating_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'target',
  '{"pace":"PARECIDO","shooting":"PARECIDO","passing":"PARECIDO","dribbling":"PARECIDO","defending":"PARECIDO","physical":"PARECIDO"}',
  '30000000-0000-0000-0000-000000000004',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"sql-client-b"}'
) as ignored \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$
declare summary jsonb;
begin
  summary := public.get_pachanga_player_rating_summary_v2('20000000-0000-0000-0000-000000000001', 'target');
  perform pg_temp.assert_true((summary ->> 'evaluatorCount')::integer = 2 and summary ->> 'state' = 'calibrating', 'Two evaluators must remain socially hidden');
  perform pg_temp.assert_true(summary -> 'calibratedFacets' = 'null'::jsonb, 'Two-vote facet detail must be hidden');
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000005', true);
select public.record_pachanga_individual_rating_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'target',
  '{"pace":"PEOR","shooting":"PEOR","passing":"PEOR","dribbling":"PEOR","defending":"PEOR","physical":"PEOR"}',
  '30000000-0000-0000-0000-000000000005',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"sql-client-c"}'
) as ignored \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
do $$
declare summary jsonb;
begin
  summary := public.get_pachanga_player_rating_summary_v2('20000000-0000-0000-0000-000000000001', 'target');
  perform pg_temp.assert_true((summary ->> 'evaluatorCount')::integer = 3 and summary ->> 'state' = 'ready', 'Three evaluators must unlock aggregate disclosure');
  perform pg_temp.assert_true(jsonb_typeof(summary -> 'calibratedFacets') = 'object' and (summary ->> 'calibratedOverall')::numeric between 0 and 100, 'Three-vote aggregate must expose only bounded aggregate data');
  perform pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence) = 0, 'Evaluated player must not read individual evidence');
end;
$$;

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
do $$
declare
  moderation jsonb;
  disabled_result jsonb;
  enabled_result jsonb;
  revision bigint;
begin
  perform pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence) = 0, 'Ordinary group admins must not read evaluator identities');
  moderation := public.list_pachanga_rating_moderation_v2('20000000-0000-0000-0000-000000000001');
  perform pg_temp.assert_true(moderation::text not like '%10000000-0000-0000-0000-000000000001%' and moderation::text not like '%Evaluator%', 'Moderation output must not reveal evaluator identity');
  select payload_revision into revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001';
  disabled_result := public.set_pachanga_group_ratings_enabled_authoritative_v2(
    '20000000-0000-0000-0000-000000000001', false,
    '30000000-0000-0000-0000-000000000006', revision, '{"sessionId":"admin"}'
  );
  perform pg_temp.assert_true(disabled_result ->> 'ratingsEnabled' = 'false', 'Admin must be able to disable ratings');
  select payload_revision into revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001';
  enabled_result := public.set_pachanga_group_ratings_enabled_authoritative_v2(
    '20000000-0000-0000-0000-000000000001', true,
    '30000000-0000-0000-0000-000000000007', revision, '{"sessionId":"admin"}'
  );
  perform pg_temp.assert_true(enabled_result ->> 'ratingsEnabled' = 'true', 'Admin must be able to re-enable ratings');
end;
$$;

reset role;
select pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence where group_id = '20000000-0000-0000-0000-000000000001') = 4, 'Settings switch must preserve rating history');
select pg_temp.assert_true((select count(*) from public.pachanga_rating_config_events where group_id = '20000000-0000-0000-0000-000000000001') = 2, 'Rating settings changes must be audited');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
declare
  first_evidence uuid;
  second_evidence uuid;
  first_created_at timestamptz;
  first_opinion_created_at timestamptz;
  first_confidence numeric;
  evidence_count_before integer;
  revision bigint;
  void_result jsonb;
  own_rating jsonb;
  eligibility jsonb;
begin
  select ratings.id, ratings.created_at, ratings.opinion_created_at,
         ratings.evaluator_confidence_snapshot
  into first_evidence, first_created_at, first_opinion_created_at, first_confidence
  from public.pachanga_individual_rating_evidence ratings
  where ratings.operation_id = '30000000-0000-0000-0000-000000000001';
  select ratings.id into second_evidence
  from public.pachanga_individual_rating_evidence ratings
  where ratings.operation_id = '30000000-0000-0000-0000-000000000002';
  select count(*) into evidence_count_before
  from public.pachanga_individual_rating_evidence ratings
  where ratings.evaluator_profile_id = (
      select profiles.id from public.pachanga_player_profiles profiles
      where profiles.user_id = '10000000-0000-0000-0000-000000000001'
    )
    and ratings.target_profile_id = (
      select profiles.id from public.pachanga_player_profiles profiles
      where profiles.user_id = '10000000-0000-0000-0000-000000000002'
    );
  select payload_revision into revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001';
  void_result := public.void_my_pachanga_individual_rating_v2(
    second_evidence, 'SQL integration withdrawal', '30000000-0000-0000-0000-000000000008', revision,
    '{"sessionId":"sql-client-a"}'
  );
  perform pg_temp.assert_true(void_result ->> 'state' = 'void', 'Own rating withdrawal must persist void state');
  perform pg_temp.assert_true(
    (void_result ->> 'restoredEvidenceId')::uuid = first_evidence,
    'Voiding the second opinion must reactivate the original evidence id'
  );
  perform pg_temp.assert_true(
    (select ratings.state from public.pachanga_individual_rating_evidence ratings where ratings.id = first_evidence) = 'active'
    and (select ratings.state from public.pachanga_individual_rating_evidence ratings where ratings.id = second_evidence) = 'void',
    'The first opinion must be active and the second must be void'
  );
  perform pg_temp.assert_true(
    (select ratings.created_at from public.pachanga_individual_rating_evidence ratings where ratings.id = first_evidence) = first_created_at
    and (select ratings.opinion_created_at from public.pachanga_individual_rating_evidence ratings where ratings.id = first_evidence) = first_opinion_created_at,
    'Restoration must preserve the original row and effective opinion date'
  );
  perform pg_temp.assert_true(
    (select ratings.restored_at from public.pachanga_individual_rating_evidence ratings where ratings.id = first_evidence) > first_opinion_created_at,
    'restoredAt must be stored separately from opinionCreatedAt'
  );
  perform pg_temp.assert_true(
    (select ratings.evaluator_confidence_snapshot from public.pachanga_individual_rating_evidence ratings where ratings.id = first_evidence) = first_confidence,
    'Restoration must not add evaluator weight'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_individual_rating_evidence ratings
      where ratings.evaluator_profile_id = (
        select profiles.id from public.pachanga_player_profiles profiles
        where profiles.user_id = '10000000-0000-0000-0000-000000000001'
      ) and ratings.target_profile_id = (
        select profiles.id from public.pachanga_player_profiles profiles
        where profiles.user_id = '10000000-0000-0000-0000-000000000002'
      )) = evidence_count_before,
    'Restoration must not insert a new rating row'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1 from public.pachanga_individual_rating_evidence ratings
      where ratings.evaluator_profile_id = (
        select profiles.id from public.pachanga_player_profiles profiles
        where profiles.user_id = '10000000-0000-0000-0000-000000000001'
      ) and ratings.target_profile_id = (
        select profiles.id from public.pachanga_player_profiles profiles
        where profiles.user_id = '10000000-0000-0000-0000-000000000002'
      ) and ratings.source = 'restored'
    ),
    'Restoration must not create a synthetic restored vote'
  );
  perform pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence ratings where ratings.state = 'active' and ratings.group_id = '20000000-0000-0000-0000-000000000001') = 1, 'Void restoration must preserve exactly one active opinion');
  own_rating := public.get_my_pachanga_rating_v2('20000000-0000-0000-0000-000000000001', 'target');
  perform pg_temp.assert_true(
    (own_rating -> 'rating' ->> 'evidenceId')::uuid = first_evidence
    and (own_rating -> 'rating' ->> 'opinionCreatedAt')::timestamptz = first_opinion_created_at
    and (own_rating -> 'rating' ->> 'restoredAt')::timestamptz > first_opinion_created_at,
    'Own-rating read must expose separate original and restoration dates'
  );
  eligibility := public.get_pachanga_rating_eligibility('20000000-0000-0000-0000-000000000001', 'target');
  perform pg_temp.assert_true(
    not (eligibility ->> 'canRate')::boolean
    and (eligibility ->> 'sharedMatches')::integer = 0
    and (eligibility ->> 'previousRatingAt')::timestamptz = '2026-02-01 12:00:00+00'::timestamptz,
    'Restoration must keep the unlock cutoff at the latest opinion really emitted'
  );
end;
$$;

reset role;

do $$
declare
  evaluator_profile uuid;
  target_profile uuid;
begin
  select id into evaluator_profile from public.pachanga_player_profiles where user_id = '10000000-0000-0000-0000-000000000001';
  select id into target_profile from public.pachanga_player_profiles where user_id = '10000000-0000-0000-0000-000000000002';
  insert into public.pachanga_match_rating_snapshots(
    group_id, match_id, engine_version, snapshot, finalized_at
  ) values (
    '20000000-0000-0000-0000-000000000001', 'post-second-pre-restore',
    'pachangas-rating-v2', '{}', '2026-02-02 12:00:00+00'
  );
  insert into public.pachanga_match_rating_participants(
    group_id, match_id, local_player_id, player_profile_id, team_side,
    attendance_confirmed, was_reserve, card_snapshot
  ) values
    ('20000000-0000-0000-0000-000000000001', 'post-second-pre-restore', 'evaluator', evaluator_profile, 'A', true, false, '{"currentOverall":60}'),
    ('20000000-0000-0000-0000-000000000001', 'post-second-pre-restore', 'target', target_profile, 'B', true, false, '{"currentOverall":50}');

  perform pg_temp.assert_true(
    (select profiles.rating_evaluator_count from public.pachanga_player_profiles profiles
      where profiles.id = target_profile) = 3,
    'Restoring one evaluator must not increase the independent evaluator count'
  );
  perform pg_temp.assert_true(
    exists (
      select 1
      from public.pachanga_player_rating_snapshots snapshots
      where snapshots.player_profile_id = target_profile
        and cardinality(snapshots.active_evidence_ids) = 3
        and snapshots.active_evidence_ids @> array[
        (select ratings.id from public.pachanga_individual_rating_evidence ratings
         where ratings.operation_id = '30000000-0000-0000-0000-000000000001')
        ]
        and not snapshots.active_evidence_ids @> array[
        (select ratings.id from public.pachanga_individual_rating_evidence ratings
         where ratings.operation_id = '30000000-0000-0000-0000-000000000002')
        ]
    ),
    'The recalculated card must use the original opinion once, exclude the voided replacement and keep three evaluator weights'
  );
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
do $$
declare eligibility jsonb;
begin
  eligibility := public.get_pachanga_rating_eligibility('20000000-0000-0000-0000-000000000001', 'target');
  perform pg_temp.assert_true(
    not (eligibility ->> 'canRate')::boolean
    and (eligibility ->> 'sharedMatches')::integer = 1
    and (eligibility ->> 'previousRatingAt')::timestamptz = '2026-02-01 12:00:00+00'::timestamptz,
    'A match after the last emitted opinion but before restoration must count; restoration itself must not reset the window'
  );
end;
$$;

do $$
begin
  perform pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence) > 0, 'Evaluator must read own evidence');
  perform pg_temp.assert_true((select count(*) from public.pachanga_operation_receipts where operation_type like 'individual_rating%') > 0, 'Evaluator must read own private operation receipts');
end;
$$;
reset role;

set local role service_role;
do $$
begin
  perform pg_temp.assert_true((select count(*) from public.pachanga_individual_rating_evidence) >= 3, 'Internal security role must retain investigative access');
end;
$$;
reset role;

do $$
begin
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.record_pachanga_individual_rating_v2(uuid,text,jsonb,uuid)', 'EXECUTE'), 'Legacy absolute individual RPC must be closed');
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.void_pachanga_individual_rating_v2(uuid,text,uuid)', 'EXECUTE'), 'Legacy void RPC must be closed');
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.save_pachanga_payload_if_current(uuid,bigint,jsonb)', 'EXECUTE'), 'Legacy full payload save must be closed');
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.finalize_pachanga_match_if_current(uuid,bigint,text,jsonb,uuid)', 'EXECUTE'), 'Legacy finalization RPC must be closed');
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.persist_pachanga_player_assessment_v2(uuid,uuid,text,text,jsonb,jsonb,uuid)', 'EXECUTE'), 'Legacy assessment persistence must be closed');
  perform pg_temp.assert_true(not has_function_privilege('authenticated', 'public.persist_pachanga_player_assessment_authoritative_v2(uuid,uuid,text,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'), 'Assessment persistence must be service-only');
  perform pg_temp.assert_true(has_function_privilege('service_role', 'public.persist_pachanga_player_assessment_authoritative_v2(uuid,uuid,text,text,jsonb,jsonb,uuid,bigint,jsonb)', 'EXECUTE'), 'Service role must persist server-calculated assessments');
  perform pg_temp.assert_true(not has_table_privilege('authenticated', 'public.pachanga_groups', 'UPDATE'), 'Authenticated clients must not update group payloads directly');
  perform pg_temp.assert_true(not has_table_privilege('authenticated', 'public.pachanga_individual_rating_evidence', 'INSERT'), 'Authenticated clients must not insert rating evidence directly');
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
do $$
declare
  current_payload jsonb;
  forged_payload jsonb;
  revision bigint;
begin
  select payload, payload_revision into current_payload, revision
  from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001';
  forged_payload := jsonb_set(current_payload, '{players,0,ratingV2,currentOverall}', '100'::jsonb, true);
  begin
    perform public.save_pachanga_payload_authoritative_v2(
      '20000000-0000-0000-0000-000000000001', revision, forged_payload,
      '30000000-0000-0000-0000-000000000009', '{"sessionId":"forger"}'
    );
    raise exception 'Forged player card unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Forged player card unexpectedly succeeded' then raise; end if;
    perform pg_temp.assert_true(position('server managed' in sqlerrm) > 0, 'Forged card must be rejected by the server');
  end;
end;
$$;
reset role;

insert into public.pachanga_match_rating_snapshots(
  group_id, match_id, engine_version, snapshot, finalized_at, group_level, lineup_a_level, lineup_b_level
) values (
  '20000000-0000-0000-0000-000000000001', 'global-1', 'pachangas-rating-v2', '{}', clock_timestamp(), 55, 55, 65
);

insert into public.pachanga_match_rating_participants(
  group_id, match_id, local_player_id, player_profile_id, team_side,
  attendance_confirmed, was_reserve, card_snapshot
) values (
  '20000000-0000-0000-0000-000000000001', 'global-1', 'admin',
  (select id from public.pachanga_player_profiles where user_id = '10000000-0000-0000-0000-000000000003'),
  'A', true, false, '{"currentOverall":55}'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select
  (public.create_pachanga_guest_identity_authoritative_v2(
    '20000000-0000-0000-0000-000000000001', 'Guest test', null,
    '30000000-0000-0000-0000-000000000010',
    (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
    '{"sessionId":"admin"}'
  ) ->> 'guestId') as guest_id
\gset
reset role;

insert into public.pachanga_match_rating_participants(
  group_id, match_id, local_player_id, guest_identity_id, team_side, attendance_confirmed, was_reserve, card_snapshot
) values (
  '20000000-0000-0000-0000-000000000001', 'global-1', 'guest', :'guest_id', 'A', true, false,
  '{"currentOverall":55,"provisional":true}'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select public.record_pachanga_global_rating_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'global-1', 'guest', 'PARECIDO', :'guest_id', null, null,
  '30000000-0000-0000-0000-000000000011',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-a"}'
) as ignored \gset

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select public.record_pachanga_global_rating_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'global-1', 'guest', 'MEJOR', :'guest_id', null, null,
  '30000000-0000-0000-0000-000000000012',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-b"}'
) as ignored \gset
reset role;

select pg_temp.assert_true((select count(*) from public.pachanga_global_rating_evidence where group_id = '20000000-0000-0000-0000-000000000001' and match_id = 'global-1' and guest_identity_id = :'guest_id') = 1, 'Two admins must produce one official guest observation');
select pg_temp.assert_true((select response_count from public.pachanga_global_rating_evidence where group_id = '20000000-0000-0000-0000-000000000001' and match_id = 'global-1' and guest_identity_id = :'guest_id') = 2, 'Official guest observation must retain two admin responses');
select pg_temp.assert_true(abs((select official_observation from public.pachanga_global_rating_evidence where group_id = '20000000-0000-0000-0000-000000000001' and match_id = 'global-1' and guest_identity_id = :'guest_id') - 57.5) < 0.000000001, 'Admin responses must aggregate before weighting');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select
  (public.issue_pachanga_guest_rating_token_authoritative_v2(
    '20000000-0000-0000-0000-000000000001', 'global-1', :'guest_id',
    '30000000-0000-0000-0000-000000000013',
    (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
    30, '{"sessionId":"admin-a"}'
  ) ->> 'token') as guest_token
\gset
reset role;

set local role anon;
select
  (public.get_pachanga_guest_rating_token_context_v2(:'guest_token') ->> 'confirmedRevision')::bigint as guest_revision
\gset
select public.record_pachanga_guest_team_rating_token_v2(
  :'guest_token', 'MEJOR', '30000000-0000-0000-0000-000000000014', :guest_revision,
  '{"sessionId":"guest-device"}'
) as guest_response \gset
select public.record_pachanga_guest_team_rating_token_v2(
  :'guest_token', 'MEJOR', '30000000-0000-0000-0000-000000000014', :guest_revision,
  '{"sessionId":"guest-device"}'
) as guest_replay \gset
reset role;

select pg_temp.assert_true(:'guest_response'::jsonb = :'guest_replay'::jsonb, 'Guest token operation must replay idempotently');
select pg_temp.assert_true((:'guest_response'::jsonb ->> 'confirmedRevision')::bigint > :guest_revision, 'Guest token operation must advance the canonical revision');
select pg_temp.assert_true(not exists (select 1 from public.pachanga_guest_rating_tokens where token_hash = :'guest_token'), 'Guest token must never be stored in plaintext');
select pg_temp.assert_true(exists (select 1 from public.pachanga_guest_rating_tokens where consumed_operation_id = '30000000-0000-0000-0000-000000000014' and client_metadata ->> 'sessionId' = 'guest-device'), 'Guest operation metadata must be stored as non-authoritative audit context');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select public.link_pachanga_registered_opponent_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'global-1', 'OPPV2',
  '30000000-0000-0000-0000-000000000015',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-a"}'
) as ignored \gset
select public.record_pachanga_global_rating_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', 'global-1', 'registered_group', 'MEJOR', null, null,
  '20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000016',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-a"}'
) as registered_result \gset

select public.link_pachanga_guest_identity_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', :'guest_id',
  '10000000-0000-0000-0000-000000000001', 'Registered later',
  '30000000-0000-0000-0000-000000000017',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-a"}'
) as ignored \gset
select public.reverse_pachanga_guest_link_authoritative_v2(
  '20000000-0000-0000-0000-000000000001', :'guest_id', 'Incorrect association',
  '30000000-0000-0000-0000-000000000018',
  (select payload_revision from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000001'),
  '{"sessionId":"admin-a"}'
) as ignored \gset
reset role;

select pg_temp.assert_true((:'registered_result'::jsonb -> 'calibrationTarget' ->> 'groupId')::uuid = '20000000-0000-0000-0000-000000000002', 'Registered rival response must return a redacted canonical calibration target');
select pg_temp.assert_true((select externally_calibrated_level from public.pachanga_groups where id = '20000000-0000-0000-0000-000000000002') is not null, 'Registered rival must receive external calibration without changing player cards');
select pg_temp.assert_true((select link_state from public.pachanga_guest_identities where id = :'guest_id') = 'reversed', 'Guest link reversal must be persisted');
select pg_temp.assert_true((select count(*) from public.pachanga_guest_link_events where guest_identity_id = :'guest_id') = 2, 'Guest link and reversal must remain auditable');

rollback;
