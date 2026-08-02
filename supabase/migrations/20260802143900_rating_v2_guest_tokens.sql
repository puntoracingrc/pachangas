-- Pachangas IQ rating system V2: scoped, hashed, expiring guest links.

alter table public.pachanga_guest_rating_tokens
  add column if not exists expected_revision bigint,
  add column if not exists result_revision bigint,
  add column if not exists client_metadata jsonb not null default '{}'::jsonb,
  add column if not exists server_sequence bigint;

create or replace function public.issue_pachanga_guest_rating_token_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_guest_id uuid,
  operation_id uuid,
  expected_revision bigint,
  expires_in_minutes integer default 1440,
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
  plain_token text;
  hashed_token text;
  token_id uuid;
  token_expires_at timestamptz;
  redacted_response jsonb;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can issue guest links';
  end if;
  if operation_id is null or expected_revision is null then
    raise exception 'Operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay || jsonb_build_object('replayed', true); end if;

  select * into current_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  if not current_group.ratings_enabled then raise exception 'Ratings are disabled for this group'; end if;
  if not exists (
    select 1
    from public.pachanga_match_rating_participants participants
    join public.pachanga_match_rating_snapshots snapshots
      on snapshots.group_id = participants.group_id
      and snapshots.match_id = participants.match_id
      and snapshots.state = 'active'
    where participants.group_id = target_group_id
      and participants.match_id = target_match_id
      and participants.guest_identity_id = target_guest_id
      and participants.attendance_confirmed
      and not participants.was_reserve
  ) then raise exception 'Guest link is not available'; end if;

  plain_token := encode(extensions.gen_random_bytes(32), 'hex');
  hashed_token := encode(extensions.digest(plain_token, 'sha256'), 'hex');
  token_expires_at := clock_timestamp() + make_interval(mins => least(10080, greatest(5, coalesce(expires_in_minutes, 1440))));

  update public.pachanga_guest_rating_tokens
  set revoked_at = clock_timestamp(), revoked_by = auth.uid()
  where group_id = target_group_id
    and match_id = target_match_id
    and guest_identity_id = target_guest_id
    and consumed_at is null
    and revoked_at is null;

  insert into public.pachanga_guest_rating_tokens(
    token_hash, group_id, match_id, guest_identity_id, action, issued_by, expires_at
  ) values (
    hashed_token, target_group_id, target_match_id, target_guest_id,
    'rate_host_team', auth.uid(), token_expires_at
  ) returning id into token_id;

  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  perform public.record_pachanga_group_event(
    target_group_id, target_match_id, 'guest_rating_link_issued_v2',
    jsonb_build_object('tokenId', token_id, 'expiresAt', token_expires_at),
    operation_id, true
  );
  redacted_response := public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'guest_rating_link_issued_v2', expected_revision,
    jsonb_build_object('tokenId', token_id, 'expiresAt', token_expires_at, 'tokenIssued', true),
    client_metadata
  );
  return redacted_response || jsonb_build_object('token', plain_token, 'replayed', false);
end;
$$;

create or replace function public.revoke_pachanga_guest_rating_token_authoritative_v2(
  target_group_id uuid,
  target_token_id uuid,
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
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can revoke guest links';
  end if;
  if operation_id is null or expected_revision is null then
    raise exception 'Operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;
  select * into current_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;

  update public.pachanga_guest_rating_tokens
  set revoked_at = coalesce(revoked_at, clock_timestamp()),
      revoked_by = coalesce(revoked_by, auth.uid())
  where id = target_token_id and group_id = target_group_id;
  if not found then raise exception 'Guest link not found'; end if;
  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  perform public.record_pachanga_group_event(
    target_group_id, null, 'guest_rating_link_revoked_v2',
    jsonb_build_object('tokenId', target_token_id), operation_id, true
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'guest_rating_link_revoked_v2', expected_revision,
    jsonb_build_object('tokenId', target_token_id, 'revoked', true), client_metadata
  );
end;
$$;

create or replace function public.get_pachanga_guest_rating_token_context_v2(claim_token text)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  hashed_claim text;
  selected_token public.pachanga_guest_rating_tokens%rowtype;
  current_group public.pachanga_groups%rowtype;
  selected_match jsonb;
begin
  if coalesce(length(claim_token), 0) < 64 then
    raise exception 'Invalid or expired rating link';
  end if;
  hashed_claim := encode(extensions.digest(claim_token, 'sha256'), 'hex');
  select * into selected_token
  from public.pachanga_guest_rating_tokens tokens
  where tokens.token_hash = hashed_claim;
  if not found
    or selected_token.revoked_at is not null
    or selected_token.expires_at <= clock_timestamp()
    or selected_token.consumed_at is not null
  then raise exception 'Invalid or expired rating link'; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_token.group_id;
  if not found or not current_group.ratings_enabled then
    raise exception 'Invalid or expired rating link';
  end if;
  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = selected_token.match_id
  limit 1;
  return jsonb_build_object(
    'groupName', current_group.name,
    'matchTitle', coalesce(selected_match ->> 'title', 'Partido'),
    'matchDate', selected_match ->> 'date',
    'confirmedRevision', current_group.payload_revision,
    'expiresAt', selected_token.expires_at
  );
end;
$$;

drop function if exists public.record_pachanga_guest_team_rating_token_v2(text, text, uuid);
create or replace function public.record_pachanga_guest_team_rating_token_v2(
  claim_token text,
  comparison text,
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
  selected_token public.pachanga_guest_rating_tokens%rowtype;
  current_group public.pachanga_groups%rowtype;
  hashed_claim text;
  comparison_delta numeric;
  reference_level numeric;
  calculated_observation numeric;
  response_id uuid;
  official_result jsonb;
  calibration_result jsonb;
  public_response jsonb;
  confirmed_revision bigint;
  event_sequence bigint;
begin
  if operation_id is null or expected_revision is null or coalesce(length(claim_token), 0) < 64 then
    raise exception 'Invalid or expired rating link';
  end if;
  hashed_claim := encode(extensions.digest(claim_token, 'sha256'), 'hex');
  select * into selected_token
  from public.pachanga_guest_rating_tokens tokens
  where tokens.token_hash = hashed_claim;
  if not found
    or selected_token.revoked_at is not null
    or selected_token.expires_at <= clock_timestamp()
  then raise exception 'Invalid or expired rating link'; end if;
  if selected_token.consumed_at is not null then
    if selected_token.consumed_operation_id = operation_id then return selected_token.response; end if;
    raise exception 'Invalid or expired rating link';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_token.group_id
  for update;
  if not found or not current_group.ratings_enabled then
    raise exception 'Ratings are disabled for this group';
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  select * into selected_token
  from public.pachanga_guest_rating_tokens tokens
  where tokens.id = selected_token.id
  for update;
  if selected_token.consumed_at is not null then
    if selected_token.consumed_operation_id = operation_id then return selected_token.response; end if;
    raise exception 'Invalid or expired rating link';
  end if;
  if not exists (
    select 1
    from public.pachanga_match_rating_participants participants
    join public.pachanga_match_rating_snapshots snapshots
      on snapshots.group_id = participants.group_id
      and snapshots.match_id = participants.match_id
      and snapshots.state = 'active'
    where participants.group_id = selected_token.group_id
      and participants.match_id = selected_token.match_id
      and participants.guest_identity_id = selected_token.guest_identity_id
      and participants.attendance_confirmed
      and not participants.was_reserve
  ) then raise exception 'Invalid or expired rating link'; end if;

  comparison_delta := public.pachanga_rating_v2_comparison_delta(comparison);
  if comparison_delta is null then raise exception 'Invalid comparison'; end if;
  reference_level := public.pachanga_host_lineup_level_v2(selected_token.group_id, selected_token.match_id);
  if reference_level is null then raise exception 'Host lineup level unavailable'; end if;
  calculated_observation := public.pachanga_rating_v2_clamp(reference_level + comparison_delta);
  perform pg_advisory_xact_lock(
    hashtext(selected_token.group_id::text),
    hashtext(selected_token.match_id || ':host-team:' || selected_token.guest_identity_id::text)
  );
  if exists (
    select 1 from public.pachanga_global_rating_responses responses
    where responses.group_id = selected_token.group_id
      and responses.match_id = selected_token.match_id
      and responses.target_kind = 'host_team'
      and responses.actor_guest_identity_id = selected_token.guest_identity_id
  ) then raise exception 'Invalid or expired rating link'; end if;

  insert into public.pachanga_global_rating_responses(
    group_id, match_id, target_kind, actor_guest_identity_id, comparison,
    delta, reference_level_snapshot, observation, engine_version, operation_id
  ) values (
    selected_token.group_id, selected_token.match_id, 'host_team',
    selected_token.guest_identity_id, comparison, comparison_delta,
    reference_level, calculated_observation, 'pachangas-rating-v2-global-1', operation_id
  ) returning id into response_id;

  official_result := public.pachanga_refresh_global_official_v2(
    selected_token.group_id, selected_token.match_id, 'host_team', null, null, null
  );
  calibration_result := public.pachanga_recalculate_group_external_level_v2(
    selected_token.group_id, clock_timestamp()
  );
  select groups.payload_revision into confirmed_revision
  from public.pachanga_groups groups where groups.id = selected_token.group_id;

  insert into public.pachanga_group_events(
    group_id, match_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    selected_token.group_id, selected_token.match_id, operation_id, null,
    'guest_host_team_rating_v2', false,
    jsonb_build_object('officialEvidenceId', official_result -> 'officialEvidenceId')
  ) returning server_sequence into event_sequence;
  public_response := jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', confirmed_revision,
    'confirmedAt', clock_timestamp(),
    'serverSequence', event_sequence,
    'officialObservation', official_result -> 'officialObservation',
    'externallyCalibratedLevel', calibration_result -> 'calibratedLevel'
  );
  update public.pachanga_guest_rating_tokens
  set consumed_at = clock_timestamp(),
      consumed_operation_id = operation_id,
      response = public_response,
      expected_revision = record_pachanga_guest_team_rating_token_v2.expected_revision,
      result_revision = confirmed_revision,
      client_metadata = case
        when jsonb_typeof(record_pachanga_guest_team_rating_token_v2.client_metadata) = 'object'
          then record_pachanga_guest_team_rating_token_v2.client_metadata
        else '{}'::jsonb
      end,
      server_sequence = event_sequence
  where id = selected_token.id;
  return public_response;
end;
$$;

revoke all on function public.issue_pachanga_guest_rating_token_v2(uuid)
  from public, anon, authenticated;
revoke all on function public.record_pachanga_guest_team_rating_v2(uuid, text, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb)
  from public, anon;
revoke all on function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.get_pachanga_guest_rating_token_context_v2(text)
  from public;
revoke all on function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb)
  from public;

grant execute on function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb)
  to authenticated;
grant execute on function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.get_pachanga_guest_rating_token_context_v2(text)
  to anon, authenticated;
grant execute on function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb)
  to anon, authenticated;
