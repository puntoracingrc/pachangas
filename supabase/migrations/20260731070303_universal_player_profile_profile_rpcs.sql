create or replace function public.upsert_pachanga_own_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  owned_player jsonb;
  selected_player_id text;
  next_player jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  global_profile_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can create a player profile';
  end if;

  selected_player_id := nullif(trim(coalesce(target_player_id, '')), '');
  if selected_player_id is null then
    raise exception 'Player id required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into owned_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'ownerUserId' = current_user_id::text
  limit 1;

  if owned_player is not null then
    selected_player := owned_player;
    selected_player_id := owned_player ->> 'id';
  else
    select value into selected_player
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
    where value ->> 'id' = selected_player_id
    limit 1;

    if selected_player is not null
      and coalesce(selected_player ->> 'ownerUserId', '') <> ''
      and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text
    then
      raise exception 'This player profile already belongs to another user';
    end if;
  end if;

  next_player := coalesce(
    selected_player,
    jsonb_build_object(
      'id', selected_player_id,
      'name', 'Jugador',
      'phone', '',
      'goalkeeperOnly', false,
      'injured', false,
      'rating', 5,
      'ratings', '[]'::jsonb,
      'ratingVotes', '[]'::jsonb,
      'position', 'Mediocentro / pivote',
      'outfieldPosition', 'Mediocentro / pivote',
      'goals', 0,
      'assists', 0,
      'appearances', 0,
      'wins', 0,
      'lateCancels', 0
    )
  ) || jsonb_build_object(
    'id', selected_player_id,
    'ownerUserId', current_user_id::text
  );

  if player_patch ? 'name' then
    next_player := next_player || jsonb_build_object('name', coalesce(nullif(trim(player_patch ->> 'name'), ''), 'Jugador'));
  end if;

  if player_patch ? 'phone' then
    next_player := next_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'birthDate' then
    next_player := next_player || jsonb_build_object('birthDate', nullif(player_patch ->> 'birthDate', ''));
  end if;

  if player_patch ? 'avatar' then
    next_player := next_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'avatarOffsetX' then
    next_player := next_player || jsonb_build_object('avatarOffsetX', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetX', '')::numeric, 50))));
  end if;

  if player_patch ? 'avatarOffsetY' then
    next_player := next_player || jsonb_build_object('avatarOffsetY', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetY', '')::numeric, 0))));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    next_player := next_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    next_player := next_player || jsonb_build_object('injured', coalesce((player_patch ->> 'injured')::boolean, false));
  end if;

  if player_patch ? 'position' then
    next_player := next_player || jsonb_build_object('position', coalesce(nullif(player_patch ->> 'position', ''), 'Mediocentro / pivote'));
  end if;

  if player_patch ? 'outfieldPosition' then
    next_player := next_player || jsonb_build_object('outfieldPosition', coalesce(nullif(player_patch ->> 'outfieldPosition', ''), 'Mediocentro / pivote'));
  end if;

  if player_patch ? 'goals' then
    next_player := next_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if player_patch ? 'importedRating' then
    next_player := next_player || jsonb_build_object(
      'importedRating', greatest(1, least(10, coalesce((player_patch ->> 'importedRating')::numeric, 5))),
      'rating', greatest(1, least(10, coalesce((player_patch ->> 'importedRating')::numeric, 5)))
    );
  end if;

  if player_patch ? 'importedRatingFromGroup' then
    next_player := next_player || jsonb_build_object('importedRatingFromGroup', nullif(trim(player_patch ->> 'importedRatingFromGroup'), ''));
  end if;

  if player_patch ? 'importedRatingAt' then
    next_player := next_player || jsonb_build_object('importedRatingAt', nullif(player_patch ->> 'importedRatingAt', ''));
  end if;

  if player_patch ? 'marketEnabled' then
    next_player := next_player || jsonb_build_object('marketEnabled', coalesce((player_patch ->> 'marketEnabled')::boolean, false));
  end if;

  if player_patch ? 'marketZones' then
    next_player := next_player || jsonb_build_object('marketZones', left(coalesce(player_patch ->> 'marketZones', ''), 320));
  end if;

  if player_patch ? 'marketAvailability' then
    next_player := next_player || jsonb_build_object('marketAvailability', left(coalesce(player_patch ->> 'marketAvailability', ''), 240));
  end if;

  if player_patch ? 'marketBio' then
    next_player := next_player || jsonb_build_object('marketBio', left(coalesce(player_patch ->> 'marketBio', ''), 280));
  end if;

  if player_patch ? 'marketOpenToGroup' then
    next_player := next_player || jsonb_build_object('marketOpenToGroup', coalesce((player_patch ->> 'marketOpenToGroup')::boolean, true));
  end if;

  if player_patch ? 'marketOpenToGuest' then
    next_player := next_player || jsonb_build_object('marketOpenToGuest', coalesce((player_patch ->> 'marketOpenToGuest')::boolean, true));
  end if;

  if player_patch ? 'marketModalities' then
    next_player := next_player || jsonb_build_object(
      'marketModalities',
      case
        when jsonb_typeof(player_patch -> 'marketModalities') = 'array' then
          coalesce((
            select jsonb_agg(value)
            from jsonb_array_elements_text(player_patch -> 'marketModalities') as modalities(value)
            where value in ('sala', 'futbol7', 'futbol11')
          ), '[]'::jsonb)
        else '[]'::jsonb
      end
    );
  end if;

  global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, selected_player_id, next_player);
  if global_profile_id is not null then
    next_player := next_player || public.pachanga_player_profile_patch(global_profile_id);
  end if;

  if selected_player is null then
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb) || jsonb_build_array(next_player);
  else
    select coalesce(jsonb_agg(
      case when value ->> 'id' = selected_player_id then next_player else value end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  patched_player jsonb;
  next_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  global_profile_id uuid;
  is_admin boolean;
  patch_injured boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only edit your own player profile';
  end if;

  patched_player := selected_player;

  if player_patch ? 'name' then
    patched_player := patched_player || jsonb_build_object('name', nullif(trim(player_patch ->> 'name'), ''));
  end if;

  if player_patch ? 'phone' then
    patched_player := patched_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'birthDate' then
    patched_player := patched_player || jsonb_build_object('birthDate', nullif(player_patch ->> 'birthDate', ''));
  end if;

  if player_patch ? 'avatar' then
    patched_player := patched_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'avatarOffsetX' then
    patched_player := patched_player || jsonb_build_object('avatarOffsetX', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetX', '')::numeric, 50))));
  end if;

  if player_patch ? 'avatarOffsetY' then
    patched_player := patched_player || jsonb_build_object('avatarOffsetY', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetY', '')::numeric, 0))));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    patched_player := patched_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    patch_injured := coalesce((player_patch ->> 'injured')::boolean, false);
    patched_player := patched_player || jsonb_build_object('injured', patch_injured);
  end if;

  if player_patch ? 'position' then
    patched_player := patched_player || jsonb_build_object('position', nullif(player_patch ->> 'position', ''));
  end if;

  if player_patch ? 'outfieldPosition' then
    patched_player := patched_player || jsonb_build_object('outfieldPosition', nullif(player_patch ->> 'outfieldPosition', ''));
  end if;

  if player_patch ? 'goals' then
    patched_player := patched_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if player_patch ? 'marketEnabled' then
    patched_player := patched_player || jsonb_build_object('marketEnabled', coalesce((player_patch ->> 'marketEnabled')::boolean, false));
  end if;

  if player_patch ? 'marketZones' then
    patched_player := patched_player || jsonb_build_object('marketZones', left(coalesce(player_patch ->> 'marketZones', ''), 320));
  end if;

  if player_patch ? 'marketAvailability' then
    patched_player := patched_player || jsonb_build_object('marketAvailability', left(coalesce(player_patch ->> 'marketAvailability', ''), 240));
  end if;

  if player_patch ? 'marketBio' then
    patched_player := patched_player || jsonb_build_object('marketBio', left(coalesce(player_patch ->> 'marketBio', ''), 280));
  end if;

  if player_patch ? 'marketOpenToGroup' then
    patched_player := patched_player || jsonb_build_object('marketOpenToGroup', coalesce((player_patch ->> 'marketOpenToGroup')::boolean, true));
  end if;

  if player_patch ? 'marketOpenToGuest' then
    patched_player := patched_player || jsonb_build_object('marketOpenToGuest', coalesce((player_patch ->> 'marketOpenToGuest')::boolean, true));
  end if;

  if player_patch ? 'marketModalities' then
    patched_player := patched_player || jsonb_build_object(
      'marketModalities',
      case
        when jsonb_typeof(player_patch -> 'marketModalities') = 'array' then
          coalesce((
            select jsonb_agg(value)
            from jsonb_array_elements_text(player_patch -> 'marketModalities') as modalities(value)
            where value in ('sala', 'futbol7', 'futbol11')
          ), '[]'::jsonb)
        else '[]'::jsonb
      end
    );
  end if;

  if is_admin and player_patch ? 'rating' then
    patched_player := patched_player || jsonb_build_object('rating', greatest(1, least(10, coalesce((player_patch ->> 'rating')::numeric, 5))));
  end if;

  if is_admin and player_patch ? 'inactive' then
    patched_player := patched_player || jsonb_build_object('inactive', coalesce((player_patch ->> 'inactive')::boolean, false));
  end if;

  if coalesce(patched_player ->> 'ownerUserId', '') = current_user_id::text then
    global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, target_player_id, patched_player);
    if global_profile_id is not null then
      patched_player := patched_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_player_id then patched_player else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_matches := current_payload -> 'matches';

  if patch_injured then
    select coalesce(jsonb_agg(
      case
        when not (coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA') then
          value || jsonb_build_object(
            'players',
            coalesce((
              select jsonb_agg(
                case
                  when entry ->> 'playerId' = target_player_id then
                    jsonb_build_object('playerId', target_player_id, 'status', 'no', 'paid', false)
                  else entry
                end
                order by entry_ordinality
              )
              from jsonb_array_elements(coalesce(value -> 'players', '[]'::jsonb)) with ordinality as match_entries(entry, entry_ordinality)
            ), '[]'::jsonb)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players, 'matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

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
  sanitized_zones_geo jsonb;
  sanitized_modalities text[];
  saved_profile public.pachanga_market_profiles%rowtype;
  saved_payload jsonb;
  saved_revision bigint;
  global_profile_id uuid;
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
    global_profile_id := public.upsert_pachanga_player_profile_from_player(
      target_group_id,
      target_player_id,
      selected_player || jsonb_build_object('marketEnabled', false)
    );

    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then value || jsonb_build_object('marketEnabled', false) || public.pachanga_player_profile_patch(global_profile_id)
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    update public.pachanga_groups
    set payload = current_group.payload || jsonb_build_object('players', next_players)
    where id = target_group_id
    returning payload, payload_revision
    into saved_payload, saved_revision;

    update public.pachanga_market_profiles
    set active = false,
        player_profile_id = coalesce(global_profile_id, player_profile_id),
        updated_at = now()
    where user_id = current_user_id
    returning * into saved_profile;

    perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
    if global_profile_id is not null then
      perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
    end if;

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

  select coalesce(jsonb_agg(zone_value order by zone_order), '[]'::jsonb)
  into sanitized_zones_geo
  from (
    select *
    from (
      select distinct on (zone_key)
        zone_key,
        ordinality as zone_order,
        jsonb_strip_nulls(jsonb_build_object(
          'placeId', left(coalesce(nullif(trim(value ->> 'placeId'), ''), zone_key), 160),
          'name', left(coalesce(nullif(trim(value ->> 'name'), ''), nullif(trim(value ->> 'city'), ''), 'Zona'), 80),
          'city', nullif(left(trim(coalesce(value ->> 'city', '')), 80), ''),
          'province', nullif(left(trim(coalesce(value ->> 'province', '')), 80), ''),
          'country', nullif(left(trim(coalesce(value ->> 'country', '')), 80), ''),
          'address', nullif(left(trim(coalesce(value ->> 'address', '')), 200), ''),
          'lat', case
            when coalesce(value ->> 'lat', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-90::numeric, least(90::numeric, (value ->> 'lat')::numeric))
            else null
          end,
          'lng', case
            when coalesce(value ->> 'lng', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-180::numeric, least(180::numeric, (value ->> 'lng')::numeric))
            else null
          end,
          'radiusKm', case
            when coalesce(value ->> 'radiusKm', '') ~ '^[0-9]+$' and (value ->> 'radiusKm')::integer in (0, 5, 10, 20, 30, 50) then (value ->> 'radiusKm')::integer
            else 0
          end
        )) as zone_value
      from jsonb_array_elements(
        case
          when jsonb_typeof(market_patch -> 'zonesGeo') = 'array' then market_patch -> 'zonesGeo'
          else '[]'::jsonb
        end
      ) with ordinality as zones(value, ordinality)
      cross join lateral (
        select coalesce(
          nullif(trim(value ->> 'placeId'), ''),
          lower(regexp_replace(coalesce(nullif(trim(value ->> 'name'), ''), nullif(trim(value ->> 'city'), ''), ''), '[[:space:]]+', ' ', 'g'))
        ) as zone_key
      ) as zone_keys
      where jsonb_typeof(value) = 'object'
        and zone_key <> ''
      order by zone_key, ordinality
    ) as deduped_zones
    order by zone_order
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
    'marketZonesGeo', sanitized_zones_geo,
    'marketAvailability', left(coalesce(market_patch ->> 'availabilityText', ''), 240),
    'marketBio', left(coalesce(market_patch ->> 'bio', ''), 280),
    'marketOpenToGroup', coalesce((market_patch ->> 'openToGroup')::boolean, true),
    'marketOpenToGuest', coalesce((market_patch ->> 'openToGuest')::boolean, true),
    'marketModalities', to_jsonb(sanitized_modalities)
  );

  global_profile_id := public.upsert_pachanga_player_profile_from_player(
    target_group_id,
    target_player_id,
    selected_player || market_player_patch
  );
  if global_profile_id is not null then
    market_player_patch := market_player_patch || public.pachanga_player_profile_patch(global_profile_id);
  end if;

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
  where id = target_group_id
  returning payload, payload_revision
  into saved_payload, saved_revision;

  insert into public.pachanga_market_profiles (
    user_id,
    player_profile_id,
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
    zones_geo,
    availability_text,
    modalities,
    open_to_guest,
    open_to_group,
    bio,
    active
  )
  values (
    current_user_id,
    global_profile_id,
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
    sanitized_zones_geo,
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
    zones_geo = excluded.zones_geo,
    availability_text = excluded.availability_text,
    modalities = excluded.modalities,
    open_to_guest = excluded.open_to_guest,
    open_to_group = excluded.open_to_group,
    bio = excluded.bio,
    active = true,
    player_profile_id = excluded.player_profile_id,
    updated_at = now()
  returning * into saved_profile;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('active', saved_profile.active, 'id', saved_profile.id);
end;
$$;
