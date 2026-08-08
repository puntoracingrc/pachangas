-- Pachangas IQ definitive achievement catalog V1, stored as catalog version 2.
-- Forward-only: historical grants remain attached to their original definitions
-- and no pre-activation match can create a new reward box.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_achievement_definitions
  add column if not exists catalog_key text,
  add column if not exists family_key text,
  add column if not exists display_priority integer,
  add column if not exists icon_key text,
  add column if not exists first_time_variant text,
  add column if not exists box_rarity text,
  add column if not exists reward_pool_version integer,
  add column if not exists animation_key text,
  add column if not exists presentation_key text,
  add column if not exists share_title text,
  add column if not exists share_description text,
  add column if not exists share_template_key text,
  add column if not exists season_id uuid,
  add column if not exists activation_server_sequence bigint not null default 0,
  add column if not exists catalog_disposition text;

alter table public.pachanga_achievement_definitions
  drop constraint if exists pachanga_achievement_definitions_match_scope_check;
alter table public.pachanga_achievement_definitions
  add constraint pachanga_achievement_definitions_match_scope_check
  check (match_scope in ('all', 'internal', 'external'));

alter table public.pachanga_achievement_definitions
  drop constraint if exists pachanga_achievement_definitions_evaluator_key_check;
alter table public.pachanga_achievement_definitions
  add constraint pachanga_achievement_definitions_evaluator_key_check check (evaluator_key in (
    'TEAM_MATCHES', 'TEAM_WINS', 'TEAM_DRAWS', 'TEAM_LOSSES', 'TEAM_GOALS',
    'TEAM_MAX_WIN_STREAK', 'TEAM_MAX_UNBEATEN_STREAK', 'TEAM_CLEAN_SHEETS',
    'TEAM_BIG_WINS', 'TEAM_CLOSE_WINS', 'TEAM_SCORELESS_DRAWS',
    'TEAM_DISTINCT_OPPONENTS', 'TEAM_DISTINCT_OPPONENT_WINS',
    'PLAYER_APPEARANCES', 'PLAYER_WINS', 'PLAYER_GOALS',
    'PLAYER_BRACES', 'PLAYER_HATTRICKS', 'PLAYER_POKERS',
    'PLAYER_REPOKERS', 'PLAYER_DOUBLE_HAT_TRICKS',
    'PLAYER_MAX_WIN_STREAK', 'PLAYER_MAX_UNBEATEN_STREAK',
    'PLAYER_DISTINCT_OPPONENTS', 'PLAYER_DISTINCT_OPPONENT_WINS'
  ));

alter table public.pachanga_achievement_definitions
  add constraint pachanga_achievement_definitions_catalog_key_check
    check (catalog_key is null or char_length(catalog_key) between 3 and 80),
  add constraint pachanga_achievement_definitions_family_key_check
    check (family_key is null or char_length(family_key) between 3 and 120),
  add constraint pachanga_achievement_definitions_display_priority_check
    check (display_priority is null or display_priority between 1 and 999),
  add constraint pachanga_achievement_definitions_box_rarity_check
    check (box_rarity is null or box_rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  add constraint pachanga_achievement_definitions_reward_pool_version_check
    check (reward_pool_version is null or reward_pool_version >= 1),
  add constraint pachanga_achievement_definitions_activation_sequence_check
    check (activation_server_sequence >= 0),
  add constraint pachanga_achievement_definitions_disposition_check
    check (catalog_disposition is null or catalog_disposition in ('KEEP', 'MIGRATE', 'RENAME', 'DEPRECATE', 'FUTURE'));

alter table public.pachanga_player_progression_stats
  add column if not exists distinct_opponents integer not null default 0,
  add column if not exists distinct_opponents_won integer not null default 0;
alter table public.pachanga_team_progression_stats
  add column if not exists distinct_opponents_won integer not null default 0;

alter table public.pachanga_player_progression_stats
  drop constraint if exists pachanga_player_progression_stats_match_scope_check;
alter table public.pachanga_player_progression_stats
  add constraint pachanga_player_progression_stats_match_scope_check
  check (match_scope in ('all', 'internal', 'external'));

alter table public.pachanga_player_progression_stats
  drop constraint if exists pachanga_player_progression_stats_nonnegative_check;
alter table public.pachanga_player_progression_stats
  add constraint pachanga_player_progression_stats_nonnegative_check check (least(
    appearances, wins, draws, losses, goals, braces, hat_tricks, pokers,
    repokers, double_hat_tricks, current_win_streak, max_win_streak,
    current_unbeaten_streak, max_unbeaten_streak, distinct_opponents,
    distinct_opponents_won
  ) >= 0);

alter table public.pachanga_team_progression_stats
  drop constraint if exists pachanga_team_progression_stats_check;
alter table public.pachanga_team_progression_stats
  add constraint pachanga_team_progression_stats_check check (least(
    matches_played, wins, draws, losses, goals_for, goals_against,
    clean_sheets, close_wins, big_wins, scoreless_draws, distinct_opponents,
    distinct_opponents_won, current_win_streak, max_win_streak,
    current_unbeaten_streak, max_unbeaten_streak
  ) >= 0);

-- Classify the deployed catalog without changing historical grant semantics.
update public.pachanga_achievement_definitions
set catalog_key = coalesce(catalog_key, 'achievement_catalog_v1_legacy'),
    family_key = coalesce(family_key, case
      when subject_type = 'player' and parameters ->> 'ruleKind' = 'player_match_goals'
        then 'player.match_goals'
      when subject_type = 'team' and parameters ->> 'ruleKind' = 'team_match_goals'
        then 'team.match_goals'
      else subject_type || '.' || category
    end),
    display_priority = coalesce(display_priority, case category
      when 'matches' then 10 when 'wins' then 20 when 'match_goals' then 30
      when 'goals' then 40 when 'special' then 50 when 'streak' then 60
      when 'opponents' then 70 else 90 end),
    icon_key = coalesce(icon_key, case
      when evaluator_key like '%GOALS%' then 'goal'
      when evaluator_key like '%WIN_STREAK%' then 'winning_streak'
      when evaluator_key like '%UNBEATEN%' then 'unbeaten'
      when evaluator_key like '%OPPONENT%' then 'rivals'
      when evaluator_key like '%WINS%' then 'victory'
      else 'matches' end),
    catalog_disposition = case
      when achievement_key in (
        'team.internal.goals.025', 'team.internal.goals.100',
        'team.external.goals.025', 'team.internal.scoreless.001'
      ) then 'DEPRECATE'
      when active then 'MIGRATE' else coalesce(catalog_disposition, 'DEPRECATE') end,
    parameters = parameters || jsonb_build_object(
      'catalogDisposition', case
        when achievement_key in (
          'team.internal.goals.025', 'team.internal.goals.100',
          'team.external.goals.025', 'team.internal.scoreless.001'
        ) then 'DEPRECATE'
        when active then 'MIGRATE' else coalesce(catalog_disposition, 'DEPRECATE') end
    )
where version = 1;

update public.pachanga_achievement_definitions
set active = false
where active;

-- Individual career milestones are global across internal and external matches.
with milestones(threshold, title, rarity) as (
  values
    (1, 'Primeros minutos', 'common'), (5, 'Uno de los nuestros', 'common'),
    (10, 'En dinámica', 'common'), (25, 'Habitual', 'uncommon'),
    (50, 'Veterano', 'uncommon'), (100, 'Centenario', 'rare'),
    (250, 'Leyenda del vestuario', 'epic'), (500, 'Historia viva', 'legendary')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, reward_key, active, catalog_key, family_key, display_priority,
  icon_key, share_title, share_description, share_template_key,
  activation_server_sequence, catalog_disposition
)
select 'player.all.matches.' || lpad(threshold::text, 3, '0'), 2, title,
  case when threshold = 1 then 'Disputa su primer partido confirmado.'
    else 'Disputa ' || threshold::text || ' partidos confirmados.' end,
  'player', 'all', 'matches', 'PLAYER_APPEARANCES', '{}'::jsonb,
  threshold, rarity, false, 'none', null, true,
  'achievement_catalog_v2', 'player.matches', 10 + threshold, 'matches',
  title, case when threshold = 1 then 'Primer partido confirmado.'
    else threshold::text || ' partidos confirmados.' end,
  'player_milestone', (select last_value + 1 from public.pachanga_progression_sequence),
  'MIGRATE'
from milestones;

with milestones(threshold, title, rarity) as (
  values
    (1, 'Primera alegría', 'common'), (5, 'Cinco victorias', 'common'),
    (10, 'Diez alegrías', 'uncommon'), (25, 'Ganador habitual', 'uncommon'),
    (50, 'Medio centenar de victorias', 'rare'),
    (100, 'Cien victorias', 'epic'), (250, 'Historia ganadora', 'legendary')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  share_title, share_description, share_template_key,
  activation_server_sequence, catalog_disposition
)
select 'player.all.wins.' || lpad(threshold::text, 3, '0'), 2, title,
  case when threshold = 1 then 'Participa en su primera victoria confirmada.'
    else 'Participa en ' || threshold::text || ' victorias confirmadas.' end,
  'player', 'all', 'wins', 'PLAYER_WINS', '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', 'player.wins',
  20 + threshold, 'victory', title,
  threshold::text || ' victorias como participante.', 'player_milestone',
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from milestones;

with milestones(threshold, title, rarity) as (
  values
    (1, 'Primer gol', 'common'), (10, 'Diez goles', 'common'),
    (25, 'Veinticinco goles', 'uncommon'), (50, 'Medio centenar', 'rare'),
    (100, 'Centenario goleador', 'epic'), (250, 'Goleador histórico', 'epic'),
    (500, 'Historia del gol', 'legendary')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  share_title, share_description, share_template_key,
  activation_server_sequence, catalog_disposition
)
select 'player.all.goals.' || lpad(threshold::text, 3, '0'), 2, title,
  case when threshold = 1 then 'Marca su primer gol confirmado.'
    else 'Alcanza ' || threshold::text || ' goles personales confirmados.' end,
  'player', 'all', 'goals', 'PLAYER_GOALS', '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', 'player.goals',
  40 + threshold, 'goal', title,
  threshold::text || ' goles confirmados.', 'player_goals_milestone',
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from milestones;

insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  first_time_variant, share_title, share_description, share_template_key,
  activation_server_sequence, catalog_disposition
)
values
  ('player.all.braces.001', 2, 'Doblete', 'Marca exactamente dos goles en un partido confirmado.', 'player', 'all', 'match_goals', 'PLAYER_BRACES', '{"ruleKind":"player_match_goals","goalsExact":2,"firstTitle":"Primer doblete","repeatTitle":"Doblete"}', 1, 'uncommon', true, 'none', true, 'achievement_catalog_v2', 'player.match_goals', 32, 'goal', 'Primer doblete', 'Doblete', '2 goles en un mismo partido.', 'player_match_goals', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('player.all.hat_tricks.001', 2, 'Hat-trick', 'Marca exactamente tres goles en un partido confirmado.', 'player', 'all', 'match_goals', 'PLAYER_HATTRICKS', '{"ruleKind":"player_match_goals","goalsExact":3,"firstTitle":"Primer hat-trick","repeatTitle":"Hat-trick"}', 1, 'rare', true, 'none', true, 'achievement_catalog_v2', 'player.match_goals', 31, 'hat_trick', 'Primer hat-trick', 'Hat-trick', '3 goles en un mismo partido.', 'player_match_goals', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('player.all.pokers.001', 2, 'Póker', 'Marca exactamente cuatro goles en un partido confirmado.', 'player', 'all', 'match_goals', 'PLAYER_POKERS', '{"ruleKind":"player_match_goals","goalsExact":4,"firstTitle":"Primer póker","repeatTitle":"Póker"}', 1, 'rare', true, 'none', true, 'achievement_catalog_v2', 'player.match_goals', 30, 'poker', 'Primer póker', 'Póker', '4 goles en un mismo partido.', 'player_match_goals', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('player.all.repokers.001', 2, 'Repóker', 'Marca exactamente cinco goles en un partido confirmado.', 'player', 'all', 'match_goals', 'PLAYER_REPOKERS', '{"ruleKind":"player_match_goals","goalsExact":5,"firstTitle":"Primer repóker","repeatTitle":"Repóker"}', 1, 'epic', true, 'none', true, 'achievement_catalog_v2', 'player.match_goals', 29, 'goal', 'Primer repóker', 'Repóker', '5 goles en un mismo partido.', 'player_match_goals', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('player.all.double_hat_tricks.001', 2, 'Doble hat-trick', 'Marca seis o más goles en un partido confirmado.', 'player', 'all', 'match_goals', 'PLAYER_DOUBLE_HAT_TRICKS', '{"ruleKind":"player_match_goals","goalsMinimum":6,"firstTitle":"Primer doble hat-trick","repeatTitle":"Doble hat-trick"}', 1, 'legendary', true, 'none', true, 'achievement_catalog_v2', 'player.match_goals', 28, 'hat_trick', 'Primer doble hat-trick', 'Doble hat-trick', '6 o más goles en un mismo partido.', 'player_match_goals', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE');

with streaks(evaluator, family_key, threshold, title, rarity, priority, icon_key) as (
  values
    ('PLAYER_MAX_WIN_STREAK', 'player.win_streak', 3, 'Tres seguidas', 'common', 61, 'winning_streak'),
    ('PLAYER_MAX_WIN_STREAK', 'player.win_streak', 5, 'Cinco seguidas', 'uncommon', 62, 'winning_streak'),
    ('PLAYER_MAX_WIN_STREAK', 'player.win_streak', 10, 'Diez seguidas', 'epic', 63, 'winning_streak'),
    ('PLAYER_MAX_WIN_STREAK', 'player.win_streak', 15, 'Quince seguidas', 'legendary', 64, 'winning_streak'),
    ('PLAYER_MAX_UNBEATEN_STREAK', 'player.unbeaten', 3, 'Tres sin perder', 'common', 65, 'unbeaten'),
    ('PLAYER_MAX_UNBEATEN_STREAK', 'player.unbeaten', 5, 'Cinco sin perder', 'uncommon', 66, 'unbeaten'),
    ('PLAYER_MAX_UNBEATEN_STREAK', 'player.unbeaten', 10, 'Diez sin perder', 'rare', 67, 'unbeaten'),
    ('PLAYER_MAX_UNBEATEN_STREAK', 'player.unbeaten', 20, 'Veinte sin perder', 'legendary', 68, 'unbeaten')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  activation_server_sequence, catalog_disposition
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 2, title,
  case when evaluator = 'PLAYER_MAX_WIN_STREAK' then
    'Encadena ' || threshold::text || ' victorias como participante.'
  else 'Encadena ' || threshold::text || ' partidos sin perder como participante.' end,
  'player', 'all', 'streak', evaluator, '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', family_key, priority,
  icon_key, (select last_value + 1 from public.pachanga_progression_sequence),
  'MIGRATE'
from streaks;

with rivals(evaluator, family_key, threshold, title, rarity, priority) as (
  values
    ('PLAYER_DISTINCT_OPPONENTS', 'player.opponents_played', 3, 'Tres rivales', 'common', 71),
    ('PLAYER_DISTINCT_OPPONENTS', 'player.opponents_played', 5, 'Cinco rivales', 'common', 72),
    ('PLAYER_DISTINCT_OPPONENTS', 'player.opponents_played', 10, 'Diez rivales', 'uncommon', 73),
    ('PLAYER_DISTINCT_OPPONENTS', 'player.opponents_played', 25, 'Veinticinco rivales', 'rare', 74),
    ('PLAYER_DISTINCT_OPPONENTS', 'player.opponents_played', 50, 'Cincuenta rivales', 'epic', 75),
    ('PLAYER_DISTINCT_OPPONENT_WINS', 'player.opponents_won', 3, 'Tres rivales vencidos', 'uncommon', 76),
    ('PLAYER_DISTINCT_OPPONENT_WINS', 'player.opponents_won', 5, 'Cinco rivales vencidos', 'uncommon', 77),
    ('PLAYER_DISTINCT_OPPONENT_WINS', 'player.opponents_won', 10, 'Diez rivales vencidos', 'rare', 78),
    ('PLAYER_DISTINCT_OPPONENT_WINS', 'player.opponents_won', 25, 'Veinticinco rivales vencidos', 'epic', 79),
    ('PLAYER_DISTINCT_OPPONENT_WINS', 'player.opponents_won', 50, 'Cincuenta rivales vencidos', 'legendary', 80)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  activation_server_sequence, catalog_disposition
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 2, title,
  case when evaluator = 'PLAYER_DISTINCT_OPPONENTS' then
    'Participa contra ' || threshold::text || ' equipos rivales distintos.'
  else 'Participa en victorias contra ' || threshold::text || ' equipos rivales distintos.' end,
  'player', 'external', 'opponents', evaluator, '{}'::jsonb, threshold,
  rarity, false, 'none', true, 'achievement_catalog_v2', family_key,
  priority, 'rivals', (select last_value + 1 from public.pachanga_progression_sequence),
  'MIGRATE'
from rivals;

-- Collective participation milestones remain scope-specific: an internal
-- pachanga and a match against another registered team tell different stories.
with scopes(scope, label) as (
  values ('internal', 'pachangas'), ('external', 'partidos contra rivales')
), milestones(threshold, title, rarity) as (
  values
    (1, 'Primer partido', 'common'), (5, 'Cinco partidos', 'common'),
    (10, 'Diez partidos', 'uncommon'), (25, 'Veinticinco partidos', 'uncommon'),
    (50, 'Cincuenta partidos', 'rare'), (100, 'Cien partidos', 'rare'),
    (250, 'Doscientos cincuenta partidos', 'epic'),
    (500, 'Quinientos partidos', 'legendary')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition
)
select 'team.' || scope || '.matches.' || lpad(threshold::text, 3, '0'),
  2, title, case when threshold = 1 then 'Completa el primer partido confirmado del equipo.'
    else 'Completa ' || threshold::text || ' ' || label || ' confirmados.' end,
  'team', scope, 'matches', 'TEAM_MATCHES', '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', 'team.' || scope || '.matches',
  10 + threshold, 'matches', rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from scopes cross join milestones;

with milestones(threshold, title, rarity, repeatable, parameters) as (
  values
    (1, 'Victoria', 'common', true, '{"ruleKind":"team_match_win","firstTitle":"Primera victoria","repeatTitle":"Victoria"}'::jsonb),
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
  presentation_key, activation_server_sequence, catalog_disposition
)
select 'team.external.wins.' || lpad(threshold::text, 3, '0'), 2, title,
  case when threshold = 1 then 'Gana un partido confirmado contra otro equipo.'
    else 'Alcanza ' || threshold::text || ' victorias contra otros equipos.' end,
  'team', 'external', 'wins', 'TEAM_WINS', parameters, threshold, rarity,
  repeatable, 'none', true, 'achievement_catalog_v2', 'team.external.wins',
  20 + threshold, 'victory', case when threshold = 1 then 'Primera victoria' end,
  rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from milestones;

with scopes(scope) as (values ('internal'), ('external')),
tiers(goals, title, rarity, priority) as (
  values
    (2, 'Dos goles', 'common', 35), (3, 'Tres goles', 'uncommon', 34),
    (4, 'Cuatro goles', 'uncommon', 33), (5, 'Manita', 'rare', 32),
    (6, 'Seis o más', 'epic', 31)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition
)
select 'team.' || scope || '.match_goals.' || lpad(goals::text, 3, '0'),
  2, title, case when goals = 6 then 'El equipo marca seis o más goles en un partido confirmado.'
    else 'El equipo marca exactamente ' || goals::text || ' goles en un partido confirmado.' end,
  'team', scope, 'match_goals', 'TEAM_GOALS',
  case when goals = 6 then jsonb_build_object('ruleKind', 'team_match_goals', 'goalsMinimum', goals)
    else jsonb_build_object('ruleKind', 'team_match_goals', 'goalsExact', goals) end,
  goals, rarity, true, 'none', true, 'achievement_catalog_v2',
  'team.' || scope || '.match_goals', priority, 'team_goals', rarity, 1,
  'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from scopes cross join tiers;

insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  first_time_variant, box_rarity, reward_pool_version, animation_key,
  presentation_key, activation_server_sequence, catalog_disposition
)
values
  ('team.external.clean_sheets.001', 2, 'Portería a cero', 'El rival no marca; también cuenta un empate 0-0.', 'team', 'external', 'special', 'TEAM_CLEAN_SHEETS', '{"ruleKind":"team_match_clean_sheet","firstTitle":"Primera portería a cero","repeatTitle":"Portería a cero"}', 1, 'common', true, 'none', true, 'achievement_catalog_v2', 'team.external.clean_sheets', 41, 'clean_sheet', 'Primera portería a cero', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('team.external.big_wins.001', 2, 'Goleada', 'Gana un partido externo por cuatro o más goles de diferencia.', 'team', 'external', 'special', 'TEAM_BIG_WINS', '{"ruleKind":"team_match_big_win","firstTitle":"Primera goleada","repeatTitle":"Goleada","goalDifferenceMinimum":4}', 1, 'uncommon', true, 'none', true, 'achievement_catalog_v2', 'team.external.big_wins', 42, 'team_goals', 'Primera goleada', 'uncommon', 1, 'reward_box_blue', 'box.uncommon', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('team.external.close_wins.001', 2, 'Por la mínima', 'Gana un partido externo por exactamente un gol de diferencia.', 'team', 'external', 'special', 'TEAM_CLOSE_WINS', '{"ruleKind":"team_match_close_win","firstTitle":"Primera victoria por la mínima","repeatTitle":"Por la mínima"}', 1, 'common', true, 'none', true, 'achievement_catalog_v2', 'team.external.close_wins', 43, 'victory', 'Primera victoria por la mínima', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('team.internal.big_wins.001', 2, 'Partido desatado', 'El partido interno termina con cuatro o más goles de diferencia.', 'team', 'internal', 'special', 'TEAM_BIG_WINS', '{"ruleKind":"team_match_big_win","firstTitle":"Primer partido desatado","repeatTitle":"Partido desatado","goalDifferenceMinimum":4}', 1, 'uncommon', true, 'none', true, 'achievement_catalog_v2', 'team.internal.big_wins', 44, 'team_goals', 'Primer partido desatado', 'uncommon', 1, 'reward_box_blue', 'box.uncommon', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'),
  ('team.internal.close_wins.001', 2, 'Hasta el final', 'El partido interno se decide por exactamente un gol.', 'team', 'internal', 'special', 'TEAM_CLOSE_WINS', '{"ruleKind":"team_match_close_win","firstTitle":"Primer final ajustado","repeatTitle":"Hasta el final"}', 1, 'common', true, 'none', true, 'achievement_catalog_v2', 'team.internal.close_wins', 45, 'victory', 'Primer final ajustado', 'common', 1, 'reward_box_blue', 'box.common', (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE');

with streaks(evaluator, family_key, threshold, title, rarity, priority, icon_key) as (
  values
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 3, 'Tres victorias seguidas', 'uncommon', 61, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 5, 'Cinco victorias seguidas', 'rare', 62, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 10, 'Diez victorias seguidas', 'epic', 63, 'winning_streak'),
    ('TEAM_MAX_WIN_STREAK', 'team.external.win_streak', 15, 'Quince victorias seguidas', 'legendary', 64, 'winning_streak'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 3, 'Tres sin perder', 'common', 65, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 5, 'Cinco sin perder', 'uncommon', 66, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 10, 'Diez sin perder', 'rare', 67, 'unbeaten'),
    ('TEAM_MAX_UNBEATEN_STREAK', 'team.external.unbeaten', 20, 'Veinte sin perder', 'legendary', 68, 'unbeaten')
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 2, title,
  case when evaluator = 'TEAM_MAX_WIN_STREAK' then
    'El equipo encadena ' || threshold::text || ' victorias externas.'
  else 'El equipo encadena ' || threshold::text || ' partidos externos sin perder.' end,
  'team', 'external', 'streak', evaluator, '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', family_key, priority,
  icon_key, rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from streaks;

with rivals(evaluator, family_key, threshold, title, rarity, priority) as (
  values
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 3, 'Tres rivales', 'common', 71),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 5, 'Cinco rivales', 'common', 72),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 10, 'Diez rivales', 'uncommon', 73),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 25, 'Veinticinco rivales', 'rare', 74),
    ('TEAM_DISTINCT_OPPONENTS', 'team.external.opponents_played', 50, 'Cincuenta rivales', 'epic', 75),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 3, 'Tres rivales vencidos', 'uncommon', 76),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 5, 'Cinco rivales vencidos', 'uncommon', 77),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 10, 'Diez rivales vencidos', 'rare', 78),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 25, 'Veinticinco rivales vencidos', 'epic', 79),
    ('TEAM_DISTINCT_OPPONENT_WINS', 'team.external.opponents_won', 50, 'Cincuenta rivales vencidos', 'legendary', 80)
)
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition
)
select family_key || '.' || lpad(threshold::text, 3, '0'), 2, title,
  case when evaluator = 'TEAM_DISTINCT_OPPONENTS' then
    'El equipo se enfrenta a ' || threshold::text || ' rivales registrados distintos.'
  else 'El equipo vence a ' || threshold::text || ' rivales registrados distintos.' end,
  'team', 'external', 'opponents', evaluator, '{}'::jsonb, threshold, rarity,
  false, 'none', true, 'achievement_catalog_v2', family_key, priority,
  'rivals', rarity, 1, 'reward_box_blue', 'box.' || rarity,
  (select last_value + 1 from public.pachanga_progression_sequence), 'MIGRATE'
from rivals;

-- Every active collective definition resolves through the existing economy V1.
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
  and definitions.catalog_key = 'achievement_catalog_v2'
  and definitions.subject_type = 'team'
on conflict (economy_version, achievement_key, achievement_version) do update set
  first_box_type = excluded.first_box_type,
  repeat_box_type = excluded.repeat_box_type,
  active = true;

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
  aggregates record;
  fact record;
  current_wins integer := 0;
  max_wins integer := 0;
  current_unbeaten integer := 0;
  max_unbeaten integer := 0;
  saved public.pachanga_team_progression_stats%rowtype;
begin
  if target_match_scope not in ('internal', 'external') then
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
    and facts.match_scope = target_match_scope
    and facts.state = 'active';

  if target_match_scope = 'external' then
    for fact in
      select facts.outcome
      from public.pachanga_progression_match_facts facts
      where facts.group_id = target_group_id
        and facts.match_scope = target_match_scope
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

  perform private.pachanga_progression_bump_group_v1(target_group_id, saved.server_sequence);
  return to_jsonb(saved);
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
    facts.clean_sheet, facts.big_win, facts.close_win
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
      and (definitions.match_scope = target_match_scope
        or (target_subject_type = 'player' and definitions.match_scope = 'all'))
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

alter function public.get_pachanga_progression_snapshot_v1(uuid)
  rename to pachanga_progression_snapshot_pre_catalog_v2;
alter function public.pachanga_progression_snapshot_pre_catalog_v2(uuid)
  set schema private;
revoke all on function private.pachanga_progression_snapshot_pre_catalog_v2(uuid)
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
  current_profile_id uuid;
begin
  base_snapshot := private.pachanga_progression_snapshot_pre_catalog_v2(target_group_id);
  select profiles.id into current_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = auth.uid();

  return base_snapshot || jsonb_build_object(
    'catalogKey', 'achievement_catalog_v2',
    'personalStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope, 'appearances', stats.appearances,
        'wins', stats.wins, 'draws', stats.draws, 'losses', stats.losses,
        'goals', stats.goals, 'braces', stats.braces,
        'hatTricks', stats.hat_tricks, 'pokers', stats.pokers,
        'repokers', stats.repokers, 'doubleHatTricks', stats.double_hat_tricks,
        'currentWinStreak', stats.current_win_streak,
        'maxWinStreak', stats.max_win_streak,
        'currentUnbeatenStreak', stats.current_unbeaten_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'distinctOpponents', stats.distinct_opponents,
        'distinctOpponentsWon', stats.distinct_opponents_won,
        'revision', stats.revision, 'updatedAt', stats.updated_at
      ) order by case stats.match_scope when 'all' then 0 when 'internal' then 1 else 2 end)
      from public.pachanga_player_progression_stats stats
      where stats.player_profile_id = current_profile_id
    ), '[]'::jsonb),
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
      ) order by stats.match_scope)
      from public.pachanga_team_progression_stats stats
      where stats.group_id = target_group_id
    ), '[]'::jsonb),
    'personalAchievementCatalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.achievement_key, 'title', catalog.title,
        'description', catalog.description, 'scope', catalog.match_scope,
        'category', catalog.category, 'family', catalog.family_key,
        'rarity', catalog.rarity, 'threshold', catalog.threshold,
        'currentValue', catalog.current_value,
        'occurrenceCount', catalog.occurrence_count,
        'progressPercent', least(100,
          floor(catalog.current_value * 100.0 / catalog.threshold)::integer),
        'unlocked', catalog.occurrence_count > 0,
        'repeatable', catalog.repeatable, 'grantId', catalog.grant_id,
        'awardedAt', catalog.last_achieved_at,
        'firstAchievedAt', catalog.first_achieved_at,
        'lastAchievedAt', catalog.last_achieved_at,
        'rewardKind', 'none', 'rewardKey', null,
        'displayPriority', catalog.display_priority,
        'iconKey', catalog.icon_key,
        'shareTitle', catalog.share_title,
        'shareDescription', catalog.share_description,
        'shareTemplateKey', catalog.share_template_key
      ) order by catalog.display_priority, catalog.threshold, catalog.achievement_key)
      from (
        select definitions.*,
          case when definitions.repeatable then coalesce(grants.occurrence_count, 0)
            else private.pachanga_achievement_metric_v1(
              definitions.id, current_profile_id
            ) end as current_value,
          coalesce(grants.occurrence_count, 0) as occurrence_count,
          grants.grant_id, grants.first_achieved_at, grants.last_achieved_at
        from public.pachanga_achievement_definitions definitions
        left join lateral (
          select count(*)::integer as occurrence_count,
            (array_agg(achievement_grants.id order by achievement_grants.occurred_at desc,
              match_facts.server_sequence desc, achievement_grants.id desc))[1] as grant_id,
            min(achievement_grants.occurred_at) as first_achieved_at,
            max(achievement_grants.occurred_at) as last_achieved_at
          from public.pachanga_achievement_grants achievement_grants
          join public.pachanga_achievement_definitions grant_definitions
            on grant_definitions.id = achievement_grants.definition_id
          join public.pachanga_progression_match_facts match_facts
            on match_facts.id = achievement_grants.origin_match_fact_id
          where achievement_grants.subject_type = 'player'
            and achievement_grants.subject_id = current_profile_id
            and achievement_grants.state = 'active'
            and grant_definitions.family_key = definitions.family_key
            and grant_definitions.evaluator_key = definitions.evaluator_key
            and grant_definitions.threshold = definitions.threshold
        ) grants on true
        where definitions.active
          and definitions.catalog_key = 'achievement_catalog_v2'
          and definitions.subject_type = 'player'
      ) catalog
    ), '[]'::jsonb),
    'teamAchievementCatalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', definitions.achievement_key, 'title', definitions.title,
        'description', definitions.description, 'scope', definitions.match_scope,
        'family', definitions.family_key, 'category', definitions.category,
        'rarity', definitions.rarity, 'threshold', definitions.threshold,
        'currentValue', private.pachanga_achievement_metric_v1(
          definitions.id, target_group_id
        ),
        'repeatable', definitions.repeatable,
        'displayPriority', definitions.display_priority,
        'iconKey', definitions.icon_key, 'boxRarity', definitions.box_rarity,
        'rewardPoolVersion', definitions.reward_pool_version,
        'animationKey', definitions.animation_key,
        'presentationKey', definitions.presentation_key
      ) order by definitions.display_priority, definitions.threshold,
        definitions.achievement_key)
      from public.pachanga_achievement_definitions definitions
      where definitions.active
        and definitions.catalog_key = 'achievement_catalog_v2'
        and definitions.subject_type = 'team'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;

comment on function public.get_pachanga_progression_snapshot_v1(uuid) is
  'Canonical achievement catalog V2 read model. Server-calculated and cacheable by revision.';

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
    return saved_grant_id;
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
      'iconKey', definition.icon_key
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
      'rewardEligible', definition.subject_type = 'team'
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
      and definitions.match_scope = target_match_scope
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
    elsif metric < definition.threshold then
      qualifies := false;
    else
      previous_metric := private.pachanga_achievement_metric_without_match_v2(
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

create or replace function private.pachanga_achievement_metric_v1(
  target_definition_id uuid,
  target_subject_id uuid
)
returns integer
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  metric integer := 0;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id;
  if not found then return 0; end if;

  if definition.subject_type = 'team' then
    select case definition.evaluator_key
      when 'TEAM_MATCHES' then stats.matches_played
      when 'TEAM_WINS' then stats.wins
      when 'TEAM_DRAWS' then stats.draws
      when 'TEAM_LOSSES' then stats.losses
      when 'TEAM_GOALS' then stats.goals_for
      when 'TEAM_MAX_WIN_STREAK' then stats.max_win_streak
      when 'TEAM_MAX_UNBEATEN_STREAK' then stats.max_unbeaten_streak
      when 'TEAM_CLEAN_SHEETS' then stats.clean_sheets
      when 'TEAM_BIG_WINS' then stats.big_wins
      when 'TEAM_CLOSE_WINS' then stats.close_wins
      when 'TEAM_SCORELESS_DRAWS' then stats.scoreless_draws
      when 'TEAM_DISTINCT_OPPONENTS' then stats.distinct_opponents
      when 'TEAM_DISTINCT_OPPONENT_WINS' then stats.distinct_opponents_won
      else 0 end
    into metric
    from public.pachanga_team_progression_stats stats
    where stats.group_id = target_subject_id
      and stats.match_scope = definition.match_scope;
  else
    select case definition.evaluator_key
      when 'PLAYER_APPEARANCES' then stats.appearances
      when 'PLAYER_WINS' then stats.wins
      when 'PLAYER_GOALS' then stats.goals
      when 'PLAYER_BRACES' then stats.braces
      when 'PLAYER_HATTRICKS' then stats.hat_tricks
      when 'PLAYER_POKERS' then stats.pokers
      when 'PLAYER_REPOKERS' then stats.repokers
      when 'PLAYER_DOUBLE_HAT_TRICKS' then stats.double_hat_tricks
      when 'PLAYER_MAX_WIN_STREAK' then stats.max_win_streak
      when 'PLAYER_MAX_UNBEATEN_STREAK' then stats.max_unbeaten_streak
      when 'PLAYER_DISTINCT_OPPONENTS' then stats.distinct_opponents
      when 'PLAYER_DISTINCT_OPPONENT_WINS' then stats.distinct_opponents_won
      else 0 end
    into metric
    from public.pachanga_player_progression_stats stats
    where stats.player_profile_id = target_subject_id
      and stats.match_scope = definition.match_scope;
  end if;
  return coalesce(metric, 0);
end;
$$;

create or replace function private.pachanga_achievement_metric_without_match_v2(
  target_definition_id uuid,
  target_subject_id uuid,
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
  where definitions.id = target_definition_id;
  if not found then return 0; end if;

  if definition.subject_type = 'team' then
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
    where facts.group_id = target_subject_id
      and facts.match_scope = definition.match_scope
      and facts.state = 'active'
      and facts.id <> excluded_match_fact_id;

    if definition.evaluator_key in ('TEAM_MAX_WIN_STREAK', 'TEAM_MAX_UNBEATEN_STREAK') then
      for fact in
        select facts.outcome
        from public.pachanga_progression_match_facts facts
        where facts.group_id = target_subject_id
          and facts.match_scope = definition.match_scope
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
  end if;

  select count(*)::integer as appearances,
    count(*) filter (where player_facts.outcome = 'win')::integer as wins,
    coalesce(sum(player_facts.goals), 0)::integer as goals,
    count(*) filter (where player_facts.goals = 2)::integer as braces,
    count(*) filter (where player_facts.goals = 3)::integer as hat_tricks,
    count(*) filter (where player_facts.goals = 4)::integer as pokers,
    count(*) filter (where player_facts.goals = 5)::integer as repokers,
    count(*) filter (where player_facts.goals >= 6)::integer as double_hat_tricks,
    count(distinct match_facts.opponent_group_id)
      filter (where match_facts.opponent_group_id is not null)::integer as distinct_opponents,
    count(distinct match_facts.opponent_group_id)
      filter (where match_facts.opponent_group_id is not null
        and player_facts.outcome = 'win')::integer as distinct_opponents_won
  into aggregates
  from public.pachanga_progression_player_match_facts player_facts
  join public.pachanga_progression_match_facts match_facts
    on match_facts.id = player_facts.match_fact_id
  where player_facts.player_profile_id = target_subject_id
    and player_facts.state = 'active'
    and match_facts.state = 'active'
    and match_facts.id <> excluded_match_fact_id
    and (definition.match_scope = 'all' or match_facts.match_scope = definition.match_scope);

  if definition.evaluator_key in ('PLAYER_MAX_WIN_STREAK', 'PLAYER_MAX_UNBEATEN_STREAK') then
    for fact in
      select player_facts.outcome
      from public.pachanga_progression_player_match_facts player_facts
      join public.pachanga_progression_match_facts match_facts
        on match_facts.id = player_facts.match_fact_id
      where player_facts.player_profile_id = target_subject_id
        and player_facts.state = 'active'
        and match_facts.state = 'active'
        and match_facts.id <> excluded_match_fact_id
        and (definition.match_scope = 'all' or match_facts.match_scope = definition.match_scope)
      order by match_facts.played_at, match_facts.server_sequence, match_facts.id
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
    when 'PLAYER_APPEARANCES' then aggregates.appearances
    when 'PLAYER_WINS' then aggregates.wins
    when 'PLAYER_GOALS' then aggregates.goals
    when 'PLAYER_BRACES' then aggregates.braces
    when 'PLAYER_HATTRICKS' then aggregates.hat_tricks
    when 'PLAYER_POKERS' then aggregates.pokers
    when 'PLAYER_REPOKERS' then aggregates.repokers
    when 'PLAYER_DOUBLE_HAT_TRICKS' then aggregates.double_hat_tricks
    when 'PLAYER_MAX_WIN_STREAK' then max_wins
    when 'PLAYER_MAX_UNBEATEN_STREAK' then max_unbeaten
    when 'PLAYER_DISTINCT_OPPONENTS' then aggregates.distinct_opponents
    when 'PLAYER_DISTINCT_OPPONENT_WINS' then aggregates.distinct_opponents_won
    else 0 end;
end;
$$;

create or replace function private.pachanga_rebuild_player_progression_stats_v1(
  target_player_profile_id uuid,
  target_match_scope text
)
returns jsonb
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
  saved public.pachanga_player_progression_stats%rowtype;
  target_user_id uuid;
begin
  if target_match_scope not in ('all', 'internal', 'external') then
    raise exception 'Invalid progression scope';
  end if;

  select count(*)::integer as appearances,
    count(*) filter (where player_facts.outcome = 'win')::integer as wins,
    count(*) filter (where player_facts.outcome = 'draw')::integer as draws,
    count(*) filter (where player_facts.outcome = 'loss')::integer as losses,
    coalesce(sum(player_facts.goals), 0)::integer as goals,
    count(*) filter (where player_facts.goals = 2)::integer as braces,
    count(*) filter (where player_facts.goals = 3)::integer as hat_tricks,
    count(*) filter (where player_facts.goals = 4)::integer as pokers,
    count(*) filter (where player_facts.goals = 5)::integer as repokers,
    count(*) filter (where player_facts.goals >= 6)::integer as double_hat_tricks,
    count(distinct match_facts.opponent_group_id)
      filter (where match_facts.opponent_group_id is not null)::integer as distinct_opponents,
    count(distinct match_facts.opponent_group_id)
      filter (where match_facts.opponent_group_id is not null
        and player_facts.outcome = 'win')::integer as distinct_opponents_won
  into aggregates
  from public.pachanga_progression_player_match_facts player_facts
  join public.pachanga_progression_match_facts match_facts
    on match_facts.id = player_facts.match_fact_id
  where player_facts.player_profile_id = target_player_profile_id
    and player_facts.state = 'active'
    and match_facts.state = 'active'
    and (target_match_scope = 'all' or match_facts.match_scope = target_match_scope);

  for fact in
    select player_facts.outcome
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = player_facts.match_fact_id
    where player_facts.player_profile_id = target_player_profile_id
      and player_facts.state = 'active'
      and match_facts.state = 'active'
      and (target_match_scope = 'all' or match_facts.match_scope = target_match_scope)
    order by match_facts.played_at, match_facts.server_sequence, match_facts.id
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

  insert into public.pachanga_player_progression_stats(
    player_profile_id, match_scope, appearances, wins, draws, losses,
    goals, braces, hat_tricks, pokers, repokers, double_hat_tricks,
    current_win_streak, max_win_streak, current_unbeaten_streak,
    max_unbeaten_streak, distinct_opponents, distinct_opponents_won
  ) values (
    target_player_profile_id, target_match_scope, aggregates.appearances,
    aggregates.wins, aggregates.draws, aggregates.losses, aggregates.goals,
    aggregates.braces, aggregates.hat_tricks, aggregates.pokers,
    aggregates.repokers, aggregates.double_hat_tricks, current_wins, max_wins,
    current_unbeaten, max_unbeaten, aggregates.distinct_opponents,
    aggregates.distinct_opponents_won
  ) on conflict (player_profile_id, match_scope) do update set
    appearances = excluded.appearances, wins = excluded.wins,
    draws = excluded.draws, losses = excluded.losses, goals = excluded.goals,
    braces = excluded.braces, hat_tricks = excluded.hat_tricks,
    pokers = excluded.pokers, repokers = excluded.repokers,
    double_hat_tricks = excluded.double_hat_tricks,
    current_win_streak = excluded.current_win_streak,
    max_win_streak = excluded.max_win_streak,
    current_unbeaten_streak = excluded.current_unbeaten_streak,
    max_unbeaten_streak = excluded.max_unbeaten_streak,
    distinct_opponents = excluded.distinct_opponents,
    distinct_opponents_won = excluded.distinct_opponents_won,
    revision = public.pachanga_player_progression_stats.revision + 1,
    server_sequence = nextval('public.pachanga_progression_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;

  select profiles.user_id into target_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = target_player_profile_id;
  perform private.pachanga_progression_bump_user_v1(target_user_id, saved.server_sequence);

  if target_match_scope <> 'all' then
    perform private.pachanga_rebuild_player_progression_stats_v1(
      target_player_profile_id, 'all'
    );
  end if;
  return to_jsonb(saved);
end;
$$;

revoke all on function private.pachanga_rebuild_team_progression_stats_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_rebuild_player_progression_stats_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_metric_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_metric_without_match_v2(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_award_achievement_v1(uuid, uuid, uuid, uuid, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_evaluate_achievements_v1(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_repeatable_grant_still_qualifies_v2(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reconcile_subject_achievements_v1(text, uuid, text, text)
  from public, anon, authenticated;
