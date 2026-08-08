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
from generate_series(1, 11) value;

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
    from generate_series(1, 11) value
  ))
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select '82100000-0000-0000-0000-000000000001',
  ('81100000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  case when value = 1 then 'owner' else 'player' end,
  'Jugador ' || value::text
from generate_series(1, 11) value;

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
from generate_series(1, 11) value;

create temporary table rating_before as
select id, current_overall, calibrated_overall, current_facets,
  rating_reliability, rating_engine_version
from public.pachanga_player_profiles
where id between '82600000-0000-0000-0000-000000000001'::uuid
  and '82600000-0000-0000-0000-000000000011'::uuid;

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
  not exists (
    select 1 from public.pachanga_reward_recipients boxes
    where boxes.match_fact_id = :'five_nil_fact'::uuid
      and boxes.user_id = '81100000-0000-0000-0000-000000000011'
  ),
  'A roster member who did not play must receive zero boxes'
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

-- Atomic opening, replay, independent recipients and correction policy.
select boxes.box_id as opened_box_id, boxes.achievement_grant_id as opened_grant_id
from public.pachanga_reward_recipients boxes
where boxes.match_fact_id = :'five_nil_fact'::uuid
  and boxes.user_id = '81100000-0000-0000-0000-000000000001'
  and boxes.status = 'pending'
order by boxes.box_id
limit 1 \gset

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
select public.open_pachanga_reward_box_v2(
  :'opened_box_id'::uuid,
  '84100000-0000-0000-0000-000000000002', 2,
  '{"sessionId":"box-device-b"}'::jsonb
) as reconnect_open \gset
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
