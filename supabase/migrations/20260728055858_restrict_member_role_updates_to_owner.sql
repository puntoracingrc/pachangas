drop policy if exists "Admins can update member roles" on public.pachanga_group_members;
drop policy if exists "Owners can update member roles" on public.pachanga_group_members;
create policy "Owners can update member roles"
on public.pachanga_group_members
for update
to authenticated
using (
  public.is_pachanga_group_owner(group_id)
)
with check (
  public.is_pachanga_group_owner(group_id)
);
