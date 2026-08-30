-- Wave 8B: scoped Team restrictions and explicit competition continuity decisions.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table private.pachanga_team_operational_restrictions_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  scope text not null,
  status text not null default 'ACTIVE',
  source_revision bigint not null,
  preset_source text not null default 'CUSTOM',
  reason_code text not null,
  public_message text not null default '',
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  supersedes_restriction_id uuid references private.pachanga_team_operational_restrictions_v1(id) on delete restrict,
  closed_by_restriction_id uuid references private.pachanga_team_operational_restrictions_v1(id) on delete restrict,
  operation_id uuid not null,
  applied_by uuid references auth.users(id) on delete set null,
  closed_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  check (scope in (
    'PUBLIC_DISCOVERY',
    'MARKETPLACE',
    'SOCIAL_CHALLENGES',
    'NEW_MATCH_CREATION',
    'COMPETITION_REGISTRATION',
    'COMPETITION_ORGANIZER',
    'EXISTING_COMPETITION_OPERATIONS',
    'TEAM_MEMBERSHIP_ADMINISTRATION',
    'PUBLIC_PROFILE'
  )),
  check (status in ('ACTIVE', 'LIFTED', 'EXPIRED', 'SUPERSEDED')),
  check (source_revision >= 1),
  check (preset_source in ('SOCIAL_ONLY', 'NEW_ACTIVITY_ONLY', 'COMPETITION_ONLY', 'FULL_PLATFORM_SUSPENSION', 'CUSTOM')),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_message) <= 500),
  check (effective_until is null or effective_until > effective_from),
  check (
    (status = 'ACTIVE' and closed_at is null and closed_by is null)
    or (status <> 'ACTIVE' and closed_at is not null)
  )
);

create unique index pachanga_team_operational_active_scope_idx
  on private.pachanga_team_operational_restrictions_v1(group_id, scope)
  where status = 'ACTIVE';

create table private.pachanga_team_operational_continuity_decisions_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  policy text not null,
  source_revision bigint not null,
  reason_code text not null,
  public_message text not null default '',
  private_note text not null default '',
  operation_id uuid not null,
  decided_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, group_id, competition_id),
  check (policy in (
    'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
    'FREEZE_FUTURE_SPORTING_WRITES',
    'PLATFORM_MANAGED_EXIT',
    'HISTORY_ONLY'
  )),
  check (source_revision >= 1),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_message) <= 500),
  check (length(private_note) <= 4000),
  check (effective_until is null or effective_until > effective_from)
);

create or replace function private.pachanga_team_operational_preset_scopes_v1(
  target_preset text
)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(trim(coalesce(target_preset, 'CUSTOM')))
    when 'SOCIAL_ONLY' then array['MARKETPLACE', 'SOCIAL_CHALLENGES']::text[]
    when 'NEW_ACTIVITY_ONLY' then array[
      'NEW_MATCH_CREATION', 'COMPETITION_REGISTRATION', 'COMPETITION_ORGANIZER'
    ]::text[]
    when 'COMPETITION_ONLY' then array[
      'COMPETITION_REGISTRATION', 'COMPETITION_ORGANIZER'
    ]::text[]
    when 'FULL_PLATFORM_SUSPENSION' then array[
      'PUBLIC_DISCOVERY', 'MARKETPLACE', 'SOCIAL_CHALLENGES',
      'NEW_MATCH_CREATION', 'COMPETITION_REGISTRATION', 'COMPETITION_ORGANIZER',
      'EXISTING_COMPETITION_OPERATIONS', 'TEAM_MEMBERSHIP_ADMINISTRATION', 'PUBLIC_PROFILE'
    ]::text[]
    else array[]::text[]
  end;
$$;

create or replace function private.pachanga_team_operational_restrictions_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', restrictions.id,
    'scope', restrictions.scope,
    'status', restrictions.status,
    'presetSource', restrictions.preset_source,
    'publicMessage', restrictions.public_message,
    'effectiveFrom', restrictions.effective_from,
    'effectiveUntil', restrictions.effective_until,
    'sourceRevision', restrictions.source_revision,
    'serverSequence', restrictions.server_sequence
  ) order by restrictions.scope, restrictions.server_sequence desc, restrictions.id), '[]'::jsonb)
  from private.pachanga_team_operational_restrictions_v1 restrictions
  where restrictions.group_id = target_group_id
    and restrictions.status = 'ACTIVE';
$$;

create or replace function private.pachanga_team_operational_continuity_for_competition_v1(
  target_group_id uuid,
  target_competition_id uuid default null
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    (
      select decisions.policy
      from private.pachanga_team_operational_continuity_decisions_v1 decisions
      where decisions.group_id = target_group_id
        and (decisions.competition_id = target_competition_id or decisions.competition_id is null)
        and decisions.effective_from <= clock_timestamp()
        and (decisions.effective_until is null or decisions.effective_until > clock_timestamp())
      order by (decisions.competition_id is not null) desc,
        decisions.server_sequence desc,
        decisions.id desc
      limit 1
    ),
    (
      select states.continuity_policy
      from private.pachanga_team_operational_states_v1 states
      where states.group_id = target_group_id
    ),
    'ALLOW_EXISTING_COMPETITIONS_TO_FINISH'
  );
$$;

revoke all on table private.pachanga_team_operational_restrictions_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_continuity_decisions_v1 from public, anon, authenticated;
grant all on table private.pachanga_team_operational_restrictions_v1 to service_role;
grant all on table private.pachanga_team_operational_continuity_decisions_v1 to service_role;

revoke all on function private.pachanga_team_operational_preset_scopes_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_restrictions_snapshot_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_continuity_for_competition_v1(uuid, uuid) from public, anon, authenticated;

comment on table private.pachanga_team_operational_restrictions_v1 is
  'Independent allowlisted Team restriction scopes. Presets are copied into rows and never interpreted dynamically afterward.';
comment on table private.pachanga_team_operational_continuity_decisions_v1 is
  'Append-only platform decisions governing existing competitions without changing sporting history.';
