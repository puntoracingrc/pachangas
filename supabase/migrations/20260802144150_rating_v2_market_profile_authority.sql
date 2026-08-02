-- Pachangas IQ rating system V2: market cards are projections of canonical profiles.

create or replace function public.sync_pachanga_market_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  market_intent jsonb,
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
  current_group public.pachanga_groups%rowtype;
  selected_player jsonb;
  safe_patch jsonb;
  canonical_media numeric;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;

  select players.value into selected_player
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) players(value)
  where players.value ->> 'id' = target_player_id
  limit 1;
  if selected_player is null then raise exception 'Player not found'; end if;
  if coalesce(selected_player ->> 'ownerUserId', '') <> auth.uid()::text then
    raise exception 'Only the player owner can publish this profile';
  end if;

  canonical_media := case
    when coalesce(selected_player #>> '{ratingV2,currentOverall}', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then (selected_player #>> '{ratingV2,currentOverall}')::numeric / 10
    when coalesce(selected_player ->> 'rating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then (selected_player ->> 'rating')::numeric
    else 5
  end;
  safe_patch := (coalesce(market_intent, '{}'::jsonb) - array[
    'displayName', 'avatar', 'avatarOffsetX', 'avatarOffsetY', 'birthDate',
    'position', 'goalkeeperOnly', 'media', 'appearances', 'goals', 'wins', 'groupName'
  ]) || jsonb_build_object(
    'displayName', selected_player ->> 'name',
    'avatar', selected_player ->> 'avatar',
    'avatarOffsetX', selected_player -> 'avatarOffsetX',
    'avatarOffsetY', selected_player -> 'avatarOffsetY',
    'birthDate', selected_player ->> 'birthDate',
    'position', selected_player ->> 'position',
    'goalkeeperOnly', coalesce((selected_player ->> 'goalkeeperOnly')::boolean, false),
    'media', least(10::numeric, greatest(1::numeric, canonical_media)),
    'appearances', greatest(0, coalesce((selected_player ->> 'appearances')::integer, 0)),
    'goals', greatest(0, coalesce((selected_player ->> 'goals')::integer, 0)),
    'wins', greatest(0, coalesce((selected_player ->> 'wins')::integer, 0)),
    'groupName', current_group.name
  );

  perform public.sync_pachanga_market_profile(target_group_id, target_player_id, safe_patch);
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'market_profile_sync_v2', expected_revision, '{}'::jsonb, client_metadata
  );
end;
$$;

revoke all on function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  to authenticated;
