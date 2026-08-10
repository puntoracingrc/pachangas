-- Restrict Team Shield V1 reads and writes to registered users. Supabase
-- anonymous sessions also use the authenticated Postgres role, so membership
-- checks alone are not the complete product boundary.

alter function public.get_pachanga_team_shield_snapshot_v1(uuid)
  rename to get_pachanga_team_shield_snapshot_v1_impl;
alter function public.get_pachanga_team_public_shield_v1(uuid)
  rename to get_pachanga_team_public_shield_v1_impl;
alter function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb)
  rename to save_pachanga_team_shield_loadout_v1_impl;
alter function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb)
  rename to mark_pachanga_team_cosmetics_seen_v1_impl;

revoke all on function public.get_pachanga_team_shield_snapshot_v1_impl(uuid)
  from public, anon, authenticated;
revoke all on function public.get_pachanga_team_public_shield_v1_impl(uuid)
  from public, anon, authenticated;
revoke all on function public.save_pachanga_team_shield_loadout_v1_impl(uuid, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;
revoke all on function public.mark_pachanga_team_cosmetics_seen_v1_impl(uuid, text[], uuid, bigint, jsonb)
  from public, anon, authenticated;

create function public.get_pachanga_team_shield_snapshot_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  return public.get_pachanga_team_shield_snapshot_v1_impl(target_group_id);
end;
$$;

create function public.get_pachanga_team_public_shield_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  return public.get_pachanga_team_public_shield_v1_impl(target_group_id);
end;
$$;

create function public.save_pachanga_team_shield_loadout_v1(
  target_group_id uuid,
  target_config jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  return public.save_pachanga_team_shield_loadout_v1_impl(
    target_group_id, target_config, operation_id, expected_revision, client_metadata
  );
end;
$$;

create function public.mark_pachanga_team_cosmetics_seen_v1(
  target_group_id uuid,
  target_cosmetic_keys text[],
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  return public.mark_pachanga_team_cosmetics_seen_v1_impl(
    target_group_id, target_cosmetic_keys, operation_id, expected_revision, client_metadata
  );
end;
$$;

revoke all on function public.get_pachanga_team_shield_snapshot_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_team_shield_snapshot_v1(uuid)
  to authenticated, service_role;
revoke all on function public.get_pachanga_team_public_shield_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_team_public_shield_v1(uuid)
  to authenticated, service_role;
revoke all on function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb)
  to authenticated;
revoke all on function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb)
  to authenticated;

alter function public.save_pachanga_team_shield_loadout_v1(uuid, jsonb, uuid, bigint, jsonb)
  set lock_timeout = '750ms';
alter function public.mark_pachanga_team_cosmetics_seen_v1(uuid, text[], uuid, bigint, jsonb)
  set lock_timeout = '750ms';

drop policy if exists "Admins read team cosmetic inventory" on public.pachanga_team_cosmetic_inventory;
create policy "Admins read team cosmetic inventory"
on public.pachanga_team_cosmetic_inventory for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_admin(group_id));

drop policy if exists "Members read team shield state" on public.pachanga_team_shield_state;
create policy "Members read team shield state"
on public.pachanga_team_shield_state for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_member(group_id));

drop policy if exists "Admins read team shield loadout" on public.pachanga_team_shield_loadouts;
create policy "Admins read team shield loadout"
on public.pachanga_team_shield_loadouts for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_admin(group_id));

drop policy if exists "Admins read team shield versions" on public.pachanga_team_shield_versions;
create policy "Admins read team shield versions"
on public.pachanga_team_shield_versions for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_admin(group_id));

drop policy if exists "Members read public team shield" on public.pachanga_team_shield_public;
create policy "Members read public team shield"
on public.pachanga_team_shield_public for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_member(group_id));

drop policy if exists "Admins read own shield eligibility" on public.pachanga_team_cosmetic_admin_eligibility;
create policy "Admins read own shield eligibility"
on public.pachanga_team_cosmetic_admin_eligibility for select to authenticated
using (
  public.is_registered_pachanga_user()
  and admin_user_id = (select auth.uid())
  and public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins read own shield seen state" on public.pachanga_team_cosmetic_seen;
create policy "Admins read own shield seen state"
on public.pachanga_team_cosmetic_seen for select to authenticated
using (
  public.is_registered_pachanga_user()
  and admin_user_id = (select auth.uid())
  and public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins read team shield events" on public.pachanga_team_shield_events;
create policy "Admins read team shield events"
on public.pachanga_team_shield_events for select to authenticated
using (public.is_registered_pachanga_user() and public.is_pachanga_group_admin(group_id));

drop policy if exists "Actors read own team shield receipts" on public.pachanga_team_shield_operation_receipts;
create policy "Actors read own team shield receipts"
on public.pachanga_team_shield_operation_receipts for select to authenticated
using (public.is_registered_pachanga_user() and actor_user_id = (select auth.uid()));
