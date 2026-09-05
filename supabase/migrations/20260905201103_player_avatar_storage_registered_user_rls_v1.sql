-- Require a registered non-anonymous account for avatar object management.

set lock_timeout = '5s';
set statement_timeout = '120s';

drop policy if exists "Players upload their own avatars" on storage.objects;
create policy "Players upload their own avatars"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'pachanga-player-avatars'
  and public.is_registered_pachanga_user()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Players read their own avatar objects" on storage.objects;
create policy "Players read their own avatar objects"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pachanga-player-avatars'
  and public.is_registered_pachanga_user()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "Players remove their own avatar objects" on storage.objects;
create policy "Players remove their own avatar objects"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'pachanga-player-avatars'
  and public.is_registered_pachanga_user()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
