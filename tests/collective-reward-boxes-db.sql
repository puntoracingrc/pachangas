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

create or replace function pg_temp.expect_error(statement text, message text)
returns void
language plpgsql
as $$
begin
  execute statement;
  raise exception 'Expected failure: %', message;
exception
  when others then
    if sqlerrm = 'Expected failure: ' || message then raise; end if;
end;
$$;
grant execute on function pg_temp.expect_error(text, text) to authenticated;

create or replace function pg_temp.apply_canonical_match(
  source_match text,
  played timestamptz,
  team_goals integer,
  rival_goals integer,
  result text,
  assigned_goals jsonb default '{}'::jsonb,
  canonical_state text default 'active'
)
returns uuid
language plpgsql
as $$
declare
  fact_id uuid;
  participant record;
begin
  insert into public.pachanga_progression_match_facts(
    source_kind, source_match_id, source_revision, group_id, match_scope,
    outcome, goals_for, goals_against, clean_sheet, close_win, big_win,
    scoreless_draw, source_snapshot, state, played_at
  ) values (
    'external_result', source_match, 1,
    '82100000-0000-0000-0000-000000000001', 'external', result,
    team_goals, rival_goals, rival_goals = 0 and team_goals > 0,
    result = 'win' and team_goals - rival_goals = 1,
    result = 'win' and team_goals - rival_goals >= 4,
    team_goals = 0 and rival_goals = 0,
    jsonb_build_object(
      'canonicalState', case when canonical_state = 'active' then 'confirmed' else 'draft' end,
      'scoreHome', team_goals, 'scoreAway', rival_goals
    ), canonical_state, played
  ) returning id into fact_id;

  if canonical_state = 'active' then
    for participant in select value from generate_series(1, 10) value loop
      insert into public.pachanga_progression_player_match_facts(
        match_fact_id, group_id, player_profile_id, local_player_id,
        team_side, outcome, goals, card_snapshot
      ) values (
        fact_id, '82100000-0000-0000-0000-000000000001',
        ('82600000-0000-0000-0000-' || lpad(participant.value::text, 12, '0'))::uuid,
        'q' || participant.value::text, 'team', result,
        coalesce((assigned_goals ->> ('q' || participant.value::text))::integer, 0),
        jsonb_build_object(
          'currentOverall', 60 + participant.value,
          'engineVersion', 'pachangas-rating-v2'
        )
      );
      perform private.pachanga_rebuild_player_progression_stats_v1(
        ('82600000-0000-0000-0000-' || lpad(participant.value::text, 12, '0'))::uuid,
        'external'
      );
    end loop;
    perform private.pachanga_rebuild_team_progression_stats_v1(
      '82100000-0000-0000-0000-000000000001', 'external'
    );
    perform private.pachanga_evaluate_achievements_v1(
      '82100000-0000-0000-0000-000000000001', 'external', fact_id
    );
  end if;
  return fact_id;
end;
$$;

insert into auth.users(id, email)
select
  ('81100000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  'box-player-' || value::text || '@example.test'
from generate_series(1, 30) value;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values (
  '82100000-0000-0000-0000-000000000001',
  '81100000-0000-0000-0000-000000000001',
  'Equipo Cajas QA', 'CAJASQA',
  jsonb_build_object('players', (
    select jsonb_agg(jsonb_build_object(
      'id', 'q' || value::text,
      'name', 'Jugador ' || value::text,
      'ownerUserId', ('81100000-0000-0000-0000-' || lpad(value::text, 12, '0'))::text,
      'position', case when value = 10 then 'POR' else 'DEL' end
    ) order by value)
    from generate_series(1, 30) value
  ))
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select '82100000-0000-0000-0000-000000000001',
  ('81100000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  case when value = 1 then 'owner' else 'player' end,
  'Jugador ' || value::text
from generate_series(1, 30) value;

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability,
  rating_engine_version
)
select
  ('82600000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  ('81100000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  'Jugador ' || value::text,
  case when value = 10 then 'POR' else 'DEL' end,
  60 + value, 59 + value, 60 + value,
  jsonb_build_object(
    'pace', 60 + value, 'shooting', 60 + value,
    'passing', 60 + value, 'dribbling', 60 + value,
    'defending', 60 + value, 'physical', 60 + value
  ), 80, 'pachangas-rating-v2'
from generate_series(1, 30) value;

create temporary table rating_before as
select id, current_overall, calibrated_overall, current_facets,
  rating_reliability, rating_engine_version
from public.pachanga_player_profiles
where id between '82600000-0000-0000-0000-000000000001'::uuid
  and '82600000-0000-0000-0000-000000000030'::uuid;

select pg_temp.assert_true(
  not has_table_privilege(
    'authenticated', 'private.pachanga_reward_box_contents', 'SELECT'
  ),
  'Authenticated clients must never read sealed box contents directly'
);
select pg_temp.assert_true(
  not has_table_privilege(
    'authenticated', 'public.pachanga_reward_recipients', 'UPDATE'
  ),
  'Authenticated clients must never open a box by updating its row directly'
);
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_player_points_ledger', 'INSERT')
    and not has_table_privilege('authenticated', 'public.pachanga_player_points_ledger', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.pachanga_player_point_accounts', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.pachanga_player_reward_inventory', 'INSERT'),
  'Authenticated clients must never mutate points or player inventory directly'
);

-- A prior defeat consumes only the first-match milestone. The following 5-0
-- therefore has exactly the four collective achievements in the product case.
select pg_temp.apply_canonical_match(
  'boxes-prelude-loss', '2026-01-01T20:00:00Z', 0, 1, 'loss'
) as prelude_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-five-nil', '2026-01-08T20:00:00Z', 5, 0, 'win',
  '{"q1":3,"q2":2}'::jsonb
) as five_nil_fact \gset

select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = :'five_nil_fact'::uuid
     and grants.subject_type = 'team' and grants.state = 'active'
     and definitions.achievement_key in (
       'team.external.wins.001',
       'team.external.clean_sheets.001',
       'team.external.big_wins.001',
       'team.external.match_goals.005'
     )) = 4,
  'The 5-0 must grant victory, clean sheet, big win and the five-goal tier'
);
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = :'five_nil_fact'::uuid
     and definitions.category = 'match_goals') = 1,
  'Only the highest collective goal tier may be granted per match'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_reward_grants rewards
    join public.pachanga_achievement_grants grants
      on grants.id = rewards.achievement_grant_id
    where grants.subject_type = 'player'
  ),
  'Personal achievements must never create rewards or boxes'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_reward_recipients boxes
    where boxes.match_fact_id = :'five_nil_fact'::uuid
    group by boxes.achievement_grant_id
    having count(*) <> 10
  ),
  'Each collective achievement must create one box per actual participant'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients boxes
   where boxes.match_fact_id = :'five_nil_fact'::uuid
     and boxes.status = 'pending') = 40,
  'Four collective achievements and ten participants must create forty boxes'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients boxes
   where boxes.match_fact_id = :'five_nil_fact'::uuid
     and boxes.economy_version = 1
     and boxes.box_type is not null
     and boxes.box_rarity is not null
     and boxes.reward_pool_key is not null) = 40,
  'Every generated box must persist its economy version, type, rarity and pool'
);
select pg_temp.assert_true(
  (select count(*)
   from private.pachanga_reward_box_contents contents
   join public.pachanga_reward_recipients boxes on boxes.box_id = contents.box_id
   where boxes.match_fact_id = :'five_nil_fact'::uuid
     and contents.catalog_version = 1
     and contents.content_hash = md5(contents.reward_payload::text)
     and contents.reward_payload ->> 'catalogVersion' = '1') = 40,
  'Every participant box must have one stable server-sealed V1 payload'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_reward_recipients first_box
    join public.pachanga_reward_recipients peer_box
      on peer_box.achievement_grant_id = first_box.achievement_grant_id
    where first_box.match_fact_id = :'five_nil_fact'::uuid
      and peer_box.match_fact_id = first_box.match_fact_id
      and peer_box.box_type <> first_box.box_type
  ),
  'All participants must receive an equivalent box tier for one collective achievement'
);
select pg_temp.assert_true(
  not exists (select 1 from public.pachanga_player_point_accounts)
    and not exists (select 1 from public.pachanga_player_points_ledger)
    and not exists (
      select 1 from public.pachanga_player_reward_inventory
      where source_box_id is not null
    ),
  'Pending boxes must grant neither points nor inventory'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_reward_recipients boxes
    where boxes.match_fact_id = :'five_nil_fact'::uuid
      and boxes.user_id between '81100000-0000-0000-0000-000000000011'::uuid
        and '81100000-0000-0000-0000-000000000030'::uuid
  ),
  'Twenty roster members who did not participate must receive zero boxes'
);
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = :'five_nil_fact'::uuid
     and grants.subject_type = 'player' and grants.state = 'active'
     and definitions.parameters ->> 'ruleKind' = 'player_match_goals') = 2,
  'Pedro with three and Juan with two goals must receive only one personal scoring occurrence each'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = :'five_nil_fact'::uuid
      and grants.subject_id = '82600000-0000-0000-0000-000000000001'
      and definitions.achievement_key = 'player.external.hat_tricks.001'
      and grants.occurrence_metadata ->> 'displayTitle' = 'Primer hat-trick'
  ) and exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = :'five_nil_fact'::uuid
      and grants.subject_id = '82600000-0000-0000-0000-000000000002'
      and definitions.achievement_key = 'player.external.braces.001'
      and grants.occurrence_metadata ->> 'displayTitle' = 'Primer doblete'
  ),
  'Pedro and Juan must receive the first hat-trick and first double recognitions'
);

-- Reprocessing a canonical fact is idempotent for achievements and boxes.
select private.pachanga_evaluate_achievements_v1(
  '82100000-0000-0000-0000-000000000001', 'external', :'five_nil_fact'::uuid
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients boxes
   where boxes.match_fact_id = :'five_nil_fact'::uuid) = 40,
  'Reprocessing the same match must not duplicate boxes'
);

-- Repeatable personal scoring families and cumulative milestones.
select pg_temp.apply_canonical_match(
  'boxes-second-double', '2026-01-15T20:00:00Z', 2, 1, 'win',
  '{"q2":2}'::jsonb
) as second_double_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-second-hat', '2026-01-22T20:00:00Z', 3, 1, 'win',
  '{"q1":3}'::jsonb
) as second_hat_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-poker', '2026-01-29T20:00:00Z', 4, 1, 'win',
  '{"q1":4}'::jsonb
) as poker_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-repoker', '2026-02-05T20:00:00Z', 5, 2, 'win',
  '{"q1":5}'::jsonb
) as repoker_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-double-hat', '2026-02-12T20:00:00Z', 6, 2, 'win',
  '{"q1":6}'::jsonb
) as double_hat_fact \gset

select pg_temp.assert_true(
  (select count(*) = 2 and min(grants.sequence_count) = 1
      and max(grants.sequence_count) = 2
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_id = '82600000-0000-0000-0000-000000000002'
     and grants.state = 'active'
     and definitions.achievement_key = 'player.external.braces.001'),
  'A second double must create a second ordered occurrence'
);
select pg_temp.assert_true(
  (select count(*) = 2 and bool_or(grants.is_first)
      and bool_or(not grants.is_first)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_id = '82600000-0000-0000-0000-000000000001'
     and grants.state = 'active'
     and definitions.achievement_key = 'player.external.hat_tricks.001'),
  'Hat-tricks must distinguish the first occurrence from repetitions'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_id = '82600000-0000-0000-0000-000000000001'
     and grants.state = 'active'
     and definitions.achievement_key in (
       'player.external.pokers.001',
       'player.external.repokers.001',
       'player.external.double_hat_tricks.001'
     )) = 3,
  'Poker, repoker and double hat-trick must each persist as repeatable occurrences'
);
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = :'repoker_fact'::uuid
     and definitions.parameters ->> 'ruleKind' = 'player_match_goals') = 1
  and exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = :'repoker_fact'::uuid
      and definitions.achievement_key = 'player.external.repokers.001'
  ),
  'Five personal goals must create only the repoker occurrence in its family'
);
select pg_temp.assert_true(
  exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.subject_id = '82600000-0000-0000-0000-000000000001'
      and definitions.achievement_key in (
        'player.external.goals.001', 'player.external.goals.010'
      )
      and grants.state = 'active'
    group by grants.subject_id
    having count(*) = 2
  ),
  'Personal cumulative goal milestones may coexist with the highest match feat'
);

-- Collective goals use the scoreboard, independent of scorer distribution.
select pg_temp.apply_canonical_match(
  'boxes-five-scorers', '2026-02-19T20:00:00Z', 5, 3, 'win',
  '{"q1":1,"q2":1,"q3":1,"q4":1,"q5":1}'::jsonb
) as five_scorers_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-one-scorer', '2026-02-26T20:00:00Z', 5, 3, 'win',
  '{"q1":5}'::jsonb
) as one_scorer_fact \gset
select pg_temp.apply_canonical_match(
  'boxes-unassigned', '2026-03-05T20:00:00Z', 5, 3, 'win',
  '{}'::jsonb
) as unassigned_fact \gset
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id in (
       :'five_scorers_fact'::uuid, :'one_scorer_fact'::uuid, :'unassigned_fact'::uuid
     )
     and definitions.achievement_key = 'team.external.match_goals.005') = 3,
  'Five team goals must grant the same collective tier for every scorer distribution'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = :'unassigned_fact'::uuid
      and grants.subject_type = 'player'
      and definitions.parameters ->> 'ruleKind' = 'player_match_goals'
  ),
  'Unassigned goals must not generate a personal scoring achievement'
);

select pg_temp.apply_canonical_match(
  'boxes-draft', '2026-03-12T20:00:00Z', 5, 0, 'win',
  '{"q1":5}'::jsonb, 'revoked'
) as draft_fact \gset
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_grants grants
    where grants.origin_match_fact_id = :'draft_fact'::uuid
  ) and not exists (
    select 1 from public.pachanga_reward_recipients boxes
    where boxes.match_fact_id = :'draft_fact'::uuid
  ),
  'A noncanonical match must create no achievement and no box'
);

-- Atomic opening, every V1 reward kind, replay, inventory and correction.
select
  (array_agg(boxes.box_id order by boxes.box_id))[1] as opened_box_id,
  (array_agg(boxes.achievement_grant_id order by boxes.box_id))[1] as opened_grant_id,
  (array_agg(boxes.box_type order by boxes.box_id))[1] as opened_box_type,
  (array_agg(boxes.box_id order by boxes.box_id))[2] as cosmetic_box_id,
  (array_agg(boxes.box_id order by boxes.box_id))[3] as combination_box_id,
  (array_agg(boxes.box_id order by boxes.box_id))[4] as duplicate_box_id
from public.pachanga_reward_recipients boxes
where boxes.match_fact_id = :'five_nil_fact'::uuid
  and boxes.user_id = '81100000-0000-0000-0000-000000000001'
  and boxes.status = 'pending' \gset

alter table private.pachanga_reward_box_contents
  disable trigger keep_pachanga_reward_box_contents_sealed_v1;
update private.pachanga_reward_box_contents contents
set reward_payload = fixtures.payload,
    content_hash = md5(fixtures.payload::text)
from (values
  (:'opened_box_id'::uuid, jsonb_build_object(
    'schemaVersion', 1, 'catalogVersion', 1, 'boxType', :'opened_box_type',
    'reward', jsonb_build_object('kind', 'points', 'points', 6)
  )),
  (:'cosmetic_box_id'::uuid, jsonb_build_object(
    'schemaVersion', 1, 'catalogVersion', 1, 'boxType', 'collective.common',
    'reward', jsonb_build_object(
      'kind', 'player_cosmetic', 'points', 0, 'cosmeticKey', 'symbol.ball',
      'duplicateConversionPoints', 4
    )
  )),
  (:'combination_box_id'::uuid, jsonb_build_object(
    'schemaVersion', 1, 'catalogVersion', 1, 'boxType', 'collective.common',
    'reward', jsonb_build_object(
      'kind', 'combination', 'points', 5, 'cosmeticKey', 'pattern.stripes',
      'duplicateConversionPoints', 4
    )
  )),
  (:'duplicate_box_id'::uuid, jsonb_build_object(
    'schemaVersion', 1, 'catalogVersion', 1, 'boxType', 'collective.common',
    'reward', jsonb_build_object(
      'kind', 'player_cosmetic', 'points', 0, 'cosmeticKey', 'symbol.ball',
      'duplicateConversionPoints', 4
    )
  ))
) fixtures(box_id, payload)
where contents.box_id = fixtures.box_id;
alter table private.pachanga_reward_box_contents
  enable trigger keep_pachanga_reward_box_contents_sealed_v1;

do $$
begin
  update private.pachanga_reward_box_contents
  set reward_payload = '{}'::jsonb
  where box_id in (select box_id from private.pachanga_reward_box_contents limit 1);
  raise exception 'A sealed box unexpectedly changed';
exception when others then
  if sqlerrm = 'A sealed box unexpectedly changed' then raise; end if;
  if sqlerrm <> 'Sealed reward box contents are immutable' then raise; end if;
end;
$$;

update public.pachanga_reward_economy_versions
set state = 'retired', retired_at = clock_timestamp()
where version = 1;
insert into public.pachanga_reward_economy_versions(
  version, state, currency_key, config, activated_at
) values (2, 'active', 'player_points', '{"policy":"qa-v2"}', clock_timestamp());

set local role authenticated;
select set_config('request.jwt.claim.sub', '81100000-0000-0000-0000-000000000002', true);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients boxes
   where boxes.user_id = '81100000-0000-0000-0000-000000000001') = 0,
  'A player must not read another player private boxes'
);
select pg_temp.expect_error(format(
  'select public.open_pachanga_reward_box_v2(%L::uuid, %L::uuid, 1, %L::jsonb)',
  :'opened_box_id', '84100000-0000-0000-0000-000000000099', '{}'
), 'another player cannot open this box');
select pg_temp.expect_error(
  'insert into public.pachanga_player_points_ledger(player_profile_id,user_id,delta,balance_after,source_type,source_id,idempotency_key) values (''82600000-0000-0000-0000-000000000002'',''81100000-0000-0000-0000-000000000002'',1000,1000,''admin_adjustment'',''82600000-0000-0000-0000-000000000002'',''forged'')',
  'clients cannot forge point ledger entries'
);
select pg_temp.expect_error(
  'insert into public.pachanga_player_point_accounts(player_profile_id,user_id,balance,lifetime_earned,lifetime_spent) values (''82600000-0000-0000-0000-000000000002'',''81100000-0000-0000-0000-000000000002'',1000,1000,0)',
  'clients cannot forge point balances'
);
select pg_temp.expect_error(
  'insert into public.pachanga_player_reward_inventory(player_profile_id,reward_kind,reward_key,state) values (''82600000-0000-0000-0000-000000000002'',''player_cosmetic'',''symbol.crown'',''unlocked'')',
  'clients cannot forge cosmetics'
);
select pg_temp.expect_error(format(
  'update public.pachanga_reward_recipients set box_rarity = %L where box_id = %L::uuid',
  'legendary', :'opened_box_id'
), 'clients cannot change box rarity');
select pg_temp.expect_error(format(
  'update private.pachanga_reward_box_contents set reward_payload = %L::jsonb where box_id = %L::uuid',
  '{"reward":{"kind":"points","points":9999}}', :'opened_box_id'
), 'clients cannot change sealed box contents');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81100000-0000-0000-0000-000000000001', true);
select public.get_pachanga_progression_snapshot_v1(
  '82100000-0000-0000-0000-000000000001'
) as pending_snapshot \gset
reset role;
select pg_temp.assert_true(
  exists (
    select 1
    from jsonb_array_elements(:'pending_snapshot'::jsonb -> 'rewards') boxes(value)
    where boxes.value ->> 'boxId' = :'opened_box_id'
      and boxes.value ->> 'status' = 'pending'
      and not boxes.value ? 'rewardPayload'
  ),
  'The canonical pending snapshot must hide sealed reward contents'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '81100000-0000-0000-0000-000000000001', true);
select public.open_pachanga_reward_box_v2(
  :'opened_box_id'::uuid,
  '84100000-0000-0000-0000-000000000001', 1,
  '{"sessionId":"box-device-a"}'::jsonb
) as first_open \gset
select public.open_pachanga_reward_box_v2(
  :'opened_box_id'::uuid,
  '84100000-0000-0000-0000-000000000001', 1,
  '{"sessionId":"box-device-a"}'::jsonb
) as replay_open \gset
select pg_temp.expect_error(format(
  'select public.open_pachanga_reward_box_v2(%L::uuid, %L::uuid, 1, %L::jsonb)',
  :'cosmetic_box_id', '84100000-0000-0000-0000-000000000001', '{}'
), 'an operation id cannot be reused for another box');
select public.open_pachanga_reward_box_v2(
  :'opened_box_id'::uuid,
  '84100000-0000-0000-0000-000000000002', 2,
  '{"sessionId":"box-device-b"}'::jsonb
) as reconnect_open \gset
select public.get_pachanga_progression_snapshot_v1(
  '82100000-0000-0000-0000-000000000001'
) as mid_sequence_snapshot \gset
select public.open_pachanga_reward_box_v2(
  :'cosmetic_box_id'::uuid,
  '84100000-0000-0000-0000-000000000003', 1,
  '{"sessionId":"box-device-return"}'::jsonb
) as cosmetic_open \gset
select public.get_pachanga_progression_snapshot_v1(
  '82100000-0000-0000-0000-000000000001'
) as two_opened_snapshot \gset
select public.open_pachanga_reward_box_v2(
  :'combination_box_id'::uuid,
  '84100000-0000-0000-0000-000000000004', 1,
  '{"sessionId":"box-device-return"}'::jsonb
) as combination_open \gset
select public.open_pachanga_reward_box_v2(
  :'duplicate_box_id'::uuid,
  '84100000-0000-0000-0000-000000000005', 1,
  '{"sessionId":"box-device-return"}'::jsonb
) as duplicate_open \gset
select public.get_pachanga_progression_snapshot_v1(
  '82100000-0000-0000-0000-000000000001'
) as completed_sequence_snapshot \gset
reset role;

select pg_temp.assert_true(
  :'first_open'::jsonb = :'replay_open'::jsonb,
  'The same opening operation must replay the exact canonical response'
);
select pg_temp.assert_true(
  (:'reconnect_open'::jsonb ->> 'alreadyOpened')::boolean,
  'A second device must converge without granting the reward twice'
);
select pg_temp.assert_true(
  (:'first_open'::jsonb -> 'rewardPayload' ->> 'catalogVersion')::integer = 1
    and (:'first_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'pointsGranted')::integer = 6,
  'A sealed V1 box must keep its original six points after the live catalog changes'
);
select pg_temp.assert_true(
  (select count(*) from jsonb_array_elements(
    :'mid_sequence_snapshot'::jsonb -> 'rewards'
  ) boxes(value)
   where boxes.value ->> 'matchFactId' = :'five_nil_fact'
     and boxes.value ->> 'status' = 'pending') = 3,
  'Closing after one box and returning must leave the remaining sequence pending'
);
select pg_temp.assert_true(
  (select count(*) from jsonb_array_elements(
    :'two_opened_snapshot'::jsonb -> 'rewards'
  ) boxes(value)
   where boxes.value ->> 'boxId' in (
     :'opened_box_id', :'cosmetic_box_id', :'combination_box_id', :'duplicate_box_id'
   ) and boxes.value ->> 'status' = 'pending') = 2,
  'Closing after two of four boxes must resume with exactly two pending'
);
select pg_temp.assert_true(
  (:'cosmetic_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'cosmeticGranted')::boolean
    and (:'cosmetic_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'pointsGranted')::integer = 0,
  'A cosmetic box must grant one new personal cosmetic without points'
);
select pg_temp.assert_true(
  (:'combination_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'cosmeticGranted')::boolean
    and (:'combination_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'pointsGranted')::integer = 5,
  'A combination box must grant its cosmetic and points atomically'
);
select pg_temp.assert_true(
  (:'duplicate_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'duplicateConverted')::boolean
    and (:'duplicate_open'::jsonb -> 'rewardPayload' -> 'grant' ->> 'duplicateConversionPoints')::integer = 4,
  'A duplicate cosmetic must convert to its audited point value'
);
select pg_temp.assert_true(
  (select balance = 15 and lifetime_earned = 15 and lifetime_spent = 0
   from public.pachanga_player_point_accounts accounts
   where accounts.player_profile_id = '82600000-0000-0000-0000-000000000001'),
  'Points, combination and duplicate conversion must produce the exact balance once'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_points_ledger ledger
   where ledger.player_profile_id = '82600000-0000-0000-0000-000000000001'
     and ledger.source_type = 'reward_box') = 3,
  'Only boxes that grant points may append one immutable ledger entry each'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_reward_inventory inventory
   where inventory.player_profile_id = '82600000-0000-0000-0000-000000000001'
     and inventory.reward_kind = 'player_cosmetic'
     and inventory.state = 'unlocked') = 2,
  'Duplicate cosmetics must not create a second inventory copy'
);
select pg_temp.assert_true(
  (:'completed_sequence_snapshot'::jsonb -> 'rewardEconomy' -> 'account' ->> 'balance')::integer = 15
    and jsonb_array_length(:'completed_sequence_snapshot'::jsonb -> 'rewardEconomy' -> 'inventory') = 2,
  'The canonical read model must expose the confirmed point account and inventory'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_progression_events events
   where events.event_type = 'reward_opened'
     and events.payload ->> 'boxId' = :'opened_box_id') = 1,
  'Double opening and reconnection must emit one grant event'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_reward_recipients boxes
    where boxes.match_fact_id = :'five_nil_fact'::uuid
      and boxes.user_id = '81100000-0000-0000-0000-000000000002'
      and boxes.achievement_grant_id = :'opened_grant_id'::uuid
      and boxes.status = 'pending'
  ),
  'One player opening a box must not open a teammate box'
);

select private.pachanga_revoke_achievement_grant_v1(
  :'opened_grant_id'::uuid, 'qa_result_correction'
);
select pg_temp.assert_true(
  (select status = 'opened' and source_correction ->> 'state' = 'source_revoked'
   from public.pachanga_reward_recipients boxes
   where boxes.box_id = :'opened_box_id'::uuid),
  'A correction must preserve an opened reward with an audit annotation'
);
select pg_temp.assert_true(
  (select status = 'revoked'
   from public.pachanga_reward_recipients boxes
   where boxes.achievement_grant_id = :'opened_grant_id'::uuid
     and boxes.user_id = '81100000-0000-0000-0000-000000000002'),
  'A correction must revoke a teammate pending box'
);

select pg_temp.assert_true(
  not exists (
    select 1
    from rating_before before
    join public.pachanga_player_profiles profiles on profiles.id = before.id
    where row(
      before.current_overall, before.calibrated_overall,
      before.current_facets, before.rating_reliability,
      before.rating_engine_version
    ) is distinct from row(
      profiles.current_overall, profiles.calibrated_overall,
      profiles.current_facets, profiles.rating_reliability,
      profiles.rating_engine_version
    )
  ),
  'Achievements, boxes and rewards must not modify Rating V2 or facets'
);

rollback;
