-- Pachangas IQ Wave 9A: RLS, scoped Realtime invalidation and idempotent notifications.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_club_venues','pachanga_venue_pitches',
    'pachanga_venue_availability_templates','pachanga_venue_availability_exceptions',
    'pachanga_venue_reservation_requests','pachanga_venue_pitch_claims',
    'pachanga_venue_reservation_holds','pachanga_venue_reservations',
    'pachanga_venue_match_bindings','pachanga_venue_invalidations'
  ] loop
    execute format('alter table public.%I enable row level security', target_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', target_table);
  end loop;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_venue_settings_v1','pachanga_club_venue_revisions',
    'pachanga_venue_publication_consents','pachanga_venue_pitch_revisions',
    'pachanga_venue_availability_template_revisions',
    'pachanga_venue_availability_exception_revisions',
    'pachanga_venue_availability_occurrences',
    'pachanga_venue_reservation_request_revisions',
    'pachanga_venue_reservation_terms','pachanga_venue_reservation_revisions',
    'pachanga_venue_match_binding_revisions','pachanga_venue_operation_receipts',
    'pachanga_venue_events'
  ] loop
    execute format('revoke all on table private.%I from public, anon, authenticated', target_table);
  end loop;
end;
$$;

drop policy if exists pachanga_venue_invalidations_public_v1 on public.pachanga_venue_invalidations;
create policy pachanga_venue_invalidations_public_v1
on public.pachanga_venue_invalidations
for select to anon
using (audience_kind = 'PUBLIC');

drop policy if exists pachanga_venue_invalidations_authenticated_v1 on public.pachanga_venue_invalidations;
create policy pachanga_venue_invalidations_authenticated_v1
on public.pachanga_venue_invalidations
for select to authenticated
using (
  audience_kind in ('PUBLIC','AUTHENTICATED')
  or (audience_kind = 'USER' and audience_id = (select auth.uid()))
  or (audience_kind = 'CLUB' and private.pachanga_club_can_v1(
    audience_id, (select auth.uid()), 'venue_read'
  ))
  or (audience_kind = 'TEAM' and (
    exists (select 1 from public.pachanga_groups groups
      where groups.id = audience_id and groups.owner_id = (select auth.uid()))
    or exists (select 1 from public.pachanga_group_members members
      where members.group_id = audience_id and members.user_id = (select auth.uid()))
  ))
  or (audience_kind = 'COMPETITION' and private.pachanga_competition_can_v1(
    audience_id, (select auth.uid()), 'read'
  ))
);

grant select on table public.pachanga_venue_invalidations to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication_tables tables
    where tables.pubname = 'supabase_realtime'
      and tables.schemaname = 'public'
      and tables.tablename = 'pachanga_venue_invalidations'
  ) then
    alter publication supabase_realtime add table public.pachanga_venue_invalidations;
  end if;
end;
$$;

create or replace function private.pachanga_venue_notify_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare request_row public.pachanga_venue_reservation_requests%rowtype;
declare venue_row public.pachanga_club_venues%rowtype;
declare recipient uuid;
declare notification_kind text;
declare notification_title text;
declare notification_body text;
begin
  if new.request_id is null then return new; end if;
  select * into request_row from public.pachanga_venue_reservation_requests requests
  where requests.id = new.request_id;
  if not found then return new; end if;
  select * into venue_row from public.pachanga_club_venues venues
  where venues.id = request_row.venue_id;
  notification_kind := case new.action
    when 'reservation.request.submit' then 'venue_reservation_request_received'
    when 'reservation.counter' then 'venue_reservation_counterproposal'
    when 'reservation.hold' then 'venue_reservation_hold_created'
    when 'reservation.hold.expire' then 'venue_reservation_hold_expired'
    when 'reservation.accept' then 'venue_reservation_accepted'
    when 'reservation.confirm' then 'venue_reservation_confirmed'
    when 'reservation.reject' then 'venue_reservation_rejected'
    when 'reservation.cancel' then 'venue_reservation_cancelled'
    when 'reservation.bind_match' then 'venue_match_bound'
    when 'reservation.replace_venue' then 'venue_match_changed'
    else null end;
  if notification_kind is null then return new; end if;
  notification_title := case new.action
    when 'reservation.request.submit' then 'Nueva solicitud de campo'
    when 'reservation.counter' then 'Nueva contrapropuesta'
    when 'reservation.hold' then 'Campo reservado temporalmente'
    when 'reservation.hold.expire' then 'El hold ha expirado'
    when 'reservation.accept' then 'Reserva aceptada'
    when 'reservation.confirm' then 'Reserva confirmada'
    when 'reservation.reject' then 'Reserva rechazada'
    when 'reservation.cancel' then 'Reserva cancelada'
    when 'reservation.bind_match' then 'Campo vinculado al partido'
    when 'reservation.replace_venue' then 'Cambio de sede confirmado'
    else 'Actualización de reserva' end;
  notification_body := case
    when new.action = 'reservation.request.submit'
      then 'Hay una solicitud nueva en el escritorio de reservas.'
    when new.action = 'reservation.counter'
      then 'Revisa el campo, horario y condiciones propuestas.'
    when new.action = 'reservation.hold'
      then 'El campo está bloqueado temporalmente mientras se confirma.'
    when new.action = 'reservation.hold.expire'
      then 'El bloqueo temporal terminó sin crear una reserva.'
    when new.action = 'reservation.accept'
      then 'La solicitud fue aceptada y necesita confirmación.'
    when new.action = 'reservation.confirm'
      then 'La reserva ya está confirmada.'
    when new.action = 'reservation.reject'
      then 'La solicitud no fue aceptada.'
    when new.action = 'reservation.cancel'
      then 'La reserva fue cancelada. El partido no se cancela automáticamente.'
    when new.action = 'reservation.bind_match'
      then 'El partido ya tiene campo y reserva canónicos.'
    else 'El partido conserva su historia y requiere revisar la nueva sede.' end;

  if new.action in ('reservation.request.submit','reservation.confirm') then
    for recipient in
      select distinct memberships.user_id
      from public.pachanga_club_memberships memberships
      where memberships.club_id = venue_row.club_id and memberships.status = 'active'
        and memberships.role in ('club_owner','club_admin','club_reservation_manager')
    loop
      perform private.pachanga_notify_v1(
        recipient, notification_kind, notification_title, notification_body,
        '/clubes/gestionar/reservas?request=' || request_row.id::text,
        jsonb_strip_nulls(jsonb_build_object(
          'requestId',request_row.id,'venueId',request_row.venue_id,
          'reservationId',new.reservation_id,'canonicalMatchId',new.canonical_match_id
        )),
        'venue:' || new.operation_id::text || ':' || recipient::text
      );
    end loop;
  else
    perform private.pachanga_notify_v1(
      request_row.requester_user_id, notification_kind, notification_title,
      notification_body,
      '/reservas/' || coalesce(new.reservation_id::text, request_row.id::text),
      jsonb_strip_nulls(jsonb_build_object(
        'requestId',request_row.id,'venueId',request_row.venue_id,
        'reservationId',new.reservation_id,'canonicalMatchId',new.canonical_match_id
      )),
      'venue:' || new.operation_id::text || ':' || request_row.requester_user_id::text
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_venue_notify_event_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_notify_event_v1 on private.pachanga_venue_events;
create trigger pachanga_venue_notify_event_v1
after insert on private.pachanga_venue_events
for each row execute function private.pachanga_venue_notify_event_v1();

create or replace function private.pachanga_venue_consume_completed_match_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare binding public.pachanga_venue_match_bindings%rowtype;
declare reservation public.pachanga_venue_reservations%rowtype;
declare derived_operation_id uuid;
declare sequence_value bigint;
declare request_hash text;
begin
  if old.status = new.status or new.status <> 'official' then return new; end if;
  select * into binding from public.pachanga_venue_match_bindings bindings
  where bindings.canonical_match_id = new.canonical_match_id
    and bindings.status in ('ACTIVE','ACTION_REQUIRED')
  for update;
  if not found then return new; end if;
  select * into reservation from public.pachanga_venue_reservations reservations
  where reservations.id = binding.reservation_id for update;
  if reservation.status not in ('CONFIRMED','PENDING_CONFIRMATION') then return new; end if;
  derived_operation_id := private.pachanga_venue_deterministic_uuid_v1(
    'match-consumed:' || new.id::text || ':' || new.revision::text
  );
  if exists (select 1 from private.pachanga_venue_operation_receipts receipts
    where receipts.operation_id = derived_operation_id) then return new; end if;
  sequence_value := nextval('private.pachanga_venue_sequence');
  update public.pachanga_venue_match_bindings bindings set
    status='CONSUMED',action_required_code=null,consumed_at=clock_timestamp(),
    binding_revision=bindings.binding_revision+1,server_sequence=sequence_value,
    operation_id=derived_operation_id,updated_at=clock_timestamp()
  where bindings.id=binding.id returning * into binding;
  update public.pachanga_venue_reservations reservations set
    status='CONSUMED',consumed_at=clock_timestamp(),revision=reservations.revision+1,
    server_sequence=sequence_value,operation_id=derived_operation_id,updated_at=clock_timestamp()
  where reservations.id=reservation.id returning * into reservation;
  update public.pachanga_venue_pitch_claims claims set
    status='CONSUMED',released_at=clock_timestamp(),server_sequence=sequence_value,
    operation_id=derived_operation_id
  where claims.id=reservation.claim_id and claims.status='ACTIVE';
  perform private.pachanga_venue_append_revision_v1(
    'venue_binding',binding.id,binding.binding_revision,'reservation.match.consume',
    derived_operation_id,null,sequence_value
  );
  perform private.pachanga_venue_append_revision_v1(
    'reservation',reservation.id,reservation.revision,'reservation.match.consume',
    derived_operation_id,null,sequence_value
  );
  request_hash:=private.pachanga_venue_request_hash_v1(
    'reservation.match.consume',reservation.id,reservation.revision-1,
    jsonb_build_object('canonicalMatchId',new.canonical_match_id,'contextRevision',new.revision)
  );
  perform private.pachanga_venue_store_command_v1(
    derived_operation_id,null,'service_authority','reservation.match.consume',
    'reservation',reservation.id::text,reservation.revision,sequence_value,
    request_hash,'{}'::jsonb,'MATCH_OFFICIAL',
    jsonb_build_object('reservationId',reservation.id,'canonicalMatchId',new.canonical_match_id),
    jsonb_build_object('reservation',to_jsonb(reservation),'binding',to_jsonb(binding)),
    reservation.venue_id,reservation.pitch_id,reservation.request_id,reservation.id,
    new.canonical_match_id,
    jsonb_build_array(
      jsonb_build_object('entityType','reservation','entityId',reservation.id,'revision',reservation.revision,'audienceKind','AUTHENTICATED'),
      jsonb_build_object('entityType','venue_binding','entityId',binding.id,'revision',binding.binding_revision,'audienceKind','AUTHENTICATED')
    )
  );
  return new;
end;
$$;

revoke all on function private.pachanga_venue_consume_completed_match_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_consume_completed_match_v1
  on public.pachanga_competition_match_contexts;
create trigger pachanga_venue_consume_completed_match_v1
after update of status on public.pachanga_competition_match_contexts
for each row execute function private.pachanga_venue_consume_completed_match_v1();

reset statement_timeout;
reset lock_timeout;
