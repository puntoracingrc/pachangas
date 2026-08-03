create table if not exists public.pachanga_market_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_group_id uuid references public.pachanga_groups(id) on delete set null,
  source_player_id text not null,
  display_name text not null,
  group_name text,
  avatar text,
  avatar_offset_x numeric,
  avatar_offset_y numeric,
  birth_date date,
  position text not null default 'Mediocentro / pivote',
  goalkeeper_only boolean not null default false,
  media numeric not null default 5,
  appearances integer not null default 0,
  goals integer not null default 0,
  wins integer not null default 0,
  zones text[] not null default '{}',
  availability_text text not null default '',
  modalities text[] not null default '{}',
  open_to_guest boolean not null default true,
  open_to_group boolean not null default true,
  bio text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists pachanga_market_profiles_user_id_idx
on public.pachanga_market_profiles(user_id);

create index if not exists pachanga_market_profiles_active_media_idx
on public.pachanga_market_profiles(active, media desc);

create index if not exists pachanga_market_profiles_source_group_id_idx
on public.pachanga_market_profiles(source_group_id);

create index if not exists pachanga_market_profiles_zones_idx
on public.pachanga_market_profiles using gin(zones);

create index if not exists pachanga_market_profiles_modalities_idx
on public.pachanga_market_profiles using gin(modalities);

grant select on public.pachanga_market_profiles to authenticated;

alter table public.pachanga_market_profiles enable row level security;

drop policy if exists "Authenticated users can read active market profiles" on public.pachanga_market_profiles;
create policy "Authenticated users can read active market profiles"
on public.pachanga_market_profiles
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    active = true
    or user_id = (select auth.uid())
  )
);

create or replace function public.sync_pachanga_market_profile(
  target_group_id uuid,
  target_player_id text,
  market_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  selected_player jsonb;
  current_group public.pachanga_groups%rowtype;
  market_player_patch jsonb;
  next_players jsonb;
  sanitized_zones text[];
  sanitized_modalities text[];
  saved_profile public.pachanga_market_profiles%rowtype;
  wants_active boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can publish market profiles';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'Only the player owner can publish this profile';
  end if;

  wants_active := coalesce((market_patch ->> 'active')::boolean, false);

  if not wants_active then
    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then value || jsonb_build_object('marketEnabled', false)
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    update public.pachanga_groups
    set payload = current_group.payload || jsonb_build_object('players', next_players)
    where id = target_group_id;

    update public.pachanga_market_profiles
    set active = false,
        updated_at = now()
    where user_id = current_user_id
    returning * into saved_profile;

    return jsonb_build_object('active', false, 'id', saved_profile.id);
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_zones
  from (
    select distinct left(trim(value), 80) as value
    from jsonb_array_elements_text(coalesce(market_patch -> 'zones', '[]'::jsonb)) as zones(value)
    where trim(value) <> ''
    limit 12
  ) as zone_values;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_modalities
  from (
    select distinct value
    from jsonb_array_elements_text(coalesce(market_patch -> 'modalities', '[]'::jsonb)) as modalities(value)
    where value in ('sala', 'futbol7', 'futbol11')
  ) as modality_values;

  market_player_patch := jsonb_build_object(
    'marketEnabled', true,
    'marketZones', left(coalesce(market_patch ->> 'zonesText', market_patch ->> 'marketZones', array_to_string(sanitized_zones, ', ')), 320),
    'marketAvailability', left(coalesce(market_patch ->> 'availabilityText', ''), 240),
    'marketBio', left(coalesce(market_patch ->> 'bio', ''), 280),
    'marketOpenToGroup', coalesce((market_patch ->> 'openToGroup')::boolean, true),
    'marketOpenToGuest', coalesce((market_patch ->> 'openToGuest')::boolean, true),
    'marketModalities', to_jsonb(sanitized_modalities)
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then value || market_player_patch
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  update public.pachanga_groups
  set payload = current_group.payload || jsonb_build_object('players', next_players)
  where id = target_group_id;

  insert into public.pachanga_market_profiles (
    user_id,
    source_group_id,
    source_player_id,
    display_name,
    group_name,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    position,
    goalkeeper_only,
    media,
    appearances,
    goals,
    wins,
    zones,
    availability_text,
    modalities,
    open_to_guest,
    open_to_group,
    bio,
    active
  )
  values (
    current_user_id,
    target_group_id,
    target_player_id,
    coalesce(nullif(trim(market_patch ->> 'displayName'), ''), nullif(trim(selected_player ->> 'name'), ''), 'Jugador'),
    nullif(trim(coalesce(market_patch ->> 'groupName', current_group.name)), ''),
    nullif(market_patch ->> 'avatar', ''),
    least(100, greatest(0, coalesce(nullif(market_patch ->> 'avatarOffsetX', '')::numeric, 50))),
    least(100, greatest(0, coalesce(nullif(market_patch ->> 'avatarOffsetY', '')::numeric, 0))),
    nullif(market_patch ->> 'birthDate', '')::date,
    coalesce(nullif(trim(market_patch ->> 'position'), ''), 'Mediocentro / pivote'),
    coalesce((market_patch ->> 'goalkeeperOnly')::boolean, false),
    greatest(1, least(10, coalesce((market_patch ->> 'media')::numeric, 5))),
    greatest(0, coalesce((market_patch ->> 'appearances')::integer, 0)),
    greatest(0, coalesce((market_patch ->> 'goals')::integer, 0)),
    greatest(0, coalesce((market_patch ->> 'wins')::integer, 0)),
    sanitized_zones,
    left(coalesce(market_patch ->> 'availabilityText', ''), 240),
    sanitized_modalities,
    coalesce((market_patch ->> 'openToGuest')::boolean, true),
    coalesce((market_patch ->> 'openToGroup')::boolean, true),
    left(coalesce(market_patch ->> 'bio', ''), 280),
    true
  )
  on conflict (user_id) do update set
    source_group_id = excluded.source_group_id,
    source_player_id = excluded.source_player_id,
    display_name = excluded.display_name,
    group_name = excluded.group_name,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    position = excluded.position,
    goalkeeper_only = excluded.goalkeeper_only,
    media = excluded.media,
    appearances = excluded.appearances,
    goals = excluded.goals,
    wins = excluded.wins,
    zones = excluded.zones,
    availability_text = excluded.availability_text,
    modalities = excluded.modalities,
    open_to_guest = excluded.open_to_guest,
    open_to_group = excluded.open_to_group,
    bio = excluded.bio,
    active = true,
    updated_at = now()
  returning * into saved_profile;

  return jsonb_build_object('active', saved_profile.active, 'id', saved_profile.id);
end;
$$;

revoke all on function public.sync_pachanga_market_profile(uuid, text, jsonb) from public;
revoke execute on function public.sync_pachanga_market_profile(uuid, text, jsonb) from anon;
grant execute on function public.sync_pachanga_market_profile(uuid, text, jsonb) to authenticated;
