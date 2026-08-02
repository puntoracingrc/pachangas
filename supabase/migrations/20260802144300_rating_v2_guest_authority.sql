-- Pachangas IQ rating system V2: versioned guest identity and link operations.

create or replace function public.create_pachanga_guest_identity_authoritative_v2(
  target_group_id uuid,
  display_name text,
  contact_hint text,
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
  guest_id uuid;
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
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can create guests';
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;

  guest_id := public.create_pachanga_guest_identity_v2(target_group_id, display_name, contact_hint);
  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  insert into public.pachanga_group_events(
    group_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id, operation_id, null, 'guest_identity_created_v2', true,
    jsonb_build_object('guestId', guest_id)
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'guest_identity_created_v2', expected_revision,
    jsonb_build_object('guestId', guest_id), client_metadata
  );
end;
$$;

create or replace function public.link_pachanga_guest_identity_authoritative_v2(
  target_group_id uuid,
  target_guest_id uuid,
  target_user_id uuid,
  reason text,
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
  link_result jsonb;
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
  if not exists (
    select 1 from public.pachanga_guest_identities guests
    where guests.id = target_guest_id
      and guests.created_by_group_id = target_group_id
  ) then raise exception 'Guest identity not found'; end if;

  link_result := public.link_pachanga_guest_identity_v2(
    target_guest_id, target_user_id, reason, operation_id
  );
  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  insert into public.pachanga_group_events(
    group_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id, operation_id, null, 'guest_identity_linked_v2',
    public.is_pachanga_group_admin(target_group_id),
    jsonb_build_object('guestId', target_guest_id, 'state', 'linked')
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'guest_identity_linked_v2', expected_revision,
    link_result, client_metadata
  );
end;
$$;

create or replace function public.reverse_pachanga_guest_link_authoritative_v2(
  target_group_id uuid,
  target_guest_id uuid,
  reason text,
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
  reverse_result jsonb;
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
  if not exists (
    select 1 from public.pachanga_guest_identities guests
    where guests.id = target_guest_id
      and guests.created_by_group_id = target_group_id
  ) then raise exception 'Guest identity not found'; end if;

  reverse_result := public.reverse_pachanga_guest_link_v2(target_guest_id, reason);
  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  insert into public.pachanga_group_events(
    group_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id, operation_id, null, 'guest_identity_link_reversed_v2',
    public.is_pachanga_group_admin(target_group_id),
    jsonb_build_object('guestId', target_guest_id, 'state', 'reversed')
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'guest_identity_link_reversed_v2', expected_revision,
    reverse_result, client_metadata
  );
end;
$$;

revoke all on function public.create_pachanga_guest_identity_v2(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.link_pachanga_guest_identity_v2(uuid, uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.reverse_pachanga_guest_link_v2(uuid, text)
  from public, anon, authenticated;
revoke all on function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon;

grant execute on function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb)
  to authenticated;
