-- Pachangas IQ Wave 9A: one server-authoritative Venue command surface.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table if not exists private.pachanga_venue_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  request_hash text not null check (length(request_hash) = 64),
  confirmed_revision bigint not null check (confirmed_revision >= 0),
  server_sequence bigint not null unique,
  client_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(client_metadata) = 'object'),
  response jsonb not null check (jsonb_typeof(response) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority'))
);

create table if not exists private.pachanga_venue_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  venue_id uuid references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  request_id uuid references public.pachanga_venue_reservation_requests(id) on delete restrict,
  reservation_id uuid references public.pachanga_venue_reservations(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  aggregate_revision bigint not null check (aggregate_revision >= 0),
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(event_payload) = 'object'),
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority'))
);

create table if not exists public.pachanga_venue_invalidations (
  server_sequence bigint primary key,
  entity_type text not null,
  entity_id text not null,
  revision bigint not null check (revision >= 0),
  audience_kind text not null default 'AUTHENTICATED',
  audience_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  check (entity_type in (
    'venue', 'pitch', 'availability', 'exception', 'reservation_request',
    'hold', 'reservation', 'venue_binding', 'canonical_match', 'venue_health'
  )),
  check (audience_kind in ('PUBLIC', 'AUTHENTICATED', 'CLUB', 'TEAM', 'COMPETITION', 'USER')),
  check ((audience_kind in ('PUBLIC', 'AUTHENTICATED') and audience_id is null)
    or (audience_kind not in ('PUBLIC', 'AUTHENTICATED') and audience_id is not null))
);

create index if not exists pachanga_venue_invalidations_entity_idx
  on public.pachanga_venue_invalidations(entity_type, entity_id, server_sequence desc);
create index if not exists pachanga_venue_invalidations_audience_idx
  on public.pachanga_venue_invalidations(audience_kind, audience_id, server_sequence desc);

create or replace function private.pachanga_venue_client_metadata_v1(source jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', nullif(left(coalesce(source ->> 'clientVersion', ''), 80), ''),
    'serviceWorkerVersion', nullif(left(coalesce(source ->> 'serviceWorkerVersion', ''), 80), ''),
    'installedMode', case
      when source ->> 'installedMode' in ('browser', 'standalone', 'fullscreen')
      then source ->> 'installedMode' else null end,
    'sessionId', nullif(left(coalesce(source ->> 'sessionId', ''), 120), ''),
    'surface', nullif(left(coalesce(source ->> 'surface', ''), 120), '')
  ));
$$;

revoke all on function private.pachanga_venue_client_metadata_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(
    coalesce(target_action, '') || '|' || coalesce(target_aggregate_id::text, '') || '|'
    || coalesce(target_expected_revision::text, '') || '|'
    || coalesce(target_payload, '{}'::jsonb)::text,
    'UTF8'
  ), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_venue_request_hash_v1(text, uuid, bigint, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allowed_payload_v1(
  target_action text,
  target_payload jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare allowed text[];
begin
  allowed := case target_action
    when 'venue.create' then array[
      'clubId','name','slug','description','municipality','generalArea','timezone','placeId',
      'privateAddress','publicAddress','privateLatitude','privateLongitude',
      'publicLatitude','publicLongitude','privateAccessInstructions','privateContactName',
      'privateContactPhone','privateContactEmail','visibility','reasonCode'
    ]
    when 'venue.update' then array[
      'name','slug','description','municipality','generalArea','timezone','placeId',
      'privateAddress','publicAddress','privateLatitude','privateLongitude',
      'publicLatitude','publicLongitude','privateAccessInstructions','privateContactName',
      'privateContactPhone','privateContactEmail','visibility','reasonCode'
    ]
    when 'venue.publication.consent' then array['selectedFields','addressMode','publicRateAllowed','reasonCode']
    when 'venue.submit_review' then array['reasonCode']
    when 'venue.activate' then array['reasonCode']
    when 'venue.suspend' then array['reasonCode']
    when 'venue.archive' then array['reasonCode']
    when 'pitch.create' then array[
      'venueId','parentPitchId','name','slug','modalities','surface','environment',
      'widthM','lengthM','hasLighting','hasChangingRooms','hasShowers','isAccessible',
      'hasParking','spectatorCapacity','publicRateKind','publicRateAmountMinor',
      'publicRateCurrency','publicRateNote','visibility','minimumSlotMinutes','bufferMinutes','reasonCode'
    ]
    when 'pitch.update' then array[
      'parentPitchId','name','slug','modalities','surface','environment','widthM','lengthM',
      'hasLighting','hasChangingRooms','hasShowers','isAccessible','hasParking',
      'spectatorCapacity','publicRateKind','publicRateAmountMinor','publicRateCurrency',
      'publicRateNote','visibility','minimumSlotMinutes','bufferMinutes','reasonCode'
    ]
    when 'pitch.maintenance' then array['reasonCode']
    when 'pitch.restore' then array['reasonCode']
    when 'pitch.archive' then array['reasonCode']
    when 'availability.template.create' then array[
      'pitchId','weekday','startLocalTime','endLocalTime','slotMinutes','bufferMinutes',
      'validFrom','validUntil','timezone','modalities','capacity','visibility','reasonCode'
    ]
    when 'availability.template.update' then array[
      'weekday','startLocalTime','endLocalTime','slotMinutes','bufferMinutes','validFrom',
      'validUntil','timezone','modalities','capacity','visibility','reasonCode'
    ]
    when 'availability.template.disable' then array['reasonCode']
    when 'availability.exception.create' then array[
      'pitchId','kind','startsAt','endsAt','publicReason','privateReason','visibility','priority','reasonCode'
    ]
    when 'availability.exception.cancel' then array['reasonCode']
    when 'reservation.request.create' then array[
      'venueId','pitchId','requesterKind','requesterTeamId','requesterClubId','competitionId',
      'canonicalMatchId','ruleRevisionId','purpose','modality','localStart','localEnd',
      'timezone','offsetMinutes','criteria','alternatives','message','reasonCode'
    ]
    when 'reservation.request.update' then array[
      'pitchId','canonicalMatchId','ruleRevisionId','purpose','modality','localStart','localEnd',
      'timezone','offsetMinutes','criteria','alternatives','message','reasonCode'
    ]
    when 'reservation.request.submit' then array['reasonCode']
    when 'reservation.request.withdraw' then array['reasonCode']
    when 'reservation.review.start' then array['reasonCode']
    when 'reservation.counter' then array[
      'pitchId','localStart','localEnd','timezone','offsetMinutes','terms','message','reasonCode'
    ]
    when 'reservation.reject' then array['message','reasonCode']
    when 'reservation.hold' then array[
      'pitchId','localStart','localEnd','timezone','offsetMinutes','expiresInMinutes','reasonCode'
    ]
    when 'reservation.accept' then array[
      'pitchId','localStart','localEnd','timezone','offsetMinutes','terms','reasonCode'
    ]
    when 'reservation.confirm' then array['reasonCode']
    when 'reservation.cancel' then array['reasonCode']
    when 'reservation.bind_match' then array[
      'canonicalMatchId','competitionMatchContextId','scheduleItemId','ruleRevisionId','reasonCode'
    ]
    when 'reservation.unbind_match' then array['reasonCode']
    when 'reservation.replace_venue' then array[
      'competitionMatchContextId','expectedContextRevision','reasonCode','publicSummary'
    ]
    when 'reservation.hold.expire' then array['reasonCode']
    else null
  end;
  if allowed is null then return false; end if;
  return not exists (
    select 1 from jsonb_object_keys(coalesce(target_payload, '{}'::jsonb)) keys(key)
    where not (keys.key = any(allowed))
  );
end;
$$;

revoke all on function private.pachanga_venue_allowed_payload_v1(text, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_public_fingerprint_v1(target_venue_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'name', venues.name,
    'description', venues.description,
    'municipality', venues.municipality,
    'generalArea', venues.general_area,
    'publicAddress', venues.public_address,
    'publicLatitude', venues.public_latitude,
    'publicLongitude', venues.public_longitude,
    'visibility', venues.visibility
  )::text, 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_club_venues venues
  where venues.id = target_venue_id;
$$;

revoke all on function private.pachanga_venue_public_fingerprint_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_assert_flags_v1(target_capability text)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_venue_settings_v1%rowtype;
begin
  select * into settings from private.pachanga_venue_settings_v1 where singleton;
  if not settings.venue_foundation_enabled then
    raise exception 'VENUE_FOUNDATION_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('management','public','availability','request','counter','hold','reservation','binding','r4d')
     and not settings.venue_management_enabled then
    raise exception 'VENUE_MANAGEMENT_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('availability','request','counter','hold','reservation','binding','r4d')
     and not settings.venue_availability_enabled then
    raise exception 'VENUE_AVAILABILITY_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('request','counter','hold','reservation','binding','r4d')
     and not settings.venue_reservation_requests_enabled then
    raise exception 'VENUE_RESERVATION_REQUESTS_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'counter' and not settings.venue_counteroffers_enabled then
    raise exception 'VENUE_COUNTEROFFERS_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'public' and not settings.venue_public_profiles_enabled then
    raise exception 'VENUE_PUBLIC_PROFILES_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'hold' and not settings.venue_reservation_holds_enabled then
    raise exception 'VENUE_HOLDS_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('reservation','binding','r4d')
     and not settings.venue_canonical_reservations_enabled then
    raise exception 'VENUE_CANONICAL_RESERVATIONS_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('binding','r4d') and not settings.venue_match_binding_enabled then
    raise exception 'VENUE_MATCH_BINDING_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'r4d' and not settings.venue_r4d_integration_enabled then
    raise exception 'VENUE_R4D_INTEGRATION_DISABLED' using errcode = '0A000';
  end if;
end;
$$;

revoke all on function private.pachanga_venue_assert_flags_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_requester_can_v1(
  target_kind text,
  target_team_id uuid,
  target_club_id uuid,
  target_competition_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if private.pachanga_competition_is_service_authority_v1() then return true; end if;
  if target_actor_id is null then return false; end if;
  if target_kind = 'TEAM' then
    return exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_team_id and groups.owner_id = target_actor_id
    ) or public.is_pachanga_group_admin(target_team_id);
  elsif target_kind = 'COMPETITION' then
    return private.pachanga_competition_can_v1(
      target_competition_id, target_actor_id, 'operations_manage'
    );
  elsif target_kind = 'CLUB_COMPETITION_STAFF' then
    return private.pachanga_club_can_v1(target_club_id, target_actor_id, 'reservation_request')
      and private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'operations_manage'
      );
  end if;
  return false;
end;
$$;

revoke all on function private.pachanga_venue_requester_can_v1(text, uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_request_owned_v1(
  target_request_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_venue_reservation_requests%rowtype;
begin
  if private.pachanga_competition_is_service_authority_v1() then return true; end if;
  select * into selected from public.pachanga_venue_reservation_requests requests
  where requests.id = target_request_id;
  if not found or target_actor_id is null then return false; end if;
  return selected.requester_user_id = target_actor_id
    or (selected.requester_team_id is not null and public.is_pachanga_group_admin(selected.requester_team_id))
    or (selected.competition_id is not null and private.pachanga_competition_can_v1(
      selected.competition_id, target_actor_id, 'operations_manage'
    ));
end;
$$;

revoke all on function private.pachanga_venue_request_owned_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_assert_slot_v1(
  target_pitch_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_modality text,
  ignored_claim_id uuid default null
)
returns public.pachanga_venue_pitches
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare pitch public.pachanga_venue_pitches%rowtype;
declare venue public.pachanga_club_venues%rowtype;
declare local_start timestamp without time zone;
declare local_end timestamp without time zone;
declare requested_range tstzrange;
declare blocked_range tstzrange;
begin
  select * into pitch from public.pachanga_venue_pitches pitches
  where pitches.id = target_pitch_id for update;
  if not found then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into venue from public.pachanga_club_venues venues where venues.id = pitch.venue_id;
  if venue.lifecycle <> 'ACTIVE' or pitch.status <> 'ACTIVE' then
    raise exception 'VENUE_PITCH_NOT_AVAILABLE' using errcode = 'PT409';
  end if;
  if not (upper(target_modality) = any(pitch.modalities)) then
    raise exception 'VENUE_PITCH_MODALITY_INCOMPATIBLE' using errcode = 'PT409';
  end if;
  if target_ends_at <= target_starts_at
     or target_ends_at > target_starts_at + interval '12 hours' then
    raise exception 'VENUE_SLOT_RANGE_INVALID' using errcode = '22023';
  end if;
  local_start := target_starts_at at time zone venue.timezone;
  local_end := target_ends_at at time zone venue.timezone;
  if local_start::date <> local_end::date then
    raise exception 'VENUE_SLOT_OVERNIGHT_UNSUPPORTED' using errcode = '22023';
  end if;
  requested_range := tstzrange(target_starts_at, target_ends_at, '[)');
  blocked_range := tstzrange(
    target_starts_at - make_interval(mins => pitch.buffer_minutes),
    target_ends_at + make_interval(mins => pitch.buffer_minutes), '[)'
  );
  if not exists (
    select 1
    from public.pachanga_venue_availability_templates templates
    where templates.pitch_id = pitch.id and templates.status = 'ACTIVE'
      and extract(isodow from local_start)::smallint = templates.weekday
      and local_start::date >= templates.valid_from
      and (templates.valid_until is null or local_start::date <= templates.valid_until)
      and local_start::time >= templates.start_local_time
      and local_end::time <= templates.end_local_time
      and upper(target_modality) = any(templates.modalities)
  ) and not exists (
    select 1
    from public.pachanga_venue_availability_exceptions exceptions
    where exceptions.pitch_id = pitch.id and exceptions.status = 'ACTIVE'
      and exceptions.exception_kind = 'SPECIAL_OPENING'
      and exceptions.time_range @> requested_range
  ) then
    raise exception 'VENUE_SLOT_OUTSIDE_AVAILABILITY' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_venue_availability_exceptions exceptions
    where exceptions.pitch_id = pitch.id and exceptions.status = 'ACTIVE'
      and exceptions.exception_kind <> 'SPECIAL_OPENING'
      and exceptions.time_range && requested_range
  ) then
    raise exception 'VENUE_SLOT_BLOCKED' using errcode = 'PT409';
  end if;
  if exists (
    select 1 from public.pachanga_venue_pitch_claims claims
    where claims.conflict_scope_id = pitch.conflict_scope_id
      and claims.status = 'ACTIVE'
      and claims.id is distinct from ignored_claim_id
      and claims.occupied_range && blocked_range
  ) then
    raise exception 'VENUE_SLOT_CONFLICT' using errcode = 'PT409';
  end if;
  return pitch;
end;
$$;

revoke all on function private.pachanga_venue_assert_slot_v1(
  uuid, timestamptz, timestamptz, text, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_venue_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id text,
  target_revision bigint,
  target_sequence bigint,
  target_request_hash text,
  target_metadata jsonb,
  target_reason_code text,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_venue_id uuid default null,
  target_pitch_id uuid default null,
  target_request_id uuid default null,
  target_reservation_id uuid default null,
  target_canonical_match_id uuid default null,
  target_invalidations jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare response jsonb;
declare item jsonb;
declare item_sequence bigint;
begin
  response := jsonb_build_object(
    'ok', true,
    'operationId', target_operation_id,
    'action', target_action,
    'aggregateType', target_aggregate_type,
    'aggregateId', target_aggregate_id,
    'confirmedRevision', target_revision,
    'serverSequence', target_sequence,
    'confirmedAt', clock_timestamp(),
    'snapshot', coalesce(target_snapshot, '{}'::jsonb)
  );
  insert into private.pachanga_venue_events(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    venue_id, pitch_id, request_id, reservation_id, canonical_match_id,
    aggregate_revision, server_sequence, reason_code, event_payload
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_venue_id, target_pitch_id,
    target_request_id, target_reservation_id, target_canonical_match_id,
    target_revision, target_sequence, left(coalesce(nullif(target_reason_code, ''), 'USER_ACTION'), 120),
    coalesce(target_event_payload, '{}'::jsonb)
  );
  for item in select value from jsonb_array_elements(coalesce(target_invalidations, '[]'::jsonb)) loop
    item_sequence := nextval('private.pachanga_venue_sequence');
    insert into public.pachanga_venue_invalidations(
      server_sequence, entity_type, entity_id, revision, audience_kind, audience_id
    ) values (
      item_sequence,
      item ->> 'entityType', item ->> 'entityId',
      coalesce((item ->> 'revision')::bigint, target_revision),
      coalesce(item ->> 'audienceKind', 'AUTHENTICATED'),
      nullif(item ->> 'audienceId', '')::uuid
    );
  end loop;
  insert into private.pachanga_venue_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_request_hash,
    target_revision, target_sequence, coalesce(target_metadata, '{}'::jsonb), response
  );
  return response;
end;
$$;

revoke all on function private.pachanga_venue_store_command_v1(
  uuid, uuid, text, text, text, text, bigint, bigint, text, jsonb, text,
  jsonb, jsonb, uuid, uuid, uuid, uuid, uuid, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_venue_append_revision_v1(
  target_entity text,
  target_id uuid,
  target_revision bigint,
  target_action text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare snapshot jsonb;
declare selected_status text;
begin
  if target_entity = 'venue' then
    select to_jsonb(rows), rows.lifecycle into snapshot, selected_status
    from public.pachanga_club_venues rows where rows.id = target_id;
    insert into private.pachanga_club_venue_revisions(
      venue_id, revision, snapshot, reason_code, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, snapshot, target_action,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'pitch' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_pitches rows where rows.id = target_id;
    insert into private.pachanga_venue_pitch_revisions(
      pitch_id, revision, snapshot, reason_code, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, snapshot, target_action,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'availability_template' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_availability_templates rows where rows.id = target_id;
    insert into private.pachanga_venue_availability_template_revisions(
      template_id, revision, snapshot, reason_code, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, snapshot, target_action,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'availability_exception' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_availability_exceptions rows where rows.id = target_id;
    insert into private.pachanga_venue_availability_exception_revisions(
      exception_id, revision, snapshot, reason_code, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, snapshot, target_action,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'reservation_request' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_reservation_requests rows where rows.id = target_id;
    insert into private.pachanga_venue_reservation_request_revisions(
      request_id, revision, action, status, snapshot, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, target_action, selected_status, snapshot,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'reservation' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_reservations rows where rows.id = target_id;
    insert into private.pachanga_venue_reservation_revisions(
      reservation_id, revision, action, status, snapshot, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, target_action, selected_status, snapshot,
      target_operation_id, target_actor_id, target_server_sequence);
  elsif target_entity = 'venue_binding' then
    select to_jsonb(rows), rows.status into snapshot, selected_status
    from public.pachanga_venue_match_bindings rows where rows.id = target_id;
    insert into private.pachanga_venue_match_binding_revisions(
      binding_id, binding_revision, action, status, snapshot, operation_id, actor_id, server_sequence
    ) values (target_id, target_revision, target_action, selected_status, snapshot,
      target_operation_id, target_actor_id, target_server_sequence);
  else
    raise exception 'VENUE_REVISION_ENTITY_UNSUPPORTED' using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.pachanga_venue_append_revision_v1(
  text, uuid, bigint, text, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function public.command_pachanga_venue_reservation_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
<<venue_command>>
declare actor_id uuid := auth.uid();
declare actor_kind text := 'authenticated';
declare action_name text := lower(trim(coalesce(action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare receipt private.pachanga_venue_operation_receipts%rowtype;
declare sequence_value bigint;
declare extra_sequence bigint;
declare server_now timestamptz := clock_timestamp();
declare reason_code text;
declare aggregate_type text;
declare confirmed_revision bigint;
declare confirmed_id uuid;
declare snapshot jsonb := '{}'::jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare venue_row public.pachanga_club_venues%rowtype;
declare pitch_row public.pachanga_venue_pitches%rowtype;
declare template_row public.pachanga_venue_availability_templates%rowtype;
declare exception_row public.pachanga_venue_availability_exceptions%rowtype;
declare request_row public.pachanga_venue_reservation_requests%rowtype;
declare hold_row public.pachanga_venue_reservation_holds%rowtype;
declare claim_row public.pachanga_venue_pitch_claims%rowtype;
declare reservation_row public.pachanga_venue_reservations%rowtype;
declare previous_reservation public.pachanga_venue_reservations%rowtype;
declare binding_row public.pachanga_venue_match_bindings%rowtype;
declare previous_binding public.pachanga_venue_match_bindings%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare canonical_row public.pachanga_canonical_matches%rowtype;
declare terms_row private.pachanga_venue_reservation_terms%rowtype;
declare consent_row private.pachanga_venue_publication_consents%rowtype;
declare club_id uuid;
declare pitch_id uuid;
declare request_id uuid;
declare reservation_id uuid;
declare hold_id uuid;
declare claim_id uuid;
declare terms_id uuid;
declare binding_id uuid;
declare canonical_match_id uuid;
declare competition_id uuid;
declare local_start timestamp without time zone;
declare local_end timestamp without time zone;
declare starts_at timestamptz;
declare ends_at timestamptz;
declare timezone_name text;
declare offset_minutes integer;
declare terms jsonb;
declare terms_kind text;
declare amount_minor bigint;
declare currency_code text;
declare public_fingerprint text;
declare requested_visibility text;
declare r4d_operation_id uuid;
declare r4d_response jsonb;
declare fixture_change_id uuid;
declare fixture_change_revision_id uuid;
declare requester_is_owner boolean;
declare club_can_manage boolean;
begin
  if operation_id is null or expected_revision is null or expected_revision < 0
     or action_name = '' or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 40000 or pg_column_size(client_metadata) > 8192 then
    raise exception 'INVALID_VENUE_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  end if;
  if not private.pachanga_venue_allowed_payload_v1(action_name, payload) then
    raise exception 'VENUE_ACTION_OR_PAYLOAD_NOT_ALLOWED' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId','actor_id','acceptedBy','confirmedAt','serverSequence','server_sequence',
    'availabilityResult','conflictResult','reservationStatus','matchState',
    'clubEntitlement','rating','facets','score','standings','discipline','billing','sql'
  ] then
    raise exception 'VENUE_CLIENT_AUTHORITY_FIELD_FORBIDDEN' using errcode = '42501';
  end if;
  metadata := private.pachanga_venue_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_venue_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  select * into receipt
  from private.pachanga_venue_operation_receipts receipts
  where receipts.operation_id = command_pachanga_venue_reservation_v1.operation_id;
  if found then
    if receipt.actor_id is distinct from actor_id
       or receipt.actor_kind <> actor_kind
       or receipt.action <> action_name
       or receipt.request_hash <> request_hash then
      raise exception 'VENUE_OPERATION_ID_CONFLICT' using errcode = 'PT409';
    end if;
    return receipt.response;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'venue:' || action_name || ':' || coalesce(aggregate_id::text, operation_id::text), 0
  ));
  sequence_value := nextval('private.pachanga_venue_sequence');
  reason_code := upper(left(coalesce(nullif(trim(payload ->> 'reasonCode'), ''), 'USER_ACTION'), 120));

  if action_name = 'venue.create' then
    perform private.pachanga_venue_assert_flags_v1('management');
    if aggregate_id is not null or expected_revision <> 0 then
      raise exception 'VENUE_CREATE_REVISION_INVALID' using errcode = '22023';
    end if;
    club_id := nullif(payload ->> 'clubId', '')::uuid;
    if not private.pachanga_club_can_v1(club_id, actor_id, 'venue_manage') then
      raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    timezone_name := coalesce(nullif(payload ->> 'timezone', ''), 'Europe/Madrid');
    if not exists (select 1 from pg_catalog.pg_timezone_names zones where zones.name = timezone_name) then
      raise exception 'VENUE_TIMEZONE_INVALID' using errcode = '22023';
    end if;
    requested_visibility := upper(coalesce(nullif(payload ->> 'visibility', ''), 'PRIVATE'));
    if requested_visibility = 'PUBLIC' then
      raise exception 'VENUE_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
    end if;
    confirmed_id := gen_random_uuid();
    insert into public.pachanga_club_venues(
      id, club_id, name, slug, description, municipality, general_area, timezone,
      place_id, private_address, public_address, private_latitude, private_longitude,
      public_latitude, public_longitude, private_access_instructions,
      private_contact_name, private_contact_phone, private_contact_email,
      visibility, lifecycle, revision, server_sequence, operation_id,
      created_by, updated_by, created_at, updated_at
    ) values (
      confirmed_id, club_id, left(trim(payload ->> 'name'), 120),
      lower(left(trim(payload ->> 'slug'), 100)), left(coalesce(payload ->> 'description', ''), 3000),
      left(coalesce(payload ->> 'municipality', ''), 120),
      left(coalesce(payload ->> 'generalArea', ''), 160), timezone_name,
      nullif(left(coalesce(payload ->> 'placeId', ''), 240), ''),
      left(coalesce(payload ->> 'privateAddress', ''), 500),
      nullif(left(coalesce(payload ->> 'publicAddress', ''), 500), ''),
      nullif(payload ->> 'privateLatitude', '')::numeric,
      nullif(payload ->> 'privateLongitude', '')::numeric,
      nullif(payload ->> 'publicLatitude', '')::numeric,
      nullif(payload ->> 'publicLongitude', '')::numeric,
      left(coalesce(payload ->> 'privateAccessInstructions', ''), 3000),
      nullif(left(coalesce(payload ->> 'privateContactName', ''), 160), ''),
      nullif(left(coalesce(payload ->> 'privateContactPhone', ''), 80), ''),
      nullif(left(coalesce(payload ->> 'privateContactEmail', ''), 320), ''),
      requested_visibility, 'DRAFT', 1, sequence_value, operation_id,
      actor_id, actor_id, server_now, server_now
    ) returning * into venue_row;
    public_fingerprint := private.pachanga_venue_public_fingerprint_v1(venue_row.id);
    update public.pachanga_club_venues venues set public_content_fingerprint = public_fingerprint
    where venues.id = venue_row.id returning * into venue_row;
    perform private.pachanga_venue_append_revision_v1(
      'venue', venue_row.id, venue_row.revision, action_name,
      operation_id, actor_id, sequence_value
    );
    aggregate_type := 'venue'; confirmed_revision := venue_row.revision;
    snapshot := to_jsonb(venue_row);
    event_payload := jsonb_build_object('clubId', club_id, 'lifecycle', venue_row.lifecycle);
    invalidations := jsonb_build_array(jsonb_build_object(
      'entityType','venue','entityId',venue_row.id,'revision',venue_row.revision,
      'audienceKind','CLUB','audienceId',club_id
    ));

  elsif action_name in (
    'venue.update','venue.publication.consent','venue.submit_review',
    'venue.activate','venue.suspend','venue.archive'
  ) then
    perform private.pachanga_venue_assert_flags_v1('management');
    select * into venue_row from public.pachanga_club_venues venues
    where venues.id = aggregate_id for update;
    if not found then raise exception 'VENUE_NOT_FOUND' using errcode = 'P0002'; end if;
    if venue_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if not private.pachanga_club_can_v1(venue_row.club_id, actor_id, 'venue_manage') then
      raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    if venue_row.lifecycle = 'ARCHIVED' then
      raise exception 'VENUE_ARCHIVED_IMMUTABLE' using errcode = 'PT409';
    end if;
    if action_name = 'venue.update' then
      timezone_name := coalesce(nullif(payload ->> 'timezone', ''), venue_row.timezone);
      if not exists (select 1 from pg_catalog.pg_timezone_names zones where zones.name = timezone_name) then
        raise exception 'VENUE_TIMEZONE_INVALID' using errcode = '22023';
      end if;
      requested_visibility := upper(coalesce(nullif(payload ->> 'visibility', ''), venue_row.visibility));
      if requested_visibility = 'PUBLIC' then
        raise exception 'VENUE_PUBLICATION_CONSENT_REQUIRED' using errcode = '42501';
      end if;
      update public.pachanga_club_venues venues set
        name = coalesce(nullif(left(trim(payload ->> 'name'), 120), ''), venues.name),
        slug = coalesce(nullif(lower(left(trim(payload ->> 'slug'), 100)), ''), venues.slug),
        description = case when payload ? 'description' then left(coalesce(payload ->> 'description',''),3000) else venues.description end,
        municipality = case when payload ? 'municipality' then left(coalesce(payload ->> 'municipality',''),120) else venues.municipality end,
        general_area = case when payload ? 'generalArea' then left(coalesce(payload ->> 'generalArea',''),160) else venues.general_area end,
        timezone = timezone_name,
        place_id = case when payload ? 'placeId' then nullif(left(coalesce(payload ->> 'placeId',''),240),'') else venues.place_id end,
        private_address = case when payload ? 'privateAddress' then left(coalesce(payload ->> 'privateAddress',''),500) else venues.private_address end,
        public_address = case when payload ? 'publicAddress' then nullif(left(coalesce(payload ->> 'publicAddress',''),500),'') else venues.public_address end,
        private_latitude = case when payload ? 'privateLatitude' then nullif(payload ->> 'privateLatitude','')::numeric else venues.private_latitude end,
        private_longitude = case when payload ? 'privateLongitude' then nullif(payload ->> 'privateLongitude','')::numeric else venues.private_longitude end,
        public_latitude = case when payload ? 'publicLatitude' then nullif(payload ->> 'publicLatitude','')::numeric else venues.public_latitude end,
        public_longitude = case when payload ? 'publicLongitude' then nullif(payload ->> 'publicLongitude','')::numeric else venues.public_longitude end,
        private_access_instructions = case when payload ? 'privateAccessInstructions' then left(coalesce(payload ->> 'privateAccessInstructions',''),3000) else venues.private_access_instructions end,
        private_contact_name = case when payload ? 'privateContactName' then nullif(left(coalesce(payload ->> 'privateContactName',''),160),'') else venues.private_contact_name end,
        private_contact_phone = case when payload ? 'privateContactPhone' then nullif(left(coalesce(payload ->> 'privateContactPhone',''),80),'') else venues.private_contact_phone end,
        private_contact_email = case when payload ? 'privateContactEmail' then nullif(left(coalesce(payload ->> 'privateContactEmail',''),320),'') else venues.private_contact_email end,
        visibility = requested_visibility,
        revision = venues.revision + 1, server_sequence = sequence_value,
        operation_id = command_pachanga_venue_reservation_v1.operation_id,
        updated_by = actor_id, updated_at = server_now
      where venues.id = venue_row.id returning * into venue_row;
      public_fingerprint := private.pachanga_venue_public_fingerprint_v1(venue_row.id);
      update private.pachanga_venue_publication_consents consents set
        status = 'SUPERSEDED', superseded_at = server_now
      where consents.venue_id = venue_row.id and consents.status = 'ACTIVE'
        and consents.content_fingerprint <> public_fingerprint;
      update public.pachanga_club_venues venues set
        public_content_fingerprint = public_fingerprint,
        visibility = case when venues.visibility = 'PUBLIC' and not exists (
          select 1 from private.pachanga_venue_publication_consents consents
          where consents.venue_id = venues.id and consents.status = 'ACTIVE'
            and consents.content_fingerprint = public_fingerprint
        ) then 'UNLISTED' else venues.visibility end
      where venues.id = venue_row.id returning * into venue_row;
    elsif action_name = 'venue.publication.consent' then
      perform private.pachanga_venue_assert_flags_v1('public');
      if venue_row.lifecycle <> 'ACTIVE' then
        raise exception 'VENUE_PUBLICATION_REQUIRES_ACTIVE' using errcode = 'PT409';
      end if;
      if jsonb_typeof(coalesce(payload -> 'selectedFields','{}'::jsonb)) <> 'object' then
        raise exception 'VENUE_PUBLICATION_FIELDS_INVALID' using errcode = '22023';
      end if;
      public_fingerprint := private.pachanga_venue_public_fingerprint_v1(venue_row.id);
      update private.pachanga_venue_publication_consents consents
      set status = 'SUPERSEDED', superseded_at = server_now
      where consents.venue_id = venue_row.id and consents.status = 'ACTIVE';
      insert into private.pachanga_venue_publication_consents(
        venue_id, version, selected_fields, public_address_mode, public_rate_allowed,
        content_fingerprint, status, revision, operation_id, consented_by,
        server_sequence, consented_at
      ) values (
        venue_row.id,
        coalesce((select max(consents.version) + 1 from private.pachanga_venue_publication_consents consents where consents.venue_id = venue_row.id), 1),
        coalesce(payload -> 'selectedFields','{}'::jsonb),
        upper(coalesce(nullif(payload ->> 'addressMode',''),'AREA_ONLY')),
        coalesce((payload ->> 'publicRateAllowed')::boolean,false), public_fingerprint,
        'ACTIVE', 1, operation_id, actor_id, sequence_value, server_now
      ) returning * into consent_row;
      update public.pachanga_club_venues venues set
        visibility = 'PUBLIC', public_content_fingerprint = public_fingerprint,
        revision = venues.revision + 1, server_sequence = sequence_value,
        operation_id = command_pachanga_venue_reservation_v1.operation_id,
        updated_by = actor_id, updated_at = server_now
      where venues.id = venue_row.id returning * into venue_row;
    elsif action_name = 'venue.submit_review' then
      if venue_row.lifecycle <> 'DRAFT' then raise exception 'VENUE_TRANSITION_INVALID' using errcode = 'PT409'; end if;
      update public.pachanga_club_venues venues set lifecycle='PENDING_REVIEW', revision=venues.revision+1,
        server_sequence=sequence_value, operation_id=command_pachanga_venue_reservation_v1.operation_id,
        updated_by=actor_id, updated_at=server_now where venues.id=venue_row.id returning * into venue_row;
    elsif action_name = 'venue.activate' then
      if venue_row.lifecycle not in ('DRAFT','PENDING_REVIEW','SUSPENDED') then raise exception 'VENUE_TRANSITION_INVALID' using errcode = 'PT409'; end if;
      update public.pachanga_club_venues venues set lifecycle='ACTIVE', revision=venues.revision+1,
        server_sequence=sequence_value, operation_id=command_pachanga_venue_reservation_v1.operation_id,
        updated_by=actor_id, updated_at=server_now where venues.id=venue_row.id returning * into venue_row;
    elsif action_name = 'venue.suspend' then
      if venue_row.lifecycle <> 'ACTIVE' then raise exception 'VENUE_TRANSITION_INVALID' using errcode = 'PT409'; end if;
      update public.pachanga_club_venues venues set lifecycle='SUSPENDED', visibility=case when visibility='PUBLIC' then 'UNLISTED' else visibility end,
        revision=venues.revision+1, server_sequence=sequence_value,
        operation_id=command_pachanga_venue_reservation_v1.operation_id,
        updated_by=actor_id, updated_at=server_now where venues.id=venue_row.id returning * into venue_row;
    else
      if exists (
        select 1 from public.pachanga_venue_reservation_requests requests
        where requests.venue_id=venue_row.id and requests.starts_at > server_now
          and requests.status in ('SUBMITTED','UNDER_REVIEW','HELD','COUNTER_PROPOSED','ACCEPTED','CONFIRMED')
      ) or exists (
        select 1 from public.pachanga_venue_reservations reservations
        where reservations.venue_id=venue_row.id and reservations.ends_at > server_now
          and reservations.status in ('PENDING_CONFIRMATION','CONFIRMED')
      ) then raise exception 'VENUE_ARCHIVE_HAS_FUTURE_OPERATIONS' using errcode = 'PT409'; end if;
      update public.pachanga_club_venues venues set lifecycle='ARCHIVED', visibility='PRIVATE',
        revision=venues.revision+1, server_sequence=sequence_value,
        operation_id=command_pachanga_venue_reservation_v1.operation_id,
        updated_by=actor_id, updated_at=server_now where venues.id=venue_row.id returning * into venue_row;
    end if;
    perform private.pachanga_venue_append_revision_v1('venue',venue_row.id,venue_row.revision,action_name,operation_id,actor_id,sequence_value);
    confirmed_id:=venue_row.id; aggregate_type:='venue'; confirmed_revision:=venue_row.revision;
    club_id:=venue_row.club_id; snapshot:=to_jsonb(venue_row);
    event_payload:=jsonb_build_object('clubId',venue_row.club_id,'lifecycle',venue_row.lifecycle,'visibility',venue_row.visibility);
    invalidations:=jsonb_build_array(
      jsonb_build_object('entityType','venue','entityId',venue_row.id,'revision',venue_row.revision,'audienceKind','CLUB','audienceId',venue_row.club_id),
      jsonb_build_object('entityType','venue','entityId',venue_row.id,'revision',venue_row.revision,'audienceKind','PUBLIC')
    );

  elsif action_name like 'pitch.%' then
    perform private.pachanga_venue_assert_flags_v1('management');
    if action_name = 'pitch.create' then
      if aggregate_id is not null or expected_revision <> 0 then raise exception 'VENUE_PITCH_CREATE_REVISION_INVALID' using errcode='22023'; end if;
      club_id:=null;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=nullif(payload->>'venueId','')::uuid for update;
      if not found then raise exception 'VENUE_NOT_FOUND' using errcode='P0002'; end if;
      if venue_row.lifecycle='ARCHIVED' or not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      confirmed_id:=gen_random_uuid();
      insert into public.pachanga_venue_pitches(
        id,venue_id,parent_pitch_id,conflict_scope_id,name,slug,modalities,surface,environment,
        width_m,length_m,has_lighting,has_changing_rooms,has_showers,is_accessible,has_parking,
        spectator_capacity,public_rate_kind,public_rate_amount_minor,public_rate_currency,
        public_rate_note,status,visibility,minimum_slot_minutes,buffer_minutes,revision,
        server_sequence,operation_id,created_by,updated_by,created_at,updated_at
      ) values (
        confirmed_id,venue_row.id,nullif(payload->>'parentPitchId','')::uuid,confirmed_id,
        left(trim(payload->>'name'),120),lower(left(trim(payload->>'slug'),100)),
        array(select jsonb_array_elements_text(coalesce(payload->'modalities','[]'::jsonb))),
        upper(coalesce(nullif(payload->>'surface',''),'ARTIFICIAL_GRASS')),
        upper(coalesce(nullif(payload->>'environment',''),'OUTDOOR')),
        nullif(payload->>'widthM','')::numeric,nullif(payload->>'lengthM','')::numeric,
        coalesce((payload->>'hasLighting')::boolean,false),coalesce((payload->>'hasChangingRooms')::boolean,false),
        coalesce((payload->>'hasShowers')::boolean,false),coalesce((payload->>'isAccessible')::boolean,false),
        coalesce((payload->>'hasParking')::boolean,false),nullif(payload->>'spectatorCapacity','')::integer,
        upper(coalesce(nullif(payload->>'publicRateKind',''),'CONTACT_CLUB')),
        nullif(payload->>'publicRateAmountMinor','')::bigint,upper(nullif(payload->>'publicRateCurrency','')),
        nullif(left(coalesce(payload->>'publicRateNote',''),500),''),
        'ACTIVE',upper(coalesce(nullif(payload->>'visibility',''),'PRIVATE')),
        coalesce(nullif(payload->>'minimumSlotMinutes','')::integer,60),
        coalesce(nullif(payload->>'bufferMinutes','')::integer,0),1,sequence_value,operation_id,
        actor_id,actor_id,server_now,server_now
      ) returning * into pitch_row;
    else
      select * into pitch_row from public.pachanga_venue_pitches pitches where pitches.id=aggregate_id for update;
      if not found then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=pitch_row.venue_id;
      if pitch_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
      if not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      if pitch_row.status='ARCHIVED' then raise exception 'VENUE_PITCH_ARCHIVED_IMMUTABLE' using errcode='PT409'; end if;
      if action_name='pitch.update' then
        update public.pachanga_venue_pitches pitches set
          parent_pitch_id=case when payload?'parentPitchId' then nullif(payload->>'parentPitchId','')::uuid else pitches.parent_pitch_id end,
          name=coalesce(nullif(left(trim(payload->>'name'),120),''),pitches.name),
          slug=coalesce(nullif(lower(left(trim(payload->>'slug'),100)),''),pitches.slug),
          modalities=case when payload?'modalities' then array(select jsonb_array_elements_text(payload->'modalities')) else pitches.modalities end,
          surface=upper(coalesce(nullif(payload->>'surface',''),pitches.surface)),
          environment=upper(coalesce(nullif(payload->>'environment',''),pitches.environment)),
          width_m=case when payload?'widthM' then nullif(payload->>'widthM','')::numeric else pitches.width_m end,
          length_m=case when payload?'lengthM' then nullif(payload->>'lengthM','')::numeric else pitches.length_m end,
          has_lighting=coalesce((payload->>'hasLighting')::boolean,pitches.has_lighting),
          has_changing_rooms=coalesce((payload->>'hasChangingRooms')::boolean,pitches.has_changing_rooms),
          has_showers=coalesce((payload->>'hasShowers')::boolean,pitches.has_showers),
          is_accessible=coalesce((payload->>'isAccessible')::boolean,pitches.is_accessible),
          has_parking=coalesce((payload->>'hasParking')::boolean,pitches.has_parking),
          spectator_capacity=case when payload?'spectatorCapacity' then nullif(payload->>'spectatorCapacity','')::integer else pitches.spectator_capacity end,
          public_rate_kind=upper(coalesce(nullif(payload->>'publicRateKind',''),pitches.public_rate_kind)),
          public_rate_amount_minor=case
            when upper(coalesce(nullif(payload->>'publicRateKind',''),pitches.public_rate_kind))<>'FIXED_QUOTE' then null
            when payload?'publicRateAmountMinor' then nullif(payload->>'publicRateAmountMinor','')::bigint
            else pitches.public_rate_amount_minor end,
          public_rate_currency=case
            when upper(coalesce(nullif(payload->>'publicRateKind',''),pitches.public_rate_kind))<>'FIXED_QUOTE' then null
            when payload?'publicRateCurrency' then upper(nullif(payload->>'publicRateCurrency',''))
            else pitches.public_rate_currency end,
          public_rate_note=case when payload?'publicRateNote' then nullif(left(coalesce(payload->>'publicRateNote',''),500),'') else pitches.public_rate_note end,
          visibility=upper(coalesce(nullif(payload->>'visibility',''),pitches.visibility)),
          minimum_slot_minutes=coalesce(nullif(payload->>'minimumSlotMinutes','')::integer,pitches.minimum_slot_minutes),
          buffer_minutes=coalesce(nullif(payload->>'bufferMinutes','')::integer,pitches.buffer_minutes),
          revision=pitches.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where pitches.id=pitch_row.id returning * into pitch_row;
      elsif action_name='pitch.maintenance' then
        update public.pachanga_venue_pitches pitches set status='MAINTENANCE',revision=pitches.revision+1,server_sequence=sequence_value,
          operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now
        where pitches.id=pitch_row.id returning * into pitch_row;
      elsif action_name='pitch.restore' then
        if pitch_row.status not in ('MAINTENANCE','TEMPORARILY_CLOSED') then raise exception 'VENUE_PITCH_TRANSITION_INVALID' using errcode='PT409'; end if;
        update public.pachanga_venue_pitches pitches set status='ACTIVE',revision=pitches.revision+1,server_sequence=sequence_value,
          operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now
        where pitches.id=pitch_row.id returning * into pitch_row;
      elsif action_name='pitch.archive' then
        if exists(select 1 from public.pachanga_venue_reservations reservations where reservations.pitch_id=pitch_row.id and reservations.ends_at>server_now and reservations.status in ('PENDING_CONFIRMATION','CONFIRMED')) then raise exception 'VENUE_PITCH_ARCHIVE_HAS_FUTURE_RESERVATIONS' using errcode='PT409'; end if;
        update public.pachanga_venue_pitches pitches set status='ARCHIVED',visibility='PRIVATE',revision=pitches.revision+1,server_sequence=sequence_value,
          operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now
        where pitches.id=pitch_row.id returning * into pitch_row;
      else raise exception 'VENUE_PITCH_ACTION_NOT_SUPPORTED' using errcode='0A000';
      end if;
    end if;
    perform private.pachanga_venue_append_revision_v1('pitch',pitch_row.id,pitch_row.revision,action_name,operation_id,actor_id,sequence_value);
    confirmed_id:=pitch_row.id;aggregate_type:='pitch';confirmed_revision:=pitch_row.revision;
    club_id:=venue_row.club_id;pitch_id:=pitch_row.id;snapshot:=to_jsonb(pitch_row);
    event_payload:=jsonb_build_object('venueId',pitch_row.venue_id,'status',pitch_row.status,'modalities',pitch_row.modalities);
    invalidations:=jsonb_build_array(jsonb_build_object('entityType','pitch','entityId',pitch_row.id,'revision',pitch_row.revision,'audienceKind','CLUB','audienceId',venue_row.club_id));

  elsif action_name like 'availability.%' then
    perform private.pachanga_venue_assert_flags_v1('availability');
    if action_name='availability.template.create' then
      if aggregate_id is not null or expected_revision<>0 then raise exception 'VENUE_AVAILABILITY_CREATE_REVISION_INVALID' using errcode='22023'; end if;
      select * into pitch_row from public.pachanga_venue_pitches pitches where pitches.id=nullif(payload->>'pitchId','')::uuid;
      if not found then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=pitch_row.venue_id;
      if not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      timezone_name:=coalesce(nullif(payload->>'timezone',''),venue_row.timezone);
      if timezone_name<>venue_row.timezone then raise exception 'VENUE_AVAILABILITY_TIMEZONE_MISMATCH' using errcode='22023'; end if;
      confirmed_id:=gen_random_uuid();
      insert into public.pachanga_venue_availability_templates(
        id,venue_id,pitch_id,weekday,start_local_time,end_local_time,slot_minutes,buffer_minutes,
        valid_from,valid_until,timezone,modalities,capacity,visibility,status,revision,
        server_sequence,operation_id,created_by,updated_by,created_at,updated_at
      ) values (
        confirmed_id,venue_row.id,pitch_row.id,(payload->>'weekday')::smallint,
        (payload->>'startLocalTime')::time,(payload->>'endLocalTime')::time,
        coalesce((payload->>'slotMinutes')::integer,pitch_row.minimum_slot_minutes),
        coalesce((payload->>'bufferMinutes')::integer,pitch_row.buffer_minutes),
        (payload->>'validFrom')::date,nullif(payload->>'validUntil','')::date,timezone_name,
        array(select jsonb_array_elements_text(coalesce(payload->'modalities',to_jsonb(pitch_row.modalities)))),
        coalesce((payload->>'capacity')::integer,1),upper(coalesce(nullif(payload->>'visibility',''),'PRIVATE')),
        'ACTIVE',1,sequence_value,operation_id,actor_id,actor_id,server_now,server_now
      ) returning * into template_row;
    elsif action_name in ('availability.template.update','availability.template.disable') then
      select * into template_row from public.pachanga_venue_availability_templates templates where templates.id=aggregate_id for update;
      if not found then raise exception 'VENUE_AVAILABILITY_TEMPLATE_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=template_row.venue_id;
      if template_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
      if not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      if template_row.status='DISABLED' then raise exception 'VENUE_AVAILABILITY_TEMPLATE_DISABLED' using errcode='PT409'; end if;
      if action_name='availability.template.update' then
        timezone_name:=coalesce(nullif(payload->>'timezone',''),template_row.timezone);
        if timezone_name<>venue_row.timezone then raise exception 'VENUE_AVAILABILITY_TIMEZONE_MISMATCH' using errcode='22023'; end if;
        update public.pachanga_venue_availability_templates templates set
          weekday=coalesce((payload->>'weekday')::smallint,templates.weekday),
          start_local_time=coalesce((payload->>'startLocalTime')::time,templates.start_local_time),
          end_local_time=coalesce((payload->>'endLocalTime')::time,templates.end_local_time),
          slot_minutes=coalesce((payload->>'slotMinutes')::integer,templates.slot_minutes),
          buffer_minutes=coalesce((payload->>'bufferMinutes')::integer,templates.buffer_minutes),
          valid_from=coalesce((payload->>'validFrom')::date,templates.valid_from),
          valid_until=case when payload?'validUntil' then nullif(payload->>'validUntil','')::date else templates.valid_until end,
          timezone=timezone_name,modalities=case when payload?'modalities' then array(select jsonb_array_elements_text(payload->'modalities')) else templates.modalities end,
          capacity=coalesce((payload->>'capacity')::integer,templates.capacity),visibility=upper(coalesce(nullif(payload->>'visibility',''),templates.visibility)),
          revision=templates.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where templates.id=template_row.id returning * into template_row;
      else
        update public.pachanga_venue_availability_templates templates set status='DISABLED',revision=templates.revision+1,
          server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where templates.id=template_row.id returning * into template_row;
      end if;
    elsif action_name='availability.exception.create' then
      if aggregate_id is not null or expected_revision<>0 then raise exception 'VENUE_EXCEPTION_CREATE_REVISION_INVALID' using errcode='22023'; end if;
      select * into pitch_row from public.pachanga_venue_pitches pitches where pitches.id=nullif(payload->>'pitchId','')::uuid;
      if not found then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=pitch_row.venue_id;
      if not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      confirmed_id:=gen_random_uuid();
      insert into public.pachanga_venue_availability_exceptions(
        id,venue_id,pitch_id,exception_kind,starts_at,ends_at,public_reason,private_reason,
        visibility,priority,status,revision,server_sequence,operation_id,created_by,updated_by,created_at,updated_at
      ) values (
        confirmed_id,venue_row.id,pitch_row.id,upper(payload->>'kind'),(payload->>'startsAt')::timestamptz,(payload->>'endsAt')::timestamptz,
        nullif(left(coalesce(payload->>'publicReason',''),500),''),left(coalesce(payload->>'privateReason',''),2000),
        upper(coalesce(nullif(payload->>'visibility',''),'PRIVATE')),coalesce((payload->>'priority')::integer,100),
        'ACTIVE',1,sequence_value,operation_id,actor_id,actor_id,server_now,server_now
      ) returning * into exception_row;
    elsif action_name='availability.exception.cancel' then
      select * into exception_row from public.pachanga_venue_availability_exceptions exceptions where exceptions.id=aggregate_id for update;
      if not found then raise exception 'VENUE_AVAILABILITY_EXCEPTION_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=exception_row.venue_id;
      if exception_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
      if not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'venue_manage') then raise exception 'VENUE_CLUB_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      if exception_row.status<>'ACTIVE' then raise exception 'VENUE_EXCEPTION_NOT_ACTIVE' using errcode='PT409'; end if;
      update public.pachanga_venue_availability_exceptions exceptions set status='CANCELLED',revision=exceptions.revision+1,
        server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
        updated_by=actor_id,updated_at=server_now where exceptions.id=exception_row.id returning * into exception_row;
    else raise exception 'VENUE_AVAILABILITY_ACTION_NOT_SUPPORTED' using errcode='0A000';
    end if;
    if action_name like 'availability.template.%' then
      perform private.pachanga_venue_append_revision_v1('availability_template',template_row.id,template_row.revision,action_name,operation_id,actor_id,sequence_value);
      confirmed_id:=template_row.id;aggregate_type:='availability_template';confirmed_revision:=template_row.revision;pitch_id:=template_row.pitch_id;snapshot:=to_jsonb(template_row);
      event_payload:=jsonb_build_object('venueId',template_row.venue_id,'pitchId',template_row.pitch_id,'status',template_row.status);
    else
      perform private.pachanga_venue_append_revision_v1('availability_exception',exception_row.id,exception_row.revision,action_name,operation_id,actor_id,sequence_value);
      confirmed_id:=exception_row.id;aggregate_type:='availability_exception';confirmed_revision:=exception_row.revision;pitch_id:=exception_row.pitch_id;snapshot:=to_jsonb(exception_row)-'private_reason';
      event_payload:=jsonb_build_object('venueId',exception_row.venue_id,'pitchId',exception_row.pitch_id,'kind',exception_row.exception_kind,'status',exception_row.status);
    end if;
    club_id:=venue_row.club_id;
    invalidations:=jsonb_build_array(jsonb_build_object('entityType',case when aggregate_type='availability_template' then 'availability' else 'exception' end,'entityId',confirmed_id,'revision',confirmed_revision,'audienceKind','CLUB','audienceId',venue_row.club_id));

  elsif action_name like 'reservation.%' then
    if action_name in ('reservation.request.create','reservation.request.update','reservation.request.submit','reservation.request.withdraw','reservation.review.start','reservation.reject') then
      perform private.pachanga_venue_assert_flags_v1('request');
    elsif action_name='reservation.counter' then perform private.pachanga_venue_assert_flags_v1('counter');
    elsif action_name in ('reservation.hold','reservation.hold.expire') then perform private.pachanga_venue_assert_flags_v1('hold');
    elsif action_name in ('reservation.accept','reservation.confirm','reservation.cancel') then perform private.pachanga_venue_assert_flags_v1('reservation');
    elsif action_name in ('reservation.bind_match','reservation.unbind_match') then perform private.pachanga_venue_assert_flags_v1('binding');
    elsif action_name='reservation.replace_venue' then perform private.pachanga_venue_assert_flags_v1('r4d');
    else raise exception 'VENUE_RESERVATION_ACTION_NOT_SUPPORTED' using errcode='0A000'; end if;

    if action_name='reservation.request.create' then
      if aggregate_id is not null or expected_revision<>0 then raise exception 'VENUE_REQUEST_CREATE_REVISION_INVALID' using errcode='22023'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=nullif(payload->>'venueId','')::uuid;
      if not found or venue_row.lifecycle<>'ACTIVE' then raise exception 'VENUE_NOT_AVAILABLE' using errcode='PT409'; end if;
      if not private.pachanga_venue_requester_can_v1(
        upper(payload->>'requesterKind'),nullif(payload->>'requesterTeamId','')::uuid,
        nullif(payload->>'requesterClubId','')::uuid,nullif(payload->>'competitionId','')::uuid,actor_id
      ) then raise exception 'VENUE_REQUESTER_AUTHORITY_REQUIRED' using errcode='42501'; end if;
      timezone_name:=coalesce(nullif(payload->>'timezone',''),venue_row.timezone);
      if timezone_name<>venue_row.timezone then raise exception 'VENUE_REQUEST_TIMEZONE_MISMATCH' using errcode='22023'; end if;
      local_start:=(payload->>'localStart')::timestamp;local_end:=(payload->>'localEnd')::timestamp;
      offset_minutes:=nullif(payload->>'offsetMinutes','')::integer;
      starts_at:=private.pachanga_venue_resolve_local_v1(local_start,timezone_name,offset_minutes);
      ends_at:=private.pachanga_venue_resolve_local_v1(local_end,timezone_name,offset_minutes);
      pitch_id:=nullif(payload->>'pitchId','')::uuid;
      if pitch_id is not null then
        select * into pitch_row from public.pachanga_venue_pitches pitches where pitches.id=pitch_id and pitches.venue_id=venue_row.id;
        if not found or not (upper(payload->>'modality')=any(pitch_row.modalities)) then raise exception 'VENUE_PITCH_MODALITY_INCOMPATIBLE' using errcode='PT409'; end if;
      end if;
      confirmed_id:=gen_random_uuid();
      insert into public.pachanga_venue_reservation_requests(
        id,venue_id,pitch_id,requester_kind,requester_user_id,requester_team_id,requester_club_id,
        competition_id,canonical_match_id,rule_revision_id,purpose,modality,starts_at,ends_at,
        requested_local_start,requested_local_end,timezone,resolved_offset_minutes,criteria,
        alternatives,message,current_proposal,status,revision,server_sequence,operation_id,
        created_by,updated_by,created_at,updated_at
      ) values (
        confirmed_id,venue_row.id,pitch_id,upper(payload->>'requesterKind'),actor_id,
        nullif(payload->>'requesterTeamId','')::uuid,nullif(payload->>'requesterClubId','')::uuid,
        nullif(payload->>'competitionId','')::uuid,nullif(payload->>'canonicalMatchId','')::uuid,
        nullif(payload->>'ruleRevisionId','')::uuid,upper(payload->>'purpose'),upper(payload->>'modality'),
        starts_at,ends_at,local_start,local_end,timezone_name,
        private.pachanga_venue_offset_minutes_v1(starts_at,timezone_name),
        coalesce(payload->'criteria','{}'::jsonb),coalesce(payload->'alternatives','[]'::jsonb),
        left(coalesce(payload->>'message',''),2000),'{}'::jsonb,'DRAFT',1,sequence_value,operation_id,
        actor_id,actor_id,server_now,server_now
      ) returning * into request_row;
    else
      if action_name='reservation.hold.expire' then
        select requests.* into request_row from public.pachanga_venue_reservation_holds holds
        join public.pachanga_venue_reservation_requests requests on requests.id=holds.request_id
        where holds.id=aggregate_id for update of requests;
      elsif action_name in ('reservation.confirm','reservation.cancel','reservation.bind_match','reservation.unbind_match','reservation.replace_venue') then
        select requests.* into request_row from public.pachanga_venue_reservations reservations
        join public.pachanga_venue_reservation_requests requests on requests.id=reservations.request_id
        where reservations.id=aggregate_id for update of requests;
      else
        select * into request_row from public.pachanga_venue_reservation_requests requests where requests.id=aggregate_id for update;
      end if;
      if not found then raise exception 'VENUE_RESERVATION_AGGREGATE_NOT_FOUND' using errcode='P0002'; end if;
      select * into venue_row from public.pachanga_club_venues venues where venues.id=request_row.venue_id;
      requester_is_owner:=private.pachanga_venue_request_owned_v1(request_row.id,actor_id);
      club_can_manage:=private.pachanga_club_can_v1(venue_row.club_id,actor_id,'reservation_manage');
      if action_name='reservation.request.update' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not requester_is_owner or request_row.status<>'DRAFT' then raise exception 'VENUE_REQUEST_UPDATE_NOT_ALLOWED' using errcode='42501'; end if;
        timezone_name:=coalesce(nullif(payload->>'timezone',''),request_row.timezone);
        local_start:=coalesce(nullif(payload->>'localStart','')::timestamp,request_row.requested_local_start);
        local_end:=coalesce(nullif(payload->>'localEnd','')::timestamp,request_row.requested_local_end);
        offset_minutes:=coalesce(nullif(payload->>'offsetMinutes','')::integer,request_row.resolved_offset_minutes);
        starts_at:=private.pachanga_venue_resolve_local_v1(local_start,timezone_name,offset_minutes);
        ends_at:=private.pachanga_venue_resolve_local_v1(local_end,timezone_name,offset_minutes);
        pitch_id:=case when payload?'pitchId' then nullif(payload->>'pitchId','')::uuid else request_row.pitch_id end;
        if pitch_id is not null and not exists(select 1 from public.pachanga_venue_pitches pitches where pitches.id=pitch_id and pitches.venue_id=request_row.venue_id) then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode='P0002'; end if;
        update public.pachanga_venue_reservation_requests requests set pitch_id=venue_command.pitch_id,
          canonical_match_id=case when payload?'canonicalMatchId' then nullif(payload->>'canonicalMatchId','')::uuid else requests.canonical_match_id end,
          rule_revision_id=case when payload?'ruleRevisionId' then nullif(payload->>'ruleRevisionId','')::uuid else requests.rule_revision_id end,
          purpose=upper(coalesce(nullif(payload->>'purpose',''),requests.purpose)),modality=upper(coalesce(nullif(payload->>'modality',''),requests.modality)),
          starts_at=venue_command.starts_at,
          ends_at=venue_command.ends_at,
          requested_local_start=local_start,requested_local_end=local_end,
          timezone=timezone_name,
          resolved_offset_minutes=private.pachanga_venue_offset_minutes_v1(starts_at,timezone_name),
          criteria=coalesce(payload->'criteria',requests.criteria),alternatives=coalesce(payload->'alternatives',requests.alternatives),
          message=case when payload?'message' then left(coalesce(payload->>'message',''),2000) else requests.message end,
          revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.request.submit' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not requester_is_owner or request_row.status<>'DRAFT' then raise exception 'VENUE_REQUEST_SUBMIT_NOT_ALLOWED' using errcode='42501'; end if;
        if request_row.pitch_id is not null then perform private.pachanga_venue_assert_slot_v1(request_row.pitch_id,request_row.starts_at,request_row.ends_at,request_row.modality,null); end if;
        update public.pachanga_venue_reservation_requests requests set status='SUBMITTED',submitted_at=server_now,
          revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.request.withdraw' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not requester_is_owner or request_row.status not in ('DRAFT','SUBMITTED','COUNTER_PROPOSED') then raise exception 'VENUE_REQUEST_WITHDRAW_NOT_ALLOWED' using errcode='42501'; end if;
        update public.pachanga_venue_reservation_requests requests set status='WITHDRAWN',resolved_at=server_now,
          revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.review.start' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not club_can_manage or request_row.status<>'SUBMITTED' then raise exception 'VENUE_REVIEW_NOT_ALLOWED' using errcode='42501'; end if;
        update public.pachanga_venue_reservation_requests requests set status='UNDER_REVIEW',revision=requests.revision+1,
          server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.counter' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not club_can_manage and not requester_is_owner then raise exception 'VENUE_COUNTER_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        if request_row.status not in ('SUBMITTED','UNDER_REVIEW','COUNTER_PROPOSED') then raise exception 'VENUE_COUNTER_TRANSITION_INVALID' using errcode='PT409'; end if;
        if requester_is_owner and not club_can_manage and request_row.status<>'COUNTER_PROPOSED' then raise exception 'VENUE_REQUESTER_COUNTER_NOT_AVAILABLE' using errcode='PT409'; end if;
        timezone_name:=coalesce(nullif(payload->>'timezone',''),request_row.timezone);
        local_start:=coalesce(nullif(payload->>'localStart','')::timestamp,request_row.requested_local_start);
        local_end:=coalesce(nullif(payload->>'localEnd','')::timestamp,request_row.requested_local_end);
        offset_minutes:=coalesce(nullif(payload->>'offsetMinutes','')::integer,request_row.resolved_offset_minutes);
        starts_at:=private.pachanga_venue_resolve_local_v1(local_start,timezone_name,offset_minutes);
        ends_at:=private.pachanga_venue_resolve_local_v1(local_end,timezone_name,offset_minutes);
        pitch_id:=coalesce(nullif(payload->>'pitchId','')::uuid,request_row.pitch_id);
        perform private.pachanga_venue_assert_slot_v1(pitch_id,starts_at,ends_at,request_row.modality,null);
        terms:=coalesce(payload->'terms','{}'::jsonb);
        if jsonb_typeof(terms)<>'object' then raise exception 'VENUE_TERMS_INVALID' using errcode='22023'; end if;
        update public.pachanga_venue_reservation_requests requests set status='COUNTER_PROPOSED',
          current_proposal=jsonb_build_object(
            'pitchId',venue_command.pitch_id,
            'localStart',local_start,'localEnd',local_end,
            'timezone',timezone_name,
            'offsetMinutes',private.pachanga_venue_offset_minutes_v1(venue_command.starts_at,timezone_name),
            'startsAt',venue_command.starts_at,
            'endsAt',venue_command.ends_at,
            'terms',terms,'message',left(coalesce(payload->>'message',''),1000),
            'proposedByKind',case when club_can_manage then 'CLUB' else 'REQUESTER' end,'proposedAt',server_now),
          revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
          updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.reject' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if club_can_manage and request_row.status in ('SUBMITTED','UNDER_REVIEW','COUNTER_PROPOSED') then
          update public.pachanga_venue_reservation_requests requests set status='REJECTED',resolved_at=server_now,
            current_proposal=requests.current_proposal||jsonb_build_object('responseMessage',left(coalesce(payload->>'message',''),1000)),
            revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
            updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
        elsif requester_is_owner and request_row.status='COUNTER_PROPOSED' then
          update public.pachanga_venue_reservation_requests requests set status='WITHDRAWN',resolved_at=server_now,
            revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,
            updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
        else raise exception 'VENUE_REJECT_NOT_ALLOWED' using errcode='42501'; end if;
      elsif action_name='reservation.hold' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not club_can_manage or request_row.status not in ('SUBMITTED','UNDER_REVIEW','COUNTER_PROPOSED') then raise exception 'VENUE_HOLD_NOT_ALLOWED' using errcode='42501'; end if;
        pitch_id:=coalesce(nullif(payload->>'pitchId','')::uuid,request_row.pitch_id,(request_row.current_proposal->>'pitchId')::uuid);
        timezone_name:=coalesce(nullif(payload->>'timezone',''),request_row.current_proposal->>'timezone',request_row.timezone);
        local_start:=coalesce(nullif(payload->>'localStart','')::timestamp,(request_row.current_proposal->>'localStart')::timestamp,request_row.requested_local_start);
        local_end:=coalesce(nullif(payload->>'localEnd','')::timestamp,(request_row.current_proposal->>'localEnd')::timestamp,request_row.requested_local_end);
        offset_minutes:=coalesce(nullif(payload->>'offsetMinutes','')::integer,(request_row.current_proposal->>'offsetMinutes')::integer,request_row.resolved_offset_minutes);
        starts_at:=private.pachanga_venue_resolve_local_v1(local_start,timezone_name,offset_minutes);ends_at:=private.pachanga_venue_resolve_local_v1(local_end,timezone_name,offset_minutes);
        pitch_row:=private.pachanga_venue_assert_slot_v1(pitch_id,starts_at,ends_at,request_row.modality,null);
        hold_id:=gen_random_uuid();claim_id:=gen_random_uuid();
        insert into public.pachanga_venue_pitch_claims(id,pitch_id,conflict_scope_id,source_kind,source_id,starts_at,ends_at,status,expires_at,operation_id,server_sequence,created_at)
        values(claim_id,pitch_row.id,pitch_row.conflict_scope_id,'HOLD',hold_id,starts_at-make_interval(mins=>pitch_row.buffer_minutes),ends_at+make_interval(mins=>pitch_row.buffer_minutes),'ACTIVE',server_now+make_interval(mins=>coalesce(nullif(payload->>'expiresInMinutes','')::integer,15)),operation_id,sequence_value,server_now)
        returning * into claim_row;
        insert into public.pachanga_venue_reservation_holds(id,request_id,pitch_id,claim_id,starts_at,ends_at,expires_at,status,revision,server_sequence,operation_id,created_by,created_at)
        values(hold_id,request_row.id,pitch_row.id,claim_id,starts_at,ends_at,claim_row.expires_at,'ACTIVE',1,sequence_value,operation_id,actor_id,server_now)
        returning * into hold_row;
        update public.pachanga_venue_reservation_requests requests set
          status='HELD',pitch_id=pitch_row.id,
          starts_at=venue_command.starts_at,
          ends_at=venue_command.ends_at,
          current_hold_id=hold_row.id,revision=requests.revision+1,server_sequence=sequence_value,
          operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now
        where requests.id=request_row.id returning * into request_row;
      elsif action_name='reservation.accept' then
        if request_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if request_row.status='COUNTER_PROPOSED' and requester_is_owner and not club_can_manage then
          if request_row.current_proposal->>'proposedByKind'<>'CLUB' or payload?'terms' then raise exception 'VENUE_COUNTER_ACCEPT_PAYLOAD_FORBIDDEN' using errcode='42501'; end if;
          terms:=coalesce(request_row.current_proposal->'terms','{}'::jsonb);
        elsif club_can_manage and request_row.status in ('SUBMITTED','UNDER_REVIEW','HELD','COUNTER_PROPOSED') then
          terms:=coalesce(payload->'terms',request_row.current_proposal->'terms','{}'::jsonb);
        else raise exception 'VENUE_ACCEPT_NOT_ALLOWED' using errcode='42501'; end if;
        if jsonb_typeof(terms)<>'object' or exists(select 1 from jsonb_object_keys(terms) keys(key) where keys.key<>all(array['kind','amountMinor','currency','publicRateAllowed','taxDisplayText','privateNotes','cancellationTerms'])) then raise exception 'VENUE_TERMS_INVALID' using errcode='22023'; end if;
        pitch_id:=coalesce(nullif(payload->>'pitchId','')::uuid,(request_row.current_proposal->>'pitchId')::uuid,request_row.pitch_id);
        timezone_name:=coalesce(nullif(payload->>'timezone',''),request_row.current_proposal->>'timezone',request_row.timezone);
        local_start:=coalesce(nullif(payload->>'localStart','')::timestamp,(request_row.current_proposal->>'localStart')::timestamp,request_row.requested_local_start);
        local_end:=coalesce(nullif(payload->>'localEnd','')::timestamp,(request_row.current_proposal->>'localEnd')::timestamp,request_row.requested_local_end);
        offset_minutes:=coalesce(nullif(payload->>'offsetMinutes','')::integer,(request_row.current_proposal->>'offsetMinutes')::integer,request_row.resolved_offset_minutes);
        starts_at:=private.pachanga_venue_resolve_local_v1(local_start,timezone_name,offset_minutes);ends_at:=private.pachanga_venue_resolve_local_v1(local_end,timezone_name,offset_minutes);
        if request_row.current_hold_id is not null then
          select * into hold_row from public.pachanga_venue_reservation_holds holds where holds.id=request_row.current_hold_id for update;
          if hold_row.status<>'ACTIVE' or hold_row.expires_at<=server_now then raise exception 'VENUE_HOLD_EXPIRED' using errcode='PT409'; end if;
          claim_id:=hold_row.claim_id;
        end if;
        pitch_row:=private.pachanga_venue_assert_slot_v1(pitch_id,starts_at,ends_at,request_row.modality,claim_id);
        reservation_id:=gen_random_uuid();terms_id:=gen_random_uuid();
        terms_kind:=upper(coalesce(nullif(terms->>'kind',''),'CONTACT_CLUB'));
        amount_minor:=nullif(terms->>'amountMinor','')::bigint;currency_code:=upper(nullif(terms->>'currency',''));
        insert into private.pachanga_venue_reservation_terms(id,request_id,terms_kind,amount_minor,currency,public_rate_allowed,tax_display_text,private_notes,cancellation_terms,terms_snapshot,version,operation_id,created_by,server_sequence,created_at)
        values(terms_id,request_row.id,terms_kind,amount_minor,currency_code,coalesce((terms->>'publicRateAllowed')::boolean,false),nullif(left(coalesce(terms->>'taxDisplayText',''),500),''),left(coalesce(terms->>'privateNotes',''),2000),left(coalesce(terms->>'cancellationTerms',''),2000),terms,1,operation_id,actor_id,sequence_value,server_now)
        returning * into terms_row;
        if claim_id is null then
          claim_id:=gen_random_uuid();
          insert into public.pachanga_venue_pitch_claims(id,pitch_id,conflict_scope_id,source_kind,source_id,starts_at,ends_at,status,operation_id,server_sequence,created_at)
          values(claim_id,pitch_row.id,pitch_row.conflict_scope_id,'RESERVATION',reservation_id,starts_at-make_interval(mins=>pitch_row.buffer_minutes),ends_at+make_interval(mins=>pitch_row.buffer_minutes),'ACTIVE',operation_id,sequence_value,server_now)
          returning * into claim_row;
        else
          update public.pachanga_venue_pitch_claims claims set source_kind='RESERVATION',source_id=reservation_id,expires_at=null,operation_id=command_pachanga_venue_reservation_v1.operation_id,server_sequence=sequence_value where claims.id=claim_id returning * into claim_row;
          update public.pachanga_venue_reservation_holds holds set status='CONSUMED',revision=holds.revision+1,server_sequence=sequence_value,released_by=actor_id,released_at=server_now where holds.id=hold_row.id returning * into hold_row;
        end if;
        insert into public.pachanga_venue_reservations(id,request_id,venue_id,pitch_id,requester_user_id,requester_team_id,requester_club_id,competition_id,canonical_match_id,terms_id,claim_id,starts_at,ends_at,timezone,status,revision,server_sequence,operation_id,accepted_by,accepted_at,created_at,updated_at)
        values(reservation_id,request_row.id,request_row.venue_id,pitch_row.id,request_row.requester_user_id,request_row.requester_team_id,request_row.requester_club_id,request_row.competition_id,request_row.canonical_match_id,terms_id,claim_id,starts_at,ends_at,timezone_name,'PENDING_CONFIRMATION',1,sequence_value,operation_id,actor_id,server_now,server_now,server_now)
        returning * into reservation_row;
        update public.pachanga_venue_reservation_requests requests set
          status='ACCEPTED',pitch_id=pitch_row.id,
          starts_at=venue_command.starts_at,
          ends_at=venue_command.ends_at,
          current_reservation_id=reservation_row.id,
          revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now
        where requests.id=request_row.id returning * into request_row;
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      elsif action_name='reservation.confirm' then
        select * into reservation_row from public.pachanga_venue_reservations reservations where reservations.id=aggregate_id for update;
        if reservation_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not requester_is_owner or reservation_row.status<>'PENDING_CONFIRMATION' or request_row.status<>'ACCEPTED' then raise exception 'VENUE_CONFIRM_NOT_ALLOWED' using errcode='42501'; end if;
        update public.pachanga_venue_reservations reservations set status='CONFIRMED',confirmed_by=actor_id,confirmed_at=server_now,revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=reservation_row.id returning * into reservation_row;
        update public.pachanga_venue_reservation_requests requests set status='CONFIRMED',resolved_at=server_now,revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      elsif action_name='reservation.cancel' then
        select * into reservation_row from public.pachanga_venue_reservations reservations where reservations.id=aggregate_id for update;
        if reservation_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not requester_is_owner and not club_can_manage then raise exception 'VENUE_CANCEL_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        if reservation_row.status not in ('PENDING_CONFIRMATION','CONFIRMED') then raise exception 'VENUE_CANCEL_TRANSITION_INVALID' using errcode='PT409'; end if;
        update public.pachanga_venue_reservations reservations set status='CANCELLED',cancelled_by=actor_id,cancelled_at=server_now,cancellation_reason_code=reason_code,revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=reservation_row.id returning * into reservation_row;
        update public.pachanga_venue_pitch_claims claims set status='RELEASED',released_at=server_now,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id where claims.id=reservation_row.claim_id and claims.status='ACTIVE';
        update public.pachanga_venue_reservation_requests requests set status='CANCELLED',resolved_at=server_now,revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_by=actor_id,updated_at=server_now where requests.id=request_row.id returning * into request_row;
        select * into binding_row from public.pachanga_venue_match_bindings bindings where bindings.reservation_id=reservation_row.id and bindings.status='ACTIVE' for update;
        if found then
          update public.pachanga_venue_match_bindings bindings set status='ACTION_REQUIRED',action_required_code='VENUE_ACTION_REQUIRED',binding_revision=bindings.binding_revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where bindings.id=binding_row.id returning * into binding_row;
          perform private.pachanga_venue_append_revision_v1('venue_binding',binding_row.id,binding_row.binding_revision,action_name,operation_id,actor_id,sequence_value);
        end if;
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      elsif action_name='reservation.hold.expire' then
        if actor_kind<>'service_authority' then raise exception 'VENUE_SERVICE_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        select * into hold_row from public.pachanga_venue_reservation_holds holds where holds.id=aggregate_id for update;
        if hold_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if hold_row.status<>'ACTIVE' or hold_row.expires_at>server_now then raise exception 'VENUE_HOLD_NOT_EXPIRABLE' using errcode='PT409'; end if;
        update public.pachanga_venue_reservation_holds holds set status='EXPIRED',revision=holds.revision+1,server_sequence=sequence_value,released_at=server_now where holds.id=hold_row.id returning * into hold_row;
        update public.pachanga_venue_pitch_claims claims set status='EXPIRED',released_at=server_now,server_sequence=sequence_value where claims.id=hold_row.claim_id and claims.status='ACTIVE';
        update public.pachanga_venue_reservation_requests requests set status='EXPIRED',resolved_at=server_now,revision=requests.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where requests.id=request_row.id and requests.status='HELD' returning * into request_row;
      elsif action_name='reservation.bind_match' then
        select * into reservation_row from public.pachanga_venue_reservations reservations where reservations.id=aggregate_id for update;
        if reservation_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if reservation_row.status<>'CONFIRMED' then raise exception 'VENUE_CONFIRMED_RESERVATION_REQUIRED' using errcode='PT409'; end if;
        canonical_match_id:=nullif(payload->>'canonicalMatchId','')::uuid;
        select * into canonical_row from public.pachanga_canonical_matches matches
        where matches.id=venue_command.canonical_match_id for update;
        if not found or canonical_row.status<>'active' then raise exception 'VENUE_CANONICAL_MATCH_NOT_ACTIVE' using errcode='PT409'; end if;
        if not requester_is_owner and not (request_row.competition_id is not null and private.pachanga_competition_can_v1(request_row.competition_id,actor_id,'operations_manage')) then raise exception 'VENUE_BIND_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        if exists(select 1 from public.pachanga_venue_match_bindings bindings where bindings.canonical_match_id=venue_command.canonical_match_id and bindings.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED')) then raise exception 'VENUE_MATCH_ALREADY_BOUND' using errcode='PT409'; end if;
        if nullif(payload->>'competitionMatchContextId','') is not null then
          select * into context_row from public.pachanga_competition_match_contexts contexts where contexts.id=(payload->>'competitionMatchContextId')::uuid and contexts.canonical_match_id=venue_command.canonical_match_id for update;
          if not found or context_row.status in ('official','retired','cancelled') then raise exception 'VENUE_MATCH_CONTEXT_NOT_BINDABLE' using errcode='PT409'; end if;
          if context_row.scheduled_start is not null and (context_row.scheduled_start<>reservation_row.starts_at or context_row.scheduled_end<>reservation_row.ends_at) then raise exception 'VENUE_MATCH_SCHEDULE_MISMATCH' using errcode='PT409'; end if;
          if context_row.venue_status<>'TBD' and context_row.venue_id is distinct from reservation_row.venue_id then raise exception 'VENUE_USE_R4D_REPLACEMENT' using errcode='PT409'; end if;
          update public.pachanga_competition_match_contexts contexts set scheduled_start=coalesce(contexts.scheduled_start,reservation_row.starts_at),scheduled_end=coalesce(contexts.scheduled_end,reservation_row.ends_at),timezone=coalesce(contexts.timezone,reservation_row.timezone),venue_id=reservation_row.venue_id,venue_label=venue_row.name,venue_status='CONFIRMED',revision=contexts.revision+1,server_sequence=nextval('private.pachanga_competition_sequence'),updated_at=server_now where contexts.id=context_row.id returning * into context_row;
        end if;
        binding_id:=gen_random_uuid();
        insert into public.pachanga_venue_match_bindings(id,reservation_id,canonical_match_id,competition_match_context_id,schedule_item_id,rule_revision_id,venue_id,pitch_id,status,binding_revision,server_sequence,operation_id,bound_by,bound_at,updated_at)
        values(binding_id,reservation_row.id,venue_command.canonical_match_id,context_row.id,nullif(payload->>'scheduleItemId','')::uuid,nullif(payload->>'ruleRevisionId','')::uuid,reservation_row.venue_id,reservation_row.pitch_id,'ACTIVE',1,sequence_value,operation_id,actor_id,server_now,server_now)
        returning * into binding_row;
        update public.pachanga_venue_reservations reservations set canonical_match_id=venue_command.canonical_match_id,revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=reservation_row.id returning * into reservation_row;
        perform private.pachanga_venue_append_revision_v1('venue_binding',binding_row.id,binding_row.binding_revision,action_name,operation_id,actor_id,sequence_value);
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      elsif action_name='reservation.unbind_match' then
        select * into reservation_row from public.pachanga_venue_reservations reservations where reservations.id=aggregate_id for update;
        if reservation_row.revision<>expected_revision then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        select * into binding_row from public.pachanga_venue_match_bindings bindings where bindings.reservation_id=reservation_row.id and bindings.status in ('ACTIVE','ACTION_REQUIRED') for update;
        if not found then raise exception 'VENUE_MATCH_BINDING_NOT_FOUND' using errcode='P0002'; end if;
        if binding_row.competition_match_context_id is not null then raise exception 'VENUE_COMPETITION_UNBIND_REQUIRES_R4D' using errcode='0A000'; end if;
        if not requester_is_owner then raise exception 'VENUE_UNBIND_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        update public.pachanga_venue_match_bindings bindings set status='UNBOUND',action_required_code=null,binding_revision=bindings.binding_revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where bindings.id=binding_row.id returning * into binding_row;
        update public.pachanga_venue_reservations reservations set canonical_match_id=null,revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=reservation_row.id returning * into reservation_row;
        perform private.pachanga_venue_append_revision_v1('venue_binding',binding_row.id,binding_row.binding_revision,action_name,operation_id,actor_id,sequence_value);
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      elsif action_name='reservation.replace_venue' then
        select * into reservation_row from public.pachanga_venue_reservations reservations where reservations.id=aggregate_id for update;
        if reservation_row.revision<>expected_revision or reservation_row.status<>'CONFIRMED' then raise exception 'VENUE_REPLACEMENT_RESERVATION_INVALID' using errcode='PT409'; end if;
        select * into context_row from public.pachanga_competition_match_contexts contexts where contexts.id=nullif(payload->>'competitionMatchContextId','')::uuid for update;
        if not found or context_row.revision<>nullif(payload->>'expectedContextRevision','')::bigint then raise exception 'STALE_REVISION' using errcode='PT409'; end if;
        if not private.pachanga_competition_can_v1(context_row.competition_id,actor_id,'operations_manage') then raise exception 'VENUE_R4D_AUTHORITY_REQUIRED' using errcode='42501'; end if;
        if context_row.status in ('official','retired','cancelled') or context_row.scheduled_start<>reservation_row.starts_at or context_row.scheduled_end<>reservation_row.ends_at then raise exception 'VENUE_R4D_REPLACEMENT_INVALID' using errcode='PT409'; end if;
        select * into previous_binding from public.pachanga_venue_match_bindings bindings where bindings.canonical_match_id=context_row.canonical_match_id and bindings.status in ('ACTIVE','ACTION_REQUIRED') for update;
        if not found then raise exception 'VENUE_MATCH_BINDING_NOT_FOUND' using errcode='P0002'; end if;
        select * into previous_reservation from public.pachanga_venue_reservations reservations where reservations.id=previous_binding.reservation_id for update;
        r4d_operation_id:=private.pachanga_venue_deterministic_uuid_v1('venue-r4d:'||operation_id::text);
        r4d_response:=public.command_pachanga_league_operational_exceptions_v1(r4d_operation_id,context_row.id,context_row.revision,'fixture.change_venue',jsonb_build_object('venueId',reservation_row.venue_id,'venueLabel',venue_row.name,'venueStatus','SAVED','reasonCode',coalesce(nullif(payload->>'reasonCode',''),'PITCH_UNAVAILABLE'),'publicSummary',left(coalesce(payload->>'publicSummary','Cambio de sede confirmado por reserva.'),500)),'{}'::jsonb);
        select revisions.fixture_change_id,revisions.id into fixture_change_id,fixture_change_revision_id from public.pachanga_competition_fixture_change_revisions revisions where revisions.operation_id=r4d_operation_id order by revisions.server_sequence desc,revisions.id desc limit 1;
        update public.pachanga_venue_match_bindings bindings set status='HISTORICAL',superseded_at=server_now,binding_revision=bindings.binding_revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where bindings.id=previous_binding.id returning * into previous_binding;
        extra_sequence:=nextval('private.pachanga_venue_sequence');
        perform private.pachanga_venue_append_revision_v1('venue_binding',previous_binding.id,previous_binding.binding_revision,action_name,operation_id,actor_id,extra_sequence);
        update public.pachanga_venue_reservations reservations set status='CANCELLED',cancelled_by=actor_id,cancelled_at=server_now,cancellation_reason_code='REPLACED_VENUE',revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=previous_reservation.id returning * into previous_reservation;
        update public.pachanga_venue_pitch_claims claims set status='RELEASED',released_at=server_now,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id where claims.id=previous_reservation.claim_id and claims.status='ACTIVE';
        binding_id:=gen_random_uuid();
        insert into public.pachanga_venue_match_bindings(id,reservation_id,canonical_match_id,competition_match_context_id,schedule_item_id,rule_revision_id,venue_id,pitch_id,previous_binding_id,fixture_change_id,fixture_change_revision_id,status,binding_revision,server_sequence,operation_id,bound_by,bound_at,updated_at)
        values(binding_id,reservation_row.id,context_row.canonical_match_id,context_row.id,context_row.schedule_item_id,context_row.rule_revision_id,reservation_row.venue_id,reservation_row.pitch_id,previous_binding.id,fixture_change_id,fixture_change_revision_id,'ACTIVE',1,sequence_value,operation_id,actor_id,server_now,server_now)
        returning * into binding_row;
        update public.pachanga_venue_reservations reservations set canonical_match_id=context_row.canonical_match_id,revision=reservations.revision+1,server_sequence=sequence_value,operation_id=command_pachanga_venue_reservation_v1.operation_id,updated_at=server_now where reservations.id=reservation_row.id returning * into reservation_row;
        perform private.pachanga_venue_append_revision_v1('venue_binding',binding_row.id,binding_row.binding_revision,action_name,operation_id,actor_id,sequence_value);
        perform private.pachanga_venue_append_revision_v1('reservation',reservation_row.id,reservation_row.revision,action_name,operation_id,actor_id,sequence_value);
      end if;
    end if;
    if action_name in ('reservation.request.create','reservation.request.update','reservation.request.submit','reservation.request.withdraw','reservation.review.start','reservation.counter','reservation.reject','reservation.hold','reservation.accept','reservation.hold.expire') then
      perform private.pachanga_venue_append_revision_v1('reservation_request',request_row.id,request_row.revision,action_name,operation_id,actor_id,sequence_value);
    end if;
    request_id:=request_row.id;club_id:=venue_row.club_id;
    if reservation_row.id is not null then
      confirmed_id:=reservation_row.id;aggregate_type:='reservation';confirmed_revision:=reservation_row.revision;reservation_id:=reservation_row.id;pitch_id:=reservation_row.pitch_id;canonical_match_id:=reservation_row.canonical_match_id;
      snapshot:=jsonb_build_object('request',to_jsonb(request_row)-'message'-'current_proposal','reservation',to_jsonb(reservation_row),'binding',case when binding_row.id is null then null else to_jsonb(binding_row) end);
    elsif hold_row.id is not null then
      confirmed_id:=hold_row.id;aggregate_type:='hold';confirmed_revision:=hold_row.revision;pitch_id:=hold_row.pitch_id;snapshot:=jsonb_build_object('request',to_jsonb(request_row)-'message'-'current_proposal','hold',to_jsonb(hold_row));
    else
      confirmed_id:=request_row.id;aggregate_type:='reservation_request';confirmed_revision:=request_row.revision;pitch_id:=request_row.pitch_id;snapshot:=to_jsonb(request_row)-'message';
    end if;
    event_payload:=jsonb_strip_nulls(jsonb_build_object('venueId',request_row.venue_id,'pitchId',pitch_id,'requestId',request_row.id,'reservationId',reservation_id,'canonicalMatchId',canonical_match_id,'requestStatus',request_row.status,'reservationStatus',reservation_row.status,'bindingStatus',binding_row.status));
    invalidations:=jsonb_build_array(
      jsonb_build_object('entityType','reservation_request','entityId',request_row.id,'revision',request_row.revision,'audienceKind','CLUB','audienceId',venue_row.club_id),
      jsonb_build_object('entityType','reservation_request','entityId',request_row.id,'revision',request_row.revision,'audienceKind','USER','audienceId',request_row.requester_user_id)
    );
    if reservation_id is not null then invalidations:=invalidations||jsonb_build_array(jsonb_build_object('entityType','reservation','entityId',reservation_id,'revision',reservation_row.revision,'audienceKind','USER','audienceId',request_row.requester_user_id)); end if;
    if canonical_match_id is not null then invalidations:=invalidations||jsonb_build_array(jsonb_build_object('entityType','canonical_match','entityId',canonical_match_id,'revision',coalesce(context_row.revision,1),'audienceKind','AUTHENTICATED')); end if;
  else
    raise exception 'VENUE_ACTION_NOT_SUPPORTED' using errcode='0A000';
  end if;

  return private.pachanga_venue_store_command_v1(
    operation_id,actor_id,actor_kind,action_name,aggregate_type,confirmed_id::text,
    confirmed_revision,sequence_value,request_hash,metadata,reason_code,event_payload,snapshot,
    coalesce(venue_row.id,request_row.venue_id),pitch_id,request_id,reservation_id,
    canonical_match_id,invalidations
  );
exception
  when exclusion_violation then
    raise exception 'VENUE_SLOT_CONFLICT' using errcode='PT409';
  when unique_violation then
    raise exception 'VENUE_CONFLICT' using errcode='PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode='PT409';
end;
$$;

revoke all on function public.command_pachanga_venue_reservation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_venue_reservation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

reset statement_timeout;
reset lock_timeout;
