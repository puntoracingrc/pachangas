grant usage on schema public to authenticated;
grant select, insert, update on public.pachanga_groups to authenticated;
grant select, insert on public.pachanga_group_members to authenticated;
revoke execute on function public.join_pachanga_group(uuid) from anon;
revoke all on function public.join_pachanga_group(uuid) from public;
grant execute on function public.join_pachanga_group(uuid) to authenticated;
