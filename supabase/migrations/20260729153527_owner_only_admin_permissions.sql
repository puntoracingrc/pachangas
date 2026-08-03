drop policy if exists "Admins can update member roles" on public.pachanga_group_members;
drop policy if exists "Owners can update member roles" on public.pachanga_group_members;
create policy "Owners can update member roles"
on public.pachanga_group_members
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
  and role <> 'owner'
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
  and role in ('admin', 'player')
);

drop policy if exists "Admins can create admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can create admin invites" on public.pachanga_admin_invites;
create policy "Owners can create admin invites"
on public.pachanga_admin_invites
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and created_by = (select auth.uid())
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can read admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can read admin invites" on public.pachanga_admin_invites;
create policy "Owners can read admin invites"
on public.pachanga_admin_invites
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can update admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can update admin invites" on public.pachanga_admin_invites;
create policy "Owners can update admin invites"
on public.pachanga_admin_invites
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
);

create or replace function public.create_pachanga_admin_invite(target_group_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  created_token uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_owner(target_group_id) then
    raise exception 'Only the group owner can invite admins';
  end if;

  insert into public.pachanga_admin_invites (group_id, created_by)
  values (target_group_id, current_user_id)
  returning token into created_token;

  return created_token;
end;
$$;
