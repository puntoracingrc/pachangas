\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.create_external_match(
  challenge_uuid uuid,
  home_group_uuid uuid,
  away_group_uuid uuid,
  actor_uuid uuid,
  scheduled timestamptz
)
returns uuid
language plpgsql
as $$
declare
  saved_match_id uuid;
begin
  insert into public.pachanga_team_challenges(
    id, sender_group_id, receiver_group_id, status, revision, proposal_number,
    scheduled_at, modality, field_name, field_address, last_proposed_by_group_id,
    created_by, updated_by
  ) values (
    challenge_uuid, home_group_uuid, away_group_uuid, 'proposed', 1, 1,
    greatest(scheduled, clock_timestamp() + interval '1 day'),
    'futbol7', 'Campo de prueba', 'Carrer de la Prova, 1',
    home_group_uuid, actor_uuid, actor_uuid
  );
  update public.pachanga_team_challenges
  set status = 'accepted', revision = 2, accepted_at = clock_timestamp(),
      updated_by = actor_uuid, updated_at = clock_timestamp()
  where id = challenge_uuid;
  select matches.id into strict saved_match_id
  from public.pachanga_external_matches matches
  where matches.challenge_id = challenge_uuid;
  update public.pachanga_external_matches
  set scheduled_at = scheduled
  where id = saved_match_id;
  return saved_match_id;
end;
$$;

insert into auth.users(id, email) values
  ('81000000-0000-0000-0000-000000000001', 'achievement-owner-a@example.test'),
  ('81000000-0000-0000-0000-000000000002', 'achievement-admin-a@example.test'),
  ('81000000-0000-0000-0000-000000000003', 'achievement-owner-b@example.test'),
  ('81000000-0000-0000-0000-000000000004', 'achievement-member-a@example.test'),
  ('81000000-0000-0000-0000-000000000005', 'achievement-third@example.test'),
  ('81000000-0000-0000-0000-000000000006', 'achievement-late@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    '82000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    'Equipo Logros A', 'LOGROSA',
    '{"players":[
      {"id":"a1","name":"Ana","ownerUserId":"81000000-0000-0000-0000-000000000001","position":"DEL"},
      {"id":"a2","name":"Alex","ownerUserId":"81000000-0000-0000-0000-000000000004","position":"MC"}
    ]}'::jsonb
  ),
  (
    '82000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000003',
    'Equipo Logros B', 'LOGROSB',
    '{"players":[
      {"id":"b1","name":"Berta","ownerUserId":"81000000-0000-0000-0000-000000000003","position":"DEL"},
      {"id":"b2","name":"Bruno","position":"POR"}
    ]}'::jsonb
  ),
  (
    '82000000-0000-0000-0000-000000000003',
    '81000000-0000-0000-0000-000000000005',
    'Equipo Ajeno', 'AJENO1', '{"players":[]}'::jsonb
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 'owner', 'Ana'),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000002', 'admin', 'Admin A'),
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000004', 'player', 'Alex'),
  ('82000000-0000-0000-0000-000000000002', '81000000-0000-0000-0000-000000000003', 'owner', 'Berta'),
  ('82000000-0000-0000-0000-000000000003', '81000000-0000-0000-0000-000000000005', 'owner', 'Tercero');

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values
  (
    '82500000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001', 'Ana', 'DEL', 68, 66, 67,
    '{"pace":70,"shooting":69,"passing":66,"dribbling":68,"defending":60,"physical":65}',
    72, 'pachangas-rating-v2'
  ),
  (
    '82500000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000004', 'Alex', 'MC', 64, 62, 63,
    '{"pace":63,"shooting":61,"passing":68,"dribbling":64,"defending":62,"physical":60}',
    65, 'pachangas-rating-v2'
  ),
  (
    '82500000-0000-0000-0000-000000000003',
    '81000000-0000-0000-0000-000000000003', 'Berta', 'DEL', 66, 64, 65,
    '{"pace":67,"shooting":68,"passing":62,"dribbling":66,"defending":58,"physical":64}',
    70, 'pachangas-rating-v2'
  );

select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '1 day'
) as normal_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000002',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '2 days'
) as accepted_correction_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000003',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '3 days'
) as rejected_correction_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000004',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '4 days'
) as silence_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000005',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '5 days'
) as correction_silence_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000006',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '6 days'
) as zero_match \gset
select pg_temp.create_external_match(
  '83000000-0000-0000-0000-000000000007',
  '82000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000002',
  '81000000-0000-0000-0000-000000000001',
  clock_timestamp() - interval '7 days'
) as validation_match \gset
select set_config('pachangas.test_validation_match', :'validation_match', true);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_external_matches
    where challenge_id between '83000000-0000-0000-0000-000000000001'::uuid
      and '83000000-0000-0000-0000-000000000007'::uuid) = 7,
  'Every accepted challenge must create exactly one normalized external match'
);

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_external_matches', 'INSERT'),
  'Authenticated clients must not insert external matches directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_achievement_grants', 'UPDATE'),
  'Authenticated clients must not update achievement grants directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_team_crest_versions', 'INSERT'),
  'Authenticated clients must not publish crest versions directly'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.run_pachanga_external_result_expiry_v1(uuid,integer,timestamptz)',
    'EXECUTE'
  ),
  'The expiry service must not be callable by authenticated clients'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.annul_pachanga_external_result_v1(uuid,text,uuid,bigint)',
    'EXECUTE'
  ),
  'External result annulment must remain service-only'
);

-- Normal confirmation and an exact idempotent replay.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'normal_match'::uuid,
  3, 1, array['a1','a2'],
  '[{"playerId":"a1","goals":2},{"playerId":"a2","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000001', 1,
  '{"sessionId":"normal-home"}'::jsonb
) as normal_published \gset
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.confirm_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000002', :'normal_match'::uuid,
  array['b1','b2'], '[{"playerId":"b1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000002', 2,
  '{"sessionId":"normal-away"}'::jsonb
) as normal_confirmed \gset
select public.confirm_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000002', :'normal_match'::uuid,
  array['b1','b2'], '[{"playerId":"b1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000002', 2,
  '{"sessionId":"normal-away"}'::jsonb
) as normal_replayed \gset
reset role;

select pg_temp.assert_true(
  :'normal_confirmed'::jsonb = :'normal_replayed'::jsonb,
  'Repeating one operation id must replay the same canonical confirmation'
);
select pg_temp.assert_true(
  (select state = 'confirmed' and official_version = 1 and revision = 3
   from public.pachanga_external_matches where id = :'normal_match'::uuid),
  'The normal bilateral flow must create one official version'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_external_result_events
   where external_match_id = :'normal_match'::uuid
     and event_type = 'match_result_confirmed') = 1,
  'The official result event must be emitted once'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_progression_match_facts
   where source_match_id = :'normal_match' and state = 'active') = 2,
  'One canonical result must create one fact per team'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
   where grants.group_id = '82000000-0000-0000-0000-000000000001'
     and definitions.achievement_key in ('team.matches.001','team.external.wins.001')
     and grants.state = 'active') = 2,
  'The first external win must award the match and win achievements once'
);

-- Accepted correction.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'accepted_correction_match'::uuid,
  2, 1, array['a1'], '[{"playerId":"a1","goals":2}]'::jsonb,
  '84000000-0000-0000-0000-000000000003', 1, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.propose_pachanga_external_result_change_v1(
  '82000000-0000-0000-0000-000000000002', :'accepted_correction_match'::uuid,
  2, 2, array['b1'], '[{"playerId":"b1","goals":2}]'::jsonb,
  '84000000-0000-0000-0000-000000000004', 2, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.confirm_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'accepted_correction_match'::uuid,
  array['a1'], '[{"playerId":"a1","goals":2}]'::jsonb,
  '84000000-0000-0000-0000-000000000005', 3, '{}'::jsonb
);
reset role;
select pg_temp.assert_true(
  (select state = 'confirmed' and official_version = 2
     and canonical_score_home = 2 and canonical_score_away = 2
   from public.pachanga_external_matches where id = :'accepted_correction_match'::uuid),
  'An accepted correction must become the only official version'
);

-- Rejected correction.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'rejected_correction_match'::uuid,
  1, 0, array['a1'], '[{"playerId":"a1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000006', 1, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.propose_pachanga_external_result_change_v1(
  '82000000-0000-0000-0000-000000000002', :'rejected_correction_match'::uuid,
  1, 1, array['b1'], '[{"playerId":"b1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000007', 2, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.reject_pachanga_external_result_change_v1(
  '82000000-0000-0000-0000-000000000001', :'rejected_correction_match'::uuid,
  '84000000-0000-0000-0000-000000000008', 3, '{}'::jsonb
);
reset role;
select pg_temp.assert_true(
  (select state = 'disputed' and official_version is null
   from public.pachanga_external_matches where id = :'rejected_correction_match'::uuid),
  'Rejecting a correction must leave the match disputed without statistics'
);
select pg_temp.assert_true(
  not exists (select 1 from public.pachanga_progression_match_facts
    where source_match_id = :'rejected_correction_match'),
  'A disputed result must not create progression facts'
);

-- Initial silence auto-confirms, but leaves the silent goals unassigned.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'silence_match'::uuid,
  2, 1, array['a1'], '[{"playerId":"a1","goals":2}]'::jsonb,
  '84000000-0000-0000-0000-000000000009', 1, '{}'::jsonb
);
reset role;
update public.pachanga_external_matches
set response_deadline = clock_timestamp() - interval '1 second'
where id = :'silence_match'::uuid;
set local role service_role;
select public.run_pachanga_external_result_expiry_v1(
  '84000000-0000-0000-0000-000000000010', 100, clock_timestamp()
);
reset role;
select pg_temp.assert_true(
  (select state = 'auto_confirmed' and canonical_unassigned_home = 0
     and canonical_unassigned_away = 1 and revision = 3
   from public.pachanga_external_matches where id = :'silence_match'::uuid),
  'Initial silence must auto-confirm while retaining unassigned rival goals'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts match_facts on match_facts.id = player_facts.match_fact_id
    where match_facts.source_match_id = :'silence_match'
      and player_facts.group_id = '82000000-0000-0000-0000-000000000002'
  ),
  'Unassigned goals must not create individual achievement facts'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.complete_pachanga_external_scorers_v1(
  '82000000-0000-0000-0000-000000000002', :'silence_match'::uuid,
  array['b1'], '[{"playerId":"b1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000011', 3, '{}'::jsonb
);
reset role;
select pg_temp.assert_true(
  (select canonical_unassigned_away = 0 and revision = 4
   from public.pachanga_external_matches where id = :'silence_match'::uuid),
  'The silent team can later complete its own canonical scorers'
);

-- Silence after a correction becomes a dispute and never auto-accepts it.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'correction_silence_match'::uuid,
  2, 0, array['a1'], '[{"playerId":"a1","goals":2}]'::jsonb,
  '84000000-0000-0000-0000-000000000012', 1, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.propose_pachanga_external_result_change_v1(
  '82000000-0000-0000-0000-000000000002', :'correction_silence_match'::uuid,
  2, 1, array['b1'], '[{"playerId":"b1","goals":1}]'::jsonb,
  '84000000-0000-0000-0000-000000000013', 2, '{}'::jsonb
);
reset role;
update public.pachanga_external_matches
set response_deadline = clock_timestamp() - interval '1 second'
where id = :'correction_silence_match'::uuid;
set local role service_role;
select public.run_pachanga_external_result_expiry_v1(
  '84000000-0000-0000-0000-000000000014', 100, clock_timestamp()
);
reset role;
select pg_temp.assert_true(
  (select state = 'disputed' and official_version is null
   from public.pachanga_external_matches where id = :'correction_silence_match'::uuid),
  'Silence after a correction must become a dispute'
);

-- A scoreless draw is valid with participants and no scorer rows.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000001', :'zero_match'::uuid,
  0, 0, array['a1'], '[]'::jsonb,
  '84000000-0000-0000-0000-000000000015', 1, '{}'::jsonb
);
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000003', true);
select public.confirm_pachanga_external_result_v1(
  '82000000-0000-0000-0000-000000000002', :'zero_match'::uuid,
  array['b1'], '[]'::jsonb,
  '84000000-0000-0000-0000-000000000016', 2, '{}'::jsonb
);
reset role;
select pg_temp.assert_true(
  (select count(*) from public.pachanga_progression_match_facts
   where source_match_id = :'zero_match' and scoreless_draw and state = 'active') = 2,
  'A 0-0 must create one scoreless-draw fact per team'
);

-- Invalid scorer sums, rival participants and nonparticipants are rejected atomically.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform public.publish_pachanga_external_result_v1(
    '82000000-0000-0000-0000-000000000001',
    current_setting('pachangas.test_validation_match')::uuid,
    2, 0, array['a1'], '[{"playerId":"a1","goals":1}]'::jsonb,
    '84000000-0000-0000-0000-000000000017', 1, '{}'::jsonb
  );
  raise exception 'An incorrect scorer sum unexpectedly succeeded';
exception when others then
  if sqlerrm = 'An incorrect scorer sum unexpectedly succeeded' then raise; end if;
  if sqlerrm <> 'Own scorers must add up exactly to the team score' then raise; end if;
end;
$$;
do $$
begin
  perform public.publish_pachanga_external_result_v1(
    '82000000-0000-0000-0000-000000000001',
    current_setting('pachangas.test_validation_match')::uuid,
    1, 0, array['b1'], '[{"playerId":"b1","goals":1}]'::jsonb,
    '84000000-0000-0000-0000-000000000018', 1, '{}'::jsonb
  );
  raise exception 'A rival participant unexpectedly succeeded';
exception when others then
  if sqlerrm = 'A rival participant unexpectedly succeeded' then raise; end if;
  if sqlerrm <> 'Participant does not belong to the acting team' then raise; end if;
end;
$$;
do $$
begin
  perform public.publish_pachanga_external_result_v1(
    '82000000-0000-0000-0000-000000000001',
    current_setting('pachangas.test_validation_match')::uuid,
    1, 0, array['a1'], '[{"playerId":"a2","goals":1}]'::jsonb,
    '84000000-0000-0000-0000-000000000019', 1, '{}'::jsonb
  );
  raise exception 'A nonparticipant scorer unexpectedly succeeded';
exception when others then
  if sqlerrm = 'A nonparticipant scorer unexpectedly succeeded' then raise; end if;
  if sqlerrm <> 'Scorer must be a participant of the acting team' then raise; end if;
end;
$$;
reset role;
select pg_temp.assert_true(
  (select state = 'draft' and revision = 1
   from public.pachanga_external_matches where id = :'validation_match'::uuid),
  'Rejected scorer submissions must not change the canonical match'
);

-- Collective boxes belong only to canonical participants; late members receive no box.
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_grants rewards
   where rewards.group_id = '82000000-0000-0000-0000-000000000001'
     and rewards.reward_kind = 'collective_box' and rewards.state = 'active') >= 2,
  'The first match and first win must create distinct collective box grants'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_reward_grants rewards
    join public.pachanga_reward_recipients recipients on recipients.reward_grant_id = rewards.id
    join public.pachanga_achievement_grants grants on grants.id = rewards.achievement_grant_id
    where rewards.group_id = '82000000-0000-0000-0000-000000000001'
      and rewards.reward_kind = 'collective_box'
      and not exists (
        select 1
        from public.pachanga_progression_player_match_facts player_facts
        join public.pachanga_player_profiles profiles on profiles.id = player_facts.player_profile_id
        where player_facts.match_fact_id = grants.origin_match_fact_id
          and player_facts.group_id = rewards.group_id
          and player_facts.state = 'active'
          and profiles.user_id = recipients.user_id
      )
  ),
  'Collective boxes must belong exclusively to canonical participants'
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('82000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000006', 'player', 'Nuevo');
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000006', true);
select public.get_pachanga_progression_snapshot_v1(
  '82000000-0000-0000-0000-000000000001'
) as late_snapshot \gset
reset role;
select pg_temp.assert_true(
  jsonb_array_length(:'late_snapshot'::jsonb -> 'rewards') = 0,
  'A later member must not receive retroactive reward openings'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_team_cosmetic_inventory inventory
    where inventory.group_id = '82000000-0000-0000-0000-000000000001'
      and inventory.cosmetic_key = 'symbol.lightning'
      and inventory.state = 'unlocked'
  ),
  'A pending box must not unlock the collective inventory'
);

select rewards.id as owner_reward_id,
  rewards.achievement_grant_id as owner_achievement_grant_id,
  recipients.box_id as owner_box_id
from public.pachanga_reward_grants rewards
join public.pachanga_reward_recipients recipients on recipients.reward_grant_id = rewards.id
where rewards.group_id = '82000000-0000-0000-0000-000000000001'
  and rewards.reward_kind = 'collective_box'
  and recipients.user_id = '81000000-0000-0000-0000-000000000001'
  and recipients.status = 'pending'
order by rewards.granted_at, rewards.id
limit 1 \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.get_pachanga_progression_snapshot_v1(
  '82000000-0000-0000-0000-000000000001'
) as owner_pending_snapshot \gset
select public.open_pachanga_reward_box_v2(
  :'owner_box_id'::uuid, '84000000-0000-0000-0000-000000000020', 1,
  '{"sessionId":"reward-device-a"}'::jsonb
) as opened_reward \gset
select public.open_pachanga_reward_box_v2(
  :'owner_box_id'::uuid, '84000000-0000-0000-0000-000000000020', 1,
  '{"sessionId":"reward-device-a"}'::jsonb
) as replayed_reward \gset
reset role;
select pg_temp.assert_true(
  not exists (
    select 1
    from jsonb_array_elements(:'owner_pending_snapshot'::jsonb -> 'rewards') boxes(value)
    where boxes.value ->> 'boxId' = :'owner_box_id'
      and boxes.value ? 'rewardPayload'
  ),
  'A pending box must not expose or grant its sealed payload'
);
select pg_temp.assert_true(
  :'opened_reward'::jsonb = :'replayed_reward'::jsonb,
  'The same reward operation must replay exactly'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_progression_events
   where reward_grant_id = :'owner_reward_id'::uuid and event_type = 'reward_opened') = 1,
  'A deterministic reward must emit one opening event'
);
select pg_temp.assert_true(
  (:'opened_reward'::jsonb -> 'rewardPayload') is not null
    and (:'opened_reward'::jsonb ->> 'status') = 'opened',
  'Opening a box must reveal its server-sealed payload'
);
-- Crest drafts and publications remain server-authoritative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.save_pachanga_team_crest_draft_v1(
  '82000000-0000-0000-0000-000000000001',
  '{"shapeKey":"shape.classic","primaryColorKey":"color.green","secondaryColorKey":"color.white","patternKey":"pattern.solid","borderKey":"border.standard","symbolKey":null,"adornmentKey":null,"paletteKey":null,"effectKey":null,"initials":"ELA"}'::jsonb,
  '84000000-0000-0000-0000-000000000021', 0, '{}'::jsonb
) as crest_saved \gset
reset role;

update public.pachanga_team_crest_drafts
set symbol_key = 'symbol.crown'
where group_id = '82000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
do $$
begin
  perform public.publish_pachanga_team_crest_v1(
    '82000000-0000-0000-0000-000000000001',
    '84000000-0000-0000-0000-000000000022', 1, '{}'::jsonb
  );
  raise exception 'A locked cosmetic unexpectedly published';
exception when others then
  if sqlerrm = 'A locked cosmetic unexpectedly published' then raise; end if;
  if sqlerrm <> 'COSMETIC_LOCKED: symbol.crown' then raise; end if;
end;
$$;
reset role;
update public.pachanga_team_crest_drafts
set symbol_key = 'symbol.lightning'
where group_id = '82000000-0000-0000-0000-000000000001';
insert into public.pachanga_team_cosmetic_inventory(
  group_id, cosmetic_key, source_grant_id
) values (
  '82000000-0000-0000-0000-000000000001', 'symbol.lightning',
  :'owner_achievement_grant_id'::uuid
) on conflict (group_id, cosmetic_key) do update set
  state = 'unlocked', revoked_at = null;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.publish_pachanga_team_crest_v1(
  '82000000-0000-0000-0000-000000000001',
  '84000000-0000-0000-0000-000000000023', 1, '{}'::jsonb
) as crest_published \gset
select public.publish_pachanga_team_crest_v1(
  '82000000-0000-0000-0000-000000000001',
  '84000000-0000-0000-0000-000000000023', 1, '{}'::jsonb
) as crest_replayed \gset
reset role;
select pg_temp.assert_true(
  :'crest_published'::jsonb = :'crest_replayed'::jsonb,
  'Crest publication must replay idempotently'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_crest_versions
   where group_id = '82000000-0000-0000-0000-000000000001') = 1,
  'One publish operation must create one immutable crest version'
);
do $$
begin
  update public.pachanga_team_crest_versions
  set initials = 'BAD'
  where group_id = '82000000-0000-0000-0000-000000000001';
  raise exception 'A published crest version unexpectedly changed';
exception when others then
  if sqlerrm = 'A published crest version unexpectedly changed' then raise; end if;
  if sqlerrm <> 'Published crest versions are immutable' then raise; end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000004', true);
select public.get_pachanga_team_crest_snapshot_v1(
  '82000000-0000-0000-0000-000000000001'
) as member_crest \gset
do $$
begin
  perform public.save_pachanga_team_crest_draft_v1(
    '82000000-0000-0000-0000-000000000001',
    '{"shapeKey":"shape.classic","primaryColorKey":"color.green","secondaryColorKey":"color.white","patternKey":"pattern.solid","borderKey":"border.standard","initials":"NO"}'::jsonb,
    '84000000-0000-0000-0000-000000000024', 2, '{}'::jsonb
  );
  raise exception 'A normal member unexpectedly edited the crest';
exception when others then
  if sqlerrm = 'A normal member unexpectedly edited the crest' then raise; end if;
  if sqlerrm <> 'Only team administrators can edit the official crest' then raise; end if;
end;
$$;
reset role;
select pg_temp.assert_true(
  (:'member_crest'::jsonb ->> 'canManage')::boolean = false
    and :'member_crest'::jsonb -> 'draft' = 'null'::jsonb,
  'Members may read the published crest but never the private draft'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000005', true);
do $$
begin
  perform public.get_pachanga_team_crest_snapshot_v1(
    '82000000-0000-0000-0000-000000000001'
  );
  raise exception 'A third team unexpectedly read the crest snapshot';
exception when others then
  if sqlerrm = 'A third team unexpectedly read the crest snapshot' then raise; end if;
  if sqlerrm <> 'Group membership required' then raise; end if;
end;
$$;
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_crest_versions
   where group_id = '82000000-0000-0000-0000-000000000001') = 0,
  'RLS must hide published crest rows from a third team'
);
reset role;

-- The internal path consumes Rating V2 snapshots and does not modify the rating card.
insert into public.pachanga_match_rating_snapshots(
  group_id, match_id, group_level, lineup_a_level, lineup_b_level,
  engine_version, snapshot, state, finalized_at
) values (
  '82000000-0000-0000-0000-000000000001', 'achievement-internal-1',
  66, 67, 65, 'pachangas-rating-v2', '{}'::jsonb, 'active', clock_timestamp()
);
insert into public.pachanga_match_rating_participants(
  group_id, match_id, local_player_id, player_profile_id, team_side,
  attendance_confirmed, was_reserve, card_snapshot
) values
  (
    '82000000-0000-0000-0000-000000000001', 'achievement-internal-1', 'a1',
    '82500000-0000-0000-0000-000000000001', 'A', true, false,
    '{"currentOverall":68,"engineVersion":"pachangas-rating-v2"}'::jsonb
  ),
  (
    '82000000-0000-0000-0000-000000000001', 'achievement-internal-1', 'a2',
    '82500000-0000-0000-0000-000000000002', 'B', true, false,
    '{"currentOverall":64,"engineVersion":"pachangas-rating-v2"}'::jsonb
  );
update public.pachanga_match_rating_snapshots
set snapshot = '{"match":{"scoreA":2,"scoreB":1,"scorers":[{"playerId":"a1","goals":2}]}}'::jsonb
where group_id = '82000000-0000-0000-0000-000000000001'
  and match_id = 'achievement-internal-1';

select pg_temp.assert_true(
  (select engine_version = 'pachangas-rating-v2' and group_level = 66
   from public.pachanga_match_rating_snapshots
   where group_id = '82000000-0000-0000-0000-000000000001'
     and match_id = 'achievement-internal-1'),
  'The progression trigger must not rewrite the Rating V2 snapshot'
);
select pg_temp.assert_true(
  (select current_overall = 68 and calibrated_overall = 67
   from public.pachanga_player_profiles
   where id = '82500000-0000-0000-0000-000000000001'),
  'Achievements must not modify a player Rating V2 card'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_progression_match_facts
   where source_kind = 'internal_snapshot'
     and source_match_id = 'achievement-internal-1' and state = 'active') = 1,
  'One internal Rating V2 snapshot must create one internal progression fact'
);

-- Canonical cumulative participation milestones and exact scoring feats.
do $$
declare
  match_number integer;
  test_match_id text;
begin
  for match_number in 2..25 loop
    test_match_id := 'achievement-internal-' || match_number::text;
    insert into public.pachanga_match_rating_snapshots(
      group_id, match_id, group_level, lineup_a_level, lineup_b_level,
      engine_version, snapshot, state, finalized_at
    ) values (
      '82000000-0000-0000-0000-000000000001', test_match_id,
      66, 66, 66, 'pachangas-rating-v2', '{}'::jsonb, 'active',
      clock_timestamp() + make_interval(secs => match_number)
    );
    insert into public.pachanga_match_rating_participants(
      group_id, match_id, local_player_id, player_profile_id, team_side,
      attendance_confirmed, was_reserve, card_snapshot
    ) values (
      '82000000-0000-0000-0000-000000000001', test_match_id, 'a1',
      '82500000-0000-0000-0000-000000000001', 'A', true, false,
      '{"currentOverall":68,"engineVersion":"pachangas-rating-v2"}'::jsonb
    );
    update public.pachanga_match_rating_snapshots
    set snapshot = '{"match":{"scoreA":0,"scoreB":0,"scorers":[]}}'::jsonb
    where group_id = '82000000-0000-0000-0000-000000000001'
      and match_id = test_match_id;
  end loop;
end;
$$;

insert into public.pachanga_match_rating_snapshots(
  group_id, match_id, group_level, lineup_a_level, lineup_b_level,
  engine_version, snapshot, state, finalized_at
) values (
  '82000000-0000-0000-0000-000000000001', 'achievement-internal-26',
  66, 67, 65, 'pachangas-rating-v2', '{}'::jsonb, 'active',
  clock_timestamp() + interval '26 seconds'
);
insert into public.pachanga_match_rating_participants(
  group_id, match_id, local_player_id, player_profile_id, team_side,
  attendance_confirmed, was_reserve, card_snapshot
) values (
  '82000000-0000-0000-0000-000000000001', 'achievement-internal-26', 'a1',
  '82500000-0000-0000-0000-000000000001', 'A', true, false,
  '{"currentOverall":68,"engineVersion":"pachangas-rating-v2"}'::jsonb
);
update public.pachanga_match_rating_snapshots
set snapshot = '{"match":{"scoreA":3,"scoreB":0,"scorers":[{"playerId":"a1","goals":3}]}}'::jsonb
where group_id = '82000000-0000-0000-0000-000000000001'
  and match_id = 'achievement-internal-26';

select pg_temp.assert_true(
  (select appearances = 26 and braces = 1 and hat_tricks = 1
   from public.pachanga_player_progression_stats
   where player_profile_id = '82500000-0000-0000-0000-000000000001'
     and match_scope = 'internal'),
  'A hat-trick must not also increase the exact-double counter'
);
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_type = 'player'
     and grants.subject_id = '82500000-0000-0000-0000-000000000001'
     and grants.state = 'active'
     and definitions.achievement_key in (
       'player.all.matches.005',
       'player.all.matches.025'
     )) = 2,
  'Five and twenty-five appearances must each grant one active achievement'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81000000-0000-0000-0000-000000000001', true);
select public.get_pachanga_progression_snapshot_v1(
  '82000000-0000-0000-0000-000000000001'
) as individual_catalog_snapshot \gset
reset role;

select pg_temp.assert_true(
  exists (
    select 1
    from jsonb_array_elements(
      :'individual_catalog_snapshot'::jsonb -> 'personalAchievementCatalog'
    ) achievements(value)
    where achievements.value ->> 'key' = 'player.all.matches.025'
      and (achievements.value ->> 'currentValue')::integer = 30
      and (achievements.value ->> 'progressPercent')::integer = 100
      and (achievements.value ->> 'unlocked')::boolean
  ),
  'The canonical read model must expose unlocked progress for the 25-match milestone'
);

rollback;
