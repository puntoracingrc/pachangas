-- Player avatar media and canonical profile synchronization.

set lock_timeout = '5s';
set statement_timeout = '120s';

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'pachanga-player-avatars',
  'pachanga-player-avatars',
  true,
  1048576,
  array['image/webp', 'image/jpeg', 'image/png']::text[]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Players upload their own avatars" on storage.objects;
create policy "Players upload their own avatars"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'pachanga-player-avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Players read their own avatar objects" on storage.objects;
create policy "Players read their own avatar objects"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pachanga-player-avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Players remove their own avatar objects" on storage.objects;
create policy "Players remove their own avatar objects"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'pachanga-player-avatars'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create or replace function private.pachanga_sync_social_avatar_to_player_profile_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_profile_id uuid;
  target_profile_revision bigint;
begin
  if new.avatar_ref is not distinct from old.avatar_ref then
    return new;
  end if;

  update public.pachanga_player_profiles profiles
  set avatar = new.avatar_ref,
      avatar_offset_x = case when new.avatar_ref is null then null else 50 end,
      avatar_offset_y = case when new.avatar_ref is null then null else 0 end,
      profile_version = profiles.profile_version + 1,
      updated_at = pg_catalog.clock_timestamp()
  where profiles.user_id = new.user_id
  returning profiles.id, profiles.profile_version
  into target_profile_id, target_profile_revision;

  if target_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(target_profile_id);
    insert into public.pachanga_social_invalidations_v1(
      entity_type, entity_id, revision, audience_user_id
    ) values (
      'rating_profile', target_profile_id::text, target_profile_revision, new.user_id
    );
  end if;

  return new;
end;
$$;

revoke all on function private.pachanga_sync_social_avatar_to_player_profile_v1()
from public, anon, authenticated, service_role;

drop trigger if exists pachanga_social_avatar_sync_player_profile_v1
on public.pachanga_social_player_profiles_v1;
create trigger pachanga_social_avatar_sync_player_profile_v1
after update of avatar_ref
on public.pachanga_social_player_profiles_v1
for each row execute function private.pachanga_sync_social_avatar_to_player_profile_v1();
