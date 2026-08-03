drop function if exists public.review_pachanga_open_match_request(uuid, text);
create or replace function public.review_pachanga_open_match_request(
  target_request_id uuid,
  next_status text,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  current_user_id uuid;
  existing_response jsonb;
  existing_entry jsonb;
  existing_player jsonb;
  next_confirmed_count integer;
  next_entry jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  next_open_slots integer;
  next_player jsonb;
  next_players jsonb;
  operation_response jsonb;
  accepted_player_id text;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  selected_match jsonb;
  selected_open public.pachanga_open_matches%rowtype;
  selected_request public.pachanga_open_match_requests%rowtype;
  global_profile_id uuid;
  target_players integer;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if next_status not in ('accepted', 'rejected') then
    raise exception 'Estado de solicitud no valido';
  end if;

  select * into selected_request
  from public.pachanga_open_match_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Solicitud no encontrada';
  end if;

  if not public.is_pachanga_group_admin(selected_request.source_group_id) then
    raise exception 'Solo los admins pueden revisar solicitudes';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = selected_request.source_group_id
  for update;

  if not found then
    raise exception 'Grupo no encontrado';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = selected_request.source_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;

  if selected_request.status = next_status and next_status in ('accepted', 'rejected') then
    operation_response := jsonb_build_object(
      'payload', current_payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_already_decided',
      operation_response
    );
  end if;

  if selected_request.status <> 'pending' then
    raise exception 'La solicitud ya estaba decidida';
  end if;

  if next_status = 'rejected' then
    update public.pachanga_open_match_requests
    set status = 'rejected',
        decided_by = current_user_id,
        decided_at = now(),
        updated_at = now()
    where id = selected_request.id;

    perform public.record_pachanga_group_event(
      selected_request.source_group_id,
      selected_request.source_match_id,
      'open_match_request_rejected',
      jsonb_build_object('requestId', selected_request.id),
      operation_key,
      true
    );

    operation_response := jsonb_build_object(
      'payload', current_payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );

    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_rejected',
      operation_response
    );
  end if;

  select * into selected_open
  from public.pachanga_open_matches
  where id = selected_request.open_match_id
  for update;

  if not found or selected_open.active = false then
    raise exception 'El partido abierto ya no esta disponible';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = selected_request.source_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Partido no encontrado';
  end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Guarda el partido antes de aceptar jugadores';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se pueden aceptar jugadores en partidos finalizados';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'La alineacion esta cerrada';
  end if;

  select value into existing_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'ownerUserId' = selected_request.requester_user_id::text
  limit 1;

  if existing_player is null then
    accepted_player_id := coalesce(
      nullif(selected_request.player_id, ''),
      'mk-' || substr(replace(selected_request.requester_user_id::text, '-', ''), 1, 8) || '-' || substr(replace(selected_request.id::text, '-', ''), 1, 6)
    );
    next_player := jsonb_strip_nulls(jsonb_build_object(
      'id', accepted_player_id,
      'name', left(coalesce(nullif(trim(selected_request.requester_name), ''), 'Jugador'), 80),
      'phone', '',
      'avatar', selected_request.avatar,
      'avatarOffsetX', selected_request.avatar_offset_x,
      'avatarOffsetY', selected_request.avatar_offset_y,
      'birthDate', selected_request.birth_date,
      'position', selected_request.position,
      'goalkeeperOnly', selected_request.goalkeeper_only,
      'rating', greatest(1::numeric, least(10::numeric, selected_request.media)),
      'importedRating', greatest(1::numeric, least(10::numeric, selected_request.media)),
      'importedRatingAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'importedRatingFromGroup', 'Mercado de fichajes',
      'goals', 0,
      'appearances', 0,
      'wins', 0,
      'injured', false,
      'inactive', false,
      'ownerUserId', selected_request.requester_user_id::text,
      'ratingVotes', '[]'::jsonb
    ));
    global_profile_id := public.upsert_pachanga_player_profile_from_player(
      selected_request.source_group_id,
      accepted_player_id,
      next_player
    );
    if global_profile_id is not null then
      next_player := next_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb) || jsonb_build_array(next_player);
  else
    accepted_player_id := existing_player ->> 'id';
    select id into global_profile_id
    from public.pachanga_player_profiles
    where user_id = selected_request.requester_user_id;

    if global_profile_id is null then
      global_profile_id := public.upsert_pachanga_player_profile_from_player(
        selected_request.source_group_id,
        accepted_player_id,
        existing_player || jsonb_build_object('ownerUserId', selected_request.requester_user_id::text)
      );
    end if;

    if global_profile_id is not null then
      select coalesce(jsonb_agg(
        case
          when value ->> 'id' = accepted_player_id then value || public.pachanga_player_profile_patch(global_profile_id)
          else value
        end
        order by ordinality
      ), '[]'::jsonb)
      into next_players
      from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
    else
      next_players := coalesce(current_payload -> 'players', '[]'::jsonb);
    end if;
  end if;

  select value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as value
  where value ->> 'playerId' = accepted_player_id
  limit 1;

  select count(*) into next_confirmed_count
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as entry(value)
  where value ->> 'status' = 'voy';

  target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, selected_open.target_players, 0));

  if (existing_entry is null or existing_entry ->> 'status' <> 'voy')
    and next_confirmed_count >= target_players
  then
    raise exception 'No quedan plazas en este partido';
  end if;

  next_entry := jsonb_build_object(
    'playerId', accepted_player_id,
    'status', 'voy',
    'paid', false,
    'joinedAt', to_char(selected_request.requested_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case
        when value ->> 'playerId' = accepted_player_id then value || next_entry
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  select count(*) into next_confirmed_count
  from jsonb_array_elements(next_match_players) as entry(value)
  where value ->> 'status' = 'voy';

  next_open_slots := greatest(target_players - next_confirmed_count, 0);
  next_match := selected_match || jsonb_build_object(
    'players', next_match_players,
    'publicOpen', next_open_slots > 0,
    'publicOpenSlots', greatest(next_open_slots, 1)
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = selected_request.source_match_id then next_match
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object(
    'players', next_players,
    'matches', next_matches
  );

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (selected_request.source_group_id, selected_request.requester_user_id, 'player', selected_request.requester_name)
  on conflict (group_id, user_id) do update set
    display_name = coalesce(nullif(public.pachanga_group_members.display_name, ''), excluded.display_name);

  update public.pachanga_open_match_requests
  set status = 'accepted',
      player_id = accepted_player_id,
      decided_by = current_user_id,
      decided_at = now(),
      updated_at = now()
  where id = selected_request.id;

  update public.pachanga_open_matches
  set confirmed_count = next_confirmed_count,
      open_slots = next_open_slots,
      active = next_open_slots > 0,
      updated_at = now()
  where id = selected_open.id;

  update public.pachanga_groups
  set payload = current_payload
  where id = selected_request.source_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(selected_request.source_group_id, next_match, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, selected_request.source_group_id);
  end if;
  perform public.record_pachanga_group_event(
    selected_request.source_group_id,
    selected_request.source_match_id,
    'open_match_request_accepted',
    jsonb_build_object(
      'requestId', selected_request.id,
      'playerId', accepted_player_id,
      'confirmedCount', next_confirmed_count,
      'openSlots', next_open_slots,
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );

  return public.remember_pachanga_operation(
    selected_request.source_group_id,
    operation_key,
    'open_match_request_accepted',
    operation_response
  );
end;
$$;

create or replace function public.append_pachanga_player_rating(
  target_group_id uuid,
  target_player_id text,
  vote_facets jsonb
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
  selected_member_name text;
  clean_facets jsonb;
  last_vote_match_count integer;
  player_appearances integer;
  next_vote jsonb;
  patched_player jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  global_profile_id uuid;
  selected_owner_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only members can rate players';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') = current_user_id::text then
    raise exception 'You cannot rate yourself';
  end if;

  if coalesce((selected_player ->> 'inactive')::boolean, false) then
    raise exception 'Inactive players cannot be rated';
  end if;

  player_appearances := greatest(0, coalesce((selected_player ->> 'appearances')::integer, 0));

  select max(greatest(0, coalesce((vote.value ->> 'matchCount')::integer, 0)))
  into last_vote_match_count
  from jsonb_array_elements(coalesce(selected_player -> 'ratingVotes', '[]'::jsonb)) as vote(value)
  where vote.value ->> 'voterId' = current_user_id::text;

  if player_appearances < coalesce(last_vote_match_count + 3, case when player_appearances = 0 then 0 else 3 end) then
    raise exception 'Rating window closed for this player';
  end if;

  select display_name into selected_member_name
  from public.pachanga_group_members
  where group_id = target_group_id
    and user_id = current_user_id;

  clean_facets := jsonb_build_object(
    'ritmo', greatest(1, least(10, coalesce((vote_facets ->> 'ritmo')::numeric, 5))),
    'tiro', greatest(1, least(10, coalesce((vote_facets ->> 'tiro')::numeric, 5))),
    'pase', greatest(1, least(10, coalesce((vote_facets ->> 'pase')::numeric, 5))),
    'regate', greatest(1, least(10, coalesce((vote_facets ->> 'regate')::numeric, 5))),
    'defensa', greatest(1, least(10, coalesce((vote_facets ->> 'defensa')::numeric, 5))),
    'fisico', greatest(1, least(10, coalesce((vote_facets ->> 'fisico')::numeric, 5)))
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', selected_member_name,
    'ratingRole',
      case
        when coalesce((selected_player ->> 'goalkeeperOnly')::boolean, false)
          or coalesce(selected_player ->> 'position', '') in ('Portero', 'Porteria')
        then 'goalkeeper'
        else 'field'
      end,
    'matchCount', player_appearances,
    'createdAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'facets', clean_facets
  );

  patched_player := selected_player || jsonb_build_object('ratingVotes', coalesce(selected_player -> 'ratingVotes', '[]'::jsonb) || jsonb_build_array(next_vote));

  if coalesce(selected_player ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    selected_owner_id := (selected_player ->> 'ownerUserId')::uuid;

    update public.pachanga_player_profiles
    set rating_votes = coalesce(rating_votes, '[]'::jsonb) || jsonb_build_array(next_vote),
        profile_version = profile_version + 1,
        updated_at = now()
    where user_id = selected_owner_id
    returning id into global_profile_id;

    if global_profile_id is null then
      global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, target_player_id, patched_player);
    end if;

    if global_profile_id is not null then
      patched_player := patched_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then patched_player
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

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
