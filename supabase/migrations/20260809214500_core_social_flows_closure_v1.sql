-- Pachangas IQ core social flows closure V1.
-- Membership lifecycle, challenge expiry and public-match lifecycle only.

create or replace function private.pachanga_membership_departure_payload_v1(
  source_payload jsonb,
  target_user_id uuid,
  server_now timestamptz
)
returns jsonb
language plpgsql
set search_path = pg_catalog
as $$
declare
  player_ids text[] := array[]::text[];
  next_players jsonb := '[]'::jsonb;
  next_matches jsonb := '[]'::jsonb;
  match_row record;
  match_value jsonb;
  next_entries jsonb;
  next_team_a jsonb;
  next_team_b jsonb;
  next_scorers jsonb;
  match_is_future boolean;
  match_is_finalized boolean;
begin
  select coalesce(array_agg(players.value ->> 'id'), array[]::text[])
  into player_ids
  from jsonb_array_elements(coalesce(source_payload -> 'players', '[]'::jsonb)) players(value)
  where players.value ->> 'ownerUserId' = target_user_id::text
    and nullif(players.value ->> 'id', '') is not null;

  select coalesce(jsonb_agg(
    case
      when players.value ->> 'ownerUserId' = target_user_id::text
        then players.value || jsonb_build_object('inactive', true, 'injured', false)
      else players.value
    end
    order by players.ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(source_payload -> 'players', '[]'::jsonb))
    with ordinality as players(value, ordinality);

  for match_row in
    select matches.value, matches.ordinality
    from jsonb_array_elements(coalesce(source_payload -> 'matches', '[]'::jsonb))
      with ordinality as matches(value, ordinality)
    order by matches.ordinality
  loop
    match_value := match_row.value;
    match_is_finalized := coalesce((match_value ->> 'closed')::boolean, false) or match_value ? 'scoreA';
    match_is_future := case
      when coalesce(match_value ->> 'date', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
        then (match_value ->> 'date')::timestamptz > server_now
      else false
    end;

    if cardinality(player_ids) > 0 and match_is_future and not match_is_finalized then
      select coalesce(jsonb_agg(
        case
          when entries.value ->> 'playerId' = any(player_ids)
            then (entries.value - 'joinedAt') || jsonb_build_object('status', 'no', 'paid', false)
          else entries.value
        end
        order by entries.ordinality
      ), '[]'::jsonb)
      into next_entries
      from jsonb_array_elements(coalesce(match_value -> 'players', '[]'::jsonb))
        with ordinality as entries(value, ordinality);

      select coalesce(jsonb_agg(to_jsonb(team_ids.value) order by team_ids.ordinality), '[]'::jsonb)
      into next_team_a
      from jsonb_array_elements_text(coalesce(match_value -> 'teamA', '[]'::jsonb))
        with ordinality as team_ids(value, ordinality)
      where not team_ids.value = any(player_ids);

      select coalesce(jsonb_agg(to_jsonb(team_ids.value) order by team_ids.ordinality), '[]'::jsonb)
      into next_team_b
      from jsonb_array_elements_text(coalesce(match_value -> 'teamB', '[]'::jsonb))
        with ordinality as team_ids(value, ordinality)
      where not team_ids.value = any(player_ids);

      select coalesce(jsonb_agg(scorers.value order by scorers.ordinality), '[]'::jsonb)
      into next_scorers
      from jsonb_array_elements(coalesce(match_value -> 'scorers', '[]'::jsonb))
        with ordinality as scorers(value, ordinality)
      where not (scorers.value ->> 'playerId') = any(player_ids);

      match_value := match_value || jsonb_build_object(
        'players', next_entries,
        'teamA', next_team_a,
        'teamB', next_team_b,
        'scorers', next_scorers
      );
      if match_value ->> 'payerId' = any(player_ids) then
        match_value := match_value - 'payerId';
      end if;
    end if;

    next_matches := next_matches || jsonb_build_array(match_value);
  end loop;

  return coalesce(source_payload, '{}'::jsonb) || jsonb_build_object(
    'players', next_players,
    'matches', next_matches
  );
end;
$$;

revoke all on function private.pachanga_membership_departure_payload_v1(jsonb, uuid, timestamptz)
  from public, anon, authenticated;

create or replace function private.pachanga_store_membership_response_v1(
  target_group_id uuid,
  target_user_id uuid,
  operation_id uuid,
  operation_type text,
  expected_revision bigint,
  result_revision bigint,
  membership_status text,
  event_sequence bigint,
  client_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  response jsonb;
  stored jsonb;
begin
  response := jsonb_build_object(
    'groupId', target_group_id,
    'targetUserId', target_user_id,
    'membershipStatus', membership_status,
    'operationId', operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', result_revision,
    'confirmedAt', clock_timestamp(),
    'serverSequence', event_sequence
  );

  insert into public.pachanga_operation_receipts(
    group_id, operation_id, operation_type, user_id, response,
    expected_revision, result_revision, client_metadata, server_sequence
  ) values (
    target_group_id, operation_id, left(operation_type, 120), auth.uid(), response,
    expected_revision, result_revision,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end,
    event_sequence
  ) on conflict on constraint pachanga_operation_receipts_group_id_operation_id_key do nothing;

  select receipts.response into stored
  from public.pachanga_operation_receipts receipts
  where receipts.group_id = target_group_id
    and receipts.operation_id = $3
    and receipts.user_id = auth.uid();
  if stored is null then raise exception 'Operation belongs to another actor'; end if;
  return stored;
end;
$$;

revoke all on function private.pachanga_store_membership_response_v1(uuid, uuid, uuid, text, bigint, bigint, text, bigint, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_depart_group_member_v1(
  target_group_id uuid,
  target_user_id uuid,
  operation_id uuid,
  expected_revision bigint,
  departure_kind text,
  client_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_member public.pachanga_group_members%rowtype;
  next_payload jsonb;
  saved_revision bigint;
  event_sequence bigint;
  changed_match jsonb;
begin
  select * into selected_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;

  select * into selected_member
  from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = target_user_id
  for update;

  if not found then
    return private.pachanga_store_membership_response_v1(
      target_group_id, target_user_id, operation_id, departure_kind || '_noop',
      expected_revision, selected_group.payload_revision, 'absent', null, client_metadata
    );
  end if;
  if selected_member.role = 'owner' or selected_group.owner_id = target_user_id then
    raise exception 'Transfer ownership before the owner leaves the group';
  end if;
  if selected_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  next_payload := private.pachanga_membership_departure_payload_v1(
    selected_group.payload, target_user_id, clock_timestamp()
  );
  update public.pachanga_groups groups
  set payload = next_payload
  where groups.id = target_group_id
  returning groups.payload_revision into saved_revision;

  perform set_config(
    'pachangas.membership_change_kind',
    case when departure_kind = 'group_member_left' then 'left' else 'removed' end,
    true
  );
  delete from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = target_user_id;

  for changed_match in
    select matches.value
    from jsonb_array_elements(coalesce(next_payload -> 'matches', '[]'::jsonb)) matches(value)
    where not (coalesce((matches.value ->> 'closed')::boolean, false) or matches.value ? 'scoreA')
      and coalesce(matches.value ->> 'date', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
      and (matches.value ->> 'date')::timestamptz > clock_timestamp()
  loop
    perform public.sync_pachanga_match_read_model(target_group_id, changed_match, saved_revision);
  end loop;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    departure_kind,
    jsonb_build_object(
      'targetUserId', target_user_id,
      'previousRole', selected_member.role,
      'payloadRevision', saved_revision
    ),
    operation_id,
    departure_kind = 'group_member_removed'
  );
  select events.server_sequence into event_sequence
  from public.pachanga_group_events events
  where events.group_id = target_group_id and events.operation_id = $3
  order by events.server_sequence desc, events.id desc
  limit 1;

  return private.pachanga_store_membership_response_v1(
    target_group_id, target_user_id, operation_id, departure_kind,
    expected_revision, saved_revision,
    case when departure_kind = 'group_member_left' then 'left' else 'removed' end,
    event_sequence, client_metadata
  );
end;
$$;

revoke all on function private.pachanga_depart_group_member_v1(uuid, uuid, uuid, bigint, text, jsonb)
  from public, anon, authenticated;

create or replace function public.leave_pachanga_group_authoritative_v1(
  target_group_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user() then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('group-membership:' || target_group_id::text, 0));
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  return private.pachanga_depart_group_member_v1(
    target_group_id, auth.uid(), operation_id, expected_revision,
    'group_member_left', client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.leave_pachanga_group_authoritative_v1(uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.leave_pachanga_group_authoritative_v1(uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.remove_pachanga_group_member_authoritative_v1(
  target_group_id uuid,
  target_user_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_role text;
  target_role text;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or target_user_id is null or not public.is_registered_pachanga_user() then
    raise exception 'Authentication, target, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('group-membership:' || target_group_id::text, 0));
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select members.role into actor_role
  from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = auth.uid();
  if actor_role is null or actor_role not in ('owner', 'admin') then
    raise exception 'Only group admins can remove members';
  end if;
  if target_user_id = auth.uid() then raise exception 'Use the leave-group operation for your own membership'; end if;

  select members.role into target_role
  from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = target_user_id;
  if target_role = 'owner' then raise exception 'The owner cannot be removed'; end if;
  if actor_role = 'admin' and target_role = 'admin' then raise exception 'Only the owner can remove another admin'; end if;

  return private.pachanga_depart_group_member_v1(
    target_group_id, target_user_id, operation_id, expected_revision,
    'group_member_removed', client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.remove_pachanga_group_member_authoritative_v1(uuid, uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.remove_pachanga_group_member_authoritative_v1(uuid, uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.transfer_pachanga_group_ownership_authoritative_v1(
  target_group_id uuid,
  target_user_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  selected_group public.pachanga_groups%rowtype;
  target_role text;
  saved_revision bigint;
  event_sequence bigint;
  replay jsonb;
begin
  if auth.uid() is null or target_user_id is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user() then
    raise exception 'Authentication, target, operation id and expected revision required';
  end if;
  if target_user_id = auth.uid() then raise exception 'Choose another current member as owner'; end if;
  perform pg_advisory_xact_lock(hashtextextended('group-membership:' || target_group_id::text, 0));
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into selected_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if selected_group.owner_id <> auth.uid() then raise exception 'Only the current owner can transfer ownership'; end if;
  if selected_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select members.role into target_role
  from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = target_user_id
  for update;
  if not found then raise exception 'The new owner must already belong to the group'; end if;

  update public.pachanga_groups groups
  set owner_id = target_user_id
  where groups.id = target_group_id
  returning groups.payload_revision into saved_revision;
  update public.pachanga_group_members members
  set role = case when members.user_id = target_user_id then 'owner' else 'admin' end
  where members.group_id = target_group_id
    and members.user_id in (auth.uid(), target_user_id);

  perform public.record_pachanga_group_event(
    target_group_id, null, 'group_owner_transferred',
    jsonb_build_object(
      'previousOwnerUserId', auth.uid(),
      'nextOwnerUserId', target_user_id,
      'previousTargetRole', target_role,
      'payloadRevision', saved_revision
    ),
    operation_id, true
  );
  select events.server_sequence into event_sequence
  from public.pachanga_group_events events
  where events.group_id = target_group_id and events.operation_id = $3
  order by events.server_sequence desc, events.id desc limit 1;

  return private.pachanga_store_membership_response_v1(
    target_group_id, target_user_id, operation_id, 'group_owner_transferred',
    expected_revision, saved_revision, 'owner', event_sequence, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.transfer_pachanga_group_ownership_authoritative_v1(uuid, uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.transfer_pachanga_group_ownership_authoritative_v1(uuid, uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function private.pachanga_notify_group_membership_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group_id uuid := coalesce(new.group_id, old.group_id);
  selected_user_id uuid := coalesce(new.user_id, old.user_id);
  selected_name text := coalesce(nullif(trim(coalesce(new.display_name, old.display_name)), ''), 'Un jugador');
  selected_created_at timestamptz := coalesce(new.created_at, old.created_at, clock_timestamp());
  change_kind text := coalesce(nullif(current_setting('pachangas.membership_change_kind', true), ''), 'removed');
  recipient record;
  notification_kind text;
begin
  notification_kind := case
    when tg_op = 'INSERT' then 'group_member_joined'
    when change_kind = 'left' then 'group_member_left'
    else 'group_member_removed'
  end;

  for recipient in
    select recipients.user_id
    from private.pachanga_group_notification_recipients_v1(selected_group_id, false) recipients
    where recipients.user_id <> selected_user_id
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      notification_kind,
      case
        when tg_op = 'INSERT' then 'Nuevo miembro en el grupo'
        when change_kind = 'left' then 'Un jugador ha dejado el equipo'
        else 'Cambio en el grupo'
      end,
      selected_name || case
        when tg_op = 'INSERT' then ' se ha unido al grupo.'
        when change_kind = 'left' then ' ha dejado el equipo.'
        else ' ya no forma parte del grupo.'
      end,
      '/?mobile=equipo',
      jsonb_build_object('groupId', selected_group_id, 'memberUserId', selected_user_id),
      'group-membership:' || selected_group_id::text || ':' || selected_user_id::text || ':'
        || notification_kind || ':' || floor(extract(epoch from selected_created_at) * 1000000)::bigint::text
        || ':' || recipient.user_id::text
    );
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.pachanga_notify_group_membership_v1()
  from public, anon, authenticated;

create or replace function public.join_pachanga_team(token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_group_id uuid;
  current_user_id uuid := auth.uid();
  current_group public.pachanga_groups%rowtype;
  next_players jsonb;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'Registered user required'; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.invite_token = token
  for update;
  if not found then raise exception 'Invalid invite token'; end if;
  target_group_id := current_group.id;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (target_group_id, current_user_id, 'player', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update
    set display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  select coalesce(jsonb_agg(
    case
      when players.value ->> 'ownerUserId' = current_user_id::text
        then players.value || jsonb_build_object('inactive', false)
      else players.value
    end
    order by players.ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb))
    with ordinality as players(value, ordinality);

  if next_players is distinct from coalesce(current_group.payload -> 'players', '[]'::jsonb) then
    update public.pachanga_groups groups
    set payload = groups.payload || jsonb_build_object('players', next_players)
    where groups.id = target_group_id;
  end if;

  return target_group_id;
end;
$$;

revoke all on function public.join_pachanga_team(uuid, text) from public, anon;
grant execute on function public.join_pachanga_team(uuid, text) to authenticated;

alter table public.pachanga_admin_invites
  add column if not exists revision bigint not null default 1,
  add column if not exists server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  add column if not exists updated_at timestamptz not null default clock_timestamp();

create unique index if not exists pachanga_admin_invites_server_sequence_idx
  on public.pachanga_admin_invites(server_sequence);

create or replace function public.accept_pachanga_admin_invite_authoritative_v1(
  admin_token uuid,
  member_name text,
  operation_id uuid,
  expected_invite_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  current_user_id uuid := auth.uid();
  selected_invite public.pachanga_admin_invites%rowtype;
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  event_sequence bigint;
  response jsonb;
begin
  if current_user_id is null or operation_id is null or expected_invite_revision is null
    or not public.is_registered_pachanga_user() then
    raise exception 'Authentication, operation id and expected invite revision required';
  end if;

  select * into selected_invite
  from public.pachanga_admin_invites invites
  where invites.token = admin_token
  for update;
  if not found then raise exception 'Invalid admin invite'; end if;

  perform pg_advisory_xact_lock(hashtextextended('admin-invite:' || selected_invite.id::text, 0));
  replay := public.pachanga_operation_replay_v2(selected_invite.group_id, operation_id, current_user_id);
  if replay is not null then return replay; end if;

  if selected_invite.accepted_at is not null then
    if selected_invite.accepted_by is distinct from current_user_id then
      raise exception 'Admin invite was already used by another user';
    end if;
    select * into current_group from public.pachanga_groups groups where groups.id = selected_invite.group_id;
    response := jsonb_build_object(
      'groupId', selected_invite.group_id,
      'role', case when current_group.owner_id = current_user_id then 'owner' else 'admin' end,
      'inviteRevision', selected_invite.revision,
      'operationId', operation_id,
      'expectedRevision', expected_invite_revision,
      'confirmedRevision', current_group.payload_revision,
      'confirmedAt', clock_timestamp(),
      'serverSequence', selected_invite.server_sequence,
      'replayedAcceptance', true
    );
    insert into public.pachanga_operation_receipts(
      group_id, operation_id, operation_type, user_id, response,
      expected_revision, result_revision, client_metadata, server_sequence
    ) values (
      selected_invite.group_id, operation_id, 'admin_invite_accept_v1', current_user_id, response,
      expected_invite_revision, current_group.payload_revision,
      case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end,
      selected_invite.server_sequence
    ) on conflict on constraint pachanga_operation_receipts_group_id_operation_id_key do nothing;
    return response;
  end if;

  if selected_invite.expires_at <= clock_timestamp() then raise exception 'Admin invite has expired'; end if;
  if selected_invite.revision <> expected_invite_revision then
    raise exception 'Invite revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (selected_invite.group_id, current_user_id, 'admin', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update set
    role = case when public.pachanga_group_members.role = 'owner' then 'owner' else 'admin' end,
    display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  update public.pachanga_admin_invites invites set
    accepted_by = current_user_id,
    accepted_at = clock_timestamp(),
    revision = invites.revision + 1,
    server_sequence = nextval('public.pachanga_match_guest_sequence'),
    updated_at = clock_timestamp()
  where invites.id = selected_invite.id
  returning * into selected_invite;

  perform public.record_pachanga_group_event(
    selected_invite.group_id, null, 'admin_invite_accepted',
    jsonb_build_object('acceptedBy', current_user_id, 'inviteId', selected_invite.id, 'inviteRevision', selected_invite.revision),
    operation_id, true
  );
  select events.server_sequence into event_sequence
  from public.pachanga_group_events events
  where events.group_id = selected_invite.group_id and events.operation_id = $3
  order by events.server_sequence desc, events.id desc limit 1;
  select * into current_group from public.pachanga_groups groups where groups.id = selected_invite.group_id;

  response := jsonb_build_object(
    'groupId', selected_invite.group_id,
    'role', case when current_group.owner_id = current_user_id then 'owner' else 'admin' end,
    'inviteRevision', selected_invite.revision,
    'operationId', operation_id,
    'expectedRevision', expected_invite_revision,
    'confirmedRevision', current_group.payload_revision,
    'confirmedAt', clock_timestamp(),
    'serverSequence', event_sequence,
    'replayedAcceptance', false
  );
  insert into public.pachanga_operation_receipts(
    group_id, operation_id, operation_type, user_id, response,
    expected_revision, result_revision, client_metadata, server_sequence
  ) values (
    selected_invite.group_id, operation_id, 'admin_invite_accept_v1', current_user_id, response,
    expected_invite_revision, current_group.payload_revision,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end,
    event_sequence
  );
  return response;
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.accept_pachanga_admin_invite_authoritative_v1(uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.accept_pachanga_admin_invite_authoritative_v1(uuid, text, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.accept_pachanga_admin_invite(admin_token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_revision bigint;
  accepted jsonb;
begin
  select invites.revision into selected_revision
  from public.pachanga_admin_invites invites where invites.token = admin_token;
  if selected_revision is null then raise exception 'Invalid admin invite'; end if;
  accepted := public.accept_pachanga_admin_invite_authoritative_v1(
    admin_token, member_name, gen_random_uuid(), selected_revision,
    jsonb_build_object('surface', 'legacy-admin-invite-compatibility')
  );
  return (accepted ->> 'groupId')::uuid;
end;
$$;

revoke all on function public.accept_pachanga_admin_invite(uuid, text) from public, anon;
grant execute on function public.accept_pachanga_admin_invite(uuid, text) to authenticated;

alter table public.pachanga_team_challenges
  drop constraint if exists pachanga_team_challenges_status_check;
alter table public.pachanga_team_challenges
  add constraint pachanga_team_challenges_status_check
  check (status in ('proposed', 'changes_proposed', 'accepted', 'rejected', 'cancelled', 'expired'));
alter table public.pachanga_team_challenges
  add column if not exists expired_at timestamptz;

alter table public.pachanga_team_challenge_events
  drop constraint if exists pachanga_team_challenge_events_event_type_check;
alter table public.pachanga_team_challenge_events
  add constraint pachanga_team_challenge_events_event_type_check
  check (event_type in ('created', 'changes_proposed', 'accepted', 'rejected', 'cancelled', 'expired'));
alter table public.pachanga_team_challenge_events
  alter column actor_user_id drop not null;

create table if not exists private.pachanga_team_challenge_lifecycle_config (
  singleton boolean primary key default true check (singleton),
  expiry_grace interval not null default interval '0 minutes' check (expiry_grace >= interval '0 minutes'),
  proposal_ttl interval,
  updated_at timestamptz not null default clock_timestamp(),
  check (proposal_ttl is null or proposal_ttl > interval '0 minutes')
);

insert into private.pachanga_team_challenge_lifecycle_config(singleton, expiry_grace, proposal_ttl)
values (true, interval '0 minutes', null)
on conflict (singleton) do nothing;

revoke all on table private.pachanga_team_challenge_lifecycle_config
  from public, anon, authenticated;
grant select, update on table private.pachanga_team_challenge_lifecycle_config to service_role;

create or replace function private.pachanga_expire_team_challenge_v1(
  target_challenge_id uuid,
  target_operation_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_team_challenges%rowtype;
  config private.pachanga_team_challenge_lifecycle_config%rowtype;
  expiry_operation_id uuid;
  event_sequence bigint;
  recipient record;
  sender_name text;
  receiver_name text;
begin
  select * into config
  from private.pachanga_team_challenge_lifecycle_config settings
  where settings.singleton;

  select * into selected
  from public.pachanga_team_challenges challenges
  where challenges.id = target_challenge_id
  for update;
  if not found or selected.status not in ('proposed', 'changes_proposed') then return false; end if;
  if clock_timestamp() < selected.scheduled_at + coalesce(config.expiry_grace, interval '0 minutes') then
    return false;
  end if;

  expiry_operation_id := coalesce(
    target_operation_id,
    md5('challenge-expiry:' || selected.id::text || ':' || selected.revision::text)::uuid
  );

  update public.pachanga_team_challenges challenges set
    status = 'expired',
    revision = challenges.revision + 1,
    expired_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where challenges.id = selected.id
  returning * into selected;

  insert into public.pachanga_team_challenge_events(
    challenge_id, operation_id, actor_user_id, actor_group_id,
    event_type, challenge_revision, snapshot
  ) values (
    selected.id, expiry_operation_id,
    case when target_operation_id is null then null else auth.uid() end,
    selected.sender_group_id,
    'expired', selected.revision,
    public.pachanga_team_challenge_snapshot(selected.id, selected.sender_group_id)
  ) on conflict (operation_id) do nothing
  returning server_sequence into event_sequence;

  if event_sequence is null then return false; end if;
  perform public.pachanga_team_social_bump(
    array[selected.sender_group_id, selected.receiver_group_id], event_sequence
  );

  select groups.name into sender_name from public.pachanga_groups groups where groups.id = selected.sender_group_id;
  select groups.name into receiver_name from public.pachanga_groups groups where groups.id = selected.receiver_group_id;
  for recipient in
    select members.user_id, members.group_id
    from public.pachanga_group_members members
    where members.group_id in (selected.sender_group_id, selected.receiver_group_id)
      and members.role in ('owner', 'admin')
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      'team_challenge_expired',
      'Reto caducado',
      'El reto con ' || case
        when recipient.group_id = selected.sender_group_id then coalesce(receiver_name, 'el rival')
        else coalesce(sender_name, 'el rival')
      end || ' ha caducado sin confirmarse.',
      '/mercado?tab=retos',
      jsonb_build_object(
        'challengeId', selected.id,
        'status', selected.status,
        'challengeRevision', selected.revision,
        'serverSequence', event_sequence
      ),
      'team-challenge-expired:' || selected.id::text || ':' || recipient.user_id::text
    );
  end loop;
  return true;
end;
$$;

revoke all on function private.pachanga_expire_team_challenge_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_guard_team_challenge_deadline_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  grace interval;
begin
  if old.status in ('proposed', 'changes_proposed')
    and new.status not in ('expired')
  then
    select settings.expiry_grace into grace
    from private.pachanga_team_challenge_lifecycle_config settings
    where settings.singleton;
    if clock_timestamp() >= old.scheduled_at + coalesce(grace, interval '0 minutes') then
      raise exception 'Challenge has reached its expiry boundary. Reload the confirmed state.' using errcode = 'PT409';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_guard_team_challenge_deadline_v1()
  from public, anon, authenticated;
drop trigger if exists guard_pachanga_team_challenge_deadline_v1 on public.pachanga_team_challenges;
create trigger guard_pachanga_team_challenge_deadline_v1
before update on public.pachanga_team_challenges
for each row execute function private.pachanga_guard_team_challenge_deadline_v1();

alter function public.respond_pachanga_team_challenge_authoritative(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) rename to respond_pachanga_team_challenge_without_expiry_v1;
revoke all on function public.respond_pachanga_team_challenge_without_expiry_v1(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) from public, anon, authenticated;

create function public.respond_pachanga_team_challenge_authoritative(
  target_group_id uuid,
  target_challenge_id uuid,
  target_action text,
  target_scheduled_at timestamptz,
  target_modality text,
  target_field_name text,
  target_field_address text,
  target_field_place_id text,
  target_field_maps_url text,
  target_message text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication required';
  end if;
  if not exists (
    select 1 from public.pachanga_team_challenges challenges
    where challenges.id = target_challenge_id
      and target_group_id in (challenges.sender_group_id, challenges.receiver_group_id)
  ) then raise exception 'Challenge not found'; end if;

  if private.pachanga_expire_team_challenge_v1(target_challenge_id, null) then
    raise exception 'Challenge expired. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  return public.respond_pachanga_team_challenge_without_expiry_v1(
    target_group_id, target_challenge_id, target_action, target_scheduled_at,
    target_modality, target_field_name, target_field_address, target_field_place_id,
    target_field_maps_url, target_message, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.respond_pachanga_team_challenge_authoritative(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.respond_pachanga_team_challenge_authoritative(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) to authenticated, service_role;

create or replace function public.reconcile_pachanga_team_challenge_expiry_v1(
  target_group_id uuid,
  target_challenge_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  selected public.pachanga_team_challenges%rowtype;
  current_sequence bigint;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  replay := public.pachanga_team_social_operation_replay(
    target_group_id, operation_id, auth.uid(), 'team_challenge_expired'
  );
  if replay is not null then return replay; end if;

  select * into selected from public.pachanga_team_challenges challenges
  where challenges.id = target_challenge_id
    and target_group_id in (challenges.sender_group_id, challenges.receiver_group_id);
  if not found then raise exception 'Challenge not found'; end if;
  if selected.status = 'expired' then
    select states.server_sequence into current_sequence
    from public.pachanga_team_social_state states where states.group_id = target_group_id;
  else
    if selected.revision <> expected_revision then
      raise exception 'Challenge revision is newer. Reload the confirmed state.' using errcode = 'PT409';
    end if;
    if not private.pachanga_expire_team_challenge_v1(target_challenge_id, operation_id) then
      raise exception 'Challenge expiry boundary has not been reached';
    end if;
    select events.server_sequence into current_sequence
    from public.pachanga_team_challenge_events events
    where events.operation_id = $3;
  end if;

  return public.pachanga_team_social_store_response(
    target_group_id, operation_id, 'team_challenge_expired', expected_revision,
    current_sequence, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$$;

revoke all on function public.reconcile_pachanga_team_challenge_expiry_v1(uuid, uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.reconcile_pachanga_team_challenge_expiry_v1(uuid, uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.run_pachanga_team_challenge_expiry_v1(batch_limit integer default 250)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  candidate record;
  processed integer := 0;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required'; end if;
  for candidate in
    select challenges.id
    from public.pachanga_team_challenges challenges
    cross join private.pachanga_team_challenge_lifecycle_config settings
    where settings.singleton
      and challenges.status in ('proposed', 'changes_proposed')
      and challenges.scheduled_at + settings.expiry_grace <= clock_timestamp()
    order by challenges.scheduled_at, challenges.id
    limit greatest(1, least(coalesce(batch_limit, 250), 1000))
    for update skip locked
  loop
    if private.pachanga_expire_team_challenge_v1(candidate.id, null) then
      processed := processed + 1;
    end if;
  end loop;
  return jsonb_build_object('expiredCount', processed, 'confirmedAt', clock_timestamp());
end;
$$;

revoke all on function public.run_pachanga_team_challenge_expiry_v1(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.run_pachanga_team_challenge_expiry_v1(integer) to service_role;

create or replace function public.pachanga_team_challenge_snapshot(
  target_challenge_id uuid,
  perspective_group_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', challenges.id,
    'direction', case when challenges.sender_group_id = perspective_group_id then 'outgoing' else 'incoming' end,
    'status', challenges.status,
    'revision', challenges.revision,
    'proposalNumber', challenges.proposal_number,
    'scheduledAt', challenges.scheduled_at,
    'modality', challenges.modality,
    'field', jsonb_build_object(
      'name', challenges.field_name,
      'address', challenges.field_address,
      'placeId', challenges.field_place_id,
      'mapsUrl', challenges.field_maps_url
    ),
    'message', challenges.message,
    'lastProposedBy', case when challenges.last_proposed_by_group_id = perspective_group_id then 'own' else 'opponent' end,
    'opponent', jsonb_build_object(
      'groupId', opponents.id,
      'name', opponents.name,
      'teamCode', opponents.team_code
    ),
    'acceptedAt', challenges.accepted_at,
    'rejectedAt', challenges.rejected_at,
    'cancelledAt', challenges.cancelled_at,
    'expiredAt', challenges.expired_at,
    'createdAt', challenges.created_at,
    'updatedAt', challenges.updated_at
  )
  from public.pachanga_team_challenges challenges
  join public.pachanga_groups opponents
    on opponents.id = case
      when challenges.sender_group_id = perspective_group_id then challenges.receiver_group_id
      else challenges.sender_group_id
    end
  where challenges.id = target_challenge_id
    and perspective_group_id in (challenges.sender_group_id, challenges.receiver_group_id);
$$;

revoke all on function public.pachanga_team_challenge_snapshot(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_team_social_snapshot(target_group_id uuid)
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog
as $$
declare
  current_state public.pachanga_team_social_state%rowtype;
  challenge_items jsonb;
  opponent_items jsonb;
  current_group public.pachanga_groups%rowtype;
  due record;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Group membership required';
  end if;

  for due in
    select challenges.id
    from public.pachanga_team_challenges challenges
    cross join private.pachanga_team_challenge_lifecycle_config settings
    where settings.singleton
      and target_group_id in (challenges.sender_group_id, challenges.receiver_group_id)
      and challenges.status in ('proposed', 'changes_proposed')
      and challenges.scheduled_at + settings.expiry_grace <= clock_timestamp()
    order by challenges.scheduled_at, challenges.id
  loop
    perform private.pachanga_expire_team_challenge_v1(due.id, null);
  end loop;

  select * into current_group
  from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  select * into current_state
  from public.pachanga_team_social_state states where states.group_id = target_group_id;

  select coalesce(jsonb_agg(
    public.pachanga_team_challenge_snapshot(challenges.id, target_group_id)
    order by
      case when challenges.status in ('proposed', 'changes_proposed') then 0
           when challenges.status = 'accepted' then 1 else 2 end,
      challenges.updated_at desc,
      challenges.id desc
  ), '[]'::jsonb)
  into challenge_items
  from public.pachanga_team_challenges challenges
  where target_group_id in (challenges.sender_group_id, challenges.receiver_group_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'groupId', opponents.id,
      'name', opponents.name,
      'teamCode', opponents.team_code,
      'matchesPlayed', known.matches_played,
      'firstEncounterAt', known.first_encounter_at,
      'lastEncounterAt', known.last_encounter_at,
      'lastMatchId', known.last_match_id,
      'revision', known.revision
    ) order by known.last_encounter_at desc, opponents.id
  ), '[]'::jsonb)
  into opponent_items
  from public.pachanga_known_opponents known
  join public.pachanga_groups opponents on opponents.id = known.opponent_group_id
  where known.group_id = target_group_id;

  return jsonb_build_object(
    'group', jsonb_build_object(
      'groupId', current_group.id,
      'name', current_group.name,
      'teamCode', current_group.team_code
    ),
    'canManage', public.is_pachanga_group_admin(target_group_id),
    'socialRevision', coalesce(current_state.revision, 0),
    'confirmedRevision', coalesce(current_state.revision, 0),
    'serverSequence', coalesce(current_state.server_sequence, 0),
    'updatedAt', coalesce(current_state.updated_at, current_group.updated_at),
    'challenges', challenge_items,
    'knownOpponents', opponent_items
  );
end;
$$;

revoke all on function public.get_pachanga_team_social_snapshot(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_team_social_snapshot(uuid)
  to authenticated, service_role;

create or replace function private.pachanga_reconcile_open_match_lifecycle_v1(
  target_open_match_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  closed_count integer;
begin
  update public.pachanga_open_matches open_matches
  set active = false,
      updated_at = clock_timestamp()
  where (target_open_match_id is null or open_matches.id = target_open_match_id)
    and open_matches.active
    and (
      open_matches.open_slots <= 0
      or open_matches.date <= clock_timestamp()
      or exists (
        select 1 from public.pachanga_match_read_model read_models
        where read_models.group_id = open_matches.source_group_id
          and read_models.match_id = open_matches.source_match_id
          and (read_models.lineup_closed or read_models.finalized)
      )
      or not exists (
        select 1
        from public.pachanga_groups groups
        cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
        where groups.id = open_matches.source_group_id
          and matches.value ->> 'id' = open_matches.source_match_id
          and not (coalesce((matches.value ->> 'closed')::boolean, false) or matches.value ? 'scoreA')
      )
    );
  get diagnostics closed_count = row_count;

  update public.pachanga_open_match_requests requests
  set status = 'rejected',
      decided_by = null,
      decided_at = clock_timestamp(),
      decision_note = 'market_closed',
      updated_at = clock_timestamp()
  from public.pachanga_open_matches open_matches
  where requests.open_match_id = open_matches.id
    and (target_open_match_id is null or open_matches.id = target_open_match_id)
    and not open_matches.active
    and requests.status = 'pending';

  return closed_count;
end;
$$;

revoke all on function private.pachanga_reconcile_open_match_lifecycle_v1(uuid)
  from public, anon, authenticated;

alter function public.request_pachanga_open_match_authoritative_v2_impl(uuid, uuid, bigint, jsonb)
  rename to request_pachanga_open_match_before_core_closure_v1;
revoke all on function public.request_pachanga_open_match_before_core_closure_v1(uuid, uuid, bigint, jsonb)
  from public, anon, authenticated;

create function public.request_pachanga_open_match_authoritative_v2_impl(
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
begin
  perform private.pachanga_reconcile_open_match_lifecycle_v1(target_open_match_id);
  return public.request_pachanga_open_match_before_core_closure_v1(
    target_open_match_id, operation_id, expected_match_revision, client_metadata
  );
end;
$$;

revoke all on function public.request_pachanga_open_match_authoritative_v2_impl(uuid, uuid, bigint, jsonb)
  from public, anon, authenticated;

alter function public.review_pachanga_open_match_request_authoritative_v2_impl(uuid, uuid, text, uuid, bigint, jsonb)
  rename to review_pachanga_open_match_request_before_core_closure_v1;
revoke all on function public.review_pachanga_open_match_request_before_core_closure_v1(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated;

create function public.review_pachanga_open_match_request_authoritative_v2_impl(
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
  selected_open_match_id uuid;
  response jsonb;
begin
  select requests.open_match_id into selected_open_match_id
  from public.pachanga_open_match_requests requests
  where requests.id = target_request_id;
  if selected_open_match_id is null then raise exception 'Request not found'; end if;

  perform private.pachanga_reconcile_open_match_lifecycle_v1(selected_open_match_id);
  if next_status = 'accepted' and exists (
    select 1 from public.pachanga_open_matches open_matches
    where open_matches.id = selected_open_match_id and not open_matches.active
  ) then
    raise exception 'The public match is closed';
  end if;

  response := public.review_pachanga_open_match_request_before_core_closure_v1(
    target_group_id, target_request_id, next_status, operation_id, expected_revision, client_metadata
  );
  perform private.pachanga_reconcile_open_match_lifecycle_v1(selected_open_match_id);
  return response;
end;
$$;

revoke all on function public.review_pachanga_open_match_request_authoritative_v2_impl(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated;

alter function public.sync_pachanga_open_match_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
  rename to sync_pachanga_open_match_before_core_closure_v1;
revoke all on function public.sync_pachanga_open_match_before_core_closure_v1(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;

create function public.sync_pachanga_open_match_authoritative_v2_impl(
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
  selected_date timestamptz;
begin
  if coalesce((match_patch ->> 'active')::boolean, false) then
    select (matches.value ->> 'date')::timestamptz into selected_date
    from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
    where groups.id = target_group_id and matches.value ->> 'id' = target_match_id
    limit 1;
    if selected_date is null or selected_date <= clock_timestamp() then
      raise exception 'Past or started matches cannot be published';
    end if;
  end if;
  return public.sync_pachanga_open_match_before_core_closure_v1(
    target_group_id, target_match_id, match_patch, operation_id,
    expected_revision, client_metadata
  );
end;
$$;

revoke all on function public.sync_pachanga_open_match_authoritative_v2_impl(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;

create or replace function public.search_pachanga_open_matches_v1()
returns jsonb
language plpgsql
security definer
volatile
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  perform private.pachanga_reconcile_open_match_lifecycle_v1(null);

  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', open_matches.id,
        'source_payload_revision', open_matches.source_payload_revision,
        'group_name', open_matches.group_name,
        'title', open_matches.title,
        'date', open_matches.date,
        'date_text', open_matches.date_text,
        'day', open_matches.day,
        'modality', open_matches.modality,
        'zone', open_matches.zone,
        'lat', case when open_matches.lat is null then null else round(open_matches.lat::numeric, 2) end,
        'lng', case when open_matches.lng is null then null else round(open_matches.lng::numeric, 2) end,
        'field_name', open_matches.field_name,
        'field_cost', open_matches.field_cost,
        'price_per_player', open_matches.price_per_player,
        'target_players', open_matches.target_players,
        'confirmed_count', open_matches.confirmed_count,
        'open_slots', open_matches.open_slots,
        'min_media', open_matches.min_media,
        'max_media', open_matches.max_media,
        'positions', open_matches.positions,
        'requires_approval', open_matches.requires_approval,
        'guests_pay', open_matches.guests_pay,
        'group_level', open_matches.group_level,
        'active', open_matches.active
      ) order by open_matches.date asc, open_matches.id asc
    ), '[]'::jsonb)
    from public.pachanga_open_matches open_matches
    where (
      open_matches.active and open_matches.open_slots > 0 and open_matches.date > clock_timestamp()
    ) or exists (
      select 1 from public.pachanga_open_match_requests own_request
      where own_request.open_match_id = open_matches.id
        and own_request.requester_user_id = auth.uid()
        and own_request.status = 'accepted'
    )
  );
end;
$$;

revoke all on function public.search_pachanga_open_matches_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_open_matches_v1()
  to authenticated, service_role;
