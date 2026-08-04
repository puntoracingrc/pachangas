-- Pachangas IQ achievements and deterministic rewards MVP.
-- Progression is derived only from canonical internal snapshots and official external results.

create sequence if not exists public.pachanga_progression_sequence;
revoke all on sequence public.pachanga_progression_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_progression_sequence to service_role;

create table if not exists public.pachanga_cosmetic_catalog (
  cosmetic_key text primary key,
  version integer not null default 1,
  family text not null,
  display_name text not null,
  description text not null,
  rarity text not null,
  availability text not null,
  render_contract jsonb not null default '{}'::jsonb,
  layer_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  check (char_length(cosmetic_key) between 3 and 120),
  check (version >= 1),
  check (family in ('shape', 'color', 'pattern', 'border', 'symbol', 'adornment', 'palette', 'effect')),
  check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  check (availability in ('base', 'achievement')),
  check (jsonb_typeof(render_contract) = 'object')
);

create table if not exists public.pachanga_achievement_definitions (
  id uuid primary key default gen_random_uuid(),
  achievement_key text not null,
  version integer not null default 1,
  title text not null,
  description text not null,
  subject_type text not null,
  match_scope text not null,
  category text not null,
  evaluator_key text not null,
  parameters jsonb not null default '{}'::jsonb,
  threshold integer not null,
  rarity text not null,
  repeatable boolean not null default false,
  reward_kind text not null default 'none',
  reward_key text,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  unique (achievement_key, version),
  check (char_length(achievement_key) between 3 and 160),
  check (version >= 1),
  check (subject_type in ('team', 'player')),
  check (match_scope in ('internal', 'external')),
  check (evaluator_key in (
    'TEAM_MATCHES', 'TEAM_WINS', 'TEAM_DRAWS', 'TEAM_LOSSES', 'TEAM_GOALS',
    'TEAM_MAX_WIN_STREAK', 'TEAM_MAX_UNBEATEN_STREAK', 'TEAM_CLEAN_SHEETS',
    'TEAM_BIG_WINS', 'TEAM_CLOSE_WINS', 'TEAM_SCORELESS_DRAWS',
    'TEAM_DISTINCT_OPPONENTS', 'PLAYER_APPEARANCES', 'PLAYER_WINS',
    'PLAYER_GOALS', 'PLAYER_BRACES', 'PLAYER_HATTRICKS'
  )),
  check (jsonb_typeof(parameters) = 'object'),
  check (threshold >= 1),
  check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  check (reward_kind in ('none', 'team_cosmetic', 'player_badge', 'player_title')),
  check ((reward_kind = 'none' and reward_key is null) or (reward_kind <> 'none' and reward_key is not null))
);

create unique index if not exists pachanga_achievement_active_key_idx
  on public.pachanga_achievement_definitions(achievement_key)
  where active;
create index if not exists pachanga_achievement_scope_idx
  on public.pachanga_achievement_definitions(subject_type, match_scope, active, threshold);

create table if not exists public.pachanga_progression_match_facts (
  id uuid primary key default gen_random_uuid(),
  source_kind text not null,
  source_match_id text not null,
  source_revision bigint not null,
  source_event_id uuid,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  opponent_group_id uuid references public.pachanga_groups(id) on delete restrict,
  match_scope text not null,
  outcome text not null,
  goals_for integer not null,
  goals_against integer not null,
  clean_sheet boolean not null,
  close_win boolean not null,
  big_win boolean not null,
  scoreless_draw boolean not null,
  player_facts_complete boolean not null default true,
  source_snapshot jsonb not null,
  state text not null default 'active',
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  played_at timestamptz not null,
  applied_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revoked_reason text,
  unique (source_kind, source_match_id, group_id, source_revision),
  check (source_kind in ('internal_snapshot', 'external_result')),
  check (source_revision >= 1),
  check (match_scope in ('internal', 'external')),
  check (outcome in ('social', 'win', 'draw', 'loss')),
  check (goals_for >= 0 and goals_against >= 0),
  check (jsonb_typeof(source_snapshot) = 'object'),
  check (state in ('active', 'revoked'))
);

create unique index if not exists pachanga_progression_active_match_fact_idx
  on public.pachanga_progression_match_facts(source_kind, source_match_id, group_id)
  where state = 'active';
create unique index if not exists pachanga_progression_match_fact_sequence_idx
  on public.pachanga_progression_match_facts(server_sequence, group_id);
create index if not exists pachanga_progression_match_fact_group_idx
  on public.pachanga_progression_match_facts(group_id, match_scope, played_at, server_sequence, id)
  where state = 'active';

create table if not exists public.pachanga_progression_player_match_facts (
  id uuid primary key default gen_random_uuid(),
  match_fact_id uuid not null references public.pachanga_progression_match_facts(id) on delete restrict,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  local_player_id text not null,
  team_side text not null,
  outcome text not null,
  goals integer not null default 0,
  card_snapshot jsonb not null default '{}'::jsonb,
  state text not null default 'active',
  created_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  unique (match_fact_id, local_player_id),
  check (team_side in ('A', 'B', 'team')),
  check (outcome in ('win', 'draw', 'loss')),
  check (goals >= 0),
  check (jsonb_typeof(card_snapshot) = 'object'),
  check (state in ('active', 'revoked'))
);

create index if not exists pachanga_progression_player_fact_profile_idx
  on public.pachanga_progression_player_match_facts(player_profile_id, state, match_fact_id);

create table if not exists public.pachanga_team_progression_stats (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_scope text not null,
  matches_played integer not null default 0,
  wins integer not null default 0,
  draws integer not null default 0,
  losses integer not null default 0,
  goals_for integer not null default 0,
  goals_against integer not null default 0,
  clean_sheets integer not null default 0,
  close_wins integer not null default 0,
  big_wins integer not null default 0,
  scoreless_draws integer not null default 0,
  distinct_opponents integer not null default 0,
  current_win_streak integer not null default 0,
  max_win_streak integer not null default 0,
  current_unbeaten_streak integer not null default 0,
  max_unbeaten_streak integer not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (group_id, match_scope),
  check (match_scope in ('internal', 'external')),
  check (least(matches_played, wins, draws, losses, goals_for, goals_against,
    clean_sheets, close_wins, big_wins, scoreless_draws, distinct_opponents,
    current_win_streak, max_win_streak, current_unbeaten_streak, max_unbeaten_streak) >= 0),
  check (revision >= 1)
);

create table if not exists public.pachanga_player_progression_stats (
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete cascade,
  match_scope text not null,
  appearances integer not null default 0,
  wins integer not null default 0,
  draws integer not null default 0,
  losses integer not null default 0,
  goals integer not null default 0,
  braces integer not null default 0,
  hat_tricks integer not null default 0,
  current_win_streak integer not null default 0,
  max_win_streak integer not null default 0,
  current_unbeaten_streak integer not null default 0,
  max_unbeaten_streak integer not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (player_profile_id, match_scope),
  check (match_scope in ('internal', 'external')),
  check (least(appearances, wins, draws, losses, goals, braces, hat_tricks,
    current_win_streak, max_win_streak, current_unbeaten_streak, max_unbeaten_streak) >= 0),
  check (revision >= 1)
);

create table if not exists public.pachanga_achievement_grants (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.pachanga_achievement_definitions(id) on delete restrict,
  subject_type text not null,
  subject_id uuid not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  origin_match_fact_id uuid not null references public.pachanga_progression_match_facts(id) on delete restrict,
  metric_value integer not null,
  operation_id uuid not null unique,
  state text not null default 'active',
  awarded_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revoked_reason text,
  check (subject_type in ('team', 'player')),
  check (metric_value >= 0),
  check (state in ('active', 'revoked'))
);

create unique index if not exists pachanga_achievement_active_grant_idx
  on public.pachanga_achievement_grants(subject_type, subject_id, definition_id)
  where state = 'active';
create index if not exists pachanga_achievement_grant_group_idx
  on public.pachanga_achievement_grants(group_id, state, awarded_at desc, id desc);

create table if not exists public.pachanga_team_cosmetic_inventory (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  cosmetic_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  source_grant_id uuid not null references public.pachanga_achievement_grants(id) on delete restrict,
  state text not null default 'unlocked',
  unlocked_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  revision bigint not null default 1,
  primary key (group_id, cosmetic_key),
  check (state in ('unlocked', 'revoked')),
  check (revision >= 1)
);

create table if not exists public.pachanga_player_reward_inventory (
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete cascade,
  reward_kind text not null,
  reward_key text not null,
  source_grant_id uuid not null references public.pachanga_achievement_grants(id) on delete restrict,
  state text not null default 'unlocked',
  unlocked_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  primary key (player_profile_id, reward_kind, reward_key),
  check (reward_kind in ('player_badge', 'player_title')),
  check (state in ('unlocked', 'revoked'))
);

create table if not exists public.pachanga_reward_grants (
  id uuid primary key default gen_random_uuid(),
  achievement_grant_id uuid not null unique references public.pachanga_achievement_grants(id) on delete restrict,
  reward_kind text not null,
  reward_key text not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  payload jsonb not null default '{}'::jsonb,
  state text not null default 'active',
  granted_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  check (reward_kind in ('team_cosmetic', 'player_badge', 'player_title')),
  check (jsonb_typeof(payload) = 'object'),
  check (state in ('active', 'revoked'))
);

create table if not exists public.pachanga_reward_recipients (
  reward_grant_id uuid not null references public.pachanga_reward_grants(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  member_role_snapshot text,
  member_name_snapshot text,
  status text not null default 'pending',
  revision bigint not null default 1,
  snapshot_at timestamptz not null default clock_timestamp(),
  opened_at timestamptz,
  revoked_at timestamptz,
  primary key (reward_grant_id, user_id),
  check (status in ('pending', 'opened', 'skipped', 'revoked')),
  check (revision >= 1)
);

create table if not exists public.pachanga_progression_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  event_type text not null,
  group_id uuid references public.pachanga_groups(id) on delete restrict,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  match_fact_id uuid references public.pachanga_progression_match_facts(id) on delete restrict,
  achievement_grant_id uuid references public.pachanga_achievement_grants(id) on delete restrict,
  reward_grant_id uuid references public.pachanga_reward_grants(id) on delete restrict,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (event_type in (
    'match_progression_applied', 'match_progression_revoked', 'achievement_awarded',
    'achievement_revoked', 'reward_granted', 'reward_opened', 'reward_revoked'
  )),
  check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists pachanga_progression_events_sequence_idx
  on public.pachanga_progression_events(server_sequence);
create index if not exists pachanga_progression_events_group_idx
  on public.pachanga_progression_events(group_id, server_sequence desc, id desc);

create table if not exists public.pachanga_progression_group_state (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1)
);

create table if not exists public.pachanga_progression_user_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1)
);

create table if not exists public.pachanga_reward_open_receipts (
  operation_id uuid primary key,
  reward_grant_id uuid not null references public.pachanga_reward_grants(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  expected_revision bigint not null,
  result_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (expected_revision >= 1 and result_revision >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

alter table public.pachanga_cosmetic_catalog enable row level security;
alter table public.pachanga_achievement_definitions enable row level security;
alter table public.pachanga_progression_match_facts enable row level security;
alter table public.pachanga_progression_player_match_facts enable row level security;
alter table public.pachanga_team_progression_stats enable row level security;
alter table public.pachanga_player_progression_stats enable row level security;
alter table public.pachanga_achievement_grants enable row level security;
alter table public.pachanga_team_cosmetic_inventory enable row level security;
alter table public.pachanga_player_reward_inventory enable row level security;
alter table public.pachanga_reward_grants enable row level security;
alter table public.pachanga_reward_recipients enable row level security;
alter table public.pachanga_progression_events enable row level security;
alter table public.pachanga_progression_group_state enable row level security;
alter table public.pachanga_progression_user_state enable row level security;
alter table public.pachanga_reward_open_receipts enable row level security;

insert into public.pachanga_cosmetic_catalog(
  cosmetic_key, family, display_name, description, rarity, availability, render_contract, layer_order
) values
  ('shape.classic', 'shape', 'Clásico', 'Escudo clásico de base.', 'common', 'base', '{"shape":"classic"}', 10),
  ('shape.rounded', 'shape', 'Redondeado', 'Escudo redondeado de base.', 'common', 'base', '{"shape":"rounded"}', 10),
  ('shape.pointed', 'shape', 'Punta', 'Escudo terminado en punta.', 'common', 'base', '{"shape":"pointed"}', 10),
  ('shape.circle', 'shape', 'Circular', 'Emblema circular de base.', 'common', 'base', '{"shape":"circle"}', 10),
  ('shape.banner', 'shape', 'Estandarte', 'Escudo con perfil de estandarte.', 'common', 'base', '{"shape":"banner"}', 10),
  ('color.black', 'color', 'Negro', 'Color básico.', 'common', 'base', '{"hex":"#111827"}', 20),
  ('color.white', 'color', 'Blanco', 'Color básico.', 'common', 'base', '{"hex":"#F8FAFC"}', 20),
  ('color.green', 'color', 'Verde', 'Color básico.', 'common', 'base', '{"hex":"#16A34A"}', 20),
  ('color.blue', 'color', 'Azul', 'Color básico.', 'common', 'base', '{"hex":"#2563EB"}', 20),
  ('color.red', 'color', 'Rojo', 'Color básico.', 'common', 'base', '{"hex":"#DC2626"}', 20),
  ('color.yellow', 'color', 'Amarillo', 'Color básico.', 'common', 'base', '{"hex":"#FACC15"}', 20),
  ('color.orange', 'color', 'Naranja', 'Color básico.', 'common', 'base', '{"hex":"#F97316"}', 20),
  ('color.purple', 'color', 'Morado', 'Color básico.', 'common', 'base', '{"hex":"#9333EA"}', 20),
  ('pattern.solid', 'pattern', 'Liso', 'Fondo liso de base.', 'common', 'base', '{"pattern":"solid"}', 30),
  ('border.standard', 'border', 'Estándar', 'Borde sencillo de base.', 'common', 'base', '{"border":"standard"}', 50),
  ('pattern.stripes', 'pattern', 'Franjas', 'Franjas verticales para el escudo.', 'common', 'achievement', '{"pattern":"stripes"}', 30),
  ('pattern.diagonal', 'pattern', 'Diagonal', 'División diagonal del escudo.', 'uncommon', 'achievement', '{"pattern":"diagonal"}', 30),
  ('pattern.halves', 'pattern', 'Mitades', 'Escudo dividido en dos mitades.', 'uncommon', 'achievement', '{"pattern":"halves"}', 30),
  ('border.double', 'border', 'Doble', 'Borde doble de competición.', 'uncommon', 'achievement', '{"border":"double"}', 50),
  ('border.silver', 'border', 'Plata', 'Borde metálico plateado.', 'rare', 'achievement', '{"border":"silver"}', 50),
  ('border.gold', 'border', 'Oro', 'Borde metálico dorado.', 'epic', 'achievement', '{"border":"gold"}', 50),
  ('border.laurel', 'border', 'Laureles', 'Laureles alrededor del escudo.', 'rare', 'achievement', '{"border":"laurel"}', 50),
  ('symbol.ball', 'symbol', 'Balón', 'Balón central.', 'common', 'achievement', '{"symbol":"ball"}', 40),
  ('symbol.lightning', 'symbol', 'Rayo', 'Rayo central.', 'uncommon', 'achievement', '{"symbol":"lightning"}', 40),
  ('symbol.crown', 'symbol', 'Corona', 'Corona central.', 'epic', 'achievement', '{"symbol":"crown"}', 40),
  ('adornment.star', 'adornment', 'Estrella', 'Estrella superior.', 'rare', 'achievement', '{"adornment":"star"}', 60),
  ('adornment.ribbon', 'adornment', 'Cinta', 'Cinta inferior.', 'uncommon', 'achievement', '{"adornment":"ribbon"}', 60),
  ('palette.silver', 'palette', 'Paleta plata', 'Paleta especial plateada.', 'rare', 'achievement', '{"palette":["#E5E7EB","#475569"]}', 20),
  ('palette.gold', 'palette', 'Paleta oro', 'Paleta especial dorada.', 'epic', 'achievement', '{"palette":["#FDE68A","#B45309"]}', 20),
  ('effect.glow', 'effect', 'Brillo', 'Brillo suave de presentación.', 'legendary', 'achievement', '{"effect":"glow"}', 70)
on conflict (cosmetic_key) do nothing;

insert into public.pachanga_achievement_definitions(
  achievement_key, title, description, subject_type, match_scope, category,
  evaluator_key, threshold, rarity, reward_kind, reward_key
) values
  ('team.internal.matches.001', 'El grupo echa a rodar', 'Completa el primer partido interno.', 'team', 'internal', 'matches', 'TEAM_MATCHES', 1, 'common', 'team_cosmetic', 'pattern.stripes'),
  ('team.internal.matches.005', 'Cinco quedadas', 'Completa cinco partidos internos.', 'team', 'internal', 'matches', 'TEAM_MATCHES', 5, 'uncommon', 'team_cosmetic', 'border.double'),
  ('team.internal.matches.010', 'Vestuario estable', 'Completa diez partidos internos.', 'team', 'internal', 'matches', 'TEAM_MATCHES', 10, 'uncommon', 'team_cosmetic', 'symbol.ball'),
  ('team.internal.matches.025', 'Tradición de jueves', 'Completa veinticinco partidos internos.', 'team', 'internal', 'matches', 'TEAM_MATCHES', 25, 'rare', 'team_cosmetic', 'pattern.halves'),
  ('team.internal.matches.050', 'Medio centenar', 'Completa cincuenta partidos internos.', 'team', 'internal', 'matches', 'TEAM_MATCHES', 50, 'epic', 'team_cosmetic', 'palette.silver'),
  ('team.internal.goals.025', 'Veinticinco goles compartidos', 'Alcanza veinticinco goles en partidos internos.', 'team', 'internal', 'goals', 'TEAM_GOALS', 25, 'uncommon', 'team_cosmetic', 'pattern.diagonal'),
  ('team.internal.goals.100', 'Centenario goleador', 'Alcanza cien goles en partidos internos.', 'team', 'internal', 'goals', 'TEAM_GOALS', 100, 'rare', 'team_cosmetic', 'border.silver'),
  ('team.internal.scoreless.001', 'Cerrojo amistoso', 'Completa un partido interno 0-0.', 'team', 'internal', 'special', 'TEAM_SCORELESS_DRAWS', 1, 'common', 'none', null),
  ('team.internal.big_wins.001', 'Partido desatado', 'Completa un partido interno con cuatro goles de diferencia.', 'team', 'internal', 'special', 'TEAM_BIG_WINS', 1, 'uncommon', 'team_cosmetic', 'adornment.ribbon'),
  ('team.internal.close_wins.001', 'Hasta el final', 'Completa un partido interno decidido por un gol.', 'team', 'internal', 'special', 'TEAM_CLOSE_WINS', 1, 'common', 'none', null),

  ('team.external.matches.001', 'Debut entre equipos', 'Completa el primer partido contra un rival.', 'team', 'external', 'matches', 'TEAM_MATCHES', 1, 'common', 'team_cosmetic', 'symbol.lightning'),
  ('team.external.matches.005', 'Agenda rival', 'Completa cinco partidos contra rivales.', 'team', 'external', 'matches', 'TEAM_MATCHES', 5, 'uncommon', 'team_cosmetic', 'border.laurel'),
  ('team.external.matches.010', 'Diez noches de competición', 'Completa diez partidos contra rivales.', 'team', 'external', 'matches', 'TEAM_MATCHES', 10, 'rare', 'team_cosmetic', 'palette.gold'),
  ('team.external.matches.025', 'Equipo de largo recorrido', 'Completa veinticinco partidos contra rivales.', 'team', 'external', 'matches', 'TEAM_MATCHES', 25, 'epic', 'team_cosmetic', 'effect.glow'),
  ('team.external.wins.001', 'Primera victoria', 'Gana por primera vez a otro equipo.', 'team', 'external', 'wins', 'TEAM_WINS', 1, 'common', 'team_cosmetic', 'adornment.star'),
  ('team.external.wins.005', 'Cinco victorias', 'Alcanza cinco victorias externas.', 'team', 'external', 'wins', 'TEAM_WINS', 5, 'uncommon', 'team_cosmetic', 'border.gold'),
  ('team.external.wins.010', 'Doble dígito', 'Alcanza diez victorias externas.', 'team', 'external', 'wins', 'TEAM_WINS', 10, 'rare', 'team_cosmetic', 'symbol.crown'),
  ('team.external.wins.025', 'Veinticinco triunfos', 'Alcanza veinticinco victorias externas.', 'team', 'external', 'wins', 'TEAM_WINS', 25, 'epic', 'none', null),
  ('team.external.win_streak.003', 'Tres seguidas', 'Encadena tres victorias externas.', 'team', 'external', 'streak', 'TEAM_MAX_WIN_STREAK', 3, 'uncommon', 'none', null),
  ('team.external.win_streak.005', 'Racha de cinco', 'Encadena cinco victorias externas.', 'team', 'external', 'streak', 'TEAM_MAX_WIN_STREAK', 5, 'rare', 'none', null),
  ('team.external.unbeaten.005', 'Cinco sin perder', 'Encadena cinco partidos externos sin perder.', 'team', 'external', 'streak', 'TEAM_MAX_UNBEATEN_STREAK', 5, 'uncommon', 'none', null),
  ('team.external.unbeaten.010', 'Diez invicto', 'Encadena diez partidos externos sin perder.', 'team', 'external', 'streak', 'TEAM_MAX_UNBEATEN_STREAK', 10, 'epic', 'none', null),
  ('team.external.clean_sheets.001', 'Primera portería a cero', 'Deja al rival sin marcar.', 'team', 'external', 'special', 'TEAM_CLEAN_SHEETS', 1, 'common', 'none', null),
  ('team.external.clean_sheets.005', 'Cinco cerrojos', 'Suma cinco porterías a cero externas.', 'team', 'external', 'special', 'TEAM_CLEAN_SHEETS', 5, 'rare', 'none', null),
  ('team.external.big_wins.001', 'Goleada', 'Gana un partido externo por cuatro o más goles.', 'team', 'external', 'special', 'TEAM_BIG_WINS', 1, 'uncommon', 'none', null),
  ('team.external.big_wins.005', 'Autoridad', 'Suma cinco goleadas externas.', 'team', 'external', 'special', 'TEAM_BIG_WINS', 5, 'rare', 'none', null),
  ('team.external.close_wins.001', 'Por la mínima', 'Gana un partido externo por un gol.', 'team', 'external', 'special', 'TEAM_CLOSE_WINS', 1, 'common', 'none', null),
  ('team.external.goals.025', 'Veinticinco contra rivales', 'Alcanza veinticinco goles externos.', 'team', 'external', 'goals', 'TEAM_GOALS', 25, 'uncommon', 'none', null),
  ('team.external.opponents.003', 'Tres rivales', 'Juega contra tres equipos distintos.', 'team', 'external', 'opponents', 'TEAM_DISTINCT_OPPONENTS', 3, 'uncommon', 'none', null),
  ('team.external.opponents.010', 'Circuito abierto', 'Juega contra diez equipos distintos.', 'team', 'external', 'opponents', 'TEAM_DISTINCT_OPPONENTS', 10, 'rare', 'none', null),

  ('player.internal.matches.001', 'Primera pachanga', 'Participa en un partido interno.', 'player', 'internal', 'matches', 'PLAYER_APPEARANCES', 1, 'common', 'player_badge', 'badge.internal.first_match'),
  ('player.internal.wins.001', 'Primera victoria interna', 'Gana un partido interno.', 'player', 'internal', 'wins', 'PLAYER_WINS', 1, 'common', 'player_badge', 'badge.internal.first_win'),
  ('player.internal.goals.001', 'Primer gol interno', 'Marca un gol en un partido interno.', 'player', 'internal', 'goals', 'PLAYER_GOALS', 1, 'common', 'player_badge', 'badge.internal.first_goal'),
  ('player.internal.goals.010', 'Diez goles internos', 'Alcanza diez goles internos.', 'player', 'internal', 'goals', 'PLAYER_GOALS', 10, 'uncommon', 'player_badge', 'badge.internal.ten_goals'),
  ('player.internal.braces.001', 'Doblete interno', 'Marca al menos dos goles en un partido interno.', 'player', 'internal', 'goals', 'PLAYER_BRACES', 1, 'uncommon', 'player_badge', 'badge.internal.brace'),
  ('player.internal.hat_tricks.001', 'Hat-trick interno', 'Marca al menos tres goles en un partido interno.', 'player', 'internal', 'goals', 'PLAYER_HATTRICKS', 1, 'rare', 'player_badge', 'badge.internal.hat_trick'),
  ('player.external.matches.001', 'Debut exterior', 'Participa en un partido externo confirmado.', 'player', 'external', 'matches', 'PLAYER_APPEARANCES', 1, 'common', 'player_badge', 'badge.external.first_match'),
  ('player.external.wins.001', 'Victoria exterior', 'Gana un partido externo que has disputado.', 'player', 'external', 'wins', 'PLAYER_WINS', 1, 'common', 'player_badge', 'badge.external.first_win'),
  ('player.external.goals.001', 'Primer gol exterior', 'Marca un gol externo confirmado.', 'player', 'external', 'goals', 'PLAYER_GOALS', 1, 'common', 'player_badge', 'badge.external.first_goal'),
  ('player.external.goals.010', 'Diez goles exteriores', 'Alcanza diez goles externos confirmados.', 'player', 'external', 'goals', 'PLAYER_GOALS', 10, 'uncommon', 'player_badge', 'badge.external.ten_goals'),
  ('player.external.braces.001', 'Doblete exterior', 'Marca al menos dos goles en un partido externo.', 'player', 'external', 'goals', 'PLAYER_BRACES', 1, 'uncommon', 'player_badge', 'badge.external.brace'),
  ('player.external.hat_tricks.001', 'Hat-trick exterior', 'Marca al menos tres goles en un partido externo.', 'player', 'external', 'goals', 'PLAYER_HATTRICKS', 1, 'rare', 'player_badge', 'badge.external.hat_trick')
on conflict (achievement_key, version) do nothing;

revoke all on table public.pachanga_cosmetic_catalog from public, anon, authenticated;
revoke all on table public.pachanga_achievement_definitions from public, anon, authenticated;
revoke all on table public.pachanga_progression_match_facts from public, anon, authenticated;
revoke all on table public.pachanga_progression_player_match_facts from public, anon, authenticated;
revoke all on table public.pachanga_team_progression_stats from public, anon, authenticated;
revoke all on table public.pachanga_player_progression_stats from public, anon, authenticated;
revoke all on table public.pachanga_achievement_grants from public, anon, authenticated;
revoke all on table public.pachanga_team_cosmetic_inventory from public, anon, authenticated;
revoke all on table public.pachanga_player_reward_inventory from public, anon, authenticated;
revoke all on table public.pachanga_reward_grants from public, anon, authenticated;
revoke all on table public.pachanga_reward_recipients from public, anon, authenticated;
revoke all on table public.pachanga_progression_events from public, anon, authenticated;
revoke all on table public.pachanga_progression_group_state from public, anon, authenticated;
revoke all on table public.pachanga_progression_user_state from public, anon, authenticated;
revoke all on table public.pachanga_reward_open_receipts from public, anon, authenticated;

grant select on table public.pachanga_cosmetic_catalog to authenticated;
grant select on table public.pachanga_achievement_definitions to authenticated;
grant select on table public.pachanga_progression_match_facts to authenticated;
grant select on table public.pachanga_progression_player_match_facts to authenticated;
grant select on table public.pachanga_team_progression_stats to authenticated;
grant select on table public.pachanga_player_progression_stats to authenticated;
grant select on table public.pachanga_achievement_grants to authenticated;
grant select on table public.pachanga_team_cosmetic_inventory to authenticated;
grant select on table public.pachanga_player_reward_inventory to authenticated;
grant select on table public.pachanga_reward_grants to authenticated;
grant select on table public.pachanga_reward_recipients to authenticated;
grant select on table public.pachanga_progression_events to authenticated;
grant select on table public.pachanga_progression_group_state to authenticated;
grant select on table public.pachanga_progression_user_state to authenticated;
grant select on table public.pachanga_reward_open_receipts to authenticated;

grant all on table public.pachanga_cosmetic_catalog to service_role;
grant all on table public.pachanga_achievement_definitions to service_role;
grant all on table public.pachanga_progression_match_facts to service_role;
grant all on table public.pachanga_progression_player_match_facts to service_role;
grant all on table public.pachanga_team_progression_stats to service_role;
grant all on table public.pachanga_player_progression_stats to service_role;
grant all on table public.pachanga_achievement_grants to service_role;
grant all on table public.pachanga_team_cosmetic_inventory to service_role;
grant all on table public.pachanga_player_reward_inventory to service_role;
grant all on table public.pachanga_reward_grants to service_role;
grant all on table public.pachanga_reward_recipients to service_role;
grant all on table public.pachanga_progression_events to service_role;
grant all on table public.pachanga_progression_group_state to service_role;
grant all on table public.pachanga_progression_user_state to service_role;
grant all on table public.pachanga_reward_open_receipts to service_role;

create or replace function private.pachanga_can_read_progression_group_v1(target_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select public.is_registered_pachanga_user()
    and public.is_pachanga_group_member(target_group_id);
$$;

create or replace function private.pachanga_can_read_player_progression_v1(target_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.pachanga_player_profiles profiles
    where profiles.id = target_profile_id
      and (
        profiles.user_id = auth.uid()
        or exists (
          select 1
          from public.pachanga_group_members own_membership
          join public.pachanga_group_members target_membership
            on target_membership.group_id = own_membership.group_id
          where own_membership.user_id = auth.uid()
            and target_membership.user_id = profiles.user_id
        )
      )
  );
$$;

revoke all on function private.pachanga_can_read_progression_group_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_can_read_player_progression_v1(uuid)
  from public, anon, authenticated;

create policy "Registered users read achievement definitions"
on public.pachanga_achievement_definitions for select to authenticated
using (public.is_registered_pachanga_user());

create policy "Registered users read cosmetic catalog"
on public.pachanga_cosmetic_catalog for select to authenticated
using (public.is_registered_pachanga_user());

create policy "Members read team match facts"
on public.pachanga_progression_match_facts for select to authenticated
using (private.pachanga_can_read_progression_group_v1(group_id));

create policy "Members read player match facts"
on public.pachanga_progression_player_match_facts for select to authenticated
using (private.pachanga_can_read_progression_group_v1(group_id));

create policy "Members read team progression stats"
on public.pachanga_team_progression_stats for select to authenticated
using (private.pachanga_can_read_progression_group_v1(group_id));

create policy "Shared players read player progression stats"
on public.pachanga_player_progression_stats for select to authenticated
using (private.pachanga_can_read_player_progression_v1(player_profile_id));

create policy "Members read team and shared player achievements"
on public.pachanga_achievement_grants for select to authenticated
using (
  private.pachanga_can_read_progression_group_v1(group_id)
  or (subject_type = 'player' and private.pachanga_can_read_player_progression_v1(subject_id))
);

create policy "Members read team cosmetic inventory"
on public.pachanga_team_cosmetic_inventory for select to authenticated
using (private.pachanga_can_read_progression_group_v1(group_id));

create policy "Shared players read personal reward inventory"
on public.pachanga_player_reward_inventory for select to authenticated
using (private.pachanga_can_read_player_progression_v1(player_profile_id));

create policy "Members read team and own reward grants"
on public.pachanga_reward_grants for select to authenticated
using (
  private.pachanga_can_read_progression_group_v1(group_id)
  or (player_profile_id is not null and private.pachanga_can_read_player_progression_v1(player_profile_id))
);

create policy "Users read their reward openings"
on public.pachanga_reward_recipients for select to authenticated
using (user_id = (select auth.uid()));

create policy "Members read progression events"
on public.pachanga_progression_events for select to authenticated
using (
  (group_id is not null and private.pachanga_can_read_progression_group_v1(group_id))
  or (player_profile_id is not null and private.pachanga_can_read_player_progression_v1(player_profile_id))
);

create policy "Members read progression revisions"
on public.pachanga_progression_group_state for select to authenticated
using (private.pachanga_can_read_progression_group_v1(group_id));

create policy "Users read their progression revision"
on public.pachanga_progression_user_state for select to authenticated
using (user_id = (select auth.uid()));

create policy "Users read their reward receipts"
on public.pachanga_reward_open_receipts for select to authenticated
using (actor_user_id = (select auth.uid()));

create or replace function private.pachanga_progression_bump_group_v1(
  target_group_id uuid,
  target_server_sequence bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  next_sequence bigint := coalesce(target_server_sequence, nextval('public.pachanga_progression_sequence'));
begin
  insert into public.pachanga_progression_group_state(group_id, revision, server_sequence)
  values (target_group_id, 1, next_sequence)
  on conflict (group_id) do update set
    revision = public.pachanga_progression_group_state.revision + 1,
    server_sequence = excluded.server_sequence,
    updated_at = clock_timestamp();
  return next_sequence;
end;
$$;

create or replace function private.pachanga_progression_bump_user_v1(
  target_user_id uuid,
  target_server_sequence bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  next_sequence bigint := coalesce(target_server_sequence, nextval('public.pachanga_progression_sequence'));
begin
  if target_user_id is null then return next_sequence; end if;
  insert into public.pachanga_progression_user_state(user_id, revision, server_sequence)
  values (target_user_id, 1, next_sequence)
  on conflict (user_id) do update set
    revision = public.pachanga_progression_user_state.revision + 1,
    server_sequence = excluded.server_sequence,
    updated_at = clock_timestamp();
  return next_sequence;
end;
$$;

create or replace function private.pachanga_progression_record_event_v1(
  target_operation_id uuid,
  target_event_type text,
  target_group_id uuid default null,
  target_player_profile_id uuid default null,
  target_match_fact_id uuid default null,
  target_achievement_grant_id uuid default null,
  target_reward_grant_id uuid default null,
  target_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved_sequence bigint;
  target_user_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('progression-event:' || target_operation_id::text, 0));
  select events.server_sequence into saved_sequence
  from public.pachanga_progression_events events
  where events.operation_id = target_operation_id;
  if found then return saved_sequence; end if;

  insert into public.pachanga_progression_events(
    operation_id, event_type, group_id, player_profile_id, match_fact_id,
    achievement_grant_id, reward_grant_id, payload
  ) values (
    target_operation_id, target_event_type, target_group_id, target_player_profile_id,
    target_match_fact_id, target_achievement_grant_id, target_reward_grant_id,
    case when jsonb_typeof(target_payload) = 'object' then target_payload else '{}'::jsonb end
  )
  returning server_sequence into saved_sequence;

  if target_group_id is not null then
    perform private.pachanga_progression_bump_group_v1(target_group_id, saved_sequence);
  end if;
  if target_player_profile_id is not null then
    select profiles.user_id into target_user_id
    from public.pachanga_player_profiles profiles
    where profiles.id = target_player_profile_id;
    perform private.pachanga_progression_bump_user_v1(target_user_id, saved_sequence);
  end if;
  return saved_sequence;
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

  select
    count(*)::integer as matches_played,
    count(*) filter (where facts.outcome = 'win')::integer as wins,
    count(*) filter (where facts.outcome = 'draw')::integer as draws,
    count(*) filter (where facts.outcome = 'loss')::integer as losses,
    coalesce(sum(facts.goals_for), 0)::integer as goals_for,
    coalesce(sum(facts.goals_against), 0)::integer as goals_against,
    count(*) filter (where facts.clean_sheet)::integer as clean_sheets,
    count(*) filter (where facts.close_win)::integer as close_wins,
    count(*) filter (where facts.big_win)::integer as big_wins,
    count(*) filter (where facts.scoreless_draw)::integer as scoreless_draws,
    count(distinct facts.opponent_group_id) filter (where facts.opponent_group_id is not null)::integer
      as distinct_opponents
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
    scoreless_draws, distinct_opponents, current_win_streak,
    max_win_streak, current_unbeaten_streak, max_unbeaten_streak
  ) values (
    target_group_id, target_match_scope, aggregates.matches_played,
    aggregates.wins, aggregates.draws, aggregates.losses,
    aggregates.goals_for, aggregates.goals_against, aggregates.clean_sheets,
    aggregates.close_wins, aggregates.big_wins, aggregates.scoreless_draws,
    aggregates.distinct_opponents, current_wins, max_wins,
    current_unbeaten, max_unbeaten
  ) on conflict (group_id, match_scope) do update set
    matches_played = excluded.matches_played,
    wins = excluded.wins,
    draws = excluded.draws,
    losses = excluded.losses,
    goals_for = excluded.goals_for,
    goals_against = excluded.goals_against,
    clean_sheets = excluded.clean_sheets,
    close_wins = excluded.close_wins,
    big_wins = excluded.big_wins,
    scoreless_draws = excluded.scoreless_draws,
    distinct_opponents = excluded.distinct_opponents,
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
  if target_match_scope not in ('internal', 'external') then
    raise exception 'Invalid progression scope';
  end if;

  select
    count(*)::integer as appearances,
    count(*) filter (where player_facts.outcome = 'win')::integer as wins,
    count(*) filter (where player_facts.outcome = 'draw')::integer as draws,
    count(*) filter (where player_facts.outcome = 'loss')::integer as losses,
    coalesce(sum(player_facts.goals), 0)::integer as goals,
    count(*) filter (where player_facts.goals >= 2)::integer as braces,
    count(*) filter (where player_facts.goals >= 3)::integer as hat_tricks
  into aggregates
  from public.pachanga_progression_player_match_facts player_facts
  join public.pachanga_progression_match_facts match_facts
    on match_facts.id = player_facts.match_fact_id
  where player_facts.player_profile_id = target_player_profile_id
    and player_facts.state = 'active'
    and match_facts.state = 'active'
    and match_facts.match_scope = target_match_scope;

  for fact in
    select player_facts.outcome
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = player_facts.match_fact_id
    where player_facts.player_profile_id = target_player_profile_id
      and player_facts.state = 'active'
      and match_facts.state = 'active'
      and match_facts.match_scope = target_match_scope
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
    goals, braces, hat_tricks, current_win_streak, max_win_streak,
    current_unbeaten_streak, max_unbeaten_streak
  ) values (
    target_player_profile_id, target_match_scope, aggregates.appearances,
    aggregates.wins, aggregates.draws, aggregates.losses,
    aggregates.goals, aggregates.braces, aggregates.hat_tricks,
    current_wins, max_wins, current_unbeaten, max_unbeaten
  ) on conflict (player_profile_id, match_scope) do update set
    appearances = excluded.appearances,
    wins = excluded.wins,
    draws = excluded.draws,
    losses = excluded.losses,
    goals = excluded.goals,
    braces = excluded.braces,
    hat_tricks = excluded.hat_tricks,
    current_win_streak = excluded.current_win_streak,
    max_win_streak = excluded.max_win_streak,
    current_unbeaten_streak = excluded.current_unbeaten_streak,
    max_unbeaten_streak = excluded.max_unbeaten_streak,
    revision = public.pachanga_player_progression_stats.revision + 1,
    server_sequence = nextval('public.pachanga_progression_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;

  select profiles.user_id into target_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = target_player_profile_id;
  perform private.pachanga_progression_bump_user_v1(target_user_id, saved.server_sequence);
  return to_jsonb(saved);
end;
$$;

create or replace function private.pachanga_achievement_metric_v1(
  target_definition_id uuid,
  target_subject_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  metric integer;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id and definitions.active;
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
      else 0 end
    into metric
    from public.pachanga_player_progression_stats stats
    where stats.player_profile_id = target_subject_id
      and stats.match_scope = definition.match_scope;
  end if;
  return coalesce(metric, 0);
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
  saved_grant_id uuid := gen_random_uuid();
  saved_reward_id uuid;
  target_player_user_id uuid;
  event_operation_id uuid;
  recipient record;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id and definitions.active;
  if not found or definition.subject_type not in ('team', 'player') then return null; end if;
  if target_metric_value < definition.threshold then return null; end if;
  if definition.subject_type = 'team' and target_subject_id <> target_group_id then
    raise exception 'Team achievement subject must be its group';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'achievement:' || definition.id::text || ':' || target_subject_id::text, 0
  ));
  select grants.id into saved_grant_id
  from public.pachanga_achievement_grants grants
  where grants.subject_type = definition.subject_type
    and grants.subject_id = target_subject_id
    and grants.definition_id = definition.id
    and grants.state = 'active';
  if found then return saved_grant_id; end if;

  saved_grant_id := gen_random_uuid();
  insert into public.pachanga_achievement_grants(
    id, definition_id, subject_type, subject_id, group_id,
    origin_match_fact_id, metric_value, operation_id
  ) values (
    saved_grant_id, definition.id, definition.subject_type, target_subject_id,
    target_group_id, target_origin_match_fact_id, target_metric_value,
    md5('achievement-grant:' || saved_grant_id::text)::uuid
  );

  event_operation_id := md5('achievement-event:' || saved_grant_id::text)::uuid;
  perform private.pachanga_progression_record_event_v1(
    event_operation_id, 'achievement_awarded', target_group_id,
    case when definition.subject_type = 'player' then target_subject_id else null end,
    target_origin_match_fact_id, saved_grant_id, null,
    jsonb_build_object(
      'achievementKey', definition.achievement_key,
      'version', definition.version,
      'metricValue', target_metric_value,
      'threshold', definition.threshold,
      'rarity', definition.rarity
    )
  );

  if definition.reward_kind = 'none' then return saved_grant_id; end if;
  if definition.reward_kind = 'team_cosmetic' and not exists (
    select 1 from public.pachanga_cosmetic_catalog cosmetics
    where cosmetics.cosmetic_key = definition.reward_key
      and cosmetics.active and cosmetics.availability = 'achievement'
  ) then raise exception 'Achievement reward cosmetic is unavailable'; end if;

  saved_reward_id := gen_random_uuid();
  insert into public.pachanga_reward_grants(
    id, achievement_grant_id, reward_kind, reward_key, group_id,
    player_profile_id, payload
  ) values (
    saved_reward_id, saved_grant_id, definition.reward_kind, definition.reward_key,
    target_group_id,
    case when definition.subject_type = 'player' then target_subject_id else null end,
    jsonb_build_object(
      'achievementKey', definition.achievement_key,
      'achievementTitle', definition.title,
      'rarity', definition.rarity,
      'rewardKey', definition.reward_key,
      'rewardKind', definition.reward_kind
    )
  );

  if definition.reward_kind = 'team_cosmetic' then
    insert into public.pachanga_team_cosmetic_inventory(
      group_id, cosmetic_key, source_grant_id
    ) values (
      target_group_id, definition.reward_key, saved_grant_id
    ) on conflict (group_id, cosmetic_key) do update set
      source_grant_id = excluded.source_grant_id,
      state = 'unlocked',
      unlocked_at = clock_timestamp(),
      revoked_at = null,
      revision = public.pachanga_team_cosmetic_inventory.revision + 1;

    for recipient in
      select distinct on (members.user_id)
        members.user_id, members.role, members.display_name
      from (
        select groups.owner_id as user_id, 'owner'::text as role, groups.name as display_name, 0 as priority
        from public.pachanga_groups groups where groups.id = target_group_id
        union all
        select memberships.user_id, memberships.role, memberships.display_name, 1 as priority
        from public.pachanga_group_members memberships
        where memberships.group_id = target_group_id
      ) members
      order by members.user_id, members.priority
    loop
      insert into public.pachanga_reward_recipients(
        reward_grant_id, user_id, member_role_snapshot, member_name_snapshot
      ) values (
        saved_reward_id, recipient.user_id, recipient.role,
        left(coalesce(recipient.display_name, 'Miembro'), 120)
      );
      perform private.pachanga_notify_v1(
        recipient.user_id,
        'achievement_reward',
        'Nueva recompensa de equipo',
        definition.title || ' ha desbloqueado ' || definition.reward_key || '.',
        '/equipo/identidad?reward=' || saved_reward_id::text,
        jsonb_build_object(
          'groupId', target_group_id,
          'rewardGrantId', saved_reward_id,
          'achievementKey', definition.achievement_key
        ),
        'achievement-reward:' || saved_reward_id::text || ':' || recipient.user_id::text
      );
      perform private.pachanga_progression_bump_user_v1(recipient.user_id);
    end loop;
  else
    insert into public.pachanga_player_reward_inventory(
      player_profile_id, reward_kind, reward_key, source_grant_id
    ) values (
      target_subject_id, definition.reward_kind, definition.reward_key, saved_grant_id
    ) on conflict (player_profile_id, reward_kind, reward_key) do update set
      source_grant_id = excluded.source_grant_id,
      state = 'unlocked',
      unlocked_at = clock_timestamp(),
      revoked_at = null;

    select profiles.user_id into target_player_user_id
    from public.pachanga_player_profiles profiles
    where profiles.id = target_subject_id;
    if target_player_user_id is not null then
      insert into public.pachanga_reward_recipients(
        reward_grant_id, user_id, member_role_snapshot, member_name_snapshot
      )
      select saved_reward_id, profiles.user_id, 'player', profiles.display_name
      from public.pachanga_player_profiles profiles
      where profiles.id = target_subject_id;
      perform private.pachanga_notify_v1(
        target_player_user_id,
        'personal_achievement_reward',
        'Nuevo logro personal',
        definition.title || ' ya forma parte de tu colección.',
        '/equipo/identidad?reward=' || saved_reward_id::text,
        jsonb_build_object(
          'groupId', target_group_id,
          'rewardGrantId', saved_reward_id,
          'achievementKey', definition.achievement_key
        ),
        'achievement-reward:' || saved_reward_id::text || ':' || target_player_user_id::text
      );
      perform private.pachanga_progression_bump_user_v1(target_player_user_id);
    end if;
  end if;

  perform private.pachanga_progression_record_event_v1(
    md5('reward-event:' || saved_reward_id::text)::uuid,
    'reward_granted', target_group_id,
    case when definition.subject_type = 'player' then target_subject_id else null end,
    target_origin_match_fact_id, saved_grant_id, saved_reward_id,
    jsonb_build_object(
      'rewardKey', definition.reward_key,
      'rewardKind', definition.reward_kind,
      'deterministic', true
    )
  );
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
  definition record;
  player record;
  metric integer;
  before_count integer;
  after_count integer;
  awarded integer := 0;
begin
  for definition in
    select definitions.id
    from public.pachanga_achievement_definitions definitions
    where definitions.active
      and definitions.subject_type = 'team'
      and definitions.match_scope = target_match_scope
    order by definitions.achievement_key, definitions.version
  loop
    metric := private.pachanga_achievement_metric_v1(definition.id, target_group_id);
    select count(*) into before_count
    from public.pachanga_achievement_grants grants
    where grants.definition_id = definition.id
      and grants.subject_type = 'team'
      and grants.subject_id = target_group_id
      and grants.state = 'active';
    perform private.pachanga_award_achievement_v1(
      definition.id, target_group_id, target_group_id,
      target_origin_match_fact_id, metric
    );
    select count(*) into after_count
    from public.pachanga_achievement_grants grants
    where grants.definition_id = definition.id
      and grants.subject_type = 'team'
      and grants.subject_id = target_group_id
      and grants.state = 'active';
    if after_count > before_count then awarded := awarded + 1; end if;
  end loop;

  for player in
    select distinct player_facts.player_profile_id
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = target_origin_match_fact_id
      and player_facts.group_id = target_group_id
      and player_facts.state = 'active'
  loop
    for definition in
      select definitions.id
      from public.pachanga_achievement_definitions definitions
      where definitions.active
        and definitions.subject_type = 'player'
        and definitions.match_scope = target_match_scope
      order by definitions.achievement_key, definitions.version
    loop
      metric := private.pachanga_achievement_metric_v1(definition.id, player.player_profile_id);
      select count(*) into before_count
      from public.pachanga_achievement_grants grants
      where grants.definition_id = definition.id
        and grants.subject_type = 'player'
        and grants.subject_id = player.player_profile_id
        and grants.state = 'active';
      perform private.pachanga_award_achievement_v1(
        definition.id, player.player_profile_id, target_group_id,
        target_origin_match_fact_id, metric
      );
      select count(*) into after_count
      from public.pachanga_achievement_grants grants
      where grants.definition_id = definition.id
        and grants.subject_type = 'player'
        and grants.subject_id = player.player_profile_id
        and grants.state = 'active';
      if after_count > before_count then awarded := awarded + 1; end if;
    end loop;
  end loop;
  return awarded;
end;
$$;

create or replace function private.pachanga_add_external_player_facts_v1(
  target_match_fact_id uuid,
  target_external_match_id uuid,
  target_result_version integer,
  target_group_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_outcome text;
  inserted_count integer := 0;
  profile record;
  match_row public.pachanga_external_matches%rowtype;
begin
  select facts.outcome into target_outcome
  from public.pachanga_progression_match_facts facts
  where facts.id = target_match_fact_id and facts.state = 'active';
  select * into match_row
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id;
  if target_outcome is null or not found then return 0; end if;

  insert into public.pachanga_progression_player_match_facts(
    match_fact_id, group_id, player_profile_id, local_player_id,
    team_side, outcome, goals, card_snapshot
  )
  select
    target_match_fact_id, participants.group_id, participants.player_profile_id,
    participants.local_player_id, 'team', target_outcome,
    coalesce(scorers.goals, 0), participants.card_snapshot
  from public.pachanga_external_match_participants participants
  left join public.pachanga_external_match_scorers scorers
    on scorers.external_match_id = participants.external_match_id
    and scorers.result_version = participants.result_version
    and scorers.group_id = participants.group_id
    and scorers.local_player_id = participants.local_player_id
  where participants.external_match_id = target_external_match_id
    and participants.result_version = target_result_version
    and participants.group_id = target_group_id
    and participants.player_profile_id is not null
  on conflict (match_fact_id, local_player_id) do nothing;
  get diagnostics inserted_count = row_count;

  update public.pachanga_progression_match_facts facts
  set player_facts_complete = case
      when target_group_id = match_row.home_group_id then match_row.canonical_unassigned_home = 0
      else match_row.canonical_unassigned_away = 0
    end,
    source_snapshot = facts.source_snapshot || jsonb_build_object(
      'unassignedHome', match_row.canonical_unassigned_home,
      'unassignedAway', match_row.canonical_unassigned_away
    )
  where facts.id = target_match_fact_id;

  for profile in
    select distinct facts.player_profile_id
    from public.pachanga_progression_player_match_facts facts
    where facts.match_fact_id = target_match_fact_id
      and facts.group_id = target_group_id
      and facts.state = 'active'
  loop
    perform private.pachanga_rebuild_player_progression_stats_v1(
      profile.player_profile_id, 'external'
    );
  end loop;
  return inserted_count;
end;
$$;

create or replace function private.pachanga_apply_external_progression_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  match_row public.pachanga_external_matches%rowtype;
  target_group_id uuid;
  opponent_group_id uuid;
  target_goals integer;
  opponent_goals integer;
  target_outcome text;
  saved_fact_id uuid;
  player record;
begin
  if new.event_type in ('match_result_confirmed', 'match_result_auto_confirmed') then
    select * into match_row
    from public.pachanga_external_matches matches
    where matches.id = new.external_match_id;
    if not found or match_row.state not in ('confirmed', 'auto_confirmed')
      or match_row.official_version is null then return new; end if;

    for target_group_id, opponent_group_id, target_goals, opponent_goals in
      select match_row.home_group_id, match_row.away_group_id,
        match_row.canonical_score_home, match_row.canonical_score_away
      union all
      select match_row.away_group_id, match_row.home_group_id,
        match_row.canonical_score_away, match_row.canonical_score_home
    loop
      target_outcome := case
        when target_goals > opponent_goals then 'win'
        when target_goals = opponent_goals then 'draw'
        else 'loss' end;

      insert into public.pachanga_progression_match_facts(
        source_kind, source_match_id, source_revision, source_event_id,
        group_id, opponent_group_id, match_scope, outcome,
        goals_for, goals_against, clean_sheet, close_win, big_win,
        scoreless_draw, player_facts_complete, source_snapshot,
        server_sequence, played_at
      ) values (
        'external_result', match_row.id::text, match_row.official_version,
        new.id, target_group_id, opponent_group_id, 'external', target_outcome,
        target_goals, opponent_goals, opponent_goals = 0,
        target_outcome = 'win' and target_goals - opponent_goals = 1,
        target_outcome = 'win' and target_goals - opponent_goals >= 4,
        target_goals = 0 and opponent_goals = 0,
        case when target_group_id = match_row.home_group_id
          then match_row.canonical_unassigned_home = 0
          else match_row.canonical_unassigned_away = 0 end,
        jsonb_build_object(
          'externalMatchId', match_row.id,
          'challengeId', match_row.challenge_id,
          'officialVersion', match_row.official_version,
          'officialState', match_row.state,
          'scoreHome', match_row.canonical_score_home,
          'scoreAway', match_row.canonical_score_away,
          'unassignedHome', match_row.canonical_unassigned_home,
          'unassignedAway', match_row.canonical_unassigned_away,
          'homeLevelSnapshot', match_row.home_level_snapshot,
          'awayLevelSnapshot', match_row.away_level_snapshot,
          'modality', match_row.modality
        ),
        new.server_sequence, match_row.scheduled_at
      ) on conflict (source_kind, source_match_id, group_id, source_revision)
      do nothing returning id into saved_fact_id;

      if saved_fact_id is null then
        select facts.id into saved_fact_id
        from public.pachanga_progression_match_facts facts
        where facts.source_kind = 'external_result'
          and facts.source_match_id = match_row.id::text
          and facts.group_id = target_group_id
          and facts.source_revision = match_row.official_version;
      end if;

      perform private.pachanga_add_external_player_facts_v1(
        saved_fact_id, match_row.id, match_row.official_version, target_group_id
      );
      perform private.pachanga_rebuild_team_progression_stats_v1(target_group_id, 'external');
      perform private.pachanga_evaluate_achievements_v1(
        target_group_id, 'external', saved_fact_id
      );
      perform private.pachanga_progression_record_event_v1(
        md5('external-progress:' || new.id::text || ':' || target_group_id::text)::uuid,
        'match_progression_applied', target_group_id, null, saved_fact_id,
        null, null,
        jsonb_build_object(
          'sourceEventId', new.id,
          'officialVersion', match_row.official_version,
          'officialState', match_row.state
        )
      );
      saved_fact_id := null;
    end loop;
  elsif new.event_type = 'match_scorers_completed' and new.actor_group_id is not null then
    select * into match_row
    from public.pachanga_external_matches matches
    where matches.id = new.external_match_id;
    select facts.id into saved_fact_id
    from public.pachanga_progression_match_facts facts
    where facts.source_kind = 'external_result'
      and facts.source_match_id = new.external_match_id::text
      and facts.group_id = new.actor_group_id
      and facts.source_revision = match_row.official_version
      and facts.state = 'active';
    if saved_fact_id is not null then
      perform private.pachanga_add_external_player_facts_v1(
        saved_fact_id, match_row.id, match_row.official_version, new.actor_group_id
      );
      perform private.pachanga_evaluate_achievements_v1(
        new.actor_group_id, 'external', saved_fact_id
      );
      perform private.pachanga_progression_record_event_v1(
        md5('external-scorers-progress:' || new.id::text || ':' || new.actor_group_id::text)::uuid,
        'match_progression_applied', new.actor_group_id, null, saved_fact_id,
        null, null, jsonb_build_object('sourceEventId', new.id, 'scorersCompleted', true)
      );
    end if;
  elsif new.event_type = 'match_result_annulled' then
    for player in
      select facts.id
      from public.pachanga_progression_match_facts facts
      where facts.source_kind = 'external_result'
        and facts.source_match_id = new.external_match_id::text
        and facts.state = 'active'
      order by facts.group_id, facts.id
    loop
      perform private.pachanga_revoke_match_progression_v1(
        player.id,
        coalesce(nullif(new.payload ->> 'reason', ''), 'external_result_annulled')
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists apply_external_progression_after_result_event
  on public.pachanga_external_result_events;
create trigger apply_external_progression_after_result_event
after insert on public.pachanga_external_result_events
for each row execute function private.pachanga_apply_external_progression_event_v1();

create or replace function private.pachanga_apply_internal_progression_snapshot_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  match_payload jsonb;
  score_a integer;
  score_b integer;
  saved_fact_id uuid;
  participant record;
  participant_outcome text;
  participant_goals integer;
begin
  if new.state <> 'active' or jsonb_typeof(new.snapshot) <> 'object'
    or not (new.snapshot ? 'match') then return new; end if;
  match_payload := new.snapshot -> 'match';
  if coalesce(match_payload ->> 'scoreA', '') !~ '^[0-9]+$'
    or coalesce(match_payload ->> 'scoreB', '') !~ '^[0-9]+$' then return new; end if;
  score_a := (match_payload ->> 'scoreA')::integer;
  score_b := (match_payload ->> 'scoreB')::integer;

  insert into public.pachanga_progression_match_facts(
    source_kind, source_match_id, source_revision, group_id, match_scope,
    outcome, goals_for, goals_against, clean_sheet, close_win, big_win,
    scoreless_draw, source_snapshot, played_at
  ) values (
    'internal_snapshot', new.match_id, 1, new.group_id, 'internal', 'social',
    score_a + score_b, 0, score_a = 0 or score_b = 0,
    abs(score_a - score_b) = 1, abs(score_a - score_b) >= 4,
    score_a = 0 and score_b = 0,
    jsonb_build_object(
      'matchId', new.match_id,
      'scoreA', score_a,
      'scoreB', score_b,
      'groupLevel', new.group_level,
      'lineupALevel', new.lineup_a_level,
      'lineupBLevel', new.lineup_b_level,
      'engineVersion', new.engine_version,
      'match', match_payload
    ),
    new.finalized_at
  ) on conflict (source_kind, source_match_id, group_id, source_revision)
  do nothing returning id into saved_fact_id;
  if saved_fact_id is null then return new; end if;

  for participant in
    select participants.*
    from public.pachanga_match_rating_participants participants
    where participants.group_id = new.group_id
      and participants.match_id = new.match_id
      and participants.player_profile_id is not null
      and participants.attendance_confirmed
      and not participants.was_reserve
      and participants.team_side in ('A', 'B')
    order by participants.local_player_id
  loop
    participant_outcome := case
      when score_a = score_b then 'draw'
      when participant.team_side = 'A' and score_a > score_b then 'win'
      when participant.team_side = 'B' and score_b > score_a then 'win'
      else 'loss' end;
    select coalesce(sum((scorers.value ->> 'goals')::integer), 0)::integer
    into participant_goals
    from jsonb_array_elements(coalesce(match_payload -> 'scorers', '[]'::jsonb)) scorers(value)
    where scorers.value ->> 'playerId' = participant.local_player_id
      and coalesce(scorers.value ->> 'goals', '') ~ '^[1-9][0-9]*$';

    insert into public.pachanga_progression_player_match_facts(
      match_fact_id, group_id, player_profile_id, local_player_id,
      team_side, outcome, goals, card_snapshot
    ) values (
      saved_fact_id, new.group_id, participant.player_profile_id,
      participant.local_player_id, participant.team_side,
      participant_outcome, participant_goals, participant.card_snapshot
    );
    perform private.pachanga_rebuild_player_progression_stats_v1(
      participant.player_profile_id, 'internal'
    );
  end loop;

  perform private.pachanga_rebuild_team_progression_stats_v1(new.group_id, 'internal');
  perform private.pachanga_evaluate_achievements_v1(new.group_id, 'internal', saved_fact_id);
  perform private.pachanga_progression_record_event_v1(
    md5('internal-progress:' || new.group_id::text || ':' || new.match_id)::uuid,
    'match_progression_applied', new.group_id, null, saved_fact_id,
    null, null,
    jsonb_build_object('sourceSnapshot', 'rating-v2', 'matchId', new.match_id)
  );
  return new;
end;
$$;

drop trigger if exists apply_internal_progression_after_rating_snapshot
  on public.pachanga_match_rating_snapshots;
create trigger apply_internal_progression_after_rating_snapshot
after insert or update of snapshot, state on public.pachanga_match_rating_snapshots
for each row execute function private.pachanga_apply_internal_progression_snapshot_v1();

create or replace function private.pachanga_revoke_achievement_grant_v1(
  target_grant_id uuid,
  target_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_achievement_grants%rowtype;
  definition public.pachanga_achievement_definitions%rowtype;
  reward public.pachanga_reward_grants%rowtype;
  recipient record;
begin
  select * into selected
  from public.pachanga_achievement_grants grants
  where grants.id = target_grant_id
  for update;
  if not found or selected.state = 'revoked' then return false; end if;
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = selected.definition_id;

  update public.pachanga_achievement_grants grants
  set state = 'revoked', revoked_at = clock_timestamp(),
      revoked_reason = left(coalesce(nullif(trim(target_reason), ''), 'canonical_fact_revoked'), 500)
  where grants.id = selected.id;

  select * into reward
  from public.pachanga_reward_grants rewards
  where rewards.achievement_grant_id = selected.id
  for update;
  if found then
    update public.pachanga_reward_grants rewards
    set state = 'revoked', revoked_at = clock_timestamp()
    where rewards.id = reward.id;
    for recipient in
      update public.pachanga_reward_recipients recipients
      set status = 'revoked', revoked_at = clock_timestamp(),
          revision = recipients.revision + 1
      where recipients.reward_grant_id = reward.id
      returning recipients.user_id
    loop
      perform private.pachanga_progression_bump_user_v1(recipient.user_id);
    end loop;

    if reward.reward_kind = 'team_cosmetic' and not exists (
      select 1
      from public.pachanga_reward_grants active_rewards
      join public.pachanga_achievement_grants active_grants
        on active_grants.id = active_rewards.achievement_grant_id
      where active_rewards.group_id = reward.group_id
        and active_rewards.reward_key = reward.reward_key
        and active_rewards.reward_kind = 'team_cosmetic'
        and active_rewards.state = 'active'
        and active_grants.state = 'active'
    ) then
      update public.pachanga_team_cosmetic_inventory inventory
      set state = 'revoked', revoked_at = clock_timestamp(),
          revision = inventory.revision + 1
      where inventory.group_id = reward.group_id
        and inventory.cosmetic_key = reward.reward_key;
    elsif reward.reward_kind in ('player_badge', 'player_title')
      and reward.player_profile_id is not null and not exists (
        select 1
        from public.pachanga_reward_grants active_rewards
        join public.pachanga_achievement_grants active_grants
          on active_grants.id = active_rewards.achievement_grant_id
        where active_rewards.player_profile_id = reward.player_profile_id
          and active_rewards.reward_key = reward.reward_key
          and active_rewards.reward_kind = reward.reward_kind
          and active_rewards.state = 'active'
          and active_grants.state = 'active'
      ) then
      update public.pachanga_player_reward_inventory inventory
      set state = 'revoked', revoked_at = clock_timestamp()
      where inventory.player_profile_id = reward.player_profile_id
        and inventory.reward_kind = reward.reward_kind
        and inventory.reward_key = reward.reward_key;
    end if;

    perform private.pachanga_progression_record_event_v1(
      md5('reward-revoked:' || reward.id::text)::uuid,
      'reward_revoked', selected.group_id,
      case when selected.subject_type = 'player' then selected.subject_id else null end,
      selected.origin_match_fact_id, selected.id, reward.id,
      jsonb_build_object('reason', target_reason, 'rewardKey', reward.reward_key)
    );
  end if;

  perform private.pachanga_progression_record_event_v1(
    md5('achievement-revoked:' || selected.id::text)::uuid,
    'achievement_revoked', selected.group_id,
    case when selected.subject_type = 'player' then selected.subject_id else null end,
    selected.origin_match_fact_id, selected.id, null,
    jsonb_build_object('reason', target_reason, 'achievementKey', definition.achievement_key)
  );
  return true;
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
  revoked integer := 0;
begin
  for grant_row in
    select grants.id, grants.definition_id, definitions.threshold
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.subject_type = target_subject_type
      and grants.subject_id = target_subject_id
      and grants.state = 'active'
      and definitions.match_scope = target_match_scope
    order by grants.awarded_at, grants.id
  loop
    metric := private.pachanga_achievement_metric_v1(grant_row.definition_id, target_subject_id);
    if metric < grant_row.threshold
      and private.pachanga_revoke_achievement_grant_v1(grant_row.id, target_reason) then
      revoked := revoked + 1;
    end if;
  end loop;
  return revoked;
end;
$$;

create or replace function private.pachanga_revoke_match_progression_v1(
  target_match_fact_id uuid,
  target_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_progression_match_facts%rowtype;
  player record;
begin
  select * into selected
  from public.pachanga_progression_match_facts facts
  where facts.id = target_match_fact_id
  for update;
  if not found or selected.state = 'revoked' then return false; end if;

  update public.pachanga_progression_match_facts facts
  set state = 'revoked', revoked_at = clock_timestamp(),
      revoked_reason = left(coalesce(nullif(trim(target_reason), ''), 'canonical_fact_revoked'), 500)
  where facts.id = selected.id;
  update public.pachanga_progression_player_match_facts player_facts
  set state = 'revoked', revoked_at = clock_timestamp()
  where player_facts.match_fact_id = selected.id and player_facts.state = 'active';

  perform private.pachanga_rebuild_team_progression_stats_v1(
    selected.group_id, selected.match_scope
  );
  perform private.pachanga_reconcile_subject_achievements_v1(
    'team', selected.group_id, selected.match_scope, target_reason
  );

  for player in
    select distinct player_facts.player_profile_id
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = selected.id
  loop
    perform private.pachanga_rebuild_player_progression_stats_v1(
      player.player_profile_id, selected.match_scope
    );
    perform private.pachanga_reconcile_subject_achievements_v1(
      'player', player.player_profile_id, selected.match_scope, target_reason
    );
  end loop;

  perform private.pachanga_progression_record_event_v1(
    md5('match-progress-revoked:' || selected.id::text)::uuid,
    'match_progression_revoked', selected.group_id, null, selected.id,
    null, null, jsonb_build_object('reason', target_reason)
  );
  return true;
end;
$$;

create or replace function public.annul_pachanga_external_result_v1(
  target_external_match_id uuid,
  target_reason text,
  operation_id uuid,
  expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_external_matches%rowtype;
  saved_sequence bigint;
begin
  if annul_pachanga_external_result_v1.operation_id is null or expected_revision is null
    or nullif(trim(target_reason), '') is null then
    raise exception 'Operation id, revision and annulment reason required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'external-result-operation:' || annul_pachanga_external_result_v1.operation_id::text, 0
  ));
  select events.server_sequence into saved_sequence
  from public.pachanga_external_result_events events
  where events.operation_id = annul_pachanga_external_result_v1.operation_id;
  if found then
    select * into selected from public.pachanga_external_matches
    where id = target_external_match_id;
    return jsonb_build_object(
      'externalMatchId', selected.id,
      'state', selected.state,
      'confirmedRevision', selected.revision,
      'serverSequence', saved_sequence,
      'operationId', annul_pachanga_external_result_v1.operation_id
    );
  end if;

  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found then raise exception 'External match not found'; end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state not in ('confirmed', 'auto_confirmed') then
    raise exception 'Only official external matches can be annulled';
  end if;

  update public.pachanga_external_matches matches
  set state = 'annulled', revision = matches.revision + 1,
      updated_at = clock_timestamp()
  where matches.id = selected.id;
  saved_sequence := private.pachanga_external_record_event_v1(
    selected.id, annul_pachanga_external_result_v1.operation_id,
    null, null, 'match_result_annulled',
    selected.official_version,
    jsonb_build_object('reason', left(trim(target_reason), 500))
  );
  return jsonb_build_object(
    'externalMatchId', selected.id,
    'state', 'annulled',
    'confirmedRevision', selected.revision + 1,
    'serverSequence', saved_sequence,
    'operationId', annul_pachanga_external_result_v1.operation_id,
    'confirmedAt', clock_timestamp()
  );
end;
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
  select jsonb_strip_nulls(jsonb_build_object(
    'rewardGrantId', rewards.id,
    'rewardKind', rewards.reward_kind,
    'rewardKey', rewards.reward_key,
    'rewardPayload', rewards.payload,
    'rewardState', rewards.state,
    'status', recipients.status,
    'recipientRevision', recipients.revision,
    'snapshotAt', recipients.snapshot_at,
    'openedAt', recipients.opened_at,
    'achievement', jsonb_build_object(
      'grantId', grants.id,
      'key', definitions.achievement_key,
      'title', definitions.title,
      'description', definitions.description,
      'scope', definitions.match_scope,
      'subjectType', definitions.subject_type,
      'rarity', definitions.rarity,
      'awardedAt', grants.awarded_at
    )
  ))
  from public.pachanga_reward_recipients recipients
  join public.pachanga_reward_grants rewards
    on rewards.id = recipients.reward_grant_id
  join public.pachanga_achievement_grants grants
    on grants.id = rewards.achievement_grant_id
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = target_user_id;
$$;

create or replace function public.get_pachanga_progression_snapshot_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_profile_id uuid;
  group_revision bigint := 0;
  group_sequence bigint := 0;
  user_revision bigint := 0;
  user_sequence bigint := 0;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Group membership required';
  end if;
  select profiles.id into current_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = auth.uid();
  select states.revision, states.server_sequence
  into group_revision, group_sequence
  from public.pachanga_progression_group_state states
  where states.group_id = target_group_id;
  select states.revision, states.server_sequence
  into user_revision, user_sequence
  from public.pachanga_progression_user_state states
  where states.user_id = auth.uid();

  return jsonb_build_object(
    'groupId', target_group_id,
    'confirmedRevision', greatest(coalesce(group_revision, 0), coalesce(user_revision, 0)),
    'groupRevision', coalesce(group_revision, 0),
    'userRevision', coalesce(user_revision, 0),
    'serverSequence', greatest(coalesce(group_sequence, 0), coalesce(user_sequence, 0)),
    'teamStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope,
        'matches', stats.matches_played,
        'wins', stats.wins,
        'draws', stats.draws,
        'losses', stats.losses,
        'goalsFor', stats.goals_for,
        'goalsAgainst', stats.goals_against,
        'cleanSheets', stats.clean_sheets,
        'closeWins', stats.close_wins,
        'bigWins', stats.big_wins,
        'scorelessDraws', stats.scoreless_draws,
        'distinctOpponents', stats.distinct_opponents,
        'maxWinStreak', stats.max_win_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'revision', stats.revision,
        'updatedAt', stats.updated_at
      ) order by stats.match_scope)
      from public.pachanga_team_progression_stats stats
      where stats.group_id = target_group_id
    ), '[]'::jsonb),
    'teamAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id,
        'key', definitions.achievement_key,
        'title', definitions.title,
        'description', definitions.description,
        'scope', definitions.match_scope,
        'category', definitions.category,
        'rarity', definitions.rarity,
        'metricValue', grants.metric_value,
        'threshold', definitions.threshold,
        'rewardKind', definitions.reward_kind,
        'rewardKey', definitions.reward_key,
        'state', grants.state,
        'awardedAt', grants.awarded_at,
        'revokedAt', grants.revoked_at,
        'originMatchFactId', grants.origin_match_fact_id
      ) order by grants.awarded_at desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      where grants.group_id = target_group_id
        and grants.subject_type = 'team'
    ), '[]'::jsonb),
    'personalStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope,
        'appearances', stats.appearances,
        'wins', stats.wins,
        'draws', stats.draws,
        'losses', stats.losses,
        'goals', stats.goals,
        'braces', stats.braces,
        'hatTricks', stats.hat_tricks,
        'maxWinStreak', stats.max_win_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'revision', stats.revision,
        'updatedAt', stats.updated_at
      ) order by stats.match_scope)
      from public.pachanga_player_progression_stats stats
      where stats.player_profile_id = current_profile_id
    ), '[]'::jsonb),
    'personalAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id,
        'key', definitions.achievement_key,
        'title', definitions.title,
        'description', definitions.description,
        'scope', definitions.match_scope,
        'rarity', definitions.rarity,
        'rewardKind', definitions.reward_kind,
        'rewardKey', definitions.reward_key,
        'state', grants.state,
        'awardedAt', grants.awarded_at,
        'revokedAt', grants.revoked_at
      ) order by grants.awarded_at desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      where grants.subject_type = 'player'
        and grants.subject_id = current_profile_id
    ), '[]'::jsonb),
    'collection', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', cosmetics.cosmetic_key,
        'family', cosmetics.family,
        'name', cosmetics.display_name,
        'description', cosmetics.description,
        'rarity', cosmetics.rarity,
        'availability', cosmetics.availability,
        'renderContract', cosmetics.render_contract,
        'layerOrder', cosmetics.layer_order,
        'unlocked', cosmetics.availability = 'base' or inventory.state = 'unlocked',
        'inventoryState', inventory.state,
        'unlockedAt', inventory.unlocked_at,
        'revision', inventory.revision
      ) order by cosmetics.family, cosmetics.layer_order, cosmetics.cosmetic_key)
      from public.pachanga_cosmetic_catalog cosmetics
      left join public.pachanga_team_cosmetic_inventory inventory
        on inventory.group_id = target_group_id
        and inventory.cosmetic_key = cosmetics.cosmetic_key
      where cosmetics.active
    ), '[]'::jsonb),
    'personalCollection', coalesce((
      select jsonb_agg(jsonb_build_object(
        'rewardKind', inventory.reward_kind,
        'rewardKey', inventory.reward_key,
        'state', inventory.state,
        'unlockedAt', inventory.unlocked_at
      ) order by inventory.unlocked_at desc, inventory.reward_key)
      from public.pachanga_player_reward_inventory inventory
      where inventory.player_profile_id = current_profile_id
    ), '[]'::jsonb),
    'rewards', coalesce((
      select jsonb_agg(private.pachanga_reward_recipient_snapshot_v1(
        recipients.reward_grant_id, auth.uid()
      ) order by recipients.snapshot_at, recipients.reward_grant_id)
      from public.pachanga_reward_recipients recipients
      join public.pachanga_reward_grants rewards
        on rewards.id = recipients.reward_grant_id
      where recipients.user_id = auth.uid()
        and rewards.group_id = target_group_id
        and recipients.status in ('pending', 'opened', 'revoked')
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id,
        'type', events.event_type,
        'serverSequence', events.server_sequence,
        'matchFactId', events.match_fact_id,
        'achievementGrantId', events.achievement_grant_id,
        'rewardGrantId', events.reward_grant_id,
        'payload', events.payload,
        'createdAt', events.created_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select progression_events.*
        from public.pachanga_progression_events progression_events
        where progression_events.group_id = target_group_id
        order by progression_events.server_sequence desc, progression_events.id desc
        limit 100
      ) events
    ), '[]'::jsonb),
    'updatedAt', clock_timestamp()
  );
end;
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
  selected public.pachanga_reward_recipients%rowtype;
  reward public.pachanga_reward_grants%rowtype;
  stored_actor uuid;
  stored_response jsonb;
  saved_sequence bigint;
  response jsonb;
begin
  if auth.uid() is null or open_pachanga_reward_v1.operation_id is null
    or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'reward-open:' || open_pachanga_reward_v1.operation_id::text, 0
  ));
  select receipts.actor_user_id, receipts.response
  into stored_actor, stored_response
  from public.pachanga_reward_open_receipts receipts
  where receipts.operation_id = open_pachanga_reward_v1.operation_id;
  if found then
    if stored_actor <> auth.uid() then raise exception 'Operation belongs to another actor'; end if;
    return stored_response;
  end if;

  select * into selected
  from public.pachanga_reward_recipients recipients
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = auth.uid()
  for update;
  if not found then raise exception 'Reward opening not found'; end if;
  select * into reward
  from public.pachanga_reward_grants rewards
  where rewards.id = target_reward_grant_id;
  if reward.state <> 'active' or selected.status = 'revoked' then
    raise exception 'Reward is no longer active';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'Reward revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  if selected.status = 'pending' then
    update public.pachanga_reward_recipients recipients
    set status = 'opened', opened_at = clock_timestamp(),
        revision = recipients.revision + 1
    where recipients.reward_grant_id = selected.reward_grant_id
      and recipients.user_id = selected.user_id
    returning * into selected;
    saved_sequence := private.pachanga_progression_record_event_v1(
      md5('reward-opened:' || selected.reward_grant_id::text || ':' || selected.user_id::text)::uuid,
      'reward_opened', reward.group_id, reward.player_profile_id,
      null, reward.achievement_grant_id, reward.id,
      jsonb_build_object('rewardKey', reward.reward_key)
    );
  else
    select states.server_sequence into saved_sequence
    from public.pachanga_progression_user_state states
    where states.user_id = auth.uid();
  end if;

  response := private.pachanga_reward_recipient_snapshot_v1(
    selected.reward_grant_id, selected.user_id
  ) || jsonb_build_object(
    'operationId', open_pachanga_reward_v1.operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', selected.revision,
    'serverSequence', coalesce(saved_sequence, 0),
    'confirmedAt', clock_timestamp(),
    'alreadyOpened', selected.status = 'opened' and selected.revision = expected_revision
  );
  insert into public.pachanga_reward_open_receipts(
    operation_id, reward_grant_id, actor_user_id, expected_revision,
    result_revision, server_sequence, response, client_metadata
  ) values (
    open_pachanga_reward_v1.operation_id,
    selected.reward_grant_id, auth.uid(), expected_revision,
    selected.revision, coalesce(saved_sequence, 0), response,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end
  );
  return response;
end;
$$;

revoke all on function private.pachanga_progression_bump_group_v1(uuid, bigint)
  from public, anon, authenticated;
revoke all on function private.pachanga_progression_bump_user_v1(uuid, bigint)
  from public, anon, authenticated;
revoke all on function private.pachanga_progression_record_event_v1(uuid, text, uuid, uuid, uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function private.pachanga_rebuild_team_progression_stats_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_rebuild_player_progression_stats_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_metric_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_award_achievement_v1(uuid, uuid, uuid, uuid, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_evaluate_achievements_v1(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_add_external_player_facts_v1(uuid, uuid, integer, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_apply_external_progression_event_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_apply_internal_progression_snapshot_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_revoke_achievement_grant_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_reconcile_subject_achievements_v1(text, uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_revoke_match_progression_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_recipient_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;
revoke all on function public.open_pachanga_reward_v1(uuid, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.open_pachanga_reward_v1(uuid, uuid, bigint, jsonb)
  to authenticated;
revoke all on function public.annul_pachanga_external_result_v1(uuid, text, uuid, bigint)
  from public, anon, authenticated;
grant execute on function public.annul_pachanga_external_result_v1(uuid, text, uuid, bigint)
  to service_role;

alter table public.pachanga_progression_group_state replica identity full;
alter table public.pachanga_progression_user_state replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_progression_group_state'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_progression_group_state;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_progression_user_state'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_progression_user_state;
  end if;
end;
$$;
