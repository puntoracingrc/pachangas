create index if not exists pachanga_groups_owner_id_idx on public.pachanga_groups(owner_id);
create index if not exists pachanga_group_members_user_id_idx on public.pachanga_group_members(user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke execute on function public.join_pachanga_group(uuid) from anon;
revoke execute on function public.join_pachanga_group(uuid) from public;
grant execute on function public.join_pachanga_group(uuid) to authenticated;
