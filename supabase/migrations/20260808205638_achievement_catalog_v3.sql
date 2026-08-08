-- Pachangas IQ achievement catalog V1.1, stored as collective catalog V3.
-- Forward-only: individual V2 definitions and every historical grant remain intact.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_achievement_definitions
  add column if not exists reward_components jsonb not null default '[]'::jsonb;

alter table public.pachanga_achievement_definitions
  drop constraint if exists pachanga_achievement_definitions_reward_components_check;
alter table public.pachanga_achievement_definitions
  add constraint pachanga_achievement_definitions_reward_components_check
  check (jsonb_typeof(reward_components) = 'array');

alter table public.pachanga_team_progression_stats
  drop constraint if exists pachanga_team_progression_stats_match_scope_check;
alter table public.pachanga_team_progression_stats
  add constraint pachanga_team_progression_stats_match_scope_check
  check (match_scope in ('all', 'internal', 'external'));

alter table public.pachanga_reward_recipients
  add column if not exists component_index integer not null default 0,
  add column if not exists reward_component_key text,
  add column if not exists reward_component jsonb;

alter table public.pachanga_reward_recipients
  drop constraint if exists pachanga_reward_recipients_component_index_check,
  drop constraint if exists pachanga_reward_recipients_component_key_check,
  drop constraint if exists pachanga_reward_recipients_component_check;
alter table public.pachanga_reward_recipients
  add constraint pachanga_reward_recipients_component_index_check
    check (component_index >= 0),
  add constraint pachanga_reward_recipients_component_key_check
    check (reward_component_key is null or char_length(reward_component_key) between 2 and 80),
  add constraint pachanga_reward_recipients_component_check
    check (reward_component is null or jsonb_typeof(reward_component) = 'object');

drop index if exists public.pachanga_reward_recipients_achievement_user_idx;
alter table public.pachanga_reward_recipients
  drop constraint if exists pachanga_reward_recipients_pkey;
alter table public.pachanga_reward_recipients
  add constraint pachanga_reward_recipients_pkey
  primary key (reward_grant_id, user_id, component_index);
create unique index pachanga_reward_recipients_achievement_user_component_idx
  on public.pachanga_reward_recipients(
    achievement_grant_id, user_id, component_index
  );

create or replace function private.pachanga_goal_reward_components_v3(
  target_goals integer
)
returns jsonb
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  remaining integer := target_goals;
  components jsonb := '[]'::jsonb;
begin
  if target_goals < 2 then return components; end if;

  while remaining > 10 loop
    if remaining % 10 = 1 then
      components := components
        || jsonb_build_array(jsonb_build_object(
          'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
        ))
        || jsonb_build_array(jsonb_build_object(
          'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
        ))
        || jsonb_build_array(jsonb_build_object(
          'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
        ));
      remaining := remaining - 11;
    else
      components := components
        || jsonb_build_array(jsonb_build_object(
          'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
        ))
        || jsonb_build_array(jsonb_build_object(
          'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
        ));
      remaining := remaining - 10;
    end if;
  end loop;

  if remaining = 2 then
    components := components || jsonb_build_array(jsonb_build_object(
      'key', 'doblete', 'label', 'Doblete', 'goals', 2, 'boxRarity', 'common'
    ));
  elsif remaining = 3 then
    components := components || jsonb_build_array(jsonb_build_object(
      'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
    ));
  elsif remaining = 4 then
    components := components || jsonb_build_array(jsonb_build_object(
      'key', 'poker', 'label', 'Póker', 'goals', 4, 'boxRarity', 'uncommon'
    ));
  elsif remaining = 5 then
    components := components || jsonb_build_array(jsonb_build_object(
      'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
    ));
  elsif remaining = 6 then
    components := components
      || jsonb_build_array(jsonb_build_object(
        'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
      ));
  elsif remaining = 7 then
    components := components
      || jsonb_build_array(jsonb_build_object(
        'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'doblete', 'label', 'Doblete', 'goals', 2, 'boxRarity', 'common'
      ));
  elsif remaining = 8 then
    components := components
      || jsonb_build_array(jsonb_build_object(
        'key', 'poker', 'label', 'Póker', 'goals', 4, 'boxRarity', 'uncommon'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'poker', 'label', 'Póker', 'goals', 4, 'boxRarity', 'uncommon'
      ));
  elsif remaining = 9 then
    components := components
      || jsonb_build_array(jsonb_build_object(
        'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'hat_trick', 'label', 'Hat-trick', 'goals', 3, 'boxRarity', 'uncommon'
      ));
  elsif remaining = 10 then
    components := components
      || jsonb_build_array(jsonb_build_object(
        'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
      ))
      || jsonb_build_array(jsonb_build_object(
        'key', 'manita', 'label', 'Manita', 'goals', 5, 'boxRarity', 'rare'
      ));
  end if;
  return components;
end;
$$;

create or replace function private.pachanga_achievement_reward_components_v3(
  target_definition_id uuid,
  target_metric_value integer
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select case
    when definitions.parameters ->> 'ruleKind' = 'team_match_goals'
      then private.pachanga_goal_reward_components_v3(target_metric_value)
    when jsonb_array_length(definitions.reward_components) > 0
      then definitions.reward_components
    else jsonb_build_array(jsonb_build_object(
      'key', definitions.family_key,
      'label', definitions.title,
      'goals', null,
      'boxRarity', coalesce(definitions.box_rarity, definitions.rarity)
    ))
  end
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id;
$$;

-- V2 individual achievements stay active and unchanged. V2 collective rows
-- remain auditable but stop producing future grants.
update public.pachanga_achievement_definitions
set active = false,
    catalog_disposition = case
      when family_key in ('team.internal.matches', 'team.external.matches')
        then 'DEPRECATE'
      else 'MIGRATE'
    end
where catalog_key = 'achievement_catalog_v2'
  and subject_type = 'team'
  and active;

with milestones(threshold, title, rarity, priority) as (
  values
    (1, 'Primer partido', 'common', 11),
    (5, 'Cinco partidos', 'uncommon', 15),
    (10, 'Diez partidos', 'uncommon', 20),
    (25, 'Veinticinco partidos', 'rare', 35),
    (50, 'Cincuenta partidos', 'rare', 60),
    (100, 'Cien partidos', 'epic', 110),
    (250, 'Doscientos cincuenta partidos', 'epic', 260),
    (500, 'Quinientos partidos', 'legendary', 510)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition, reward_components
)
select 'team.matches.' || lpad(threshold::text, 3, '0'), 3, title,
  'Completa ' || threshold::text || ' partidos canónicos entre Pachangas y Retos.',
  'team', 'all', 'matches', 'TEAM_MATCHES', '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v3', 'team.matches', priority,
  'matches', rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE',
  jsonb_build_array(jsonb_build_object(
    'key', 'team_matches_' || threshold::text, 'label', title,
    'boxRarity', rarity
  ))
from milestones;

with milestones(threshold, title, rarity, repeatable, parameters) as (
  values
    (1, 'Victoria', 'common', true,
      '{"ruleKind":"team_match_win","firstTitle":"Primera conquista","repeatTitle":"Victoria"}'::jsonb),
    (5, 'Cinco victorias', 'uncommon', false, '{}'::jsonb),
    (10, 'Diez victorias', 'uncommon', false, '{}'::jsonb),
    (25, 'Veinticinco victorias', 'rare', false, '{}'::jsonb),
    (50, 'Cincuenta victorias', 'rare', false, '{}'::jsonb),
    (100, 'Cien victorias', 'epic', false, '{}'::jsonb),
    (250, 'Doscientas cincuenta victorias', 'legendary', false, '{}'::jsonb)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  first_time_variant, box_rarity, reward_pool_version, animation_key,
  presentation_key, activation_server_sequence, catalog_disposition,
  reward_components
)
select 'team.external.wins.' || lpad(threshold::text, 3, '0'), 3, title,
  case when threshold = 1 then 'Gana un Reto contra otro equipo.'
    else 'Alcanza ' || threshold::text || ' victorias en Retos.' end,
  'team', 'external', 'wins', 'TEAM_WINS', parameters, threshold, rarity,
  repeatable, 'none', true, 'achievement_catalog_v3', 'team.external.wins',
  20 + threshold, 'victory', case when threshold = 1 then 'Primera conquista' end,
  rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE',
  jsonb_build_array(jsonb_build_object(
    'key', 'victoria_reto', 'label', 'Victoria', 'boxRarity', rarity
  ))
from milestones;

with scopes(scope) as (values ('internal'), ('external')),
tiers(goals, title, rarity, priority) as (
  values
    (2, 'Doblete', 'common', 39),
    (3, 'Hat-trick', 'uncommon', 38),
    (4, 'Póker', 'uncommon', 37),
    (5, 'Manita', 'rare', 36),
    (6, 'Doble hat-trick', 'uncommon', 35),
    (7, '7 goles', 'rare', 34),
    (8, 'Doble póker', 'uncommon', 33),
    (9, 'Triple hat-trick', 'uncommon', 32),
    (10, 'Doble manita', 'rare', 31),
    (11, '11 o más goles', 'epic', 30)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition, reward_components
)
select 'team.' || scope || '.match_goals.' || lpad(goals::text, 3, '0'),
  3, title,
  case when goals = 11 then 'El equipo marca once o más goles; las cajas representan exactamente el total.'
    else 'El equipo marca exactamente ' || goals::text || ' goles en un partido confirmado.' end,
  'team', scope, 'match_goals', 'TEAM_GOALS',
  case when goals = 11
    then jsonb_build_object('ruleKind', 'team_match_goals', 'goalsMinimum', goals)
    else jsonb_build_object('ruleKind', 'team_match_goals', 'goalsExact', goals) end,
  goals, rarity, true, 'none', true, 'achievement_catalog_v3',
  'team.' || scope || '.match_goals', priority, 'team_goals', rarity, 1,
  'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE',
  case when goals = 11 then '[]'::jsonb
    else private.pachanga_goal_reward_components_v3(goals) end
from scopes cross join tiers;

insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  first_time_variant, box_rarity, reward_pool_version, animation_key,
  presentation_key, activation_server_sequence, catalog_disposition,
  reward_components
)
values
  ('team.external.clean_sheets.001', 3, 'Portería a cero', 'El rival no marca; también cuenta un empate 0-0.', 'team', 'external', 'special', 'TEAM_CLEAN_SHEETS', '{"ruleKind":"team_match_clean_sheet","firstTitle":"Primera portería a cero","repeatTitle":"Portería a cero"}', 1, 'common', true, 'none', true, 'achievement_catalog_v3', 'team.external.clean_sheets', 41, 'clean_sheet', 'Primera portería a cero', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE', '[{"key":"porteria_cero","label":"Portería a cero","boxRarity":"common"}]'),
  ('team.external.big_wins.001', 3, 'Goleada', 'Gana un Reto por cuatro o más goles de diferencia.', 'team', 'external', 'special', 'TEAM_BIG_WINS', '{"ruleKind":"team_match_big_win","firstTitle":"Primera goleada","repeatTitle":"Goleada","goalDifferenceMinimum":4}', 1, 'uncommon', true, 'none', true, 'achievement_catalog_v3', 'team.external.big_wins', 42, 'team_goals', 'Primera goleada', 'uncommon', 1, 'reward_box_blue', 'box.uncommon', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE', '[{"key":"goleada","label":"Goleada","boxRarity":"uncommon"}]'),
  ('team.external.close_wins.001', 3, 'Por la mínima', 'Gana un Reto por exactamente un gol de diferencia.', 'team', 'external', 'special', 'TEAM_CLOSE_WINS', '{"ruleKind":"team_match_close_win","firstTitle":"Primera victoria por la mínima","repeatTitle":"Por la mínima"}', 1, 'common', true, 'none', true, 'achievement_catalog_v3', 'team.external.close_wins', 43, 'victory', 'Primera victoria por la mínima', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE', '[{"key":"por_la_minima","label":"Por la mínima","boxRarity":"common"}]'),
  ('team.external.absolute_dominance.001', 3, 'Dominio absoluto', 'Gana un Reto por cuatro o más goles de diferencia sin encajar.', 'team', 'external', 'special', 'TEAM_BIG_WINS', '{"ruleKind":"team_match_absolute_dominance","firstTitle":"Primer dominio absoluto","repeatTitle":"Dominio absoluto","goalDifferenceMinimum":4}', 1, 'rare', true, 'none', true, 'achievement_catalog_v3', 'team.external.absolute_dominance', 44, 'team_goals', 'Primer dominio absoluto', 'rare', 1, 'reward_box_blue', 'box.rare', (select last_value + 1 from public.pachanga_progression_sequence), 'KEEP', '[{"key":"dominio_absoluto","label":"Dominio absoluto","boxRarity":"rare"}]'),
  ('team.internal.big_wins.001', 3, 'Partido desatado', 'El partido interno termina con cuatro o más goles de diferencia.', 'team', 'internal', 'special', 'TEAM_BIG_WINS', '{"ruleKind":"team_match_big_win","firstTitle":"Primer partido desatado","repeatTitle":"Partido desatado","goalDifferenceMinimum":4}', 1, 'uncommon', true, 'none', true, 'achievement_catalog_v3', 'team.internal.big_wins', 45, 'team_goals', 'Primer partido desatado', 'uncommon', 1, 'reward_box_blue', 'box.uncommon', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE', '[{"key":"partido_desatado","label":"Partido desatado","boxRarity":"uncommon"}]'),
  ('team.internal.close_wins.001', 3, 'Hasta el final', 'El partido interno se decide por exactamente un gol.', 'team', 'internal', 'special', 'TEAM_CLOSE_WINS', '{"ruleKind":"team_match_close_win","firstTitle":"Primer final ajustado","repeatTitle":"Hasta el final"}', 1, 'common', true, 'none', true, 'achievement_catalog_v3', 'team.internal.close_wins', 46, 'victory', 'Primer final ajustado', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE', '[{"key":"hasta_el_final","label":"Hasta el final","boxRarity":"common"}]');

with streaks(evaluator, family_key, threshold, title, rarity, priority, icon_key) as (
  values
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 3, 'Tres victorias seguidas', 'uncommon', 61, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 5, 'Cinco victorias seguidas', 'rare', 62, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 10, 'Diez victorias seguidas', 'epic', 63, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 15, 'Quince victorias seguidas', 'legendary', 64, 'winning_streak'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 3, 'Tres Retos sin perder', 'common', 65, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 5, 'Cinco Retos sin perder', 'uncommon', 66, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 10, 'Diez Retos sin perder', 'rare', 67, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 20, 'Veinte Retos sin perder', 'legendary', 68, 'unbeaten')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition, reward_components
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 3, title,
  case when evaluator = 'TEAM_MAX_WIN_STREAK'
    then 'Encadena ' || threshold::text || ' victorias en Retos.'
    else 'Encadena ' || threshold::text || ' Retos sin perder.' end,
  'team', 'external', 'streak', evaluator, '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v3', family_key, priority,
  icon_key, rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE',
  jsonb_build_array(jsonb_build_object(
    'key', replace(family_key, '.', '_') || '_' || threshold::text,
    'label', title, 'boxRarity', rarity
  ))
from streaks;

with rivals(evaluator, family_key, threshold, title, rarity, priority) as (
  values
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 3, 'Tres rivales', 'common', 71),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 5, 'Cinco rivales', 'common', 72),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 10, 'Diez rivales', 'uncommon', 73),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 25, 'Veinticinco rivales', 'rare', 74),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 50, 'Cincuenta rivales', 'epic', 75),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 100, 'Cien rivales', 'epic', 76),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 3, 'Tres rivales vencidos', 'uncommon', 77),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 5, 'Cinco rivales vencidos', 'uncommon', 78),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 10, 'Diez rivales vencidos', 'rare', 79),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 25, 'Veinticinco rivales vencidos', 'epic', 80),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 50, 'Cincuenta rivales vencidos', 'legendary', 81)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition, reward_components
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 3, title,
  case when evaluator = 'TEAM_DISTINCT_OPPONENTS'
    then 'Disputa Retos contra ' || threshold::text || ' equipos rivales distintos.'
    else 'Vence en Retos a ' || threshold::text || ' equipos rivales distintos.' end,
  'team', 'external', 'opponents', evaluator, '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v3', family_key, priority,
  'rivals', rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE',
  jsonb_build_array(jsonb_build_object(
    'key', replace(family_key, '.', '_') || '_' || threshold::text,
    'label', title, 'boxRarity', rarity
  ))
from rivals;

insert into public.pachanga_achievement_box_rules(
  economy_version, achievement_key, achievement_version,
  first_box_type, repeat_box_type, active
)
select 1, definitions.achievement_key, definitions.version,
  case definitions.box_rarity
    when 'common' then 'collective.uncommon'
    when 'uncommon' then 'collective.rare'
    when 'rare' then 'collective.epic'
    when 'epic' then 'collective.legendary'
    else 'collective.legendary' end,
  'collective.' || definitions.box_rarity, true
from public.pachanga_achievement_definitions definitions
where definitions.active
  and definitions.catalog_key = 'achievement_catalog_v3'
  and definitions.subject_type = 'team';

create or replace function private.pachanga_upsert_team_progression_scope_v3(
  target_group_id uuid,
  target_match_scope text
)
returns public.pachanga_team_progression_stats
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  aggregates record;
  fact record;
  current_wins integer := 0;
  max_wins integer := 0;
  current_unbeaten integer := 0;
  max_unbeaten integer := 0;
  saved public.pachanga_team_progression_stats%rowtype;
begin
  if target_match_scope not in ('all', 'internal', 'external') then
    raise exception 'Invalid progression scope';
  end if;

  select count(*)::integer as matches_played,
    count(*) filter (where facts.outcome = 'win')::integer as wins,
    count(*) filter (where facts.outcome = 'draw')::integer as draws,
    count(*) filter (where facts.outcome = 'loss')::integer as losses,
    coalesce(sum(facts.goals_for), 0)::integer as goals_for,
    coalesce(sum(facts.goals_against), 0)::integer as goals_against,
    count(*) filter (where facts.clean_sheet)::integer as clean_sheets,
    count(*) filter (where facts.close_win)::integer as close_wins,
    count(*) filter (where facts.big_win)::integer as big_wins,
    count(*) filter (where facts.scoreless_draw)::integer as scoreless_draws,
    count(distinct facts.opponent_group_id)
      filter (where facts.opponent_group_id is not null)::integer as distinct_opponents,
    count(distinct facts.opponent_group_id)
      filter (where facts.opponent_group_id is not null and facts.outcome = 'win')::integer
      as distinct_opponents_won
  into aggregates
  from public.pachanga_progression_match_facts facts
  where facts.group_id = target_group_id
    and (target_match_scope = 'all' or facts.match_scope = target_match_scope)
    and facts.state = 'active';

  if target_match_scope = 'external' then
    for fact in
      select facts.outcome
      from public.pachanga_progression_match_facts facts
      where facts.group_id = target_group_id
        and facts.match_scope = 'external'
        and facts.state = 'active'
      order by facts.played_at, facts.server_sequence, facts.id
    loop
      if fact.outcome = 'win' then
        current_wins := current_wins + 1;
        current_unbeaten := current_unbeaten + 1;
      elsif fact.outcome = 'draw' then
        current_wins := 0;
        current_unbeaten := current_unbeaten + 1;
      else
        current_wins := 0;
        current_unbeaten := 0;
      end if;
      max_wins := greatest(max_wins, current_wins);
      max_unbeaten := greatest(max_unbeaten, current_unbeaten);
    end loop;
  end if;

  insert into public.pachanga_team_progression_stats(
    group_id, match_scope, matches_played, wins, draws, losses,
    goals_for, goals_against, clean_sheets, close_wins, big_wins,
    scoreless_draws, distinct_opponents, distinct_opponents_won,
    current_win_streak, max_win_streak, current_unbeaten_streak,
    max_unbeaten_streak
  ) values (
    target_group_id, target_match_scope, aggregates.matches_played,
    aggregates.wins, aggregates.draws, aggregates.losses,
    aggregates.goals_for, aggregates.goals_against, aggregates.clean_sheets,
    aggregates.close_wins, aggregates.big_wins, aggregates.scoreless_draws,
    aggregates.distinct_opponents, aggregates.distinct_opponents_won,
    current_wins, max_wins, current_unbeaten, max_unbeaten
  ) on conflict (group_id, match_scope) do update set
    matches_played = excluded.matches_played,
    wins = excluded.wins, draws = excluded.draws, losses = excluded.losses,
    goals_for = excluded.goals_for, goals_against = excluded.goals_against,
    clean_sheets = excluded.clean_sheets, close_wins = excluded.close_wins,
    big_wins = excluded.big_wins, scoreless_draws = excluded.scoreless_draws,
    distinct_opponents = excluded.distinct_opponents,
    distinct_opponents_won = excluded.distinct_opponents_won,
    current_win_streak = excluded.current_win_streak,
    max_win_streak = excluded.max_win_streak,
    current_unbeaten_streak = excluded.current_unbeaten_streak,
    max_unbeaten_streak = excluded.max_unbeaten_streak,
    revision = public.pachanga_team_progression_stats.revision + 1,
    server_sequence = nextval('public.pachanga_progression_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;
  return saved;
end;
$$;

create or replace function private.pachanga_rebuild_team_progression_stats_v1(
  target_group_id uuid,
  target_match_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  scoped public.pachanga_team_progression_stats%rowtype;
  global_stats public.pachanga_team_progression_stats%rowtype;
begin
  if target_match_scope not in ('internal', 'external') then
    raise exception 'Invalid progression scope';
  end if;
  scoped := private.pachanga_upsert_team_progression_scope_v3(
    target_group_id, target_match_scope
  );
  global_stats := private.pachanga_upsert_team_progression_scope_v3(
    target_group_id, 'all'
  );
  perform private.pachanga_progression_bump_group_v1(
    target_group_id, greatest(scoped.server_sequence, global_stats.server_sequence)
  );
  return to_jsonb(scoped);
end;
$$;

create or replace function private.pachanga_team_metric_without_match_v3(
  target_definition_id uuid,
  target_group_id uuid,
  excluded_match_fact_id uuid
)
returns integer
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  aggregates record;
  fact record;
  current_wins integer := 0;
  max_wins integer := 0;
  current_unbeaten integer := 0;
  max_unbeaten integer := 0;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id
    and definitions.subject_type = 'team';
  if not found then return 0; end if;

  select count(*)::integer as matches_played,
    count(*) filter (where facts.outcome = 'win')::integer as wins,
    count(*) filter (where facts.outcome = 'draw')::integer as draws,
    count(*) filter (where facts.outcome = 'loss')::integer as losses,
    coalesce(sum(facts.goals_for), 0)::integer as goals_for,
    count(*) filter (where facts.clean_sheet)::integer as clean_sheets,
    count(*) filter (where facts.big_win)::integer as big_wins,
    count(*) filter (where facts.close_win)::integer as close_wins,
    count(*) filter (where facts.scoreless_draw)::integer as scoreless_draws,
    count(distinct facts.opponent_group_id)
      filter (where facts.opponent_group_id is not null)::integer as distinct_opponents,
    count(distinct facts.opponent_group_id)
      filter (where facts.opponent_group_id is not null and facts.outcome = 'win')::integer
      as distinct_opponents_won
  into aggregates
  from public.pachanga_progression_match_facts facts
  where facts.group_id = target_group_id
    and (definition.match_scope = 'all' or facts.match_scope = definition.match_scope)
    and facts.state = 'active'
    and facts.id <> excluded_match_fact_id;

  if definition.evaluator_key in ('TEAM_MAX_WIN_STREAK', 'TEAM_MAX_UNBEATEN_STREAK') then
    for fact in
      select facts.outcome
      from public.pachanga_progression_match_facts facts
      where facts.group_id = target_group_id
        and facts.match_scope = 'external'
        and facts.state = 'active'
        and facts.id <> excluded_match_fact_id
      order by facts.played_at, facts.server_sequence, facts.id
    loop
      if fact.outcome = 'win' then
        current_wins := current_wins + 1;
        current_unbeaten := current_unbeaten + 1;
      elsif fact.outcome = 'draw' then
        current_wins := 0;
        current_unbeaten := current_unbeaten + 1;
      else
        current_wins := 0;
        current_unbeaten := 0;
      end if;
      max_wins := greatest(max_wins, current_wins);
      max_unbeaten := greatest(max_unbeaten, current_unbeaten);
    end loop;
  end if;

  return case definition.evaluator_key
    when 'TEAM_MATCHES' then aggregates.matches_played
    when 'TEAM_WINS' then aggregates.wins
    when 'TEAM_DRAWS' then aggregates.draws
    when 'TEAM_LOSSES' then aggregates.losses
    when 'TEAM_GOALS' then aggregates.goals_for
    when 'TEAM_MAX_WIN_STREAK' then max_wins
    when 'TEAM_MAX_UNBEATEN_STREAK' then max_unbeaten
    when 'TEAM_CLEAN_SHEETS' then aggregates.clean_sheets
    when 'TEAM_BIG_WINS' then aggregates.big_wins
    when 'TEAM_CLOSE_WINS' then aggregates.close_wins
    when 'TEAM_SCORELESS_DRAWS' then aggregates.scoreless_draws
    when 'TEAM_DISTINCT_OPPONENTS' then aggregates.distinct_opponents
    when 'TEAM_DISTINCT_OPPONENT_WINS' then aggregates.distinct_opponents_won
    else 0 end;
end;
$$;

create or replace function private.pachanga_repeatable_grant_still_qualifies_v2(
  target_grant_id uuid
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  source record;
  player_goals integer;
begin
  select grants.subject_type, grants.subject_id, grants.group_id,
    grants.origin_match_fact_id, definitions.parameters,
    facts.state as fact_state, facts.outcome, facts.goals_for,
    facts.goals_against, facts.clean_sheet, facts.big_win, facts.close_win
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  join public.pachanga_progression_match_facts facts
    on facts.id = grants.origin_match_fact_id
  where grants.id = target_grant_id;
  if not found or source.fact_state <> 'active' then return false; end if;

  if source.parameters ->> 'ruleKind' = 'player_match_goals' then
    select player_facts.goals into player_goals
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = source.origin_match_fact_id
      and player_facts.player_profile_id = source.subject_id
      and player_facts.group_id = source.group_id
      and player_facts.state = 'active';
    if player_goals is null then return false; end if;
    return case
      when source.parameters ? 'goalsExact'
        then player_goals = (source.parameters ->> 'goalsExact')::integer
      when source.parameters ? 'goalsMinimum'
        then player_goals >= (source.parameters ->> 'goalsMinimum')::integer
      else false end;
  end if;

  return case source.parameters ->> 'ruleKind'
    when 'team_match_win' then source.outcome = 'win'
    when 'team_match_clean_sheet' then source.clean_sheet
    when 'team_match_big_win' then source.big_win
    when 'team_match_close_win' then source.close_win
    when 'team_match_absolute_dominance' then
      source.outcome = 'win' and source.big_win and source.goals_against = 0
    when 'team_match_goals' then case
      when source.parameters ? 'goalsExact'
        then source.goals_for = (source.parameters ->> 'goalsExact')::integer
      when source.parameters ? 'goalsMinimum'
        then source.goals_for >= (source.parameters ->> 'goalsMinimum')::integer
      else false end
    else true end;
end;
$$;

create or replace function private.pachanga_reconcile_subject_achievements_v1(
  target_subject_type text,
  target_subject_id uuid,
  target_match_scope text,
  target_reason text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  grant_row record;
  metric integer;
  should_revoke boolean;
  revoked integer := 0;
begin
  for grant_row in
    select grants.id, grants.definition_id, grants.origin_match_fact_id,
      definitions.threshold, definitions.repeatable, match_facts.state as fact_state
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = grants.origin_match_fact_id
    where grants.subject_type = target_subject_type
      and grants.subject_id = target_subject_id
      and grants.state = 'active'
      and definitions.match_scope in (target_match_scope, 'all')
    order by grants.occurred_at, match_facts.server_sequence, grants.id
  loop
    if grant_row.repeatable then
      should_revoke := not private.pachanga_repeatable_grant_still_qualifies_v2(
        grant_row.id
      );
    else
      metric := private.pachanga_achievement_metric_v1(
        grant_row.definition_id, target_subject_id
      );
      should_revoke := metric < grant_row.threshold;
    end if;
    if should_revoke
      and private.pachanga_revoke_achievement_grant_v1(grant_row.id, target_reason) then
      revoked := revoked + 1;
    end if;
  end loop;
  return revoked;
end;
$$;

create or replace function private.pachanga_seal_reward_box_v1(
  target_box_id uuid,
  target_achievement_grant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  source record;
  catalog public.pachanga_reward_box_catalog%rowtype;
  pool_entry public.pachanga_reward_pool_catalog%rowtype;
  active_version integer;
  selected_box_type text;
  component_rarity text;
  total_weight integer;
  ticket integer;
  selected_points integer := 0;
  payload jsonb;
  entropy uuid := gen_random_uuid();
begin
  select contents.reward_payload into payload
  from private.pachanga_reward_box_contents contents
  where contents.box_id = target_box_id;
  if found then return payload; end if;

  select versions.version into active_version
  from public.pachanga_reward_economy_versions versions
  where versions.state = 'active'
  order by versions.version desc
  limit 1;
  if active_version is null then raise exception 'No active reward economy'; end if;

  select grants.id, grants.is_first, grants.origin_match_fact_id,
    grants.group_id, definitions.achievement_key,
    definitions.version as achievement_version,
    recipients.component_index, recipients.reward_component_key,
    recipients.reward_component
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  join public.pachanga_reward_recipients recipients
    on recipients.achievement_grant_id = grants.id
   and recipients.box_id = target_box_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'team'
    and grants.state = 'active';
  if not found then raise exception 'Active team achievement required'; end if;

  component_rarity := source.reward_component ->> 'boxRarity';
  if component_rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary') then
    if source.is_first then
      selected_box_type := 'collective.' || case component_rarity
        when 'common' then 'uncommon'
        when 'uncommon' then 'rare'
        when 'rare' then 'epic'
        when 'epic' then 'legendary'
        else 'legendary' end;
    else
      selected_box_type := 'collective.' || component_rarity;
    end if;
  else
    select case when source.is_first then rules.first_box_type
      else rules.repeat_box_type end
    into selected_box_type
    from public.pachanga_achievement_box_rules rules
    where rules.economy_version = active_version
      and rules.achievement_key = source.achievement_key
      and rules.achievement_version = source.achievement_version
      and rules.active;
  end if;
  if selected_box_type is null then raise exception 'Achievement box rule missing'; end if;

  select * into catalog
  from public.pachanga_reward_box_catalog boxes
  where boxes.economy_version = active_version
    and boxes.box_type = selected_box_type
    and boxes.active;
  if not found then raise exception 'Reward box catalog entry missing'; end if;

  select sum(entries.weight)::integer into total_weight
  from public.pachanga_reward_pool_catalog entries
  where entries.economy_version = active_version
    and entries.pool_key = catalog.reward_pool_key
    and entries.active;
  if coalesce(total_weight, 0) <= 0 then raise exception 'Reward pool is empty'; end if;
  ticket := (hashtextextended(
    entropy::text || ':pool:' || active_version::text || ':' || catalog.reward_pool_key,
    0
  ) & 9223372036854775807) % total_weight;

  select (weighted.entry).* into pool_entry
  from (
    select entries as entry,
      sum(entries.weight) over (order by entries.entry_key) as ceiling
    from public.pachanga_reward_pool_catalog entries
    where entries.economy_version = active_version
      and entries.pool_key = catalog.reward_pool_key
      and entries.active
  ) weighted
  where ticket < weighted.ceiling
  order by weighted.ceiling
  limit 1;
  if not found then raise exception 'Reward pool selection failed'; end if;

  if pool_entry.points_max > 0 then
    selected_points := pool_entry.points_min + (
      (hashtextextended(entropy::text || ':points', 0)
        & 9223372036854775807)
      % (pool_entry.points_max - pool_entry.points_min + 1)
    );
  end if;

  payload := jsonb_strip_nulls(jsonb_build_object(
    'schemaVersion', 2,
    'catalogVersion', active_version,
    'boxType', catalog.box_type,
    'rarity', catalog.rarity,
    'poolKey', catalog.reward_pool_key,
    'poolEntryKey', pool_entry.entry_key,
    'animationKey', catalog.animation_key,
    'presentationKey', catalog.presentation_key,
    'source', 'collective_achievement',
    'reward', jsonb_strip_nulls(jsonb_build_object(
      'kind', pool_entry.reward_kind,
      'points', selected_points,
      'cosmeticKey', pool_entry.cosmetic_key,
      'duplicateConversionPoints', pool_entry.duplicate_conversion_points
    )),
    'origin', jsonb_build_object(
      'achievementKey', source.achievement_key,
      'achievementGrantId', source.id,
      'matchFactId', source.origin_match_fact_id,
      'groupId', source.group_id,
      'componentIndex', source.component_index,
      'componentKey', source.reward_component_key,
      'component', source.reward_component
    )
  ));

  update public.pachanga_reward_recipients recipients
  set economy_version = active_version,
      box_type = catalog.box_type,
      box_rarity = catalog.rarity,
      reward_pool_key = catalog.reward_pool_key,
      animation_key = catalog.animation_key,
      presentation_key = catalog.presentation_key,
      reward_reference = catalog.box_type
  where recipients.box_id = target_box_id;

  insert into private.pachanga_reward_box_contents(
    box_id, reward_payload, catalog_version, content_hash, sealed_at
  ) values (
    target_box_id, payload, active_version, md5(payload::text), clock_timestamp()
  ) on conflict (box_id) do nothing;
  return payload;
end;
$$;

create or replace function private.pachanga_ensure_collective_boxes_v2(
  target_achievement_grant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  source record;
  reward public.pachanga_reward_grants%rowtype;
  recipient record;
  component record;
  components jsonb;
  saved_box_id uuid;
  created_count integer := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    'collective-boxes:' || target_achievement_grant_id::text, 0
  ));

  select grants.*, definitions.achievement_key, definitions.title,
    definitions.description, definitions.rarity
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'team'
    and grants.state = 'active';
  if not found then return 0; end if;

  components := private.pachanga_achievement_reward_components_v3(
    source.definition_id, source.metric_value
  );
  if coalesce(jsonb_array_length(components), 0) = 0 then return 0; end if;

  insert into public.pachanga_reward_grants(
    achievement_grant_id, reward_kind, reward_key, group_id,
    player_profile_id, payload
  ) values (
    source.id, 'collective_box', 'box.collective.pending', source.group_id,
    null, jsonb_build_object(
      'boxKind', 'collective_achievement',
      'achievementKey', source.achievement_key,
      'achievementRarity', source.rarity,
      'economy', 'player_reward_v1',
      'rewardComponents', components
    )
  ) on conflict (achievement_grant_id) do update set
    payload = excluded.payload
  returning * into reward;

  for recipient in
    select distinct on (profiles.user_id)
      profiles.user_id, profiles.id as player_profile_id,
      profiles.display_name, player_facts.local_player_id
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_player_profiles profiles
      on profiles.id = player_facts.player_profile_id
    where player_facts.match_fact_id = source.origin_match_fact_id
      and player_facts.group_id = source.group_id
      and player_facts.state = 'active'
      and profiles.user_id is not null
    order by profiles.user_id, player_facts.local_player_id
  loop
    for component in
      select values_row.value as payload,
        (values_row.ordinality - 1)::integer as component_index
      from jsonb_array_elements(components) with ordinality as values_row(value, ordinality)
      order by values_row.ordinality
    loop
      saved_box_id := gen_random_uuid();
      insert into public.pachanga_reward_recipients(
        reward_grant_id, user_id, member_role_snapshot, member_name_snapshot,
        box_id, achievement_grant_id, match_fact_id, group_id,
        player_profile_id, reward_reference, component_index,
        reward_component_key, reward_component
      ) values (
        reward.id, recipient.user_id, 'participant',
        left(coalesce(recipient.display_name, 'Jugador'), 120),
        saved_box_id, source.id, source.origin_match_fact_id, source.group_id,
        recipient.player_profile_id, 'box.collective.pending',
        component.component_index, component.payload ->> 'key', component.payload
      ) on conflict (achievement_grant_id, user_id, component_index) do update set
        player_profile_id = excluded.player_profile_id,
        match_fact_id = excluded.match_fact_id,
        group_id = excluded.group_id,
        member_role_snapshot = 'participant',
        member_name_snapshot = excluded.member_name_snapshot,
        reward_component_key = excluded.reward_component_key,
        reward_component = excluded.reward_component
      returning box_id into saved_box_id;

      if not exists (
        select 1 from private.pachanga_reward_box_contents contents
        where contents.box_id = saved_box_id
      ) then
        perform private.pachanga_seal_reward_box_v1(saved_box_id, source.id);
        created_count := created_count + 1;
      end if;
    end loop;
    perform private.pachanga_progression_bump_user_v1(recipient.user_id);
  end loop;
  return created_count;
end;
$$;

create or replace function private.pachanga_reward_box_snapshot_v2(
  target_box_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'boxId', recipients.box_id,
    'rewardGrantId', rewards.id,
    'rewardKind', case when coalesce(recipients.economy_version, 0) >= 1
      then 'collective_box'
      when recipients.status = 'opened' then rewards.reward_kind
      else 'collective_box' end,
    'rewardKey', coalesce(recipients.box_type, recipients.reward_reference),
    'rewardPayload', case when recipients.status = 'opened'
      then recipients.revealed_payload else null end,
    'rewardState', rewards.state,
    'status', recipients.status,
    'recipientRevision', recipients.revision,
    'generatedAt', recipients.snapshot_at,
    'openedAt', recipients.opened_at,
    'rewardGrantedAt', recipients.reward_granted_at,
    'matchFactId', recipients.match_fact_id,
    'groupId', recipients.group_id,
    'economyVersion', recipients.economy_version,
    'boxType', recipients.box_type,
    'boxRarity', recipients.box_rarity,
    'rewardPoolKey', recipients.reward_pool_key,
    'animationKey', recipients.animation_key,
    'presentationKey', recipients.presentation_key,
    'componentIndex', recipients.component_index,
    'rewardComponentKey', recipients.reward_component_key,
    'rewardComponent', recipients.reward_component,
    'sourceCorrection', recipients.source_correction,
    'achievement', jsonb_build_object(
      'grantId', grants.id,
      'key', definitions.achievement_key,
      'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
      'description', definitions.description,
      'scope', definitions.match_scope,
      'subjectType', definitions.subject_type,
      'rarity', definitions.rarity,
      'isFirst', grants.is_first,
      'sequenceCount', grants.sequence_count,
      'occurredAt', grants.occurred_at,
      'awardedAt', grants.awarded_at
    )
  ))
  from public.pachanga_reward_recipients recipients
  join public.pachanga_reward_grants rewards
    on rewards.id = recipients.reward_grant_id
  join public.pachanga_achievement_grants grants
    on grants.id = recipients.achievement_grant_id
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where recipients.box_id = target_box_id
    and recipients.user_id = target_user_id;
$$;

create or replace function private.pachanga_reward_recipient_snapshot_v1(
  target_reward_grant_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select private.pachanga_reward_box_snapshot_v2(
    recipients.box_id, target_user_id
  )
  from public.pachanga_reward_recipients recipients
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = target_user_id
  order by case when recipients.status = 'pending' then 0 else 1 end,
    recipients.component_index, recipients.box_id
  limit 1;
$$;

create or replace function public.open_pachanga_reward_v1(
  target_reward_grant_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_box_id uuid;
begin
  select recipients.box_id into target_box_id
  from public.pachanga_reward_recipients recipients
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = auth.uid()
  order by case when recipients.status = 'pending' then 0 else 1 end,
    recipients.component_index, recipients.box_id
  limit 1;
  if target_box_id is null then raise exception 'Reward box not found'; end if;
  return public.open_pachanga_reward_box_v2(
    target_box_id, open_pachanga_reward_v1.operation_id,
    expected_revision, client_metadata
  );
end;
$$;

create or replace function private.pachanga_award_achievement_v1(
  target_definition_id uuid,
  target_subject_id uuid,
  target_group_id uuid,
  target_origin_match_fact_id uuid,
  target_metric_value integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  source_fact public.pachanga_progression_match_facts%rowtype;
  saved_grant_id uuid;
  occurrence_is_first boolean;
  occurrence_sequence integer;
  occurrence_title text;
  occurrence_components jsonb;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id and definitions.active;
  if not found or definition.subject_type not in ('team', 'player') then return null; end if;
  if target_metric_value < definition.threshold then return null; end if;
  if definition.subject_type = 'team' and target_subject_id <> target_group_id then
    raise exception 'Team achievement subject must be its group';
  end if;

  select * into source_fact
  from public.pachanga_progression_match_facts facts
  where facts.id = target_origin_match_fact_id and facts.state = 'active';
  if not found or source_fact.server_sequence < definition.activation_server_sequence then
    return null;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'achievement-family:' || definition.family_key || ':' || definition.evaluator_key
      || ':' || definition.threshold::text || ':' || target_subject_id::text, 0
  ));

  if definition.repeatable then
    select grants.id into saved_grant_id
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions grant_definitions
      on grant_definitions.id = grants.definition_id
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grant_definitions.family_key = definition.family_key
      and grant_definitions.evaluator_key = definition.evaluator_key
      and grant_definitions.threshold = definition.threshold
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active'
    order by grants.id
    limit 1;
  else
    select grants.id into saved_grant_id
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions grant_definitions
      on grant_definitions.id = grants.definition_id
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grant_definitions.family_key = definition.family_key
      and grant_definitions.evaluator_key = definition.evaluator_key
      and grant_definitions.threshold = definition.threshold
      and grants.state = 'active'
    order by grants.occurred_at, grants.id
    limit 1;
  end if;

  if saved_grant_id is not null then
    if definition.subject_type = 'team' then
      perform private.pachanga_ensure_collective_boxes_v2(saved_grant_id);
    end if;
    return null;
  end if;

  select not exists (
    select 1
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions grant_definitions
      on grant_definitions.id = grants.definition_id
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grant_definitions.family_key = definition.family_key
      and grant_definitions.evaluator_key = definition.evaluator_key
      and grant_definitions.threshold = definition.threshold
      and grants.state = 'active'
  ), count(*) + 1
  into occurrence_is_first, occurrence_sequence
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions grant_definitions
    on grant_definitions.id = grants.definition_id
  where grants.subject_type = definition.subject_type
    and grants.subject_id = target_subject_id
    and grant_definitions.family_key = definition.family_key
    and grant_definitions.evaluator_key = definition.evaluator_key
    and grant_definitions.threshold = definition.threshold
    and grants.state = 'active';

  occurrence_title := private.pachanga_achievement_occurrence_title_v2(
    definition.id, occurrence_is_first
  );
  if definition.parameters ->> 'ruleKind' = 'team_match_goals'
    and target_metric_value > 10 then
    occurrence_title := target_metric_value::text || ' goles';
  end if;
  occurrence_components := case when definition.subject_type = 'team'
    then private.pachanga_achievement_reward_components_v3(
      definition.id, target_metric_value
    ) else '[]'::jsonb end;

  saved_grant_id := gen_random_uuid();
  insert into public.pachanga_achievement_grants(
    id, definition_id, subject_type, subject_id, group_id,
    origin_match_fact_id, metric_value, operation_id, occurred_at,
    is_first, sequence_count, occurrence_metadata
  ) values (
    saved_grant_id, definition.id, definition.subject_type, target_subject_id,
    target_group_id, target_origin_match_fact_id, target_metric_value,
    md5(
      'achievement-grant:' || definition.id::text || ':' || target_subject_id::text
      || ':' || target_origin_match_fact_id::text
    )::uuid,
    source_fact.played_at, occurrence_is_first, occurrence_sequence,
    jsonb_build_object(
      'displayTitle', occurrence_title,
      'repeatable', definition.repeatable,
      'sourceKind', source_fact.source_kind,
      'sourceMatchId', source_fact.source_match_id,
      'catalogKey', definition.catalog_key,
      'familyKey', definition.family_key,
      'displayPriority', definition.display_priority,
      'iconKey', definition.icon_key,
      'rewardComponents', occurrence_components
    )
  );

  perform private.pachanga_progression_record_event_v1(
    md5('achievement-event:' || saved_grant_id::text)::uuid,
    'achievement_awarded', target_group_id,
    case when definition.subject_type = 'player' then target_subject_id else null end,
    target_origin_match_fact_id, saved_grant_id, null,
    jsonb_build_object(
      'achievementKey', definition.achievement_key,
      'catalogKey', definition.catalog_key,
      'familyKey', definition.family_key,
      'displayTitle', occurrence_title,
      'isFirst', occurrence_is_first,
      'sequenceCount', occurrence_sequence,
      'metricValue', target_metric_value,
      'threshold', definition.threshold,
      'rarity', definition.rarity,
      'displayPriority', definition.display_priority,
      'rewardEligible', definition.subject_type = 'team',
      'rewardComponents', occurrence_components
    )
  );

  if definition.subject_type = 'team' then
    perform private.pachanga_ensure_collective_boxes_v2(saved_grant_id);
  end if;
  return saved_grant_id;
end;
$$;

create or replace function private.pachanga_evaluate_achievements_v1(
  target_group_id uuid,
  target_match_scope text,
  target_origin_match_fact_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  match_fact public.pachanga_progression_match_facts%rowtype;
  definition record;
  player record;
  metric integer;
  previous_metric integer;
  qualifies boolean;
  before_id uuid;
  after_id uuid;
  awarded integer := 0;
  recipient record;
  personal_count integer;
  box_count integer;
begin
  select * into match_fact
  from public.pachanga_progression_match_facts facts
  where facts.id = target_origin_match_fact_id
    and facts.group_id = target_group_id
    and facts.match_scope = target_match_scope
    and facts.state = 'active';
  if not found then return 0; end if;
  if match_fact.source_kind = 'external_result'
    and coalesce(match_fact.source_snapshot ->> 'officialState',
      match_fact.source_snapshot ->> 'canonicalState', '')
      not in ('confirmed', 'auto_confirmed') then
    return 0;
  end if;

  for definition in
    select definitions.*
    from public.pachanga_achievement_definitions definitions
    where definitions.active
      and definitions.subject_type = 'team'
      and definitions.match_scope in (target_match_scope, 'all')
      and definitions.activation_server_sequence <= match_fact.server_sequence
      and coalesce(definitions.parameters ->> 'ruleKind', '') <> 'team_match_goals'
    order by definitions.display_priority, definitions.achievement_key
  loop
    if not definition.repeatable and exists (
      select 1
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions grant_definitions
        on grant_definitions.id = grants.definition_id
      where grants.subject_type = 'team'
        and grants.subject_id = target_group_id
        and grants.state = 'active'
        and grant_definitions.family_key = definition.family_key
        and grant_definitions.evaluator_key = definition.evaluator_key
        and grant_definitions.threshold = definition.threshold
    ) then
      continue;
    end if;

    metric := private.pachanga_achievement_metric_v1(definition.id, target_group_id);
    if definition.parameters ->> 'ruleKind' = 'team_match_win' then
      qualifies := match_fact.outcome = 'win';
    elsif definition.parameters ->> 'ruleKind' = 'team_match_clean_sheet' then
      qualifies := match_fact.clean_sheet;
    elsif definition.parameters ->> 'ruleKind' = 'team_match_big_win' then
      qualifies := match_fact.big_win;
    elsif definition.parameters ->> 'ruleKind' = 'team_match_close_win' then
      qualifies := match_fact.close_win;
    elsif definition.parameters ->> 'ruleKind' = 'team_match_absolute_dominance' then
      qualifies := target_match_scope = 'external'
        and match_fact.outcome = 'win'
        and match_fact.big_win
        and match_fact.goals_against = 0;
    elsif metric < definition.threshold then
      qualifies := false;
    else
      previous_metric := private.pachanga_team_metric_without_match_v3(
        definition.id, target_group_id, target_origin_match_fact_id
      );
      qualifies := previous_metric < definition.threshold;
    end if;
    if not qualifies then continue; end if;

    select grants.id into before_id
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions grant_definitions
      on grant_definitions.id = grants.definition_id
    where grant_definitions.family_key = definition.family_key
      and grant_definitions.evaluator_key = definition.evaluator_key
      and grant_definitions.threshold = definition.threshold
      and grants.subject_type = 'team'
      and grants.subject_id = target_group_id
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active';
    after_id := private.pachanga_award_achievement_v1(
      definition.id, target_group_id, target_group_id,
      target_origin_match_fact_id, greatest(metric, definition.threshold)
    );
    if before_id is null and after_id is not null then awarded := awarded + 1; end if;
    before_id := null;
    after_id := null;
  end loop;

  select definitions.* into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.active
    and definitions.subject_type = 'team'
    and definitions.match_scope = target_match_scope
    and definitions.activation_server_sequence <= match_fact.server_sequence
    and definitions.parameters ->> 'ruleKind' = 'team_match_goals'
    and (
      (definitions.parameters ? 'goalsExact'
        and (definitions.parameters ->> 'goalsExact')::integer = match_fact.goals_for)
      or (definitions.parameters ? 'goalsMinimum'
        and (definitions.parameters ->> 'goalsMinimum')::integer <= match_fact.goals_for)
    )
  order by coalesce((definitions.parameters ->> 'goalsMinimum')::integer,
    (definitions.parameters ->> 'goalsExact')::integer) desc,
    definitions.achievement_key
  limit 1;
  if found then
    select grants.id into before_id
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions grant_definitions
      on grant_definitions.id = grants.definition_id
    where grant_definitions.family_key = definition.family_key
      and grant_definitions.evaluator_key = definition.evaluator_key
      and grant_definitions.threshold = definition.threshold
      and grants.subject_id = target_group_id
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active';
    after_id := private.pachanga_award_achievement_v1(
      definition.id, target_group_id, target_group_id,
      target_origin_match_fact_id, match_fact.goals_for
    );
    if after_id is not null then
      update public.pachanga_achievement_grants grants
      set occurrence_metadata = grants.occurrence_metadata || jsonb_build_object(
        'displayTitle', case when match_fact.goals_for > 10
          then match_fact.goals_for::text || ' goles' else definition.title end,
        'rewardComponents', private.pachanga_goal_reward_components_v3(
          match_fact.goals_for
        )
      )
      where grants.id = after_id;
    end if;
    if before_id is null and after_id is not null then awarded := awarded + 1; end if;
    before_id := null;
    after_id := null;
  end if;

  for player in
    select player_facts.player_profile_id, player_facts.goals
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = target_origin_match_fact_id
      and player_facts.group_id = target_group_id
      and player_facts.state = 'active'
    order by player_facts.player_profile_id
  loop
    select definitions.* into definition
    from public.pachanga_achievement_definitions definitions
    where definitions.active
      and definitions.subject_type = 'player'
      and definitions.match_scope in (target_match_scope, 'all')
      and definitions.activation_server_sequence <= match_fact.server_sequence
      and definitions.parameters ->> 'ruleKind' = 'player_match_goals'
      and (
        (definitions.parameters ? 'goalsExact'
          and (definitions.parameters ->> 'goalsExact')::integer = player.goals)
        or (definitions.parameters ? 'goalsMinimum'
          and (definitions.parameters ->> 'goalsMinimum')::integer <= player.goals)
      )
    order by coalesce((definitions.parameters ->> 'goalsMinimum')::integer,
      (definitions.parameters ->> 'goalsExact')::integer) desc,
      definitions.achievement_key
    limit 1;
    if found then
      select grants.id into before_id
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions grant_definitions
        on grant_definitions.id = grants.definition_id
      where grant_definitions.family_key = definition.family_key
        and grant_definitions.evaluator_key = definition.evaluator_key
        and grant_definitions.threshold = definition.threshold
        and grants.subject_id = player.player_profile_id
        and grants.origin_match_fact_id = target_origin_match_fact_id
        and grants.state = 'active';
      after_id := private.pachanga_award_achievement_v1(
        definition.id, player.player_profile_id, target_group_id,
        target_origin_match_fact_id,
        private.pachanga_achievement_metric_v1(definition.id, player.player_profile_id)
      );
      if before_id is null and after_id is not null then awarded := awarded + 1; end if;
      before_id := null;
      after_id := null;
    end if;

    for definition in
      select definitions.*
      from public.pachanga_achievement_definitions definitions
      where definitions.active
        and definitions.subject_type = 'player'
        and definitions.match_scope in (target_match_scope, 'all')
        and definitions.activation_server_sequence <= match_fact.server_sequence
        and coalesce(definitions.parameters ->> 'ruleKind', '') <> 'player_match_goals'
      order by definitions.display_priority, definitions.achievement_key
    loop
      if exists (
        select 1
        from public.pachanga_achievement_grants grants
        join public.pachanga_achievement_definitions grant_definitions
          on grant_definitions.id = grants.definition_id
        where grants.subject_type = 'player'
          and grants.subject_id = player.player_profile_id
          and grants.state = 'active'
          and grant_definitions.family_key = definition.family_key
          and grant_definitions.evaluator_key = definition.evaluator_key
          and grant_definitions.threshold = definition.threshold
      ) then
        continue;
      end if;
      metric := private.pachanga_achievement_metric_v1(
        definition.id, player.player_profile_id
      );
      if metric < definition.threshold then continue; end if;
      previous_metric := private.pachanga_achievement_metric_without_match_v2(
        definition.id, player.player_profile_id, target_origin_match_fact_id
      );
      if previous_metric >= definition.threshold then continue; end if;
      before_id := null;
      select grants.id into before_id
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions grant_definitions
        on grant_definitions.id = grants.definition_id
      where grant_definitions.family_key = definition.family_key
        and grant_definitions.evaluator_key = definition.evaluator_key
        and grant_definitions.threshold = definition.threshold
        and grants.subject_id = player.player_profile_id
        and grants.state = 'active'
      order by grants.occurred_at, grants.id
      limit 1;
      after_id := private.pachanga_award_achievement_v1(
        definition.id, player.player_profile_id, target_group_id,
        target_origin_match_fact_id, metric
      );
      if before_id is null and after_id is not null then awarded := awarded + 1; end if;
      before_id := null;
      after_id := null;
    end loop;
  end loop;

  if coalesce(current_setting('pachangas.progression_backfill', true), '') <> 'on' then
    for recipient in
      select recipients.user_id, count(*)::integer as pending_boxes
      from public.pachanga_reward_recipients recipients
      where recipients.match_fact_id = target_origin_match_fact_id
        and recipients.group_id = target_group_id
        and recipients.status = 'pending'
      group by recipients.user_id
      order by recipients.user_id
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id, 'postmatch_reward_boxes',
        'Tus premios del partido están listos',
        'Premios pendientes: ' || recipient.pending_boxes::text || '.',
        '/equipo/identidad?grupo=' || target_group_id::text || '&rewards=pending',
        jsonb_build_object(
          'groupId', target_group_id, 'matchFactId', target_origin_match_fact_id,
          'pendingRewardCount', recipient.pending_boxes
        ),
        'postmatch-rewards:' || target_origin_match_fact_id::text || ':' || recipient.user_id::text
      );
    end loop;

    for recipient in
      select profiles.user_id, profiles.id as player_profile_id
      from public.pachanga_progression_player_match_facts player_facts
      join public.pachanga_player_profiles profiles
        on profiles.id = player_facts.player_profile_id
      where player_facts.match_fact_id = target_origin_match_fact_id
        and player_facts.group_id = target_group_id
        and player_facts.state = 'active'
        and profiles.user_id is not null
      order by profiles.user_id
    loop
      select count(*)::integer into personal_count
      from public.pachanga_achievement_grants grants
      where grants.subject_type = 'player'
        and grants.subject_id = recipient.player_profile_id
        and grants.origin_match_fact_id = target_origin_match_fact_id
        and grants.state = 'active';
      select count(*)::integer into box_count
      from public.pachanga_reward_recipients boxes
      where boxes.user_id = recipient.user_id
        and boxes.match_fact_id = target_origin_match_fact_id
        and boxes.status = 'pending';
      if personal_count > 0 and box_count = 0 then
        perform private.pachanga_notify_v1(
          recipient.user_id, 'personal_achievement', 'Nuevos logros personales',
          'Reconocimientos del partido: ' || personal_count::text || '.',
          '/equipo/identidad?grupo=' || target_group_id::text || '&achievements=latest',
          jsonb_build_object(
            'groupId', target_group_id, 'matchFactId', target_origin_match_fact_id,
            'personalAchievementCount', personal_count
          ),
          'postmatch-personal:' || target_origin_match_fact_id::text || ':' || recipient.user_id::text
        );
      end if;
    end loop;
  end if;
  return awarded;
end;
$$;

-- Build the global read model as baseline only. Definitions use activation
-- sequence guards, so this does not award any historical achievement or box.
do $$
declare
  group_row record;
begin
  for group_row in
    select distinct facts.group_id
    from public.pachanga_progression_match_facts facts
    where facts.state = 'active'
    order by facts.group_id
  loop
    perform private.pachanga_upsert_team_progression_scope_v3(
      group_row.group_id, 'all'
    );
  end loop;
end;
$$;

alter function public.get_pachanga_progression_snapshot_v1(uuid)
  rename to pachanga_progression_snapshot_pre_catalog_v3;
alter function public.pachanga_progression_snapshot_pre_catalog_v3(uuid)
  set schema private;
revoke all on function private.pachanga_progression_snapshot_pre_catalog_v3(uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_progression_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  base_snapshot jsonb;
begin
  base_snapshot := private.pachanga_progression_snapshot_pre_catalog_v3(
    target_group_id
  );
  return base_snapshot || jsonb_build_object(
    'catalogKey', 'achievement_catalog_v3',
    'teamStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope, 'matches', stats.matches_played,
        'wins', stats.wins, 'draws', stats.draws, 'losses', stats.losses,
        'goalsFor', stats.goals_for, 'goalsAgainst', stats.goals_against,
        'cleanSheets', stats.clean_sheets, 'bigWins', stats.big_wins,
        'closeWins', stats.close_wins,
        'currentWinStreak', stats.current_win_streak,
        'maxWinStreak', stats.max_win_streak,
        'currentUnbeatenStreak', stats.current_unbeaten_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'distinctOpponents', stats.distinct_opponents,
        'distinctOpponentsWon', stats.distinct_opponents_won,
        'revision', stats.revision, 'updatedAt', stats.updated_at
      ) order by case stats.match_scope
        when 'all' then 0 when 'internal' then 1 else 2 end)
      from public.pachanga_team_progression_stats stats
      where stats.group_id = target_group_id
    ), '[]'::jsonb),
    'teamAchievementCatalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', definitions.achievement_key,
        'title', definitions.title,
        'description', definitions.description,
        'scope', definitions.match_scope,
        'family', definitions.family_key,
        'category', definitions.category,
        'rarity', definitions.rarity,
        'threshold', definitions.threshold,
        'currentValue', private.pachanga_achievement_metric_v1(
          definitions.id, target_group_id
        ),
        'repeatable', definitions.repeatable,
        'displayPriority', definitions.display_priority,
        'iconKey', definitions.icon_key,
        'boxRarity', definitions.box_rarity,
        'rewardPoolVersion', definitions.reward_pool_version,
        'animationKey', definitions.animation_key,
        'presentationKey', definitions.presentation_key,
        'rewardComponents', definitions.reward_components
      ) order by definitions.display_priority,
        definitions.threshold, definitions.achievement_key)
      from public.pachanga_achievement_definitions definitions
      where definitions.active
        and definitions.catalog_key = 'achievement_catalog_v3'
        and definitions.subject_type = 'team'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.pachanga_goal_reward_components_v3(integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_reward_components_v3(uuid, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_upsert_team_progression_scope_v3(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_metric_without_match_v3(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_seal_reward_box_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_ensure_collective_boxes_v2(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_box_snapshot_v2(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_recipient_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;

comment on column public.pachanga_achievement_definitions.reward_components is
  'Server-authored ordered box components for one collective achievement occurrence.';
comment on column public.pachanga_reward_recipients.component_index is
  'Stable zero-based component identity; idempotency is grant + user + component index.';
comment on function private.pachanga_goal_reward_components_v3(integer) is
  'Exact server-authoritative decomposition of collective team goals into reward boxes.';
