create table if not exists public.pachanga_group_backups (
  id uuid primary key default gen_random_uuid(),
  source_group_id uuid,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  group_name text not null,
  team_code text,
  reason text not null default 'manual',
  payload jsonb not null,
  created_at timestamptz not null default now(),
  restored_at timestamptz,
  restored_group_id uuid
);

create index if not exists pachanga_group_backups_owner_id_idx
on public.pachanga_group_backups(owner_id);

create index if not exists pachanga_group_backups_source_group_id_idx
on public.pachanga_group_backups(source_group_id);

create index if not exists pachanga_group_backups_created_at_idx
on public.pachanga_group_backups(created_at desc);

grant select on public.pachanga_group_backups to authenticated;

alter table public.pachanga_group_backups enable row level security;

drop policy if exists "Users can read recoverable backups" on public.pachanga_group_backups;
create policy "Users can read recoverable backups"
on public.pachanga_group_backups
for select
to authenticated
using (
  owner_id = (select auth.uid())
  or created_by = (select auth.uid())
  or (
    source_group_id is not null
    and public.is_pachanga_group_admin(source_group_id)
  )
);

create or replace function public.create_pachanga_group_backup(
  target_group_id uuid,
  backup_reason text default 'manual',
  backup_payload jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  created_backup_id uuid;
  source_group public.pachanga_groups%rowtype;
  snapshot_payload jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can create backups';
  end if;

  select * into source_group
  from public.pachanga_groups
  where id = target_group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  snapshot_payload := coalesce(backup_payload, source_group.payload);

  insert into public.pachanga_group_backups (
    source_group_id,
    owner_id,
    created_by,
    group_name,
    team_code,
    reason,
    payload
  )
  values (
    source_group.id,
    source_group.owner_id,
    current_user_id,
    source_group.name,
    source_group.team_code,
    coalesce(nullif(trim(backup_reason), ''), 'manual'),
    snapshot_payload
  )
  returning id into created_backup_id;

  return created_backup_id;
end;
$$;

create or replace function public.restore_pachanga_group_backup(backup_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  selected_backup public.pachanga_group_backups%rowtype;
  restored_group uuid;
  can_restore_existing boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into selected_backup
  from public.pachanga_group_backups
  where id = backup_id;

  if not found then
    raise exception 'Backup not found';
  end if;

  if selected_backup.owner_id <> current_user_id
    and selected_backup.created_by is distinct from current_user_id
    and not (
      selected_backup.source_group_id is not null
      and public.is_pachanga_group_admin(selected_backup.source_group_id)
    )
  then
    raise exception 'You cannot restore this backup';
  end if;

  can_restore_existing := selected_backup.source_group_id is not null
    and public.is_pachanga_group_admin(selected_backup.source_group_id)
    and exists (
      select 1 from public.pachanga_groups groups
      where groups.id = selected_backup.source_group_id
    );

  if can_restore_existing then
    update public.pachanga_groups
    set payload = selected_backup.payload,
        name = selected_backup.group_name
    where id = selected_backup.source_group_id;

    restored_group := selected_backup.source_group_id;
  else
    insert into public.pachanga_groups (owner_id, name, payload)
    values (current_user_id, selected_backup.group_name, selected_backup.payload)
    returning id into restored_group;

    insert into public.pachanga_group_members (group_id, user_id, role, display_name)
    values (restored_group, current_user_id, 'owner', null)
    on conflict (group_id, user_id) do update
      set role = 'owner';
  end if;

  update public.pachanga_group_backups
  set restored_at = now(),
      restored_group_id = restored_group
  where id = backup_id;

  return restored_group;
end;
$$;

revoke all on function public.create_pachanga_group_backup(uuid, text, jsonb) from public;
revoke execute on function public.create_pachanga_group_backup(uuid, text, jsonb) from anon;
grant execute on function public.create_pachanga_group_backup(uuid, text, jsonb) to authenticated;
revoke all on function public.restore_pachanga_group_backup(uuid) from public;
revoke execute on function public.restore_pachanga_group_backup(uuid) from anon;
grant execute on function public.restore_pachanga_group_backup(uuid) to authenticated;
