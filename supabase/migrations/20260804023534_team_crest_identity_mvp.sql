-- Pachangas IQ team crest identity MVP.
-- Drafts and immutable published versions use only server-validated catalog pieces.

create sequence if not exists public.pachanga_team_crest_sequence;
revoke all on sequence public.pachanga_team_crest_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_team_crest_sequence to service_role;

create table if not exists public.pachanga_team_crest_drafts (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  draft_revision bigint not null default 1,
  based_on_version integer,
  shape_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  primary_color_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  secondary_color_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  pattern_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  border_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  symbol_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  adornment_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  palette_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  effect_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  initials text not null,
  updated_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (draft_revision >= 1),
  check (based_on_version is null or based_on_version >= 1),
  check (char_length(initials) between 1 and 4),
  check (initials = upper(initials))
);

create table if not exists public.pachanga_team_crest_versions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  version_number integer not null,
  previous_version_id uuid references public.pachanga_team_crest_versions(id) on delete restrict,
  source_draft_revision bigint not null,
  shape_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  primary_color_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  secondary_color_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  pattern_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  border_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  symbol_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  adornment_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  palette_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  effect_key text references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  initials text not null,
  operation_id uuid not null unique,
  published_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz not null default clock_timestamp(),
  unique (group_id, version_number),
  check (version_number >= 1),
  check (source_draft_revision >= 1),
  check (char_length(initials) between 1 and 4),
  check (initials = upper(initials))
);

create index if not exists pachanga_team_crest_versions_group_idx
  on public.pachanga_team_crest_versions(group_id, version_number desc, id desc);

create table if not exists public.pachanga_team_crest_state (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_team_crest_sequence'),
  draft_revision bigint not null default 0,
  published_version_id uuid references public.pachanga_team_crest_versions(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 0),
  check (draft_revision >= 0)
);

create table if not exists public.pachanga_team_crest_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  event_type text not null,
  crest_version_id uuid references public.pachanga_team_crest_versions(id) on delete restrict,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (event_type in ('crest_draft_saved', 'crest_published')),
  check (confirmed_revision >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists pachanga_team_crest_events_sequence_idx
  on public.pachanga_team_crest_events(server_sequence);
create index if not exists pachanga_team_crest_events_group_idx
  on public.pachanga_team_crest_events(group_id, server_sequence desc, id desc);

create table if not exists public.pachanga_team_crest_operation_receipts (
  operation_id uuid primary key,
  operation_kind text not null,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  expected_revision bigint not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (operation_kind in ('save_draft', 'publish')),
  check (expected_revision >= 0 and confirmed_revision >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

alter table public.pachanga_team_crest_drafts enable row level security;
alter table public.pachanga_team_crest_versions enable row level security;
alter table public.pachanga_team_crest_state enable row level security;
alter table public.pachanga_team_crest_events enable row level security;
alter table public.pachanga_team_crest_operation_receipts enable row level security;

revoke all on table public.pachanga_team_crest_drafts from public, anon, authenticated;
revoke all on table public.pachanga_team_crest_versions from public, anon, authenticated;
revoke all on table public.pachanga_team_crest_state from public, anon, authenticated;
revoke all on table public.pachanga_team_crest_events from public, anon, authenticated;
revoke all on table public.pachanga_team_crest_operation_receipts from public, anon, authenticated;

grant select on table public.pachanga_team_crest_drafts to authenticated;
grant select on table public.pachanga_team_crest_versions to authenticated;
grant select on table public.pachanga_team_crest_state to authenticated;
grant select on table public.pachanga_team_crest_events to authenticated;
grant select on table public.pachanga_team_crest_operation_receipts to authenticated;

grant all on table public.pachanga_team_crest_drafts to service_role;
grant all on table public.pachanga_team_crest_versions to service_role;
grant all on table public.pachanga_team_crest_state to service_role;
grant all on table public.pachanga_team_crest_events to service_role;
grant all on table public.pachanga_team_crest_operation_receipts to service_role;

drop policy if exists "Admins can read team crest drafts" on public.pachanga_team_crest_drafts;
create policy "Admins can read team crest drafts"
on public.pachanga_team_crest_drafts for select to authenticated
using (public.is_pachanga_group_admin(group_id));

drop policy if exists "Members can read published team crest versions" on public.pachanga_team_crest_versions;
create policy "Members can read published team crest versions"
on public.pachanga_team_crest_versions for select to authenticated
using (public.is_pachanga_group_member(group_id));

drop policy if exists "Members can read team crest state" on public.pachanga_team_crest_state;
create policy "Members can read team crest state"
on public.pachanga_team_crest_state for select to authenticated
using (public.is_pachanga_group_member(group_id));

drop policy if exists "Members can read team crest events" on public.pachanga_team_crest_events;
create policy "Members can read team crest events"
on public.pachanga_team_crest_events for select to authenticated
using (public.is_pachanga_group_member(group_id));

drop policy if exists "Actors can read own team crest receipts" on public.pachanga_team_crest_operation_receipts;
create policy "Actors can read own team crest receipts"
on public.pachanga_team_crest_operation_receipts for select to authenticated
using (actor_user_id = (select auth.uid()));

create or replace function private.pachanga_team_crest_design_v1(
  target_shape_key text,
  target_primary_color_key text,
  target_secondary_color_key text,
  target_pattern_key text,
  target_border_key text,
  target_symbol_key text,
  target_adornment_key text,
  target_palette_key text,
  target_effect_key text,
  target_initials text
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'shapeKey', target_shape_key,
    'primaryColorKey', target_primary_color_key,
    'secondaryColorKey', target_secondary_color_key,
    'patternKey', target_pattern_key,
    'borderKey', target_border_key,
    'symbolKey', target_symbol_key,
    'adornmentKey', target_adornment_key,
    'paletteKey', target_palette_key,
    'effectKey', target_effect_key,
    'initials', target_initials
  ));
$$;

create or replace function private.pachanga_assert_team_crest_piece_v1(
  target_group_id uuid,
  target_cosmetic_key text,
  target_family text,
  allow_null boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_cosmetic_catalog%rowtype;
begin
  if target_cosmetic_key is null or trim(target_cosmetic_key) = '' then
    if allow_null then return; end if;
    raise exception 'A % cosmetic is required', target_family;
  end if;

  select * into selected
  from public.pachanga_cosmetic_catalog catalog
  where catalog.cosmetic_key = target_cosmetic_key
    and catalog.active;
  if not found or selected.family <> target_family then
    raise exception 'Invalid % cosmetic', target_family;
  end if;
  if selected.availability = 'achievement' and not exists (
    select 1
    from public.pachanga_team_cosmetic_inventory inventory
    where inventory.group_id = target_group_id
      and inventory.cosmetic_key = selected.cosmetic_key
      and inventory.state = 'unlocked'
  ) then
    raise exception 'COSMETIC_LOCKED: %', selected.cosmetic_key using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.pachanga_validate_team_crest_design_v1(
  target_group_id uuid,
  target_design jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  normalized jsonb;
  normalized_initials text;
  allowed_keys text[] := array[
    'shapeKey', 'primaryColorKey', 'secondaryColorKey', 'patternKey',
    'borderKey', 'symbolKey', 'adornmentKey', 'paletteKey', 'effectKey', 'initials'
  ];
begin
  if jsonb_typeof(target_design) <> 'object' then
    raise exception 'Crest design must be an object';
  end if;
  if target_design - allowed_keys <> '{}'::jsonb then
    raise exception 'Crest design contains unsupported fields';
  end if;
  normalized_initials := upper(regexp_replace(coalesce(target_design ->> 'initials', ''), '\s+', '', 'g'));
  if char_length(normalized_initials) not between 1 and 4
    or normalized_initials !~ '^[[:alnum:]]{1,4}$' then
    raise exception 'Initials must contain 1 to 4 letters or numbers';
  end if;

  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, target_design ->> 'shapeKey', 'shape');
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, target_design ->> 'primaryColorKey', 'color');
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, target_design ->> 'secondaryColorKey', 'color');
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, target_design ->> 'patternKey', 'pattern');
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, target_design ->> 'borderKey', 'border');
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, nullif(target_design ->> 'symbolKey', ''), 'symbol', true);
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, nullif(target_design ->> 'adornmentKey', ''), 'adornment', true);
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, nullif(target_design ->> 'paletteKey', ''), 'palette', true);
  perform private.pachanga_assert_team_crest_piece_v1(target_group_id, nullif(target_design ->> 'effectKey', ''), 'effect', true);

  normalized := private.pachanga_team_crest_design_v1(
    target_design ->> 'shapeKey', target_design ->> 'primaryColorKey',
    target_design ->> 'secondaryColorKey', target_design ->> 'patternKey',
    target_design ->> 'borderKey', nullif(target_design ->> 'symbolKey', ''),
    nullif(target_design ->> 'adornmentKey', ''), nullif(target_design ->> 'paletteKey', ''),
    nullif(target_design ->> 'effectKey', ''), normalized_initials
  );
  return normalized;
end;
$$;

create or replace function private.pachanga_team_crest_version_snapshot_v1(target_version_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', versions.id,
    'version', versions.version_number,
    'previousVersionId', versions.previous_version_id,
    'sourceDraftRevision', versions.source_draft_revision,
    'design', private.pachanga_team_crest_design_v1(
      versions.shape_key, versions.primary_color_key, versions.secondary_color_key,
      versions.pattern_key, versions.border_key, versions.symbol_key,
      versions.adornment_key, versions.palette_key, versions.effect_key,
      versions.initials
    ),
    'publishedAt', versions.published_at
  )
  from public.pachanga_team_crest_versions versions
  where versions.id = target_version_id;
$$;

create or replace function private.pachanga_team_crest_draft_snapshot_v1(target_group_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'draftRevision', drafts.draft_revision,
    'basedOnVersion', drafts.based_on_version,
    'design', private.pachanga_team_crest_design_v1(
      drafts.shape_key, drafts.primary_color_key, drafts.secondary_color_key,
      drafts.pattern_key, drafts.border_key, drafts.symbol_key,
      drafts.adornment_key, drafts.palette_key, drafts.effect_key,
      drafts.initials
    ),
    'updatedAt', drafts.updated_at
  )
  from public.pachanga_team_crest_drafts drafts
  where drafts.group_id = target_group_id;
$$;

create or replace function private.pachanga_team_crest_replay_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_kind text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  receipt public.pachanga_team_crest_operation_receipts%rowtype;
begin
  select * into receipt
  from public.pachanga_team_crest_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_user_id <> target_actor_user_id
    or receipt.operation_kind <> target_operation_kind then
    raise exception 'Operation id belongs to another action';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_team_crest_versions_are_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' and not exists (
    select 1 from public.pachanga_groups groups where groups.id = old.group_id
  ) then
    return old;
  end if;
  raise exception 'Published crest versions are immutable';
end;
$$;

drop trigger if exists enforce_team_crest_version_immutability
  on public.pachanga_team_crest_versions;
create trigger enforce_team_crest_version_immutability
before update or delete on public.pachanga_team_crest_versions
for each row execute function private.pachanga_team_crest_versions_are_immutable_v1();

create or replace function public.get_pachanga_team_crest_snapshot_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_state public.pachanga_team_crest_state%rowtype;
  can_manage boolean;
  default_initials text;
begin
  if auth.uid() is null or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Group membership required';
  end if;
  select * into selected_group
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  select * into selected_state
  from public.pachanga_team_crest_state states
  where states.group_id = target_group_id;
  can_manage := public.is_pachanga_group_admin(target_group_id);
  default_initials := left(upper(regexp_replace(selected_group.name, '[^[:alnum:]]', '', 'g')), 3);
  if default_initials = '' then default_initials := 'PIQ'; end if;

  return jsonb_build_object(
    'group', jsonb_build_object('groupId', selected_group.id, 'name', selected_group.name),
    'canManage', can_manage,
    'crestRevision', coalesce(selected_state.revision, 0),
    'confirmedRevision', coalesce(selected_state.revision, 0),
    'serverSequence', coalesce(selected_state.server_sequence, 0),
    'defaultDesign', private.pachanga_team_crest_design_v1(
      'shape.classic', 'color.green', 'color.white', 'pattern.solid',
      'border.standard', null, null, null, null, default_initials
    ),
    'draft', case when can_manage then private.pachanga_team_crest_draft_snapshot_v1(target_group_id) else null end,
    'published', private.pachanga_team_crest_version_snapshot_v1(selected_state.published_version_id),
    'history', coalesce((
      select jsonb_agg(private.pachanga_team_crest_version_snapshot_v1(versions.id)
        order by versions.version_number desc, versions.id desc)
      from (
        select version_rows.id, version_rows.version_number
        from public.pachanga_team_crest_versions version_rows
        where version_rows.group_id = target_group_id
        order by version_rows.version_number desc, version_rows.id desc
        limit 30
      ) versions
    ), '[]'::jsonb),
    'catalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.cosmetic_key,
        'family', catalog.family,
        'name', catalog.display_name,
        'description', catalog.description,
        'rarity', catalog.rarity,
        'availability', catalog.availability,
        'render', catalog.render_contract,
        'unlocked', catalog.availability = 'base' or inventory.state = 'unlocked'
      ) order by catalog.layer_order, catalog.family, catalog.cosmetic_key)
      from public.pachanga_cosmetic_catalog catalog
      left join public.pachanga_team_cosmetic_inventory inventory
        on inventory.group_id = target_group_id
        and inventory.cosmetic_key = catalog.cosmetic_key
      where catalog.active
    ), '[]'::jsonb),
    'updatedAt', coalesce(selected_state.updated_at, selected_group.updated_at, clock_timestamp())
  );
end;
$$;

create or replace function public.save_pachanga_team_crest_draft_v1(
  target_group_id uuid,
  target_design jsonb,
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
  normalized jsonb;
  selected_state public.pachanga_team_crest_state%rowtype;
  selected_draft public.pachanga_team_crest_drafts%rowtype;
  replay jsonb;
  next_sequence bigint;
  response jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only team administrators can edit the official crest';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-crest-operation:' || operation_id::text, 0));
  replay := private.pachanga_team_crest_replay_v1(operation_id, auth.uid(), 'save_draft');
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-crest-group:' || target_group_id::text, 0));

  insert into public.pachanga_team_crest_state(group_id)
  values (target_group_id)
  on conflict (group_id) do nothing;
  select * into selected_state
  from public.pachanga_team_crest_state states
  where states.group_id = target_group_id
  for update;
  if selected_state.revision <> expected_revision then
    raise exception 'Crest revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  normalized := private.pachanga_validate_team_crest_design_v1(target_group_id, target_design);

  insert into public.pachanga_team_crest_drafts(
    group_id, draft_revision, based_on_version, shape_key, primary_color_key,
    secondary_color_key, pattern_key, border_key, symbol_key, adornment_key,
    palette_key, effect_key, initials, updated_by
  ) values (
    target_group_id, 1, null,
    normalized ->> 'shapeKey', normalized ->> 'primaryColorKey',
    normalized ->> 'secondaryColorKey', normalized ->> 'patternKey',
    normalized ->> 'borderKey', normalized ->> 'symbolKey',
    normalized ->> 'adornmentKey', normalized ->> 'paletteKey',
    normalized ->> 'effectKey', normalized ->> 'initials', auth.uid()
  ) on conflict (group_id) do update set
    draft_revision = public.pachanga_team_crest_drafts.draft_revision + 1,
    shape_key = excluded.shape_key,
    primary_color_key = excluded.primary_color_key,
    secondary_color_key = excluded.secondary_color_key,
    pattern_key = excluded.pattern_key,
    border_key = excluded.border_key,
    symbol_key = excluded.symbol_key,
    adornment_key = excluded.adornment_key,
    palette_key = excluded.palette_key,
    effect_key = excluded.effect_key,
    initials = excluded.initials,
    updated_by = excluded.updated_by,
    updated_at = clock_timestamp()
  returning * into selected_draft;

  next_sequence := nextval('public.pachanga_team_crest_sequence');
  update public.pachanga_team_crest_state states
  set revision = states.revision + 1,
      draft_revision = selected_draft.draft_revision,
      server_sequence = next_sequence,
      updated_at = clock_timestamp()
  where states.group_id = target_group_id;
  insert into public.pachanga_team_crest_events(
    operation_id, group_id, event_type, confirmed_revision, server_sequence, payload
  ) values (
    operation_id, target_group_id, 'crest_draft_saved',
    selected_state.revision + 1, next_sequence,
    jsonb_build_object('draftRevision', selected_draft.draft_revision)
  );
  response := public.get_pachanga_team_crest_snapshot_v1(target_group_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', selected_state.revision + 1,
      'serverSequence', next_sequence,
      'confirmedAt', clock_timestamp()
    );
  insert into public.pachanga_team_crest_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, expected_revision,
    confirmed_revision, server_sequence, response, client_metadata
  ) values (
    operation_id, 'save_draft', target_group_id, auth.uid(), expected_revision,
    selected_state.revision + 1, next_sequence, response,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end
  );
  return response;
end;
$$;

create or replace function public.publish_pachanga_team_crest_v1(
  target_group_id uuid,
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
  selected_state public.pachanga_team_crest_state%rowtype;
  selected_draft public.pachanga_team_crest_drafts%rowtype;
  saved_version public.pachanga_team_crest_versions%rowtype;
  replay jsonb;
  next_sequence bigint;
  next_version integer;
  response jsonb;
  member record;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only team administrators can publish the official crest';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-crest-operation:' || operation_id::text, 0));
  replay := private.pachanga_team_crest_replay_v1(operation_id, auth.uid(), 'publish');
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-crest-group:' || target_group_id::text, 0));

  insert into public.pachanga_team_crest_state(group_id)
  values (target_group_id)
  on conflict (group_id) do nothing;
  select * into selected_state
  from public.pachanga_team_crest_state states
  where states.group_id = target_group_id
  for update;
  if selected_state.revision <> expected_revision then
    raise exception 'Crest revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  select * into selected_draft
  from public.pachanga_team_crest_drafts drafts
  where drafts.group_id = target_group_id
  for update;
  if not found then raise exception 'Save a crest draft before publishing'; end if;

  perform private.pachanga_validate_team_crest_design_v1(
    target_group_id,
    private.pachanga_team_crest_design_v1(
      selected_draft.shape_key, selected_draft.primary_color_key,
      selected_draft.secondary_color_key, selected_draft.pattern_key,
      selected_draft.border_key, selected_draft.symbol_key,
      selected_draft.adornment_key, selected_draft.palette_key,
      selected_draft.effect_key, selected_draft.initials
    )
  );
  select coalesce(max(versions.version_number), 0) + 1 into next_version
  from public.pachanga_team_crest_versions versions
  where versions.group_id = target_group_id;

  insert into public.pachanga_team_crest_versions(
    group_id, version_number, previous_version_id, source_draft_revision,
    shape_key, primary_color_key, secondary_color_key, pattern_key, border_key,
    symbol_key, adornment_key, palette_key, effect_key, initials,
    operation_id, published_by
  ) values (
    target_group_id, next_version, selected_state.published_version_id,
    selected_draft.draft_revision, selected_draft.shape_key,
    selected_draft.primary_color_key, selected_draft.secondary_color_key,
    selected_draft.pattern_key, selected_draft.border_key, selected_draft.symbol_key,
    selected_draft.adornment_key, selected_draft.palette_key,
    selected_draft.effect_key, selected_draft.initials, operation_id, auth.uid()
  ) returning * into saved_version;

  next_sequence := nextval('public.pachanga_team_crest_sequence');
  update public.pachanga_team_crest_state states
  set revision = states.revision + 1,
      published_version_id = saved_version.id,
      server_sequence = next_sequence,
      updated_at = clock_timestamp()
  where states.group_id = target_group_id;
  update public.pachanga_team_crest_drafts drafts
  set based_on_version = saved_version.version_number,
      updated_at = clock_timestamp()
  where drafts.group_id = target_group_id;
  insert into public.pachanga_team_crest_events(
    operation_id, group_id, event_type, crest_version_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id, target_group_id, 'crest_published', saved_version.id,
    selected_state.revision + 1, next_sequence,
    jsonb_build_object('version', saved_version.version_number)
  );

  for member in
    select distinct users.user_id
    from (
      select groups.owner_id as user_id
      from public.pachanga_groups groups where groups.id = target_group_id
      union all
      select memberships.user_id
      from public.pachanga_group_members memberships
      where memberships.group_id = target_group_id
    ) users
    where users.user_id is not null and users.user_id <> auth.uid()
  loop
    perform private.pachanga_notify_v1(
      member.user_id,
      'team_crest_published',
      'Nuevo escudo del equipo',
      'Un administrador ha publicado una nueva versión del escudo.',
      '/equipo/identidad?grupo=' || target_group_id::text,
      jsonb_build_object('groupId', target_group_id, 'version', saved_version.version_number),
      'team-crest:' || target_group_id::text || ':' || saved_version.version_number::text || ':' || member.user_id::text
    );
  end loop;

  response := public.get_pachanga_team_crest_snapshot_v1(target_group_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', selected_state.revision + 1,
      'serverSequence', next_sequence,
      'confirmedAt', clock_timestamp()
    );
  insert into public.pachanga_team_crest_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, expected_revision,
    confirmed_revision, server_sequence, response, client_metadata
  ) values (
    operation_id, 'publish', target_group_id, auth.uid(), expected_revision,
    selected_state.revision + 1, next_sequence, response,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end
  );
  return response;
end;
$$;

revoke all on function private.pachanga_team_crest_design_v1(text, text, text, text, text, text, text, text, text, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_assert_team_crest_piece_v1(uuid, text, text, boolean)
  from public, anon, authenticated;
revoke all on function private.pachanga_validate_team_crest_design_v1(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_crest_version_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_crest_draft_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_crest_replay_v1(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_crest_versions_are_immutable_v1()
  from public, anon, authenticated;

revoke all on function public.get_pachanga_team_crest_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_team_crest_snapshot_v1(uuid)
  to authenticated;
revoke all on function public.save_pachanga_team_crest_draft_v1(uuid, jsonb, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.save_pachanga_team_crest_draft_v1(uuid, jsonb, uuid, bigint, jsonb)
  to authenticated;
revoke all on function public.publish_pachanga_team_crest_v1(uuid, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.publish_pachanga_team_crest_v1(uuid, uuid, bigint, jsonb)
  to authenticated;

alter table public.pachanga_team_crest_state replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_team_crest_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_team_crest_state;
  end if;
end;
$$;
