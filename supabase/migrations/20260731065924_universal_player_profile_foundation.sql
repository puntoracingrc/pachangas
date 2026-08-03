create table if not exists public.pachanga_player_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_group_id uuid references public.pachanga_groups(id) on delete set null,
  source_player_id text,
  display_name text not null default 'Jugador',
  phone text not null default '',
  avatar text,
  avatar_offset_x numeric,
  avatar_offset_y numeric,
  birth_date date,
  goalkeeper_only boolean not null default false,
  injured boolean not null default false,
  inactive boolean not null default false,
  imported_rating numeric,
  imported_rating_at timestamptz,
  imported_rating_from_group text,
  rating numeric not null default 5,
  ratings jsonb not null default '[]'::jsonb,
  rating_votes jsonb not null default '[]'::jsonb,
  position text not null default 'Mediocentro / pivote',
  outfield_position text,
  market_enabled boolean not null default false,
  market_zones text not null default '',
  market_zones_geo jsonb not null default '[]'::jsonb,
  market_availability text not null default '',
  market_bio text not null default '',
  market_modalities text[] not null default '{}',
  market_open_to_group boolean not null default true,
  market_open_to_guest boolean not null default true,
  stats jsonb not null default '{}'::jsonb,
  profile_version bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rating >= 1 and rating <= 10),
  check (imported_rating is null or (imported_rating >= 1 and imported_rating <= 10))
);

alter table public.pachanga_market_profiles
add column if not exists player_profile_id uuid references public.pachanga_player_profiles(id) on delete set null;

create unique index if not exists pachanga_player_profiles_user_id_idx
on public.pachanga_player_profiles(user_id);

create index if not exists pachanga_player_profiles_source_group_id_idx
on public.pachanga_player_profiles(source_group_id)
where source_group_id is not null;

create index if not exists pachanga_player_profiles_active_market_idx
on public.pachanga_player_profiles(market_enabled, rating desc)
where market_enabled = true;

create index if not exists pachanga_market_profiles_player_profile_id_idx
on public.pachanga_market_profiles(player_profile_id)
where player_profile_id is not null;

grant select on public.pachanga_player_profiles to authenticated;

alter table public.pachanga_player_profiles enable row level security;

drop policy if exists "Users can read own universal player profile" on public.pachanga_player_profiles;
create policy "Users can read own universal player profile"
on public.pachanga_player_profiles
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
);

create or replace function public.pachanga_player_profile_patch(target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  profile public.pachanga_player_profiles%rowtype;
begin
  select * into profile
  from public.pachanga_player_profiles
  where id = target_profile_id;

  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'globalPlayerProfileId', profile.id::text,
      'ownerUserId', profile.user_id::text,
      'name', profile.display_name,
      'phone', profile.phone,
      'avatar', profile.avatar,
      'avatarOffsetX', profile.avatar_offset_x,
      'avatarOffsetY', profile.avatar_offset_y,
      'birthDate', profile.birth_date,
      'goalkeeperOnly', profile.goalkeeper_only,
      'injured', profile.injured,
      'inactive', profile.inactive,
      'importedRating', profile.imported_rating,
      'importedRatingAt', case
        when profile.imported_rating_at is not null then to_char(profile.imported_rating_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        else null
      end,
      'importedRatingFromGroup', profile.imported_rating_from_group,
      'rating', profile.rating,
      'ratings', profile.ratings,
      'ratingVotes', profile.rating_votes,
      'position', profile.position,
      'outfieldPosition', profile.outfield_position,
      'marketEnabled', profile.market_enabled,
      'marketZones', profile.market_zones,
      'marketZonesGeo', profile.market_zones_geo,
      'marketAvailability', profile.market_availability,
      'marketBio', profile.market_bio,
      'marketModalities', to_jsonb(profile.market_modalities),
      'marketOpenToGroup', profile.market_open_to_group,
      'marketOpenToGuest', profile.market_open_to_guest
    )
  );
end;
$$;

create or replace function public.upsert_pachanga_player_profile_from_player(
  target_group_id uuid,
  target_player_id text,
  player_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  global_profile_id uuid;
  owner_id uuid;
  safe_avatar_offset_x numeric;
  safe_avatar_offset_y numeric;
  safe_birth_date date;
  safe_imported_rating numeric;
  safe_imported_rating_at timestamptz;
  safe_market_modalities text[];
  safe_rating numeric;
  safe_stats jsonb;
begin
  if coalesce(player_payload ->> 'ownerUserId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  owner_id := (player_payload ->> 'ownerUserId')::uuid;

  safe_avatar_offset_x := case
    when coalesce(player_payload ->> 'avatarOffsetX', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetX')::numeric))
    else null
  end;
  safe_avatar_offset_y := case
    when coalesce(player_payload ->> 'avatarOffsetY', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetY')::numeric))
    else null
  end;
  safe_birth_date := case
    when coalesce(player_payload ->> 'birthDate', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (player_payload ->> 'birthDate')::date
    else null
  end;
  safe_imported_rating := case
    when coalesce(player_payload ->> 'importedRating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'importedRating')::numeric))
    else null
  end;
  safe_imported_rating_at := case
    when coalesce(player_payload ->> 'importedRatingAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' then (player_payload ->> 'importedRatingAt')::timestamptz
    else null
  end;
  safe_rating := case
    when coalesce(player_payload ->> 'rating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'rating')::numeric))
    when safe_imported_rating is not null then safe_imported_rating
    else 5
  end;

  select coalesce(array_agg(value), '{}'::text[])
  into safe_market_modalities
  from (
    select distinct value
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(player_payload -> 'marketModalities') = 'array' then player_payload -> 'marketModalities'
        else '[]'::jsonb
      end
    ) as modalities(value)
    where value in ('sala', 'futbol7', 'futbol11')
  ) as modality_values;

  safe_stats := jsonb_build_object(
    'goals', case
      when coalesce(player_payload ->> 'goals', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'goals')::integer)
      else 0
    end,
    'assists', case
      when coalesce(player_payload ->> 'assists', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'assists')::integer)
      else 0
    end,
    'appearances', case
      when coalesce(player_payload ->> 'appearances', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'appearances')::integer)
      else 0
    end,
    'wins', case
      when coalesce(player_payload ->> 'wins', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'wins')::integer)
      else 0
    end,
    'lateCancels', case
      when coalesce(player_payload ->> 'lateCancels', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'lateCancels')::integer)
      else 0
    end
  );

  insert into public.pachanga_player_profiles (
    user_id,
    source_group_id,
    source_player_id,
    display_name,
    phone,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    goalkeeper_only,
    injured,
    inactive,
    imported_rating,
    imported_rating_at,
    imported_rating_from_group,
    rating,
    ratings,
    rating_votes,
    position,
    outfield_position,
    market_enabled,
    market_zones,
    market_zones_geo,
    market_availability,
    market_bio,
    market_modalities,
    market_open_to_group,
    market_open_to_guest,
    stats
  )
  values (
    owner_id,
    target_group_id,
    nullif(trim(coalesce(target_player_id, player_payload ->> 'id', '')), ''),
    left(coalesce(nullif(trim(player_payload ->> 'name'), ''), 'Jugador'), 80),
    left(coalesce(player_payload ->> 'phone', ''), 40),
    nullif(player_payload ->> 'avatar', ''),
    safe_avatar_offset_x,
    safe_avatar_offset_y,
    safe_birth_date,
    coalesce((player_payload ->> 'goalkeeperOnly')::boolean, false),
    coalesce((player_payload ->> 'injured')::boolean, false),
    coalesce((player_payload ->> 'inactive')::boolean, false),
    safe_imported_rating,
    safe_imported_rating_at,
    nullif(left(trim(coalesce(player_payload ->> 'importedRatingFromGroup', '')), 120), ''),
    safe_rating,
    case when jsonb_typeof(player_payload -> 'ratings') = 'array' then player_payload -> 'ratings' else '[]'::jsonb end,
    case when jsonb_typeof(player_payload -> 'ratingVotes') = 'array' then player_payload -> 'ratingVotes' else '[]'::jsonb end,
    left(coalesce(nullif(trim(player_payload ->> 'position'), ''), 'Mediocentro / pivote'), 80),
    nullif(left(trim(coalesce(player_payload ->> 'outfieldPosition', '')), 80), ''),
    coalesce((player_payload ->> 'marketEnabled')::boolean, false),
    left(coalesce(player_payload ->> 'marketZones', ''), 320),
    case when jsonb_typeof(player_payload -> 'marketZonesGeo') = 'array' then player_payload -> 'marketZonesGeo' else '[]'::jsonb end,
    left(coalesce(player_payload ->> 'marketAvailability', ''), 240),
    left(coalesce(player_payload ->> 'marketBio', ''), 280),
    safe_market_modalities,
    coalesce((player_payload ->> 'marketOpenToGroup')::boolean, true),
    coalesce((player_payload ->> 'marketOpenToGuest')::boolean, true),
    safe_stats
  )
  on conflict (user_id) do update set
    source_group_id = excluded.source_group_id,
    source_player_id = excluded.source_player_id,
    display_name = excluded.display_name,
    phone = excluded.phone,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    goalkeeper_only = excluded.goalkeeper_only,
    injured = excluded.injured,
    inactive = excluded.inactive,
    imported_rating = coalesce(excluded.imported_rating, public.pachanga_player_profiles.imported_rating),
    imported_rating_at = coalesce(excluded.imported_rating_at, public.pachanga_player_profiles.imported_rating_at),
    imported_rating_from_group = coalesce(excluded.imported_rating_from_group, public.pachanga_player_profiles.imported_rating_from_group),
    rating = excluded.rating,
    ratings = excluded.ratings,
    rating_votes = excluded.rating_votes,
    position = excluded.position,
    outfield_position = excluded.outfield_position,
    market_enabled = excluded.market_enabled,
    market_zones = excluded.market_zones,
    market_zones_geo = excluded.market_zones_geo,
    market_availability = excluded.market_availability,
    market_bio = excluded.market_bio,
    market_modalities = excluded.market_modalities,
    market_open_to_group = excluded.market_open_to_group,
    market_open_to_guest = excluded.market_open_to_guest,
    stats = excluded.stats,
    profile_version = public.pachanga_player_profiles.profile_version + 1,
    updated_at = now()
  returning id into global_profile_id;

  return global_profile_id;
end;
$$;

create or replace function public.sync_pachanga_player_profile_to_groups(
  target_profile_id uuid,
  except_group_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  next_payload jsonb;
  next_players jsonb;
  profile_patch jsonb;
  profile_user_id uuid;
  saved_revision bigint;
begin
  select user_id into profile_user_id
  from public.pachanga_player_profiles
  where id = target_profile_id;

  if profile_user_id is null then
    return;
  end if;

  profile_patch := public.pachanga_player_profile_patch(target_profile_id);
  if profile_patch = '{}'::jsonb then
    return;
  end if;

  for current_group in
    select *
    from public.pachanga_groups groups
    where (except_group_id is null or groups.id <> except_group_id)
      and exists (
        select 1
        from jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) as players(value)
        where players.value ->> 'ownerUserId' = profile_user_id::text
      )
    order by groups.id
    for update skip locked
  loop
    select coalesce(jsonb_agg(
      case
        when value ->> 'ownerUserId' = profile_user_id::text then value || profile_patch
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    next_payload := current_group.payload || jsonb_build_object('players', next_players);

    update public.pachanga_groups
    set payload = next_payload
    where id = current_group.id
    returning payload_revision into saved_revision;

    perform public.sync_pachanga_group_read_model(current_group.id, next_payload, saved_revision);
  end loop;
end;
$$;

revoke all on function public.pachanga_player_profile_patch(uuid) from public;
revoke all on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from public;
revoke all on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from public;
revoke execute on function public.pachanga_player_profile_patch(uuid) from anon;
revoke execute on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from anon;
revoke execute on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from anon;
revoke execute on function public.pachanga_player_profile_patch(uuid) from authenticated;
revoke execute on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from authenticated;
revoke execute on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from authenticated;

do $$
declare
  group_record record;
  player_record jsonb;
  profile_id uuid;
begin
  for group_record in
    select id, payload
    from public.pachanga_groups
    order by updated_at asc
  loop
    for player_record in
      select value
      from jsonb_array_elements(coalesce(group_record.payload -> 'players', '[]'::jsonb)) as players(value)
    loop
      profile_id := public.upsert_pachanga_player_profile_from_player(
        group_record.id,
        player_record ->> 'id',
        player_record
      );
    end loop;
  end loop;

  for profile_id in
    select id
    from public.pachanga_player_profiles
  loop
    perform public.sync_pachanga_player_profile_to_groups(profile_id);
  end loop;

  update public.pachanga_market_profiles market_profiles
  set player_profile_id = player_profiles.id,
      updated_at = now()
  from public.pachanga_player_profiles player_profiles
  where market_profiles.user_id = player_profiles.user_id
    and market_profiles.player_profile_id is null;
end;
$$;
