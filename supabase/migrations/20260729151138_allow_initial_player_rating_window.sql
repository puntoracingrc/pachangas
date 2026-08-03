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

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then
        value || jsonb_build_object('ratingVotes', coalesce(value -> 'ratingVotes', '[]'::jsonb) || jsonb_build_array(next_vote))
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

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.append_pachanga_player_rating(uuid, text, jsonb) from public;
revoke execute on function public.append_pachanga_player_rating(uuid, text, jsonb) from anon;
grant execute on function public.append_pachanga_player_rating(uuid, text, jsonb) to authenticated;
