-- Restore suspended referee profiles safely when publication evidence became stale.
-- Product flags remain unchanged by this migration.

drop trigger if exists pachanga_referee_00_restore_private_v1
on public.pachanga_referee_profiles;
drop function if exists private.pachanga_referee_restore_private_v1();

create or replace function private.pachanga_referee_publication_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.operational_status = 'suspended'
     and new.operational_status = 'active'
     and new.visibility = 'public' then
    new.visibility := 'private';
  end if;

  if old.operational_status = 'active'
     and old.visibility = 'public'
     and new.operational_status = 'active'
     and new.visibility = 'public'
     and (
       new.slug, new.public_display_name_snapshot, new.public_avatar_snapshot,
       new.bio, new.experience_since_year, new.experience_summary,
       new.availability_status, new.available_for_assignments,
       new.share_recurring_availability
     ) is distinct from (
       old.slug, old.public_display_name_snapshot, old.public_avatar_snapshot,
       old.bio, old.experience_since_year, old.experience_summary,
       old.availability_status, old.available_for_assignments,
       old.share_recurring_availability
     ) then
    raise exception 'REFEREE_PUBLICATION_PAUSE_REQUIRED' using errcode = '42501';
  end if;

  if new.operational_status = 'active'
     and new.visibility = 'public'
     and old.visibility is distinct from 'public'
     and (
       new.slug, new.public_display_name_snapshot, new.public_avatar_snapshot,
       new.bio, new.experience_since_year, new.experience_summary,
       new.availability_status, new.available_for_assignments,
       new.share_recurring_availability
     ) is distinct from (
       old.slug, old.public_display_name_snapshot, old.public_avatar_snapshot,
       old.bio, old.experience_since_year, old.experience_summary,
       old.availability_status, old.available_for_assignments,
       old.share_recurring_availability
     ) then
    raise exception 'REFEREE_PUBLICATION_RECONFIRM_REQUIRED' using errcode = '42501';
  end if;

  if not (
    old.operational_status = 'suspended'
    and new.operational_status = 'active'
    and new.visibility = 'private'
  ) and (
    (new.operational_status = 'active' and old.operational_status is distinct from 'active')
    or (new.marketplace_status = 'listed' and old.marketplace_status is distinct from 'listed')
    or (new.visibility = 'public' and old.visibility is distinct from 'public'
        and new.operational_status = 'active')
  ) and not private.pachanga_publication_consent_valid_v1(
    'REFEREE_PROFILE', new.id, new.user_id
  ) then
    raise exception 'REFEREE_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_referee_publication_guard_v1()
  from public, anon, authenticated, service_role;

comment on function private.pachanga_referee_publication_guard_v1() is
  'Guards public referee changes and always restores suspended public profiles as private.';
