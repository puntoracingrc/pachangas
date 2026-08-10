\set ON_ERROR_STOP on
\set VERBOSITY verbose

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
  ('c4100000-0000-0000-0000-000000000001', 'cosmetics-owner@example.test'),
  ('c4100000-0000-0000-0000-000000000002', 'cosmetics-member@example.test'),
  ('c4100000-0000-0000-0000-000000000003', 'cosmetics-outsider@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  'c4200000-0000-0000-0000-000000000001',
  'c4100000-0000-0000-0000-000000000001',
  'Cosmetics V1 test', 'COSMETIC1', '{"players":[],"matches":[]}'
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('c4200000-0000-0000-0000-000000000001', 'c4100000-0000-0000-0000-000000000001', 'owner', 'Cosmetics Owner'),
  ('c4200000-0000-0000-0000-000000000001', 'c4100000-0000-0000-0000-000000000002', 'player', 'Cosmetics Member');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name, position,
  rating, base_overall, calibrated_overall, current_overall,
  base_facets, calibrated_facets, current_facets, rating_engine_version
) values
  ('c4300000-0000-0000-0000-000000000001', 'c4100000-0000-0000-0000-000000000001', 'c4200000-0000-0000-0000-000000000001', 'cosmetics-owner', 'Cosmetics Owner', 'MC', 7.4, 73, 74, 74,
    '{"pace":74,"shooting":74,"passing":74,"dribbling":74,"defending":74,"physical":74}',
    '{"pace":74,"shooting":74,"passing":74,"dribbling":74,"defending":74,"physical":74}',
    '{"pace":74,"shooting":74,"passing":74,"dribbling":74,"defending":74,"physical":74}', 'pachangas-rating-v2'),
  ('c4300000-0000-0000-0000-000000000002', 'c4100000-0000-0000-0000-000000000002', 'c4200000-0000-0000-0000-000000000001', 'cosmetics-member', 'Cosmetics Member', 'DEF', 6.8, 68, 68, 68,
    '{"pace":68,"shooting":68,"passing":68,"dribbling":68,"defending":68,"physical":68}',
    '{"pace":68,"shooting":68,"passing":68,"dribbling":68,"defending":68,"physical":68}',
    '{"pace":68,"shooting":68,"passing":68,"dribbling":68,"defending":68,"physical":68}', 'pachangas-rating-v2');

insert into public.pachanga_progression_match_facts(
  id, source_kind, source_match_id, source_revision, group_id, match_scope,
  outcome, goals_for, goals_against, clean_sheet, close_win, big_win,
  scoreless_draw, player_facts_complete, source_snapshot, state, played_at
) values (
  'c4400000-0000-0000-0000-000000000001', 'internal_snapshot',
  'cosmetics-v1-match', 1, 'c4200000-0000-0000-0000-000000000001',
  'internal', 'win', 3, 1, false, false, false, false, true,
  '{"canonicalState":"finalized"}', 'active', '2026-08-10T09:00:00Z'
);

insert into public.pachanga_achievement_definitions(
  id, achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, threshold, rarity, repeatable, reward_kind,
  active, catalog_key, family_key, display_priority
) values (
  'c4500000-0000-0000-0000-000000000001', 'test.cosmetics.featured', 1,
  'Figura del partido', 'Logro real de prueba', 'player', 'internal',
  'test', 'PLAYER_APPEARANCES', 1, 'rare', false, 'none', true,
  'test_cosmetics_v1', 'test.cosmetics', 1
);

insert into public.pachanga_achievement_grants(
  id, definition_id, subject_type, subject_id, group_id, origin_match_fact_id,
  metric_value, operation_id, state, occurred_at
) values (
  'c4600000-0000-0000-0000-000000000001',
  'c4500000-0000-0000-0000-000000000001', 'player',
  'c4300000-0000-0000-0000-000000000001',
  'c4200000-0000-0000-0000-000000000001',
  'c4400000-0000-0000-0000-000000000001', 1,
  'c4700000-0000-0000-0000-000000000001', 'active', '2026-08-10T09:00:00Z'
);

insert into public.pachanga_reward_grants(
  id, achievement_grant_id, reward_kind, reward_key, group_id,
  player_profile_id, payload, state
) values (
  'c4800000-0000-0000-0000-000000000001',
  'c4600000-0000-0000-0000-000000000001', 'collective_box',
  'box.common', 'c4200000-0000-0000-0000-000000000001',
  'c4300000-0000-0000-0000-000000000001', '{}', 'active'
);

insert into public.pachanga_reward_recipients(
  reward_grant_id, user_id, status, revision, box_id, achievement_grant_id,
  match_fact_id, group_id, player_profile_id, reward_reference,
  revealed_payload, reward_granted_at
) values (
  'c4800000-0000-0000-0000-000000000001',
  'c4100000-0000-0000-0000-000000000001', 'opened', 2,
  'c4900000-0000-0000-0000-000000000001',
  'c4600000-0000-0000-0000-000000000001',
  'c4400000-0000-0000-0000-000000000001',
  'c4200000-0000-0000-0000-000000000001',
  'c4300000-0000-0000-0000-000000000001', 'test-cosmetic-box',
  '{"grant":{"cosmeticKey":"player.frame.barrio.steel","cosmeticGranted":true,"pointsGranted":0}}',
  clock_timestamp()
);

update private.pachanga_player_cosmetic_settings
set player_cosmetics_enabled = true, updated_at = clock_timestamp()
where singleton;

create temporary table cosmetics_sport_before as
select rating, base_overall, calibrated_overall, current_overall,
  base_facets, calibrated_facets, current_facets, rating_engine_version
from public.pachanga_player_profiles
where id = 'c4300000-0000-0000-0000-000000000001';

insert into public.pachanga_player_reward_inventory(
  player_profile_id, reward_kind, reward_key, source_grant_id,
  source_box_id, state, acquired_at
) values
  ('c4300000-0000-0000-0000-000000000001', 'player_cosmetic',
    'player.frame.barrio.steel', 'c4600000-0000-0000-0000-000000000001',
    'c4900000-0000-0000-0000-000000000001', 'unlocked', clock_timestamp()),
  ('c4300000-0000-0000-0000-000000000001', 'player_cosmetic',
    'player.title.old_school', 'c4600000-0000-0000-0000-000000000001',
    null, 'unlocked', clock_timestamp());

select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_cosmetic_loadouts
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001') = 1,
  'Inventory grants must create one authoritative loadout'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_user_notifications
   where recipient_user_id = 'c4100000-0000-0000-0000-000000000001'
     and kind = 'player_reward_cosmetic_unlocked') = 2,
  'Each newly owned cosmetic must create one deduplicated notification'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_player_cosmetic_loadouts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.pachanga_player_cosmetic_loadouts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.pachanga_player_reward_inventory', 'INSERT'),
  'Authenticated clients must not write cosmetic tables directly'
);
select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.save_pachanga_player_cosmetic_loadout_v1(jsonb,uuid,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.save_pachanga_player_cosmetic_loadout_v1(jsonb,uuid,bigint,jsonb)', 'EXECUTE'),
  'Only authenticated users may send cosmetic write intentions'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c4100000-0000-0000-0000-000000000001', true);

select pg_temp.assert_true(
  (public.get_pachanga_player_cosmetics_snapshot_v1() ->> 'revision')::bigint = 3
  and jsonb_array_length(public.get_pachanga_player_cosmetics_snapshot_v1() -> 'owned') = 2,
  'The owner snapshot must contain both pieces and the trigger-confirmed revision'
);

do $$
begin
  insert into public.pachanga_player_cosmetic_loadouts(player_profile_id)
  values ('c4300000-0000-0000-0000-000000000002');
  raise exception 'Direct cosmetic write unexpectedly succeeded';
exception when insufficient_privilege then null;
end;
$$;

create temporary table saved_loadout as
select public.save_pachanga_player_cosmetic_loadout_v1(
  jsonb_build_object(
    'frameKey', 'player.frame.barrio.steel',
    'backgroundKey', null,
    'accentKey', null,
    'effectKey', null,
    'titleKey', 'player.title.old_school',
    'featuredBadgeGrantId', 'c4600000-0000-0000-0000-000000000001'
  ),
  'c4a00000-0000-0000-0000-000000000001', 3, '{"device":"sql-a"}'
) as response;

select pg_temp.assert_true(
  (select response ->> 'confirmedRevision' from saved_loadout) = '4',
  'One save must increment the authoritative loadout revision exactly once'
);
select pg_temp.assert_true(
  public.save_pachanga_player_cosmetic_loadout_v1(
    jsonb_build_object(
      'frameKey', 'player.frame.barrio.steel',
      'backgroundKey', null,
      'accentKey', null,
      'effectKey', null,
      'titleKey', 'player.title.old_school',
      'featuredBadgeGrantId', 'c4600000-0000-0000-0000-000000000001'
    ),
    'c4a00000-0000-0000-0000-000000000001', 3, '{"device":"sql-a"}'
  ) = (select response from saved_loadout),
  'Replaying the same operation must return the original receipt'
);

do $$
begin
  perform public.save_pachanga_player_cosmetic_loadout_v1(
    '{"frameKey":null,"backgroundKey":null,"accentKey":null,"effectKey":null,"titleKey":null,"featuredBadgeGrantId":null}',
    'c4a00000-0000-0000-0000-000000000002', 3, '{"device":"sql-b"}'
  );
  raise exception 'A stale cosmetic revision unexpectedly succeeded';
exception when sqlstate 'PT409' then null;
end;
$$;

select public.mark_pachanga_player_cosmetics_seen_v1(
  array['player.title.old_school'],
  'c4a00000-0000-0000-0000-000000000003', 4, '{}'
);
select pg_temp.assert_true(
  (select seen_at is not null from public.pachanga_player_reward_inventory
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001'
     and reward_key = 'player.title.old_school'),
  'Opening one category must persist its NEW acknowledgement'
);

select public.equip_pachanga_player_cosmetic_from_box_v1(
  'c4900000-0000-0000-0000-000000000001',
  'player.frame.barrio.steel',
  'c4a00000-0000-0000-0000-000000000004', 5, '{}'
);
select pg_temp.assert_true(
  (select revision = 6 and frame_key = 'player.frame.barrio.steel'
   from public.pachanga_player_cosmetic_loadouts
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001'),
  'Equip from box must confirm the item and revision atomically'
);

reset role;

select pg_temp.assert_true(
  (select count(*) = 1
   from public.pachanga_player_profiles after_profile
   join cosmetics_sport_before before_profile
     on after_profile.rating = before_profile.rating
    and after_profile.base_overall = before_profile.base_overall
    and after_profile.calibrated_overall = before_profile.calibrated_overall
    and after_profile.current_overall = before_profile.current_overall
    and after_profile.base_facets = before_profile.base_facets
    and after_profile.calibrated_facets = before_profile.calibrated_facets
    and after_profile.current_facets = before_profile.current_facets
    and after_profile.rating_engine_version = before_profile.rating_engine_version
   where after_profile.id = 'c4300000-0000-0000-0000-000000000001'),
  'Cosmetics must not change Rating V2 fields or facets'
);
select pg_temp.assert_true(
  (select count(*) from private.pachanga_player_cosmetic_operation_receipts
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001') = 3,
  'Save, mark seen and equip must keep one idempotent receipt each'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c4100000-0000-0000-0000-000000000002', true);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_reward_inventory
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001') = 0,
  'A teammate must not read another player private inventory'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_cosmetic_loadouts
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001') = 0,
  'A teammate must not read another player private loadout'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_cosmetic_public_cards
   where player_profile_id = 'c4300000-0000-0000-0000-000000000001') = 1,
  'A teammate may read the safe equipped-only public card'
);
select pg_temp.assert_true(
  public.get_pachanga_public_player_card_cosmetics_v1(
    'c4300000-0000-0000-0000-000000000001'
  )::text !~* 'sourceBoxId|seenAt|acquiredAt|inventory',
  'The public RPC must not expose private ownership or NEW metadata'
);

rollback;
