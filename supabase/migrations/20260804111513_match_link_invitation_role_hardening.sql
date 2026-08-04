-- Separate one-use match invitations from permanent group/admin invitations.
-- A match invitation can be opened before registration, but only an authenticated
-- user can accept it. Acceptance grants access to the safe guest read model only.

create table if not exists public.pachanga_match_link_invitations (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  inviter_user_id uuid not null references auth.users(id) on delete restrict,
  claimed_by_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  expires_at timestamptz not null default (clock_timestamp() + interval '7 days'),
  created_at timestamptz not null default clock_timestamp(),
  responded_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('pending', 'accepted', 'rejected', 'cancelled'))
);

create index if not exists pachanga_match_link_invitations_group_match_idx
  on public.pachanga_match_link_invitations(group_id, match_id, server_sequence desc);
create index if not exists pachanga_match_link_invitations_claimed_by_idx
  on public.pachanga_match_link_invitations(claimed_by_user_id, server_sequence desc)
  where claimed_by_user_id is not null;

alter table public.pachanga_match_link_invitations enable row level security;
revoke all on table public.pachanga_match_link_invitations from public, anon, authenticated;

create or replace function public.create_pachanga_match_link_invitation_v1(
  target_group_id uuid,
  target_match_id text,
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
  actor_id uuid := auth.uid();
  current_group public.pachanga_groups%rowtype;
  selected_match jsonb;
  saved_invitation public.pachanga_match_link_invitations%rowtype;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;

  replay := private.pachanga_safe_operation_replay_v1(
    target_group_id, operation_id, actor_id, 'match_link_invitation_create_v1'
  );
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Solo los admins pueden invitar a un partido';
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id
  limit 1;
  if selected_match is null then raise exception 'Partido no encontrado'; end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Guarda el partido antes de invitar jugadores';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se puede invitar a un partido finalizado';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'La alineación está cerrada';
  end if;

  insert into public.pachanga_match_link_invitations(
    group_id, match_id, inviter_user_id
  ) values (
    target_group_id, target_match_id, actor_id
  )
  returning * into saved_invitation;

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', current_group.payload_revision,
    'invitation', jsonb_build_object(
      'id', saved_invitation.id,
      'token', saved_invitation.token,
      'status', saved_invitation.status,
      'revision', saved_invitation.revision,
      'serverSequence', saved_invitation.server_sequence,
      'expiresAt', saved_invitation.expires_at
    )
  );

  return private.pachanga_store_safe_operation_v1(
    target_group_id, operation_id, 'match_link_invitation_create_v1', actor_id,
    expected_revision, current_group.payload_revision, client_metadata,
    response, saved_invitation.server_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.create_pachanga_match_link_invitation_v1(uuid, text, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_pachanga_match_link_invitation_v1(uuid, text, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.get_pachanga_match_link_invitation_v1(invitation_token uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected_invitation public.pachanga_match_link_invitations%rowtype;
  selected_group public.pachanga_groups%rowtype;
  selected_match jsonb;
  confirmed_count integer;
begin
  select * into selected_invitation
  from public.pachanga_match_link_invitations invitations
  where invitations.token = invitation_token;
  if not found then raise exception 'Invitación no encontrada'; end if;

  select * into selected_group
  from public.pachanga_groups groups
  where groups.id = selected_invitation.group_id;
  if not found then raise exception 'Grupo no encontrado'; end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(selected_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = selected_invitation.match_id
  limit 1;
  if selected_match is null then raise exception 'Partido no encontrado'; end if;

  select count(*)::integer into confirmed_count
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) participants(value)
  where participants.value ->> 'status' = 'voy';

  return jsonb_build_object(
    'invitation', jsonb_build_object(
      'status', case
        when selected_invitation.status = 'pending' and selected_invitation.expires_at <= statement_timestamp() then 'expired'
        else selected_invitation.status
      end,
      'revision', selected_invitation.revision,
      'serverSequence', selected_invitation.server_sequence,
      'expiresAt', selected_invitation.expires_at
    ),
    'groupName', selected_group.name,
    'matchRevision', selected_group.payload_revision,
    'match', jsonb_strip_nulls(jsonb_build_object(
      'id', selected_invitation.match_id,
      'title', coalesce(nullif(selected_match ->> 'title', ''), 'Partido'),
      'date', selected_match ->> 'date',
      'place', selected_match -> 'place',
      'kind', selected_match ->> 'kind',
      'targetPlayers', greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0)),
      'confirmedCount', confirmed_count,
      'lineupClosed', coalesce((selected_match ->> 'lineupClosed')::boolean, false),
      'finalized', coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA'
    ))
  );
end;
$$;

revoke all on function public.get_pachanga_match_link_invitation_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_match_link_invitation_v1(uuid)
  to anon, authenticated, service_role;

create or replace function public.respond_pachanga_match_link_invitation_v1(
  invitation_token uuid,
  next_status text,
  operation_id uuid,
  expected_invitation_revision bigint,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_invitation public.pachanga_match_link_invitations%rowtype;
  current_group public.pachanga_groups%rowtype;
  auth_metadata jsonb;
  player_profile public.pachanga_player_profiles%rowtype;
  display_name text;
  avatar_url text;
  acceptance jsonb;
  saved_access_id uuid;
  result_revision bigint;
  result_sequence bigint;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null
    or expected_invitation_revision is null or expected_match_revision is null
  then
    raise exception 'Authentication, operation id and revisions required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if next_status not in ('accepted', 'rejected') then raise exception 'Respuesta no válida'; end if;

  select * into selected_invitation
  from public.pachanga_match_link_invitations invitations
  where invitations.token = invitation_token
  for update;
  if not found then raise exception 'Invitación no encontrada'; end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_invitation.group_id, operation_id, actor_id, 'match_link_invitation_respond_v1'
  );
  if replay is not null then return replay; end if;
  if selected_invitation.revision <> expected_invitation_revision then
    raise exception 'Invitation revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected_invitation.status <> 'pending' then raise exception 'La invitación ya estaba decidida'; end if;
  if selected_invitation.expires_at <= clock_timestamp() then raise exception 'La invitación ha caducado'; end if;
  if public.is_pachanga_group_member(selected_invitation.group_id) then
    raise exception 'Ya perteneces al grupo; abre el partido desde tu equipo';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_invitation.group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if current_group.payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select users.raw_user_meta_data into auth_metadata
  from auth.users users
  where users.id = actor_id;
  display_name := coalesce(
    nullif(trim(auth_metadata ->> 'full_name'), ''),
    nullif(trim(auth_metadata ->> 'name'), ''),
    'Jugador invitado'
  );

  if next_status = 'accepted' then
    select * into player_profile
    from public.pachanga_player_profiles profiles
    where profiles.user_id = actor_id
    order by profiles.profile_version desc, profiles.id desc
    limit 1;

    display_name := coalesce(
      nullif(trim(player_profile.display_name), ''),
      display_name
    );
    avatar_url := coalesce(
      nullif(player_profile.avatar, ''),
      nullif(auth_metadata ->> 'avatar_url', ''),
      nullif(auth_metadata ->> 'picture', '')
    );

    select access.id into saved_access_id
    from public.pachanga_match_guest_access access
    where access.group_id = selected_invitation.group_id
      and access.match_id = selected_invitation.match_id
      and access.guest_user_id = actor_id
      and access.status = 'accepted'
    order by access.server_sequence desc, access.id desc
    limit 1;

    if saved_access_id is null then
      acceptance := private.pachanga_accept_guest_into_match_v1(
        selected_invitation.group_id,
        selected_invitation.match_id,
        actor_id,
        display_name,
        avatar_url,
        player_profile.avatar_offset_x,
        player_profile.avatar_offset_y,
        player_profile.birth_date,
        coalesce(nullif(player_profile.position, ''), 'Mediocentro / pivote'),
        coalesce(player_profile.goalkeeper_only, false),
        coalesce(player_profile.rating, 5),
        clock_timestamp(),
        'invitation',
        selected_invitation.id,
        operation_id
      );
      saved_access_id := (acceptance ->> 'accessId')::uuid;
      result_revision := (acceptance ->> 'payload_revision')::bigint;
    else
      result_revision := current_group.payload_revision;
    end if;
  else
    result_revision := current_group.payload_revision;
  end if;

  update public.pachanga_match_link_invitations invitations
  set status = next_status,
      claimed_by_user_id = actor_id,
      revision = invitations.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      responded_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where invitations.id = selected_invitation.id
  returning invitations.server_sequence into result_sequence;

  perform private.pachanga_notify_v1(
    selected_invitation.inviter_user_id,
    'match_link_invitation_response',
    case when next_status = 'accepted' then 'Invitación aceptada' else 'Invitación rechazada' end,
    display_name || case when next_status = 'accepted' then ' irá al partido.' else ' ha rechazado la invitación.' end,
    '/?mobile=partido&p=' || replace(selected_invitation.match_id, '-', ''),
    jsonb_build_object(
      'invitationId', selected_invitation.id,
      'status', next_status,
      'matchRevision', result_revision
    ),
    'match-link-invitation:' || selected_invitation.id::text || ':inviter:' || next_status
  );

  response := jsonb_strip_nulls(jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', result_revision,
    'invitation', jsonb_build_object(
      'status', next_status,
      'revision', expected_invitation_revision + 1,
      'serverSequence', result_sequence
    ),
    'accessId', saved_access_id
  ));

  return private.pachanga_store_safe_operation_v1(
    selected_invitation.group_id, operation_id, 'match_link_invitation_respond_v1', actor_id,
    expected_match_revision, result_revision, client_metadata, response, result_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.respond_pachanga_match_link_invitation_v1(uuid, text, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.respond_pachanga_match_link_invitation_v1(uuid, text, uuid, bigint, bigint, jsonb)
  to authenticated, service_role;

-- Guests accepted through the safe match route are not group members. Keep the
-- regular attendance/payment RPCs restricted to actual members so a guessed
-- player id cannot turn the guest page into a hidden write surface.
create or replace function private.pachanga_require_group_member_v1(target_group_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Solo los miembros del grupo pueden modificar este dato';
  end if;
end;
$$;

revoke all on function private.pachanga_require_group_member_v1(uuid)
  from public, anon, authenticated, service_role;

alter function public.patch_pachanga_match_player_status_authoritative_v2(
  uuid, text, text, text, uuid, bigint, jsonb
) rename to patch_pachanga_match_player_status_authoritative_v2_member_impl;
revoke all on function public.patch_pachanga_match_player_status_authoritative_v2_member_impl(
  uuid, text, text, text, uuid, bigint, jsonb
) from public, anon, authenticated;

create function public.patch_pachanga_match_player_status_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text,
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
  perform private.pachanga_require_group_member_v1(target_group_id);
  return public.patch_pachanga_match_player_status_authoritative_v2_member_impl(
    target_group_id, target_match_id, target_player_id, next_status,
    operation_id, expected_revision, client_metadata
  );
end;
$$;

revoke all on function public.patch_pachanga_match_player_status_authoritative_v2(
  uuid, text, text, text, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_player_status_authoritative_v2(
  uuid, text, text, text, uuid, bigint, jsonb
) to authenticated, service_role;

alter function public.patch_pachanga_match_player_paid_authoritative_v2(
  uuid, text, text, boolean, uuid, bigint, jsonb
) rename to patch_pachanga_match_player_paid_authoritative_v2_member_impl;
revoke all on function public.patch_pachanga_match_player_paid_authoritative_v2_member_impl(
  uuid, text, text, boolean, uuid, bigint, jsonb
) from public, anon, authenticated;

create function public.patch_pachanga_match_player_paid_authoritative_v2(
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
set lock_timeout = '750ms'
as $$
begin
  perform private.pachanga_require_group_member_v1(target_group_id);
  return public.patch_pachanga_match_player_paid_authoritative_v2_member_impl(
    target_group_id, target_match_id, target_player_id, next_paid,
    operation_id, expected_revision, client_metadata
  );
end;
$$;

revoke all on function public.patch_pachanga_match_player_paid_authoritative_v2(
  uuid, text, text, boolean, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.patch_pachanga_match_player_paid_authoritative_v2(
  uuid, text, text, boolean, uuid, bigint, jsonb
) to authenticated, service_role;
