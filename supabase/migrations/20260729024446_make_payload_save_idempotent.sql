create or replace function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can save the full team state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  if current_group.payload = next_payload then
    return jsonb_build_object(
      'payload', current_group.payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
  end if;

  update public.pachanga_groups
  set payload = next_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
end;
$$;

revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from public;
revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from anon;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
