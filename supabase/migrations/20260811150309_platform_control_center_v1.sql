-- Pachangas IQ Platform Control Center V1.
-- Global platform authority is deliberately separate from team ownership.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create sequence if not exists private.pachanga_platform_admin_sequence;
revoke all on sequence private.pachanga_platform_admin_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_platform_admin_sequence to service_role;

create table if not exists private.pachanga_platform_admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null,
  active boolean not null default true,
  granted_at timestamptz not null default clock_timestamp(),
  granted_by uuid references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  updated_at timestamptz not null default clock_timestamp(),
  check (role in ('platform_owner', 'platform_admin', 'moderator', 'support', 'finance', 'ops')),
  check (revision >= 1)
);

create table if not exists private.pachanga_platform_user_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active',
  reason text,
  expires_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_platform_admin_sequence'),
  auth_sync_state text not null default 'pending',
  auth_synced_at timestamptz,
  auth_sync_error text,
  updated_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'suspended', 'banned')),
  check (revision >= 1),
  check (auth_sync_state in ('pending', 'confirmed', 'error')),
  check (auth_sync_error is null or char_length(auth_sync_error) <= 240),
  check (
    (status = 'active' and expires_at is null)
    or (status = 'suspended' and expires_at is not null)
    or status = 'banned'
  )
);

create table if not exists private.pachanga_platform_admin_action_ledger (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_user_id uuid references auth.users(id) on delete restrict,
  actor_role text not null,
  action text not null,
  target_type text not null,
  target_id text not null,
  reason text not null,
  before_state jsonb not null default '{}'::jsonb,
  after_state jsonb not null default '{}'::jsonb,
  response jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('private.pachanga_platform_admin_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (actor_role in (
    'service_bootstrap', 'platform_owner', 'platform_admin', 'moderator', 'support', 'finance', 'ops'
  )),
  check (char_length(action) between 3 and 120),
  check (char_length(target_type) between 2 and 80),
  check (char_length(target_id) between 1 and 240),
  check (char_length(reason) between 3 and 1200),
  check (jsonb_typeof(before_state) = 'object'),
  check (jsonb_typeof(after_state) = 'object'),
  check (jsonb_typeof(response) = 'object')
);

create unique index if not exists pachanga_platform_admin_ledger_sequence_idx
  on private.pachanga_platform_admin_action_ledger(server_sequence);
create index if not exists pachanga_platform_admin_ledger_target_idx
  on private.pachanga_platform_admin_action_ledger(target_type, target_id, server_sequence desc);
create index if not exists pachanga_platform_admin_ledger_actor_idx
  on private.pachanga_platform_admin_action_ledger(actor_user_id, server_sequence desc);
create index if not exists pachanga_platform_user_states_status_idx
  on private.pachanga_platform_user_states(status, expires_at, server_sequence desc);

revoke all on table private.pachanga_platform_admin_roles from public, anon, authenticated;
revoke all on table private.pachanga_platform_user_states from public, anon, authenticated;
revoke all on table private.pachanga_platform_admin_action_ledger from public, anon, authenticated;
grant all on table private.pachanga_platform_admin_roles to service_role;
grant all on table private.pachanga_platform_user_states to service_role;
grant all on table private.pachanga_platform_admin_action_ledger to service_role;

create or replace function private.pachanga_platform_admin_replay_v1(
  requested_operation_id uuid,
  expected_action text,
  expected_target_type text,
  expected_target_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved private.pachanga_platform_admin_action_ledger%rowtype;
begin
  if requested_operation_id is null then raise exception 'operationId required'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('platform-admin-operation:' || requested_operation_id::text, 0)
  );
  select * into saved
  from private.pachanga_platform_admin_action_ledger ledger
  where ledger.operation_id = requested_operation_id;
  if not found then return null; end if;
  if saved.action <> expected_action
    or saved.target_type <> expected_target_type
    or (expected_target_id is not null and saved.target_id <> expected_target_id) then
    raise exception 'operationId already belongs to a different platform action';
  end if;
  return saved.response;
end;
$$;

revoke all on function private.pachanga_platform_admin_replay_v1(uuid, text, text, text)
  from public, anon, authenticated;

create or replace function private.pachanga_platform_sanitize_error_v1(source_error text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  sanitized text := source_error;
begin
  if sanitized is null then return null; end if;
  sanitized := regexp_replace(sanitized, '(sk|rk|pk)_(live|test)_[A-Za-z0-9_]+', '[redacted-key]', 'gi');
  sanitized := regexp_replace(sanitized, 'Bearer[[:space:]]+[A-Za-z0-9._~-]+', 'Bearer [redacted]', 'gi');
  sanitized := regexp_replace(sanitized, '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[redacted-email]', 'gi');
  sanitized := regexp_replace(sanitized, '([?&](token|key|secret)=)[^&[:space:]]+', '\1[redacted]', 'gi');
  return left(sanitized, 240);
end;
$$;

revoke all on function private.pachanga_platform_sanitize_error_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_platform_role_for_user_v1(target_user_id uuid)
returns text
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select roles.role
  from private.pachanga_platform_admin_roles roles
  where roles.user_id = target_user_id
    and roles.active
    and not exists (
      select 1
      from private.pachanga_platform_user_states states
      where states.user_id = roles.user_id
        and (
          states.status = 'banned'
          or (states.status = 'suspended' and states.expires_at > statement_timestamp())
        )
    )
  limit 1;
$$;

revoke all on function private.pachanga_platform_role_for_user_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_platform_require_v1(required_capability text)
returns text
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  capabilities jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  actor_role := private.pachanga_platform_role_for_user_v1(actor_id);
  if actor_role is null then
    raise exception 'Platform access required' using errcode = '42501';
  end if;
  capabilities := private.pachanga_platform_capabilities_v1(actor_role);
  if not (capabilities ? required_capability) then
    raise exception 'Platform capability required: %', required_capability using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

revoke all on function private.pachanga_platform_require_v1(text)
  from public, anon, authenticated;

create or replace function public.get_my_pachanga_platform_access_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  actor_role := private.pachanga_platform_role_for_user_v1(actor_id);
  if actor_role is null then
    raise exception 'Platform access required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'userId', actor_id,
    'role', actor_role,
    'capabilities', private.pachanga_platform_capabilities_v1(actor_role),
    'revision', (
      select roles.revision from private.pachanga_platform_admin_roles roles
      where roles.user_id = actor_id
    )
  );
end;
$$;

revoke all on function public.get_my_pachanga_platform_access_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_platform_access_v1() to authenticated;

create or replace function public.get_pachanga_platform_access_service_v1(target_user_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected_role private.pachanga_platform_admin_roles%rowtype;
  effective_role text;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  effective_role := private.pachanga_platform_role_for_user_v1(target_user_id);
  if effective_role is null then return null; end if;
  select * into selected_role
  from private.pachanga_platform_admin_roles roles
  where roles.user_id = target_user_id and roles.active and roles.role = effective_role;
  if not found then return null; end if;
  return jsonb_build_object(
    'userId', selected_role.user_id,
    'role', selected_role.role,
    'capabilities', private.pachanga_platform_capabilities_v1(selected_role.role),
    'revision', selected_role.revision
  );
end;
$$;

revoke all on function public.get_pachanga_platform_access_service_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_access_service_v1(uuid) to service_role;

create or replace function public.bootstrap_pachanga_platform_owner_v1(
  target_user_id uuid,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  prior jsonb;
  response jsonb;
  sequence_value bigint;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if target_user_id is null or operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'Target, operationId and reason required';
  end if;
  prior := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_owner.bootstrap', 'user', target_user_id::text
  );
  if prior is not null then return prior; end if;

  lock table private.pachanga_platform_admin_roles in share row exclusive mode;
  if not exists (select 1 from auth.users users where users.id = target_user_id) then
    raise exception 'User not found';
  end if;
  if exists (
    select 1 from private.pachanga_platform_admin_roles roles
    where roles.role = 'platform_owner' and roles.active
  ) then
    raise exception 'Platform owner already bootstrapped';
  end if;

  insert into private.pachanga_platform_admin_roles(user_id, role, active, granted_by)
  values (target_user_id, 'platform_owner', true, null)
  on conflict (user_id) do update set
    role = excluded.role,
    active = true,
    granted_by = null,
    granted_at = clock_timestamp(),
    revision = private.pachanga_platform_admin_roles.revision + 1,
    updated_at = clock_timestamp();

  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'userId', target_user_id,
    'role', 'platform_owner',
    'active', true,
    'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, null, 'service_bootstrap', 'platform_owner.bootstrap', 'user', target_user_id::text,
    trim(reason), '{}'::jsonb, response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.bootstrap_pachanga_platform_owner_v1(uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.bootstrap_pachanga_platform_owner_v1(uuid, uuid, text) to service_role;

create or replace function public.set_pachanga_platform_role_v1(
  target_user_id uuid,
  next_role text,
  next_active boolean,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  selected_role private.pachanga_platform_admin_roles%rowtype;
  before_snapshot jsonb := '{}'::jsonb;
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('roles.manage');
  if next_role not in ('platform_owner', 'platform_admin', 'moderator', 'support', 'finance', 'ops') then
    raise exception 'Invalid platform role';
  end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_role.set', 'user', target_user_id::text
  );
  if response is not null then return response; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('platform-role-target:' || target_user_id::text, 0)
  );

  if not exists (select 1 from auth.users users where users.id = target_user_id) then
    raise exception 'User not found';
  end if;
  select * into selected_role
  from private.pachanga_platform_admin_roles roles
  where roles.user_id = target_user_id
  for update;
  if found then
    before_snapshot := jsonb_build_object(
      'role', selected_role.role, 'active', selected_role.active, 'revision', selected_role.revision
    );
    if expected_revision is null or selected_role.revision <> expected_revision then
      raise exception 'Platform role changed before saving' using errcode = '40001';
    end if;
  elsif coalesce(expected_revision, 0) <> 0 then
    raise exception 'Platform role changed before saving' using errcode = '40001';
  end if;

  if found and selected_role.role = 'platform_owner' and selected_role.active
    and (not next_active or next_role <> 'platform_owner')
    and (select count(*) from private.pachanga_platform_admin_roles roles
         where roles.role = 'platform_owner' and roles.active) <= 1 then
    raise exception 'Cannot remove the last platform owner';
  end if;

  insert into private.pachanga_platform_admin_roles(
    user_id, role, active, granted_at, granted_by, revision, updated_at
  ) values (
    target_user_id, next_role, next_active, clock_timestamp(), actor_id, 1, clock_timestamp()
  ) on conflict (user_id) do update set
    role = excluded.role,
    active = excluded.active,
    granted_at = clock_timestamp(),
    granted_by = actor_id,
    revision = private.pachanga_platform_admin_roles.revision + 1,
    updated_at = clock_timestamp()
  returning * into selected_role;

  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'userId', selected_role.user_id,
    'role', selected_role.role,
    'active', selected_role.active,
    'revision', selected_role.revision,
    'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_role.set', 'user', target_user_id::text,
    trim(reason), before_snapshot, response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_role_v1(uuid, text, boolean, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_role_v1(uuid, text, boolean, bigint, uuid, text)
  to authenticated;

create or replace function public.set_pachanga_platform_user_state_v1(
  target_user_id uuid,
  next_status text,
  next_expires_at timestamptz,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  selected_state private.pachanga_platform_user_states%rowtype;
  before_snapshot jsonb := jsonb_build_object('status', 'active', 'revision', 0);
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('users.suspend');
  if next_status not in ('active', 'suspended', 'banned') then raise exception 'Invalid user status'; end if;
  if next_status = 'suspended' and (next_expires_at is null or next_expires_at <= clock_timestamp()) then
    raise exception 'A suspension needs a future expiry';
  end if;
  if next_status = 'active' then next_expires_at := null; end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  if target_user_id = actor_id and next_status <> 'active' then
    raise exception 'Administrators cannot suspend themselves';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_user_state.set', 'user', target_user_id::text
  );
  if response is not null then return response; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('platform-user-state-target:' || target_user_id::text, 0)
  );
  if not exists (select 1 from auth.users users where users.id = target_user_id) then
    raise exception 'User not found';
  end if;

  select * into selected_state
  from private.pachanga_platform_user_states states
  where states.user_id = target_user_id
  for update;
  if found then
    before_snapshot := jsonb_build_object(
      'status', selected_state.status,
      'expiresAt', selected_state.expires_at,
      'revision', selected_state.revision
    );
    if expected_revision is null or selected_state.revision <> expected_revision then
      raise exception 'User platform state changed before saving' using errcode = '40001';
    end if;
  elsif coalesce(expected_revision, 0) <> 0 then
    raise exception 'User platform state changed before saving' using errcode = '40001';
  end if;

  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  insert into private.pachanga_platform_user_states(
    user_id, status, reason, expires_at, revision, server_sequence,
    auth_sync_state, auth_synced_at, auth_sync_error, updated_by, updated_at
  ) values (
    target_user_id, next_status, trim(reason), next_expires_at, 1, sequence_value,
    'pending', null, null, actor_id, clock_timestamp()
  ) on conflict (user_id) do update set
    status = excluded.status,
    reason = excluded.reason,
    expires_at = excluded.expires_at,
    revision = private.pachanga_platform_user_states.revision + 1,
    server_sequence = sequence_value,
    auth_sync_state = 'pending',
    auth_synced_at = null,
    auth_sync_error = null,
    updated_by = actor_id,
    updated_at = clock_timestamp()
  returning * into selected_state;

  response := jsonb_build_object(
    'userId', selected_state.user_id,
    'status', selected_state.status,
    'expiresAt', selected_state.expires_at,
    'revision', selected_state.revision,
    'serverSequence', selected_state.server_sequence,
    'authSyncState', selected_state.auth_sync_state,
    'authSyncRequired', true
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_user_state.set', 'user', target_user_id::text,
    trim(reason), before_snapshot, response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_user_state_v1(uuid, text, timestamptz, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_user_state_v1(uuid, text, timestamptz, bigint, uuid, text)
  to authenticated;

create or replace function public.confirm_pachanga_platform_user_auth_sync_v1(
  source_operation_id uuid,
  sync_succeeded boolean,
  sanitized_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_user_id uuid;
  selected_state private.pachanga_platform_user_states%rowtype;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  select ledger.target_id::uuid into target_user_id
  from private.pachanga_platform_admin_action_ledger ledger
  where ledger.operation_id = source_operation_id
    and ledger.action = 'platform_user_state.set';
  if target_user_id is null then raise exception 'Platform state operation not found'; end if;

  update private.pachanga_platform_user_states states set
    auth_sync_state = case
      when states.auth_sync_state = 'confirmed' or sync_succeeded then 'confirmed'
      else 'error'
    end,
    auth_synced_at = case
      when states.auth_sync_state = 'confirmed' then states.auth_synced_at
      when sync_succeeded then clock_timestamp()
      else null
    end,
    auth_sync_error = case
      when states.auth_sync_state = 'confirmed' or sync_succeeded then null
      else left(nullif(trim(coalesce(sanitized_error, '')), ''), 240)
    end,
    updated_at = clock_timestamp()
  where states.user_id = target_user_id
  returning * into selected_state;

  return jsonb_build_object(
    'userId', selected_state.user_id,
    'status', selected_state.status,
    'revision', selected_state.revision,
    'authSyncState', selected_state.auth_sync_state,
    'authSyncedAt', selected_state.auth_synced_at
  );
end;
$$;

revoke all on function public.confirm_pachanga_platform_user_auth_sync_v1(uuid, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function public.confirm_pachanga_platform_user_auth_sync_v1(uuid, boolean, text)
  to service_role;

create or replace function public.get_pachanga_platform_user_summaries_v1(target_user_ids uuid[])
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  safe_ids uuid[] := coalesce(target_user_ids, '{}'::uuid[]);
begin
  perform private.pachanga_platform_require_v1('users.read');
  if cardinality(safe_ids) > 100 then raise exception 'Too many users requested'; end if;
  return coalesce((
    select jsonb_object_agg(users.id::text, jsonb_build_object(
      'status', coalesce(states.status, 'active'),
      'statusReason', states.reason,
      'statusExpiresAt', states.expires_at,
      'statusRevision', coalesce(states.revision, 0),
      'authSyncState', coalesce(states.auth_sync_state, 'confirmed'),
      'platformRole', roles.role,
      'platformRoleActive', coalesce(roles.active, false),
      'platformRoleRevision', coalesce(roles.revision, 0),
      'teamCount', (select count(*) from public.pachanga_group_members members where members.user_id = users.id),
      'ownedTeamCount', (select count(*) from public.pachanga_groups groups where groups.owner_id = users.id),
      'activeRestrictionCount', (select count(*) from private.pachanga_social_restrictions restrictions
        where restrictions.target_user_id = users.id and restrictions.state = 'active'
          and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp()))
    ))
    from auth.users users
    left join private.pachanga_platform_user_states states on states.user_id = users.id
    left join private.pachanga_platform_admin_roles roles on roles.user_id = users.id
    where users.id = any(safe_ids)
  ), '{}'::jsonb);
end;
$$;

revoke all on function public.get_pachanga_platform_user_summaries_v1(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_user_summaries_v1(uuid[]) to authenticated;

create or replace function public.list_pachanga_platform_users_v1(
  search_text text default '',
  status_filter text default 'all',
  created_from date default null,
  created_to date default null,
  sort_key text default 'created_desc',
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  actor_role text;
  can_read_pii boolean;
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  safe_status text := lower(coalesce(status_filter, 'all'));
  safe_sort text := lower(coalesce(sort_key, 'created_desc'));
  safe_size integer := least(greatest(coalesce(page_size, 30), 10), 100);
  safe_offset integer := greatest(coalesce(page_offset, 0), 0);
  result jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('users.read');
  can_read_pii := actor_role in ('platform_owner', 'platform_admin', 'support', 'finance');
  if safe_status not in ('all', 'active', 'suspended', 'banned')
    or safe_sort not in ('created_desc', 'created_asc', 'last_sign_in_desc', 'name_asc') then
    raise exception 'Invalid user status filter';
  end if;
  if created_from is not null and created_to is not null and created_from > created_to then
    raise exception 'Invalid user creation date range';
  end if;

  with filtered as materialized (
    select
      users.id,
      users.email,
      users.raw_user_meta_data,
      users.created_at,
      users.last_sign_in_at,
      profiles.id as profile_id,
      profiles.display_name,
      coalesce(
        nullif(trim(profiles.display_name), ''),
        nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
        case when can_read_pii then users.email else null end,
        'Usuario ' || left(users.id::text, 8)
      ) as resolved_name,
      coalesce(states.status, 'active') as platform_status,
      states.expires_at as status_expires_at,
      coalesce(states.revision, 0) as status_revision,
      coalesce(states.auth_sync_state, 'confirmed') as auth_sync_state,
      roles.role as platform_role
    from auth.users users
    left join public.pachanga_player_profiles profiles on profiles.user_id = users.id
    left join private.pachanga_platform_user_states states on states.user_id = users.id
    left join private.pachanga_platform_admin_roles roles on roles.user_id = users.id and roles.active
    where (safe_status = 'all' or coalesce(states.status, 'active') = safe_status)
      and (created_from is null or users.created_at::date >= created_from)
      and (created_to is null or users.created_at::date <= created_to)
      and (
        nullif(trim(coalesce(search_text, '')), '') is null
        or lower(coalesce(profiles.display_name, '')) like needle
        or lower(coalesce(users.raw_user_meta_data ->> 'full_name', '')) like needle
        or lower(coalesce(users.raw_user_meta_data ->> 'name', '')) like needle
        or users.id::text like needle
        or (can_read_pii and lower(coalesce(users.email, '')) like needle)
      )
  ), page_source as (
    select filtered.*,
      row_number() over (order by
        case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
        case when safe_sort = 'created_asc' then filtered.created_at end asc nulls last,
        case when safe_sort = 'last_sign_in_desc' then filtered.last_sign_in_at end desc nulls last,
        case when safe_sort = 'name_asc' then lower(filtered.resolved_name) end asc nulls last,
        filtered.id
      ) as sort_ordinal
    from filtered
    order by
      case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
      case when safe_sort = 'created_asc' then filtered.created_at end asc nulls last,
      case when safe_sort = 'last_sign_in_desc' then filtered.last_sign_in_at end desc nulls last,
      case when safe_sort = 'name_asc' then lower(filtered.resolved_name) end asc nulls last,
      filtered.id
    limit safe_size offset safe_offset
  ), paged as (
    select jsonb_build_object(
      'id', page_source.id,
      'name', page_source.resolved_name,
      'email', case when can_read_pii then page_source.email else null end,
      'createdAt', page_source.created_at,
      'lastSignInAt', page_source.last_sign_in_at,
      'profileId', page_source.profile_id,
      'status', page_source.platform_status,
      'statusExpiresAt', page_source.status_expires_at,
      'statusRevision', page_source.status_revision,
      'authSyncState', page_source.auth_sync_state,
      'platformRole', page_source.platform_role,
      'teamCount', (select count(*) from public.pachanga_group_members members where members.user_id = page_source.id),
      'ownedTeamCount', (select count(*) from public.pachanga_groups groups where groups.owner_id = page_source.id),
      'activeRestrictionCount', (select count(*) from private.pachanga_social_restrictions restrictions
        where restrictions.target_user_id = page_source.id
          and restrictions.state = 'active'
          and (restrictions.effective_until is null or restrictions.effective_until > statement_timestamp()))
    ) as item,
    page_source.sort_ordinal
    from page_source
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(paged.item order by paged.sort_ordinal) from paged), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_pachanga_platform_users_v1(text, text, date, date, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.list_pachanga_platform_users_v1(text, text, date, date, text, integer, integer)
  to authenticated;

create or replace function public.list_pachanga_platform_teams_v1(
  search_text text default '',
  billing_filter text default 'all',
  market_filter text default 'all',
  locality_filter text default '',
  owner_filter uuid default null,
  activity_filter text default 'all',
  social_filter text default 'all',
  minimum_level numeric default null,
  maximum_level numeric default null,
  created_from date default null,
  created_to date default null,
  sort_key text default 'updated_desc',
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  locality_needle text := '%' || lower(trim(coalesce(locality_filter, ''))) || '%';
  safe_billing text := lower(coalesce(billing_filter, 'all'));
  safe_market text := lower(coalesce(market_filter, 'all'));
  safe_activity text := lower(coalesce(activity_filter, 'all'));
  safe_social text := lower(coalesce(social_filter, 'all'));
  safe_sort text := lower(coalesce(sort_key, 'updated_desc'));
  safe_size integer := least(greatest(coalesce(page_size, 30), 10), 100);
  safe_offset integer := greatest(coalesce(page_offset, 0), 0);
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('teams.read');
  if safe_billing not in ('all', 'trial', 'trialing', 'active', 'past_due', 'unpaid', 'incomplete', 'canceled')
    or safe_market not in ('all', 'enabled', 'disabled')
    or safe_activity not in ('all', 'active', 'inactive')
    or safe_social not in ('all', 'restricted', 'clean')
    or safe_sort not in ('updated_desc', 'created_desc', 'name_asc', 'level_desc') then
    raise exception 'Invalid team filter';
  end if;
  if minimum_level is not null and (minimum_level < 0 or minimum_level > 100) then
    raise exception 'Invalid minimum level';
  end if;
  if maximum_level is not null and (maximum_level < 0 or maximum_level > 100) then
    raise exception 'Invalid maximum level';
  end if;
  if minimum_level is not null and maximum_level is not null and minimum_level > maximum_level then
    raise exception 'Invalid level range';
  end if;
  if created_from is not null and created_to is not null and created_from > created_to then
    raise exception 'Invalid team creation date range';
  end if;

  with member_stats as materialized (
    select
      members.group_id,
      count(*)::integer as member_count,
      count(distinct restrictions.target_user_id)::integer as active_restriction_count
    from public.pachanga_group_members members
    left join private.pachanga_social_restrictions restrictions
      on restrictions.target_user_id = members.user_id
      and restrictions.state = 'active'
      and (restrictions.effective_until is null or restrictions.effective_until > statement_timestamp())
    group by members.group_id
  ), filtered as materialized (
    select
      groups.id,
      groups.owner_id,
      groups.name,
      groups.team_code,
      groups.billing_status,
      groups.billing_interval,
      groups.billing_trial_finalized_matches,
      groups.created_at,
      groups.updated_at,
      groups.ratings_enabled,
      groups.externally_calibrated_level,
      coalesce(owner_profile.display_name, 'Owner') as owner_name,
      coalesce(member_stats.member_count, 0) as member_count,
      coalesce(member_stats.active_restriction_count, 0) as active_restriction_count,
      market.enabled as market_enabled,
      market.zone_label,
      market.min_opponent_level,
      market.max_opponent_level,
      market.modalities,
      market.revision as market_revision
    from public.pachanga_groups groups
    left join member_stats on member_stats.group_id = groups.id
    left join public.pachanga_challengeable_team_profiles market on market.group_id = groups.id
    left join lateral (
      select profiles.display_name
      from public.pachanga_player_profiles profiles
      where profiles.user_id = groups.owner_id
      order by profiles.updated_at desc, profiles.id
      limit 1
    ) owner_profile on true
    where (safe_billing = 'all' or groups.billing_status = safe_billing)
      and (safe_market = 'all'
        or (safe_market = 'enabled' and coalesce(market.enabled, false))
        or (safe_market = 'disabled' and not coalesce(market.enabled, false)))
      and (safe_activity = 'all'
        or (safe_activity = 'active' and coalesce(member_stats.member_count, 0) > 0)
        or (safe_activity = 'inactive' and coalesce(member_stats.member_count, 0) = 0))
      and (safe_social = 'all'
        or (safe_social = 'restricted' and coalesce(member_stats.active_restriction_count, 0) > 0)
        or (safe_social = 'clean' and coalesce(member_stats.active_restriction_count, 0) = 0))
      and (owner_filter is null or groups.owner_id = owner_filter)
      and (created_from is null or groups.created_at::date >= created_from)
      and (created_to is null or groups.created_at::date <= created_to)
      and (nullif(trim(coalesce(locality_filter, '')), '') is null
        or lower(coalesce(market.zone_label, '')) like locality_needle)
      and (minimum_level is null
        or (groups.externally_calibrated_level is not null and groups.externally_calibrated_level >= minimum_level))
      and (maximum_level is null
        or (groups.externally_calibrated_level is not null and groups.externally_calibrated_level <= maximum_level))
      and (
        nullif(trim(coalesce(search_text, '')), '') is null
        or lower(groups.name) like needle
        or lower(coalesce(groups.team_code, '')) like needle
        or lower(coalesce(owner_profile.display_name, '')) like needle
        or groups.id::text like needle
      )
  ), page_source as (
    select filtered.*,
      row_number() over (order by
        case when safe_sort = 'name_asc' then lower(filtered.name) end asc nulls last,
        case when safe_sort = 'level_desc' then filtered.externally_calibrated_level end desc nulls last,
        case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
        case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
        filtered.id
      ) as sort_ordinal
    from filtered
    order by
      case when safe_sort = 'name_asc' then lower(filtered.name) end asc nulls last,
      case when safe_sort = 'level_desc' then filtered.externally_calibrated_level end desc nulls last,
      case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
      case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
      filtered.id
    limit safe_size offset safe_offset
  ), paged as (
    select jsonb_build_object(
      'id', page_source.id,
      'ownerId', page_source.owner_id,
      'ownerName', page_source.owner_name,
      'name', page_source.name,
      'teamCode', page_source.team_code,
      'billingStatus', page_source.billing_status,
      'billingInterval', page_source.billing_interval,
      'billingTrialFinalizedMatches', page_source.billing_trial_finalized_matches,
      'createdAt', page_source.created_at,
      'updatedAt', page_source.updated_at,
      'ratingsEnabled', page_source.ratings_enabled,
      'level', page_source.externally_calibrated_level,
      'active', page_source.member_count > 0,
      'memberCount', page_source.member_count,
      'activeRestrictionCount', page_source.active_restriction_count,
      'market', case when page_source.market_revision is null then null else jsonb_build_object(
        'enabled', page_source.market_enabled,
        'zoneLabel', page_source.zone_label,
        'minOpponentLevel', page_source.min_opponent_level,
        'maxOpponentLevel', page_source.max_opponent_level,
        'modalities', page_source.modalities,
        'revision', page_source.market_revision
      ) end
    ) as item, page_source.sort_ordinal
    from page_source
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(paged.item order by paged.sort_ordinal) from paged), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_pachanga_platform_teams_v1(
  text, text, text, text, uuid, text, text, numeric, numeric, date, date, text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.list_pachanga_platform_teams_v1(
  text, text, text, text, uuid, text, text, numeric, numeric, date, date, text, integer, integer
) to authenticated;

create or replace function public.list_pachanga_platform_matches_v1(
  search_text text default '',
  team_filter uuid default null,
  date_from date default null,
  date_to date default null,
  type_filter text default 'all',
  scope_filter text default 'all',
  state_filter text default 'all',
  sort_key text default 'date_asc',
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  safe_type text := lower(coalesce(type_filter, 'all'));
  safe_scope text := lower(coalesce(scope_filter, 'all'));
  safe_state text := lower(coalesce(state_filter, 'all'));
  safe_sort text := lower(coalesce(sort_key, 'date_asc'));
  safe_size integer := least(greatest(coalesce(page_size, 30), 10), 100);
  safe_offset integer := greatest(coalesce(page_offset, 0), 0);
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('matches.read');
  if safe_type not in ('all', 'sala', 'futbol7', 'futbol11')
    or safe_scope not in ('all', 'internal', 'challenge')
    or safe_sort not in ('date_asc', 'date_desc', 'updated_desc', 'state_asc')
    or safe_state not in (
      'all', 'draft', 'published', 'lineup_open', 'lineup_closed', 'played',
      'finalized', 'historical', 'pending_rival', 'change_proposed',
      'needs_scorer_fix', 'confirmed', 'auto_confirmed', 'disputed',
      'unverified', 'annulled', 'cancelled'
    ) then
    raise exception 'Invalid match filter';
  end if;
  if date_from is not null and date_to is not null and date_from > date_to then
    raise exception 'Invalid match date range';
  end if;

  with internal_matches as (
    select
      'internal'::text as scope,
      matches.group_id,
      null::uuid as secondary_group_id,
      matches.match_id,
      null::uuid as challenge_id,
      coalesce(nullif(metadata.item ->> 'title', ''), 'Partido ' || matches.match_id) as title,
      coalesce(
        nullif(metadata.item ->> 'kind', ''),
        nullif(metadata.item ->> 'modality', ''),
        nullif(metadata.item ->> 'format', '')
      ) as modality,
      case
        when lower(coalesce(metadata.item ->> 'kind', metadata.item ->> 'modality', metadata.item ->> 'format', ''))
          in ('sala', 'futbol sala', 'fútbol sala', '5v5') then 'sala'
        when lower(coalesce(metadata.item ->> 'kind', metadata.item ->> 'modality', metadata.item ->> 'format', ''))
          in ('futbol7', 'futbol 7', 'fútbol 7', '7v7') then 'futbol7'
        when lower(coalesce(metadata.item ->> 'kind', metadata.item ->> 'modality', metadata.item ->> 'format', ''))
          in ('futbol11', 'futbol 11', 'fútbol 11', '11v11') then 'futbol11'
        else lower(coalesce(metadata.item ->> 'kind', metadata.item ->> 'modality', metadata.item ->> 'format', ''))
      end as normalized_modality,
      nullif(metadata.item ->> 'place', '') as place,
      case
        when coalesce(metadata.item ->> 'date', '') ~ '^\d{4}-\d{2}-\d{2}'
          then substring(metadata.item ->> 'date' from 1 for 10)::date
        else null
      end as match_date,
      matches.match_state as state,
      matches.match_version as revision,
      matches.lineup_closed,
      matches.score_a,
      matches.score_b,
      matches.updated_at,
      groups.name as group_name,
      groups.team_code,
      null::text as secondary_group_name,
      null::text as secondary_team_code
    from public.pachanga_match_read_model matches
    join public.pachanga_groups groups on groups.id = matches.group_id
    left join lateral (
      select entry.item
      from jsonb_array_elements(
        case when jsonb_typeof(groups.payload -> 'matches') = 'array'
          then groups.payload -> 'matches' else '[]'::jsonb end
      ) entry(item)
      where entry.item ->> 'id' = matches.match_id
      limit 1
    ) metadata on true
  ), challenge_matches as (
    select
      'challenge'::text as scope,
      matches.home_group_id as group_id,
      matches.away_group_id as secondary_group_id,
      matches.id::text as match_id,
      matches.challenge_id,
      home.name || ' vs ' || away.name as title,
      matches.modality,
      matches.modality as normalized_modality,
      nullif(matches.field_snapshot ->> 'name', '') as place,
      matches.scheduled_at::date as match_date,
      matches.state,
      matches.revision,
      matches.state in ('confirmed', 'auto_confirmed', 'annulled', 'cancelled') as lineup_closed,
      matches.canonical_score_home as score_a,
      matches.canonical_score_away as score_b,
      matches.updated_at,
      home.name as group_name,
      home.team_code,
      away.name as secondary_group_name,
      away.team_code as secondary_team_code
    from public.pachanga_external_matches matches
    join public.pachanga_groups home on home.id = matches.home_group_id
    join public.pachanga_groups away on away.id = matches.away_group_id
  ), combined as materialized (
    select * from internal_matches where safe_scope in ('all', 'internal')
    union all
    select * from challenge_matches where safe_scope in ('all', 'challenge')
  ), filtered as materialized (
    select combined.*
    from combined
    where (team_filter is null or combined.group_id = team_filter or combined.secondary_group_id = team_filter)
      and (date_from is null or combined.match_date >= date_from)
      and (date_to is null or combined.match_date <= date_to)
      and (safe_type = 'all' or combined.normalized_modality = safe_type)
      and (safe_state = 'all' or combined.state = safe_state)
      and (
        nullif(trim(coalesce(search_text, '')), '') is null
        or lower(combined.title) like needle
        or lower(combined.match_id) like needle
        or lower(combined.group_name) like needle
        or lower(coalesce(combined.team_code, '')) like needle
        or lower(coalesce(combined.secondary_group_name, '')) like needle
        or lower(coalesce(combined.secondary_team_code, '')) like needle
        or lower(coalesce(combined.challenge_id::text, '')) like needle
      )
  ), page_source as (
    select filtered.*,
      row_number() over (order by
        case when safe_sort = 'date_asc' then filtered.match_date end asc nulls last,
        case when safe_sort = 'date_desc' then filtered.match_date end desc nulls last,
        case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
        case when safe_sort = 'state_asc' then filtered.state end asc nulls last,
        filtered.updated_at desc,
        filtered.scope,
        filtered.match_id
      ) as sort_ordinal
    from filtered
    order by
      case when safe_sort = 'date_asc' then filtered.match_date end asc nulls last,
      case when safe_sort = 'date_desc' then filtered.match_date end desc nulls last,
      case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
      case when safe_sort = 'state_asc' then filtered.state end asc nulls last,
      filtered.updated_at desc,
      filtered.scope,
      filtered.match_id
    limit safe_size offset safe_offset
  ), paged as (
    select jsonb_build_object(
      'scope', page_source.scope,
      'groupId', page_source.group_id,
      'secondaryGroupId', page_source.secondary_group_id,
      'matchId', page_source.match_id,
      'challengeId', page_source.challenge_id,
      'title', page_source.title,
      'modality', page_source.modality,
      'place', page_source.place,
      'date', page_source.match_date,
      'state', page_source.state,
      'revision', page_source.revision,
      'lineupClosed', page_source.lineup_closed,
      'scoreA', page_source.score_a,
      'scoreB', page_source.score_b,
      'updatedAt', page_source.updated_at,
      'groupName', page_source.group_name,
      'teamCode', page_source.team_code,
      'secondaryGroupName', page_source.secondary_group_name,
      'secondaryTeamCode', page_source.secondary_team_code
    ) as item, page_source.sort_ordinal
    from page_source
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(paged.item order by paged.sort_ordinal) from paged), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_pachanga_platform_matches_v1(
  text, uuid, date, date, text, text, text, text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.list_pachanga_platform_matches_v1(
  text, uuid, date, date, text, text, text, text, integer, integer
) to authenticated;

create or replace function public.list_pachanga_platform_challenges_v1(
  search_text text default '',
  team_filter uuid default null,
  date_from date default null,
  date_to date default null,
  status_filter text default 'all',
  sort_key text default 'updated_desc',
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  safe_status text := lower(coalesce(status_filter, 'all'));
  safe_sort text := lower(coalesce(sort_key, 'updated_desc'));
  safe_size integer := least(greatest(coalesce(page_size, 30), 10), 100);
  safe_offset integer := greatest(coalesce(page_offset, 0), 0);
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('challenges.read');
  if safe_status not in ('all', 'proposed', 'changes_proposed', 'accepted', 'rejected', 'cancelled', 'expired')
    or safe_sort not in ('date_asc', 'date_desc', 'updated_desc', 'created_desc') then
    raise exception 'Invalid challenge filter';
  end if;
  if date_from is not null and date_to is not null and date_from > date_to then
    raise exception 'Invalid challenge date range';
  end if;

  with filtered as materialized (
    select
      challenges.id,
      challenges.sender_group_id,
      challenges.receiver_group_id,
      challenges.status,
      challenges.revision,
      challenges.proposal_number,
      challenges.scheduled_at,
      challenges.modality,
      challenges.field_name,
      challenges.last_proposed_by_group_id,
      challenges.accepted_at,
      challenges.rejected_at,
      challenges.cancelled_at,
      challenges.expired_at,
      challenges.created_at,
      challenges.updated_at,
      sender.name as sender_name,
      sender.team_code as sender_team_code,
      receiver.name as receiver_name,
      receiver.team_code as receiver_team_code
    from public.pachanga_team_challenges challenges
    join public.pachanga_groups sender on sender.id = challenges.sender_group_id
    join public.pachanga_groups receiver on receiver.id = challenges.receiver_group_id
    where (safe_status = 'all' or challenges.status = safe_status)
      and (team_filter is null or challenges.sender_group_id = team_filter or challenges.receiver_group_id = team_filter)
      and (date_from is null or challenges.scheduled_at::date >= date_from)
      and (date_to is null or challenges.scheduled_at::date <= date_to)
      and (
        nullif(trim(coalesce(search_text, '')), '') is null
        or challenges.id::text like needle
        or lower(sender.name) like needle
        or lower(coalesce(sender.team_code, '')) like needle
        or lower(receiver.name) like needle
        or lower(coalesce(receiver.team_code, '')) like needle
        or lower(coalesce(challenges.field_name, '')) like needle
      )
  ), page_source as (
    select filtered.*,
      row_number() over (order by
        case when safe_sort = 'date_asc' then filtered.scheduled_at end asc nulls last,
        case when safe_sort = 'date_desc' then filtered.scheduled_at end desc nulls last,
        case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
        case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
        filtered.id
      ) as sort_ordinal
    from filtered
    order by
      case when safe_sort = 'date_asc' then filtered.scheduled_at end asc nulls last,
      case when safe_sort = 'date_desc' then filtered.scheduled_at end desc nulls last,
      case when safe_sort = 'updated_desc' then filtered.updated_at end desc nulls last,
      case when safe_sort = 'created_desc' then filtered.created_at end desc nulls last,
      filtered.id
    limit safe_size offset safe_offset
  ), paged as (
    select jsonb_build_object(
      'id', page_source.id,
      'senderGroupId', page_source.sender_group_id,
      'receiverGroupId', page_source.receiver_group_id,
      'status', page_source.status,
      'revision', page_source.revision,
      'proposalNumber', page_source.proposal_number,
      'scheduledAt', page_source.scheduled_at,
      'modality', page_source.modality,
      'fieldName', page_source.field_name,
      'lastProposedByGroupId', page_source.last_proposed_by_group_id,
      'acceptedAt', page_source.accepted_at,
      'rejectedAt', page_source.rejected_at,
      'cancelledAt', page_source.cancelled_at,
      'expiredAt', page_source.expired_at,
      'createdAt', page_source.created_at,
      'updatedAt', page_source.updated_at,
      'sender', jsonb_build_object('id', page_source.sender_group_id, 'name', page_source.sender_name, 'teamCode', page_source.sender_team_code),
      'receiver', jsonb_build_object('id', page_source.receiver_group_id, 'name', page_source.receiver_name, 'teamCode', page_source.receiver_team_code)
    ) as item, page_source.sort_ordinal
    from page_source
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'items', coalesce((select jsonb_agg(paged.item order by paged.sort_ordinal) from paged), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.list_pachanga_platform_challenges_v1(
  text, uuid, date, date, text, text, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.list_pachanga_platform_challenges_v1(
  text, uuid, date, date, text, text, integer, integer
) to authenticated;

-- Platform moderators inherit the canonical conduct RPCs without relying on mutable team roles.
create or replace function private.pachanga_is_security_moderator_v1()
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select (select auth.uid()) is not null and (
    coalesce((select auth.jwt()) -> 'app_metadata' ->> 'pachangas_security_role', '')
      in ('moderator', 'security_admin')
    or coalesce(private.pachanga_platform_role_for_user_v1((select auth.uid())), '')
      in ('moderator', 'platform_admin', 'platform_owner')
  );
$$;

revoke all on function private.pachanga_is_security_moderator_v1()
  from public, anon, authenticated;

alter table private.pachanga_conduct_settings
  add column if not exists platform_revision bigint not null default 1;
alter table private.pachanga_player_cosmetic_settings
  add column if not exists platform_revision bigint not null default 1;
alter table private.pachanga_team_cosmetic_settings
  add column if not exists platform_revision bigint not null default 1;

create or replace function public.get_pachanga_platform_flags_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('flags.read');
  select jsonb_build_array(
    jsonb_build_object('key', 'attendance', 'label', 'Asistencia', 'enabled', conduct.attendance_closure_enabled,
      'state', case when conduct.attendance_closure_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision, 'source', 'pachanga_conduct_settings'),
    jsonb_build_object('key', 'conduct', 'label', 'Conducta', 'enabled', conduct.conduct_reports_enabled,
      'state', case when conduct.conduct_reports_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision, 'source', 'pachanga_conduct_settings'),
    jsonb_build_object('key', 'social_restrictions', 'label', 'Restricciones sociales', 'enabled', conduct.social_restrictions_enabled,
      'state', case when conduct.social_restrictions_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision, 'source', 'pachanga_conduct_settings'),
    jsonb_build_object('key', 'triage', 'label', 'Triage de conducta', 'enabled', conduct.conduct_triage_enabled,
      'state', case when conduct.conduct_triage_enabled and not conduct.conduct_triage_shadow_mode then 'PRODUCT'
                    when conduct.conduct_triage_enabled or conduct.conduct_triage_shadow_mode then 'LAB' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision, 'source', 'pachanga_conduct_settings'),
    jsonb_build_object('key', 'player_cosmetics', 'label', 'Cosmeticos de jugador', 'enabled', player.player_cosmetics_enabled,
      'state', case when player.player_cosmetics_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', player.platform_revision, 'source', 'pachanga_player_cosmetic_settings'),
    jsonb_build_object('key', 'team_cosmetics', 'label', 'Cosmeticos de equipo', 'enabled', team.team_cosmetics_enabled,
      'state', case when team.team_cosmetics_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', team.platform_revision, 'source', 'pachanga_team_cosmetic_settings'),
    jsonb_build_object('key', 'team_cosmetic_rewards', 'label', 'Team Cosmetic Rewards', 'enabled', team.team_cosmetic_rewards_enabled,
      'state', case when team.team_cosmetic_rewards_enabled then 'PRODUCT' else 'OFF' end,
      'mutable', true, 'sensitive', true, 'revision', team.platform_revision, 'source', 'pachanga_team_cosmetic_settings'),
    jsonb_build_object('key', 'provincial_rankings', 'label', 'Rankings provinciales', 'enabled', false,
      'state', 'LAB', 'mutable', false, 'sensitive', true, 'revision', 0, 'source', 'season-ranking-lab'),
    jsonb_build_object('key', 'provincial_awards', 'label', 'Premios provinciales', 'enabled', false,
      'state', 'OFF', 'mutable', false, 'sensitive', true, 'revision', 0, 'source', 'territory-award-readiness')
  ) into result
  from private.pachanga_conduct_settings conduct
  cross join private.pachanga_player_cosmetic_settings player
  cross join private.pachanga_team_cosmetic_settings team
  where conduct.singleton and player.singleton and team.singleton;
  return coalesce(result, '[]'::jsonb);
end;
$$;

revoke all on function public.get_pachanga_platform_flags_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_flags_v1() to authenticated;

create or replace function public.set_pachanga_platform_flag_v1(
  flag_key text,
  next_enabled boolean,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  current_enabled boolean;
  current_revision bigint;
  next_revision bigint;
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('flags.write');
  if flag_key not in (
    'attendance', 'conduct', 'social_restrictions', 'triage',
    'player_cosmetics', 'team_cosmetics', 'team_cosmetic_rewards'
  ) then raise exception 'Flag is read-only or unknown'; end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_flag.set', 'feature_flag', flag_key
  );
  if response is not null then return response; end if;

  if flag_key in ('attendance', 'conduct', 'social_restrictions', 'triage') then
    select case flag_key
      when 'attendance' then settings.attendance_closure_enabled
      when 'conduct' then settings.conduct_reports_enabled
      when 'social_restrictions' then settings.social_restrictions_enabled
      else settings.conduct_triage_enabled
    end, settings.platform_revision into current_enabled, current_revision
    from private.pachanga_conduct_settings settings where settings.singleton for update;
  elsif flag_key = 'player_cosmetics' then
    select settings.player_cosmetics_enabled, settings.platform_revision
    into current_enabled, current_revision
    from private.pachanga_player_cosmetic_settings settings where settings.singleton for update;
  else
    select case flag_key when 'team_cosmetics' then settings.team_cosmetics_enabled
                         else settings.team_cosmetic_rewards_enabled end,
           settings.platform_revision into current_enabled, current_revision
    from private.pachanga_team_cosmetic_settings settings where settings.singleton for update;
  end if;
  if expected_revision is null or current_revision <> expected_revision then
    raise exception 'Feature flag changed before saving' using errcode = '40001';
  end if;

  next_revision := current_revision + 1;
  if flag_key = 'attendance' then
    update private.pachanga_conduct_settings set attendance_closure_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  elsif flag_key = 'conduct' then
    update private.pachanga_conduct_settings set conduct_reports_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  elsif flag_key = 'social_restrictions' then
    update private.pachanga_conduct_settings set social_restrictions_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  elsif flag_key = 'triage' then
    update private.pachanga_conduct_settings set conduct_triage_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  elsif flag_key = 'player_cosmetics' then
    update private.pachanga_player_cosmetic_settings set player_cosmetics_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  elsif flag_key = 'team_cosmetics' then
    update private.pachanga_team_cosmetic_settings set team_cosmetics_enabled = next_enabled,
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  else
    perform private.pachanga_set_team_cosmetic_rewards_enabled_v1(next_enabled, operation_id, 1);
    update private.pachanga_team_cosmetic_settings set
      platform_revision = next_revision, updated_at = clock_timestamp() where singleton;
  end if;

  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'key', flag_key, 'enabled', next_enabled, 'revision', next_revision, 'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_flag.set', 'feature_flag', flag_key,
    trim(reason), jsonb_build_object('enabled', current_enabled, 'revision', current_revision),
    response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  to authenticated;

create table if not exists private.pachanga_platform_announcements (
  id uuid primary key default gen_random_uuid(),
  audience_type text not null,
  audience_id uuid,
  title text not null,
  body text not null,
  action_url text,
  state text not null default 'draft',
  recipient_count integer,
  revision bigint not null default 1,
  created_by uuid not null references auth.users(id) on delete restrict,
  sent_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (audience_type in ('user', 'team', 'team_admins')),
  check (char_length(title) between 3 and 120),
  check (char_length(body) between 3 and 1000),
  check (action_url is null or (char_length(action_url) <= 500 and action_url like '/%')),
  check (state in ('draft', 'sent', 'cancelled')),
  check (recipient_count is null or recipient_count >= 0),
  check (revision >= 1)
);

create table if not exists private.pachanga_client_error_telemetry (
  fingerprint text not null,
  route text not null,
  app_version text not null,
  category text not null,
  browser_family text not null,
  platform text not null,
  occurrence_count bigint not null default 1,
  first_seen_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  last_server_sequence bigint not null default nextval('private.pachanga_platform_admin_sequence'),
  primary key (fingerprint, route, app_version, category, browser_family, platform),
  check (char_length(fingerprint) between 8 and 160),
  check (char_length(route) between 1 and 240),
  check (char_length(app_version) between 1 and 80),
  check (char_length(category) between 1 and 80),
  check (char_length(browser_family) between 1 and 40),
  check (char_length(platform) between 1 and 40),
  check (occurrence_count >= 1)
);

create table if not exists private.pachanga_client_error_receipts (
  operation_id uuid primary key,
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists private.pachanga_platform_incidents (
  fingerprint text primary key,
  state text not null default 'new',
  note text,
  revision bigint not null default 1,
  updated_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('new', 'investigating', 'resolved', 'ignored')),
  check (note is null or char_length(note) <= 1200),
  check (revision >= 1)
);

create index if not exists pachanga_platform_announcements_state_idx
  on private.pachanga_platform_announcements(state, created_at desc, id desc);
create index if not exists pachanga_client_error_last_seen_idx
  on private.pachanga_client_error_telemetry(last_seen_at desc, last_server_sequence desc);

revoke all on table private.pachanga_platform_announcements from public, anon, authenticated;
revoke all on table private.pachanga_client_error_telemetry from public, anon, authenticated;
revoke all on table private.pachanga_client_error_receipts from public, anon, authenticated;
revoke all on table private.pachanga_platform_incidents from public, anon, authenticated;
grant all on table private.pachanga_platform_announcements to service_role;
grant all on table private.pachanga_client_error_telemetry to service_role;
grant all on table private.pachanga_client_error_receipts to service_role;
grant all on table private.pachanga_platform_incidents to service_role;

create or replace function private.pachanga_platform_announcement_recipients_v1(
  selected_audience_type text,
  selected_audience_id uuid
)
returns table(user_id uuid)
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select selected_audience_id
  where selected_audience_type = 'user'
    and exists (select 1 from auth.users users where users.id = selected_audience_id)
  union
  select groups.owner_id
  from public.pachanga_groups groups
  where selected_audience_type in ('team', 'team_admins')
    and groups.id = selected_audience_id
  union
  select members.user_id
  from public.pachanga_group_members members
  where selected_audience_type = 'team'
    and members.group_id = selected_audience_id
  union
  select members.user_id
  from public.pachanga_group_members members
  where selected_audience_type = 'team_admins'
    and members.group_id = selected_audience_id
    and members.role = 'admin';
$$;

revoke all on function private.pachanga_platform_announcement_recipients_v1(text, uuid)
  from public, anon, authenticated;

create or replace function public.create_pachanga_platform_announcement_v1(
  audience_type text,
  audience_id uuid,
  announcement_title text,
  announcement_body text,
  announcement_action_url text,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  created private.pachanga_platform_announcements%rowtype;
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('notifications.send');
  if audience_type not in ('user', 'team', 'team_admins') or audience_id is null then
    raise exception 'A supported audience is required';
  end if;
  if char_length(trim(coalesce(announcement_title, ''))) < 3
    or char_length(trim(coalesce(announcement_body, ''))) < 3 then
    raise exception 'Title and body required';
  end if;
  if announcement_action_url is not null and announcement_action_url not like '/%' then
    raise exception 'Action URL must be internal';
  end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_announcement.create', 'announcement', null
  );
  if response is not null then return response; end if;
  if not exists (
    select 1 from private.pachanga_platform_announcement_recipients_v1(audience_type, audience_id)
  ) then raise exception 'Audience has no recipients'; end if;

  insert into private.pachanga_platform_announcements(
    audience_type, audience_id, title, body, action_url, created_by
  ) values (
    audience_type, audience_id, trim(announcement_title), trim(announcement_body),
    nullif(trim(coalesce(announcement_action_url, '')), ''), actor_id
  ) returning * into created;
  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'id', created.id, 'state', created.state, 'revision', created.revision,
    'audienceType', created.audience_type, 'audienceId', created.audience_id,
    'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_announcement.create', 'announcement', created.id::text,
    trim(reason), '{}'::jsonb, response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.create_pachanga_platform_announcement_v1(text, uuid, text, text, text, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.create_pachanga_platform_announcement_v1(text, uuid, text, text, text, uuid, text)
  to authenticated;

create or replace function public.preview_pachanga_platform_announcement_v1(target_announcement_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  selected private.pachanga_platform_announcements%rowtype;
  recipients integer;
begin
  perform private.pachanga_platform_require_v1('notifications.send');
  select * into selected from private.pachanga_platform_announcements announcements
  where announcements.id = target_announcement_id;
  if not found then raise exception 'Announcement not found'; end if;
  select count(*) into recipients
  from private.pachanga_platform_announcement_recipients_v1(selected.audience_type, selected.audience_id);
  return jsonb_build_object(
    'id', selected.id, 'state', selected.state, 'revision', selected.revision,
    'title', selected.title, 'body', selected.body, 'actionUrl', selected.action_url,
    'audienceType', selected.audience_type, 'audienceId', selected.audience_id,
    'recipientCount', recipients
  );
end;
$$;

revoke all on function public.preview_pachanga_platform_announcement_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.preview_pachanga_platform_announcement_v1(uuid) to authenticated;

create or replace function public.send_pachanga_platform_announcement_v1(
  target_announcement_id uuid,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  selected private.pachanga_platform_announcements%rowtype;
  recipient record;
  recipients integer := 0;
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('notifications.send');
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_announcement.send', 'announcement', target_announcement_id::text
  );
  if response is not null then return response; end if;
  select * into selected
  from private.pachanga_platform_announcements announcements
  where announcements.id = target_announcement_id
  for update;
  if not found then raise exception 'Announcement not found'; end if;
  if selected.state <> 'draft' then raise exception 'Only drafts can be sent'; end if;
  if selected.revision <> expected_revision then
    raise exception 'Announcement changed before sending' using errcode = '40001';
  end if;

  for recipient in
    select * from private.pachanga_platform_announcement_recipients_v1(
      selected.audience_type, selected.audience_id
    )
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      'platform_announcement',
      selected.title,
      selected.body,
      coalesce(selected.action_url, '/'),
      jsonb_build_object('announcementId', selected.id),
      'platform-announcement:' || selected.id::text || ':' || recipient.user_id::text
    );
    recipients := recipients + 1;
  end loop;
  if recipients = 0 then raise exception 'Audience has no recipients'; end if;

  update private.pachanga_platform_announcements
  set state = 'sent', recipient_count = recipients, sent_by = actor_id,
      sent_at = clock_timestamp(), revision = revision + 1, updated_at = clock_timestamp()
  where id = selected.id
  returning * into selected;
  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'id', selected.id, 'state', selected.state, 'revision', selected.revision,
    'recipientCount', recipients, 'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_announcement.send', 'announcement', selected.id::text,
    trim(reason), jsonb_build_object('state', 'draft', 'revision', expected_revision),
    response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.send_pachanga_platform_announcement_v1(uuid, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.send_pachanga_platform_announcement_v1(uuid, bigint, uuid, text)
  to authenticated;

create or replace function public.record_pachanga_client_error_v1(
  error_fingerprint text,
  error_route text,
  error_app_version text,
  error_category text,
  error_browser_family text,
  error_platform text,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved private.pachanga_client_error_telemetry%rowtype;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if operation_id is null then raise exception 'operationId required'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('platform-client-error-operation:' || operation_id::text, 0)
  );
  if exists (
    select 1 from private.pachanga_client_error_receipts receipts
    where receipts.operation_id = record_pachanga_client_error_v1.operation_id
  ) then return jsonb_build_object('accepted', true, 'duplicate', true); end if;

  delete from private.pachanga_client_error_receipts where created_at < clock_timestamp() - interval '30 days';
  delete from private.pachanga_client_error_telemetry where last_seen_at < clock_timestamp() - interval '30 days';
  insert into private.pachanga_client_error_receipts(operation_id) values (operation_id);
  insert into private.pachanga_client_error_telemetry(
    fingerprint, route, app_version, category, browser_family, platform
  ) values (
    left(trim(error_fingerprint), 160), left(trim(error_route), 240), left(trim(error_app_version), 80),
    left(trim(error_category), 80), left(trim(error_browser_family), 40), left(trim(error_platform), 40)
  ) on conflict (fingerprint, route, app_version, category, browser_family, platform)
  do update set
    occurrence_count = private.pachanga_client_error_telemetry.occurrence_count + 1,
    last_seen_at = clock_timestamp(),
    last_server_sequence = nextval('private.pachanga_platform_admin_sequence')
  returning * into saved;
  return jsonb_build_object(
    'accepted', true,
    'occurrenceCount', saved.occurrence_count,
    'serverTime', saved.last_seen_at
  );
end;
$$;

revoke all on function public.record_pachanga_client_error_v1(text, text, text, text, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.record_pachanga_client_error_v1(text, text, text, text, text, text, uuid)
  to service_role;

create or replace function public.get_pachanga_platform_overview_v1(selected_period text default 'today')
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  since_at timestamptz;
  period_key text := lower(coalesce(selected_period, 'today'));
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('overview.read');
  if period_key = 'today' then since_at := date_trunc('day', clock_timestamp());
  elsif period_key = '7d' then since_at := clock_timestamp() - interval '7 days';
  elsif period_key = '30d' then since_at := clock_timestamp() - interval '30 days';
  elsif period_key = 'season' then since_at := null;
  else raise exception 'Invalid period'; end if;

  select jsonb_build_object(
    'period', period_key,
    'periodStart', since_at,
    'periodNote', case when period_key = 'season'
      then 'No existe una temporada global canonica; se muestra todo el historico disponible.' else null end,
    'users', jsonb_build_object(
      'total', (select count(*) from auth.users),
      'new', (select count(*) from auth.users users where since_at is null or users.created_at >= since_at),
      'banned', (select count(*) from auth.users users where users.banned_until > clock_timestamp())
    ),
    'teams', jsonb_build_object(
      'total', (select count(*) from public.pachanga_groups),
      'active', (select count(*) from public.pachanga_groups groups
        where exists (
          select 1 from public.pachanga_group_members members where members.group_id = groups.id
        )),
      'new', (select count(*) from public.pachanga_groups groups
        where since_at is null or groups.created_at >= since_at)
    ),
    'players', jsonb_build_object(
      'registered', (select count(*) from public.pachanga_player_profiles profiles where profiles.user_id is not null),
      'totalProfiles', (select count(*) from public.pachanga_player_profiles)
    ),
    'matches', jsonb_build_object(
      'total', (select count(*) from public.pachanga_match_read_model),
      'changedInPeriod', (select count(*) from public.pachanga_match_read_model matches
        where since_at is null or matches.updated_at >= since_at),
      'finalized', (select count(*) from public.pachanga_match_read_model matches where matches.finalized),
      'pending', (select count(*) from public.pachanga_match_read_model matches where not matches.finalized)
    ),
    'challenges', jsonb_build_object(
      'total', (select count(*) from public.pachanga_team_challenges),
      'createdInPeriod', (select count(*) from public.pachanga_team_challenges challenges
        where since_at is null or challenges.created_at >= since_at),
      'accepted', (select count(*) from public.pachanga_team_challenges challenges where challenges.status = 'accepted'),
      'pending', (select count(*) from public.pachanga_team_challenges challenges
        where challenges.status in ('proposed', 'changes_proposed'))
    ),
    'market', jsonb_build_object(
      'teams', (select count(*) from public.pachanga_challengeable_team_profiles profiles where profiles.enabled),
      'players', (select count(*) from public.pachanga_player_profiles profiles where profiles.market_enabled)
    ),
    'moderation', jsonb_build_object(
      'pending', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')),
      'urgent', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')
          and cases.triage_recommendation = 'urgent_review'),
      'restrictedUsers', (select count(distinct restrictions.target_user_id)
        from private.pachanga_social_restrictions restrictions
        where restrictions.state = 'active'
          and (restrictions.ends_at is null or restrictions.ends_at > clock_timestamp()))
    ),
    'billing', jsonb_build_object(
      'trial', (select count(*) from public.pachanga_groups groups where groups.billing_status = 'trial'),
      'active', (select count(*) from public.pachanga_groups groups where groups.billing_status in ('active', 'trialing')),
      'pastDue', (select count(*) from public.pachanga_groups groups where groups.billing_status in ('past_due', 'unpaid', 'incomplete')),
      'canceled', (select count(*) from public.pachanga_groups groups where groups.billing_status = 'canceled'),
      'failedWebhooks', (select count(*) from public.pachanga_stripe_webhook_events events
        where events.processing_status = 'failed')
    ),
    'rewards', jsonb_build_object(
      'achievementGrants', (select count(*) from public.pachanga_achievement_grants grants
        where since_at is null or grants.awarded_at >= since_at),
      'rewardGrants', (select count(*) from public.pachanga_reward_grants grants
        where since_at is null or grants.granted_at >= since_at),
      'pendingBoxes', (select count(*) from public.pachanga_reward_recipients recipients
        where recipients.status = 'pending'),
      'openedBoxes', (select count(*) from public.pachanga_reward_open_receipts receipts
        where since_at is null or receipts.created_at >= since_at)
    ),
    'notifications', jsonb_build_object(
      'created', (select count(*) from public.pachanga_user_notifications notifications
        where since_at is null or notifications.created_at >= since_at),
      'unread', (select count(*) from public.pachanga_user_notifications notifications
        where notifications.read_at is null and notifications.visible_in_app),
      'failedDeliveries', (select count(*) from private.pachanga_notification_delivery_outbox outbox
        where outbox.state = 'failed')
    ),
    'alerts', jsonb_strip_nulls(jsonb_build_object(
      'moderationUrgent', (select count(*) from private.pachanga_moderation_cases cases
        where cases.state not in ('dismissed', 'corrected', 'closed')
          and cases.triage_recommendation = 'urgent_review'),
      'billingFailures', (select count(*) from public.pachanga_groups groups
        where groups.billing_status in ('past_due', 'unpaid', 'incomplete')),
      'webhookFailures', (select count(*) from public.pachanga_stripe_webhook_events events
        where events.processing_status = 'failed'),
      'newClientErrors', (select count(*) from private.pachanga_client_error_telemetry errors
        where errors.last_seen_at >= clock_timestamp() - interval '24 hours')
    ))
  ) into result;
  return result;
end;
$$;

revoke all on function public.get_pachanga_platform_overview_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_overview_v1(text) to authenticated;

create or replace function public.search_pachanga_platform_v1(
  search_text text,
  result_limit integer default 20
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  safe_limit integer := least(greatest(coalesce(result_limit, 20), 1), 50);
  actor_role text;
  can_read_billing boolean;
  can_read_pii boolean;
begin
  actor_role := private.pachanga_platform_require_v1('search.read');
  can_read_billing := actor_role in ('platform_owner', 'platform_admin', 'finance');
  can_read_pii := actor_role in ('platform_owner', 'platform_admin', 'support', 'finance');
  if char_length(trim(coalesce(search_text, ''))) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(limited.item order by limited.priority, limited.label, limited.id)
    from (
      select results.*
      from (
      select 1 as priority, users.id::text as id, jsonb_build_object(
        'type', 'user', 'id', users.id,
        'label', coalesce(
          nullif(trim(profiles.display_name), ''),
          nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
          nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
          case when can_read_pii then users.email else null end,
          'Usuario ' || left(users.id::text, 8)
        ),
        'secondary', case when can_read_pii then users.email else null end,
        'href', '/admin/users/' || users.id::text
      ) as item, coalesce(
        nullif(trim(profiles.display_name), ''),
        nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
        nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
        case when can_read_pii then users.email else null end,
        users.id::text
      ) as label
      from auth.users users
      left join public.pachanga_player_profiles profiles on profiles.user_id = users.id
      where (can_read_pii and lower(coalesce(users.email, '')) like needle)
         or lower(coalesce(profiles.display_name, '')) like needle
         or lower(coalesce(users.raw_user_meta_data ->> 'full_name', '')) like needle
         or lower(coalesce(users.raw_user_meta_data ->> 'name', '')) like needle
         or users.id::text like needle
      union all
      select 2, groups.id::text, jsonb_build_object(
        'type', 'team', 'id', groups.id, 'label', groups.name,
        'secondary', groups.team_code, 'href', '/admin/teams/' || groups.id::text
      ), coalesce(groups.name, groups.team_code, groups.id::text)
      from public.pachanga_groups groups
      where lower(coalesce(groups.name, '')) like needle
         or lower(coalesce(groups.team_code, '')) like needle
         or (can_read_billing and lower(coalesce(groups.stripe_customer_id, '')) like needle)
         or (can_read_billing and lower(coalesce(groups.stripe_subscription_id, '')) like needle)
      union all
      select 3, matches.group_id::text || ':' || matches.match_id, jsonb_build_object(
        'type', 'match', 'id', matches.match_id, 'label', 'Partido ' || matches.match_id,
        'secondary', groups.name, 'href', '/admin/matches/' || matches.group_id::text || '/' || matches.match_id
      ), matches.match_id
      from public.pachanga_match_read_model matches
      join public.pachanga_groups groups on groups.id = matches.group_id
      where lower(matches.match_id) like needle
      union all
      select 4, challenges.id::text, jsonb_build_object(
        'type', 'challenge', 'id', challenges.id, 'label', 'Reto ' || left(challenges.id::text, 8),
        'secondary', sender.name || ' vs ' || receiver.name,
        'href', '/admin/challenges/' || challenges.id::text
      ), challenges.id::text
      from public.pachanga_team_challenges challenges
      join public.pachanga_groups sender on sender.id = challenges.sender_group_id
      join public.pachanga_groups receiver on receiver.id = challenges.receiver_group_id
      where challenges.id::text like needle
         or lower(sender.name) like needle or lower(receiver.name) like needle
      union all
      select 5, cases.opaque_reference::text, jsonb_build_object(
        'type', 'moderation', 'id', cases.opaque_reference,
        'label', 'Caso ' || left(cases.opaque_reference::text, 8),
        'secondary', cases.category, 'href', '/admin/conduct?case=' || cases.opaque_reference::text
      ), cases.opaque_reference::text
      from private.pachanga_moderation_cases cases
      where cases.opaque_reference::text like needle
      ) results
      order by results.priority, results.label, results.id
      limit safe_limit
    ) limited
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.search_pachanga_platform_v1(text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_platform_v1(text, integer) to authenticated;

create or replace function public.get_pachanga_platform_section_v1(
  section_key text,
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  safe_limit integer := least(greatest(coalesce(page_size, 30), 1), 100);
  safe_offset integer := greatest(coalesce(page_offset, 0), 0);
  result jsonb;
begin
  if section_key = 'moderation' then
    perform private.pachanga_platform_require_v1('moderation.read');
    select jsonb_build_object(
      'total', (select count(*) from private.pachanga_moderation_cases),
      'items', coalesce((select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
        from (
          select cases.id, cases.server_sequence, jsonb_build_object(
            'caseReference', cases.opaque_reference, 'targetName', profiles.display_name,
            'category', cases.category, 'state', cases.state, 'priority', cases.priority,
            'queue', cases.operational_queue, 'recommendation', cases.triage_recommendation,
            'reportCount', cases.report_count, 'independentSources', cases.independent_source_count,
            'correlatedSources', cases.correlated_source_count,
            'correlatedReporting', cases.correlated_reporting, 'mutualRetaliation', cases.mutual_retaliation,
            'revision', cases.revision, 'updatedAt', cases.updated_at
          ) item
          from private.pachanga_moderation_cases cases
          left join public.pachanga_player_profiles profiles on profiles.id = cases.target_profile_id
          order by cases.server_sequence desc, cases.id desc
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'rewards' then
    perform private.pachanga_platform_require_v1('rewards.read');
    select jsonb_build_object(
      'metrics', jsonb_build_object(
        'achievements', (select count(*) from public.pachanga_achievement_grants),
        'rewardGrants', (select count(*) from public.pachanga_reward_grants),
        'boxesPending', (select count(*) from public.pachanga_reward_recipients where status = 'pending'),
        'boxesOpened', (select count(*) from public.pachanga_reward_recipients where status = 'opened'),
        'playerCosmetics', (select count(*) from public.pachanga_player_reward_inventory
          where reward_kind = 'player_cosmetic' and state = 'active'),
        'teamCosmetics', (select count(*) from public.pachanga_team_cosmetic_inventory where state = 'active'),
        'alreadyOwned', (select count(*) from public.pachanga_progression_events events
          where coalesce((events.payload ->> 'alreadyOwned')::boolean, false))
      ),
      'items', coalesce((select jsonb_agg(rows.item order by rows.granted_at desc, rows.id desc)
        from (
          select grants.id, grants.granted_at, jsonb_build_object(
            'id', grants.id, 'kind', grants.reward_kind, 'key', grants.reward_key,
            'groupId', grants.group_id, 'playerProfileId', grants.player_profile_id,
            'state', grants.state, 'grantedAt', grants.granted_at,
            'achievementGrantId', grants.achievement_grant_id
          ) item
          from public.pachanga_reward_grants grants
          order by grants.granted_at desc, grants.id desc
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'notifications' then
    perform private.pachanga_platform_require_v1('notifications.read');
    select jsonb_build_object(
      'metrics', jsonb_build_object(
        'total', (select count(*) from public.pachanga_user_notifications),
        'unread', (select count(*) from public.pachanga_user_notifications
          where read_at is null and visible_in_app),
        'critical', (select count(*) from public.pachanga_user_notifications where priority = 'critical'),
        'pendingDelivery', (select count(*) from private.pachanga_notification_delivery_outbox
          where state = 'pending'),
        'failedDelivery', (select count(*) from private.pachanga_notification_delivery_outbox
          where state = 'failed')
      ),
      'announcements', coalesce((select jsonb_agg(rows.item order by rows.created_at desc, rows.id desc)
        from (
          select announcements.id, announcements.created_at, jsonb_build_object(
            'id', announcements.id, 'title', announcements.title, 'state', announcements.state,
            'audienceType', announcements.audience_type, 'audienceId', announcements.audience_id,
            'recipientCount', announcements.recipient_count, 'revision', announcements.revision,
            'createdAt', announcements.created_at, 'sentAt', announcements.sent_at
          ) item
          from private.pachanga_platform_announcements announcements
          order by announcements.created_at desc, announcements.id desc
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'billing' then
    perform private.pachanga_platform_require_v1('billing.read');
    select jsonb_build_object(
      'metrics', jsonb_build_object(
        'trial', (select count(*) from public.pachanga_groups where billing_status = 'trial'),
        'active', (select count(*) from public.pachanga_groups where billing_status in ('active', 'trialing')),
        'pastDue', (select count(*) from public.pachanga_groups
          where billing_status in ('past_due', 'unpaid', 'incomplete')),
        'canceled', (select count(*) from public.pachanga_groups where billing_status = 'canceled')
      ),
      'webhooks', coalesce((select jsonb_agg(rows.item order by rows.sort_at desc nulls last, rows.event_id desc)
        from (
          select events.event_id, coalesce(events.processed_at, '-infinity'::timestamptz) sort_at,
            jsonb_build_object(
              'eventId', events.event_id, 'eventType', events.event_type,
              'status', events.processing_status, 'processedAt', events.processed_at,
              'error', private.pachanga_platform_sanitize_error_v1(events.error_message)
            ) item
          from public.pachanga_stripe_webhook_events events
          order by coalesce(events.processed_at, '-infinity'::timestamptz) desc, events.event_id desc
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'audit' then
    perform private.pachanga_platform_require_v1('audit.read');
    select jsonb_build_object(
      'total', (select count(*) from private.pachanga_platform_admin_action_ledger),
      'items', coalesce((select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
        from (
          select ledger.id, ledger.server_sequence, jsonb_build_object(
            'id', ledger.id, 'operationId', ledger.operation_id,
            'actorUserId', ledger.actor_user_id, 'actorRole', ledger.actor_role,
            'action', ledger.action, 'targetType', ledger.target_type, 'targetId', ledger.target_id,
            'reason', ledger.reason, 'before', ledger.before_state, 'after', ledger.after_state,
            'serverSequence', ledger.server_sequence, 'createdAt', ledger.created_at
          ) item
          from private.pachanga_platform_admin_action_ledger ledger
          order by ledger.server_sequence desc, ledger.id desc
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'errors' then
    perform private.pachanga_platform_require_v1('system.read');
    select jsonb_build_object(
      'retentionDays', 30,
      'items', coalesce((select jsonb_agg(rows.item order by rows.last_seen_at desc, rows.fingerprint)
        from (
          select errors.fingerprint, errors.last_seen_at, jsonb_build_object(
            'fingerprint', errors.fingerprint, 'route', errors.route,
            'appVersion', errors.app_version, 'category', errors.category,
            'browserFamily', errors.browser_family, 'platform', errors.platform,
            'occurrences', errors.occurrence_count, 'firstSeenAt', errors.first_seen_at,
            'lastSeenAt', errors.last_seen_at, 'incidentState', coalesce(incidents.state, 'new'),
            'incidentRevision', coalesce(incidents.revision, 0)
          ) item
          from private.pachanga_client_error_telemetry errors
          left join private.pachanga_platform_incidents incidents
            on incidents.fingerprint = errors.fingerprint
          order by errors.last_seen_at desc, errors.fingerprint
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  elsif section_key = 'roles' then
    perform private.pachanga_platform_require_v1('roles.manage');
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(rows.item order by rows.role, rows.user_id)
        from (
          select roles.user_id, roles.role, jsonb_build_object(
            'userId', roles.user_id, 'email', users.email, 'role', roles.role,
            'active', roles.active, 'revision', roles.revision,
            'grantedAt', roles.granted_at, 'updatedAt', roles.updated_at
          ) item
          from private.pachanga_platform_admin_roles roles
          join auth.users users on users.id = roles.user_id
          order by roles.role, roles.user_id
          limit safe_limit offset safe_offset
        ) rows), '[]'::jsonb)
    ) into result;
  else
    raise exception 'Unsupported platform section';
  end if;
  return result;
end;
$$;

revoke all on function public.get_pachanga_platform_section_v1(text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_section_v1(text, integer, integer)
  to authenticated;

create or replace function public.get_pachanga_platform_database_health_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  top_tables jsonb;
  migration_count bigint := 0;
  latest_migration text;
  storage_files bigint := 0;
  storage_bytes bigint := 0;
  storage_buckets bigint := 0;
begin
  perform private.pachanga_platform_require_v1('system.read');
  select coalesce(jsonb_agg(rows.item order by rows.bytes desc, rows.schema_name, rows.table_name), '[]'::jsonb)
  into top_tables
  from (
    select namespaces.nspname schema_name, classes.relname table_name,
      pg_total_relation_size(classes.oid) bytes,
      jsonb_build_object(
        'schema', namespaces.nspname,
        'table', classes.relname,
        'bytes', pg_total_relation_size(classes.oid)
      ) item
    from pg_class classes
    join pg_namespace namespaces on namespaces.oid = classes.relnamespace
    where classes.relkind in ('r', 'p') and namespaces.nspname in ('public', 'private')
    order by pg_total_relation_size(classes.oid) desc, namespaces.nspname, classes.relname
    limit 10
  ) rows;
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select count(*), max(version)::text from supabase_migrations.schema_migrations'
      into migration_count, latest_migration;
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'select count(*), coalesce(sum(coalesce((metadata ->> ''size'')::bigint, 0)), 0) from storage.objects'
      into storage_files, storage_bytes;
  end if;
  if to_regclass('storage.buckets') is not null then
    execute 'select count(*) from storage.buckets' into storage_buckets;
  end if;
  return jsonb_build_object(
    'status', 'OK',
    'databaseBytes', pg_database_size(current_database()),
    'connections', (select count(*) from pg_stat_activity activity where activity.datname = current_database()),
    'activeConnections', (select count(*) from pg_stat_activity activity
      where activity.datname = current_database() and activity.state = 'active'),
    'longRunningQueries', (select count(*) from pg_stat_activity activity
      where activity.datname = current_database() and activity.state = 'active'
        and activity.pid <> pg_backend_pid() and clock_timestamp() - activity.query_start > interval '30 seconds'),
    'authUsers', (select count(*) from auth.users),
    'topTables', top_tables,
    'migrationCount', migration_count,
    'latestMigration', latest_migration,
    'storage', jsonb_build_object('buckets', storage_buckets, 'files', storage_files, 'bytes', storage_bytes),
    'limits', jsonb_build_object('databaseBytes', null, 'storageBytes', null),
    'limitsAvailable', false,
    'measuredAt', clock_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_platform_database_health_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_database_health_v1() to authenticated;

create or replace function public.set_pachanga_platform_incident_v1(
  error_fingerprint text,
  next_state text,
  incident_note text,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  selected private.pachanga_platform_incidents%rowtype;
  before_snapshot jsonb := jsonb_build_object('state', 'new', 'revision', 0);
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('system.read');
  if actor_role not in ('platform_owner', 'platform_admin', 'ops') then
    raise exception 'Operations role required' using errcode = '42501';
  end if;
  if next_state not in ('new', 'investigating', 'resolved', 'ignored') then
    raise exception 'Invalid incident state';
  end if;
  if not exists (select 1 from private.pachanga_client_error_telemetry errors
    where errors.fingerprint = error_fingerprint) then raise exception 'Error fingerprint not found'; end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_incident.set', 'client_error', error_fingerprint
  );
  if response is not null then return response; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('platform-incident-target:' || error_fingerprint, 0)
  );
  select * into selected from private.pachanga_platform_incidents incidents
  where incidents.fingerprint = error_fingerprint for update;
  if found then
    before_snapshot := jsonb_build_object('state', selected.state, 'revision', selected.revision);
    if expected_revision is null or selected.revision <> expected_revision then
      raise exception 'Incident changed before saving' using errcode = '40001';
    end if;
  elsif coalesce(expected_revision, 0) <> 0 then
    raise exception 'Incident changed before saving' using errcode = '40001';
  end if;
  insert into private.pachanga_platform_incidents(fingerprint, state, note, updated_by)
  values (error_fingerprint, next_state, nullif(trim(coalesce(incident_note, '')), ''), actor_id)
  on conflict (fingerprint) do update set
    state = excluded.state, note = excluded.note,
    revision = private.pachanga_platform_incidents.revision + 1,
    updated_by = actor_id, updated_at = clock_timestamp()
  returning * into selected;
  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_build_object(
    'fingerprint', selected.fingerprint, 'state', selected.state,
    'revision', selected.revision, 'serverSequence', sequence_value
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_incident.set', 'client_error', error_fingerprint,
    trim(reason), before_snapshot, response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_incident_v1(text, text, text, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_incident_v1(text, text, text, bigint, uuid, text)
  to authenticated;
