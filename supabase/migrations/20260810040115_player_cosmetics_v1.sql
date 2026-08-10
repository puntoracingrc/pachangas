-- Player Cosmetics V1. Cosmetics are identity-only and never affect sporting data.

create table if not exists private.pachanga_player_cosmetic_settings (
  singleton boolean primary key default true check (singleton),
  player_cosmetics_enabled boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);

insert into private.pachanga_player_cosmetic_settings(singleton, player_cosmetics_enabled)
values (true, false)
on conflict (singleton) do nothing;

revoke all on table private.pachanga_player_cosmetic_settings
  from public, anon, authenticated;
grant all on table private.pachanga_player_cosmetic_settings to service_role;

alter table public.pachanga_cosmetic_catalog
  add column if not exists owner_scope text not null default 'team',
  add column if not exists slot text,
  add column if not exists collection_key text,
  add column if not exists material_key text,
  add column if not exists lifecycle text not null default 'active_reward';

alter table public.pachanga_cosmetic_catalog
  drop constraint if exists pachanga_cosmetic_catalog_availability_check,
  drop constraint if exists pachanga_cosmetic_catalog_owner_scope_check,
  drop constraint if exists pachanga_cosmetic_catalog_slot_check,
  drop constraint if exists pachanga_cosmetic_catalog_lifecycle_check,
  add constraint pachanga_cosmetic_catalog_availability_check
    check (availability in ('base', 'achievement', 'reward_box', 'prototype')),
  add constraint pachanga_cosmetic_catalog_owner_scope_check
    check (owner_scope in ('player', 'team')),
  add constraint pachanga_cosmetic_catalog_slot_check
    check (
      (owner_scope = 'team' and slot is null)
      or (owner_scope = 'player' and slot in (
        'frame', 'background', 'accent', 'effect', 'title'
      ))
    ),
  add constraint pachanga_cosmetic_catalog_lifecycle_check
    check (lifecycle in ('prototype', 'active_reward', 'retired'));

create index if not exists pachanga_cosmetic_catalog_player_slot_idx
  on public.pachanga_cosmetic_catalog(owner_scope, lifecycle, slot, layer_order, cosmetic_key)
  where active;

insert into public.pachanga_cosmetic_catalog(
  cosmetic_key, version, family, display_name, description, rarity,
  availability, render_contract, layer_order, active,
  owner_scope, slot, collection_key, material_key, lifecycle
) values
  ('player.frame.barrio.steel', 1, 'border', 'Barrio Acero',
    'Marco urbano de acero cepillado.', 'common', 'reward_box',
    '{"frameStyle":"barrio","material":"steel"}', 10, true,
    'player', 'frame', 'futbol_de_barrio', 'steel', 'active_reward'),
  ('player.frame.barrio.copper', 1, 'border', 'Marco Cobre',
    'Marco Barrio con acabado de cobre.', 'uncommon', 'reward_box',
    '{"frameStyle":"barrio","material":"copper"}', 10, true,
    'player', 'frame', 'futbol_de_barrio', 'copper', 'active_reward'),
  ('player.frame.barrio.silver', 1, 'border', 'Barrio Plata',
    'Marco Barrio con acabado de plata.', 'rare', 'reward_box',
    '{"frameStyle":"barrio","material":"silver"}', 10, true,
    'player', 'frame', 'futbol_de_barrio', 'silver', 'active_reward'),
  ('player.frame.future.navy', 1, 'border', 'Future IQ Navy',
    'Marco técnico Navy de la colección Future IQ.', 'epic', 'reward_box',
    '{"frameStyle":"future","material":"navy"}', 10, true,
    'player', 'frame', 'future_iq', 'navy', 'active_reward'),
  ('player.frame.retro.chrome', 1, 'border', 'Retro Cromo',
    'Marco retro con reflejo cromado sobrio.', 'legendary', 'reward_box',
    '{"frameStyle":"retro","material":"chrome"}', 10, true,
    'player', 'frame', 'retro', 'chrome', 'active_reward'),
  ('player.background.asphalt_night', 1, 'pattern', 'Asfalto Nocturno',
    'Fondo oscuro inspirado en una pista de barrio.', 'common', 'reward_box',
    '{"backgroundStyle":"asphalt_night"}', 20, true,
    'player', 'background', 'noche_de_partido', 'black_matte', 'active_reward'),
  ('player.background.grid_iq', 1, 'pattern', 'Grid IQ',
    'Retícula táctica discreta para la carta.', 'uncommon', 'reward_box',
    '{"backgroundStyle":"grid_iq"}', 20, true,
    'player', 'background', 'future_iq', 'navy', 'active_reward'),
  ('player.accent.copper', 1, 'color', 'Acento Cobre',
    'Líneas y barras de cobre.', 'uncommon', 'reward_box',
    '{"accent":"copper"}', 30, true,
    'player', 'accent', 'futbol_de_barrio', 'copper', 'active_reward'),
  ('player.accent.navy', 1, 'color', 'Acento Navy',
    'Líneas y barras Navy.', 'epic', 'reward_box',
    '{"accent":"navy"}', 30, true,
    'player', 'accent', 'future_iq', 'navy', 'active_reward'),
  ('player.effect.spotlights', 1, 'effect', 'Focos',
    'Barrido de focos suave detrás de la carta.', 'rare', 'reward_box',
    '{"effect":"spotlights","intensity":"subtle"}', 40, true,
    'player', 'effect', 'noche_de_partido', null, 'active_reward'),
  ('player.effect.iq_scan', 1, 'effect', 'IQ Scan',
    'Barrido horizontal cian de Future IQ.', 'epic', 'reward_box',
    '{"effect":"scan","direction":"horizontal","material":"cyan_iq"}', 40, true,
    'player', 'effect', 'future_iq', 'cyan_iq', 'active_reward'),
  ('player.effect.gold_glint', 1, 'effect', 'Glint Oro',
    'Reflejo dorado que recorre el marco.', 'legendary', 'reward_box',
    '{"effect":"glint","direction":"diagonal","material":"gold"}', 40, true,
    'player', 'effect', 'noche_de_partido', 'gold', 'active_reward'),
  ('player.title.old_school', 1, 'adornment', 'De toda la vida',
    'Título personal para veteranos de la pachanga.', 'common', 'reward_box',
    '{"title":"De toda la vida"}', 50, true,
    'player', 'title', 'futbol_de_barrio', null, 'active_reward'),
  ('player.title.team_engine', 1, 'adornment', 'Motor del equipo',
    'Título personal de constancia y equipo.', 'rare', 'reward_box',
    '{"title":"Motor del equipo"}', 50, true,
    'player', 'title', 'noche_de_partido', null, 'active_reward')
on conflict (cosmetic_key) do update set
  version = excluded.version,
  family = excluded.family,
  display_name = excluded.display_name,
  description = excluded.description,
  rarity = excluded.rarity,
  availability = excluded.availability,
  render_contract = excluded.render_contract,
  layer_order = excluded.layer_order,
  active = excluded.active,
  owner_scope = excluded.owner_scope,
  slot = excluded.slot,
  collection_key = excluded.collection_key,
  material_key = excluded.material_key,
  lifecycle = excluded.lifecycle;

-- Preserve every audited pool weight and duplicate conversion value. Only the
-- renderer key is upgraded from the old team-shaped placeholder to player V1.
update public.pachanga_reward_pool_catalog pools
set cosmetic_key = replacements.cosmetic_key,
    metadata = coalesce(pools.metadata, '{}'::jsonb)
      || jsonb_build_object('playerCosmeticsVersion', 1)
from (values
  ('pool.collective.common', 'cosmetic.ball', 'player.frame.barrio.steel'),
  ('pool.collective.common', 'cosmetic.stripes', 'player.background.asphalt_night'),
  ('pool.collective.common', 'combo.ball', 'player.title.old_school'),
  ('pool.collective.uncommon', 'cosmetic.diagonal', 'player.frame.barrio.copper'),
  ('pool.collective.uncommon', 'cosmetic.double', 'player.background.grid_iq'),
  ('pool.collective.uncommon', 'combo.ribbon', 'player.accent.copper'),
  ('pool.collective.rare', 'cosmetic.silver', 'player.frame.barrio.silver'),
  ('pool.collective.rare', 'cosmetic.laurel', 'player.effect.spotlights'),
  ('pool.collective.rare', 'combo.star', 'player.title.team_engine'),
  ('pool.collective.epic', 'cosmetic.gold', 'player.frame.future.navy'),
  ('pool.collective.epic', 'cosmetic.crown', 'player.effect.iq_scan'),
  ('pool.collective.epic', 'combo.palette', 'player.accent.navy'),
  ('pool.collective.legendary', 'cosmetic.glow', 'player.frame.retro.chrome'),
  ('pool.collective.legendary', 'combo.glow', 'player.effect.gold_glint')
) as replacements(pool_key, entry_key, cosmetic_key)
where pools.economy_version = 1
  and pools.pool_key = replacements.pool_key
  and pools.entry_key = replacements.entry_key;

-- Upgrade historical placeholder keys when doing so cannot collide with an
-- already owned canonical item. Conflicting rows stay as immutable legacy
-- evidence and are deliberately excluded from the V1 editor.
update public.pachanga_player_reward_inventory inventory
set reward_key = replacements.cosmetic_key
from (values
  ('symbol.ball', 'player.frame.barrio.steel'),
  ('pattern.stripes', 'player.background.asphalt_night'),
  ('pattern.diagonal', 'player.frame.barrio.copper'),
  ('border.double', 'player.background.grid_iq'),
  ('border.silver', 'player.frame.barrio.silver'),
  ('border.laurel', 'player.effect.spotlights'),
  ('border.gold', 'player.frame.future.navy'),
  ('symbol.crown', 'player.effect.iq_scan'),
  ('effect.glow', 'player.frame.retro.chrome')
) as replacements(legacy_key, cosmetic_key)
where inventory.reward_kind = 'player_cosmetic'
  and inventory.reward_key = replacements.legacy_key
  and not exists (
    select 1
    from public.pachanga_player_reward_inventory canonical
    where canonical.player_profile_id = inventory.player_profile_id
      and canonical.reward_kind = 'player_cosmetic'
      and canonical.reward_key = replacements.cosmetic_key
  );

alter table public.pachanga_player_reward_inventory
  add column if not exists seen_at timestamptz,
  add column if not exists revision bigint not null default 1,
  add column if not exists server_sequence bigint not null
    default nextval('public.pachanga_progression_sequence'),
  add column if not exists updated_at timestamptz not null default clock_timestamp();

-- Existing inventory was already visible in the old product surface. Avoid
-- presenting historical rows as newly acquired after this migration.
update public.pachanga_player_reward_inventory
set seen_at = coalesce(seen_at, acquired_at, unlocked_at),
    updated_at = clock_timestamp()
where seen_at is null;

alter table public.pachanga_player_reward_inventory
  drop constraint if exists pachanga_player_reward_inventory_revision_check,
  add constraint pachanga_player_reward_inventory_revision_check
    check (revision >= 1);

create index if not exists pachanga_player_reward_inventory_unseen_idx
  on public.pachanga_player_reward_inventory(
    player_profile_id, reward_kind, acquired_at desc, reward_key
  ) where state = 'unlocked' and seen_at is null;

drop policy if exists "Shared players read personal reward inventory"
  on public.pachanga_player_reward_inventory;
drop policy if exists "Players read their own reward inventory"
  on public.pachanga_player_reward_inventory;
create policy "Players read their own reward inventory"
on public.pachanga_player_reward_inventory
for select to authenticated
using (exists (
  select 1
  from public.pachanga_player_profiles profiles
  where profiles.id = player_profile_id
    and profiles.user_id = (select auth.uid())
));

create table if not exists public.pachanga_player_cosmetic_loadouts (
  player_profile_id uuid primary key
    references public.pachanga_player_profiles(id) on delete cascade,
  frame_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  background_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  accent_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  effect_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  title_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  featured_achievement_grant_id uuid
    references public.pachanga_achievement_grants(id) on delete set null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1)
);

create table if not exists public.pachanga_player_cosmetic_public_cards (
  player_profile_id uuid primary key
    references public.pachanga_player_profiles(id) on delete cascade,
  frame_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  background_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  accent_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  effect_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  title_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  featured_achievement_grant_id uuid
    references public.pachanga_achievement_grants(id) on delete set null,
  revision bigint not null,
  server_sequence bigint not null,
  updated_at timestamptz not null,
  check (revision >= 1)
);

create index if not exists pachanga_player_cosmetic_public_cards_sequence_idx
  on public.pachanga_player_cosmetic_public_cards(server_sequence desc, player_profile_id);

create table if not exists private.pachanga_player_cosmetic_operation_receipts (
  operation_id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  player_profile_id uuid not null
    references public.pachanga_player_profiles(id) on delete cascade,
  operation_kind text not null,
  request_hash text not null,
  response jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (operation_kind in ('mark_seen', 'save_loadout', 'equip_from_box')),
  check (jsonb_typeof(response) = 'object')
);

create index if not exists pachanga_player_cosmetic_receipts_profile_idx
  on private.pachanga_player_cosmetic_operation_receipts(
    player_profile_id, server_sequence desc, operation_id
  );

alter table public.pachanga_player_cosmetic_loadouts enable row level security;
alter table public.pachanga_player_cosmetic_public_cards enable row level security;

create or replace function public.can_read_pachanga_player_cosmetic_card_v1(
  target_player_profile_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select public.is_registered_pachanga_user()
    and (
      private.pachanga_can_read_player_progression_v1(target_player_profile_id)
      or exists (
        select 1
        from public.pachanga_player_profiles profiles
        where profiles.id = target_player_profile_id
          and profiles.market_enabled
      )
    );
$$;

revoke all on function public.can_read_pachanga_player_cosmetic_card_v1(uuid)
  from public, anon, authenticated;

revoke all on table public.pachanga_player_cosmetic_loadouts
  from public, anon, authenticated;
revoke all on table public.pachanga_player_cosmetic_public_cards
  from public, anon, authenticated;
revoke all on table private.pachanga_player_cosmetic_operation_receipts
  from public, anon, authenticated;

grant select on table public.pachanga_player_cosmetic_loadouts to authenticated;
grant select on table public.pachanga_player_cosmetic_public_cards to authenticated;
grant all on table public.pachanga_player_cosmetic_loadouts to service_role;
grant all on table public.pachanga_player_cosmetic_public_cards to service_role;
grant all on table private.pachanga_player_cosmetic_operation_receipts to service_role;

create policy "Players read their own cosmetic loadout"
on public.pachanga_player_cosmetic_loadouts
for select to authenticated
using (exists (
  select 1 from public.pachanga_player_profiles profiles
  where profiles.id = player_profile_id
    and profiles.user_id = (select auth.uid())
));

create policy "Registered users read allowed public cosmetic cards"
on public.pachanga_player_cosmetic_public_cards
for select to authenticated
using (
  public.can_read_pachanga_player_cosmetic_card_v1(player_profile_id)
);

create or replace function private.pachanga_player_cosmetics_enabled_v1()
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(settings.player_cosmetics_enabled, false)
  from private.pachanga_player_cosmetic_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_current_player_profile_id_v1()
returns uuid
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select profiles.id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = auth.uid()
  limit 1;
$$;

create or replace function private.pachanga_ensure_player_cosmetic_loadout_v1(
  target_player_profile_id uuid
)
returns public.pachanga_player_cosmetic_loadouts
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved public.pachanga_player_cosmetic_loadouts%rowtype;
begin
  insert into public.pachanga_player_cosmetic_loadouts(player_profile_id)
  values (target_player_profile_id)
  on conflict (player_profile_id) do nothing;

  select * into saved
  from public.pachanga_player_cosmetic_loadouts loadouts
  where loadouts.player_profile_id = target_player_profile_id;
  return saved;
end;
$$;

create or replace function private.pachanga_player_cosmetic_owned_v1(
  target_player_profile_id uuid,
  target_cosmetic_key text,
  target_slot text
)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select target_cosmetic_key is null or exists (
    select 1
    from public.pachanga_player_reward_inventory inventory
    join public.pachanga_cosmetic_catalog catalog
      on catalog.cosmetic_key = inventory.reward_key
    where inventory.player_profile_id = target_player_profile_id
      and inventory.reward_kind = 'player_cosmetic'
      and inventory.reward_key = target_cosmetic_key
      and inventory.state = 'unlocked'
      and catalog.owner_scope = 'player'
      and catalog.slot = target_slot
      and catalog.lifecycle = 'active_reward'
      and catalog.active
  );
$$;

create or replace function private.pachanga_sync_player_cosmetic_public_card_v1(
  target_player_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_player_cosmetic_public_cards(
    player_profile_id, frame_key, background_key, accent_key, effect_key,
    title_key, featured_achievement_grant_id, revision, server_sequence, updated_at
  )
  select loadouts.player_profile_id, loadouts.frame_key, loadouts.background_key,
    loadouts.accent_key, loadouts.effect_key, loadouts.title_key,
    loadouts.featured_achievement_grant_id, loadouts.revision,
    loadouts.server_sequence, loadouts.updated_at
  from public.pachanga_player_cosmetic_loadouts loadouts
  where loadouts.player_profile_id = target_player_profile_id
  on conflict (player_profile_id) do update set
    frame_key = excluded.frame_key,
    background_key = excluded.background_key,
    accent_key = excluded.accent_key,
    effect_key = excluded.effect_key,
    title_key = excluded.title_key,
    featured_achievement_grant_id = excluded.featured_achievement_grant_id,
    revision = excluded.revision,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function private.pachanga_player_cosmetic_loadout_sync_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_sync_player_cosmetic_public_card_v1(new.player_profile_id);
  return new;
end;
$$;

drop trigger if exists sync_pachanga_player_cosmetic_public_card_v1
  on public.pachanga_player_cosmetic_loadouts;
create trigger sync_pachanga_player_cosmetic_public_card_v1
after insert or update on public.pachanga_player_cosmetic_loadouts
for each row execute function private.pachanga_player_cosmetic_loadout_sync_trigger_v1();

create or replace function private.pachanga_player_cosmetic_inventory_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.reward_kind = 'player_cosmetic'
    and (
      tg_op = 'INSERT'
      or new.reward_kind is distinct from old.reward_kind
      or new.reward_key is distinct from old.reward_key
    )
    and not exists (
    select 1 from public.pachanga_cosmetic_catalog catalog
    where catalog.cosmetic_key = new.reward_key
      and catalog.owner_scope = 'player'
      and catalog.slot is not null
      and catalog.lifecycle = 'active_reward'
      and catalog.active
  ) then
    raise exception 'Player cosmetic is not active in the canonical catalog';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_pachanga_player_cosmetic_inventory_v1
  on public.pachanga_player_reward_inventory;
create trigger guard_pachanga_player_cosmetic_inventory_v1
before insert or update
on public.pachanga_player_reward_inventory
for each row execute function private.pachanga_player_cosmetic_inventory_guard_v1();

create or replace function private.pachanga_player_cosmetic_inventory_after_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_profile public.pachanga_player_profiles%rowtype;
  selected_catalog public.pachanga_cosmetic_catalog%rowtype;
  saved_sequence bigint;
begin
  if new.reward_kind <> 'player_cosmetic' or new.state <> 'unlocked' then
    return new;
  end if;

  select * into selected_profile
  from public.pachanga_player_profiles profiles
  where profiles.id = new.player_profile_id;
  select * into selected_catalog
  from public.pachanga_cosmetic_catalog catalog
  where catalog.cosmetic_key = new.reward_key;
  if not found then return new; end if;

  perform private.pachanga_ensure_player_cosmetic_loadout_v1(new.player_profile_id);
  saved_sequence := nextval('public.pachanga_progression_sequence');
  update public.pachanga_player_cosmetic_loadouts loadouts
  set revision = loadouts.revision + 1,
      server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where loadouts.player_profile_id = new.player_profile_id;

  perform private.pachanga_notify_v1(
    selected_profile.user_id,
    'player_reward_cosmetic_unlocked',
    'Nuevo cosmético desbloqueado',
    selected_catalog.display_name || ' ya está disponible para tu carta.',
    '/personalizar-carta?slot=' || selected_catalog.slot
      || '&item=' || selected_catalog.cosmetic_key,
    jsonb_build_object(
      'playerProfileId', new.player_profile_id,
      'cosmeticKey', selected_catalog.cosmetic_key,
      'slot', selected_catalog.slot,
      'sourceBoxId', new.source_box_id
    ),
    'player-cosmetic-unlocked:' || new.player_profile_id::text
      || ':' || selected_catalog.cosmetic_key
  );
  return new;
end;
$$;

drop trigger if exists notify_pachanga_player_cosmetic_inventory_v1
  on public.pachanga_player_reward_inventory;
create trigger notify_pachanga_player_cosmetic_inventory_v1
after insert on public.pachanga_player_reward_inventory
for each row execute function private.pachanga_player_cosmetic_inventory_after_insert_v1();

-- Historical player_cosmetic rows used team-shaped placeholders. They remain
-- as immutable history, but only canonical player items enter the V1 editor.
insert into public.pachanga_player_cosmetic_loadouts(player_profile_id)
select distinct inventory.player_profile_id
from public.pachanga_player_reward_inventory inventory
where inventory.reward_kind = 'player_cosmetic'
on conflict (player_profile_id) do nothing;

insert into public.pachanga_player_cosmetic_public_cards(
  player_profile_id, frame_key, background_key, accent_key, effect_key,
  title_key, featured_achievement_grant_id, revision, server_sequence, updated_at
)
select loadouts.player_profile_id, loadouts.frame_key, loadouts.background_key,
  loadouts.accent_key, loadouts.effect_key, loadouts.title_key,
  loadouts.featured_achievement_grant_id, loadouts.revision,
  loadouts.server_sequence, loadouts.updated_at
from public.pachanga_player_cosmetic_loadouts loadouts
on conflict (player_profile_id) do nothing;

create or replace function private.pachanga_player_cosmetics_snapshot_v1(
  target_player_profile_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with selected_loadout as (
    select loadouts.*
    from public.pachanga_player_cosmetic_loadouts loadouts
    where loadouts.player_profile_id = target_player_profile_id
  ), owned as (
    select inventory.reward_key, inventory.acquired_at, inventory.seen_at,
      inventory.source_box_id, inventory.revision as inventory_revision,
      inventory.server_sequence as inventory_sequence,
      catalog.display_name, catalog.description, catalog.rarity, catalog.slot,
      catalog.collection_key, catalog.material_key, catalog.render_contract,
      catalog.layer_order
    from public.pachanga_player_reward_inventory inventory
    join public.pachanga_cosmetic_catalog catalog
      on catalog.cosmetic_key = inventory.reward_key
    where inventory.player_profile_id = target_player_profile_id
      and inventory.reward_kind = 'player_cosmetic'
      and inventory.state = 'unlocked'
      and catalog.owner_scope = 'player'
      and catalog.lifecycle = 'active_reward'
      and catalog.active
  ), badges as (
    select grants.id, definitions.achievement_key, definitions.title,
      definitions.rarity, grants.occurred_at
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    where grants.subject_type = 'player'
      and grants.subject_id = target_player_profile_id
      and grants.state = 'active'
      and definitions.active
  )
  select jsonb_build_object(
    'enabled', private.pachanga_player_cosmetics_enabled_v1(),
    'playerProfileId', target_player_profile_id,
    'revision', coalesce((select revision from selected_loadout), 0),
    'serverSequence', coalesce((select server_sequence from selected_loadout), 0),
    'updatedAt', (select updated_at from selected_loadout),
    'loadout', jsonb_build_object(
      'frameKey', (select frame_key from selected_loadout),
      'backgroundKey', (select background_key from selected_loadout),
      'accentKey', (select accent_key from selected_loadout),
      'effectKey', (select effect_key from selected_loadout),
      'titleKey', (select title_key from selected_loadout),
      'featuredBadgeGrantId', (select featured_achievement_grant_id from selected_loadout)
    ),
    'owned', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', owned.reward_key,
        'name', owned.display_name,
        'description', owned.description,
        'rarity', owned.rarity,
        'slot', owned.slot,
        'collection', owned.collection_key,
        'material', owned.material_key,
        'render', owned.render_contract,
        'layerOrder', owned.layer_order,
        'acquiredAt', owned.acquired_at,
        'seenAt', owned.seen_at,
        'sourceBoxId', owned.source_box_id,
        'revision', owned.inventory_revision,
        'serverSequence', owned.inventory_sequence
      ) order by owned.slot, owned.layer_order, owned.acquired_at, owned.reward_key)
      from owned
    ), '[]'::jsonb),
    'featuredBadges', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', badges.id,
        'achievementKey', badges.achievement_key,
        'title', badges.title,
        'rarity', badges.rarity,
        'occurredAt', badges.occurred_at
      ) order by badges.occurred_at desc, badges.id desc)
      from badges
    ), '[]'::jsonb)
  );
$$;

create or replace function public.get_pachanga_player_cosmetics_snapshot_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  profile_id uuid;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  profile_id := private.pachanga_current_player_profile_id_v1();
  if profile_id is null then raise exception 'Player profile required'; end if;
  return private.pachanga_player_cosmetics_snapshot_v1(profile_id);
end;
$$;

create or replace function private.pachanga_player_featured_badge_public_v1(
  target_player_profile_id uuid,
  target_achievement_grant_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
set row_security = off
as $$
  select jsonb_build_object(
    'grantId', grants.id,
    'achievementKey', definitions.achievement_key,
    'title', definitions.title,
    'rarity', definitions.rarity
  )
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'player'
    and grants.subject_id = target_player_profile_id
    and grants.state = 'active'
    and definitions.active;
$$;

create or replace function public.get_pachanga_public_player_card_cosmetics_v1(
  target_player_profile_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_player_cosmetic_public_cards%rowtype;
  allowed boolean;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  select public.can_read_pachanga_player_cosmetic_card_v1(target_player_profile_id)
  into allowed;
  if not coalesce(allowed, false) then raise exception 'Player card access denied'; end if;

  select * into selected
  from public.pachanga_player_cosmetic_public_cards cards
  where cards.player_profile_id = target_player_profile_id;

  return jsonb_build_object(
    'enabled', private.pachanga_player_cosmetics_enabled_v1(),
    'playerProfileId', target_player_profile_id,
    'revision', coalesce(selected.revision, 0),
    'serverSequence', coalesce(selected.server_sequence, 0),
    'updatedAt', selected.updated_at,
    'loadout', jsonb_build_object(
      'frameKey', selected.frame_key,
      'backgroundKey', selected.background_key,
      'accentKey', selected.accent_key,
      'effectKey', selected.effect_key,
      'titleKey', selected.title_key,
      'featuredBadgeGrantId', selected.featured_achievement_grant_id
    ),
    'equipped', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.cosmetic_key,
        'name', catalog.display_name,
        'slot', catalog.slot,
        'material', catalog.material_key,
        'render', catalog.render_contract,
        'layerOrder', catalog.layer_order
      ) order by catalog.layer_order, catalog.cosmetic_key)
      from public.pachanga_cosmetic_catalog catalog
      where catalog.cosmetic_key in (
        selected.frame_key, selected.background_key, selected.accent_key,
        selected.effect_key, selected.title_key
      )
    ), '[]'::jsonb),
    'featuredBadge', private.pachanga_player_featured_badge_public_v1(
      target_player_profile_id,
      selected.featured_achievement_grant_id
    )
  );
end;
$$;

create or replace function private.pachanga_player_cosmetic_receipt_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_player_profile_id uuid,
  target_operation_kind text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  receipt private.pachanga_player_cosmetic_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_player_cosmetic_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_user_id <> target_actor_user_id
    or receipt.player_profile_id <> target_player_profile_id
    or receipt.operation_kind <> target_operation_kind
    or receipt.request_hash <> target_request_hash then
    raise exception 'Operation conflicts with existing cosmetic evidence';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_store_player_cosmetic_receipt_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_player_profile_id uuid,
  target_operation_kind text,
  target_request_hash text,
  target_response jsonb,
  target_server_sequence bigint
)
returns void
language sql
security definer
set search_path = pg_catalog
as $$
  insert into private.pachanga_player_cosmetic_operation_receipts(
    operation_id, actor_user_id, player_profile_id, operation_kind,
    request_hash, response, server_sequence
  ) values (
    target_operation_id, target_actor_user_id, target_player_profile_id,
    target_operation_kind, target_request_hash, target_response,
    target_server_sequence
  );
$$;

create or replace function public.mark_pachanga_player_cosmetics_seen_v1(
  target_cosmetic_keys text[],
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
  actor_id uuid := auth.uid();
  profile_id uuid;
  loadout public.pachanga_player_cosmetic_loadouts%rowtype;
  normalized_keys text[];
  request_hash text;
  existing_response jsonb;
  response jsonb;
  saved_sequence bigint;
  changed_count integer;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  if not private.pachanga_player_cosmetics_enabled_v1() then
    raise exception 'Player cosmetics are not enabled';
  end if;
  profile_id := private.pachanga_current_player_profile_id_v1();
  if profile_id is null then raise exception 'Player profile required'; end if;
  select coalesce(array_agg(distinct keys.key order by keys.key), '{}'::text[])
  into normalized_keys
  from unnest(coalesce(target_cosmetic_keys, '{}'::text[])) keys(key)
  where nullif(trim(keys.key), '') is not null;
  if coalesce(array_length(normalized_keys, 1), 0) = 0
    or array_length(normalized_keys, 1) > 50 then
    raise exception 'Between one and fifty cosmetic keys required';
  end if;
  request_hash := md5(jsonb_build_object(
    'keys', to_jsonb(normalized_keys),
    'expectedRevision', expected_revision,
    'clientMetadata', case when jsonb_typeof(client_metadata) = 'object'
      then client_metadata else '{}'::jsonb end
  )::text);
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'mark_seen', request_hash
  );
  if existing_response is not null then return existing_response; end if;

  perform private.pachanga_ensure_player_cosmetic_loadout_v1(profile_id);
  select * into loadout
  from public.pachanga_player_cosmetic_loadouts loadouts
  where loadouts.player_profile_id = profile_id
  for update;
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'mark_seen', request_hash
  );
  if existing_response is not null then return existing_response; end if;
  if loadout.revision <> expected_revision then
    raise exception 'Cosmetic state revision is newer. Reload the confirmed state.'
      using errcode = 'PT409';
  end if;
  if exists (
    select 1 from unnest(normalized_keys) requested(key)
    where not exists (
      select 1 from public.pachanga_player_reward_inventory inventory
      join public.pachanga_cosmetic_catalog catalog
        on catalog.cosmetic_key = inventory.reward_key
      where inventory.player_profile_id = profile_id
        and inventory.reward_kind = 'player_cosmetic'
        and inventory.reward_key = requested.key
        and inventory.state = 'unlocked'
        and catalog.owner_scope = 'player'
        and catalog.lifecycle = 'active_reward'
        and catalog.active
    )
  ) then raise exception 'Cannot mark an unowned cosmetic as seen'; end if;

  saved_sequence := nextval('public.pachanga_progression_sequence');
  update public.pachanga_player_reward_inventory inventory
  set seen_at = clock_timestamp(),
      revision = inventory.revision + 1,
      server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where inventory.player_profile_id = profile_id
    and inventory.reward_kind = 'player_cosmetic'
    and inventory.reward_key = any(normalized_keys)
    and inventory.state = 'unlocked'
    and inventory.seen_at is null;
  get diagnostics changed_count = row_count;

  if changed_count > 0 then
    update public.pachanga_player_cosmetic_loadouts loadouts
    set revision = loadouts.revision + 1,
        server_sequence = saved_sequence,
        updated_at = clock_timestamp()
    where loadouts.player_profile_id = profile_id;
  end if;
  response := private.pachanga_player_cosmetics_snapshot_v1(profile_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', case when changed_count > 0
        then expected_revision + 1 else expected_revision end,
      'serverSequence', case when changed_count > 0
        then saved_sequence else loadout.server_sequence end,
      'confirmedAt', clock_timestamp(),
      'markedSeen', changed_count
    );
  perform private.pachanga_store_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'mark_seen', request_hash,
    response, coalesce((response ->> 'serverSequence')::bigint, 0)
  );
  return response;
end;
$$;

create or replace function public.save_pachanga_player_cosmetic_loadout_v1(
  target_loadout jsonb,
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
  actor_id uuid := auth.uid();
  profile_id uuid;
  loadout public.pachanga_player_cosmetic_loadouts%rowtype;
  next_frame text;
  next_background text;
  next_accent text;
  next_effect text;
  next_title text;
  next_badge uuid;
  request_hash text;
  existing_response jsonb;
  response jsonb;
  saved_sequence bigint;
begin
  if actor_id is null or operation_id is null or expected_revision is null
    or jsonb_typeof(target_loadout) <> 'object' then
    raise exception 'Authentication, loadout, operation id and expected revision required';
  end if;
  if not private.pachanga_player_cosmetics_enabled_v1() then
    raise exception 'Player cosmetics are not enabled';
  end if;
  if target_loadout - array[
    'frameKey', 'backgroundKey', 'accentKey', 'effectKey', 'titleKey',
    'featuredBadgeGrantId'
  ] <> '{}'::jsonb then
    raise exception 'Unsupported player cosmetic loadout field';
  end if;
  profile_id := private.pachanga_current_player_profile_id_v1();
  if profile_id is null then raise exception 'Player profile required'; end if;

  next_frame := nullif(trim(target_loadout ->> 'frameKey'), '');
  next_background := nullif(trim(target_loadout ->> 'backgroundKey'), '');
  next_accent := nullif(trim(target_loadout ->> 'accentKey'), '');
  next_effect := nullif(trim(target_loadout ->> 'effectKey'), '');
  next_title := nullif(trim(target_loadout ->> 'titleKey'), '');
  begin
    next_badge := nullif(trim(target_loadout ->> 'featuredBadgeGrantId'), '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Featured badge grant id must be a UUID';
  end;

  if not private.pachanga_player_cosmetic_owned_v1(profile_id, next_frame, 'frame')
    or not private.pachanga_player_cosmetic_owned_v1(profile_id, next_background, 'background')
    or not private.pachanga_player_cosmetic_owned_v1(profile_id, next_accent, 'accent')
    or not private.pachanga_player_cosmetic_owned_v1(profile_id, next_effect, 'effect')
    or not private.pachanga_player_cosmetic_owned_v1(profile_id, next_title, 'title') then
    raise exception 'Cannot equip an unowned player cosmetic';
  end if;
  if next_badge is not null and not exists (
    select 1 from public.pachanga_achievement_grants grants
    where grants.id = next_badge
      and grants.subject_type = 'player'
      and grants.subject_id = profile_id
      and grants.state = 'active'
  ) then raise exception 'Cannot feature an achievement the player has not earned'; end if;

  request_hash := md5(jsonb_build_object(
    'loadout', target_loadout,
    'expectedRevision', expected_revision,
    'clientMetadata', case when jsonb_typeof(client_metadata) = 'object'
      then client_metadata else '{}'::jsonb end
  )::text);
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'save_loadout', request_hash
  );
  if existing_response is not null then return existing_response; end if;

  perform private.pachanga_ensure_player_cosmetic_loadout_v1(profile_id);
  select * into loadout
  from public.pachanga_player_cosmetic_loadouts loadouts
  where loadouts.player_profile_id = profile_id
  for update;
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'save_loadout', request_hash
  );
  if existing_response is not null then return existing_response; end if;
  if loadout.revision <> expected_revision then
    raise exception 'Cosmetic state revision is newer. Reload the confirmed state.'
      using errcode = 'PT409';
  end if;

  saved_sequence := nextval('public.pachanga_progression_sequence');
  update public.pachanga_player_cosmetic_loadouts loadouts
  set frame_key = next_frame,
      background_key = next_background,
      accent_key = next_accent,
      effect_key = next_effect,
      title_key = next_title,
      featured_achievement_grant_id = next_badge,
      revision = loadouts.revision + 1,
      server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where loadouts.player_profile_id = profile_id;

  response := private.pachanga_player_cosmetics_snapshot_v1(profile_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', expected_revision + 1,
      'serverSequence', saved_sequence,
      'confirmedAt', clock_timestamp()
    );
  perform private.pachanga_store_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'save_loadout', request_hash,
    response, saved_sequence
  );
  return response;
end;
$$;

create or replace function public.equip_pachanga_player_cosmetic_from_box_v1(
  target_box_id uuid,
  target_cosmetic_key text,
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
  actor_id uuid := auth.uid();
  profile_id uuid;
  selected_inventory public.pachanga_player_reward_inventory%rowtype;
  selected_catalog public.pachanga_cosmetic_catalog%rowtype;
  loadout public.pachanga_player_cosmetic_loadouts%rowtype;
  request_hash text;
  existing_response jsonb;
  response jsonb;
  saved_sequence bigint;
begin
  if actor_id is null or target_box_id is null or operation_id is null
    or expected_revision is null or nullif(trim(target_cosmetic_key), '') is null then
    raise exception 'Authentication, box, cosmetic, operation id and expected revision required';
  end if;
  if not private.pachanga_player_cosmetics_enabled_v1() then
    raise exception 'Player cosmetics are not enabled';
  end if;
  profile_id := private.pachanga_current_player_profile_id_v1();
  if profile_id is null then raise exception 'Player profile required'; end if;
  request_hash := md5(jsonb_build_object(
    'boxId', target_box_id,
    'cosmeticKey', target_cosmetic_key,
    'expectedRevision', expected_revision,
    'clientMetadata', case when jsonb_typeof(client_metadata) = 'object'
      then client_metadata else '{}'::jsonb end
  )::text);
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'equip_from_box', request_hash
  );
  if existing_response is not null then return existing_response; end if;

  if not exists (
    select 1 from public.pachanga_reward_recipients recipients
    where recipients.box_id = target_box_id
      and recipients.user_id = actor_id
      and recipients.player_profile_id = profile_id
      and recipients.status = 'opened'
      and recipients.revealed_payload -> 'grant' ->> 'cosmeticKey' = target_cosmetic_key
      and coalesce((recipients.revealed_payload -> 'grant' ->> 'cosmeticGranted')::boolean, false)
  ) then raise exception 'Box did not grant this player cosmetic'; end if;

  select inventory.* into selected_inventory
  from public.pachanga_player_reward_inventory inventory
  where inventory.player_profile_id = profile_id
    and inventory.reward_kind = 'player_cosmetic'
    and inventory.reward_key = target_cosmetic_key
    and inventory.source_box_id = target_box_id
    and inventory.state = 'unlocked'
  for update;
  if not found then raise exception 'Player cosmetic ownership not found'; end if;
  select * into selected_catalog
  from public.pachanga_cosmetic_catalog catalog
  where catalog.cosmetic_key = target_cosmetic_key
    and catalog.owner_scope = 'player'
    and catalog.lifecycle = 'active_reward'
    and catalog.active;
  if not found then raise exception 'Player cosmetic is not active'; end if;

  perform private.pachanga_ensure_player_cosmetic_loadout_v1(profile_id);
  select * into loadout
  from public.pachanga_player_cosmetic_loadouts loadouts
  where loadouts.player_profile_id = profile_id
  for update;
  existing_response := private.pachanga_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'equip_from_box', request_hash
  );
  if existing_response is not null then return existing_response; end if;
  if loadout.revision <> expected_revision then
    raise exception 'Cosmetic state revision is newer. Reload the confirmed state.'
      using errcode = 'PT409';
  end if;

  saved_sequence := nextval('public.pachanga_progression_sequence');
  update public.pachanga_player_reward_inventory inventory
  set seen_at = coalesce(inventory.seen_at, clock_timestamp()),
      revision = case when inventory.seen_at is null
        then inventory.revision + 1 else inventory.revision end,
      server_sequence = case when inventory.seen_at is null
        then saved_sequence else inventory.server_sequence end,
      updated_at = clock_timestamp()
  where inventory.player_profile_id = profile_id
    and inventory.reward_kind = 'player_cosmetic'
    and inventory.reward_key = target_cosmetic_key;

  update public.pachanga_player_cosmetic_loadouts loadouts
  set frame_key = case when selected_catalog.slot = 'frame'
        then target_cosmetic_key else loadouts.frame_key end,
      background_key = case when selected_catalog.slot = 'background'
        then target_cosmetic_key else loadouts.background_key end,
      accent_key = case when selected_catalog.slot = 'accent'
        then target_cosmetic_key else loadouts.accent_key end,
      effect_key = case when selected_catalog.slot = 'effect'
        then target_cosmetic_key else loadouts.effect_key end,
      title_key = case when selected_catalog.slot = 'title'
        then target_cosmetic_key else loadouts.title_key end,
      revision = loadouts.revision + 1,
      server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where loadouts.player_profile_id = profile_id;

  response := private.pachanga_player_cosmetics_snapshot_v1(profile_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', expected_revision + 1,
      'serverSequence', saved_sequence,
      'confirmedAt', clock_timestamp(),
      'equippedFromBoxId', target_box_id,
      'equippedCosmeticKey', target_cosmetic_key
    );
  perform private.pachanga_store_player_cosmetic_receipt_v1(
    operation_id, actor_id, profile_id, 'equip_from_box', request_hash,
    response, saved_sequence
  );
  return response;
end;
$$;

revoke all on function private.pachanga_player_cosmetics_enabled_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_current_player_profile_id_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_ensure_player_cosmetic_loadout_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetic_owned_v1(uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_sync_player_cosmetic_public_card_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetic_loadout_sync_trigger_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetic_inventory_guard_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetic_inventory_after_insert_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetics_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_player_featured_badge_public_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_player_cosmetic_receipt_v1(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_store_player_cosmetic_receipt_v1(
  uuid, uuid, uuid, text, text, jsonb, bigint
) from public, anon, authenticated;

revoke all on function public.get_pachanga_player_cosmetics_snapshot_v1()
  from public, anon, authenticated;
grant execute on function public.get_pachanga_player_cosmetics_snapshot_v1()
  to authenticated;
grant execute on function public.can_read_pachanga_player_cosmetic_card_v1(uuid)
  to authenticated;
revoke all on function public.get_pachanga_public_player_card_cosmetics_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_public_player_card_cosmetics_v1(uuid)
  to authenticated;
revoke all on function public.mark_pachanga_player_cosmetics_seen_v1(
  text[], uuid, bigint, jsonb
) from public, anon, authenticated;
grant execute on function public.mark_pachanga_player_cosmetics_seen_v1(
  text[], uuid, bigint, jsonb
) to authenticated;
revoke all on function public.save_pachanga_player_cosmetic_loadout_v1(
  jsonb, uuid, bigint, jsonb
) from public, anon, authenticated;
grant execute on function public.save_pachanga_player_cosmetic_loadout_v1(
  jsonb, uuid, bigint, jsonb
) to authenticated;
revoke all on function public.equip_pachanga_player_cosmetic_from_box_v1(
  uuid, text, uuid, bigint, jsonb
) from public, anon, authenticated;
grant execute on function public.equip_pachanga_player_cosmetic_from_box_v1(
  uuid, text, uuid, bigint, jsonb
) to authenticated;

alter function public.mark_pachanga_player_cosmetics_seen_v1(
  text[], uuid, bigint, jsonb
) set lock_timeout = '750ms';
alter function public.save_pachanga_player_cosmetic_loadout_v1(
  jsonb, uuid, bigint, jsonb
) set lock_timeout = '750ms';
alter function public.equip_pachanga_player_cosmetic_from_box_v1(
  uuid, text, uuid, bigint, jsonb
) set lock_timeout = '750ms';

alter table public.pachanga_player_cosmetic_loadouts replica identity full;
alter table public.pachanga_player_cosmetic_public_cards replica identity full;
alter table public.pachanga_player_reward_inventory replica identity full;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'pachanga_player_cosmetic_loadouts',
    'pachanga_player_cosmetic_public_cards',
    'pachanga_player_reward_inventory'
  ] loop
    if not exists (
      select 1 from pg_publication_tables publication_tables
      where publication_tables.pubname = 'supabase_realtime'
        and publication_tables.schemaname = 'public'
        and publication_tables.tablename = target_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        target_table
      );
    end if;
  end loop;
end;
$$;

comment on table public.pachanga_player_cosmetic_loadouts is
  'Authoritative personal card loadout and aggregate cosmetic revision. Cosmetic state never changes sporting values.';
comment on table public.pachanga_player_cosmetic_public_cards is
  'Safe read model exposing only equipped personal cosmetics and a featured earned achievement.';
comment on function public.save_pachanga_player_cosmetic_loadout_v1(jsonb, uuid, bigint, jsonb) is
  'Idempotent server-authoritative player cosmetic save with ownership and stale-revision validation.';
