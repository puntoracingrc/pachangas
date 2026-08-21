-- Distinguish an installed canonical registry from one that has completed its
-- explicit backfill. The original R1 migrations are immutable after staging.

alter table private.pachanga_canonical_match_health_state
  add column if not exists initialized_at timestamptz;

update private.pachanga_canonical_match_health_state state
set initialized_at = backfills.confirmed_at,
    updated_at = clock_timestamp()
from (
  select min(events.confirmed_at) as confirmed_at
  from private.pachanga_competition_events events
  where events.action = 'canonical.backfill'
) backfills
where state.singleton
  and state.initialized_at is null
  and backfills.confirmed_at is not null;

comment on column private.pachanga_canonical_match_health_state.initialized_at is
  'Server timestamp of the first confirmed canonical.backfill; null means the registry is not initialized.';

create or replace function private.pachanga_canonical_match_health_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select state.snapshot || jsonb_build_object(
    'revision', state.revision,
    'serverSequence', state.server_sequence,
    'initialized', state.initialized_at is not null,
    'status', case
      when state.initialized_at is null then 'NOT_INITIALIZED'
      when state.dirty then 'DIRTY'
      else 'READY'
    end,
    'stale', state.dirty,
    'initializedAt', state.initialized_at,
    'sourceChangedAt', state.source_changed_at,
    'calculatedAt', state.calculated_at,
    'updatedAt', state.updated_at
  )
  from private.pachanga_canonical_match_health_state state
  where state.singleton;
$$;

revoke all on function private.pachanga_canonical_match_health_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_competition_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_organizer_group_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  response jsonb;
begin
  if target_action = 'canonical.backfill' then
    update private.pachanga_canonical_match_health_state state
    set initialized_at = coalesce(state.initialized_at, target_confirmed_at),
        updated_at = clock_timestamp()
    where state.singleton;

    target_snapshot := jsonb_set(
      coalesce(target_snapshot, '{}'::jsonb),
      '{health}',
      private.pachanga_canonical_match_health_v1(),
      true
    );
  end if;

  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', case when target_organizer_group_id is null then '[]'::jsonb else jsonb_build_array(
      jsonb_build_object(
        'entityType', target_aggregate_type,
        'entityId', target_aggregate_id,
        'revision', target_confirmed_revision
      )
    ) end
  );

  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_aggregate_type,
    target_aggregate_id::text, target_competition_id, target_action,
    target_confirmed_revision, target_server_sequence, target_reason_code,
    coalesce(target_event_payload, '{}'::jsonb), target_confirmed_at
  );

  if target_organizer_group_id is not null then
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, entity_type,
      entity_id, revision, created_at
    ) values (
      target_server_sequence, target_competition_id, target_organizer_group_id,
      target_aggregate_type, target_aggregate_id::text,
      target_confirmed_revision, target_confirmed_at
    );
  end if;

  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence, target_client_metadata, response, target_confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_competition_store_command_v1(
  uuid, uuid, text, text, text, uuid, uuid, uuid, bigint, bigint, text, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

comment on function private.pachanga_canonical_match_health_v1() is
  'Returns the materialized canonical health plus explicit initialization state; reads never trigger a recalculation.';
