create or replace function public.patch_pachanga_match_player_paid(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean
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
  selected_match jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
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
    raise exception 'You can only mark your own payment';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing payments';
  end if;

  if not (
    coalesce((selected_match ->> 'lineupClosed')::boolean, false)
    or coalesce((selected_match ->> 'closed')::boolean, false)
    or selected_match ? 'scoreA'
  ) then
    raise exception 'Close the lineup before changing payments';
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'playerId' = target_player_id and value ->> 'status' = 'voy' then value || jsonb_build_object('paid', coalesce(next_paid, false))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_match_players
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from public;
revoke execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from anon;
grant execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) to authenticated;
