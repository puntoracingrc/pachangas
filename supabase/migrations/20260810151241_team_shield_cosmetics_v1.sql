-- Pachangas IQ Team Shield Cosmetics V1 visual foundation.
-- Clean visual replacement: sporting/team data stays untouched and legacy crest
-- tables remain historical only. The new system is disabled by default.

create table if not exists private.pachanga_team_cosmetic_settings (
  singleton boolean primary key default true check (singleton),
  team_cosmetics_enabled boolean not null default false,
  team_cosmetic_rewards_enabled boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);

insert into private.pachanga_team_cosmetic_settings(
  singleton, team_cosmetics_enabled, team_cosmetic_rewards_enabled
) values (true, false, false)
on conflict (singleton) do nothing;

revoke all on table private.pachanga_team_cosmetic_settings from public, anon, authenticated;
grant all on table private.pachanga_team_cosmetic_settings to service_role;

alter table public.pachanga_cosmetic_catalog
  drop constraint if exists pachanga_cosmetic_catalog_slot_check;
alter table public.pachanga_cosmetic_catalog
  add constraint pachanga_cosmetic_catalog_slot_check check (
    (owner_scope = 'player' and slot in ('frame', 'background', 'accent', 'effect', 'title'))
    or (owner_scope = 'team' and (
      slot is null or slot in (
        'shape', 'background', 'pattern', 'primary_symbol', 'secondary_symbol',
        'border', 'ornament', 'top_ornament', 'side_ornament', 'bottom_ornament', 'effect'
      )
    ))
  );

-- New base library. It is intentionally independent from the legacy crest catalog.
insert into public.pachanga_cosmetic_catalog(
  cosmetic_key, version, family, display_name, description, rarity,
  availability, render_contract, layer_order, active,
  owner_scope, slot, collection_key, material_key, lifecycle
) values
  ('team.shield.shape.classic_iq',1,'shape','Clásico IQ','Silueta principal de Pachangas IQ.','common','base','{"shape":"classic_iq"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.round',1,'shape','Redondo','Emblema circular de lectura inmediata.','common','base','{"shape":"round"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.tall',1,'shape','Alto','Escudo vertical de presencia competitiva.','common','base','{"shape":"tall"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.swiss',1,'shape','Suizo','Hombros rectos y punta contenida.','common','base','{"shape":"swiss"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.hex_iq',1,'shape','Hex IQ','Geometría técnica propia de Future IQ.','common','base','{"shape":"hex_iq"}',10,true,'team','shape','base_iq','navy','active_reward'),
  ('team.shield.shape.diamond',1,'shape','Diamante','Silueta angular y ligera.','common','base','{"shape":"diamond"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.modern',1,'shape','Modern Crest','Curvas tensas y base moderna.','common','base','{"shape":"modern"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.shape.barrio',1,'shape','Barrio Shield','Escudo robusto de fútbol de barrio.','common','base','{"shape":"barrio"}',10,true,'team','shape','base_iq',null,'active_reward'),
  ('team.shield.color.midnight',1,'color','Midnight','Azul noche profundo.','common','base','{"hex":"#071b31"}',12,true,'team',null,'base_iq','navy','active_reward'),
  ('team.shield.color.cyan',1,'color','Cian IQ','Acento tecnológico de Pachangas IQ.','common','base','{"hex":"#33d6dd"}',12,true,'team',null,'base_iq','cyan_iq','active_reward'),
  ('team.shield.color.ivory',1,'color','Marfil','Blanco cálido de alta lectura.','common','base','{"hex":"#f1f4ea"}',12,true,'team',null,'base_iq','pearl','active_reward'),
  ('team.shield.color.crimson',1,'color','Carmesí','Rojo deportivo contenido.','common','base','{"hex":"#b52838"}',12,true,'team',null,'base_iq',null,'active_reward'),
  ('team.shield.color.emerald',1,'color','Esmeralda','Verde de campo profundo.','common','base','{"hex":"#08765d"}',12,true,'team',null,'base_iq',null,'active_reward'),
  ('team.shield.color.amber',1,'color','Ámbar','Amarillo cálido competitivo.','common','base','{"hex":"#efb82e"}',12,true,'team',null,'base_iq',null,'active_reward'),
  ('team.shield.background.duotone',1,'pattern','Dúo','Base de dos tonos equilibrada.','common','base','{"background":"duotone"}',20,true,'team','background','base_iq',null,'active_reward'),
  ('team.shield.background.solid',1,'pattern','Liso','Color principal limpio.','common','base','{"background":"solid"}',20,true,'team','background','base_iq',null,'active_reward'),
  ('team.shield.background.split',1,'pattern','Partido','Dos campos verticales.','common','base','{"background":"split"}',20,true,'team','background','base_iq',null,'active_reward'),
  ('team.shield.pattern.none',1,'pattern','Sin trama','Superficie limpia.','common','base','{"pattern":"none"}',30,true,'team','pattern','base_iq',null,'active_reward'),
  ('team.shield.pattern.diagonal',1,'pattern','Diagonal','Franja diagonal deportiva.','common','base','{"pattern":"diagonal"}',30,true,'team','pattern','base_iq',null,'active_reward'),
  ('team.shield.pattern.stripes',1,'pattern','Franjas','Franjas verticales compactas.','common','base','{"pattern":"stripes"}',30,true,'team','pattern','base_iq',null,'active_reward'),
  ('team.shield.pattern.chevron',1,'pattern','Chevron','V central con profundidad.','common','base','{"pattern":"chevron"}',30,true,'team','pattern','base_iq',null,'active_reward'),
  ('team.shield.symbol.ball_iq',1,'symbol','Balón IQ','Balón geométrico propio.','common','base','{"symbol":"ball_iq"}',40,true,'team','primary_symbol','base_iq',null,'active_reward'),
  ('team.shield.symbol.monogram',1,'symbol','Monograma','Inicial central como símbolo.','common','base','{"symbol":"monogram"}',40,true,'team','primary_symbol','base_iq',null,'active_reward'),
  ('team.shield.symbol.star_iq',1,'symbol','Estrella IQ','Estrella técnica de ocho puntas.','common','base','{"symbol":"star_iq"}',40,true,'team','primary_symbol','base_iq',null,'active_reward'),
  ('team.shield.symbol.bolt',1,'symbol','Rayo','Rayo angular de energía.','common','base','{"symbol":"bolt"}',40,true,'team','primary_symbol','base_iq',null,'active_reward'),
  ('team.shield.symbol.tower',1,'symbol','Torre','Torre geométrica de barrio.','common','base','{"symbol":"tower"}',40,true,'team','primary_symbol','base_iq',null,'active_reward'),
  ('team.shield.border.clean',1,'border','Contorno IQ','Doble línea limpia de alto contraste.','common','base','{"border":"clean","material":"pearl"}',50,true,'team','border','base_iq','pearl','active_reward'),
  ('team.shield.border.double',1,'border','Doble','Marco doble deportivo.','common','base','{"border":"double","material":"steel"}',50,true,'team','border','base_iq','steel','active_reward'),
  ('team.shield.border.steel',1,'border','Acero','Acero cepillado sobrio.','common','achievement','{"border":"material","material":"steel"}',50,true,'team','border','futbol_de_barrio','steel','active_reward'),
  ('team.shield.border.copper',1,'border','Cobre','Cobre cálido con contraste alto.','uncommon','achievement','{"border":"material","material":"copper"}',50,true,'team','border','futbol_de_barrio','copper','active_reward'),
  ('team.shield.border.silver',1,'border','Plata','Plata satinada de alta lectura.','rare','achievement','{"border":"material","material":"silver"}',50,true,'team','border','retro','silver','active_reward'),
  ('team.shield.border.navy',1,'border','Navy','Marco técnico azul oscuro.','epic','achievement','{"border":"material","material":"navy"}',50,true,'team','border','future_iq','navy','active_reward'),
  ('team.shield.border.carbon',1,'border','Carbono','Carbono mate de baja reflexión.','epic','achievement','{"border":"material","material":"carbon"}',50,true,'team','border','future_iq','carbon','active_reward'),
  ('team.shield.pattern.grid_iq',1,'pattern','Grid IQ','Retícula táctica discreta.','uncommon','achievement','{"pattern":"grid_iq"}',30,true,'team','pattern','future_iq','navy','active_reward'),
  ('team.shield.pattern.retro',1,'pattern','Retro','Franjas estrechas clásicas.','rare','achievement','{"pattern":"retro"}',30,true,'team','pattern','retro',null,'active_reward'),
  ('team.shield.symbol.tower_elite',1,'symbol','Torre Elite','Torre doble con placa inferior.','uncommon','achievement','{"symbol":"tower_elite"}',40,true,'team','primary_symbol','futbol_de_barrio','steel','active_reward'),
  ('team.shield.symbol.iq_star',1,'symbol','Estrella Future','Estrella facetada de Future IQ.','rare','achievement','{"symbol":"iq_star"}',40,true,'team','primary_symbol','future_iq','cyan_iq','active_reward'),
  ('team.shield.ornament.crown',1,'adornment','Corona Geométrica','Corona superior de líneas limpias.','epic','achievement','{"ornament":"crown","anchor":"top"}',60,true,'team','top_ornament','noche_de_partido','gold','active_reward'),
  ('team.shield.ornament.three_stars',1,'adornment','Tres Estrellas','Tres estrellas compactas.','rare','achievement','{"ornament":"three_stars","anchor":"top"}',60,true,'team','top_ornament','retro','silver','active_reward'),
  ('team.shield.ornament.laurels',1,'adornment','Laureles','Laureles laterales de competición.','rare','achievement','{"ornament":"laurels","anchor":"sides"}',60,true,'team','side_ornament','retro','silver','active_reward'),
  ('team.shield.ornament.banner',1,'adornment','Banner','Cinta inferior de identidad.','uncommon','achievement','{"ornament":"banner","anchor":"bottom"}',60,true,'team','bottom_ornament','futbol_de_barrio','copper','active_reward'),
  ('team.shield.effect.glint',1,'effect','Glint','Reflejo diagonal contenido.','legendary','achievement','{"effect":"glint"}',70,true,'team','effect','noche_de_partido','gold','active_reward'),
  ('team.shield.effect.scan',1,'effect','Scan','Línea cian que recorre el escudo.','epic','achievement','{"effect":"scan"}',70,true,'team','effect','future_iq','cyan_iq','active_reward'),
  ('team.shield.effect.edge_glow',1,'effect','Edge Glow','Resplandor limitado al contorno.','rare','achievement','{"effect":"edge_glow"}',70,true,'team','effect','future_iq','cyan_iq','active_reward')
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

-- Existing reward rows remain historical. New shield ownership is team scoped
-- and only the new team.shield namespace is read by V1.
alter table public.pachanga_team_cosmetic_inventory
  alter column source_grant_id drop not null,
  add column if not exists operation_id uuid,
  add column if not exists source_kind text not null default 'legacy_achievement',
  add column if not exists server_sequence bigint,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.pachanga_team_cosmetic_inventory inventory
set server_sequence = nextval('public.pachanga_team_crest_sequence')
where inventory.server_sequence is null;

alter table public.pachanga_team_cosmetic_inventory
  alter column server_sequence set default nextval('public.pachanga_team_crest_sequence'),
  alter column server_sequence set not null;
alter table public.pachanga_team_cosmetic_inventory
  drop constraint if exists pachanga_team_cosmetic_inventory_source_kind_check,
  drop constraint if exists pachanga_team_cosmetic_inventory_metadata_check,
  drop constraint if exists pachanga_team_cosmetic_inventory_source_check,
  add constraint pachanga_team_cosmetic_inventory_source_kind_check check (
    source_kind in ('legacy_achievement','achievement','admin','staging_fixture','future_top','future_tournament')
  ),
  add constraint pachanga_team_cosmetic_inventory_metadata_check check (jsonb_typeof(metadata) = 'object'),
  add constraint pachanga_team_cosmetic_inventory_source_check check (source_grant_id is not null or operation_id is not null);

create unique index if not exists pachanga_team_cosmetic_inventory_operation_idx
  on public.pachanga_team_cosmetic_inventory(operation_id) where operation_id is not null;
create index if not exists pachanga_team_cosmetic_inventory_sequence_idx
  on public.pachanga_team_cosmetic_inventory(group_id, server_sequence desc, cosmetic_key);

create table if not exists public.pachanga_team_shield_state (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_team_crest_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 0),
  check (server_sequence >= 1)
);

create table if not exists public.pachanga_team_shield_loadouts (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null,
  config jsonb not null,
  updated_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null,
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(config) = 'object')
);

create table if not exists public.pachanga_team_shield_versions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  version_number integer not null,
  previous_version_id uuid references public.pachanga_team_shield_versions(id) on delete restrict,
  config jsonb not null,
  operation_id uuid not null unique,
  saved_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (group_id, version_number),
  check (version_number >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(config) = 'object')
);

create index if not exists pachanga_team_shield_versions_group_idx
  on public.pachanga_team_shield_versions(group_id, version_number desc, id desc);

create table if not exists public.pachanga_team_shield_public (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null,
  config jsonb not null,
  equipped jsonb not null default '[]'::jsonb,
  server_sequence bigint not null,
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(config) = 'object'),
  check (jsonb_typeof(equipped) = 'array')
);

create table if not exists public.pachanga_team_cosmetic_admin_eligibility (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  eligible_since timestamptz not null,
  seen_revision bigint not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (group_id, admin_user_id),
  check (role in ('owner','admin')),
  check (seen_revision >= 0)
);

create table if not exists public.pachanga_team_cosmetic_seen (
  group_id uuid not null,
  cosmetic_key text not null,
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  seen_at timestamptz not null default clock_timestamp(),
  server_sequence bigint not null default nextval('public.pachanga_team_crest_sequence'),
  primary key (group_id, cosmetic_key, admin_user_id),
  foreign key (group_id, cosmetic_key)
    references public.pachanga_team_cosmetic_inventory(group_id, cosmetic_key) on delete cascade
);

create index if not exists pachanga_team_cosmetic_seen_admin_idx
  on public.pachanga_team_cosmetic_seen(admin_user_id, group_id, server_sequence desc, cosmetic_key);

create table if not exists public.pachanga_team_shield_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  event_type text not null,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  cosmetic_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, event_type),
  check (event_type in ('team_cosmetic_granted','team_cosmetic_already_owned','team_cosmetic_seen','team_shield_saved')),
  check (confirmed_revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists pachanga_team_shield_events_sequence_idx
  on public.pachanga_team_shield_events(server_sequence, id);
create index if not exists pachanga_team_shield_events_group_idx
  on public.pachanga_team_shield_events(group_id, server_sequence desc, id desc);

create table if not exists public.pachanga_team_shield_operation_receipts (
  operation_id uuid primary key,
  operation_kind text not null,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete restrict,
  request_hash text not null,
  expected_revision bigint not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (operation_kind in ('grant','mark_seen','save')),
  check (expected_revision >= 0 and confirmed_revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

alter table public.pachanga_team_shield_state enable row level security;
alter table public.pachanga_team_shield_loadouts enable row level security;
alter table public.pachanga_team_shield_versions enable row level security;
alter table public.pachanga_team_shield_public enable row level security;
alter table public.pachanga_team_cosmetic_admin_eligibility enable row level security;
alter table public.pachanga_team_cosmetic_seen enable row level security;
alter table public.pachanga_team_shield_events enable row level security;
alter table public.pachanga_team_shield_operation_receipts enable row level security;

revoke all on table public.pachanga_team_shield_state from public, anon, authenticated;
revoke all on table public.pachanga_team_shield_loadouts from public, anon, authenticated;
revoke all on table public.pachanga_team_shield_versions from public, anon, authenticated;
revoke all on table public.pachanga_team_shield_public from public, anon, authenticated;
revoke all on table public.pachanga_team_cosmetic_admin_eligibility from public, anon, authenticated;
revoke all on table public.pachanga_team_cosmetic_seen from public, anon, authenticated;
revoke all on table public.pachanga_team_shield_events from public, anon, authenticated;
revoke all on table public.pachanga_team_shield_operation_receipts from public, anon, authenticated;

grant select on table public.pachanga_team_shield_state to authenticated;
grant select on table public.pachanga_team_shield_loadouts to authenticated;
grant select on table public.pachanga_team_shield_versions to authenticated;
grant select on table public.pachanga_team_shield_public to authenticated;
grant select on table public.pachanga_team_cosmetic_admin_eligibility to authenticated;
grant select on table public.pachanga_team_cosmetic_seen to authenticated;
grant select on table public.pachanga_team_shield_events to authenticated;
grant select on table public.pachanga_team_shield_operation_receipts to authenticated;

grant all on table public.pachanga_team_shield_state to service_role;
grant all on table public.pachanga_team_shield_loadouts to service_role;
grant all on table public.pachanga_team_shield_versions to service_role;
grant all on table public.pachanga_team_shield_public to service_role;
grant all on table public.pachanga_team_cosmetic_admin_eligibility to service_role;
grant all on table public.pachanga_team_cosmetic_seen to service_role;
grant all on table public.pachanga_team_shield_events to service_role;
grant all on table public.pachanga_team_shield_operation_receipts to service_role;

drop policy if exists "Members read team cosmetic inventory" on public.pachanga_team_cosmetic_inventory;
drop policy if exists "Admins read team cosmetic inventory" on public.pachanga_team_cosmetic_inventory;
create policy "Admins read team cosmetic inventory"
on public.pachanga_team_cosmetic_inventory for select to authenticated
using (public.is_pachanga_group_admin(group_id));

drop policy if exists "Members read team shield state" on public.pachanga_team_shield_state;
create policy "Members read team shield state"
on public.pachanga_team_shield_state for select to authenticated
using (public.is_pachanga_group_member(group_id));

drop policy if exists "Admins read team shield loadout" on public.pachanga_team_shield_loadouts;
create policy "Admins read team shield loadout"
on public.pachanga_team_shield_loadouts for select to authenticated
using (public.is_pachanga_group_admin(group_id));

drop policy if exists "Admins read team shield versions" on public.pachanga_team_shield_versions;
create policy "Admins read team shield versions"
on public.pachanga_team_shield_versions for select to authenticated
using (public.is_pachanga_group_admin(group_id));

drop policy if exists "Members read public team shield" on public.pachanga_team_shield_public;
create policy "Members read public team shield"
on public.pachanga_team_shield_public for select to authenticated
using (public.is_pachanga_group_member(group_id));

drop policy if exists "Admins read own shield eligibility" on public.pachanga_team_cosmetic_admin_eligibility;
create policy "Admins read own shield eligibility"
on public.pachanga_team_cosmetic_admin_eligibility for select to authenticated
using (admin_user_id = (select auth.uid()) and public.is_pachanga_group_admin(group_id));

drop policy if exists "Admins read own shield seen state" on public.pachanga_team_cosmetic_seen;
create policy "Admins read own shield seen state"
on public.pachanga_team_cosmetic_seen for select to authenticated
using (admin_user_id = (select auth.uid()) and public.is_pachanga_group_admin(group_id));

drop policy if exists "Admins read team shield events" on public.pachanga_team_shield_events;
create policy "Admins read team shield events"
on public.pachanga_team_shield_events for select to authenticated
using (public.is_pachanga_group_admin(group_id));

drop policy if exists "Actors read own team shield receipts" on public.pachanga_team_shield_operation_receipts;
create policy "Actors read own team shield receipts"
on public.pachanga_team_shield_operation_receipts for select to authenticated
using (actor_user_id = (select auth.uid()));

revoke insert, update, delete on table public.pachanga_team_cosmetic_inventory from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_state from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_loadouts from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_versions from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_public from authenticated;
revoke insert, update, delete on table public.pachanga_team_cosmetic_admin_eligibility from authenticated;
revoke insert, update, delete on table public.pachanga_team_cosmetic_seen from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_events from authenticated;
revoke insert, update, delete on table public.pachanga_team_shield_operation_receipts from authenticated;

-- NEW starts when a user becomes eligible to edit this team, never when an
-- old item happened to be awarded.
alter table public.pachanga_group_members add column if not exists role_changed_at timestamptz;
update public.pachanga_group_members set role_changed_at = clock_timestamp() where role_changed_at is null;
alter table public.pachanga_group_members
  alter column role_changed_at set default clock_timestamp(),
  alter column role_changed_at set not null;

create or replace function private.pachanga_stamp_group_member_role_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' then
    new.role_changed_at := coalesce(new.role_changed_at, clock_timestamp());
  elsif new.role is distinct from old.role then
    new.role_changed_at := clock_timestamp();
  end if;
  return new;
end;
$$;

drop trigger if exists stamp_pachanga_group_member_role_v1 on public.pachanga_group_members;
create trigger stamp_pachanga_group_member_role_v1
before insert or update of role on public.pachanga_group_members
for each row execute function private.pachanga_stamp_group_member_role_v1();

create or replace function private.pachanga_sync_team_shield_admin_eligibility_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_group_id uuid;
  target_user_id uuid;
begin
  if tg_op = 'DELETE' then
    target_group_id := old.group_id;
    target_user_id := old.user_id;
  else
    target_group_id := new.group_id;
    target_user_id := new.user_id;
  end if;

  if tg_op <> 'DELETE' and new.role in ('owner','admin') then
    insert into public.pachanga_team_cosmetic_admin_eligibility(
      group_id, admin_user_id, role, eligible_since, seen_revision, updated_at
    ) values (
      target_group_id, target_user_id, new.role, new.role_changed_at, 0, clock_timestamp()
    ) on conflict (group_id, admin_user_id) do update set
      role = excluded.role,
      eligible_since = case
        when public.pachanga_team_cosmetic_admin_eligibility.role is distinct from excluded.role
          or public.pachanga_team_cosmetic_admin_eligibility.eligible_since is distinct from excluded.eligible_since
        then excluded.eligible_since
        else public.pachanga_team_cosmetic_admin_eligibility.eligible_since
      end,
      seen_revision = case
        when public.pachanga_team_cosmetic_admin_eligibility.role is distinct from excluded.role
          or public.pachanga_team_cosmetic_admin_eligibility.eligible_since is distinct from excluded.eligible_since
        then 0
        else public.pachanga_team_cosmetic_admin_eligibility.seen_revision
      end,
      updated_at = clock_timestamp();
  elsif exists (
    select 1 from public.pachanga_groups groups
    where groups.id = target_group_id and groups.owner_id = target_user_id
  ) then
    insert into public.pachanga_team_cosmetic_admin_eligibility(
      group_id, admin_user_id, role, eligible_since, seen_revision, updated_at
    ) values (target_group_id, target_user_id, 'owner', clock_timestamp(), 0, clock_timestamp())
    on conflict (group_id, admin_user_id) do update set role = 'owner', updated_at = clock_timestamp();
  else
    delete from public.pachanga_team_cosmetic_admin_eligibility eligibility
    where eligibility.group_id = target_group_id and eligibility.admin_user_id = target_user_id;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists sync_pachanga_team_shield_admin_eligibility_v1 on public.pachanga_group_members;
create trigger sync_pachanga_team_shield_admin_eligibility_v1
after insert or delete or update of role, role_changed_at on public.pachanga_group_members
for each row execute function private.pachanga_sync_team_shield_admin_eligibility_v1();

create or replace function private.pachanga_sync_team_shield_owner_eligibility_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  previous_role text;
  previous_since timestamptz;
begin
  if tg_op = 'UPDATE' and old.owner_id is distinct from new.owner_id then
    select memberships.role, memberships.role_changed_at into previous_role, previous_since
    from public.pachanga_group_members memberships
    where memberships.group_id = new.id and memberships.user_id = old.owner_id;
    if previous_role in ('owner','admin') then
      update public.pachanga_team_cosmetic_admin_eligibility eligibility
      set role = previous_role, eligible_since = previous_since,
          seen_revision = 0, updated_at = clock_timestamp()
      where eligibility.group_id = new.id and eligibility.admin_user_id = old.owner_id;
    else
      delete from public.pachanga_team_cosmetic_admin_eligibility eligibility
      where eligibility.group_id = new.id and eligibility.admin_user_id = old.owner_id;
    end if;
  end if;
  insert into public.pachanga_team_cosmetic_admin_eligibility(
    group_id, admin_user_id, role, eligible_since, seen_revision, updated_at
  ) values (new.id, new.owner_id, 'owner', clock_timestamp(), 0, clock_timestamp())
  on conflict (group_id, admin_user_id) do update set
    role = 'owner',
    eligible_since = case
      when public.pachanga_team_cosmetic_admin_eligibility.role <> 'owner'
        or (tg_op = 'UPDATE' and old.owner_id is distinct from new.owner_id)
      then excluded.eligible_since
      else public.pachanga_team_cosmetic_admin_eligibility.eligible_since
    end,
    seen_revision = case
      when public.pachanga_team_cosmetic_admin_eligibility.role <> 'owner'
        or (tg_op = 'UPDATE' and old.owner_id is distinct from new.owner_id)
      then 0
      else public.pachanga_team_cosmetic_admin_eligibility.seen_revision
    end,
    updated_at = clock_timestamp();
  return new;
end;
$$;

drop trigger if exists sync_pachanga_team_shield_owner_eligibility_v1 on public.pachanga_groups;
create trigger sync_pachanga_team_shield_owner_eligibility_v1
after insert or update of owner_id on public.pachanga_groups
for each row execute function private.pachanga_sync_team_shield_owner_eligibility_v1();

insert into public.pachanga_team_cosmetic_admin_eligibility(group_id, admin_user_id, role, eligible_since)
select memberships.group_id, memberships.user_id, memberships.role, memberships.role_changed_at
from public.pachanga_group_members memberships
where memberships.role in ('owner','admin')
on conflict (group_id, admin_user_id) do nothing;

insert into public.pachanga_team_cosmetic_admin_eligibility(group_id, admin_user_id, role, eligible_since)
select groups.id, groups.owner_id, 'owner', clock_timestamp()
from public.pachanga_groups groups
where groups.owner_id is not null
on conflict (group_id, admin_user_id) do update set role = 'owner', updated_at = clock_timestamp();

create or replace function private.pachanga_team_cosmetics_enabled_v1()
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(settings.team_cosmetics_enabled, false)
  from private.pachanga_team_cosmetic_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_team_cosmetic_rewards_enabled_v1()
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(settings.team_cosmetic_rewards_enabled, false)
  from private.pachanga_team_cosmetic_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_default_team_shield_config_v1(target_group_name text)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  default_initials text;
begin
  default_initials := left(upper(regexp_replace(coalesce(target_group_name, ''), '[^[:alnum:]]', '', 'g')), 3);
  if default_initials = '' then default_initials := 'PIQ'; end if;
  return jsonb_build_object(
    'schemaVersion', 1,
    'shapeKey', 'team.shield.shape.classic_iq',
    'backgroundKey', 'team.shield.background.duotone',
    'patternKey', 'team.shield.pattern.diagonal',
    'primaryColorKey', 'team.shield.color.midnight',
    'secondaryColorKey', 'team.shield.color.cyan',
    'primarySymbolKey', 'team.shield.symbol.ball_iq',
    'secondarySymbolKey', null,
    'borderKey', 'team.shield.border.clean',
    'topOrnamentKey', null,
    'sideOrnamentKey', null,
    'bottomOrnamentKey', null,
    'initials', default_initials,
    'foundationYear', '',
    'effectKey', null,
    'primarySymbolScale', 1,
    'primarySymbolRotation', 0
  );
end;
$$;

create or replace function private.pachanga_team_shield_client_metadata_v1(target_metadata jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when jsonb_typeof(target_metadata) <> 'object' then '{}'::jsonb
    else jsonb_strip_nulls(jsonb_build_object(
      'clientVersion', target_metadata -> 'clientVersion',
      'serviceWorkerVersion', target_metadata -> 'serviceWorkerVersion',
      'displayMode', target_metadata -> 'displayMode',
      'sessionId', target_metadata -> 'sessionId',
      'deviceId', target_metadata -> 'deviceId',
      'surface', target_metadata -> 'surface'
    ))
  end;
$$;

create or replace function private.pachanga_team_shield_replay_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_kind text,
  target_group_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  receipt public.pachanga_team_shield_operation_receipts%rowtype;
begin
  select * into receipt
  from public.pachanga_team_shield_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_user_id is distinct from target_actor_user_id
    or receipt.operation_kind <> target_operation_kind
    or receipt.group_id <> target_group_id
    or receipt.request_hash <> target_request_hash then
    raise exception 'Operation id belongs to another team shield action';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_assert_team_shield_piece_v1(
  target_group_id uuid,
  target_cosmetic_key text,
  target_family text,
  target_slot text default null,
  allow_null boolean default false,
  allow_primary_symbol_slot boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_cosmetic_catalog%rowtype;
begin
  if nullif(trim(target_cosmetic_key), '') is null then
    if allow_null then return; end if;
    raise exception 'A % team shield piece is required', target_family;
  end if;
  select * into selected
  from public.pachanga_cosmetic_catalog catalog
  where catalog.cosmetic_key = target_cosmetic_key
    and catalog.cosmetic_key like 'team.shield.%'
    and catalog.owner_scope = 'team'
    and catalog.active
    and catalog.lifecycle = 'active_reward';
  if not found or selected.family <> target_family then
    raise exception 'Invalid % team shield piece', target_family;
  end if;
  if target_slot is not null
    and selected.slot is distinct from target_slot
    and not (allow_primary_symbol_slot and selected.slot = 'primary_symbol') then
    raise exception 'Invalid % team shield slot', target_slot;
  end if;
  if selected.availability <> 'base' and not exists (
    select 1 from public.pachanga_team_cosmetic_inventory inventory
    where inventory.group_id = target_group_id
      and inventory.cosmetic_key = selected.cosmetic_key
      and inventory.state = 'unlocked'
  ) then
    raise exception 'COSMETIC_LOCKED: %', selected.cosmetic_key;
  end if;
end;
$$;

create or replace function private.pachanga_validate_team_shield_config_v1(
  target_group_id uuid,
  target_config jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  allowed_keys text[] := array[
    'schemaVersion','shapeKey','backgroundKey','patternKey','primaryColorKey',
    'secondaryColorKey','primarySymbolKey','secondarySymbolKey','borderKey',
    'topOrnamentKey','sideOrnamentKey','bottomOrnamentKey','initials',
    'foundationYear','effectKey','primarySymbolScale','primarySymbolRotation'
  ];
  normalized_initials text;
  normalized_year text;
  normalized_scale numeric;
  normalized_rotation numeric;
begin
  if jsonb_typeof(target_config) <> 'object' then raise exception 'Team shield config must be an object'; end if;
  if target_config - allowed_keys <> '{}'::jsonb then raise exception 'Team shield config contains unsupported fields'; end if;
  if coalesce((target_config ->> 'schemaVersion')::integer, 0) <> 1 then raise exception 'Unsupported team shield schema version'; end if;
  normalized_initials := upper(regexp_replace(coalesce(target_config ->> 'initials', ''), '\s+', '', 'g'));
  if char_length(normalized_initials) not between 1 and 4 or normalized_initials !~ '^[[:alnum:]]{1,4}$' then
    raise exception 'Initials must contain 1 to 4 letters or numbers';
  end if;
  normalized_year := regexp_replace(coalesce(target_config ->> 'foundationYear', ''), '[^0-9]', '', 'g');
  if normalized_year <> '' and normalized_year !~ '^[0-9]{4}$' then raise exception 'Foundation year must contain exactly four digits'; end if;
  begin
    normalized_scale := coalesce((target_config ->> 'primarySymbolScale')::numeric, 1);
    normalized_rotation := coalesce((target_config ->> 'primarySymbolRotation')::numeric, 0);
  exception when invalid_text_representation then
    raise exception 'Symbol scale and rotation must be numeric';
  end;
  if normalized_scale < 0.8 or normalized_scale > 1.2 then raise exception 'Symbol scale must be between 0.8 and 1.2'; end if;
  if normalized_rotation < -12 or normalized_rotation > 12 then raise exception 'Symbol rotation must be between -12 and 12'; end if;

  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'shapeKey', 'shape', 'shape', false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'backgroundKey', 'pattern', 'background', false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'patternKey',''), 'pattern', 'pattern', true, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'primaryColorKey', 'color', null, false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'secondaryColorKey', 'color', null, false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'primarySymbolKey', 'symbol', 'primary_symbol', false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'secondarySymbolKey',''), 'symbol', 'secondary_symbol', true, true);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, target_config ->> 'borderKey', 'border', 'border', false, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'topOrnamentKey',''), 'adornment', 'top_ornament', true, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'sideOrnamentKey',''), 'adornment', 'side_ornament', true, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'bottomOrnamentKey',''), 'adornment', 'bottom_ornament', true, false);
  perform private.pachanga_assert_team_shield_piece_v1(target_group_id, nullif(target_config ->> 'effectKey',''), 'effect', 'effect', true, false);

  return jsonb_build_object(
    'schemaVersion', 1,
    'shapeKey', target_config ->> 'shapeKey',
    'backgroundKey', target_config ->> 'backgroundKey',
    'patternKey', nullif(target_config ->> 'patternKey',''),
    'primaryColorKey', target_config ->> 'primaryColorKey',
    'secondaryColorKey', target_config ->> 'secondaryColorKey',
    'primarySymbolKey', target_config ->> 'primarySymbolKey',
    'secondarySymbolKey', nullif(target_config ->> 'secondarySymbolKey',''),
    'borderKey', target_config ->> 'borderKey',
    'topOrnamentKey', nullif(target_config ->> 'topOrnamentKey',''),
    'sideOrnamentKey', nullif(target_config ->> 'sideOrnamentKey',''),
    'bottomOrnamentKey', nullif(target_config ->> 'bottomOrnamentKey',''),
    'initials', normalized_initials,
    'foundationYear', normalized_year,
    'effectKey', nullif(target_config ->> 'effectKey',''),
    'primarySymbolScale', round(normalized_scale, 2),
    'primarySymbolRotation', round(normalized_rotation, 2)
  );
end;
$$;

create or replace function private.pachanga_team_shield_config_keys_v1(target_config jsonb)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select coalesce(array_agg(distinct keys.key order by keys.key), array[]::text[])
  from (
    select nullif(target_config ->> field_name, '') as key
    from unnest(array[
      'shapeKey','backgroundKey','patternKey','primaryColorKey','secondaryColorKey',
      'primarySymbolKey','secondarySymbolKey','borderKey','topOrnamentKey',
      'sideOrnamentKey','bottomOrnamentKey','effectKey'
    ]) field_name
  ) keys where keys.key is not null;
$$;

create or replace function private.pachanga_team_shield_equipped_v1(target_config jsonb)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', catalog.cosmetic_key,
    'family', catalog.family,
    'slot', catalog.slot,
    'name', catalog.display_name,
    'rarity', catalog.rarity,
    'collection', catalog.collection_key,
    'material', catalog.material_key,
    'render', catalog.render_contract,
    'layerOrder', catalog.layer_order
  ) order by catalog.layer_order, catalog.cosmetic_key), '[]'::jsonb)
  from public.pachanga_cosmetic_catalog catalog
  where catalog.owner_scope = 'team'
    and catalog.active
    and catalog.cosmetic_key = any(private.pachanga_team_shield_config_keys_v1(target_config));
$$;

create or replace function private.pachanga_team_shield_versions_are_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' and not exists (
    select 1 from public.pachanga_groups groups where groups.id = old.group_id
  ) then return old; end if;
  raise exception 'Team shield versions are immutable';
end;
$$;

drop trigger if exists enforce_team_shield_version_immutability_v1 on public.pachanga_team_shield_versions;
create trigger enforce_team_shield_version_immutability_v1
before update or delete on public.pachanga_team_shield_versions
for each row execute function private.pachanga_team_shield_versions_are_immutable_v1();

create or replace function public.get_pachanga_team_shield_snapshot_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_state public.pachanga_team_shield_state%rowtype;
  selected_loadout public.pachanga_team_shield_loadouts%rowtype;
  selected_eligibility public.pachanga_team_cosmetic_admin_eligibility%rowtype;
  selected_config jsonb;
  equipped_keys text[];
  can_manage boolean;
  unseen_count integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and (auth.uid() is null or not public.is_pachanga_group_member(target_group_id)) then
    raise exception 'Group membership required';
  end if;
  select * into selected_group from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  select * into selected_state from public.pachanga_team_shield_state states where states.group_id = target_group_id;
  select * into selected_loadout from public.pachanga_team_shield_loadouts loadouts where loadouts.group_id = target_group_id;
  selected_config := coalesce(selected_loadout.config, private.pachanga_default_team_shield_config_v1(selected_group.name));
  equipped_keys := private.pachanga_team_shield_config_keys_v1(selected_config);
  can_manage := coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or public.is_pachanga_group_admin(target_group_id);

  if can_manage and auth.uid() is not null then
    select * into selected_eligibility
    from public.pachanga_team_cosmetic_admin_eligibility eligibility
    where eligibility.group_id = target_group_id and eligibility.admin_user_id = auth.uid();
    select count(*) into unseen_count
    from public.pachanga_team_cosmetic_inventory inventory
    left join public.pachanga_team_cosmetic_seen seen
      on seen.group_id = inventory.group_id
      and seen.cosmetic_key = inventory.cosmetic_key
      and seen.admin_user_id = auth.uid()
    where inventory.group_id = target_group_id
      and inventory.cosmetic_key like 'team.shield.%'
      and inventory.state = 'unlocked'
      and inventory.unlocked_at >= coalesce(selected_eligibility.eligible_since, clock_timestamp())
      and seen.cosmetic_key is null;
  end if;

  return jsonb_build_object(
    'group', jsonb_build_object('groupId', selected_group.id, 'name', selected_group.name),
    'canManage', can_manage,
    'teamCosmeticsEnabled', private.pachanga_team_cosmetics_enabled_v1(),
    'teamCosmeticRewardsEnabled', private.pachanga_team_cosmetic_rewards_enabled_v1(),
    'revision', coalesce(selected_state.revision, 0),
    'confirmedRevision', coalesce(selected_state.revision, 0),
    'seenRevision', case when auth.uid() is null then 0 else coalesce(selected_eligibility.seen_revision, 0) end,
    'serverSequence', coalesce(selected_state.server_sequence, selected_loadout.server_sequence, 0),
    'unseenCount', unseen_count,
    'config', selected_config,
    'defaultConfig', private.pachanga_default_team_shield_config_v1(selected_group.name),
    'history', case when can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', versions.id,
        'version', versions.version_number,
        'config', versions.config,
        'serverSequence', versions.server_sequence,
        'createdAt', versions.created_at
      ) order by versions.version_number desc, versions.id desc)
      from (
        select version_rows.*
        from public.pachanga_team_shield_versions version_rows
        where version_rows.group_id = target_group_id
        order by version_rows.version_number desc, version_rows.id desc
        limit 30
      ) versions
    ), '[]'::jsonb) else '[]'::jsonb end,
    'catalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.cosmetic_key,
        'family', catalog.family,
        'slot', catalog.slot,
        'name', catalog.display_name,
        'description', catalog.description,
        'rarity', catalog.rarity,
        'availability', catalog.availability,
        'collection', catalog.collection_key,
        'material', catalog.material_key,
        'render', catalog.render_contract,
        'serverSequence', case when can_manage then coalesce(inventory.server_sequence, 0) else 0 end,
        'acquiredAt', case when can_manage then inventory.unlocked_at else null end,
        'seenAt', case
          when not can_manage then null
          when inventory.unlocked_at is null then null
          when auth.uid() is null then inventory.unlocked_at
          when inventory.unlocked_at < coalesce(selected_eligibility.eligible_since, clock_timestamp()) then inventory.unlocked_at
          else seen.seen_at
        end,
        'unlocked', catalog.availability = 'base' or inventory.state = 'unlocked'
      ) order by catalog.layer_order, catalog.slot, catalog.cosmetic_key)
      from public.pachanga_cosmetic_catalog catalog
      left join public.pachanga_team_cosmetic_inventory inventory
        on inventory.group_id = target_group_id
        and inventory.cosmetic_key = catalog.cosmetic_key
        and inventory.state = 'unlocked'
      left join public.pachanga_team_cosmetic_seen seen
        on seen.group_id = target_group_id
        and seen.cosmetic_key = catalog.cosmetic_key
        and seen.admin_user_id = auth.uid()
      where catalog.owner_scope = 'team'
        and catalog.cosmetic_key like 'team.shield.%'
        and catalog.active
        and catalog.lifecycle = 'active_reward'
        and (
          (can_manage and (catalog.availability = 'base' or inventory.state = 'unlocked'))
          or (not can_manage and (catalog.availability = 'base' or catalog.cosmetic_key = any(equipped_keys)))
        )
    ), '[]'::jsonb),
    'updatedAt', coalesce(selected_state.updated_at, selected_loadout.updated_at, selected_group.updated_at, clock_timestamp())
  );
end;
$$;

create or replace function public.get_pachanga_team_public_shield_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_public public.pachanga_team_shield_public%rowtype;
  selected_config jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into selected_group from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  select * into selected_public from public.pachanga_team_shield_public shields where shields.group_id = target_group_id;
  selected_config := coalesce(selected_public.config, private.pachanga_default_team_shield_config_v1(selected_group.name));
  return jsonb_build_object(
    'groupId', selected_group.id,
    'revision', coalesce(selected_public.revision, 0),
    'confirmedRevision', coalesce(selected_public.revision, 0),
    'serverSequence', coalesce(selected_public.server_sequence, 0),
    'config', selected_config,
    'equipped', coalesce(selected_public.equipped, private.pachanga_team_shield_equipped_v1(selected_config)),
    'updatedAt', coalesce(selected_public.updated_at, selected_group.updated_at)
  );
end;
$$;

create or replace function private.pachanga_upsert_team_shield_public_v1(
  target_group_id uuid,
  target_revision bigint,
  target_server_sequence bigint,
  target_config jsonb
)
returns void
language sql
security definer
set search_path = pg_catalog
as $$
  insert into public.pachanga_team_shield_public(
    group_id, revision, config, equipped, server_sequence, updated_at
  ) values (
    target_group_id, target_revision, target_config,
    private.pachanga_team_shield_equipped_v1(target_config),
    target_server_sequence, clock_timestamp()
  ) on conflict (group_id) do update set
    revision = excluded.revision,
    config = excluded.config,
    equipped = excluded.equipped,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at
  where public.pachanga_team_shield_public.revision <= excluded.revision;
$$;

drop function if exists public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb);

create function public.save_pachanga_team_shield_loadout_v1(
  target_group_id uuid,
  target_config jsonb,
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
  normalized jsonb;
  selected_state public.pachanga_team_shield_state%rowtype;
  selected_loadout public.pachanga_team_shield_loadouts%rowtype;
  previous_version_id uuid;
  next_version integer;
  next_sequence bigint;
  request_hash text;
  replay jsonb;
  response jsonb;
  member record;
begin
  if actor_id is null or target_group_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, team, operation id and expected revision required';
  end if;
  if not private.pachanga_team_cosmetics_enabled_v1() then raise exception 'Team cosmetics are not enabled'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then raise exception 'Only team administrators can edit the official shield'; end if;
  normalized := private.pachanga_validate_team_shield_config_v1(target_group_id, target_config);
  request_hash := md5(jsonb_build_object(
    'groupId', target_group_id, 'config', normalized, 'expectedRevision', expected_revision
  )::text);

  perform pg_advisory_xact_lock(hashtextextended('team-shield-operation:' || operation_id::text, 0));
  replay := private.pachanga_team_shield_replay_v1(operation_id, actor_id, 'save', target_group_id, request_hash);
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-shield-group:' || target_group_id::text, 0));

  insert into public.pachanga_team_shield_state(group_id) values (target_group_id)
  on conflict (group_id) do nothing;
  select * into selected_state
  from public.pachanga_team_shield_state states
  where states.group_id = target_group_id
  for update;
  if selected_state.revision <> expected_revision then
    raise exception 'Team shield revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  select * into selected_loadout
  from public.pachanga_team_shield_loadouts loadouts
  where loadouts.group_id = target_group_id;
  if found and selected_loadout.config = normalized then
    response := public.get_pachanga_team_shield_snapshot_v1(target_group_id) || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', expected_revision,
      'serverSequence', selected_state.server_sequence,
      'confirmedAt', clock_timestamp(),
      'noChange', true
    );
    insert into public.pachanga_team_shield_operation_receipts(
      operation_id, operation_kind, group_id, actor_user_id, request_hash,
      expected_revision, confirmed_revision, server_sequence, response, client_metadata
    ) values (
      operation_id, 'save', target_group_id, actor_id, request_hash,
      expected_revision, expected_revision, selected_state.server_sequence, response,
      private.pachanga_team_shield_client_metadata_v1(client_metadata)
    );
    return response;
  end if;

  select versions.id, versions.version_number
  into previous_version_id, next_version
  from public.pachanga_team_shield_versions versions
  where versions.group_id = target_group_id
  order by versions.version_number desc, versions.id desc
  limit 1;
  next_version := coalesce(next_version, 0) + 1;
  next_sequence := nextval('public.pachanga_team_crest_sequence');

  insert into public.pachanga_team_shield_versions(
    group_id, version_number, previous_version_id, config, operation_id,
    saved_by, server_sequence
  ) values (
    target_group_id, next_version, previous_version_id, normalized, operation_id,
    actor_id, next_sequence
  );
  insert into public.pachanga_team_shield_loadouts(
    group_id, revision, config, updated_by, server_sequence, updated_at
  ) values (
    target_group_id, selected_state.revision + 1, normalized, actor_id,
    next_sequence, clock_timestamp()
  ) on conflict (group_id) do update set
    revision = excluded.revision,
    config = excluded.config,
    updated_by = excluded.updated_by,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at;
  update public.pachanga_team_shield_state states
  set revision = states.revision + 1,
      server_sequence = next_sequence,
      updated_at = clock_timestamp()
  where states.group_id = target_group_id;
  perform private.pachanga_upsert_team_shield_public_v1(
    target_group_id, selected_state.revision + 1, next_sequence, normalized
  );
  insert into public.pachanga_team_shield_events(
    operation_id, event_type, group_id, actor_user_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id, 'team_shield_saved', target_group_id, actor_id,
    selected_state.revision + 1, next_sequence,
    jsonb_build_object('version', next_version, 'config', normalized)
  );

  for member in
    select distinct users.user_id
    from (
      select groups.owner_id as user_id from public.pachanga_groups groups where groups.id = target_group_id
      union all
      select memberships.user_id from public.pachanga_group_members memberships where memberships.group_id = target_group_id
    ) users
    where users.user_id is not null and users.user_id <> actor_id
  loop
    perform private.pachanga_notify_v1(
      member.user_id,
      'team_shield_updated',
      'Nueva identidad del equipo',
      'Un administrador ha actualizado el escudo oficial.',
      '/equipo/identidad?grupo=' || target_group_id::text,
      jsonb_build_object('groupId', target_group_id, 'version', next_version),
      'team-shield-v1:' || target_group_id::text || ':' || next_version::text || ':' || member.user_id::text
    );
  end loop;

  response := public.get_pachanga_team_shield_snapshot_v1(target_group_id) || jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', selected_state.revision + 1,
    'serverSequence', next_sequence,
    'confirmedAt', clock_timestamp(),
    'noChange', false
  );
  insert into public.pachanga_team_shield_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, request_hash,
    expected_revision, confirmed_revision, server_sequence, response, client_metadata
  ) values (
    operation_id, 'save', target_group_id, actor_id, request_hash,
    expected_revision, selected_state.revision + 1, next_sequence, response,
    private.pachanga_team_shield_client_metadata_v1(client_metadata)
  );
  return response;
end;
$$;

create or replace function public.mark_pachanga_team_cosmetics_seen_v1(
  target_group_id uuid,
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
  eligibility public.pachanga_team_cosmetic_admin_eligibility%rowtype;
  normalized_keys text[];
  next_sequence bigint;
  changed_count integer := 0;
  request_hash text;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or target_group_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, team, operation id and expected revision required';
  end if;
  if not private.pachanga_team_cosmetics_enabled_v1() then raise exception 'Team cosmetics are not enabled'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then raise exception 'Only team administrators can update cosmetic visibility'; end if;
  select coalesce(array_agg(distinct keys.key order by keys.key), '{}'::text[])
  into normalized_keys
  from unnest(coalesce(target_cosmetic_keys, '{}'::text[])) keys(key)
  where nullif(trim(keys.key), '') is not null;
  if coalesce(array_length(normalized_keys, 1), 0) = 0 or array_length(normalized_keys, 1) > 50 then
    raise exception 'Between one and fifty cosmetic keys required';
  end if;
  request_hash := md5(jsonb_build_object(
    'groupId', target_group_id, 'keys', to_jsonb(normalized_keys), 'expectedRevision', expected_revision
  )::text);
  perform pg_advisory_xact_lock(hashtextextended('team-shield-operation:' || operation_id::text, 0));
  replay := private.pachanga_team_shield_replay_v1(operation_id, actor_id, 'mark_seen', target_group_id, request_hash);
  if replay is not null then return replay; end if;

  select * into eligibility
  from public.pachanga_team_cosmetic_admin_eligibility rows
  where rows.group_id = target_group_id and rows.admin_user_id = actor_id
  for update;
  if not found then raise exception 'Team cosmetic admin eligibility required'; end if;
  if eligibility.seen_revision <> expected_revision then
    raise exception 'Team cosmetic seen revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if exists (
    select 1 from unnest(normalized_keys) requested(key)
    where not exists (
      select 1 from public.pachanga_team_cosmetic_inventory inventory
      where inventory.group_id = target_group_id
        and inventory.cosmetic_key = requested.key
        and inventory.cosmetic_key like 'team.shield.%'
        and inventory.state = 'unlocked'
    )
  ) then raise exception 'Cannot mark an unowned team cosmetic as seen'; end if;

  next_sequence := nextval('public.pachanga_team_crest_sequence');
  with inserted as (
    insert into public.pachanga_team_cosmetic_seen(group_id, cosmetic_key, admin_user_id, server_sequence)
    select target_group_id, requested.key, actor_id, next_sequence
    from unnest(normalized_keys) requested(key)
    on conflict (group_id, cosmetic_key, admin_user_id) do nothing
    returning 1
  ) select count(*) into changed_count from inserted;
  if changed_count > 0 then
    update public.pachanga_team_cosmetic_admin_eligibility rows
    set seen_revision = rows.seen_revision + 1, updated_at = clock_timestamp()
    where rows.group_id = target_group_id and rows.admin_user_id = actor_id;
  end if;
  insert into public.pachanga_team_shield_events(
    operation_id, event_type, group_id, actor_user_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id, 'team_cosmetic_seen', target_group_id, actor_id,
    expected_revision + case when changed_count > 0 then 1 else 0 end,
    next_sequence,
    jsonb_build_object('cosmeticKeys', to_jsonb(normalized_keys), 'markedSeen', changed_count)
  );
  response := public.get_pachanga_team_shield_snapshot_v1(target_group_id) || jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', expected_revision + case when changed_count > 0 then 1 else 0 end,
    'serverSequence', next_sequence,
    'confirmedAt', clock_timestamp(),
    'markedSeen', changed_count
  );
  insert into public.pachanga_team_shield_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, request_hash,
    expected_revision, confirmed_revision, server_sequence, response, client_metadata
  ) values (
    operation_id, 'mark_seen', target_group_id, actor_id, request_hash,
    expected_revision, expected_revision + case when changed_count > 0 then 1 else 0 end,
    next_sequence, response, private.pachanga_team_shield_client_metadata_v1(client_metadata)
  );
  return response;
end;
$$;

create or replace function public.grant_pachanga_team_cosmetic_v1(
  target_group_id uuid,
  target_cosmetic_key text,
  operation_id uuid,
  expected_revision bigint,
  source_kind text default 'admin',
  source_metadata jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_state public.pachanga_team_shield_state%rowtype;
  selected_loadout public.pachanga_team_shield_loadouts%rowtype;
  selected_inventory public.pachanga_team_cosmetic_inventory%rowtype;
  selected_config jsonb;
  normalized_source_kind text := lower(coalesce(nullif(trim(source_kind), ''), 'admin'));
  next_sequence bigint;
  changed boolean;
  request_hash text;
  replay jsonb;
  response jsonb;
  recipient record;
begin
  if target_group_id is null or nullif(trim(target_cosmetic_key), '') is null
    or operation_id is null or expected_revision is null then
    raise exception 'Team, cosmetic, operation id and expected revision required';
  end if;
  if not private.pachanga_team_cosmetics_enabled_v1() then raise exception 'Team cosmetics are not enabled'; end if;
  if normalized_source_kind not in ('admin','staging_fixture','future_top','future_tournament') then
    raise exception 'Unsupported controlled team cosmetic grant source';
  end if;
  if not exists (
    select 1 from public.pachanga_cosmetic_catalog catalog
    where catalog.cosmetic_key = target_cosmetic_key
      and catalog.cosmetic_key like 'team.shield.%'
      and catalog.owner_scope = 'team'
      and catalog.availability <> 'base'
      and catalog.active
      and catalog.lifecycle = 'active_reward'
  ) then raise exception 'Team cosmetic is unavailable for controlled grants'; end if;
  select * into selected_group from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  request_hash := md5(jsonb_build_object(
    'groupId', target_group_id,
    'cosmeticKey', target_cosmetic_key,
    'expectedRevision', expected_revision,
    'sourceKind', normalized_source_kind,
    'sourceMetadata', case when jsonb_typeof(source_metadata) = 'object' then source_metadata else '{}'::jsonb end
  )::text);

  perform pg_advisory_xact_lock(hashtextextended('team-shield-operation:' || operation_id::text, 0));
  replay := private.pachanga_team_shield_replay_v1(operation_id, auth.uid(), 'grant', target_group_id, request_hash);
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-shield-group:' || target_group_id::text, 0));
  insert into public.pachanga_team_shield_state(group_id) values (target_group_id)
  on conflict (group_id) do nothing;
  select * into selected_state
  from public.pachanga_team_shield_state states
  where states.group_id = target_group_id
  for update;
  if selected_state.revision <> expected_revision then
    raise exception 'Team shield revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  select * into selected_inventory
  from public.pachanga_team_cosmetic_inventory inventory
  where inventory.group_id = target_group_id and inventory.cosmetic_key = target_cosmetic_key
  for update;
  changed := not found or selected_inventory.state <> 'unlocked';
  next_sequence := nextval('public.pachanga_team_crest_sequence');

  if changed then
    insert into public.pachanga_team_cosmetic_inventory(
      group_id, cosmetic_key, source_grant_id, state, unlocked_at, revoked_at,
      revision, operation_id, source_kind, server_sequence, metadata
    ) values (
      target_group_id, target_cosmetic_key, null, 'unlocked', clock_timestamp(), null,
      1, operation_id, normalized_source_kind, next_sequence,
      case when jsonb_typeof(source_metadata) = 'object' then source_metadata else '{}'::jsonb end
    ) on conflict (group_id, cosmetic_key) do update set
      source_grant_id = null,
      state = 'unlocked',
      unlocked_at = clock_timestamp(),
      revoked_at = null,
      revision = public.pachanga_team_cosmetic_inventory.revision + 1,
      operation_id = excluded.operation_id,
      source_kind = excluded.source_kind,
      server_sequence = excluded.server_sequence,
      metadata = excluded.metadata;
    update public.pachanga_team_shield_state states
    set revision = states.revision + 1,
        server_sequence = next_sequence,
        updated_at = clock_timestamp()
    where states.group_id = target_group_id;
    select * into selected_loadout
    from public.pachanga_team_shield_loadouts loadouts
    where loadouts.group_id = target_group_id;
    selected_config := coalesce(selected_loadout.config, private.pachanga_default_team_shield_config_v1(selected_group.name));
    perform private.pachanga_upsert_team_shield_public_v1(
      target_group_id, selected_state.revision + 1, next_sequence, selected_config
    );

    for recipient in
      select distinct admins.user_id
      from (
        select groups.owner_id as user_id from public.pachanga_groups groups where groups.id = target_group_id
        union all
        select memberships.user_id from public.pachanga_group_members memberships
        where memberships.group_id = target_group_id and memberships.role in ('owner','admin')
      ) admins where admins.user_id is not null
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id,
        'team_cosmetic_reward',
        'Nuevo cosmético de equipo',
        'El equipo ha desbloqueado una nueva pieza para su escudo.',
        '/equipo/identidad?grupo=' || target_group_id::text,
        jsonb_build_object('groupId', target_group_id, 'cosmeticKey', target_cosmetic_key),
        'team-cosmetic:' || target_group_id::text || ':' || target_cosmetic_key || ':' || recipient.user_id::text
      );
    end loop;
  end if;

  insert into public.pachanga_team_shield_events(
    operation_id, event_type, group_id, cosmetic_key, actor_user_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id,
    case when changed then 'team_cosmetic_granted' else 'team_cosmetic_already_owned' end,
    target_group_id, target_cosmetic_key, auth.uid(),
    selected_state.revision + case when changed then 1 else 0 end,
    next_sequence,
    jsonb_build_object('sourceKind', normalized_source_kind, 'duplicate', not changed)
  );
  response := public.get_pachanga_team_shield_snapshot_v1(target_group_id) || jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', selected_state.revision + case when changed then 1 else 0 end,
    'serverSequence', next_sequence,
    'confirmedAt', clock_timestamp(),
    'grantedCosmeticKey', target_cosmetic_key,
    'alreadyOwned', not changed,
    'currencyGranted', 0
  );
  insert into public.pachanga_team_shield_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, request_hash,
    expected_revision, confirmed_revision, server_sequence, response, client_metadata
  ) values (
    operation_id, 'grant', target_group_id, auth.uid(), request_hash,
    expected_revision, selected_state.revision + case when changed then 1 else 0 end,
    next_sequence, response, private.pachanga_team_shield_client_metadata_v1(client_metadata)
  );
  return response;
end;
$$;

-- The legacy visual write path is intentionally no longer client reachable.
revoke execute on function public.save_pachanga_team_crest_draft_v1(uuid, jsonb, uuid, bigint, jsonb) from authenticated;
revoke execute on function public.publish_pachanga_team_crest_v1(uuid, uuid, bigint, jsonb) from authenticated;

revoke all on function private.pachanga_stamp_group_member_role_v1() from public, anon, authenticated;
revoke all on function private.pachanga_sync_team_shield_admin_eligibility_v1() from public, anon, authenticated;
revoke all on function private.pachanga_sync_team_shield_owner_eligibility_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_cosmetics_enabled_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_cosmetic_rewards_enabled_v1() from public, anon, authenticated;
revoke all on function private.pachanga_default_team_shield_config_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_team_shield_client_metadata_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_shield_replay_v1(uuid, uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_assert_team_shield_piece_v1(uuid, text, text, text, boolean, boolean) from public, anon, authenticated;
revoke all on function private.pachanga_validate_team_shield_config_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_shield_config_keys_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_shield_equipped_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_shield_versions_are_immutable_v1() from public, anon, authenticated;
revoke all on function private.pachanga_upsert_team_shield_public_v1(uuid, bigint, bigint, jsonb) from public, anon, authenticated;

revoke all on function public.get_pachanga_team_shield_snapshot_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_pachanga_team_shield_snapshot_v1(uuid) to authenticated;
revoke all on function public.get_pachanga_team_public_shield_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_pachanga_team_public_shield_v1(uuid) to authenticated;
revoke all on function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb) to authenticated;
revoke all on function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb) to authenticated;
revoke all on function public.grant_pachanga_team_cosmetic_v1(uuid, text, uuid, bigint, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.grant_pachanga_team_cosmetic_v1(uuid, text, uuid, bigint, text, jsonb, jsonb) to service_role;

alter function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.grant_pachanga_team_cosmetic_v1(uuid, text, uuid, bigint, text, jsonb, jsonb) set lock_timeout = '750ms';

alter table public.pachanga_team_cosmetic_inventory replica identity full;
alter table public.pachanga_team_shield_state replica identity full;
alter table public.pachanga_team_shield_public replica identity full;
alter table public.pachanga_team_cosmetic_seen replica identity full;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_team_cosmetic_inventory',
    'pachanga_team_shield_state',
    'pachanga_team_shield_public',
    'pachanga_team_cosmetic_seen'
  ] loop
    if not exists (
      select 1 from pg_publication_tables publication_tables
      where publication_tables.pubname = 'supabase_realtime'
        and publication_tables.schemaname = 'public'
        and publication_tables.tablename = target_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target_table);
    end if;
  end loop;
end;
$$;

comment on table public.pachanga_team_shield_loadouts is
  'Authoritative TeamShieldConfig V1. It is independent from the legacy crest editor and never changes sporting data.';
comment on table public.pachanga_team_shield_public is
  'Safe canonical team shield read model containing only the equipped visual configuration.';
comment on function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb) is
  'Idempotent server-authoritative team shield save with ownership and stale-revision validation.';
comment on function public.grant_pachanga_team_cosmetic_v1(uuid, text, uuid, bigint, text, jsonb, jsonb) is
  'Service-only controlled team cosmetic grant. Duplicates never create currency or extra ownership.';
