-- Pachangas IQ Wave 9B: RLS, immutable evidence, notifications and staged flags.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_venue_settings_v1
  add column if not exists demo_world_v35_enabled boolean not null default false;

alter table private.pachanga_venue_settings_v1
  drop constraint if exists pachanga_venue_wave9b_recurring_dependencies_check,
  add constraint pachanga_venue_wave9b_recurring_dependencies_check check (
    not venue_recurring_series_enabled or venue_availability_enabled
  ),
  drop constraint if exists pachanga_venue_wave9b_materialization_dependencies_check,
  add constraint pachanga_venue_wave9b_materialization_dependencies_check check (
    not venue_recurring_materialization_enabled or venue_recurring_series_enabled
  ),
  drop constraint if exists pachanga_venue_wave9b_pool_dependencies_check,
  add constraint pachanga_venue_wave9b_pool_dependencies_check check (
    not competition_venue_pool_enabled or venue_availability_enabled
  ),
  drop constraint if exists pachanga_venue_wave9b_allocation_dependencies_check,
  add constraint pachanga_venue_wave9b_allocation_dependencies_check check (
    not competition_venue_allocation_foundation_enabled
    or (competition_venue_pool_enabled and venue_match_binding_enabled)
  ),
  drop constraint if exists pachanga_venue_wave9b_modes_dependencies_check,
  add constraint pachanga_venue_wave9b_modes_dependencies_check check (
    (not competition_venue_allocation_automatic_enabled
      or competition_venue_allocation_foundation_enabled)
    and (not competition_venue_allocation_manual_enabled
      or competition_venue_allocation_foundation_enabled)
    and (not competition_venue_allocation_hybrid_enabled
      or (competition_venue_allocation_foundation_enabled
        and competition_venue_allocation_manual_enabled
        and competition_venue_allocation_automatic_enabled))
  ),
  drop constraint if exists pachanga_venue_wave9b_holds_dependencies_check,
  add constraint pachanga_venue_wave9b_holds_dependencies_check check (
    not competition_venue_allocation_holds_enabled
    or (competition_venue_allocation_foundation_enabled
      and venue_reservation_holds_enabled)
  ),
  drop constraint if exists pachanga_venue_wave9b_publish_dependencies_check,
  add constraint pachanga_venue_wave9b_publish_dependencies_check check (
    not competition_venue_allocation_publish_enabled
    or (competition_venue_allocation_foundation_enabled
      and venue_canonical_reservations_enabled and venue_match_binding_enabled)
  ),
  drop constraint if exists pachanga_venue_wave9b_demo_dependencies_check,
  add constraint pachanga_venue_wave9b_demo_dependencies_check check (
    not demo_world_v35_enabled or demo_world_v34_enabled
  ),
  drop constraint if exists pachanga_venue_wave9b_future_off_check,
  add constraint pachanga_venue_wave9b_future_off_check check (
    not joint_schedule_venue_optimization_enabled
    and not venue_public_recurring_sales_enabled
    and not venue_external_calendar_enabled
  );

alter table public.pachanga_venue_invalidations
  drop constraint if exists pachanga_venue_invalidations_entity_type_check;
alter table public.pachanga_venue_invalidations
  add constraint pachanga_venue_invalidations_entity_type_check check (entity_type in (
    'venue', 'pitch', 'availability', 'exception', 'reservation_request',
    'hold', 'reservation', 'venue_binding', 'canonical_match', 'venue_health',
    'recurring_series', 'recurring_occurrence', 'venue_pool',
    'venue_pool_authorization', 'venue_allocation_plan',
    'venue_allocation_revision', 'venue_allocation_health'
  ));

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_venue_recurring_series',
    'pachanga_venue_recurring_exceptions',
    'pachanga_venue_recurring_occurrences',
    'pachanga_competition_venue_pools',
    'pachanga_competition_venue_authorizations',
    'pachanga_competition_venue_pool_memberships',
    'pachanga_competition_venue_allocation_plans',
    'pachanga_competition_venue_allocation_revisions',
    'pachanga_competition_venue_allocation_items',
    'pachanga_competition_venue_allocation_constraints',
    'pachanga_competition_venue_allocation_locks',
    'pachanga_competition_venue_allocation_holds'
  ] loop
    execute format('alter table public.%I enable row level security', target_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', target_table);
  end loop;
end;
$$;

create or replace function private.pachanga_venue_allocation_revision_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'UPDATE'
     and old.result_checksum = repeat('0', 64)
     and new.result_checksum <> repeat('0', 64)
     and (to_jsonb(new) - array[
       'result_checksum', 'candidate_count', 'assigned_count', 'unassigned_count',
       'hard_violation_count', 'quality_score', 'status', 'validation_status'
     ]) = (to_jsonb(old) - array[
       'result_checksum', 'candidate_count', 'assigned_count', 'unassigned_count',
       'hard_violation_count', 'quality_score', 'status', 'validation_status'
     ]) then
    return new;
  end if;
  raise exception 'VENUE_IMMUTABLE_HISTORY' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_venue_allocation_revision_immutable_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_immutable_history_v1
  on public.pachanga_competition_venue_allocation_revisions;
create trigger pachanga_venue_immutable_history_v1
before update or delete on public.pachanga_competition_venue_allocation_revisions
for each row execute function private.pachanga_venue_allocation_revision_immutable_v1();

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_venue_recurring_series_revisions',
    'pachanga_competition_venue_pool_revisions',
    'pachanga_competition_venue_allocation_input_freezes',
    'pachanga_competition_venue_allocation_diffs',
    'pachanga_competition_venue_allocation_conflicts',
    'pachanga_competition_venue_allocation_quality_snapshots',
    'pachanga_competition_venue_allocation_validations'
  ] loop
    execute format('revoke all on table private.%I from public, anon, authenticated', target_table);
  end loop;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_venue_recurring_series',
    'pachanga_venue_recurring_occurrences',
    'pachanga_competition_venue_pools',
    'pachanga_competition_venue_authorizations',
    'pachanga_competition_venue_pool_memberships',
    'pachanga_competition_venue_allocation_plans',
    'pachanga_competition_venue_allocation_items',
    'pachanga_competition_venue_allocation_constraints'
  ] loop
    execute format('drop trigger if exists pachanga_venue_touch_updated_at_v1 on public.%I', target_table);
    execute format(
      'create trigger pachanga_venue_touch_updated_at_v1 before update on public.%I '
      || 'for each row execute function private.pachanga_venue_touch_updated_at_v1()',
      target_table
    );
  end loop;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_venue_recurring_series_revisions',
    'pachanga_competition_venue_pool_revisions',
    'pachanga_competition_venue_allocation_input_freezes',
    'pachanga_competition_venue_allocation_diffs',
    'pachanga_competition_venue_allocation_quality_snapshots',
    'pachanga_competition_venue_allocation_validations'
  ] loop
    execute format('drop trigger if exists pachanga_venue_immutable_history_v1 on private.%I', target_table);
    execute format(
      'create trigger pachanga_venue_immutable_history_v1 before update or delete on private.%I '
      || 'for each row execute function private.pachanga_venue_immutable_history_v1()',
      target_table
    );
  end loop;
end;
$$;

create index if not exists pachanga_recurring_occurrence_series_status_idx
  on public.pachanga_venue_recurring_occurrences(
    series_id, status, occurrence_date, server_sequence, id
  );
create index if not exists pachanga_recurring_series_owner_status_idx
  on public.pachanga_venue_recurring_series(
    owner_club_id, status, start_date, end_date, server_sequence desc, id
  );
create index if not exists pachanga_venue_authorization_active_window_idx
  on public.pachanga_competition_venue_authorizations(
    pool_id, status, valid_from, valid_until, priority, server_sequence, id
  );
create index if not exists pachanga_venue_pool_membership_allocator_idx
  on public.pachanga_competition_venue_pool_memberships(
    pool_id, status, modality, priority, consumed_count, server_sequence, id
  );
create index if not exists pachanga_venue_allocation_item_revision_status_idx
  on public.pachanga_competition_venue_allocation_items(
    allocation_revision_id, assignment_status, scheduled_start, server_sequence, id
  );
create index if not exists pachanga_venue_allocation_validation_order_idx
  on private.pachanga_competition_venue_allocation_validations(
    allocation_plan_id, server_sequence desc, id
  );

create or replace function private.pachanga_venue_allocation_hold_state_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare allocation_hold public.pachanga_competition_venue_allocation_holds%rowtype;
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare invalidation_sequence bigint;
begin
  if old.status = new.status or new.status not in ('EXPIRED', 'RELEASED') then
    return new;
  end if;
  update public.pachanga_competition_venue_allocation_holds rows set
    status = lower(new.status), revision = rows.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    released_at = coalesce(new.released_at, clock_timestamp())
  where rows.wave9a_hold_id = new.id and rows.status = 'active'
  returning * into allocation_hold;
  if not found then return new; end if;

  update public.pachanga_competition_venue_allocation_plans rows set
    status = case when rows.status not in ('published','cancelled') then 'stale' else rows.status end,
    revision = rows.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_at = clock_timestamp()
  where rows.id = allocation_hold.allocation_plan_id
  returning * into plan_row;
  invalidation_sequence := nextval('private.pachanga_venue_sequence');
  insert into public.pachanga_venue_invalidations(
    server_sequence, entity_type, entity_id, revision, audience_kind, audience_id
  ) values (
    invalidation_sequence, 'venue_allocation_plan', plan_row.id::text,
    plan_row.revision, 'COMPETITION', plan_row.competition_id
  );
  return new;
end;
$$;

revoke all on function private.pachanga_venue_allocation_hold_state_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_allocation_hold_state_v1
  on public.pachanga_venue_reservation_holds;
create trigger pachanga_venue_allocation_hold_state_v1
after update of status on public.pachanga_venue_reservation_holds
for each row execute function private.pachanga_venue_allocation_hold_state_v1();

create or replace function private.pachanga_venue_allocation_notify_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare recipient uuid;
declare target_competition_id uuid;
declare target_club_id uuid;
declare target_team_id uuid;
declare target_kind text;
declare target_title text;
declare target_body text;
declare target_url text;
begin
  if new.aggregate_type not in (
    'recurring_series','venue_pool','venue_pool_authorization','venue_allocation_plan'
  ) then return new; end if;

  if new.aggregate_type = 'recurring_series' then
    select series.competition_id, series.owner_club_id, series.team_id
      into target_competition_id, target_club_id, target_team_id
    from public.pachanga_venue_recurring_series series
    where series.id = new.aggregate_id::uuid;
    target_kind := case new.action
      when 'recurring_series.offer' then 'venue_recurring_block_offered'
      when 'recurring_series.accept' then 'venue_recurring_block_accepted'
      when 'recurring_series.publish' then 'venue_recurring_block_published'
      when 'recurring_series.pause' then 'venue_recurring_block_paused'
      when 'recurring_series.end' then 'venue_recurring_block_ended'
      when 'recurring_series.cancel' then 'venue_recurring_block_cancelled'
      else null end;
    target_title := case new.action
      when 'recurring_series.offer' then 'Bloque recurrente propuesto'
      when 'recurring_series.accept' then 'Bloque recurrente aceptado'
      when 'recurring_series.publish' then 'Bloque recurrente publicado'
      when 'recurring_series.pause' then 'Bloque recurrente pausado'
      when 'recurring_series.end' then 'Bloque recurrente finalizado'
      else 'Bloque recurrente cancelado' end;
    target_body := 'Revisa el calendario confirmado y su estado actual.';
    target_url := '/reservas/recurrentes/' || new.aggregate_id;
  elsif new.aggregate_type in ('venue_pool','venue_pool_authorization') then
    if new.aggregate_type = 'venue_pool' then
      select pools.competition_id into target_competition_id
      from public.pachanga_competition_venue_pools pools
      where pools.id = new.aggregate_id::uuid;
    else
      select authorizations.competition_id, authorizations.owner_club_id
        into target_competition_id, target_club_id
      from public.pachanga_competition_venue_authorizations authorizations
      where authorizations.id = new.aggregate_id::uuid;
    end if;
    target_kind := case new.action
      when 'venue_pool.offer' then 'competition_venue_pool_offered'
      when 'venue_pool.accept' then 'competition_venue_pool_accepted'
      when 'venue_pool.activate' then 'competition_venue_pool_activated'
      when 'venue_pool.revoke' then 'competition_venue_pool_revoked'
      else null end;
    target_title := case new.action
      when 'venue_pool.offer' then 'Campo ofrecido a la competición'
      when 'venue_pool.accept' then 'Campo aceptado para la competición'
      when 'venue_pool.activate' then 'Pool de campos activo'
      else 'Autorización de campo revocada' end;
    target_body := 'La autoridad de campos de la competición ha cambiado.';
    target_url := '/competiciones/' || target_competition_id::text || '/gestion/campos';
  else
    select plans.competition_id into target_competition_id
    from public.pachanga_competition_venue_allocation_plans plans
    where plans.id = new.aggregate_id::uuid;
    target_kind := case new.action
      when 'allocation.hold' then 'competition_venue_allocation_held'
      when 'allocation.publish' then 'competition_venue_allocation_published'
      when 'allocation.cancel' then 'competition_venue_allocation_cancelled'
      else null end;
    target_title := case new.action
      when 'allocation.hold' then 'Campos bloqueados temporalmente'
      when 'allocation.publish' then 'Plan de campos publicado'
      else 'Plan de campos cancelado' end;
    target_body := 'Consulta la revisión canónica y sus asignaciones.';
    target_url := '/competiciones/' || target_competition_id::text || '/gestion/campos/plan';
  end if;
  if target_kind is null then return new; end if;

  for recipient in
    select distinct recipients.user_id from (
      select assignments.user_id
      from public.pachanga_competition_staff_assignments assignments
      where assignments.competition_id = target_competition_id and assignments.status = 'active'
      union all
      select memberships.user_id
      from public.pachanga_club_memberships memberships
      where memberships.club_id = target_club_id and memberships.status = 'active'
        and memberships.role in ('club_owner','club_admin','club_reservation_manager','club_venue_manager')
      union all
      select members.user_id
      from public.pachanga_group_members members
      where members.group_id = target_team_id and members.role in ('owner','admin')
    ) recipients
  loop
    perform private.pachanga_notify_v1(
      recipient, target_kind, target_title, target_body, target_url,
      jsonb_strip_nulls(jsonb_build_object(
        'aggregateType',new.aggregate_type,'aggregateId',new.aggregate_id,
        'competitionId',target_competition_id,'serverSequence',new.server_sequence
      )),
      'venue-wave9b:' || new.id::text || ':' || recipient::text
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.pachanga_venue_allocation_notify_event_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_allocation_notify_event_v1
  on private.pachanga_venue_events;
create trigger pachanga_venue_allocation_notify_event_v1
after insert on private.pachanga_venue_events
for each row execute function private.pachanga_venue_allocation_notify_event_v1();

create or replace function public.get_pachanga_venue_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'venueFoundationEnabled',settings.venue_foundation_enabled,
    'venueManagementEnabled',settings.venue_management_enabled,
    'venuePublicProfilesEnabled',settings.venue_public_profiles_enabled,
    'venuePublicDirectoryEnabled',settings.venue_public_directory_enabled,
    'venueAvailabilityEnabled',settings.venue_availability_enabled,
    'venueReservationRequestsEnabled',settings.venue_reservation_requests_enabled,
    'venueCounteroffersEnabled',settings.venue_counteroffers_enabled,
    'venueReservationHoldsEnabled',settings.venue_reservation_holds_enabled,
    'venueCanonicalReservationsEnabled',settings.venue_canonical_reservations_enabled,
    'venueMatchBindingEnabled',settings.venue_match_binding_enabled,
    'venueR4dIntegrationEnabled',settings.venue_r4d_integration_enabled,
    'demoWorldV34Enabled',settings.demo_world_v34_enabled,
    'demoWorldV35Enabled',settings.demo_world_v35_enabled,
    'venuePaymentsEnabled',settings.venue_payments_enabled,
    'venueRecurringBookingsEnabled',settings.venue_recurring_bookings_enabled,
    'venueBulkCompetitionAllocationEnabled',settings.venue_bulk_competition_allocation_enabled,
    'venueExternalIntegrationsEnabled',settings.venue_external_integrations_enabled,
    'venueRecurringSeriesEnabled',settings.venue_recurring_series_enabled,
    'venueRecurringMaterializationEnabled',settings.venue_recurring_materialization_enabled,
    'venuePublicRecurringSalesEnabled',settings.venue_public_recurring_sales_enabled,
    'venueExternalCalendarEnabled',settings.venue_external_calendar_enabled,
    'competitionVenuePoolEnabled',settings.competition_venue_pool_enabled,
    'competitionVenueAllocationFoundationEnabled',settings.competition_venue_allocation_foundation_enabled,
    'competitionVenueAllocationAutomaticEnabled',settings.competition_venue_allocation_automatic_enabled,
    'competitionVenueAllocationManualEnabled',settings.competition_venue_allocation_manual_enabled,
    'competitionVenueAllocationHybridEnabled',settings.competition_venue_allocation_hybrid_enabled,
    'competitionVenueAllocationHoldsEnabled',settings.competition_venue_allocation_holds_enabled,
    'competitionVenueAllocationPublishEnabled',settings.competition_venue_allocation_publish_enabled,
    'jointScheduleVenueOptimizationEnabled',settings.joint_schedule_venue_optimization_enabled,
    'revision',settings.revision,'serverSequence',settings.server_sequence,
    'updatedAt',settings.updated_at
  ) from private.pachanga_venue_settings_v1 settings where settings.singleton;
$$;

revoke all on function public.get_pachanga_venue_flags_v1() from public;
grant execute on function public.get_pachanga_venue_flags_v1()
  to anon, authenticated, service_role;

create or replace function public.set_pachanga_venue_flags_v1(
  operation_id uuid,
  expected_revision bigint,
  flag_updates jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare actor_kind text:='authenticated';
declare updates jsonb:=coalesce(flag_updates,'{}'::jsonb);
declare settings private.pachanga_venue_settings_v1%rowtype;
declare receipt private.pachanga_venue_operation_receipts%rowtype;
declare request_hash text;
declare metadata jsonb;
declare sequence_value bigint;
declare response jsonb;
begin
  if operation_id is null or expected_revision is null or expected_revision<1
     or jsonb_typeof(updates)<>'object'
     or jsonb_typeof(coalesce(client_metadata,'{}'::jsonb))<>'object'
     or exists(select 1 from jsonb_each(updates) pairs where jsonb_typeof(pairs.value)<>'boolean')
     or exists(select 1 from jsonb_object_keys(updates) keys(key) where keys.key<>all(array[
       'venueFoundationEnabled','venueManagementEnabled','venuePublicProfilesEnabled',
       'venuePublicDirectoryEnabled','venueAvailabilityEnabled','venueReservationRequestsEnabled',
       'venueCounteroffersEnabled','venueReservationHoldsEnabled','venueCanonicalReservationsEnabled',
       'venueMatchBindingEnabled','venueR4dIntegrationEnabled','demoWorldV34Enabled',
       'demoWorldV35Enabled','venuePaymentsEnabled','venueRecurringBookingsEnabled',
       'venueBulkCompetitionAllocationEnabled','venueExternalIntegrationsEnabled',
       'venueRecurringSeriesEnabled','venueRecurringMaterializationEnabled',
       'venuePublicRecurringSalesEnabled','venueExternalCalendarEnabled',
       'competitionVenuePoolEnabled','competitionVenueAllocationFoundationEnabled',
       'competitionVenueAllocationAutomaticEnabled','competitionVenueAllocationManualEnabled',
       'competitionVenueAllocationHybridEnabled','competitionVenueAllocationHoldsEnabled',
       'competitionVenueAllocationPublishEnabled','jointScheduleVenueOptimizationEnabled'
     ])) then raise exception 'VENUE_FLAG_COMMAND_INVALID' using errcode='22023'; end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode='42501';
    end if;
    actor_kind:='service_authority';
  elsif not private.pachanga_club_platform_can_v1(actor_id,'clubs.manage') then
    raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode='42501';
  end if;
  if coalesce((updates->>'venuePaymentsEnabled')::boolean,false)
     or coalesce((updates->>'venueRecurringBookingsEnabled')::boolean,false)
     or coalesce((updates->>'venueBulkCompetitionAllocationEnabled')::boolean,false)
     or coalesce((updates->>'venueExternalIntegrationsEnabled')::boolean,false)
     or coalesce((updates->>'venuePublicRecurringSalesEnabled')::boolean,false)
     or coalesce((updates->>'venueExternalCalendarEnabled')::boolean,false)
     or coalesce((updates->>'jointScheduleVenueOptimizationEnabled')::boolean,false) then
    raise exception 'VENUE_FUTURE_CAPABILITY_NOT_IMPLEMENTED' using errcode='0A000';
  end if;
  metadata:=private.pachanga_venue_client_metadata_v1(client_metadata);
  request_hash:=private.pachanga_venue_request_hash_v1(
    'platform.venue_flags.update',null,expected_revision,updates
  );
  select * into receipt from private.pachanga_venue_operation_receipts receipts
  where receipts.operation_id=set_pachanga_venue_flags_v1.operation_id;
  if found then
    if receipt.actor_id is distinct from actor_id or receipt.actor_kind<>actor_kind
       or receipt.request_hash<>request_hash then
      raise exception 'VENUE_OPERATION_ID_CONFLICT' using errcode='PT409';
    end if;
    return receipt.response;
  end if;
  select * into settings from private.pachanga_venue_settings_v1 rows
  where rows.singleton for update;
  if settings.revision<>expected_revision then
    raise exception 'STALE_REVISION' using errcode='PT409';
  end if;
  sequence_value:=nextval('private.pachanga_venue_sequence');
  update private.pachanga_venue_settings_v1 rows set
    venue_foundation_enabled=coalesce((updates->>'venueFoundationEnabled')::boolean,rows.venue_foundation_enabled),
    venue_management_enabled=coalesce((updates->>'venueManagementEnabled')::boolean,rows.venue_management_enabled),
    venue_public_profiles_enabled=coalesce((updates->>'venuePublicProfilesEnabled')::boolean,rows.venue_public_profiles_enabled),
    venue_public_directory_enabled=coalesce((updates->>'venuePublicDirectoryEnabled')::boolean,rows.venue_public_directory_enabled),
    venue_availability_enabled=coalesce((updates->>'venueAvailabilityEnabled')::boolean,rows.venue_availability_enabled),
    venue_reservation_requests_enabled=coalesce((updates->>'venueReservationRequestsEnabled')::boolean,rows.venue_reservation_requests_enabled),
    venue_counteroffers_enabled=coalesce((updates->>'venueCounteroffersEnabled')::boolean,rows.venue_counteroffers_enabled),
    venue_reservation_holds_enabled=coalesce((updates->>'venueReservationHoldsEnabled')::boolean,rows.venue_reservation_holds_enabled),
    venue_canonical_reservations_enabled=coalesce((updates->>'venueCanonicalReservationsEnabled')::boolean,rows.venue_canonical_reservations_enabled),
    venue_match_binding_enabled=coalesce((updates->>'venueMatchBindingEnabled')::boolean,rows.venue_match_binding_enabled),
    venue_r4d_integration_enabled=coalesce((updates->>'venueR4dIntegrationEnabled')::boolean,rows.venue_r4d_integration_enabled),
    demo_world_v34_enabled=coalesce((updates->>'demoWorldV34Enabled')::boolean,rows.demo_world_v34_enabled),
    demo_world_v35_enabled=coalesce((updates->>'demoWorldV35Enabled')::boolean,rows.demo_world_v35_enabled),
    venue_payments_enabled=coalesce((updates->>'venuePaymentsEnabled')::boolean,rows.venue_payments_enabled),
    venue_recurring_bookings_enabled=coalesce((updates->>'venueRecurringBookingsEnabled')::boolean,rows.venue_recurring_bookings_enabled),
    venue_bulk_competition_allocation_enabled=coalesce((updates->>'venueBulkCompetitionAllocationEnabled')::boolean,rows.venue_bulk_competition_allocation_enabled),
    venue_external_integrations_enabled=coalesce((updates->>'venueExternalIntegrationsEnabled')::boolean,rows.venue_external_integrations_enabled),
    venue_recurring_series_enabled=coalesce((updates->>'venueRecurringSeriesEnabled')::boolean,rows.venue_recurring_series_enabled),
    venue_recurring_materialization_enabled=coalesce((updates->>'venueRecurringMaterializationEnabled')::boolean,rows.venue_recurring_materialization_enabled),
    venue_public_recurring_sales_enabled=coalesce((updates->>'venuePublicRecurringSalesEnabled')::boolean,rows.venue_public_recurring_sales_enabled),
    venue_external_calendar_enabled=coalesce((updates->>'venueExternalCalendarEnabled')::boolean,rows.venue_external_calendar_enabled),
    competition_venue_pool_enabled=coalesce((updates->>'competitionVenuePoolEnabled')::boolean,rows.competition_venue_pool_enabled),
    competition_venue_allocation_foundation_enabled=coalesce((updates->>'competitionVenueAllocationFoundationEnabled')::boolean,rows.competition_venue_allocation_foundation_enabled),
    competition_venue_allocation_automatic_enabled=coalesce((updates->>'competitionVenueAllocationAutomaticEnabled')::boolean,rows.competition_venue_allocation_automatic_enabled),
    competition_venue_allocation_manual_enabled=coalesce((updates->>'competitionVenueAllocationManualEnabled')::boolean,rows.competition_venue_allocation_manual_enabled),
    competition_venue_allocation_hybrid_enabled=coalesce((updates->>'competitionVenueAllocationHybridEnabled')::boolean,rows.competition_venue_allocation_hybrid_enabled),
    competition_venue_allocation_holds_enabled=coalesce((updates->>'competitionVenueAllocationHoldsEnabled')::boolean,rows.competition_venue_allocation_holds_enabled),
    competition_venue_allocation_publish_enabled=coalesce((updates->>'competitionVenueAllocationPublishEnabled')::boolean,rows.competition_venue_allocation_publish_enabled),
    joint_schedule_venue_optimization_enabled=coalesce((updates->>'jointScheduleVenueOptimizationEnabled')::boolean,rows.joint_schedule_venue_optimization_enabled),
    revision=rows.revision+1,server_sequence=sequence_value,
    updated_by=actor_id,updated_at=clock_timestamp()
  where rows.singleton returning * into settings;
  response:=private.pachanga_venue_store_command_v1(
    operation_id,actor_id,actor_kind,'platform.venue_flags.update','venue_settings','singleton',
    settings.revision,sequence_value,request_hash,metadata,'PLATFORM_FLAG_UPDATE',updates,
    public.get_pachanga_venue_flags_v1(),null,null,null,null,null,
    jsonb_build_array(jsonb_build_object(
      'entityType','venue_health','entityId','settings','revision',settings.revision,
      'audienceKind','AUTHENTICATED'
    ))
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_venue_flags_v1(uuid,bigint,jsonb,jsonb)
  from public, anon;
grant execute on function public.set_pachanga_venue_flags_v1(uuid,bigint,jsonb,jsonb)
  to authenticated, service_role;

comment on function public.command_pachanga_competition_venue_allocation_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'Only Wave 9B write authority. Clients send intent, operationId and expected revision; PostgreSQL returns the confirmed canonical snapshot.';
comment on function public.get_pachanga_competition_venue_allocation_desk_v1(uuid) is
  'Canonical season Venue planner read model. Realtime invalidates this snapshot; WAL payload is never applied as authority.';

reset statement_timeout;
reset lock_timeout;
