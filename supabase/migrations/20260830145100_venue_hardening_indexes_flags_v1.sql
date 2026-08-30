-- Pachangas IQ Wave 9A: hardening, support indexes and versioned flag authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_venue_touch_updated_at_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.pachanga_venue_touch_updated_at_v1()
  from public, anon, authenticated;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_club_venues','pachanga_venue_pitches',
    'pachanga_venue_availability_templates','pachanga_venue_availability_exceptions',
    'pachanga_venue_reservation_requests','pachanga_venue_reservations',
    'pachanga_venue_match_bindings'
  ] loop
    execute format('drop trigger if exists pachanga_venue_touch_updated_at_v1 on public.%I',target_table);
    execute format('create trigger pachanga_venue_touch_updated_at_v1 before update on public.%I for each row execute function private.pachanga_venue_touch_updated_at_v1()',target_table);
  end loop;
end;
$$;

create or replace function private.pachanga_venue_immutable_history_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'VENUE_IMMUTABLE_HISTORY' using errcode='55000';
end;
$$;

revoke all on function private.pachanga_venue_immutable_history_v1()
  from public, anon, authenticated;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_club_venue_revisions','pachanga_venue_pitch_revisions',
    'pachanga_venue_availability_template_revisions',
    'pachanga_venue_availability_exception_revisions',
    'pachanga_venue_reservation_request_revisions',
    'pachanga_venue_reservation_terms','pachanga_venue_reservation_revisions',
    'pachanga_venue_match_binding_revisions','pachanga_venue_operation_receipts',
    'pachanga_venue_events'
  ] loop
    execute format('drop trigger if exists pachanga_venue_immutable_history_v1 on private.%I',target_table);
    execute format('create trigger pachanga_venue_immutable_history_v1 before update or delete on private.%I for each row execute function private.pachanga_venue_immutable_history_v1()',target_table);
  end loop;
end;
$$;

create index if not exists pachanga_club_venue_revisions_actor_idx
  on private.pachanga_club_venue_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_publication_consents_actor_idx
  on private.pachanga_venue_publication_consents(consented_by,server_sequence desc,id);
create index if not exists pachanga_venue_pitch_revisions_actor_idx
  on private.pachanga_venue_pitch_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_template_revisions_actor_idx
  on private.pachanga_venue_availability_template_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_exception_revisions_actor_idx
  on private.pachanga_venue_availability_exception_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_request_revisions_actor_idx
  on private.pachanga_venue_reservation_request_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_terms_request_idx
  on private.pachanga_venue_reservation_terms(request_id,server_sequence desc,id);
create index if not exists pachanga_venue_reservation_revisions_actor_idx
  on private.pachanga_venue_reservation_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_binding_revisions_actor_idx
  on private.pachanga_venue_match_binding_revisions(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_receipts_actor_idx
  on private.pachanga_venue_operation_receipts(actor_id,server_sequence desc,id);
create index if not exists pachanga_venue_events_venue_idx
  on private.pachanga_venue_events(venue_id,server_sequence desc,id);
create index if not exists pachanga_venue_events_request_idx
  on private.pachanga_venue_events(request_id,server_sequence desc,id);
create index if not exists pachanga_venue_events_match_idx
  on private.pachanga_venue_events(canonical_match_id,server_sequence desc,id);
create index if not exists pachanga_venue_pitches_parent_idx
  on public.pachanga_venue_pitches(parent_pitch_id,id) where parent_pitch_id is not null;
create index if not exists pachanga_venue_requests_rule_idx
  on public.pachanga_venue_reservation_requests(rule_revision_id,id) where rule_revision_id is not null;
create index if not exists pachanga_venue_requests_match_idx
  on public.pachanga_venue_reservation_requests(canonical_match_id,server_sequence desc,id) where canonical_match_id is not null;
create index if not exists pachanga_venue_holds_claim_idx
  on public.pachanga_venue_reservation_holds(claim_id,id);
create index if not exists pachanga_venue_reservations_terms_idx
  on public.pachanga_venue_reservations(terms_id,id);
create index if not exists pachanga_venue_reservations_claim_idx
  on public.pachanga_venue_reservations(claim_id,id);
create index if not exists pachanga_venue_reservations_venue_status_idx
  on public.pachanga_venue_reservations(venue_id,status,server_sequence desc,id);
create index if not exists pachanga_venue_bindings_fixture_idx
  on public.pachanga_venue_match_bindings(fixture_change_id,fixture_change_revision_id,id)
  where fixture_change_id is not null;

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
     or jsonb_typeof(updates)<>'object' or jsonb_typeof(coalesce(client_metadata,'{}'::jsonb))<>'object'
     or exists(select 1 from jsonb_object_keys(updates) keys(key) where keys.key<>all(array[
       'venueFoundationEnabled','venueManagementEnabled','venuePublicProfilesEnabled',
       'venuePublicDirectoryEnabled','venueAvailabilityEnabled','venueReservationRequestsEnabled',
       'venueCounteroffersEnabled','venueReservationHoldsEnabled','venueCanonicalReservationsEnabled',
       'venueMatchBindingEnabled','venueR4dIntegrationEnabled','demoWorldV34Enabled',
       'venuePaymentsEnabled','venueRecurringBookingsEnabled',
       'venueBulkCompetitionAllocationEnabled','venueExternalIntegrationsEnabled'
     ])) then raise exception 'VENUE_FLAG_COMMAND_INVALID' using errcode='22023'; end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode='42501'; end if;
    actor_kind:='service_authority';
  elsif not private.pachanga_club_platform_can_v1(actor_id,'clubs.manage') then
    raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode='42501';
  end if;
  if coalesce((updates->>'venuePaymentsEnabled')::boolean,false)
     or coalesce((updates->>'venueRecurringBookingsEnabled')::boolean,false)
     or coalesce((updates->>'venueBulkCompetitionAllocationEnabled')::boolean,false)
     or coalesce((updates->>'venueExternalIntegrationsEnabled')::boolean,false) then
    raise exception 'VENUE_FUTURE_CAPABILITY_NOT_IMPLEMENTED' using errcode='0A000';
  end if;
  metadata:=private.pachanga_venue_client_metadata_v1(client_metadata);
  request_hash:=private.pachanga_venue_request_hash_v1('platform.venue_flags.update',null,expected_revision,updates);
  select * into receipt from private.pachanga_venue_operation_receipts receipts where receipts.operation_id=set_pachanga_venue_flags_v1.operation_id;
  if found then
    if receipt.actor_id is distinct from actor_id or receipt.actor_kind<>actor_kind or receipt.request_hash<>request_hash then raise exception 'VENUE_OPERATION_ID_CONFLICT' using errcode='PT409'; end if;
    return receipt.response;
  end if;
  select * into settings from private.pachanga_venue_settings_v1 rows where rows.singleton for update;
  if settings.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
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
    venue_payments_enabled=coalesce((updates->>'venuePaymentsEnabled')::boolean,rows.venue_payments_enabled),
    venue_recurring_bookings_enabled=coalesce((updates->>'venueRecurringBookingsEnabled')::boolean,rows.venue_recurring_bookings_enabled),
    venue_bulk_competition_allocation_enabled=coalesce((updates->>'venueBulkCompetitionAllocationEnabled')::boolean,rows.venue_bulk_competition_allocation_enabled),
    venue_external_integrations_enabled=coalesce((updates->>'venueExternalIntegrationsEnabled')::boolean,rows.venue_external_integrations_enabled),
    revision=rows.revision+1,server_sequence=sequence_value,updated_by=actor_id,updated_at=clock_timestamp()
  where rows.singleton returning * into settings;
  response:=private.pachanga_venue_store_command_v1(
    operation_id,actor_id,actor_kind,'platform.venue_flags.update','venue_settings','singleton',
    settings.revision,sequence_value,request_hash,metadata,'PLATFORM_FLAG_UPDATE',updates,
    public.get_pachanga_venue_flags_v1(),null,null,null,null,null,
    jsonb_build_array(jsonb_build_object('entityType','venue_health','entityId','settings','revision',settings.revision,'audienceKind','AUTHENTICATED'))
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_venue_flags_v1(uuid,bigint,jsonb,jsonb)
  from public,anon;
grant execute on function public.set_pachanga_venue_flags_v1(uuid,bigint,jsonb,jsonb)
  to authenticated,service_role;

create or replace function public.expire_pachanga_venue_holds_v1(
  operation_id uuid,
  batch_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_venue_operation_receipts%rowtype;
declare selected_hold public.pachanga_venue_reservation_holds%rowtype;
declare child_operation_id uuid;
declare expired_count integer:=0;
declare sequence_value bigint;
declare request_hash text;
declare response jsonb;
begin
  if not private.pachanga_competition_is_service_authority_v1() then raise exception 'VENUE_SERVICE_AUTHORITY_REQUIRED' using errcode='42501'; end if;
  if operation_id is null or batch_limit not between 1 and 500 then raise exception 'VENUE_HOLD_EXPIRY_BATCH_INVALID' using errcode='22023'; end if;
  request_hash:=private.pachanga_venue_request_hash_v1('reservation.hold.expire.batch',null,0,jsonb_build_object('batchLimit',batch_limit));
  select * into receipt from private.pachanga_venue_operation_receipts receipts where receipts.operation_id=expire_pachanga_venue_holds_v1.operation_id;
  if found then
    if receipt.actor_id is not null or receipt.actor_kind<>'service_authority' or receipt.request_hash<>request_hash then raise exception 'VENUE_OPERATION_ID_CONFLICT' using errcode='PT409'; end if;
    return receipt.response;
  end if;
  perform private.pachanga_venue_assert_flags_v1('hold');
  for selected_hold in
    select holds.* from public.pachanga_venue_reservation_holds holds
    where holds.status='ACTIVE' and holds.expires_at<=clock_timestamp()
    order by holds.expires_at,holds.server_sequence,holds.id limit batch_limit
  loop
    child_operation_id:=private.pachanga_venue_deterministic_uuid_v1('hold-expire:'||selected_hold.id::text||':'||selected_hold.revision::text);
    perform public.command_pachanga_venue_reservation_v1(child_operation_id,selected_hold.id,selected_hold.revision,'reservation.hold.expire',jsonb_build_object('reasonCode','SERVER_EXPIRY'),'{}'::jsonb);
    expired_count:=expired_count+1;
  end loop;
  sequence_value:=nextval('private.pachanga_venue_sequence');
  response:=private.pachanga_venue_store_command_v1(
    operation_id,null,'service_authority','reservation.hold.expire.batch','hold_expiry_batch',operation_id::text,
    expired_count,sequence_value,request_hash,'{}'::jsonb,'SERVER_EXPIRY_BATCH',
    jsonb_build_object('expiredCount',expired_count),jsonb_build_object('expiredCount',expired_count),
    null,null,null,null,null,'[]'::jsonb
  );
  return response;
end;
$$;

revoke all on function public.expire_pachanga_venue_holds_v1(uuid,integer)
  from public,anon,authenticated;
grant execute on function public.expire_pachanga_venue_holds_v1(uuid,integer)
  to service_role;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_venue_pitch_scope_v1()'::regprocedure,
    'private.pachanga_venue_resolve_local_v1(timestamp without time zone,text,integer)'::regprocedure,
    'private.pachanga_venue_offset_minutes_v1(timestamptz,text)'::regprocedure,
    'private.pachanga_venue_deterministic_uuid_v1(text)'::regprocedure,
    'private.pachanga_venue_client_metadata_v1(jsonb)'::regprocedure,
    'private.pachanga_venue_request_hash_v1(text,uuid,bigint,jsonb)'::regprocedure,
    'private.pachanga_venue_allowed_payload_v1(text,jsonb)'::regprocedure,
    'private.pachanga_venue_public_fingerprint_v1(uuid)'::regprocedure,
    'private.pachanga_venue_assert_flags_v1(text)'::regprocedure,
    'private.pachanga_venue_requester_can_v1(text,uuid,uuid,uuid,uuid)'::regprocedure,
    'private.pachanga_venue_request_owned_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_venue_assert_slot_v1(uuid,timestamptz,timestamptz,text,uuid)'::regprocedure,
    'private.pachanga_venue_store_command_v1(uuid,uuid,text,text,text,text,bigint,bigint,text,jsonb,text,jsonb,jsonb,uuid,uuid,uuid,uuid,uuid,jsonb)'::regprocedure,
    'private.pachanga_venue_append_revision_v1(text,uuid,bigint,text,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_venue_publicly_visible_v1(uuid,boolean)'::regprocedure,
    'private.pachanga_venue_private_location_can_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_venue_public_projection_v1(uuid)'::regprocedure,
    'private.pachanga_venue_slot_is_available_v1(uuid,timestamptz,timestamptz,text)'::regprocedure,
    'private.pachanga_venue_health_v1()'::regprocedure,
    'private.pachanga_venue_notify_event_v1()'::regprocedure,
    'private.pachanga_venue_consume_completed_match_v1()'::regprocedure,
    'private.pachanga_venue_touch_updated_at_v1()'::regprocedure,
    'private.pachanga_venue_immutable_history_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public,anon,authenticated',signature);
  end loop;
end;
$$;

comment on function public.command_pachanga_venue_reservation_v1(uuid,uuid,bigint,text,jsonb,jsonb) is
  'Only Venue write authority. Client sends intent, operationId and expectedRevision; PostgreSQL returns the confirmed snapshot.';
comment on function public.expire_pachanga_venue_holds_v1(uuid,integer) is
  'Idempotent service worker for server-time hold expiry. It never creates or cancels a sporting match.';

reset statement_timeout;
reset lock_timeout;
