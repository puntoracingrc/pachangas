-- R1 staging regression: a grant created with clock_timestamp() must be active
-- in the receipt produced by that same command. Capture one authoritative clock
-- value per resolver invocation instead of comparing with the older statement
-- start timestamp.

create or replace function private.pachanga_competition_active_entitlement_v1(
  target_group_id uuid,
  target_capability text
)
returns boolean
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (
    select clock_timestamp() as checked_at
  )
  select exists (
    select 1
    from public.pachanga_competition_entitlement_grants grants
    cross join authority_time
    where grants.organizer_group_id = target_group_id
      and grants.capability = target_capability
      and grants.status = 'active'
      and grants.valid_from <= authority_time.checked_at
      and (grants.expires_at is null or grants.expires_at > authority_time.checked_at)
  );
$$;

revoke all on function private.pachanga_competition_active_entitlement_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_entitlement_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (
    select clock_timestamp() as checked_at
  )
  select jsonb_build_object(
    'organizerKind', 'TEAM',
    'organizerGroupId', target_group_id,
    'organizerRevision', coalesce((
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_group_id = target_group_id
    ), 0),
    'grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'capability', grants.capability,
        'source', grants.grant_source,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.expires_at is not null and grants.expires_at <= authority_time.checked_at then 'expired'
          when grants.valid_from > authority_time.checked_at then 'scheduled'
          else 'active'
        end,
        'validFrom', grants.valid_from,
        'expiresAt', grants.expires_at,
        'revision', grants.revision,
        'updatedAt', grants.updated_at
      ) order by grants.capability, grants.created_at, grants.id)
      from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_group_id = target_group_id
    ), '[]'::jsonb),
    'canCreate', exists (
      select 1
      from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_group_id = target_group_id
        and grants.capability = 'competition_create'
        and grants.status = 'active'
        and grants.valid_from <= authority_time.checked_at
        and (grants.expires_at is null or grants.expires_at > authority_time.checked_at)
    )
  )
  from authority_time;
$$;

revoke all on function private.pachanga_competition_entitlement_snapshot_v1(uuid)
  from public, anon, authenticated;

comment on function private.pachanga_competition_active_entitlement_v1(uuid, text) is
  'Server-clock entitlement resolver. One volatile timestamp is captured per invocation.';
comment on function private.pachanga_competition_entitlement_snapshot_v1(uuid) is
  'Canonical TEAM entitlement snapshot using one server-clock timestamp for status and capability.';
