create table if not exists public.pachanga_groups (
  id uuid primary key default gen_random_uuid(),
  invite_token uuid not null unique default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Equipo pachanguero',
  team_code text unique,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pachanga_group_members (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'player',
  display_name text,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.pachanga_admin_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now()
);

create or replace function public.new_pachanga_team_code()
returns text
language sql
set search_path = public
as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

update public.pachanga_groups
set team_code = public.new_pachanga_team_code()
where team_code is null;

alter table public.pachanga_groups
alter column team_code set default public.new_pachanga_team_code();

alter table public.pachanga_groups
alter column team_code set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_group_members_role_check'
  ) then
    alter table public.pachanga_group_members
    add constraint pachanga_group_members_role_check
    check (role in ('owner', 'admin', 'player'));
  end if;
end;
$$;

update public.pachanga_group_members members
set role = 'owner'
from public.pachanga_groups groups
where members.group_id = groups.id
  and members.user_id = groups.owner_id;

create index if not exists pachanga_groups_owner_id_idx
on public.pachanga_groups(owner_id);

create unique index if not exists pachanga_groups_team_code_idx
on public.pachanga_groups(team_code);

create index if not exists pachanga_group_members_user_id_idx
on public.pachanga_group_members(user_id);

create index if not exists pachanga_admin_invites_group_id_idx
on public.pachanga_admin_invites(group_id);

create index if not exists pachanga_admin_invites_token_idx
on public.pachanga_admin_invites(token);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.pachanga_groups to authenticated;
grant select, insert, update on public.pachanga_group_members to authenticated;
grant select, insert, update on public.pachanga_admin_invites to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_pachanga_groups_updated_at on public.pachanga_groups;
create trigger set_pachanga_groups_updated_at
before update on public.pachanga_groups
for each row
execute function public.set_updated_at();

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

create or replace function public.is_pachanga_group_admin(target_group_id uuid)
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
      and members.role in ('owner', 'admin')
  );
$$;

revoke all on function public.is_pachanga_group_member(uuid) from public;
revoke all on function public.is_pachanga_group_owner(uuid) from public;
revoke all on function public.is_pachanga_group_admin(uuid) from public;
revoke execute on function public.is_pachanga_group_member(uuid) from anon;
revoke execute on function public.is_pachanga_group_owner(uuid) from anon;
revoke execute on function public.is_pachanga_group_admin(uuid) from anon;
grant execute on function public.is_pachanga_group_member(uuid) to authenticated;
grant execute on function public.is_pachanga_group_owner(uuid) to authenticated;
grant execute on function public.is_pachanga_group_admin(uuid) to authenticated;

alter table public.pachanga_groups enable row level security;
alter table public.pachanga_group_members enable row level security;
alter table public.pachanga_admin_invites enable row level security;

drop policy if exists "Owners can create groups" on public.pachanga_groups;
create policy "Owners can create groups"
on public.pachanga_groups
for insert
to authenticated
with check ((select auth.uid()) = owner_id);

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

drop policy if exists "Owners can delete groups" on public.pachanga_groups;
drop policy if exists "Admins can delete groups" on public.pachanga_groups;
create policy "Admins can delete groups"
on public.pachanga_groups
for delete
to authenticated
using (
  public.is_pachanga_group_admin(id)
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

drop policy if exists "Admins can update member roles" on public.pachanga_group_members;
drop policy if exists "Owners can update member roles" on public.pachanga_group_members;
create policy "Admins can update member roles"
on public.pachanga_group_members
for update
to authenticated
using (
  public.is_pachanga_group_admin(group_id)
  and role <> 'owner'
)
with check (
  public.is_pachanga_group_admin(group_id)
  and role in ('admin', 'player')
);

drop policy if exists "Admins can create admin invites" on public.pachanga_admin_invites;
create policy "Admins can create admin invites"
on public.pachanga_admin_invites
for insert
to authenticated
with check (
  created_by = (select auth.uid())
  and public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins can read admin invites" on public.pachanga_admin_invites;
create policy "Admins can read admin invites"
on public.pachanga_admin_invites
for select
to authenticated
using (
  public.is_pachanga_group_admin(group_id)
);

drop policy if exists "Admins can update admin invites" on public.pachanga_admin_invites;
create policy "Admins can update admin invites"
on public.pachanga_admin_invites
for update
to authenticated
using (
  public.is_pachanga_group_admin(group_id)
)
with check (
  public.is_pachanga_group_admin(group_id)
);

create or replace function public.join_pachanga_group(token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select id into target_group_id
  from public.pachanga_groups
  where invite_token = token;

  if target_group_id is null then
    raise exception 'Invalid invite token';
  end if;

  insert into public.pachanga_group_members (group_id, user_id)
  values (target_group_id, current_user_id)
  on conflict (group_id, user_id) do nothing;

  return target_group_id;
end;
$$;

create or replace function public.join_pachanga_team(token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select id into target_group_id
  from public.pachanga_groups
  where invite_token = token;

  if target_group_id is null then
    raise exception 'Invalid invite token';
  end if;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (target_group_id, current_user_id, 'player', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update
    set display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  return target_group_id;
end;
$$;

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

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can invite admins';
  end if;

  insert into public.pachanga_admin_invites (group_id, created_by)
  values (target_group_id, current_user_id)
  returning token into created_token;

  return created_token;
end;
$$;

create or replace function public.accept_pachanga_admin_invite(admin_token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select group_id into target_group_id
  from public.pachanga_admin_invites invites
  where invites.token = admin_token
    and invites.accepted_at is null
    and invites.expires_at > now();

  if target_group_id is null then
    raise exception 'Invalid admin invite';
  end if;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (target_group_id, current_user_id, 'admin', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update
    set role = case
        when public.pachanga_group_members.role = 'owner' then 'owner'
        else 'admin'
      end,
      display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  update public.pachanga_admin_invites
  set accepted_by = current_user_id,
      accepted_at = now()
  where public.pachanga_admin_invites.token = admin_token
    and public.pachanga_admin_invites.accepted_at is null;

  return target_group_id;
end;
$$;

revoke all on function public.join_pachanga_group(uuid) from public;
revoke execute on function public.join_pachanga_group(uuid) from anon;
grant execute on function public.join_pachanga_group(uuid) to authenticated;
revoke all on function public.join_pachanga_team(uuid, text) from public;
revoke execute on function public.join_pachanga_team(uuid, text) from anon;
grant execute on function public.join_pachanga_team(uuid, text) to authenticated;
revoke all on function public.create_pachanga_admin_invite(uuid) from public;
revoke execute on function public.create_pachanga_admin_invite(uuid) from anon;
grant execute on function public.create_pachanga_admin_invite(uuid) to authenticated;
revoke all on function public.accept_pachanga_admin_invite(uuid, text) from public;
revoke execute on function public.accept_pachanga_admin_invite(uuid, text) from anon;
grant execute on function public.accept_pachanga_admin_invite(uuid, text) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_groups'
  ) then
    alter publication supabase_realtime add table public.pachanga_groups;
  end if;
end;
$$;
