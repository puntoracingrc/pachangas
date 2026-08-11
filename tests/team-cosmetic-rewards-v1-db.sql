\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table reward_facts(
  group_id uuid not null,
  label text not null,
  fact_id uuid not null,
  primary key (group_id, label)
);

create or replace function pg_temp.apply_reward_match(
  target_group_id uuid,
  target_label text,
  target_scope text,
  target_opponent_id uuid,
  target_goals_for integer,
  target_goals_against integer,
  target_outcome text,
  target_evaluate boolean default true
)
returns uuid
language plpgsql
as $$
declare
  saved_fact_id uuid;
begin
  insert into public.pachanga_progression_match_facts(
    source_kind, source_match_id, source_revision, group_id, opponent_group_id,
    match_scope, outcome, goals_for, goals_against, clean_sheet, close_win,
    big_win, scoreless_draw, player_facts_complete, source_snapshot, state,
    server_sequence, played_at
  ) values (
    case when target_scope = 'external' then 'external_result' else 'internal_snapshot' end,
    target_group_id::text || ':' || target_label, 1, target_group_id,
    case when target_scope = 'external' then target_opponent_id else null end,
    target_scope, target_outcome, target_goals_for, target_goals_against,
    target_goals_against = 0,
    target_outcome = 'win' and target_goals_for - target_goals_against = 1,
    target_outcome = 'win' and target_goals_for - target_goals_against >= 4,
    target_goals_for = 0 and target_goals_against = 0,
    true, jsonb_build_object('canonicalState', 'confirmed', 'officialState', 'confirmed'),
    'active', nextval('public.pachanga_progression_sequence'), clock_timestamp()
  ) returning id into saved_fact_id;
  perform private.pachanga_rebuild_team_progression_stats_v1(target_group_id, target_scope);
  if target_evaluate then
    perform private.pachanga_evaluate_achievements_v1(target_group_id, target_scope, saved_fact_id);
  end if;
  insert into reward_facts(group_id, label, fact_id)
  values (target_group_id, target_label, saved_fact_id);
  return saved_fact_id;
end;
$$;

insert into auth.users(id, email) values
  ('f1100000-0000-0000-0000-000000000001', 'reward-owner@example.test'),
  ('f1100000-0000-0000-0000-000000000002', 'reward-admin@example.test'),
  ('f1100000-0000-0000-0000-000000000003', 'reward-late-admin@example.test'),
  ('f1100000-0000-0000-0000-000000000004', 'reward-member@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select group_id, 'f1100000-0000-0000-0000-000000000001', name, code,
  jsonb_build_object('players', '[]'::jsonb, 'sportingMarker', 'unchanged')
from (values
  ('f1200000-0000-0000-0000-000000000001'::uuid, 'Historical Reward Team', 'TRV1001'),
  ('f1200000-0000-0000-0000-000000000002'::uuid, 'Flag Off Reward Team', 'TRV1002'),
  ('f1200000-0000-0000-0000-000000000003'::uuid, 'First Win Reward Team', 'TRV1003'),
  ('f1200000-0000-0000-0000-000000000004'::uuid, 'Ten Retos Reward Team', 'TRV1004'),
  ('f1200000-0000-0000-0000-000000000005'::uuid, 'Matches Reward Team', 'TRV1005'),
  ('f1200000-0000-0000-0000-000000000006'::uuid, 'Clean Sheet Reward Team', 'TRV1006'),
  ('f1200000-0000-0000-0000-000000000007'::uuid, 'Already Owned Reward Team', 'TRV1007'),
  ('f1200000-0000-0000-0000-000000000008'::uuid, 'Historical Ten Retos Team', 'TRV1008'),
  ('f1200000-0000-0000-0000-000000000099'::uuid, 'Reward Rival', 'TRV1099')
) groups(group_id, name, code);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select groups.id, users.user_id, users.role, users.display_name
from public.pachanga_groups groups
cross join (values
  ('f1100000-0000-0000-0000-000000000001'::uuid, 'owner', 'Reward Owner'),
  ('f1100000-0000-0000-0000-000000000002'::uuid, 'admin', 'Reward Admin')
) users(user_id, role, display_name)
where groups.id::text like 'f1200000-0000-0000-0000-00000000000%';

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('f1200000-0000-0000-0000-000000000003', 'f1100000-0000-0000-0000-000000000004', 'player', 'Reward Member');

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values (
  'f1300000-0000-0000-0000-000000000001',
  'f1100000-0000-0000-0000-000000000001', 'Reward Owner', 'DEL', 67, 67, 67,
  '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}',
  80, 'pachangas-rating-v2'
);

create temporary table reward_rating_before as
select md5(jsonb_build_object(
  'currentOverall', current_overall,
  'calibratedOverall', calibrated_overall,
  'facets', current_facets,
  'reliability', rating_reliability,
  'engine', rating_engine_version
)::text) as checksum
from public.pachanga_player_profiles
where id = 'f1300000-0000-0000-0000-000000000001';

create temporary table reward_payload_before as
select id, md5(payload::text) as checksum
from public.pachanga_groups
where id::text like 'f1200000-0000-0000-0000-00000000000%';

update private.pachanga_team_cosmetic_settings
set team_cosmetics_enabled = true,
    team_cosmetic_rewards_enabled = false,
    updated_at = clock_timestamp()
where singleton;
update private.pachanga_team_cosmetic_reward_policies
set state = 'ready',
    effective_from = null,
    effective_from_server_sequence = null,
    activation_operation_id = null,
    activated_at = null,
    updated_at = clock_timestamp()
where policy_version = 1;

select pg_temp.assert_true(
  (select count(*) from private.pachanga_team_cosmetic_reward_mappings
   where policy_version = 1 and active) = 5,
  'Policy V1 must install exactly five active mappings'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_definitions
   where achievement_key = 'team.external.matches.010'
     and version = 3 and active and match_scope = 'external'
     and evaluator_key = 'TEAM_MATCHES' and threshold = 10) = 1,
  '10 Retos must use one new active V3 canonical milestone'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_definitions
    where achievement_key = 'team.external.matches.010'
      and version < 3 and active
  ),
  'Legacy 10-Retos definitions must remain inactive'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_team_cosmetic_reward_ledger', 'SELECT')
  and not has_table_privilege('authenticated', 'private.pachanga_team_cosmetic_reward_mappings', 'SELECT')
  and not has_function_privilege(
    'authenticated', 'private.pachanga_apply_team_cosmetic_reward_v1(uuid)', 'EXECUTE'
  )
  and not has_function_privilege(
    'anon', 'private.pachanga_apply_team_cosmetic_reward_v1(uuid)', 'EXECUTE'
  ),
  'Policy, evidence and automatic grant functions must stay server-only'
);

-- A canonical achievement before activation remains an achievement only.
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000001', 'historical-win-1', 'external',
  'f1200000-0000-0000-0000-000000000099', 2, 1, 'win', true
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
    where grants.group_id = 'f1200000-0000-0000-0000-000000000001'
      and definitions.achievement_key = 'team.external.wins.001'
  ),
  'The canonical pre-activation achievement must still be emitted'
);
select pg_temp.assert_true(
  not exists (
    select 1 from private.pachanga_team_cosmetic_reward_ledger
    where group_id = 'f1200000-0000-0000-0000-000000000001'
      and mapping_key = 'first_challenge_win'
  ) and not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000001'
      and cosmetic_key = 'team.shield.border.copper'
      and source_kind = 'achievement'
      and metadata ->> 'policyVersion' = '1'
  ),
  'The pre-activation achievement must not enter the reward bridge'
);

do $$
begin
  for index in 1..10 loop
    perform pg_temp.apply_reward_match(
      'f1200000-0000-0000-0000-000000000008', 'historical-reto-' || index,
      'external', 'f1200000-0000-0000-0000-000000000099', 1, 1, 'draw', false
    );
  end loop;
end;
$$;

select private.pachanga_set_team_cosmetic_rewards_enabled_v1(
  true, 'f1400000-0000-0000-0000-000000000001', 1
);
select pg_temp.assert_true(
  (select state = 'active' and effective_from is not null
     and effective_from_server_sequence is not null
   from private.pachanga_team_cosmetic_reward_policies where policy_version = 1)
  and private.pachanga_team_cosmetic_rewards_enabled_v1(),
  'Activation must record a non-retroactive frontier and enable the flag'
);
select pg_temp.assert_true(
  private.pachanga_set_team_cosmetic_rewards_enabled_v1(
    true, 'f1400000-0000-0000-0000-000000000001', 1
  ) = (select response from private.pachanga_team_cosmetic_reward_policy_events
       where operation_id = 'f1400000-0000-0000-0000-000000000001'),
  'Policy activation replay must return the original response'
);

-- A later win cannot turn a historical first win into a retroactive reward.
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000001', 'historical-win-2', 'external',
  'f1200000-0000-0000-0000-000000000099', 3, 1, 'win', true
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000001'
      and cosmetic_key = 'team.shield.border.copper'
  ),
  'Historical first-win ownership must never be reconstructed after activation'
);

select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000008', 'historical-reto-11', 'external',
  'f1200000-0000-0000-0000-000000000099', 1, 1, 'draw', true
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
    where grants.group_id = 'f1200000-0000-0000-0000-000000000008'
      and definitions.achievement_key = 'team.external.matches.010'
  ) and not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000008'
      and cosmetic_key = 'team.shield.ornament.banner'
  ),
  'A team already above 10 Retos at activation must receive neither a late milestone nor Banner'
);

select private.pachanga_set_team_cosmetic_rewards_enabled_v1(
  false, 'f1400000-0000-0000-0000-000000000002', 1
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000002', 'flag-off-win', 'external',
  'f1200000-0000-0000-0000-000000000099', 2, 1, 'win', true
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
    where grants.group_id = 'f1200000-0000-0000-0000-000000000002'
      and definitions.achievement_key = 'team.external.wins.001'
  ) and not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000002'
  ),
  'Flag off must keep achievements while producing zero cosmetics'
);
select private.pachanga_set_team_cosmetic_rewards_enabled_v1(
  true, 'f1400000-0000-0000-0000-000000000003', 1
);
select private.pachanga_evaluate_achievements_v1(
  'f1200000-0000-0000-0000-000000000002', 'external',
  (select fact_id from reward_facts
   where group_id = 'f1200000-0000-0000-0000-000000000002' and label = 'flag-off-win')
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000002'
  ),
  'Re-enabling and replaying must not backfill an achievement emitted while off'
);

-- Story 1: first canonical Reto win.
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000003', 'first-win', 'external',
  'f1200000-0000-0000-0000-000000000099', 2, 1, 'win', true
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000003', 'second-win', 'external',
  'f1200000-0000-0000-0000-000000000099', 3, 2, 'win', true
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_cosmetic_inventory
   where group_id = 'f1200000-0000-0000-0000-000000000003'
     and cosmetic_key = 'team.shield.border.copper' and state = 'unlocked') = 1
  and (select count(*) from private.pachanga_team_cosmetic_reward_ledger
       where group_id = 'f1200000-0000-0000-0000-000000000003'
         and mapping_key = 'first_challenge_win') = 1,
  'Only the first Reto win may grant Borde Cobre'
);

-- Story 2: exact external match milestone 9 -> 10 -> 11.
do $$
declare match_number integer;
begin
  for match_number in 1..9 loop
    perform pg_temp.apply_reward_match(
      'f1200000-0000-0000-0000-000000000004',
      'reto-' || match_number, 'external',
      'f1200000-0000-0000-0000-000000000099', 1, 1, 'draw', false
    );
  end loop;
end;
$$;
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000004'
  ), 'Nine Retos must grant no Banner'
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000004', 'reto-10', 'external',
  'f1200000-0000-0000-0000-000000000099', 1, 1, 'draw', true
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000004', 'reto-11', 'external',
  'f1200000-0000-0000-0000-000000000099', 1, 1, 'draw', true
);
select private.pachanga_evaluate_achievements_v1(
  'f1200000-0000-0000-0000-000000000004', 'external',
  (select fact_id from reward_facts
   where group_id = 'f1200000-0000-0000-0000-000000000004' and label = 'reto-10')
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions on definitions.id = grants.definition_id
   where grants.group_id = 'f1200000-0000-0000-0000-000000000004'
     and definitions.achievement_key = 'team.external.matches.010') = 1
  and (select count(*) from public.pachanga_team_cosmetic_inventory
       where group_id = 'f1200000-0000-0000-0000-000000000004'
         and cosmetic_key = 'team.shield.ornament.banner') = 1,
  'The tenth canonical Reto grants one Banner and replays add nothing'
);

-- Stories 3 and 4: global canonical matches 25 and 50 remain independent.
do $$
declare match_number integer;
begin
  for match_number in 1..24 loop
    perform pg_temp.apply_reward_match(
      'f1200000-0000-0000-0000-000000000005',
      'match-' || match_number, 'internal', null, 1, 1, 'draw', false
    );
  end loop;
end;
$$;
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000005'
  ), 'Twenty-four matches must grant neither Laurels nor Silver'
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000005', 'match-25',
  'internal', null, 1, 1, 'draw', true
);
do $$
declare match_number integer;
begin
  for match_number in 26..49 loop
    perform pg_temp.apply_reward_match(
      'f1200000-0000-0000-0000-000000000005',
      'match-' || match_number, 'internal', null, 1, 1, 'draw', false
    );
  end loop;
end;
$$;
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000005'
      and cosmetic_key = 'team.shield.ornament.laurels'
  ) and not exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000005'
      and cosmetic_key = 'team.shield.border.silver'
  ), 'Match 25 grants Laurels while match 49 still has no Silver'
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000005', 'match-50',
  'internal', null, 1, 1, 'draw', true
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_cosmetic_inventory
   where group_id = 'f1200000-0000-0000-0000-000000000005'
     and cosmetic_key in ('team.shield.ornament.laurels', 'team.shield.border.silver')) = 2,
  'Match 50 grants Silver without replacing Laurels'
);

-- Story 5: first V3 clean sheet, including the existing 0-0 semantics.
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000006', 'clean-sheet-1', 'external',
  'f1200000-0000-0000-0000-000000000099', 0, 0, 'draw', true
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000006', 'clean-sheet-2', 'external',
  'f1200000-0000-0000-0000-000000000099', 1, 0, 'win', true
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_cosmetic_inventory
   where group_id = 'f1200000-0000-0000-0000-000000000006'
     and cosmetic_key = 'team.shield.effect.edge_glow') = 1
  and (select count(*) from private.pachanga_team_cosmetic_reward_ledger
       where group_id = 'f1200000-0000-0000-0000-000000000006'
         and mapping_key = 'first_clean_sheet') = 1,
  'Only the first V3 clean sheet grants Edge Glow'
);

-- Existing ownership records the mapping but creates no duplicate or notification.
insert into public.pachanga_team_cosmetic_inventory(
  group_id, cosmetic_key, source_grant_id, state, operation_id,
  source_kind, server_sequence, metadata
) values (
  'f1200000-0000-0000-0000-000000000007', 'team.shield.border.copper', null,
  'unlocked', 'f1500000-0000-0000-0000-000000000001', 'staging_fixture',
  nextval('public.pachanga_team_crest_sequence'), '{"fixture":"already-owned"}'
);
select pg_temp.apply_reward_match(
  'f1200000-0000-0000-0000-000000000007', 'already-owned-win', 'external',
  'f1200000-0000-0000-0000-000000000099', 2, 1, 'win', true
);
select pg_temp.assert_true(
  (select outcome = 'already_owned'
   from private.pachanga_team_cosmetic_reward_ledger
   where group_id = 'f1200000-0000-0000-0000-000000000007'
     and mapping_key = 'first_challenge_win')
  and (select count(*) from public.pachanga_team_cosmetic_inventory
       where group_id = 'f1200000-0000-0000-0000-000000000007'
         and cosmetic_key = 'team.shield.border.copper') = 1
  and (select count(*) from public.pachanga_user_notifications
       where kind = 'team_cosmetic_reward'
         and payload ->> 'groupId' = 'f1200000-0000-0000-0000-000000000007') = 0,
  'alreadyOwned must keep evidence without duplicate ownership, currency or notifications'
);

select pg_temp.assert_true(
  (select count(*) from private.pachanga_team_cosmetic_reward_ledger
   where outcome = 'granted') = 6
  and (select count(*) from private.pachanga_team_cosmetic_reward_ledger
       where outcome = 'already_owned') = 1
  and (select count(*) from public.pachanga_user_notifications
       where kind = 'team_cosmetic_reward') = 12,
  'Six scenario grants must produce one ledger row each and two idempotent admin notifications each'
);
select pg_temp.assert_true(
  not exists (
    select 1 from private.pachanga_team_cosmetic_reward_ledger
    where response ->> 'currencyGranted' <> '0'
  ), 'Team cosmetic rewards must never create compensation or currency'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1100000-0000-0000-0000-000000000001","role":"authenticated"}', true);
create temporary table first_win_owner_snapshot as
select public.get_pachanga_team_shield_snapshot_v1(
  'f1200000-0000-0000-0000-000000000003'
) as response;
select pg_temp.assert_true(
  (select (response ->> 'unseenCount')::integer = 1 from first_win_owner_snapshot),
  'The eligible owner must see one NEW cosmetic'
);
select public.mark_pachanga_team_cosmetics_seen_v1(
  'f1200000-0000-0000-0000-000000000003',
  array['team.shield.border.copper'],
  'f1600000-0000-0000-0000-000000000001', 0,
  '{"clientVersion":"2.0.0+reward-test","displayMode":"browser","surface":"team-identity"}'
);
select public.save_pachanga_team_shield_loadout_v1(
  'f1200000-0000-0000-0000-000000000003',
  jsonb_build_object(
    'schemaVersion', 1,
    'shapeKey', 'team.shield.shape.classic_iq',
    'backgroundKey', 'team.shield.background.duotone',
    'patternKey', 'team.shield.pattern.diagonal',
    'primaryColorKey', 'team.shield.color.midnight',
    'secondaryColorKey', 'team.shield.color.cyan',
    'primarySymbolKey', 'team.shield.symbol.ball_iq',
    'secondarySymbolKey', null,
    'borderKey', 'team.shield.border.copper',
    'topOrnamentKey', null,
    'sideOrnamentKey', null,
    'bottomOrnamentKey', null,
    'initials', 'FWR',
    'foundationYear', '2026',
    'effectKey', null,
    'primarySymbolScale', 1,
    'primarySymbolRotation', 0
  ),
  'f1600000-0000-0000-0000-000000000002',
  (select (response ->> 'revision')::bigint from first_win_owner_snapshot),
  '{"clientVersion":"2.0.0+reward-test","displayMode":"browser","surface":"team-identity"}'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1100000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1(
    'f1200000-0000-0000-0000-000000000003'
  ) ->> 'unseenCount')::integer = 1,
  'One admin marking NEW as seen must not affect another admin'
);
reset role;

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values (
  'f1200000-0000-0000-0000-000000000003',
  'f1100000-0000-0000-0000-000000000003', 'admin', 'Late Reward Admin'
);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f1100000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1(
    'f1200000-0000-0000-0000-000000000003'
  ) ->> 'unseenCount')::integer = 0,
  'A late admin must not inherit historical NEW cosmetics'
);
reset role;

select pg_temp.assert_true(
  (public.get_pachanga_team_public_shield_v1(
    'f1200000-0000-0000-0000-000000000003'
  ) -> 'config' ->> 'borderKey') = 'team.shield.border.copper'
  and not (public.get_pachanga_team_public_shield_v1(
    'f1200000-0000-0000-0000-000000000003'
  ) ? 'inventory'),
  'Public shield changes only after equip and never exposes inventory evidence'
);

select private.pachanga_revoke_match_progression_v1(
  (select fact_id from reward_facts
   where group_id = 'f1200000-0000-0000-0000-000000000003' and label = 'first-win'),
  'team_cosmetic_reward_correction_test'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_team_cosmetic_inventory
    where group_id = 'f1200000-0000-0000-0000-000000000003'
      and cosmetic_key = 'team.shield.border.copper' and state = 'unlocked'
  ) and exists (
    select 1 from private.pachanga_team_cosmetic_reward_ledger
    where group_id = 'f1200000-0000-0000-0000-000000000003'
      and mapping_key = 'first_challenge_win'
  ),
  'A later sporting correction must preserve revealed cosmetic ownership and evidence'
);

select pg_temp.assert_true(
  exists (
    select 1
    from public.pachanga_player_profiles profiles
    cross join reward_rating_before before
    where profiles.id = 'f1300000-0000-0000-0000-000000000001'
      and md5(jsonb_build_object(
        'currentOverall', profiles.current_overall,
        'calibratedOverall', profiles.calibrated_overall,
        'facets', profiles.current_facets,
        'reliability', profiles.rating_reliability,
        'engine', profiles.rating_engine_version
      )::text) = before.checksum
  ), 'Team cosmetic rewards must leave Rating V2 and facets unchanged'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_groups groups
    join reward_payload_before before on before.id = groups.id
    where md5(groups.payload::text) <> before.checksum
  ), 'Team cosmetic rewards must not modify sporting group payloads'
);
select pg_temp.assert_true(
  exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pachanga_team_cosmetic_inventory'
  ) and exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pachanga_team_shield_state'
  ), 'Inventory and shield revision must remain Realtime invalidation sources'
);

rollback;
