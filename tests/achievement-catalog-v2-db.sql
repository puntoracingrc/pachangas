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

create or replace function pg_temp.apply_catalog_match(
  target_group_id uuid,
  target_profile_id uuid,
  target_source_id text,
  target_opponent_id uuid,
  target_played_at timestamptz,
  target_goals_for integer,
  target_goals_against integer,
  target_outcome text,
  target_player_goals integer,
  target_canonical_state text default 'confirmed',
  target_server_sequence bigint default null
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
    'external_result', target_source_id, 1, target_group_id, target_opponent_id,
    'external', target_outcome, target_goals_for, target_goals_against,
    target_goals_against = 0,
    target_outcome = 'win' and target_goals_for - target_goals_against = 1,
    target_outcome = 'win' and target_goals_for - target_goals_against >= 4,
    target_goals_for = 0 and target_goals_against = 0, true,
    jsonb_build_object('canonicalState', target_canonical_state), 'active',
    coalesce(target_server_sequence, nextval('public.pachanga_progression_sequence')),
    target_played_at
  ) returning id into saved_fact_id;

  insert into public.pachanga_progression_player_match_facts(
    match_fact_id, group_id, player_profile_id, local_player_id,
    team_side, outcome, goals, card_snapshot
  ) values (
    saved_fact_id, target_group_id, target_profile_id, 'catalog-player',
    'team', target_outcome, target_player_goals,
    '{"currentOverall":67,"engineVersion":"pachangas-rating-v2"}'::jsonb
  );
  perform private.pachanga_rebuild_player_progression_stats_v1(
    target_profile_id, 'external'
  );
  perform private.pachanga_rebuild_team_progression_stats_v1(
    target_group_id, 'external'
  );
  perform private.pachanga_evaluate_achievements_v1(
    target_group_id, 'external', saved_fact_id
  );
  return saved_fact_id;
end;
$$;

insert into auth.users(id, email) values
  ('a1100000-0000-0000-0000-000000000001', 'catalog-owner@example.test'),
  ('a1100000-0000-0000-0000-000000000002', 'catalog-legacy@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values
  ('a1200000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
    'Equipo Catálogo', 'CATV2001', '{"players":[]}'::jsonb),
  ('a1200000-0000-0000-0000-000000000002', 'a1100000-0000-0000-0000-000000000002',
    'Equipo Previo', 'CATV2002', '{"players":[]}'::jsonb);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select ('a1300000-0000-0000-0000-' || lpad(value::text, 12, '0'))::uuid,
  'a1100000-0000-0000-0000-000000000001', 'Rival ' || value::text,
  'RIV' || lpad(value::text, 5, '0'), '{"players":[]}'::jsonb
from generate_series(1, 50) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values
  ('a1200000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001', 'owner', 'Catalog Player'),
  ('a1200000-0000-0000-0000-000000000002', 'a1100000-0000-0000-0000-000000000002', 'owner', 'Legacy Player');

insert into public.pachanga_player_profiles(
  id, user_id, display_name, position, current_overall, base_overall,
  calibrated_overall, current_facets, rating_reliability, rating_engine_version
) values
  ('a1600000-0000-0000-0000-000000000001', 'a1100000-0000-0000-0000-000000000001',
    'Catalog Player', 'DEL', 67, 66, 67,
    '{"pace":67,"shooting":67,"passing":67,"dribbling":67,"defending":67,"physical":67}',
    80, 'pachangas-rating-v2'),
  ('a1600000-0000-0000-0000-000000000002', 'a1100000-0000-0000-0000-000000000002',
    'Legacy Player', 'MC', 64, 63, 64,
    '{"pace":64,"shooting":64,"passing":64,"dribbling":64,"defending":64,"physical":64}',
    75, 'pachangas-rating-v2');

create temporary table catalog_rating_before as
select id, current_overall, calibrated_overall, current_facets,
  rating_reliability, rating_engine_version
from public.pachanga_player_profiles
where id in (
  'a1600000-0000-0000-0000-000000000001',
  'a1600000-0000-0000-0000-000000000002'
);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_definitions
   where active and catalog_key = 'achievement_catalog_v2'
     and subject_type = 'player') = 45,
  'The integrated catalog must preserve all 45 active individual V2 definitions'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_definitions
   where active and catalog_key = 'achievement_catalog_v3'
     and subject_type = 'team') = 60,
  'The integrated catalog must expose all 60 active collective V3 definitions'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_definitions
    where active and subject_type = 'player'
      and (reward_kind <> 'none' or reward_key is not null or box_rarity is not null)
  ),
  'Individual achievements must never contain rewards or boxes'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_definitions definitions
    left join public.pachanga_achievement_box_rules rules
      on rules.economy_version = definitions.reward_pool_version
     and rules.achievement_key = definitions.achievement_key
     and rules.achievement_version = definitions.version
     and rules.active
    where definitions.active and definitions.subject_type = 'team'
      and (definitions.box_rarity is null or definitions.animation_key is null
        or definitions.presentation_key is null or rules.achievement_key is null)
  ),
  'Every collective achievement must resolve to a versioned box rule'
);

-- A pre-activation fact updates history but cannot create retroactive grants or boxes.
select pg_temp.apply_catalog_match(
  'a1200000-0000-0000-0000-000000000002',
  'a1600000-0000-0000-0000-000000000002', 'catalog-pre-activation',
  'a1300000-0000-0000-0000-000000000001', '2025-01-01T20:00:00Z',
  0, 1, 'loss', 0, 'confirmed',
  (select min(activation_server_sequence) - 1
   from public.pachanga_achievement_definitions where active)
) as pre_activation_fact \gset
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_achievement_grants
    where group_id = 'a1200000-0000-0000-0000-000000000002'
  ),
  'Pre-activation history must not create retroactive achievements'
);

do $$
declare
  match_number integer;
  goals_for integer;
  goals_against integer;
  player_goals integer;
  outcome text;
  opponent_id uuid;
begin
  for match_number in 1..500 loop
    opponent_id := ('a1300000-0000-0000-0000-'
      || lpad((((match_number - 1) % 50) + 1)::text, 12, '0'))::uuid;
    if match_number = 1 then
      goals_for := 0; goals_against := 0; player_goals := 0; outcome := 'draw';
    elsif match_number = 2 then
      goals_for := 5; goals_against := 0; player_goals := 3; outcome := 'win';
    elsif match_number = 3 then
      goals_for := 3; goals_against := 2; player_goals := 3; outcome := 'win';
    elsif match_number = 4 then
      goals_for := 4; goals_against := 1; player_goals := 4; outcome := 'win';
    elsif match_number = 5 then
      goals_for := 5; goals_against := 1; player_goals := 5; outcome := 'win';
    elsif match_number = 6 then
      goals_for := 6; goals_against := 1; player_goals := 6; outcome := 'win';
    elsif match_number <= 251 then
      goals_for := 2; goals_against := 1; player_goals := 2; outcome := 'win';
    else
      goals_for := 0; goals_against := 1; player_goals := 0; outcome := 'loss';
    end if;

    perform pg_temp.apply_catalog_match(
      'a1200000-0000-0000-0000-000000000001',
      'a1600000-0000-0000-0000-000000000001',
      'catalog-match-' || lpad(match_number::text, 3, '0'), opponent_id,
      '2026-01-01T20:00:00Z'::timestamptz + make_interval(days => match_number),
      goals_for, goals_against, outcome, player_goals
    );
  end loop;
end;
$$;

select pg_temp.assert_true(
  (select appearances = 500 and wins = 250 and goals = 511
     and max_win_streak = 250 and max_unbeaten_streak = 251
     and distinct_opponents = 50 and distinct_opponents_won = 50
   from public.pachanga_player_progression_stats
   where player_profile_id = 'a1600000-0000-0000-0000-000000000001'
     and match_scope = 'all'),
  'Global player statistics must be canonical across all confirmed matches'
);
select pg_temp.assert_true(
  (select matches_played = 500 and wins = 250
     and max_win_streak = 250 and max_unbeaten_streak = 251
     and distinct_opponents = 50 and distinct_opponents_won = 50
   from public.pachanga_team_progression_stats
   where group_id = 'a1200000-0000-0000-0000-000000000001'
     and match_scope = 'external'),
  'Team statistics must retain streaks and unique opponent counts'
);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_id = 'a1600000-0000-0000-0000-000000000001'
     and grants.state = 'active'
     and definitions.family_key in ('player.matches', 'player.wins', 'player.goals',
       'player.win_streak', 'player.unbeaten', 'player.opponents_played',
       'player.opponents_won')
     and not definitions.repeatable) = 40,
  'All 40 cumulative individual milestones must unlock at their thresholds'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where grants.subject_id = 'a1600000-0000-0000-0000-000000000001'
     and grants.state = 'active'
     and definitions.family_key = 'player.match_goals') = 250,
  'Exactly one personal scoring tier must be recorded for each scoring match'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.subject_type = 'player'
      and definitions.family_key = 'player.match_goals'
    group by grants.origin_match_fact_id, grants.subject_id
    having count(*) > 1
  ),
  'A player match may never unlock more than its highest scoring tier'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.subject_type = 'team'
      and definitions.category = 'match_goals'
    group by grants.origin_match_fact_id
    having count(*) > 1
  ),
  'A team match may never unlock more than its highest collective goal tier'
);

select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    join public.pachanga_progression_match_facts facts
      on facts.id = grants.origin_match_fact_id
    where facts.source_match_id = 'catalog-match-001'
      and definitions.achievement_key = 'team.external.clean_sheets.001'
  ),
  'A canonical 0-0 must unlock the collective clean sheet'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_achievement_grants grants
   join public.pachanga_progression_match_facts facts
     on facts.id = grants.origin_match_fact_id
   join public.pachanga_achievement_definitions definitions
     on definitions.id = grants.definition_id
   where facts.source_match_id = 'catalog-match-002'
     and grants.subject_type = 'team'
     and definitions.achievement_key in (
       'team.external.wins.001', 'team.external.match_goals.005',
       'team.external.clean_sheets.001', 'team.external.big_wins.001'
     )) = 4,
  'The first 5-0 after a prior draw must create four expected collective rewards'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    join public.pachanga_progression_match_facts facts
      on facts.id = grants.origin_match_fact_id
    where facts.source_match_id = 'catalog-match-002'
      and definitions.achievement_key = 'player.all.hat_tricks.001'
      and grants.occurrence_metadata ->> 'displayTitle' = 'Primer hat-trick'
  ) and exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    join public.pachanga_progression_match_facts facts
      on facts.id = grants.origin_match_fact_id
    where facts.source_match_id = 'catalog-match-003'
      and definitions.achievement_key = 'player.all.hat_tricks.001'
      and grants.occurrence_metadata ->> 'displayTitle' = 'Hat-trick'
      and grants.sequence_count = 2
  ),
  'First and repeated scoring occurrences must retain distinct titles and counters'
);

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_reward_grants rewards
    join public.pachanga_achievement_grants grants
      on grants.id = rewards.achievement_grant_id
    where grants.subject_type = 'player'
  ),
  'No personal recognition may create a reward grant'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_reward_recipients recipients
    join public.pachanga_progression_player_match_facts player_facts
      on player_facts.match_fact_id = recipients.match_fact_id
     and player_facts.player_profile_id = recipients.player_profile_id
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = recipients.match_fact_id
     and match_facts.group_id = 'a1200000-0000-0000-0000-000000000001'
    where recipients.user_id <> 'a1100000-0000-0000-0000-000000000001'
  ),
  'Only canonical participants may receive collective boxes'
);

-- Re-evaluation is idempotent.
select count(*) as grants_before_replay from public.pachanga_achievement_grants \gset
select private.pachanga_evaluate_achievements_v1(
  'a1200000-0000-0000-0000-000000000001', 'external',
  (select id from public.pachanga_progression_match_facts
   where source_match_id = 'catalog-match-002')
) as replay_awarded \gset
select pg_temp.assert_true(
  :'replay_awarded'::integer = 0
    and (select count(*) from public.pachanga_achievement_grants) = :'grants_before_replay'::integer,
  'Replaying one canonical fact must not duplicate achievements'
);

-- Corrections revoke invalid pending rewards and recompute cumulative state.
select private.pachanga_revoke_match_progression_v1(
  (select id from public.pachanga_progression_match_facts
   where source_match_id = 'catalog-match-251'),
  'catalog_v2_correction_test'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where definitions.achievement_key = 'team.external.wins.250'
      and grants.subject_id = 'a1200000-0000-0000-0000-000000000001'
      and grants.state = 'revoked'
  ),
  'Removing the 250th victory must revoke the now-invalid milestone evidence'
);

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_player_profiles profiles
    join catalog_rating_before before on before.id = profiles.id
    where profiles.current_overall is distinct from before.current_overall
      or profiles.calibrated_overall is distinct from before.calibrated_overall
      or profiles.current_facets is distinct from before.current_facets
      or profiles.rating_reliability is distinct from before.rating_reliability
      or profiles.rating_engine_version is distinct from before.rating_engine_version
  ),
  'Achievement progression must leave every Rating V2 field untouched'
);

rollback;
