create or replace function public.is_registered_pachanga_user()
returns boolean
language sql
set search_path = public
stable
as $$
  select (select auth.uid()) is not null
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false;
$$;

drop policy if exists "Owners can create groups" on public.pachanga_groups;
create policy "Owners can create groups"
on public.pachanga_groups
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and (select auth.uid()) = owner_id
);

drop policy if exists "Members can read groups" on public.pachanga_groups;
create policy "Members can read groups"
on public.pachanga_groups
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    owner_id = (select auth.uid())
    or public.is_pachanga_group_member(id)
  )
);

drop policy if exists "Admins can update groups" on public.pachanga_groups;
create policy "Admins can update groups"
on public.pachanga_groups
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
);

drop policy if exists "Admins can delete groups" on public.pachanga_groups;
create policy "Admins can delete groups"
on public.pachanga_groups
for delete
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
);

drop policy if exists "Members can read memberships" on public.pachanga_group_members;
create policy "Members can read memberships"
on public.pachanga_group_members
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    user_id = (select auth.uid())
    or public.is_pachanga_group_owner(group_id)
    or public.is_pachanga_group_member(group_id)
  )
);

drop policy if exists "Owners can add themselves as members" on public.pachanga_group_members;
create policy "Owners can add themselves as members"
on public.pachanga_group_members
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can update member roles" on public.pachanga_group_members;
create policy "Admins can update member roles"
on public.pachanga_group_members
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(group_id)
  and role <> 'owner'
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(group_id)
  and role in ('admin', 'player')
);

drop policy if exists "Admins can create admin invites" on public.pachanga_admin_invites;
create policy "Admins can create admin invites"
on public.pachanga_admin_invites
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and created_by = (select auth.uid())
  and public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins can read admin invites" on public.pachanga_admin_invites;
create policy "Admins can read admin invites"
on public.pachanga_admin_invites
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins can update admin invites" on public.pachanga_admin_invites;
create policy "Admins can update admin invites"
on public.pachanga_admin_invites
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(group_id)
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(group_id)
);
