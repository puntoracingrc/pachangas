create or replace function public.update_pachanga_member_name(target_group_id uuid, member_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  next_name text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  next_name := nullif(trim(member_name), '');
  if next_name is null then
    raise exception 'Member name required';
  end if;

  update public.pachanga_group_members
  set display_name = next_name
  where group_id = target_group_id
    and user_id = current_user_id;

  if not found then
    raise exception 'Current user is not a member of this group';
  end if;

  return next_name;
end;
$$;

revoke all on function public.update_pachanga_member_name(uuid, text) from public;
revoke execute on function public.update_pachanga_member_name(uuid, text) from anon;
grant execute on function public.update_pachanga_member_name(uuid, text) to authenticated;
