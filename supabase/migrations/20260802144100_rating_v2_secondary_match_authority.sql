-- Pachangas IQ rating system V2: remaining match and public-request intents.

create or replace function public.patch_pachanga_match_player_paid_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean,
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  perform public.patch_pachanga_match_player_paid(
    target_group_id, target_match_id, target_player_id, next_paid, operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'match_payment_v2', expected_revision, '{}'::jsonb, client_metadata
  );
end;
$$;

create or replace function public.patch_pachanga_match_scorers_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  next_scorers jsonb,
  target_team_a_ids text[],
  target_team_b_ids text[],
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  perform public.patch_pachanga_match_scorers(
    target_group_id,
    target_match_id,
    target_score_a,
    target_score_b,
    coalesce(next_scorers, '[]'::jsonb),
    coalesce(target_team_a_ids, array[]::text[]),
    coalesce(target_team_b_ids, array[]::text[]),
    operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'match_scorers_v2', expected_revision, '{}'::jsonb, client_metadata
  );
end;
$$;

create or replace function public.sync_pachanga_open_match_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  match_patch jsonb,
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
  replay jsonb;
  selected_match jsonb;
  selected_venue jsonb;
  safe_match_patch jsonb;
  confirmed_count integer;
  target_count integer;
  field_cost numeric;
  stable_level numeric;
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id
  limit 1;
  if selected_match is null then raise exception 'Match not found'; end if;
  select venues.value into selected_venue
  from jsonb_array_elements(coalesce(current_group.payload -> 'venues', '[]'::jsonb)) venues(value)
  where venues.value ->> 'id' = selected_match ->> 'venueId'
  limit 1;
  select count(*)::integer into confirmed_count
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) participants(value)
  where participants.value ->> 'status' = 'voy';
  target_count := greatest(1, coalesce((selected_match ->> 'targetPlayers')::integer, 1));
  field_cost := greatest(0, coalesce((selected_match ->> 'fieldCost')::numeric, 0));
  stable_level := public.pachanga_group_level_v2(target_group_id, clock_timestamp());
  safe_match_patch := coalesce(match_patch, '{}'::jsonb) || jsonb_build_object(
    'groupName', current_group.name,
    'title', selected_match ->> 'title',
    'date', selected_match ->> 'date',
    'modality', selected_match ->> 'kind',
    'fieldName', coalesce(selected_venue ->> 'name', selected_match ->> 'place'),
    'fieldCost', field_cost,
    'pricePerPlayer', field_cost / target_count,
    'targetPlayers', target_count,
    'confirmedCount', confirmed_count,
    'groupLevel', case when stable_level is null then null else stable_level / 10 end,
    'placeId', selected_venue ->> 'placeId',
    'lat', selected_venue -> 'lat',
    'lng', selected_venue -> 'lng',
    'zone', coalesce(selected_venue ->> 'city', selected_venue ->> 'address', selected_match ->> 'place')
  );

  perform public.sync_pachanga_open_match(
    target_group_id, target_match_id, safe_match_patch, operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'open_match_sync_v2', expected_revision, '{}'::jsonb, client_metadata
  );
end;
$$;

create or replace function public.review_pachanga_open_match_request_authoritative_v2(
  target_group_id uuid,
  target_request_id uuid,
  next_status text,
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
  replay jsonb;
  request_group_id uuid;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  select requests.source_group_id into request_group_id
  from public.pachanga_open_match_requests requests
  where requests.id = target_request_id;
  if request_group_id is distinct from target_group_id then raise exception 'Request does not belong to group'; end if;

  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;
  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  perform public.review_pachanga_open_match_request(target_request_id, next_status, operation_id);
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'open_match_request_review_v2', expected_revision, '{}'::jsonb, client_metadata
  );
end;
$$;

create or replace function public.request_pachanga_open_match_authoritative_v2(
  target_open_match_id uuid,
  operation_id uuid,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_open public.pachanga_open_matches%rowtype;
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  replay_actor uuid;
  legacy_result jsonb;
  confirmed_open public.pachanga_open_matches%rowtype;
  final_response jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_match_revision is null then
    raise exception 'Authentication, operation id and expected match revision required';
  end if;

  select * into selected_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = target_open_match_id
  for update;
  if not found then raise exception 'Open match not found'; end if;

  select receipts.response, receipts.user_id into replay, replay_actor
  from public.pachanga_operation_receipts receipts
  where receipts.group_id = selected_open.source_group_id
    and receipts.operation_id = operation_id;
  if replay is not null then
    if replay_actor is distinct from auth.uid() then raise exception 'Operation belongs to another actor'; end if;
    return replay;
  end if;
  if selected_open.source_payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_open.source_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;

  legacy_result := public.request_pachanga_open_match(target_open_match_id, operation_id);
  select * into confirmed_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = target_open_match_id;

  final_response := jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_match_revision,
    'confirmedRevision', confirmed_open.source_payload_revision,
    'confirmedAt', clock_timestamp(),
    'request', legacy_result,
    'openMatch', jsonb_build_object(
      'id', confirmed_open.id,
      'active', confirmed_open.active,
      'confirmedCount', confirmed_open.confirmed_count,
      'openSlots', confirmed_open.open_slots,
      'sourcePayloadRevision', confirmed_open.source_payload_revision
    )
  );

  update public.pachanga_operation_receipts receipts
  set response = final_response,
      expected_revision = expected_match_revision,
      result_revision = confirmed_open.source_payload_revision,
      client_metadata = case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end
  where receipts.group_id = selected_open.source_group_id
    and receipts.operation_id = operation_id
    and receipts.user_id = auth.uid();

  return final_response;
end;
$$;

revoke all on function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb) from public, anon;
revoke all on function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb) from public, anon;
revoke all on function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) from public, anon;
revoke all on function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb) from public, anon;
revoke all on function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb) from public, anon;

grant execute on function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb) to authenticated;
grant execute on function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb) to authenticated;
grant execute on function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) to authenticated;
grant execute on function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb) to authenticated;
grant execute on function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb) to authenticated;
