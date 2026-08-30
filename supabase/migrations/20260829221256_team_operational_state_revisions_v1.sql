-- Wave 8B: canonical Team lifecycle/enforcement authority and immutable history.
-- Existing teams are initialized idempotently as ACTIVE + CLEAR without notifications.

set lock_timeout = '5s';
set statement_timeout = '5min';

create sequence if not exists private.pachanga_team_operational_sequence_v1;
revoke all on sequence private.pachanga_team_operational_sequence_v1 from public, anon, authenticated;
grant usage, select on sequence private.pachanga_team_operational_sequence_v1 to service_role;

create table private.pachanga_team_operational_settings_v1 (
  singleton boolean primary key default true check (singleton),
  foundation_enabled boolean not null default false,
  enforcement_enabled boolean not null default false,
  restrictions_enabled boolean not null default false,
  continuity_enabled boolean not null default false,
  appeals_enabled boolean not null default false,
  cross_product_guards_enabled boolean not null default false,
  public_projection_enabled boolean not null default false,
  demo_world_v31_enabled boolean not null default false,
  revision bigint not null default 1 check (revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_team_operational_sequence_v1'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (not enforcement_enabled or foundation_enabled),
  check (not restrictions_enabled or enforcement_enabled),
  check (not continuity_enabled or restrictions_enabled),
  check (not appeals_enabled or enforcement_enabled),
  check (not cross_product_guards_enabled or restrictions_enabled),
  check (not public_projection_enabled or foundation_enabled),
  check (not demo_world_v31_enabled or public_projection_enabled)
);

insert into private.pachanga_team_operational_settings_v1(singleton)
values (true)
on conflict (singleton) do nothing;

create table private.pachanga_team_operational_states_v1 (
  group_id uuid primary key references public.pachanga_groups(id) on delete restrict,
  lifecycle_status text not null default 'ACTIVE',
  enforcement_status text not null default 'CLEAR',
  effective_status text not null default 'ACTIVE',
  restriction_preset text not null default 'CUSTOM',
  continuity_policy text not null default 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
  public_message text not null default '',
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  current_revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_team_operational_sequence_v1'),
  source text not null default 'MIGRATION_INITIALIZATION',
  last_operation_id uuid not null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (lifecycle_status in ('ACTIVE', 'ARCHIVED')),
  check (enforcement_status in ('CLEAR', 'UNDER_REVIEW', 'LIMITED', 'SUSPENDED')),
  check (effective_status in ('ACTIVE', 'UNDER_REVIEW', 'LIMITED', 'SUSPENDED', 'ARCHIVED')),
  check (restriction_preset in ('SOCIAL_ONLY', 'NEW_ACTIVITY_ONLY', 'COMPETITION_ONLY', 'FULL_PLATFORM_SUSPENSION', 'CUSTOM')),
  check (continuity_policy in (
    'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
    'FREEZE_FUTURE_SPORTING_WRITES',
    'PLATFORM_MANAGED_EXIT',
    'HISTORY_ONLY'
  )),
  check (length(public_message) <= 500),
  check (current_revision >= 1),
  check (effective_until is null or effective_until > effective_from),
  check (
    effective_status = case
      when lifecycle_status = 'ARCHIVED' then 'ARCHIVED'
      when enforcement_status = 'SUSPENDED' then 'SUSPENDED'
      when enforcement_status = 'LIMITED' then 'LIMITED'
      when enforcement_status = 'UNDER_REVIEW' then 'UNDER_REVIEW'
      else 'ACTIVE'
    end
  )
);

create table private.pachanga_team_operational_state_revisions_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  revision bigint not null,
  lifecycle_status text not null,
  enforcement_status text not null,
  effective_status text not null,
  restriction_preset text not null,
  continuity_policy text not null,
  public_message text not null default '',
  effective_from timestamptz not null,
  effective_until timestamptz,
  reason_code text not null,
  private_note text not null default '',
  evidence jsonb not null default '{}'::jsonb,
  source text not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (group_id, revision),
  unique (operation_id, group_id),
  check (revision >= 1),
  check (lifecycle_status in ('ACTIVE', 'ARCHIVED')),
  check (enforcement_status in ('CLEAR', 'UNDER_REVIEW', 'LIMITED', 'SUSPENDED')),
  check (effective_status in ('ACTIVE', 'UNDER_REVIEW', 'LIMITED', 'SUSPENDED', 'ARCHIVED')),
  check (restriction_preset in ('SOCIAL_ONLY', 'NEW_ACTIVITY_ONLY', 'COMPETITION_ONLY', 'FULL_PLATFORM_SUSPENSION', 'CUSTOM')),
  check (continuity_policy in (
    'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
    'FREEZE_FUTURE_SPORTING_WRITES',
    'PLATFORM_MANAGED_EXIT',
    'HISTORY_ONLY'
  )),
  check (length(public_message) <= 500),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(private_note) <= 4000),
  check (jsonb_typeof(evidence) = 'object'),
  check (actor_kind in ('MIGRATION', 'OWNER', 'PLATFORM', 'SERVICE_AUTHORITY'))
);

create table private.pachanga_team_operational_operation_receipts_v1 (
  operation_id uuid primary key,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  action text not null,
  request_hash text not null,
  expected_revision bigint not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('MIGRATION', 'OWNER', 'PLATFORM', 'SERVICE_AUTHORITY')),
  check (action ~ '^team\.[a-z][a-z0-9_.]{1,79}$'),
  check (length(request_hash) = 64),
  check (expected_revision >= 0),
  check (confirmed_revision >= 1),
  check (jsonb_typeof(client_metadata) = 'object'),
  check (jsonb_typeof(response) = 'object')
);

create table private.pachanga_team_operational_events_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  event_kind text not null,
  aggregate_revision bigint not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique,
  confirmed_at timestamptz not null default clock_timestamp(),
  unique (operation_id, event_kind),
  check (event_kind ~ '^team\.[a-z][a-z0-9_.]{1,79}$'),
  check (aggregate_revision >= 1),
  check (actor_kind in ('MIGRATION', 'OWNER', 'PLATFORM', 'SERVICE_AUTHORITY')),
  check (length(trim(reason_code)) between 3 and 120),
  check (jsonb_typeof(event_payload) = 'object')
);

create or replace function private.pachanga_team_operational_effective_status_v1(
  target_lifecycle text,
  target_enforcement text
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when target_lifecycle = 'ARCHIVED' then 'ARCHIVED'
    when target_enforcement = 'SUSPENDED' then 'SUSPENDED'
    when target_enforcement = 'LIMITED' then 'LIMITED'
    when target_enforcement = 'UNDER_REVIEW' then 'UNDER_REVIEW'
    else 'ACTIVE'
  end;
$$;

create or replace function private.pachanga_team_operational_request_hash_v1(
  target_group_id uuid,
  target_action text,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'groupId', target_group_id,
    'action', lower(trim(coalesce(target_action, ''))),
    'expectedRevision', target_expected_revision,
    'payload', coalesce(target_payload, '{}'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_team_operational_state_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', 'TeamOperationalState',
    'groupId', states.group_id,
    'lifecycle', states.lifecycle_status,
    'enforcement', states.enforcement_status,
    'effectiveStatus', states.effective_status,
    'restrictionPreset', states.restriction_preset,
    'continuityPolicy', states.continuity_policy,
    'publicMessage', states.public_message,
    'effectiveFrom', states.effective_from,
    'effectiveUntil', states.effective_until,
    'revision', states.current_revision,
    'serverSequence', states.server_sequence,
    'updatedAt', states.updated_at
  )
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id;
$$;

create or replace function private.pachanga_ensure_team_operational_state_v1(
  target_group_id uuid
)
returns private.pachanga_team_operational_states_v1
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  state_row private.pachanga_team_operational_states_v1%rowtype;
  operation_id uuid := gen_random_uuid();
  sequence_value bigint;
  snapshot jsonb;
  inserted boolean := false;
begin
  perform set_config('pachanga.team_operational_authority', 'on', true);
  if not exists (select 1 from public.pachanga_groups groups where groups.id = target_group_id) then
    raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002';
  end if;

  sequence_value := nextval('private.pachanga_team_operational_sequence_v1');
  insert into private.pachanga_team_operational_states_v1(
    group_id, lifecycle_status, enforcement_status, effective_status,
    restriction_preset, continuity_policy, public_message,
    effective_from, current_revision, server_sequence, source,
    last_operation_id, updated_by
  ) values (
    target_group_id, 'ACTIVE', 'CLEAR', 'ACTIVE',
    'CUSTOM', 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH', '',
    clock_timestamp(), 1, sequence_value, 'MIGRATION_INITIALIZATION',
    operation_id, null
  )
  on conflict (group_id) do nothing
  returning * into state_row;

  inserted := found;
  if not inserted then
    select * into strict state_row
    from private.pachanga_team_operational_states_v1 states
    where states.group_id = target_group_id;
    return state_row;
  end if;

  insert into private.pachanga_team_operational_state_revisions_v1(
    group_id, revision, lifecycle_status, enforcement_status, effective_status,
    restriction_preset, continuity_policy, public_message, effective_from,
    effective_until, reason_code, private_note, evidence, source,
    operation_id, actor_id, actor_kind, server_sequence
  ) values (
    state_row.group_id, state_row.current_revision, state_row.lifecycle_status,
    state_row.enforcement_status, state_row.effective_status,
    state_row.restriction_preset, state_row.continuity_policy,
    state_row.public_message, state_row.effective_from, state_row.effective_until,
    'migration.initialization', '', '{}'::jsonb, 'MIGRATION_INITIALIZATION',
    operation_id, null, 'MIGRATION', sequence_value
  );

  snapshot := private.pachanga_team_operational_state_snapshot_v1(target_group_id);
  insert into private.pachanga_team_operational_operation_receipts_v1(
    operation_id, group_id, actor_id, actor_kind, action, request_hash,
    expected_revision, confirmed_revision, server_sequence, client_metadata, response
  ) values (
    operation_id, target_group_id, null, 'MIGRATION', 'team.initialize',
    private.pachanga_team_operational_request_hash_v1(target_group_id, 'team.initialize', 0, '{}'::jsonb),
    0, 1, sequence_value, '{}'::jsonb, snapshot
  );

  insert into private.pachanga_team_operational_events_v1(
    operation_id, group_id, event_kind, aggregate_revision, actor_id,
    actor_kind, reason_code, event_payload, server_sequence
  ) values (
    operation_id, target_group_id, 'team.initialized', 1, null,
    'MIGRATION', 'migration.initialization', snapshot, sequence_value
  );

  return state_row;
end;
$$;

create or replace function private.pachanga_initialize_team_operational_state_after_insert_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_ensure_team_operational_state_v1(new.id);
  return new;
end;
$$;

drop trigger if exists pachanga_initialize_team_operational_state_after_insert_v1
  on public.pachanga_groups;
create trigger pachanga_initialize_team_operational_state_after_insert_v1
after insert on public.pachanga_groups
for each row execute function private.pachanga_initialize_team_operational_state_after_insert_v1();

do $$
declare target record;
begin
  for target in
    select groups.id from public.pachanga_groups groups order by groups.id
  loop
    perform private.pachanga_ensure_team_operational_state_v1(target.id);
  end loop;
end;
$$;

revoke all on table private.pachanga_team_operational_settings_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_states_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_state_revisions_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_operation_receipts_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_events_v1 from public, anon, authenticated;

grant all on table private.pachanga_team_operational_settings_v1 to service_role;
grant all on table private.pachanga_team_operational_states_v1 to service_role;
grant all on table private.pachanga_team_operational_state_revisions_v1 to service_role;
grant all on table private.pachanga_team_operational_operation_receipts_v1 to service_role;
grant all on table private.pachanga_team_operational_events_v1 to service_role;

revoke all on function private.pachanga_team_operational_effective_status_v1(text, text) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_request_hash_v1(uuid, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_state_snapshot_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_ensure_team_operational_state_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_initialize_team_operational_state_after_insert_v1() from public, anon, authenticated;

grant execute on function private.pachanga_ensure_team_operational_state_v1(uuid) to service_role;

comment on table private.pachanga_team_operational_states_v1 is
  'Wave 8B single current operational projection per Team. Billing, Conduct and owner state are independent inputs, never authority.';
comment on table private.pachanga_team_operational_state_revisions_v1 is
  'Append-only operational decisions. Private notes and evidence never enter public read models.';
