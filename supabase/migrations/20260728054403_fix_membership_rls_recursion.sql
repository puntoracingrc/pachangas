create or replace function public.is_pachanga_group_member(target_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.user_id = auth.uid()
  );
$$;

create or replace function public.is_pachanga_group_owner(target_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.pachanga_groups groups
    where groups.id = target_group_id
      and groups.owner_id = auth.uid()
  );
$$;

revoke all on function public.is_pachanga_group_member(uuid) from public;
revoke all on function public.is_pachanga_group_owner(uuid) from public;
grant execute on function public.is_pachanga_group_member(uuid) to authenticated;
grant execute on function public.is_pachanga_group_owner(uuid) to authenticated;

drop policy if exists "Members can read groups" on public.pachanga_groups;
create policy "Members can read groups"
on public.pachanga_groups
for select
to authenticated
using (
  owner_id = (select auth.uid())
  or public.is_pachanga_group_member(id)
);

drop policy if exists "Members can update groups" on public.pachanga_groups;
create policy "Members can update groups"
on public.pachanga_groups
for update
to authenticated
using (
  owner_id = (select auth.uid())
  or public.is_pachanga_group_member(id)
)
with check (
  owner_id = (select auth.uid())
  or public.is_pachanga_group_member(id)
);

drop policy if exists "Members can read memberships" on public.pachanga_group_members;
create policy "Members can read memberships"
on public.pachanga_group_members
for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.is_pachanga_group_owner(group_id)
  or public.is_pachanga_group_member(group_id)
);

drop policy if exists "Owners can add themselves as members" on public.pachanga_group_members;
create policy "Owners can add themselves as members"
on public.pachanga_group_members
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and public.is_pachanga_group_owner(group_id)
);
