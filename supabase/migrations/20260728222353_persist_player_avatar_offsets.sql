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

  if is_admin and player_patch ? 'rating' then
    patched_player := patched_player || jsonb_build_object('rating', greatest(1, least(10, coalesce((player_patch ->> 'rating')::numeric, 5))));
  end if;

  if is_admin and player_patch ? 'inactive' then
    patched_player := patched_player || jsonb_build_object('inactive', coalesce((player_patch ->> 'inactive')::boolean, false));
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

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.patch_pachanga_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) to authenticated;
