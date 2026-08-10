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

insert into auth.users(id, email) values
  ('71000000-0000-0000-0000-000000000001', 'social-owner-a@example.test'),
  ('71000000-0000-0000-0000-000000000002', 'social-owner-b@example.test'),
  ('71000000-0000-0000-0000-000000000003', 'social-player@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    '72000000-0000-0000-0000-000000000001',
    '71000000-0000-0000-0000-000000000001',
    'Social Local',
    'SOCIALA',
    '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
  ),
  (
    '72000000-0000-0000-0000-000000000002',
    '71000000-0000-0000-0000-000000000002',
    'Social Rival',
    'SOCIALB',
    '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
  );

insert into public.pachanga_group_members(group_id, user_id, role) values
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000001', 'owner'),
  ('72000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000003', 'player'),
  ('72000000-0000-0000-0000-000000000002', '71000000-0000-0000-0000-000000000002', 'owner');

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_team_challenges', 'SELECT'),
  'Authenticated clients must not read private challenges directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_team_challenges', 'INSERT'),
  'Authenticated clients must not write private challenges directly'
);
select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_team_social_state', 'SELECT'),
  'Members need the Realtime invalidation row'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);

select public.create_pachanga_team_challenge_authoritative(
  '72000000-0000-0000-0000-000000000001',
  'SOCIALB',
  clock_timestamp() + interval '7 days',
  'futbol7',
  'Camp Central',
  'Carrer de la Prova, 1',
  'place-social-test',
  'https://www.google.com/maps/place/?q=place_id:place-social-test',
  '¿Jugamos?',
  '73000000-0000-0000-0000-000000000001',
  0,
  '{"sessionId":"social-device-a"}'::jsonb
) as created_response \gset

select public.create_pachanga_team_challenge_authoritative(
  '72000000-0000-0000-0000-000000000001',
  'SOCIALB',
  clock_timestamp() + interval '7 days',
  'futbol7',
  'Camp Central',
  'Carrer de la Prova, 1',
  'place-social-test',
  'https://www.google.com/maps/place/?q=place_id:place-social-test',
  '¿Jugamos?',
  '73000000-0000-0000-0000-000000000001',
  0,
  '{"sessionId":"social-device-a"}'::jsonb
) as replayed_response \gset

reset role;
select pg_temp.assert_true(
  :'created_response'::jsonb = :'replayed_response'::jsonb,
  'Repeating one operation id must replay the exact canonical response'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_challenges
   where sender_group_id = '72000000-0000-0000-0000-000000000001'
     and receiver_group_id = '72000000-0000-0000-0000-000000000002') = 1,
  'An idempotent retry must create one challenge'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_challenge_events
   where operation_id = '73000000-0000-0000-0000-000000000001') = 1,
  'An idempotent retry must create one event'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_social_operation_receipts
   where operation_id = '73000000-0000-0000-0000-000000000001') = 1,
  'An idempotent retry must create one receipt'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
do $$
begin
  perform public.create_pachanga_team_challenge_authoritative(
    '72000000-0000-0000-0000-000000000001', 'SOCIALB', clock_timestamp() + interval '8 days',
    'futbol7', 'Otro campo', 'Otra dirección', null, null, null,
    '73000000-0000-0000-0000-000000000002', 1, '{}'::jsonb
  );
  raise exception 'A non-admin unexpectedly created a challenge';
exception when others then
  if sqlerrm = 'A non-admin unexpectedly created a challenge' then raise; end if;
  if sqlerrm <> 'Admin authentication, operation id and expected revision required' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
select public.get_pachanga_team_social_snapshot(
  '72000000-0000-0000-0000-000000000002'
) as receiver_snapshot \gset
select set_config(
  'team_social_test.challenge_id',
  (:'receiver_snapshot'::jsonb -> 'challenges' -> 0 ->> 'id'),
  true
);

select public.respond_pachanga_team_challenge_authoritative(
  '72000000-0000-0000-0000-000000000002',
  ((:'receiver_snapshot'::jsonb -> 'challenges' -> 0 ->> 'id')::uuid),
  'accept', null, null, null, null, null, null, null,
  '73000000-0000-0000-0000-000000000003',
  1,
  '{"sessionId":"social-device-b"}'::jsonb
) as accepted_response \gset

select public.respond_pachanga_team_challenge_authoritative(
  '72000000-0000-0000-0000-000000000002',
  ((:'receiver_snapshot'::jsonb -> 'challenges' -> 0 ->> 'id')::uuid),
  'accept', null, null, null, null, null, null, null,
  '73000000-0000-0000-0000-000000000003',
  1,
  '{"sessionId":"social-device-b"}'::jsonb
) as accepted_replay \gset

do $$
declare
  challenge_id uuid := current_setting('team_social_test.challenge_id')::uuid;
begin
  begin
    perform public.respond_pachanga_team_challenge_authoritative(
      '72000000-0000-0000-0000-000000000002', challenge_id,
      'reject', null, null, null, null, null, null, null,
      '73000000-0000-0000-0000-000000000004', 1, '{}'::jsonb
    );
    raise exception 'A stale device unexpectedly changed the accepted challenge';
  exception when sqlstate 'PT409' then
    null;
  end;

  begin
    perform public.respond_pachanga_team_challenge_authoritative(
      '72000000-0000-0000-0000-000000000002', challenge_id,
      'accept', null, null, null, null, null, null, null,
      '73000000-0000-0000-0000-000000000001', 2, '{}'::jsonb
    );
    raise exception 'A reused operation id unexpectedly changed context';
  exception when others then
    if sqlerrm = 'A reused operation id unexpectedly changed context' then raise; end if;
    if sqlerrm <> 'Operation id was already used for another action' then raise; end if;
  end;
end;
$$;
reset role;

select pg_temp.assert_true(
  :'accepted_response'::jsonb = :'accepted_replay'::jsonb,
  'The accepted response must replay exactly once'
);
select pg_temp.assert_true(
  (select status from public.pachanga_team_challenges
   where sender_group_id = '72000000-0000-0000-0000-000000000001'
     and receiver_group_id = '72000000-0000-0000-0000-000000000002') = 'accepted',
  'The receiver must be able to accept the challenge'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_challenge_events
   where operation_id in (
     '73000000-0000-0000-0000-000000000001',
     '73000000-0000-0000-0000-000000000003'
   )) = 2,
  'Create and accept must remain as two auditable events'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_social_operation_receipts
   where operation_id in (
     '73000000-0000-0000-0000-000000000001',
     '73000000-0000-0000-0000-000000000003'
   )) = 2,
  'Only two successful operations must have receipts'
);

insert into public.pachanga_match_rating_snapshots(
  group_id, match_id, group_level, lineup_a_level, lineup_b_level,
  engine_version, snapshot, state, finalized_at
) values (
  '72000000-0000-0000-0000-000000000001', 'social-finalized-1',
  60, 61, 59, 'pachangas-rating-v2', '{}'::jsonb, 'active', clock_timestamp()
);
insert into public.pachanga_registered_match_opponents(
  host_group_id, match_id, opponent_group_id, linked_by, operation_id
) values (
  '72000000-0000-0000-0000-000000000001', 'social-finalized-1',
  '72000000-0000-0000-0000-000000000002',
  '71000000-0000-0000-0000-000000000001',
  '73000000-0000-0000-0000-000000000005'
);

select pg_temp.assert_true(
  (select matches_played from public.pachanga_known_opponents
   where group_id = '72000000-0000-0000-0000-000000000001'
     and opponent_group_id = '72000000-0000-0000-0000-000000000002') = 1,
  'A finalized linked match must add the private known opponent'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_known_opponents
   where group_id in (
     '72000000-0000-0000-0000-000000000001',
     '72000000-0000-0000-0000-000000000002'
   )) = 2,
  'Known-opponent agenda must be available to both teams'
);

update public.pachanga_match_rating_snapshots
set state = 'void', voided_at = clock_timestamp(), void_reason = 'Test reversal'
where group_id = '72000000-0000-0000-0000-000000000001'
  and match_id = 'social-finalized-1';

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_known_opponents
    where group_id = '72000000-0000-0000-0000-000000000001'
      and opponent_group_id = '72000000-0000-0000-0000-000000000002'
  ),
  'Voiding the only finalized match must remove the known opponent'
);

insert into public.pachanga_player_profiles(
  user_id, source_group_id, display_name, calibrated_overall, current_overall,
  calibrated_facets, current_facets, rating_engine_version
) values
  (
    '71000000-0000-0000-0000-000000000001',
    '72000000-0000-0000-0000-000000000001',
    'Owner social A', 62, 62,
    '{"pace":62,"shooting":62,"passing":62,"dribbling":62,"defending":62,"physical":62}'::jsonb,
    '{"pace":62,"shooting":62,"passing":62,"dribbling":62,"defending":62,"physical":62}'::jsonb,
    'pachangas-rating-v2'
  ),
  (
    '71000000-0000-0000-0000-000000000002',
    '72000000-0000-0000-0000-000000000002',
    'Owner social B', 67, 67,
    '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}'::jsonb,
    '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}'::jsonb,
    'pachangas-rating-v2'
  );

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_challengeable_team_profiles', 'SELECT'),
  'Authenticated clients must not read private challengeable profiles directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_challengeable_team_profiles', 'UPDATE'),
  'Authenticated clients must not update private challengeable profiles directly'
);
select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_challengeable_team_profile_state', 'SELECT'),
  'Members need the scoped profile revision row for Realtime invalidation'
);
select pg_temp.assert_true(
  has_table_privilege('authenticated', 'public.pachanga_challengeable_team_search_state', 'SELECT'),
  'Registered users need the global search revision row for Realtime invalidation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);

select public.upsert_pachanga_challengeable_team_profile_authoritative(
  '72000000-0000-0000-0000-000000000001', true,
  'Barcelona', 'zone-social-a', 41.3874, 2.1686,
  30, 40, 80, array['futbol7'],
  '[{"day":4,"start":"20:00","end":"22:00"}]'::jsonb,
  '74000000-0000-0000-0000-000000000001', 0,
  '{"sessionId":"public-team-device-a"}'::jsonb
) as public_a_response \gset

select public.upsert_pachanga_challengeable_team_profile_authoritative(
  '72000000-0000-0000-0000-000000000001', true,
  'Barcelona', 'zone-social-a', 41.3874, 2.1686,
  30, 40, 80, array['futbol7'],
  '[{"day":4,"start":"20:00","end":"22:00"}]'::jsonb,
  '74000000-0000-0000-0000-000000000001', 0,
  '{"sessionId":"public-team-device-a"}'::jsonb
) as public_a_replay \gset

reset role;
select pg_temp.assert_true(
  :'public_a_response'::jsonb = :'public_a_replay'::jsonb,
  'Repeating a public-profile operation must replay the exact canonical response'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_challengeable_team_profile_events
   where group_id = '72000000-0000-0000-0000-000000000001') = 1,
  'An idempotent public-profile retry must create one event'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_challengeable_team_operation_receipts
   where group_id = '72000000-0000-0000-0000-000000000001') = 1,
  'An idempotent public-profile retry must create one receipt'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000003', true);
do $$
begin
  perform public.upsert_pachanga_challengeable_team_profile_authoritative(
    '72000000-0000-0000-0000-000000000001', true,
    'Barcelona', 'zone-forbidden', 41.3874, 2.1686,
    20, 0, 100, array['futbol7'],
    '[{"day":4,"start":"20:00","end":"22:00"}]'::jsonb,
    '74000000-0000-0000-0000-000000000002', 1, '{}'::jsonb
  );
  raise exception 'A non-admin unexpectedly changed the public team profile';
exception when others then
  if sqlerrm = 'A non-admin unexpectedly changed the public team profile' then raise; end if;
  if sqlerrm <> 'Admin authentication, operation id and expected revision required' then raise; end if;
end;
$$;

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
select public.upsert_pachanga_challengeable_team_profile_authoritative(
  '72000000-0000-0000-0000-000000000002', true,
  'Sant Adrià de Besòs', 'zone-social-b', 41.4306, 2.2182,
  20, 45, 75, array['futbol7','futbol11'],
  '[{"day":4,"start":"19:30","end":"22:30"},{"day":6,"start":"18:00","end":"21:00"}]'::jsonb,
  '74000000-0000-0000-0000-000000000003', 0,
  '{"sessionId":"public-team-device-b"}'::jsonb
) as public_b_response \gset

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select public.search_pachanga_challengeable_teams(
  '72000000-0000-0000-0000-000000000001',
  null, 41.3874::double precision, 2.1686::double precision, 30,
  60::numeric, 70::numeric, 4::smallint, '20:00'::time, '22:00'::time,
  'futbol7', 1, 12
) as public_search \gset
reset role;

select pg_temp.assert_true(
  jsonb_array_length(:'public_search'::jsonb -> 'items') = 1,
  'Server-side filters must return the compatible public rival'
);
select pg_temp.assert_true(
  (:'public_search'::jsonb -> 'items' -> 0 ->> 'groupId')::uuid = '72000000-0000-0000-0000-000000000002',
  'The compatible result must be the rival team'
);
select pg_temp.assert_true(
  not ((:'public_search'::jsonb -> 'items' -> 0) ?| array['zoneLat','zoneLng','placeId','teamCode','address','createdBy','updatedBy']),
  'Public results must not expose coordinates, team code, address or actor identities'
);
select pg_temp.assert_true(
  (:'public_search'::jsonb ->> 'confirmedRevision')::bigint =
    (select revision from public.pachanga_challengeable_team_search_state where id),
  'Search results and the returned revision must come from one canonical server snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000002', true);
do $$
begin
  perform public.upsert_pachanga_challengeable_team_profile_authoritative(
    '72000000-0000-0000-0000-000000000002', true,
    'Sant Adrià de Besòs', 'zone-social-b', 41.4306, 2.2182,
    20, 45, 75, array['futbol7'],
    '[{"day":4,"start":"19:30","end":"22:30"}]'::jsonb,
    '74000000-0000-0000-0000-000000000004', 0, '{}'::jsonb
  );
  raise exception 'A stale profile revision unexpectedly won';
exception when sqlstate 'PT409' then
  null;
end;
$$;

select public.upsert_pachanga_challengeable_team_profile_authoritative(
  '72000000-0000-0000-0000-000000000002', false,
  'Sant Adrià de Besòs', 'zone-social-b', 41.4306, 2.2182,
  20, 45, 75, array['futbol7','futbol11'],
  '[{"day":4,"start":"19:30","end":"22:30"}]'::jsonb,
  '74000000-0000-0000-0000-000000000005', 1,
  '{"sessionId":"public-team-device-b"}'::jsonb
) as public_b_disabled \gset

select set_config('request.jwt.claim.sub', '71000000-0000-0000-0000-000000000001', true);
select public.search_pachanga_challengeable_teams(
  '72000000-0000-0000-0000-000000000001',
  null, 41.3874::double precision, 2.1686::double precision, 30,
  null, null, null, null, null, null, 1, 12
) as public_search_after_disable \gset
select public.lookup_pachanga_team_by_code(
  '72000000-0000-0000-0000-000000000001', 'SOCIALB'
) as private_lookup_after_disable \gset
reset role;

select pg_temp.assert_true(
  jsonb_array_length(:'public_search_after_disable'::jsonb -> 'items') = 0,
  'A disabled public profile must disappear from public search'
);
select pg_temp.assert_true(
  (:'private_lookup_after_disable'::jsonb ->> 'groupId')::uuid = '72000000-0000-0000-0000-000000000002',
  'Disabling a public profile must not block private code challenges'
);
select pg_temp.assert_true(
  (select stable_level from public.pachanga_team_level_read_models
   where group_id = '72000000-0000-0000-0000-000000000001') = 62,
  'The public team read model must use the canonical V2 group level'
);

rollback;
