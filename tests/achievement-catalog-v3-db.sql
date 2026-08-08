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

create temporary table v3_facts(label text primary key, fact_id uuid not null);

create or replace function pg_temp.apply_v3_match(
  target_group_id uuid,
  target_profile_id uuid,
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
    target_label, 1, target_group_id,
    case when target_scope = 'external' then target_opponent_id else null end,
    target_scope, target_outcome, target_goals_for, target_goals_against,
    target_goals_against = 0,
    target_outcome = 'win' and target_goals_for - target_goals_against = 1,
    target_outcome = 'win' and target_goals_for - target_goals_against >= 4,
    target_goals_for = 0 and target_goals_against = 0, true,
    jsonb_build_object('canonicalState', 'confirmed', 'officialState', 'confirmed'),
    'active', nextval('public.pachanga_progression_sequence'),
    '2026-08-08T12:00:00Z'::timestamptz
      + make_interval(secs => nextval('public.pachanga_progression_sequence'))
  ) returning id into saved_fact_id;

  insert into public.pachanga_progression_player_match_facts(
    match_fact_id, group_id, player_profile_id, local_player_id,
    team_side, outcome, goals, card_snapshot
  ) values (
    saved_fact_id, target_group_id, target_profile_id, target_label || '-player',
    'team', target_outcome, 0,
    '{"currentOverall":67,"engineVersion":"pachangas-rating-v2"}'::jsonb
  );
  perform private.pachanga_rebuild_player_progression_stats_v1(
    target_profile_id, target_scope
  );
  perform private.pachanga_rebuild_team_progression_stats_v1(
    target_group_id, target_scope
  );
  if target_evaluate then
    perform private.pachanga_evaluate_achievements_v1(
      target_group_id, target_scope, saved_fact_id
    );
  end if;
  insert into v3_facts(label, fact_id) values (target_label, saved_fact_id);
  return saved_fact_id;
end;
$$;

insert into auth.users(id, email) values
  ('b3100000-0000-0000-0000-000000000001', 'v3-player@example.test'),
  ('b3100000-0000-0000-0000-000000000002', 'v3-outsider@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select group_id, 'b3100000-0000-0000-0000-000000000001', name, code,
  '{"players":[]}'::jsonb
from (values
  ('b3200000-0000-0000-0000-000000000001'::uuid, 'Goles V3', 'V3GOL001'),
  ('b3200000-0000-0000-0000-000000000002'::uuid, 'Dominio V3', 'V3DOM002'),
  ('b3200000-0000-0000-0000-000000000003'::uuid, 'Global V3', 'V3ALL003'),
  ('b3200000-0000-0000-0000-000000000004'::uuid, 'Rachas V3', 'V3STR004'),
  ('b3200000-0000-0000-0000-000000000005'::uuid, 'Rivales V3', 'V3RIV005')
) groups(group_id, name, code);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select ('b3300000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  'b3100000-0000-0000-0000-000000000001', 'Rival V3 ' || value,
  'V3R' || lpad(value::text, 5, '0'), '{"players":[]}'::jsonb
from generate_series(1, 30) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select id, 'b3100000-0000-0000-0000-000000000001', 'owner', 'Jugador V3'
from public.pachanga_groups
where id::text like 'b32%';

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values (
  'b3600000-0000-0000-0000-000000000001',
  'b3100000-0000-0000-0000-000000000001', 'Jugador V3', 'DEL', 67, 66, 67,
  '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}',
  80, 'pachangas-rating-v2'
);

create temporary table v3_rating_before as
select current_overall, calibrated_overall, current_facets,
  rating_reliability, rating_engine_version
from public.pachanga_player_profiles
where id = 'b3600000-0000-0000-0000-000000000001';

select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_definitions
   where active and catalog_key = 'achievement_catalog_v3'
     and subject_type = 'team') = 60,
  'V3 must expose exactly 60 active collective definitions'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_definitions
   where active and catalog_key = 'achievement_catalog_v2'
     and subject_type = 'player') = 45,
  'All 45 individual V2 definitions must remain active and unchanged'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_definitions
    where active and family_key in ('team.internal.matches', 'team.external.matches')
  ),
  'Split match milestones must be inactive after the global trajectory activates'
);

create temporary table expected_goal_components(
  goals integer primary key,
  expected jsonb not null
);
insert into expected_goal_components values
  (1, '{}'::jsonb),
  (2, '{"doblete":1}'),
  (3, '{"hat_trick":1}'),
  (4, '{"poker":1}'),
  (5, '{"manita":1}'),
  (6, '{"hat_trick":2}'),
  (7, '{"doblete":1,"manita":1}'),
  (8, '{"poker":2}'),
  (9, '{"hat_trick":3}'),
  (10, '{"manita":2}'),
  (11, '{"hat_trick":2,"manita":1}'),
  (12, '{"doblete":1,"manita":2}'),
  (13, '{"hat_trick":1,"manita":2}'),
  (14, '{"manita":2,"poker":1}'),
  (15, '{"manita":3}'),
  (16, '{"hat_trick":2,"manita":2}'),
  (17, '{"doblete":1,"manita":3}'),
  (18, '{"manita":2,"poker":2}'),
  (19, '{"hat_trick":3,"manita":2}'),
  (20, '{"manita":4}');

select pg_temp.assert_true(
  not exists (
    select 1
    from expected_goal_components expected
    cross join lateral (
      select coalesce(jsonb_object_agg(summary.key, summary.amount), '{}'::jsonb) as value
      from (
        select component ->> 'key' as key, count(*)::integer as amount
        from jsonb_array_elements(
          private.pachanga_goal_reward_components_v3(expected.goals)
        ) component
        group by component ->> 'key'
      ) summary
    ) actual
    where actual.value <> expected.expected
  ),
  'SQL goal decomposition must match every approved case from 1 through 20'
);
select pg_temp.assert_true(
  not exists (
    select 1 from generate_series(2, 250) goals
    where (select coalesce(sum((component ->> 'goals')::integer), 0)
      from jsonb_array_elements(
        private.pachanga_goal_reward_components_v3(goals)
      ) component) <> goals
  ),
  'Every total above one must be represented exactly without a remainder'
);

do $$
declare
  goals integer;
begin
  for goals in 1..20 loop
    perform pg_temp.apply_v3_match(
      'b3200000-0000-0000-0000-000000000001',
      'b3600000-0000-0000-0000-000000000001',
      'v3-goals-' || lpad(goals::text, 2, '0'), 'external',
      'b3300000-0000-0000-0000-000000000001',
      goals, goals, 'draw', true
    );
  end loop;
end;
$$;

select pg_temp.assert_true(
  not exists (
    select 1
    from generate_series(1, 20) goals
    left join lateral (
      select count(distinct grants.id)::integer as achievement_count,
        count(recipients.box_id)::integer as box_count,
        coalesce(sum((recipients.reward_component ->> 'goals')::integer), 0)::integer
          as represented_goals
      from v3_facts facts_index
      join public.pachanga_achievement_grants grants
        on grants.origin_match_fact_id = facts_index.fact_id
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
       and definitions.category = 'match_goals'
      left join public.pachanga_reward_recipients recipients
        on recipients.achievement_grant_id = grants.id
       and recipients.user_id = 'b3100000-0000-0000-0000-000000000001'
      where facts_index.label = 'v3-goals-' || lpad(goals::text, 2, '0')
    ) actual on true
    where actual.achievement_count <> case when goals = 1 then 0 else 1 end
      or actual.box_count <> case when goals = 1 then 0 else
        jsonb_array_length(private.pachanga_goal_reward_components_v3(goals)) end
      or actual.represented_goals <> case when goals = 1 then 0 else goals end
  ),
  'Every goal occurrence must create one achievement and one independent box per component'
);

select count(*) as boxes_before_replay
from public.pachanga_reward_recipients
where match_fact_id = (select fact_id from v3_facts where label = 'v3-goals-09') \gset
select private.pachanga_evaluate_achievements_v1(
  'b3200000-0000-0000-0000-000000000001', 'external',
  (select fact_id from v3_facts where label = 'v3-goals-09')
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients
   where match_fact_id = (select fact_id from v3_facts where label = 'v3-goals-09'))
    = :'boxes_before_replay'::integer,
  'Reprocessing a multi-component grant must create zero additional boxes'
);

do $$
declare
  item record;
begin
  for item in select * from (values
    ('dom-4-0', 4, 0, 'win'), ('dom-5-0', 5, 0, 'win'),
    ('dom-8-0', 8, 0, 'win'), ('dom-3-0', 3, 0, 'win'),
    ('dom-5-1', 5, 1, 'win'), ('dom-4-1', 4, 1, 'win'),
    ('dom-0-0', 0, 0, 'draw')
  ) cases(label, goals_for, goals_against, outcome)
  loop
    perform pg_temp.apply_v3_match(
      'b3200000-0000-0000-0000-000000000002',
      'b3600000-0000-0000-0000-000000000001', item.label,
      'external', 'b3300000-0000-0000-0000-000000000002',
      item.goals_for, item.goals_against, item.outcome, true
    );
  end loop;
end;
$$;

select pg_temp.assert_true(
  (select array_agg(facts_index.label order by facts_index.label)
   from v3_facts facts_index
   join public.pachanga_achievement_grants grants
     on grants.origin_match_fact_id = facts_index.fact_id
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where definitions.family_key = 'team.external.absolute_dominance')
  = array['dom-4-0','dom-5-0','dom-8-0'],
  'Dominio absoluto must unlock only for Reto wins by four without conceding'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = (select fact_id from v3_facts where label = 'dom-4-0')
     and definitions.family_key in (
       'team.external.wins', 'team.external.match_goals',
       'team.external.big_wins', 'team.external.clean_sheets',
       'team.external.absolute_dominance'
     )) = 5,
  'A 4-0 Reto must keep all five additive collective achievements'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = (select fact_id from v3_facts where label = 'dom-0-0')
      and definitions.family_key = 'team.external.clean_sheets'
  ) and not exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.origin_match_fact_id = (select fact_id from v3_facts where label = 'dom-0-0')
      and definitions.family_key in (
        'team.external.wins', 'team.external.big_wins',
        'team.external.absolute_dominance'
      )
  ),
  'A 0-0 must grant clean sheet but not victory, big win or dominance'
);

do $$
declare
  match_number integer;
  scope text;
begin
  for match_number in 1..24 loop
    scope := case when match_number <= 17 then 'internal' else 'external' end;
    perform pg_temp.apply_v3_match(
      'b3200000-0000-0000-0000-000000000003',
      'b3600000-0000-0000-0000-000000000001',
      'global-baseline-' || match_number, scope,
      'b3300000-0000-0000-0000-000000000003', 1, 1, 'draw', false
    );
  end loop;
end;
$$;
select pg_temp.apply_v3_match(
  'b3200000-0000-0000-0000-000000000003',
  'b3600000-0000-0000-0000-000000000001', 'global-match-25',
  'internal', null, 1, 1, 'draw', true
);
select pg_temp.assert_true(
  (select matches_played from public.pachanga_team_progression_stats
   where group_id = 'b3200000-0000-0000-0000-000000000003'
     and match_scope = 'all') = 25,
  'Global team matches must combine 17 internal, 7 Retos and the next match'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.origin_match_fact_id = (select fact_id from v3_facts where label = 'global-match-25')
     and definitions.achievement_key = 'team.matches.025') = 1,
  'The 25th global match must create one trajectory grant only'
);

select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-e1', 'external', 'b3300000-0000-0000-0000-000000000004', 2, 1, 'win', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-i1', 'internal', null, 0, 1, 'loss', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-e2', 'external', 'b3300000-0000-0000-0000-000000000005', 2, 1, 'win', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-i2', 'internal', null, 1, 1, 'draw', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-e3', 'external', 'b3300000-0000-0000-0000-000000000006', 2, 1, 'win', false);
select pg_temp.assert_true(
  (select current_win_streak = 3 and current_unbeaten_streak = 3
   from public.pachanga_team_progression_stats
   where group_id = 'b3200000-0000-0000-0000-000000000004'
     and match_scope = 'external'),
  'Internal losses and draws must not alter competitive Reto streaks'
);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-e4', 'external', 'b3300000-0000-0000-0000-000000000007', 1, 1, 'draw', false);
select pg_temp.assert_true(
  (select current_win_streak = 0 and current_unbeaten_streak = 4
   from public.pachanga_team_progression_stats
   where group_id = 'b3200000-0000-0000-0000-000000000004'
     and match_scope = 'external'),
  'A Reto draw must break the winning streak but preserve unbeaten'
);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000004', 'b3600000-0000-0000-0000-000000000001', 'streak-e5', 'external', 'b3300000-0000-0000-0000-000000000008', 0, 1, 'loss', false);
select pg_temp.assert_true(
  (select current_win_streak = 0 and current_unbeaten_streak = 0
     and max_win_streak = 3 and max_unbeaten_streak = 4
   from public.pachanga_team_progression_stats
   where group_id = 'b3200000-0000-0000-0000-000000000004'
     and match_scope = 'external'),
  'A Reto loss must reset both current competitive streaks'
);

select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000005', 'b3600000-0000-0000-0000-000000000001', 'unique-a1', 'external', 'b3300000-0000-0000-0000-000000000009', 2, 1, 'win', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000005', 'b3600000-0000-0000-0000-000000000001', 'unique-a2', 'external', 'b3300000-0000-0000-0000-000000000009', 2, 1, 'win', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000005', 'b3600000-0000-0000-0000-000000000001', 'unique-a3', 'external', 'b3300000-0000-0000-0000-000000000009', 1, 1, 'draw', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000005', 'b3600000-0000-0000-0000-000000000001', 'unique-b', 'external', 'b3300000-0000-0000-0000-000000000010', 2, 1, 'win', false);
select pg_temp.apply_v3_match('b3200000-0000-0000-0000-000000000005', 'b3600000-0000-0000-0000-000000000001', 'unique-c', 'external', 'b3300000-0000-0000-0000-000000000011', 0, 1, 'loss', false);
select pg_temp.assert_true(
  (select distinct_opponents = 3 and distinct_opponents_won = 2
   from public.pachanga_team_progression_stats
   where group_id = 'b3200000-0000-0000-0000-000000000005'
     and match_scope = 'external'),
  'Repeated Retos must count three distinct rivals and two distinct beaten rivals'
);

select private.pachanga_revoke_match_progression_v1(
  (select fact_id from v3_facts where label = 'v3-goals-09'),
  'catalog_v3_correction_test'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_reward_recipients
    where match_fact_id = (select fact_id from v3_facts where label = 'v3-goals-09')
      and status <> 'revoked'
  ),
  'Correction must revoke every component box without deleting evidence'
);

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_player_profiles profiles
    cross join v3_rating_before before
    where profiles.id = 'b3600000-0000-0000-0000-000000000001'
      and (profiles.current_overall is distinct from before.current_overall
        or profiles.calibrated_overall is distinct from before.calibrated_overall
        or profiles.current_facets is distinct from before.current_facets
        or profiles.rating_reliability is distinct from before.rating_reliability
        or profiles.rating_engine_version is distinct from before.rating_engine_version)
  ),
  'Achievement V1.1 must leave every Rating V2 field untouched'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b3100000-0000-0000-0000-000000000002', true);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_reward_recipients) = 0,
  'RLS must hide every reward component from an unrelated authenticated user'
);
reset role;

rollback;
