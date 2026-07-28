create table if not exists public.pachanga_groups (
  id uuid primary key default gen_random_uuid(),
  invite_token uuid not null unique default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Equipo pachanguero',
  team_code text unique,
  payload jsonb not null,
  payload_revision bigint not null default 0,
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

alter table public.pachanga_groups
add column if not exists payload_revision bigint not null default 0;

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

create index if not exists pachanga_group_backups_owner_id_idx
on public.pachanga_group_backups(owner_id);

create index if not exists pachanga_group_backups_created_by_idx
on public.pachanga_group_backups(created_by);

create index if not exists pachanga_group_backups_source_group_id_idx
on public.pachanga_group_backups(source_group_id);

create index if not exists pachanga_group_backups_created_at_idx
on public.pachanga_group_backups(created_at desc);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.pachanga_groups to authenticated;
grant select, insert, update on public.pachanga_group_members to authenticated;
grant select, insert, update on public.pachanga_admin_invites to authenticated;
grant select on public.pachanga_group_backups to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  new.payload_revision = coalesce(old.payload_revision, 0) + 1;
  return new;
end;
$$;

create or replace function public.is_registered_pachanga_user()
returns boolean
language sql
set search_path = public
stable
as $$
  select (select auth.uid()) is not null
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false;
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
alter table public.pachanga_group_backups enable row level security;

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

drop policy if exists "Members can update groups" on public.pachanga_groups;
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

drop policy if exists "Owners can delete groups" on public.pachanga_groups;
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
drop policy if exists "Owners can update member roles" on public.pachanga_group_members;
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

drop policy if exists "Users can read recoverable backups" on public.pachanga_group_backups;
create policy "Users can read recoverable backups"
on public.pachanga_group_backups
for select
to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and (
    owner_id = (select auth.uid())
    or created_by = (select auth.uid())
    or (
      source_group_id is not null
      and public.is_pachanga_group_admin(source_group_id)
    )
  )
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
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
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
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
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
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
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
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
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

create or replace function public.update_pachanga_member_name(target_group_id uuid, member_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  next_name text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  next_name := nullif(trim(member_name), '');
  if next_name is null then
    raise exception 'Member name required';
  end if;

  update public.pachanga_group_members
  set display_name = next_name
  where group_id = target_group_id
    and user_id = current_user_id;

  if not found then
    raise exception 'Current user is not a member of this group';
  end if;

  return next_name;
end;
$$;

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

  if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'Registered user required';
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

  if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'Registered user required';
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

create or replace function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can save the full team state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  update public.pachanga_groups
  set payload = next_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
end;
$$;

create or replace function public.patch_pachanga_match_player_status(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_match jsonb;
  existing_entry jsonb;
  next_entry jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
  is_finalized boolean;
  was_confirmed boolean;
  will_confirmed boolean;
  previous_goals integer;
  direction integer;
  score_a integer;
  score_b integer;
  winning_ids text[];
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if next_status not in ('voy', 'duda', 'no') then
    raise exception 'Invalid status';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only change your own attendance';
  end if;

  if next_status = 'voy'
    and (
      coalesce((selected_player ->> 'injured')::boolean, false)
      or coalesce((selected_player ->> 'inactive')::boolean, false)
    )
  then
    raise exception 'This player cannot attend';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing attendance';
  end if;

  is_finalized := coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA';
  if is_finalized and not is_admin then
    raise exception 'Only admins can edit a finalized match';
  end if;

  select value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as value
  where value ->> 'playerId' = target_player_id
  limit 1;

  was_confirmed := existing_entry ->> 'status' = 'voy';
  will_confirmed := next_status = 'voy';

  next_entry := jsonb_build_object(
    'playerId', target_player_id,
    'status', next_status,
    'paid', case when next_status = 'voy' then coalesce((existing_entry ->> 'paid')::boolean, false) else false end
  );

  if next_status = 'voy' then
    next_entry := next_entry || jsonb_build_object(
      'joinedAt',
      coalesce(
        case when existing_entry ->> 'status' = 'voy' then existing_entry ->> 'joinedAt' else null end,
        to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
    );
  end if;

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case when value ->> 'playerId' = target_player_id then next_entry else value end
      order by ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  previous_goals := coalesce((
    select (value ->> 'goals')::integer
    from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as value
    where value ->> 'playerId' = target_player_id
    limit 1
  ), 0);

  if is_finalized and was_confirmed and not will_confirmed then
    next_match := jsonb_set(
      next_match,
      '{scorers}',
      coalesce((
        select jsonb_agg(value)
        from jsonb_array_elements(coalesce(next_match -> 'scorers', '[]'::jsonb)) as value
        where value ->> 'playerId' <> target_player_id
      ), '[]'::jsonb),
      true
    );
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if is_finalized and was_confirmed <> will_confirmed then
    direction := case when will_confirmed then 1 else -1 end;
    score_a := coalesce((selected_match ->> 'scoreA')::integer, 0);
    score_b := coalesce((selected_match ->> 'scoreB')::integer, 0);
    winning_ids := case
      when score_a = score_b then array[]::text[]
      when score_a > score_b then array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamA', '[]'::jsonb)))
      else array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamB', '[]'::jsonb)))
    end;

    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then
          value || jsonb_build_object(
            'appearances', greatest(0, coalesce((value ->> 'appearances')::integer, 0) + direction),
            'goals', greatest(0, coalesce((value ->> 'goals')::integer, 0) + (direction * previous_goals)),
            'wins', greatest(0, coalesce((value ->> 'wins')::integer, 0) + case when target_player_id = any(winning_ids) then direction else 0 end)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_match_player_paid(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_match jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only mark your own payment';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing payments';
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'playerId' = target_player_id and value ->> 'status' = 'voy' then value || jsonb_build_object('paid', coalesce(next_paid, false))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_match_players
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_match_scorers(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  next_scorers jsonb,
  target_team_a_ids text[],
  target_team_b_ids text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_match jsonb;
  sanitized_scorers jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  score_a integer;
  score_b integer;
  team_a_total integer;
  team_b_total integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can edit scorers';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before editing scorers';
  end if;

  score_a := coalesce((selected_match ->> 'scoreA')::integer, target_score_a);
  score_b := coalesce((selected_match ->> 'scoreB')::integer, target_score_b);
  if score_a is null or score_b is null or score_a < 0 or score_b < 0 then
    raise exception 'Fill the score before editing scorers';
  end if;

  with scorer_rows as (
    select
      value ->> 'playerId' as player_id,
      greatest(0, coalesce((value ->> 'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(next_scorers, '[]'::jsonb)) as value
  ),
  grouped as (
    select player_id, sum(goals)::integer as goals
    from scorer_rows
    where player_id is not null and goals > 0
    group by player_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('playerId', player_id, 'goals', goals)), '[]'::jsonb)
  into sanitized_scorers
  from grouped;

  if exists (
    select 1
    from jsonb_array_elements(sanitized_scorers) as value
    where not ((value ->> 'playerId') = any(coalesce(target_team_a_ids, array[]::text[]))
      or (value ->> 'playerId') = any(coalesce(target_team_b_ids, array[]::text[])))
  ) then
    raise exception 'Scorer is not in the current lineups';
  end if;

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_a_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_a_ids, array[]::text[]));

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_b_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_b_ids, array[]::text[]));

  if team_a_total > score_a or team_b_total > score_b then
    raise exception 'Scorers exceed the match score';
  end if;

  next_match := jsonb_set(selected_match, '{scorers}', sanitized_scorers, true);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    select coalesce(jsonb_agg(
      value || jsonb_build_object(
        'goals',
        greatest(0,
          coalesce((value ->> 'goals')::integer, 0)
          - coalesce((
              select (old_scorer ->> 'goals')::integer
              from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as old_scorer
              where old_scorer ->> 'playerId' = value ->> 'id'
              limit 1
            ), 0)
          + coalesce((
              select (new_scorer ->> 'goals')::integer
              from jsonb_array_elements(sanitized_scorers) as new_scorer
              where new_scorer ->> 'playerId' = value ->> 'id'
              limit 1
            ), 0)
        )
      )
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  patched_player jsonb;
  next_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
  patch_injured boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only edit your own player profile';
  end if;

  patched_player := selected_player;

  if player_patch ? 'name' then
    patched_player := patched_player || jsonb_build_object('name', nullif(trim(player_patch ->> 'name'), ''));
  end if;

  if player_patch ? 'phone' then
    patched_player := patched_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'birthDate' then
    patched_player := patched_player || jsonb_build_object('birthDate', nullif(player_patch ->> 'birthDate', ''));
  end if;

  if player_patch ? 'avatar' then
    patched_player := patched_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    patched_player := patched_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    patch_injured := coalesce((player_patch ->> 'injured')::boolean, false);
    patched_player := patched_player || jsonb_build_object('injured', patch_injured);
  end if;

  if player_patch ? 'position' then
    patched_player := patched_player || jsonb_build_object('position', nullif(player_patch ->> 'position', ''));
  end if;

  if player_patch ? 'outfieldPosition' then
    patched_player := patched_player || jsonb_build_object('outfieldPosition', nullif(player_patch ->> 'outfieldPosition', ''));
  end if;

  if player_patch ? 'goals' then
    patched_player := patched_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if is_admin and player_patch ? 'rating' then
    patched_player := patched_player || jsonb_build_object('rating', greatest(1, least(10, coalesce((player_patch ->> 'rating')::numeric, 5))));
  end if;

  if is_admin and player_patch ? 'inactive' then
    patched_player := patched_player || jsonb_build_object('inactive', coalesce((player_patch ->> 'inactive')::boolean, false));
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_player_id then patched_player else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_matches := current_payload -> 'matches';

  if patch_injured then
    select coalesce(jsonb_agg(
      case
        when not (coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA') then
          value || jsonb_build_object(
            'players',
            coalesce((
              select jsonb_agg(
                case
                  when entry ->> 'playerId' = target_player_id then
                    jsonb_build_object('playerId', target_player_id, 'status', 'no', 'paid', false)
                  else entry
                end
                order by entry_ordinality
              )
              from jsonb_array_elements(coalesce(value -> 'players', '[]'::jsonb)) with ordinality as match_entries(entry, entry_ordinality)
            ), '[]'::jsonb)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players, 'matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.append_pachanga_player_rating(
  target_group_id uuid,
  target_player_id text,
  vote_facets jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_member_name text;
  clean_facets jsonb;
  last_vote_match_count integer;
  player_appearances integer;
  next_vote jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only members can rate players';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') = current_user_id::text then
    raise exception 'You cannot rate yourself';
  end if;

  if coalesce((selected_player ->> 'inactive')::boolean, false) then
    raise exception 'Inactive players cannot be rated';
  end if;

  player_appearances := greatest(0, coalesce((selected_player ->> 'appearances')::integer, 0));

  select max(greatest(0, coalesce((vote.value ->> 'matchCount')::integer, 0)))
  into last_vote_match_count
  from jsonb_array_elements(coalesce(selected_player -> 'ratingVotes', '[]'::jsonb)) as vote(value)
  where vote.value ->> 'voterId' = current_user_id::text;

  if player_appearances < coalesce(last_vote_match_count + 3, 3) then
    raise exception 'Rating window closed for this player';
  end if;

  select display_name into selected_member_name
  from public.pachanga_group_members
  where group_id = target_group_id
    and user_id = current_user_id;

  clean_facets := jsonb_build_object(
    'ritmo', greatest(1, least(10, coalesce((vote_facets ->> 'ritmo')::numeric, 5))),
    'tiro', greatest(1, least(10, coalesce((vote_facets ->> 'tiro')::numeric, 5))),
    'pase', greatest(1, least(10, coalesce((vote_facets ->> 'pase')::numeric, 5))),
    'regate', greatest(1, least(10, coalesce((vote_facets ->> 'regate')::numeric, 5))),
    'defensa', greatest(1, least(10, coalesce((vote_facets ->> 'defensa')::numeric, 5))),
    'fisico', greatest(1, least(10, coalesce((vote_facets ->> 'fisico')::numeric, 5)))
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', selected_member_name,
    'ratingRole',
      case
        when coalesce((selected_player ->> 'goalkeeperOnly')::boolean, false)
          or coalesce(selected_player ->> 'position', '') in ('Portero', 'Porteria')
        then 'goalkeeper'
        else 'field'
      end,
    'matchCount', player_appearances,
    'createdAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'facets', clean_facets
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then
        value || jsonb_build_object('ratingVotes', coalesce(value -> 'ratingVotes', '[]'::jsonb) || jsonb_build_array(next_vote))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
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
revoke all on function public.update_pachanga_member_name(uuid, text) from public;
revoke execute on function public.update_pachanga_member_name(uuid, text) from anon;
grant execute on function public.update_pachanga_member_name(uuid, text) to authenticated;
revoke all on function public.create_pachanga_group_backup(uuid, text, jsonb) from public;
revoke execute on function public.create_pachanga_group_backup(uuid, text, jsonb) from anon;
grant execute on function public.create_pachanga_group_backup(uuid, text, jsonb) to authenticated;
revoke all on function public.restore_pachanga_group_backup(uuid) from public;
revoke execute on function public.restore_pachanga_group_backup(uuid) from anon;
grant execute on function public.restore_pachanga_group_backup(uuid) to authenticated;
revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from public;
revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from anon;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
revoke all on function public.patch_pachanga_match_player_status(uuid, text, text, text) from public;
revoke execute on function public.patch_pachanga_match_player_status(uuid, text, text, text) from anon;
grant execute on function public.patch_pachanga_match_player_status(uuid, text, text, text) to authenticated;
revoke all on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from public;
revoke execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from anon;
grant execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) to authenticated;
revoke all on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) from public;
revoke execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) from anon;
grant execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) to authenticated;
revoke all on function public.patch_pachanga_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.append_pachanga_player_rating(uuid, text, jsonb) from public;
revoke execute on function public.append_pachanga_player_rating(uuid, text, jsonb) from anon;
grant execute on function public.append_pachanga_player_rating(uuid, text, jsonb) to authenticated;

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
