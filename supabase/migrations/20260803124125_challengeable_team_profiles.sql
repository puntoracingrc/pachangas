-- Pachangas IQ social phase 3: voluntary public challengeable-team profiles.
-- Public search reads a server-maintained read model. Private challenge data,
-- exact fields and Rating V2 evidence remain outside this surface.

create sequence if not exists public.pachanga_challengeable_team_sequence;
revoke all on sequence public.pachanga_challengeable_team_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_challengeable_team_sequence to service_role;

create table if not exists public.pachanga_team_level_read_models (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  stable_level numeric,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_challengeable_team_sequence'),
  calculated_at timestamptz not null default now(),
  check (stable_level is null or stable_level between 0 and 100),
  check (revision >= 0)
);

create table if not exists public.pachanga_challengeable_team_profiles (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  enabled boolean not null default false,
  zone_label text,
  zone_place_id text,
  zone_lat double precision,
  zone_lng double precision,
  travel_radius_km integer not null default 20,
  min_opponent_level numeric not null default 0,
  max_opponent_level numeric not null default 100,
  modalities text[] not null default '{}',
  revision bigint not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (revision >= 0),
  check (travel_radius_km between 1 and 100),
  check (min_opponent_level between 0 and 100),
  check (max_opponent_level between 0 and 100),
  check (min_opponent_level <= max_opponent_level),
  check (zone_label is null or char_length(zone_label) between 2 and 120),
  check (zone_place_id is null or char_length(zone_place_id) <= 300),
  check ((zone_lat is null) = (zone_lng is null)),
  check (zone_lat is null or zone_lat between -90 and 90),
  check (zone_lng is null or zone_lng between -180 and 180),
  check (modalities <@ array['sala', 'futbol7', 'futbol11']::text[]),
  check (cardinality(modalities) <= 3),
  check (
    not enabled
    or (
      zone_label is not null
      and zone_lat is not null
      and cardinality(modalities) > 0
    )
  )
);

create index if not exists pachanga_challengeable_profiles_enabled_level_idx
  on public.pachanga_challengeable_team_profiles(enabled, min_opponent_level, max_opponent_level, group_id)
  where enabled;
create index if not exists pachanga_challengeable_profiles_zone_idx
  on public.pachanga_challengeable_team_profiles(lower(zone_label), group_id)
  where enabled;

create table if not exists public.pachanga_challengeable_team_availability (
  group_id uuid not null references public.pachanga_challengeable_team_profiles(group_id) on delete cascade,
  weekday smallint not null,
  starts_at time without time zone not null,
  ends_at time without time zone not null,
  primary key (group_id, weekday, starts_at),
  check (weekday between 1 and 7),
  check (ends_at > starts_at)
);

create index if not exists pachanga_challengeable_availability_search_idx
  on public.pachanga_challengeable_team_availability(weekday, starts_at, ends_at, group_id);

create table if not exists public.pachanga_challengeable_team_profile_state (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_challengeable_team_sequence'),
  updated_at timestamptz not null default now(),
  check (revision >= 0)
);

create table if not exists public.pachanga_challengeable_team_search_state (
  id boolean primary key default true,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_challengeable_team_sequence'),
  updated_at timestamptz not null default now(),
  check (id),
  check (revision >= 0)
);

insert into public.pachanga_challengeable_team_search_state(id)
values (true)
on conflict (id) do nothing;

create table if not exists public.pachanga_challengeable_team_profile_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  operation_id uuid not null unique,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null,
  profile_revision bigint not null,
  snapshot jsonb not null,
  server_sequence bigint not null default nextval('public.pachanga_challengeable_team_sequence'),
  created_at timestamptz not null default now(),
  check (event_type in ('profile_enabled', 'profile_updated', 'profile_disabled')),
  check (profile_revision >= 1)
);

create unique index if not exists pachanga_challengeable_profile_events_sequence_idx
  on public.pachanga_challengeable_team_profile_events(server_sequence);
create index if not exists pachanga_challengeable_profile_events_group_idx
  on public.pachanga_challengeable_team_profile_events(group_id, profile_revision desc, server_sequence desc);

create table if not exists public.pachanga_challengeable_team_operation_receipts (
  operation_id uuid primary key,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  operation_type text not null,
  expected_revision bigint not null,
  result_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (expected_revision >= 0),
  check (result_revision >= 0),
  check (jsonb_typeof(client_metadata) = 'object')
);

create index if not exists pachanga_challengeable_receipts_group_created_idx
  on public.pachanga_challengeable_team_operation_receipts(group_id, created_at desc, operation_id);

alter table public.pachanga_team_level_read_models enable row level security;
alter table public.pachanga_challengeable_team_profiles enable row level security;
alter table public.pachanga_challengeable_team_availability enable row level security;
alter table public.pachanga_challengeable_team_profile_state enable row level security;
alter table public.pachanga_challengeable_team_search_state enable row level security;
alter table public.pachanga_challengeable_team_profile_events enable row level security;
alter table public.pachanga_challengeable_team_operation_receipts enable row level security;

revoke all on table public.pachanga_team_level_read_models from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_profiles from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_availability from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_profile_state from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_search_state from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_profile_events from public, anon, authenticated;
revoke all on table public.pachanga_challengeable_team_operation_receipts from public, anon, authenticated;

grant select on table public.pachanga_challengeable_team_profile_state to authenticated;
grant select on table public.pachanga_challengeable_team_search_state to authenticated;
grant all on table public.pachanga_team_level_read_models to service_role;
grant all on table public.pachanga_challengeable_team_profiles to service_role;
grant all on table public.pachanga_challengeable_team_availability to service_role;
grant all on table public.pachanga_challengeable_team_profile_state to service_role;
grant all on table public.pachanga_challengeable_team_search_state to service_role;
grant all on table public.pachanga_challengeable_team_profile_events to service_role;
grant all on table public.pachanga_challengeable_team_operation_receipts to service_role;

drop policy if exists "Members can observe challengeable profile revisions" on public.pachanga_challengeable_team_profile_state;
create policy "Members can observe challengeable profile revisions"
on public.pachanga_challengeable_team_profile_state
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

drop policy if exists "Registered users can observe challengeable search revisions" on public.pachanga_challengeable_team_search_state;
create policy "Registered users can observe challengeable search revisions"
on public.pachanga_challengeable_team_search_state
for select
to authenticated
using (public.is_registered_pachanga_user());

create or replace function public.pachanga_initialize_challengeable_team_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_challengeable_team_profile_state(group_id)
  values (new.id)
  on conflict (group_id) do nothing;

  insert into public.pachanga_team_level_read_models(group_id)
  values (new.id)
  on conflict (group_id) do nothing;
  return new;
end;
$$;

drop trigger if exists initialize_pachanga_challengeable_team_state on public.pachanga_groups;
create trigger initialize_pachanga_challengeable_team_state
after insert on public.pachanga_groups
for each row execute function public.pachanga_initialize_challengeable_team_state();

insert into public.pachanga_challengeable_team_profile_state(group_id)
select groups.id
from public.pachanga_groups groups
on conflict (group_id) do nothing;

insert into public.pachanga_team_level_read_models(
  group_id,
  stable_level,
  revision,
  server_sequence,
  calculated_at
)
select
  groups.id,
  public.pachanga_group_level_v2(groups.id, clock_timestamp()),
  0,
  nextval('public.pachanga_challengeable_team_sequence'),
  clock_timestamp()
from public.pachanga_groups groups
on conflict (group_id) do update set
  stable_level = excluded.stable_level,
  calculated_at = excluded.calculated_at;

create or replace function public.pachanga_refresh_team_level_read_model(target_group_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_level numeric;
  next_level numeric;
  next_sequence bigint;
begin
  if target_group_id is null or not exists (
    select 1 from public.pachanga_groups groups where groups.id = target_group_id
  ) then
    return;
  end if;

  select levels.stable_level
  into current_level
  from public.pachanga_team_level_read_models levels
  where levels.group_id = target_group_id
  for update;

  next_level := public.pachanga_group_level_v2(target_group_id, clock_timestamp());

  if found and current_level is not distinct from next_level then
    return;
  end if;

  perform 1
  from public.pachanga_challengeable_team_search_state state
  where state.id
  for update;

  next_sequence := nextval('public.pachanga_challengeable_team_sequence');
  insert into public.pachanga_team_level_read_models(
    group_id, stable_level, revision, server_sequence, calculated_at
  ) values (
    target_group_id, next_level, 1, next_sequence, clock_timestamp()
  )
  on conflict (group_id) do update set
    stable_level = excluded.stable_level,
    revision = public.pachanga_team_level_read_models.revision + 1,
    server_sequence = excluded.server_sequence,
    calculated_at = excluded.calculated_at;

  update public.pachanga_challengeable_team_search_state
  set revision = revision + 1,
      server_sequence = next_sequence,
      updated_at = clock_timestamp()
  where id;

  update public.pachanga_challengeable_team_profile_state
  set server_sequence = next_sequence,
      updated_at = clock_timestamp()
  where group_id = target_group_id;
end;
$$;

create or replace function public.pachanga_refresh_team_levels_for_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_group_id uuid;
  affected_user_id uuid;
begin
  affected_user_id := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  for affected_group_id in
    select distinct members.group_id
    from public.pachanga_group_members members
    where members.user_id = affected_user_id
    order by members.group_id
  loop
    perform public.pachanga_refresh_team_level_read_model(affected_group_id);
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_challengeable_level_after_profile_insert_delete on public.pachanga_player_profiles;
create trigger refresh_challengeable_level_after_profile_insert_delete
after insert or delete on public.pachanga_player_profiles
for each row execute function public.pachanga_refresh_team_levels_for_profile();

drop trigger if exists refresh_challengeable_level_after_profile_update on public.pachanga_player_profiles;
create trigger refresh_challengeable_level_after_profile_update
after update of calibrated_overall, inactive on public.pachanga_player_profiles
for each row
when (
  old.calibrated_overall is distinct from new.calibrated_overall
  or old.inactive is distinct from new.inactive
)
execute function public.pachanga_refresh_team_levels_for_profile();

create or replace function public.pachanga_refresh_team_levels_for_membership()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_group_id uuid;
begin
  for affected_group_id in
    select distinct affected.group_id
    from unnest(
      case
        when tg_op = 'INSERT' then array[new.group_id]
        when tg_op = 'DELETE' then array[old.group_id]
        else array[old.group_id, new.group_id]
      end
    ) affected(group_id)
    order by affected.group_id
  loop
    perform public.pachanga_refresh_team_level_read_model(affected_group_id);
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_challengeable_level_after_membership_change on public.pachanga_group_members;
create trigger refresh_challengeable_level_after_membership_change
after insert or delete or update of group_id, user_id on public.pachanga_group_members
for each row execute function public.pachanga_refresh_team_levels_for_membership();

create or replace function public.pachanga_refresh_team_level_after_match_snapshot()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_group_id uuid;
begin
  affected_group_id := case when tg_op = 'DELETE' then old.group_id else new.group_id end;
  perform public.pachanga_refresh_team_level_read_model(affected_group_id);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_challengeable_level_after_match_snapshot_insert_delete on public.pachanga_match_rating_snapshots;
create trigger refresh_challengeable_level_after_match_snapshot_insert_delete
after insert or delete on public.pachanga_match_rating_snapshots
for each row execute function public.pachanga_refresh_team_level_after_match_snapshot();

drop trigger if exists refresh_challengeable_level_after_match_snapshot_update on public.pachanga_match_rating_snapshots;
create trigger refresh_challengeable_level_after_match_snapshot_update
after update of state, finalized_at, group_level on public.pachanga_match_rating_snapshots
for each row
when (
  old.state is distinct from new.state
  or old.finalized_at is distinct from new.finalized_at
  or old.group_level is distinct from new.group_level
)
execute function public.pachanga_refresh_team_level_after_match_snapshot();

create or replace function public.pachanga_refresh_team_level_after_participant_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  affected_group_id uuid;
begin
  affected_group_id := case when tg_op = 'DELETE' then old.group_id else new.group_id end;
  perform public.pachanga_refresh_team_level_read_model(affected_group_id);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_challengeable_level_after_participant_delete on public.pachanga_match_rating_participants;
create trigger refresh_challengeable_level_after_participant_delete
after delete on public.pachanga_match_rating_participants
for each row execute function public.pachanga_refresh_team_level_after_participant_change();

drop trigger if exists refresh_challengeable_level_after_participant_update on public.pachanga_match_rating_participants;
create trigger refresh_challengeable_level_after_participant_update
after update of player_profile_id, attendance_confirmed, was_reserve on public.pachanga_match_rating_participants
for each row
when (
  old.player_profile_id is distinct from new.player_profile_id
  or old.attendance_confirmed is distinct from new.attendance_confirmed
  or old.was_reserve is distinct from new.was_reserve
)
execute function public.pachanga_refresh_team_level_after_participant_change();

create or replace function public.pachanga_challengeable_profile_operation_replay(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_type text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  stored_actor uuid;
  stored_group uuid;
  stored_operation_type text;
  stored_response jsonb;
begin
  select receipts.actor_user_id, receipts.group_id, receipts.operation_type, receipts.response
  into stored_actor, stored_group, stored_operation_type, stored_response
  from public.pachanga_challengeable_team_operation_receipts receipts
  where receipts.operation_id = target_operation_id;

  if found and (
    stored_actor is distinct from target_actor_user_id
    or stored_group is distinct from target_group_id
    or stored_operation_type is distinct from target_operation_type
  ) then
    raise exception 'Operation id was already used for another action';
  end if;
  return stored_response;
end;
$$;

create or replace function public.pachanga_challengeable_team_profile_snapshot(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_profile public.pachanga_challengeable_team_profiles%rowtype;
  current_state public.pachanga_challengeable_team_profile_state%rowtype;
  current_search_state public.pachanga_challengeable_team_search_state%rowtype;
  current_level public.pachanga_team_level_read_models%rowtype;
  availability_items jsonb;
begin
  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;

  select * into current_profile
  from public.pachanga_challengeable_team_profiles profiles
  where profiles.group_id = target_group_id;

  select * into current_state
  from public.pachanga_challengeable_team_profile_state states
  where states.group_id = target_group_id;

  select * into current_search_state
  from public.pachanga_challengeable_team_search_state states
  where states.id;

  select * into current_level
  from public.pachanga_team_level_read_models levels
  where levels.group_id = target_group_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'day', slots.weekday,
      'start', to_char(slots.starts_at, 'HH24:MI'),
      'end', to_char(slots.ends_at, 'HH24:MI')
    ) order by slots.weekday, slots.starts_at, slots.ends_at
  ), '[]'::jsonb)
  into availability_items
  from public.pachanga_challengeable_team_availability slots
  where slots.group_id = target_group_id;

  return jsonb_build_object(
    'group', jsonb_build_object(
      'groupId', current_group.id,
      'name', current_group.name,
      'teamCode', current_group.team_code
    ),
    'canManage', public.is_pachanga_group_admin(target_group_id),
    'ownLevel', current_level.stable_level,
    'levelRevision', coalesce(current_level.revision, 0),
    'profileRevision', coalesce(current_state.revision, 0),
    'confirmedRevision', coalesce(current_state.revision, 0),
    'searchRevision', coalesce(current_search_state.revision, 0),
    'serverSequence', coalesce(current_state.server_sequence, 0),
    'updatedAt', coalesce(current_state.updated_at, current_group.updated_at),
    'profile', jsonb_build_object(
      'enabled', coalesce(current_profile.enabled, false),
      'zone', jsonb_build_object(
        'label', current_profile.zone_label,
        'placeId', current_profile.zone_place_id,
        'lat', current_profile.zone_lat,
        'lng', current_profile.zone_lng
      ),
      'travelRadiusKm', coalesce(current_profile.travel_radius_km, 20),
      'minOpponentLevel', coalesce(current_profile.min_opponent_level, 0),
      'maxOpponentLevel', coalesce(current_profile.max_opponent_level, 100),
      'modalities', coalesce(to_jsonb(current_profile.modalities), '[]'::jsonb),
      'availability', availability_items
    )
  );
end;
$$;

create or replace function public.get_pachanga_challengeable_team_profile(target_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Group membership required';
  end if;

  perform 1
  from public.pachanga_challengeable_team_profile_state states
  where states.group_id = target_group_id
  for share;

  return public.pachanga_challengeable_team_profile_snapshot(target_group_id);
end;
$$;

create or replace function public.pachanga_challengeable_store_profile_response(
  target_group_id uuid,
  target_operation_id uuid,
  target_expected_revision bigint,
  target_server_sequence bigint,
  target_client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canonical jsonb;
  final_response jsonb;
  stored_response jsonb;
begin
  canonical := public.pachanga_challengeable_team_profile_snapshot(target_group_id);
  final_response := canonical || jsonb_build_object(
    'operationId', target_operation_id,
    'expectedRevision', target_expected_revision,
    'confirmedAt', clock_timestamp(),
    'serverSequence', target_server_sequence
  );

  insert into public.pachanga_challengeable_team_operation_receipts(
    operation_id,
    group_id,
    actor_user_id,
    operation_type,
    expected_revision,
    result_revision,
    server_sequence,
    response,
    client_metadata
  ) values (
    target_operation_id,
    target_group_id,
    auth.uid(),
    'challengeable_profile_saved',
    target_expected_revision,
    (canonical ->> 'confirmedRevision')::bigint,
    target_server_sequence,
    final_response,
    case
      when jsonb_typeof(target_client_metadata) = 'object'
        and pg_column_size(target_client_metadata) <= 4096 then target_client_metadata
      else '{}'::jsonb
    end
  )
  on conflict (operation_id) do nothing;

  select receipts.response into stored_response
  from public.pachanga_challengeable_team_operation_receipts receipts
  where receipts.operation_id = target_operation_id
    and receipts.actor_user_id = auth.uid();

  if stored_response is null then raise exception 'Operation belongs to another actor'; end if;
  return stored_response;
end;
$$;

create or replace function public.upsert_pachanga_challengeable_team_profile_authoritative(
  target_group_id uuid,
  target_enabled boolean,
  target_zone_label text,
  target_zone_place_id text,
  target_zone_lat double precision,
  target_zone_lng double precision,
  target_travel_radius_km integer,
  target_min_opponent_level numeric,
  target_max_opponent_level numeric,
  target_modalities text[],
  target_availability jsonb,
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
  current_revision bigint;
  event_sequence bigint;
  previous_enabled boolean;
  replay jsonb;
  safe_modalities text[];
  safe_zone_label text := nullif(trim(target_zone_label), '');
  safe_zone_place_id text := nullif(trim(target_zone_place_id), '');
  slot jsonb;
  slot_start time without time zone;
  slot_end time without time zone;
  snapshot jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('challengeable-team-operation:' || operation_id::text, 0));
  replay := public.pachanga_challengeable_profile_operation_replay(
    target_group_id, operation_id, auth.uid(), 'challengeable_profile_saved'
  );
  if replay is not null then return replay; end if;

  if target_enabled is null then raise exception 'Availability status required'; end if;
  if target_travel_radius_km is null or target_travel_radius_km < 1 or target_travel_radius_km > 100 then
    raise exception 'Travel radius must be between 1 and 100 km';
  end if;
  if target_min_opponent_level is null or target_max_opponent_level is null
    or target_min_opponent_level < 0 or target_max_opponent_level > 100
    or target_min_opponent_level > target_max_opponent_level then
    raise exception 'Opponent level range is invalid';
  end if;
  if char_length(coalesce(safe_zone_label, '')) > 120
    or char_length(coalesce(safe_zone_place_id, '')) > 300 then
    raise exception 'Zone data is too long';
  end if;
  if (target_zone_lat is null) <> (target_zone_lng is null)
    or (target_zone_lat is not null and target_zone_lat not between -90 and 90)
    or (target_zone_lng is not null and target_zone_lng not between -180 and 180) then
    raise exception 'Zone coordinates are invalid';
  end if;

  select coalesce(array_agg(distinct modality order by modality), '{}'::text[])
  into safe_modalities
  from unnest(coalesce(target_modalities, '{}'::text[])) modalities(modality);

  if exists (
    select 1 from unnest(safe_modalities) modalities(modality)
    where modality not in ('sala', 'futbol7', 'futbol11')
  ) then
    raise exception 'Invalid modality';
  end if;

  if target_availability is null or jsonb_typeof(target_availability) <> 'array'
    or jsonb_array_length(target_availability) > 21 then
    raise exception 'Availability must be an array with at most 21 time slots';
  end if;

  for slot in select value from jsonb_array_elements(target_availability) entries(value)
  loop
    if jsonb_typeof(slot) <> 'object'
      or coalesce(slot ->> 'day', '') !~ '^[1-7]$'
      or coalesce(slot ->> 'start', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      or coalesce(slot ->> 'end', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'Availability slot is invalid';
    end if;
    slot_start := (slot ->> 'start')::time;
    slot_end := (slot ->> 'end')::time;
    if slot_end <= slot_start then raise exception 'Availability end must be after start'; end if;
  end loop;

  if target_enabled and (
    safe_zone_label is null
    or target_zone_lat is null
    or cardinality(safe_modalities) = 0
    or jsonb_array_length(target_availability) = 0
  ) then
    raise exception 'Enabled public profiles require zone, coordinates, modality and availability';
  end if;

  perform public.pachanga_refresh_team_level_read_model(target_group_id);

  insert into public.pachanga_challengeable_team_profile_state(group_id)
  values (target_group_id)
  on conflict (group_id) do nothing;

  perform 1
  from public.pachanga_challengeable_team_profile_state states
  where states.group_id = target_group_id
  for update;

  perform 1
  from public.pachanga_challengeable_team_search_state states
  where states.id
  for update;

  select states.revision into current_revision
  from public.pachanga_challengeable_team_profile_state states
  where states.group_id = target_group_id;
  if current_revision is distinct from expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select profiles.enabled into previous_enabled
  from public.pachanga_challengeable_team_profiles profiles
  where profiles.group_id = target_group_id;

  insert into public.pachanga_challengeable_team_profiles(
    group_id,
    enabled,
    zone_label,
    zone_place_id,
    zone_lat,
    zone_lng,
    travel_radius_km,
    min_opponent_level,
    max_opponent_level,
    modalities,
    revision,
    created_by,
    updated_by,
    updated_at
  ) values (
    target_group_id,
    target_enabled,
    safe_zone_label,
    safe_zone_place_id,
    target_zone_lat,
    target_zone_lng,
    target_travel_radius_km,
    target_min_opponent_level,
    target_max_opponent_level,
    safe_modalities,
    current_revision + 1,
    auth.uid(),
    auth.uid(),
    clock_timestamp()
  )
  on conflict (group_id) do update set
    enabled = excluded.enabled,
    zone_label = excluded.zone_label,
    zone_place_id = excluded.zone_place_id,
    zone_lat = excluded.zone_lat,
    zone_lng = excluded.zone_lng,
    travel_radius_km = excluded.travel_radius_km,
    min_opponent_level = excluded.min_opponent_level,
    max_opponent_level = excluded.max_opponent_level,
    modalities = excluded.modalities,
    revision = excluded.revision,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  delete from public.pachanga_challengeable_team_availability
  where group_id = target_group_id;

  for slot in select value from jsonb_array_elements(target_availability) entries(value)
  loop
    insert into public.pachanga_challengeable_team_availability(
      group_id, weekday, starts_at, ends_at
    ) values (
      target_group_id,
      (slot ->> 'day')::smallint,
      (slot ->> 'start')::time,
      (slot ->> 'end')::time
    );
  end loop;

  event_sequence := nextval('public.pachanga_challengeable_team_sequence');
  update public.pachanga_challengeable_team_profile_state
  set revision = current_revision + 1,
      server_sequence = event_sequence,
      updated_at = clock_timestamp()
  where group_id = target_group_id;

  update public.pachanga_challengeable_team_search_state
  set revision = revision + 1,
      server_sequence = event_sequence,
      updated_at = clock_timestamp()
  where id;

  snapshot := public.pachanga_challengeable_team_profile_snapshot(target_group_id);
  insert into public.pachanga_challengeable_team_profile_events(
    group_id,
    operation_id,
    actor_user_id,
    event_type,
    profile_revision,
    snapshot,
    server_sequence
  ) values (
    target_group_id,
    operation_id,
    auth.uid(),
    case
      when not target_enabled then 'profile_disabled'
      when coalesce(previous_enabled, false) then 'profile_updated'
      else 'profile_enabled'
    end,
    current_revision + 1,
    snapshot,
    event_sequence
  );

  return public.pachanga_challengeable_store_profile_response(
    target_group_id,
    operation_id,
    expected_revision,
    event_sequence,
    client_metadata
  );
end;
$$;

create or replace function public.search_pachanga_challengeable_teams(
  requesting_group_id uuid,
  target_zone_query text default null,
  target_zone_lat double precision default null,
  target_zone_lng double precision default null,
  target_max_distance_km integer default null,
  target_min_team_level numeric default null,
  target_max_team_level numeric default null,
  target_weekday smallint default null,
  target_start_time time without time zone default null,
  target_end_time time without time zone default null,
  target_modality text default null,
  target_page integer default 1,
  target_page_size integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  candidate record;
  current_search_state public.pachanga_challengeable_team_search_state%rowtype;
  has_more boolean := false;
  item_count integer := 0;
  items jsonb := '[]'::jsonb;
  requester_level numeric;
  safe_page integer := coalesce(target_page, 1);
  safe_page_size integer := coalesce(target_page_size, 12);
  safe_zone_query text := case
    when target_zone_lat is null then nullif(trim(target_zone_query), '')
    else null
  end;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(requesting_group_id) then
    raise exception 'Group membership required';
  end if;
  if safe_page < 1 or safe_page > 1000 or safe_page_size < 1 or safe_page_size > 24 then
    raise exception 'Invalid pagination';
  end if;
  if char_length(coalesce(safe_zone_query, '')) > 120 then raise exception 'Zone query is too long'; end if;
  if (target_zone_lat is null) <> (target_zone_lng is null)
    or (target_zone_lat is not null and target_zone_lat not between -90 and 90)
    or (target_zone_lng is not null and target_zone_lng not between -180 and 180) then
    raise exception 'Search coordinates are invalid';
  end if;
  if target_max_distance_km is not null and (
    target_zone_lat is null or target_max_distance_km < 1 or target_max_distance_km > 100
  ) then
    raise exception 'Distance filter requires a zone and 1 to 100 km';
  end if;
  if (target_min_team_level is not null and target_min_team_level not between 0 and 100)
    or (target_max_team_level is not null and target_max_team_level not between 0 and 100)
    or (
      target_min_team_level is not null
      and target_max_team_level is not null
      and target_min_team_level > target_max_team_level
    ) then
    raise exception 'Team level filter is invalid';
  end if;
  if target_weekday is not null and target_weekday not between 1 and 7 then raise exception 'Invalid weekday'; end if;
  if (target_start_time is null) <> (target_end_time is null)
    or (
      target_start_time is not null
      and (target_weekday is null or target_end_time <= target_start_time)
    ) then
    raise exception 'Time filter requires a day and a valid range';
  end if;
  if target_modality is not null and target_modality not in ('sala', 'futbol7', 'futbol11') then
    raise exception 'Invalid modality';
  end if;

  perform 1
  from public.pachanga_challengeable_team_search_state states
  where states.id
  for share;

  select * into current_search_state
  from public.pachanga_challengeable_team_search_state states
  where states.id;

  select levels.stable_level into requester_level
  from public.pachanga_team_level_read_models levels
  where levels.group_id = requesting_group_id;

  for candidate in
    with candidates as (
      select
        profiles.*,
        groups.name as group_name,
        levels.stable_level as team_level,
        case
          when target_zone_lat is null or profiles.zone_lat is null then null
          else 6371.0 * 2.0 * asin(sqrt(least(1.0,
            power(sin(radians(profiles.zone_lat - target_zone_lat) / 2.0), 2)
            + cos(radians(target_zone_lat)) * cos(radians(profiles.zone_lat))
              * power(sin(radians(profiles.zone_lng - target_zone_lng) / 2.0), 2)
          )))
        end as distance_km,
        (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'day', slots.weekday,
              'start', to_char(slots.starts_at, 'HH24:MI'),
              'end', to_char(slots.ends_at, 'HH24:MI')
            ) order by slots.weekday, slots.starts_at, slots.ends_at
          ), '[]'::jsonb)
          from public.pachanga_challengeable_team_availability slots
          where slots.group_id = profiles.group_id
        ) as availability
      from public.pachanga_challengeable_team_profiles profiles
      join public.pachanga_groups groups on groups.id = profiles.group_id
      left join public.pachanga_team_level_read_models levels on levels.group_id = profiles.group_id
      where profiles.enabled
        and profiles.group_id <> requesting_group_id
        and (requester_level is null or requester_level between profiles.min_opponent_level and profiles.max_opponent_level)
        and (target_min_team_level is null or levels.stable_level >= target_min_team_level)
        and (target_max_team_level is null or levels.stable_level <= target_max_team_level)
        and (target_modality is null or target_modality = any(profiles.modalities))
        and (
          safe_zone_query is null
          or lower(profiles.zone_label) like '%' || lower(safe_zone_query) || '%'
        )
        and (
          target_weekday is null
          or exists (
            select 1
            from public.pachanga_challengeable_team_availability slots
            where slots.group_id = profiles.group_id
              and slots.weekday = target_weekday
              and (
                target_start_time is null
                or slots.starts_at <= target_start_time and slots.ends_at >= target_end_time
              )
          )
        )
    )
    select *
    from candidates
    where target_zone_lat is null
      or (
        distance_km <= travel_radius_km
        and (target_max_distance_km is null or distance_km <= target_max_distance_km)
      )
    order by
      distance_km asc nulls last,
      abs(coalesce(team_level, 50) - coalesce(requester_level, team_level, 50)),
      lower(group_name),
      group_id
    offset (safe_page - 1) * safe_page_size
    limit safe_page_size + 1
  loop
    item_count := item_count + 1;
    if item_count > safe_page_size then
      has_more := true;
    else
      items := items || jsonb_build_array(jsonb_build_object(
        'groupId', candidate.group_id,
        'name', candidate.group_name,
        'zoneLabel', candidate.zone_label,
        'travelRadiusKm', candidate.travel_radius_km,
        'teamLevel', candidate.team_level,
        'minOpponentLevel', candidate.min_opponent_level,
        'maxOpponentLevel', candidate.max_opponent_level,
        'modalities', to_jsonb(candidate.modalities),
        'availability', candidate.availability,
        'distanceKm', case when candidate.distance_km is null then null else round(candidate.distance_km::numeric, 1) end,
        'levelCompatibility', case
          when requester_level is null or candidate.team_level is null then 'unknown'
          else 'compatible'
        end,
        'profileRevision', candidate.revision,
        'updatedAt', candidate.updated_at
      ));
    end if;
  end loop;

  return jsonb_build_object(
    'items', items,
    'page', safe_page,
    'pageSize', safe_page_size,
    'hasMore', has_more,
    'requestingGroupId', requesting_group_id,
    'requesterLevel', requester_level,
    'searchRevision', coalesce(current_search_state.revision, 0),
    'confirmedRevision', coalesce(current_search_state.revision, 0),
    'serverSequence', coalesce(current_search_state.server_sequence, 0),
    'updatedAt', current_search_state.updated_at
  );
end;
$$;

create or replace function public.lookup_pachanga_challengeable_team_for_challenge(
  requesting_group_id uuid,
  opponent_group_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  opponent public.pachanga_groups%rowtype;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(requesting_group_id) then
    raise exception 'Only group admins can prepare public challenges';
  end if;
  if opponent_group_id is null or opponent_group_id = requesting_group_id then
    raise exception 'Invalid rival';
  end if;

  select groups.* into opponent
  from public.pachanga_groups groups
  join public.pachanga_challengeable_team_profiles profiles on profiles.group_id = groups.id
  where groups.id = opponent_group_id
    and profiles.enabled;
  if not found then raise exception 'Public rival is no longer available'; end if;

  return jsonb_build_object(
    'groupId', opponent.id,
    'name', opponent.name,
    'teamCode', opponent.team_code
  );
end;
$$;

revoke all on function public.pachanga_initialize_challengeable_team_state() from public, anon, authenticated;
revoke all on function public.pachanga_refresh_team_level_read_model(uuid) from public, anon, authenticated;
revoke all on function public.pachanga_refresh_team_levels_for_profile() from public, anon, authenticated;
revoke all on function public.pachanga_refresh_team_levels_for_membership() from public, anon, authenticated;
revoke all on function public.pachanga_refresh_team_level_after_match_snapshot() from public, anon, authenticated;
revoke all on function public.pachanga_refresh_team_level_after_participant_change() from public, anon, authenticated;
revoke all on function public.pachanga_challengeable_profile_operation_replay(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.pachanga_challengeable_team_profile_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.pachanga_challengeable_store_profile_response(uuid, uuid, bigint, bigint, jsonb) from public, anon, authenticated;

revoke all on function public.get_pachanga_challengeable_team_profile(uuid) from public, anon, authenticated;
revoke all on function public.upsert_pachanga_challengeable_team_profile_authoritative(
  uuid, boolean, text, text, double precision, double precision, integer, numeric, numeric, text[], jsonb, uuid, bigint, jsonb
) from public, anon, authenticated;
revoke all on function public.search_pachanga_challengeable_teams(
  uuid, text, double precision, double precision, integer, numeric, numeric, smallint,
  time without time zone, time without time zone, text, integer, integer
) from public, anon, authenticated;
revoke all on function public.lookup_pachanga_challengeable_team_for_challenge(uuid, uuid) from public, anon, authenticated;

grant execute on function public.get_pachanga_challengeable_team_profile(uuid) to authenticated;
grant execute on function public.upsert_pachanga_challengeable_team_profile_authoritative(
  uuid, boolean, text, text, double precision, double precision, integer, numeric, numeric, text[], jsonb, uuid, bigint, jsonb
) to authenticated;
grant execute on function public.search_pachanga_challengeable_teams(
  uuid, text, double precision, double precision, integer, numeric, numeric, smallint,
  time without time zone, time without time zone, text, integer, integer
) to authenticated;
grant execute on function public.lookup_pachanga_challengeable_team_for_challenge(uuid, uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_challengeable_team_profile_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_challengeable_team_profile_state;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_challengeable_team_search_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_challengeable_team_search_state;
  end if;
end;
$$;
