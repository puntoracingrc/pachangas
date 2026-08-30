-- Pachangas IQ Wave 9A: privacy-aware read models, directory and Control Center.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_venue_publicly_visible_v1(
  target_venue_id uuid,
  allow_unlisted boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce((
    select settings.venue_foundation_enabled
      and settings.venue_public_profiles_enabled
      and venues.lifecycle = 'ACTIVE'
      and (venues.visibility = 'PUBLIC' or (allow_unlisted and venues.visibility = 'UNLISTED'))
      and exists (
        select 1 from private.pachanga_venue_publication_consents consents
        where consents.venue_id = venues.id and consents.status = 'ACTIVE'
          and consents.content_fingerprint = venues.public_content_fingerprint
      )
    from public.pachanga_club_venues venues
    cross join private.pachanga_venue_settings_v1 settings
    where venues.id = target_venue_id and settings.singleton
  ), false);
$$;

revoke all on function private.pachanga_venue_publicly_visible_v1(uuid, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_private_location_can_v1(
  target_venue_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare target_club_id uuid;
begin
  if target_actor_id is null then return false; end if;
  select venues.club_id into target_club_id
  from public.pachanga_club_venues venues where venues.id = target_venue_id;
  if private.pachanga_club_can_v1(target_club_id, target_actor_id, 'venue_read') then
    return true;
  end if;
  return exists (
    select 1
    from public.pachanga_venue_reservations reservations
    left join public.pachanga_group_members members
      on members.group_id = reservations.requester_team_id
      and members.user_id = target_actor_id
    where reservations.venue_id = target_venue_id
      and reservations.status in ('CONFIRMED', 'CONSUMED')
      and (
        reservations.requester_user_id = target_actor_id
        or members.user_id is not null
        or (reservations.competition_id is not null and private.pachanga_competition_can_v1(
          reservations.competition_id, target_actor_id, 'operations_read'
        ))
        or exists (
          select 1
          from public.pachanga_venue_match_bindings bindings
          join public.pachanga_match_participants participants
            on participants.canonical_match_id = bindings.canonical_match_id
          join public.pachanga_player_profiles profiles
            on profiles.id = participants.player_profile_id
          where bindings.reservation_id = reservations.id
            and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
            and profiles.user_id = target_actor_id
        )
        or exists (
          select 1
          from public.pachanga_venue_match_bindings bindings
          join public.pachanga_referee_assignments assignments
            on assignments.canonical_match_id = bindings.canonical_match_id
          join public.pachanga_referee_profiles profiles
            on profiles.id = assignments.referee_profile_id
          where bindings.reservation_id = reservations.id
            and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
            and assignments.status in ('confirmed', 'completed')
            and profiles.user_id = target_actor_id
        )
      )
  );
end;
$$;

revoke all on function private.pachanga_venue_private_location_can_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_public_projection_v1(target_venue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare venue public.pachanga_club_venues%rowtype;
declare consent private.pachanga_venue_publication_consents%rowtype;
declare club public.pachanga_clubs%rowtype;
declare fields jsonb;
declare pitches jsonb;
declare address_value text;
declare coordinates jsonb;
begin
  select * into venue from public.pachanga_club_venues rows where rows.id = target_venue_id;
  if not found then return null; end if;
  select * into consent from private.pachanga_venue_publication_consents rows
  where rows.venue_id = venue.id and rows.status = 'ACTIVE'
    and rows.content_fingerprint = venue.public_content_fingerprint;
  if not found then return null; end if;
  select * into club from public.pachanga_clubs rows where rows.id = venue.club_id;
  fields := consent.selected_fields;
  address_value := case
    when consent.public_address_mode in ('PUBLIC_ADDRESS','EXACT_COORDINATES')
      and coalesce((fields ->> 'address')::boolean, false) then venue.public_address
    else null end;
  coordinates := case
    when consent.public_address_mode = 'EXACT_COORDINATES'
      and coalesce((fields ->> 'coordinates')::boolean, false)
      then jsonb_build_object('latitude',venue.public_latitude,'longitude',venue.public_longitude,'precision','EXACT')
    when consent.public_address_mode = 'APPROXIMATE_COORDINATES'
      and coalesce((fields ->> 'coordinates')::boolean, false)
      then jsonb_build_object('latitude',round(venue.public_latitude,3),'longitude',round(venue.public_longitude,3),'precision','APPROXIMATE')
    else null end;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'pitchId', pitch.id,
    'name', pitch.name,
    'modalities', pitch.modalities,
    'surface', pitch.surface,
    'environment', pitch.environment,
    'hasLighting', pitch.has_lighting,
    'hasChangingRooms', pitch.has_changing_rooms,
    'hasShowers', pitch.has_showers,
    'isAccessible', pitch.is_accessible,
    'hasParking', pitch.has_parking,
    'spectatorCapacity', pitch.spectator_capacity,
    'status', pitch.status,
    'publicRate', case when consent.public_rate_allowed then jsonb_strip_nulls(jsonb_build_object(
      'kind', pitch.public_rate_kind,
      'amountMinor', pitch.public_rate_amount_minor,
      'currency', pitch.public_rate_currency,
      'note', pitch.public_rate_note,
      'paymentNotice', 'Pago fuera de Pachangas IQ.'
    )) else null end
  )) order by pitch.server_sequence, pitch.id), '[]'::jsonb) into pitches
  from public.pachanga_venue_pitches pitch
  where pitch.venue_id = venue.id and pitch.visibility = 'PUBLIC'
    and pitch.status <> 'ARCHIVED';
  return jsonb_strip_nulls(jsonb_build_object(
    'venueId',venue.id,'slug',venue.slug,'name',venue.name,
    'description',case when coalesce((fields->>'description')::boolean,false) then venue.description else null end,
    'club',jsonb_build_object('clubId',club.id,'slug',club.slug,'name',club.name,'logoAsset',club.logo_asset),
    'municipality',venue.municipality,'generalArea',venue.general_area,
    'address',address_value,'coordinates',coordinates,'visibility',venue.visibility,
    'revision',venue.revision,'serverSequence',venue.server_sequence,
    'updatedAt',venue.updated_at,'pitches',pitches,'paymentNotice','Pago fuera de Pachangas IQ.'
  ));
end;
$$;

revoke all on function private.pachanga_venue_public_projection_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_slot_is_available_v1(
  target_pitch_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_modality text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with selected as (
    select pitches.*, venues.timezone, venues.lifecycle
    from public.pachanga_venue_pitches pitches
    join public.pachanga_club_venues venues on venues.id = pitches.venue_id
    where pitches.id = target_pitch_id
  ), local_values as (
    select selected.*,
      target_starts_at at time zone selected.timezone as local_start,
      target_ends_at at time zone selected.timezone as local_end
    from selected
  )
  select coalesce((
    select selected.lifecycle = 'ACTIVE' and selected.status = 'ACTIVE'
      and upper(target_modality) = any(selected.modalities)
      and target_ends_at > target_starts_at
      and (
        exists (
          select 1 from public.pachanga_venue_availability_templates templates
          where templates.pitch_id = selected.id and templates.status = 'ACTIVE'
            and templates.weekday = extract(isodow from selected.local_start)::smallint
            and selected.local_start::date >= templates.valid_from
            and (templates.valid_until is null or selected.local_start::date <= templates.valid_until)
            and selected.local_start::time >= templates.start_local_time
            and selected.local_end::time <= templates.end_local_time
            and upper(target_modality) = any(templates.modalities)
        ) or exists (
          select 1 from public.pachanga_venue_availability_exceptions exceptions
          where exceptions.pitch_id = selected.id and exceptions.status = 'ACTIVE'
            and exceptions.exception_kind = 'SPECIAL_OPENING'
            and exceptions.time_range @> tstzrange(target_starts_at,target_ends_at,'[)')
        )
      )
      and not exists (
        select 1 from public.pachanga_venue_availability_exceptions exceptions
        where exceptions.pitch_id = selected.id and exceptions.status = 'ACTIVE'
          and exceptions.exception_kind <> 'SPECIAL_OPENING'
          and exceptions.time_range && tstzrange(target_starts_at,target_ends_at,'[)')
      )
      and not exists (
        select 1 from public.pachanga_venue_pitch_claims claims
        where claims.conflict_scope_id = selected.conflict_scope_id and claims.status = 'ACTIVE'
          and claims.occupied_range && tstzrange(
            target_starts_at - make_interval(mins=>selected.buffer_minutes),
            target_ends_at + make_interval(mins=>selected.buffer_minutes),'[)'
          )
      )
    from local_values selected
  ), false);
$$;

revoke all on function private.pachanga_venue_slot_is_available_v1(
  uuid, timestamptz, timestamptz, text
) from public, anon, authenticated;

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
    'venuePaymentsEnabled',settings.venue_payments_enabled,
    'venueRecurringBookingsEnabled',settings.venue_recurring_bookings_enabled,
    'venueBulkCompetitionAllocationEnabled',settings.venue_bulk_competition_allocation_enabled,
    'venueExternalIntegrationsEnabled',settings.venue_external_integrations_enabled,
    'revision',settings.revision,'serverSequence',settings.server_sequence,'updatedAt',settings.updated_at
  ) from private.pachanga_venue_settings_v1 settings where settings.singleton;
$$;

revoke all on function public.get_pachanga_venue_flags_v1() from public;
grant execute on function public.get_pachanga_venue_flags_v1() to anon, authenticated, service_role;

create or replace function public.get_pachanga_public_venues_v1(
  filters jsonb default '{}'::jsonb,
  page_number integer default 1,
  page_size integer default 24
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized jsonb := coalesce(filters,'{}'::jsonb);
declare starts_at timestamptz := nullif(normalized->>'startsAt','')::timestamptz;
declare ends_at timestamptz := nullif(normalized->>'endsAt','')::timestamptz;
declare modality text := upper(nullif(normalized->>'modality',''));
declare response jsonb;
begin
  if jsonb_typeof(normalized)<>'object' or page_number<1 or page_size not between 1 and 60
     or (starts_at is null) <> (ends_at is null) then
    raise exception 'VENUE_DIRECTORY_FILTERS_INVALID' using errcode='22023';
  end if;
  if not (select settings.venue_public_directory_enabled from private.pachanga_venue_settings_v1 settings where settings.singleton) then
    return jsonb_build_object('items','[]'::jsonb,'total',0,'page',page_number,'pageSize',page_size);
  end if;
  with matching as (
    select venues.id, venues.server_sequence
    from public.pachanga_club_venues venues
    where private.pachanga_venue_publicly_visible_v1(venues.id,false)
      and (nullif(normalized->>'municipality','') is null or lower(venues.municipality)=lower(normalized->>'municipality'))
      and (nullif(normalized->>'clubId','') is null or venues.club_id=(normalized->>'clubId')::uuid)
      and exists (
        select 1 from public.pachanga_venue_pitches pitches
        where pitches.venue_id=venues.id and pitches.visibility='PUBLIC' and pitches.status='ACTIVE'
          and (modality is null or modality=any(pitches.modalities))
          and (nullif(normalized->>'environment','') is null or pitches.environment=upper(normalized->>'environment'))
          and (nullif(normalized->>'surface','') is null or pitches.surface=upper(normalized->>'surface'))
          and (not coalesce((normalized->>'lighting')::boolean,false) or pitches.has_lighting)
          and (not coalesce((normalized->>'changingRooms')::boolean,false) or pitches.has_changing_rooms)
          and (not coalesce((normalized->>'accessible')::boolean,false) or pitches.is_accessible)
          and (starts_at is null or private.pachanga_venue_slot_is_available_v1(pitches.id,starts_at,ends_at,modality))
      )
  ), total as (select count(*)::integer value from matching), paged as (
    select * from matching order by server_sequence desc,id
    limit page_size offset (page_number-1)*page_size
  )
  select jsonb_build_object(
    'items',coalesce(jsonb_agg(private.pachanga_venue_public_projection_v1(paged.id) order by paged.server_sequence desc,paged.id),'[]'::jsonb),
    'total',(select value from total),'page',page_number,'pageSize',page_size,
    'serverSequence',coalesce(max(paged.server_sequence),0)
  ) into response from paged;
  return response;
end;
$$;

revoke all on function public.get_pachanga_public_venues_v1(jsonb,integer,integer) from public;
grant execute on function public.get_pachanga_public_venues_v1(jsonb,integer,integer) to anon,authenticated,service_role;

create or replace function public.get_pachanga_public_venue_v1(target_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare venue_id uuid;
begin
  select venues.id into venue_id from public.pachanga_club_venues venues
  where venues.slug=target_slug and private.pachanga_venue_publicly_visible_v1(venues.id,true);
  if venue_id is null then raise exception 'VENUE_PUBLIC_PROFILE_NOT_FOUND' using errcode='P0002'; end if;
  return private.pachanga_venue_public_projection_v1(venue_id);
end;
$$;

revoke all on function public.get_pachanga_public_venue_v1(text) from public;
grant execute on function public.get_pachanga_public_venue_v1(text) to anon,authenticated,service_role;

create or replace function public.get_pachanga_venue_availability_v1(
  target_pitch_id uuid,
  range_start timestamptz,
  range_end timestamptz,
  target_modality text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare pitch public.pachanga_venue_pitches%rowtype;
declare venue public.pachanga_club_venues%rowtype;
declare can_read boolean;
declare items jsonb;
begin
  if range_start is null or range_end<=range_start or range_end>range_start+interval '62 days'
     or upper(target_modality) not in ('F5','F7','F11','FUTSAL') then
    raise exception 'VENUE_AVAILABILITY_RANGE_INVALID' using errcode='22023';
  end if;
  select * into pitch from public.pachanga_venue_pitches rows where rows.id=target_pitch_id;
  if not found then raise exception 'VENUE_PITCH_NOT_FOUND' using errcode='P0002'; end if;
  select * into venue from public.pachanga_club_venues rows where rows.id=pitch.venue_id;
  can_read:=private.pachanga_venue_publicly_visible_v1(venue.id,true)
    and pitch.visibility in ('PUBLIC','UNLISTED');
  if not can_read and not private.pachanga_club_can_v1(venue.club_id,auth.uid(),'venue_read') then
    raise exception 'VENUE_AVAILABILITY_NOT_VISIBLE' using errcode='42501';
  end if;
  with days as (
    select day::date local_date from generate_series(
      (range_start at time zone venue.timezone)::date,
      (range_end at time zone venue.timezone)::date,interval '1 day'
    ) day
  ), local_slots as (
    select templates.id template_id,templates.revision source_revision,
      slot_time as local_start,
      slot_time + make_interval(mins=>templates.slot_minutes) as local_end
    from days
    join public.pachanga_venue_availability_templates templates
      on templates.pitch_id=pitch.id and templates.status='ACTIVE'
      and templates.weekday=extract(isodow from days.local_date)::smallint
      and days.local_date>=templates.valid_from
      and (templates.valid_until is null or days.local_date<=templates.valid_until)
      and upper(target_modality)=any(templates.modalities)
    cross join lateral generate_series(
      days.local_date + templates.start_local_time,
      days.local_date + templates.end_local_time-make_interval(mins=>templates.slot_minutes),
      make_interval(mins=>templates.slot_minutes+templates.buffer_minutes)
    ) slot_time
  ), candidates as (
    select local_slots.*,(local_slots.local_start at time zone venue.timezone)+delta.value as starts_at,
      (local_slots.local_end at time zone venue.timezone)+delta.value as ends_at
    from local_slots cross join lateral (values(interval '-1 hour'),(interval '0'),(interval '1 hour')) delta(value)
  ), valid as (
    select distinct template_id,source_revision,local_start,local_end,starts_at,ends_at
    from candidates where starts_at at time zone venue.timezone=local_start
      and ends_at at time zone venue.timezone=local_end
      and starts_at>=range_start and ends_at<=range_end
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'templateId',valid.template_id,'sourceRevision',valid.source_revision,
    'startsAt',valid.starts_at,'endsAt',valid.ends_at,
    'localStart',valid.local_start,'localEnd',valid.local_end,
    'timezone',venue.timezone,
    'offsetMinutes',private.pachanga_venue_offset_minutes_v1(valid.starts_at,venue.timezone),
    'status',case
      when exists(select 1 from public.pachanga_venue_availability_exceptions exceptions where exceptions.pitch_id=pitch.id and exceptions.status='ACTIVE' and exceptions.exception_kind<>'SPECIAL_OPENING' and exceptions.time_range&&tstzrange(valid.starts_at,valid.ends_at,'[)')) then 'BLOCKED'
      when exists(select 1 from public.pachanga_venue_pitch_claims claims where claims.conflict_scope_id=pitch.conflict_scope_id and claims.status='ACTIVE' and claims.occupied_range&&tstzrange(valid.starts_at,valid.ends_at,'[)')) then 'OCCUPIED'
      else 'AVAILABLE' end
  ) order by valid.starts_at,valid.template_id),'[]'::jsonb) into items from valid;
  return jsonb_build_object('pitchId',pitch.id,'venueId',venue.id,'timezone',venue.timezone,
    'rangeStart',range_start,'rangeEnd',range_end,'items',items,
    'revision',greatest(pitch.revision,venue.revision),'serverSequence',greatest(pitch.server_sequence,venue.server_sequence));
end;
$$;

revoke all on function public.get_pachanga_venue_availability_v1(uuid,timestamptz,timestamptz,text) from public;
grant execute on function public.get_pachanga_venue_availability_v1(uuid,timestamptz,timestamptz,text) to anon,authenticated,service_role;

create or replace function public.get_pachanga_club_venue_desk_v1(target_club_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare response jsonb;
begin
  if actor_id is null or not private.pachanga_club_can_v1(target_club_id,actor_id,'reservation_read') then
    raise exception 'VENUE_CLUB_DESK_AUTHORITY_REQUIRED' using errcode='42501';
  end if;
  select jsonb_build_object(
    'clubId',target_club_id,
    'canManageVenues',private.pachanga_club_can_v1(target_club_id,actor_id,'venue_manage'),
    'canManageReservations',private.pachanga_club_can_v1(target_club_id,actor_id,'reservation_manage'),
    'venues',coalesce((select jsonb_agg(to_jsonb(venues) order by venues.server_sequence desc,venues.id) from public.pachanga_club_venues venues where venues.club_id=target_club_id),'[]'::jsonb),
    'pitches',coalesce((select jsonb_agg(to_jsonb(pitches) order by pitches.server_sequence desc,pitches.id) from public.pachanga_venue_pitches pitches join public.pachanga_club_venues venues on venues.id=pitches.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'availabilityTemplates',coalesce((select jsonb_agg(to_jsonb(templates) order by templates.server_sequence desc,templates.id) from public.pachanga_venue_availability_templates templates join public.pachanga_venue_pitches pitches on pitches.id=templates.pitch_id join public.pachanga_club_venues venues on venues.id=pitches.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'availabilityExceptions',coalesce((select jsonb_agg(to_jsonb(exceptions) order by exceptions.server_sequence desc,exceptions.id) from public.pachanga_venue_availability_exceptions exceptions join public.pachanga_venue_pitches pitches on pitches.id=exceptions.pitch_id join public.pachanga_club_venues venues on venues.id=pitches.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(requests) order by requests.server_sequence desc,requests.id) from public.pachanga_venue_reservation_requests requests join public.pachanga_club_venues venues on venues.id=requests.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'holds',coalesce((select jsonb_agg(to_jsonb(holds) order by holds.server_sequence desc,holds.id) from public.pachanga_venue_reservation_holds holds join public.pachanga_venue_reservation_requests requests on requests.id=holds.request_id join public.pachanga_club_venues venues on venues.id=requests.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'reservations',coalesce((select jsonb_agg(to_jsonb(reservations) order by reservations.server_sequence desc,reservations.id) from public.pachanga_venue_reservations reservations join public.pachanga_club_venues venues on venues.id=reservations.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'matchBindings',coalesce((select jsonb_agg(to_jsonb(bindings) order by bindings.server_sequence desc,bindings.id) from public.pachanga_venue_match_bindings bindings join public.pachanga_club_venues venues on venues.id=bindings.venue_id where venues.club_id=target_club_id),'[]'::jsonb),
    'conflicts',coalesce((select jsonb_agg(jsonb_build_object(
      'exceptionId',exceptions.id,'reservationId',reservations.id,'pitchId',reservations.pitch_id,
      'startsAt',greatest(lower(exceptions.time_range),reservations.starts_at),
      'endsAt',least(upper(exceptions.time_range),reservations.ends_at),
      'exceptionKind',exceptions.exception_kind,'reservationStatus',reservations.status
    ) order by reservations.server_sequence desc,reservations.id,exceptions.id)
    from public.pachanga_venue_availability_exceptions exceptions
    join public.pachanga_venue_pitches pitches on pitches.id=exceptions.pitch_id
    join public.pachanga_club_venues venues on venues.id=pitches.venue_id
    join public.pachanga_venue_reservations reservations on reservations.pitch_id=pitches.id
      and reservations.status in ('PENDING_CONFIRMATION','CONFIRMED')
      and exceptions.time_range&&tstzrange(reservations.starts_at,reservations.ends_at,'[)')
    where venues.club_id=target_club_id and exceptions.status='ACTIVE'
      and exceptions.exception_kind in ('MAINTENANCE','CLOSED','BLOCKED')),'[]'::jsonb),
    'serverSequence',coalesce((select max(venues.server_sequence) from public.pachanga_club_venues venues where venues.club_id=target_club_id),0)
  ) into response;
  return response;
end;
$$;

revoke all on function public.get_pachanga_club_venue_desk_v1(uuid) from public,anon;
grant execute on function public.get_pachanga_club_venue_desk_v1(uuid) to authenticated,service_role;

create or replace function public.get_pachanga_my_venue_reservations_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode='42501'; end if;
  return jsonb_build_object('items',coalesce((
    select jsonb_agg(jsonb_build_object(
      'request',(to_jsonb(requests)-'message'-'current_proposal') || jsonb_build_object(
        'currentProposal',case when requests.current_proposal='{}'::jsonb then null
          else requests.current_proposal #- '{terms,privateNotes}' end
      ),
      'hold',case when holds.id is null then null else jsonb_build_object(
        'id',holds.id,'requestId',holds.request_id,'pitchId',holds.pitch_id,
        'startsAt',holds.starts_at,'endsAt',holds.ends_at,'expiresAt',holds.expires_at,
        'status',holds.status,'revision',holds.revision,'serverSequence',holds.server_sequence
      ) end,
      'reservation',case when reservations.id is null then null else to_jsonb(reservations) end,
      'venue',private.pachanga_venue_public_projection_v1(requests.venue_id),
      'operationalLocation',case when private.pachanga_venue_private_location_can_v1(requests.venue_id,actor_id)
        then jsonb_build_object('address',venues.private_address,'latitude',venues.private_latitude,'longitude',venues.private_longitude,'accessInstructions',venues.private_access_instructions)
        else null end
    ) order by requests.server_sequence desc,requests.id)
    from public.pachanga_venue_reservation_requests requests
    join public.pachanga_club_venues venues on venues.id=requests.venue_id
    left join public.pachanga_venue_reservations reservations on reservations.id=requests.current_reservation_id
    left join lateral (
      select candidate.*
      from public.pachanga_venue_reservation_holds candidate
      where candidate.request_id=requests.id
      order by candidate.server_sequence desc,candidate.id desc limit 1
    ) holds on true
    where requests.requester_user_id=actor_id
      or (requests.requester_team_id is not null and public.is_pachanga_group_admin(requests.requester_team_id))
      or (requests.competition_id is not null and private.pachanga_competition_can_v1(requests.competition_id,actor_id,'operations_read'))
  ),'[]'::jsonb),'serverSequence',coalesce((select max(requests.server_sequence) from public.pachanga_venue_reservation_requests requests where requests.requester_user_id=actor_id),0));
end;
$$;

revoke all on function public.get_pachanga_my_venue_reservations_v1() from public,anon;
grant execute on function public.get_pachanga_my_venue_reservations_v1() to authenticated,service_role;

create or replace function public.get_pachanga_venue_reservation_v1(target_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare reservation public.pachanga_venue_reservations%rowtype;
declare request public.pachanga_venue_reservation_requests%rowtype;
declare venue public.pachanga_club_venues%rowtype;
declare terms private.pachanga_venue_reservation_terms%rowtype;
declare binding public.pachanga_venue_match_bindings%rowtype;
declare allowed boolean;
begin
  if actor_id is null then raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode='42501'; end if;
  select * into reservation from public.pachanga_venue_reservations rows where rows.id=target_reservation_id;
  if not found then raise exception 'VENUE_RESERVATION_NOT_FOUND' using errcode='P0002'; end if;
  select * into request from public.pachanga_venue_reservation_requests rows where rows.id=reservation.request_id;
  select * into venue from public.pachanga_club_venues rows where rows.id=reservation.venue_id;
  allowed:=private.pachanga_venue_request_owned_v1(request.id,actor_id)
    or private.pachanga_club_can_v1(venue.club_id,actor_id,'reservation_read')
    or (reservation.competition_id is not null and private.pachanga_competition_can_v1(reservation.competition_id,actor_id,'operations_read'));
  if not allowed then raise exception 'VENUE_RESERVATION_READ_FORBIDDEN' using errcode='42501'; end if;
  select * into terms from private.pachanga_venue_reservation_terms rows where rows.id=reservation.terms_id;
  select * into binding from public.pachanga_venue_match_bindings rows where rows.reservation_id=reservation.id and rows.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED');
  return jsonb_build_object(
    'request',(to_jsonb(request)-'current_proposal') || jsonb_build_object(
      'current_proposal', request.current_proposal #- '{terms,privateNotes}'
    ),
    'reservation',to_jsonb(reservation),
    'terms',jsonb_strip_nulls(jsonb_build_object(
      'id',terms.id,
      'kind',terms.terms_kind,
      'amountMinor',terms.amount_minor,
      'currency',terms.currency,
      'publicRateAllowed',terms.public_rate_allowed,
      'taxDisplayText',terms.tax_display_text,
      'cancellationTerms',terms.cancellation_terms,
      'version',terms.version,
      'createdAt',terms.created_at
    )),
    'binding',case when binding.id is null then null else to_jsonb(binding) end,
    'venue',private.pachanga_venue_public_projection_v1(venue.id),
    'operationalLocation',case when private.pachanga_venue_private_location_can_v1(venue.id,actor_id)
      then jsonb_build_object('address',venue.private_address,'latitude',venue.private_latitude,'longitude',venue.private_longitude,'accessInstructions',venue.private_access_instructions,'contactName',venue.private_contact_name,'contactPhone',venue.private_contact_phone,'contactEmail',venue.private_contact_email)
      else null end,
    'paymentNotice','Pachangas IQ no procesa el pago de esta reserva. El pago, si existe, se gestiona directamente con el Club.'
  );
end;
$$;

revoke all on function public.get_pachanga_venue_reservation_v1(uuid) from public,anon;
grant execute on function public.get_pachanga_venue_reservation_v1(uuid) to authenticated,service_role;

create or replace function public.get_pachanga_match_venue_v1(target_canonical_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare binding public.pachanga_venue_match_bindings%rowtype;
declare reservation public.pachanga_venue_reservations%rowtype;
declare venue public.pachanga_club_venues%rowtype;
declare pitch public.pachanga_venue_pitches%rowtype;
declare referee_state text;
begin
  if actor_id is null then raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode='42501'; end if;
  select * into binding from public.pachanga_venue_match_bindings rows
  where rows.canonical_match_id=target_canonical_match_id and rows.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED');
  if not found then return jsonb_build_object('canonicalMatchId',target_canonical_match_id,'bindingStatus','UNASSIGNED'); end if;
  select * into reservation from public.pachanga_venue_reservations rows where rows.id=binding.reservation_id;
  select * into venue from public.pachanga_club_venues rows where rows.id=binding.venue_id;
  select * into pitch from public.pachanga_venue_pitches rows where rows.id=binding.pitch_id;
  select assignments.schedule_state into referee_state from public.pachanga_referee_assignments assignments
  where assignments.canonical_match_id=target_canonical_match_id and assignments.status in ('accepted','confirmed','completed')
  order by assignments.server_sequence desc,assignments.id desc limit 1;
  return jsonb_build_object(
    'canonicalMatchId',target_canonical_match_id,'binding',to_jsonb(binding),
    'reservation',to_jsonb(reservation),'venue',private.pachanga_venue_public_projection_v1(venue.id),
    'pitch',jsonb_build_object('pitchId',pitch.id,'name',pitch.name,'modalities',pitch.modalities),
    'operationalLocation',case when private.pachanga_venue_private_location_can_v1(venue.id,actor_id)
      then jsonb_build_object('address',venue.private_address,'latitude',venue.private_latitude,'longitude',venue.private_longitude,'accessInstructions',venue.private_access_instructions)
      else null end,
    'refereeScheduleState',referee_state,'actionRequired',binding.action_required_code
  );
end;
$$;

revoke all on function public.get_pachanga_match_venue_v1(uuid) from public,anon;
grant execute on function public.get_pachanga_match_venue_v1(uuid) to authenticated,service_role;

create or replace function private.pachanga_venue_health_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'activeVenueWithoutPitch',(select count(*) from public.pachanga_club_venues venues where venues.lifecycle='ACTIVE' and not exists(select 1 from public.pachanga_venue_pitches pitches where pitches.venue_id=venues.id and pitches.status<>'ARCHIVED')),
    'pitchWithoutModality',(select count(*) from public.pachanga_venue_pitches pitches where cardinality(pitches.modalities)=0),
    'expiredActiveHolds',(select count(*) from public.pachanga_venue_reservation_holds holds where holds.status='ACTIVE' and holds.expires_at<=clock_timestamp()),
    'overlappingActiveClaims',(select count(*) from public.pachanga_venue_pitch_claims left_claim join public.pachanga_venue_pitch_claims right_claim on right_claim.id>left_claim.id and right_claim.conflict_scope_id=left_claim.conflict_scope_id and right_claim.status='ACTIVE' and left_claim.status='ACTIVE' and right_claim.occupied_range&&left_claim.occupied_range),
    'publicVenueWithoutConsent',(select count(*) from public.pachanga_club_venues venues where venues.visibility='PUBLIC' and not private.pachanga_venue_publicly_visible_v1(venues.id,false)),
    'matchWithMultipleCurrentBindings',(select count(*) from (select bindings.canonical_match_id from public.pachanga_venue_match_bindings bindings where bindings.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED') group by bindings.canonical_match_id having count(*)>1) duplicates),
    'venueActionRequired',(select count(*) from public.pachanga_venue_match_bindings bindings where bindings.status='ACTION_REQUIRED' and bindings.action_required_code='VENUE_ACTION_REQUIRED'),
    'refereeReconfirmationRequired',(select count(*) from public.pachanga_venue_match_bindings bindings join public.pachanga_referee_assignments assignments on assignments.canonical_match_id=bindings.canonical_match_id where bindings.status='ACTIVE' and assignments.status='confirmed' and assignments.schedule_state='RECONFIRMATION_REQUIRED'),
    'maintenanceReservationConflicts',(select count(*) from public.pachanga_venue_availability_exceptions exceptions join public.pachanga_venue_reservations reservations on reservations.pitch_id=exceptions.pitch_id and reservations.status in ('PENDING_CONFIRMATION','CONFIRMED') and exceptions.time_range&&tstzrange(reservations.starts_at,reservations.ends_at,'[)') where exceptions.status='ACTIVE' and exceptions.exception_kind in ('MAINTENANCE','CLOSED','BLOCKED')),
    'checkedAt',clock_timestamp()
  );
$$;

revoke all on function private.pachanga_venue_health_v1() from public,anon,authenticated;

create or replace function public.get_pachanga_venue_control_center_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare partner_candidates jsonb;
begin
  if actor_id is null or not private.pachanga_club_platform_can_v1(actor_id,'clubs.read') then
    raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode='42501';
  end if;

  with visible_venues as materialized (
    select venues.id,venues.club_id
    from public.pachanga_club_venues venues
    join private.pachanga_venue_publication_consents consents
      on consents.venue_id=venues.id
     and consents.status='ACTIVE'
     and consents.content_fingerprint=venues.public_content_fingerprint
    cross join private.pachanga_venue_settings_v1 settings
    where settings.singleton
      and settings.venue_foundation_enabled
      and settings.venue_public_profiles_enabled
      and venues.lifecycle='ACTIVE'
      and venues.visibility='PUBLIC'
  ), confirmed_by_venue as materialized (
    select reservations.venue_id,count(*) reservation_count
    from public.pachanga_venue_reservations reservations
    where reservations.status='CONFIRMED'
    group by reservations.venue_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'clubId',candidates.club_id,
    'clubName',candidates.club_name,
    'municipality',candidates.municipality,
    'publicVenues',candidates.public_venues,
    'confirmedReservations',candidates.confirmed_reservations
  ) order by candidates.confirmed_reservations desc,candidates.club_id),'[]'::jsonb)
  into partner_candidates
  from (
    select clubs.id club_id,clubs.name club_name,clubs.municipality,
      count(venues.id) public_venues,
      coalesce(sum(reservations.reservation_count),0) confirmed_reservations
    from public.pachanga_clubs clubs
    join visible_venues venues on venues.club_id=clubs.id
    left join confirmed_by_venue reservations on reservations.venue_id=venues.id
    where clubs.operational_status='active'
      and clubs.partnership_status in ('none','candidate')
    group by clubs.id,clubs.name,clubs.municipality
    order by confirmed_reservations desc,clubs.id
    limit 20
  ) candidates;

  return jsonb_build_object(
    'counts',jsonb_build_object(
      'venues',(select count(*) from public.pachanga_club_venues),
      'pitches',(select count(*) from public.pachanga_venue_pitches),
      'availabilityTemplates',(select count(*) from public.pachanga_venue_availability_templates where status='ACTIVE'),
      'exceptions',(select count(*) from public.pachanga_venue_availability_exceptions where status='ACTIVE'),
      'requests',(select count(*) from public.pachanga_venue_reservation_requests),
      'activeHolds',(select count(*) from public.pachanga_venue_reservation_holds where status='ACTIVE'),
      'confirmedReservations',(select count(*) from public.pachanga_venue_reservations where status='CONFIRMED'),
      'bindings',(select count(*) from public.pachanga_venue_match_bindings where status in ('ACTIVE','ACTION_REQUIRED','CONSUMED')),
      'cancellations',(select count(*) from public.pachanga_venue_reservations where status='CANCELLED'),
      'publicConsents',(select count(*) from private.pachanga_venue_publication_consents where status='ACTIVE'),
      'events',(select count(*) from private.pachanga_venue_events),
      'invalidations',(select count(*) from public.pachanga_venue_invalidations)
    ),
    'health',private.pachanga_venue_health_v1(),
    'flags',public.get_pachanga_venue_flags_v1(),
    'latestSequence',coalesce((select max(events.server_sequence) from private.pachanga_venue_events events),0),
    'indexes',jsonb_build_object(
      'protectedIndexCount',(select count(*) from pg_catalog.pg_indexes indexes where indexes.schemaname in ('public','private') and (indexes.indexname like 'pachanga_venue_%' or indexes.indexname like 'pachanga_club_venue_%')),
      'status','MIGRATION_MANAGED'
    ),
    'realtime',jsonb_build_object(
      'latestInvalidationSequence',coalesce((select max(invalidations.server_sequence) from public.pachanga_venue_invalidations invalidations),0),
      'publication','pachanga_realtime',
      'transport','postgres_changes'
    ),
    'errors',jsonb_build_object(
      'persistedCommandErrors',null,
      'status','NOT_IN_CANONICAL_LEDGER',
      'trackedByHealthChecks',true
    ),
    'partnerCandidates',partner_candidates
  );
end;
$$;

revoke all on function public.get_pachanga_venue_control_center_v1() from public,anon;
grant execute on function public.get_pachanga_venue_control_center_v1() to authenticated,service_role;

create or replace function public.get_pachanga_venue_home_status_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
begin
  if actor_id is null then raise exception 'VENUE_AUTH_REQUIRED' using errcode='42501'; end if;
  return jsonb_build_object(
    'teamOwner',jsonb_build_object(
      'visible',exists(select 1 from public.pachanga_groups groups where groups.owner_id=actor_id),
      'pendingCounterproposals',(select count(*) from public.pachanga_venue_reservation_requests requests join public.pachanga_groups groups on groups.id=requests.requester_team_id where groups.owner_id=actor_id and requests.status='COUNTER_PROPOSED'),
      'reservationsToConfirm',(select count(*) from public.pachanga_venue_reservations reservations join public.pachanga_groups groups on groups.id=reservations.requester_team_id where groups.owner_id=actor_id and reservations.status='PENDING_CONFIRMATION'),
      'matchesWithoutVenue',(select count(*) from public.pachanga_canonical_match_bindings sources join public.pachanga_groups groups on groups.id=sources.source_group_id where groups.owner_id=actor_id and sources.binding_status='active' and not exists(select 1 from public.pachanga_venue_match_bindings bindings where bindings.canonical_match_id=sources.canonical_match_id and bindings.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED')))
    ),
    'clubBookingManager',jsonb_build_object(
      'visible',exists(select 1 from public.pachanga_clubs clubs where private.pachanga_club_can_v1(clubs.id,actor_id,'reservation_manage')),
      'newRequests',(select count(*) from public.pachanga_venue_reservation_requests requests join public.pachanga_club_venues venues on venues.id=requests.venue_id where requests.status='SUBMITTED' and private.pachanga_club_can_v1(venues.club_id,actor_id,'reservation_manage')),
      'holdsExpiring',(select count(*) from public.pachanga_venue_reservation_holds holds join public.pachanga_venue_reservation_requests requests on requests.id=holds.request_id join public.pachanga_club_venues venues on venues.id=requests.venue_id where holds.status='ACTIVE' and holds.expires_at>clock_timestamp() and holds.expires_at<=clock_timestamp()+interval '60 minutes' and private.pachanga_club_can_v1(venues.club_id,actor_id,'reservation_manage')),
      'conflicts',(select count(*) from public.pachanga_venue_availability_exceptions exceptions join public.pachanga_venue_pitches pitches on pitches.id=exceptions.pitch_id join public.pachanga_club_venues venues on venues.id=pitches.venue_id join public.pachanga_venue_reservations reservations on reservations.pitch_id=pitches.id and reservations.status in ('PENDING_CONFIRMATION','CONFIRMED') and exceptions.time_range&&tstzrange(reservations.starts_at,reservations.ends_at,'[)') where exceptions.status='ACTIVE' and exceptions.exception_kind in ('MAINTENANCE','CLOSED','BLOCKED') and private.pachanga_club_can_v1(venues.club_id,actor_id,'reservation_manage')),
      'reservationsToday',(select count(*) from public.pachanga_venue_reservations reservations join public.pachanga_club_venues venues on venues.id=reservations.venue_id where reservations.status in ('PENDING_CONFIRMATION','CONFIRMED') and (reservations.starts_at at time zone venues.timezone)::date=(clock_timestamp() at time zone venues.timezone)::date and private.pachanga_club_can_v1(venues.club_id,actor_id,'reservation_manage'))
    ),
    'competitionOrganizer',jsonb_build_object(
      'visible',exists(select 1 from public.pachanga_competition_staff_assignments staff where staff.user_id=actor_id and staff.status='active' and staff.staff_role in ('competition_owner','competition_director','competition_admin')),
      'matchesWithoutVenue',(select count(*) from public.pachanga_competition_match_contexts contexts join public.pachanga_competition_staff_assignments staff on staff.competition_id=contexts.competition_id and staff.user_id=actor_id and staff.status='active' where contexts.status<>'retired' and not exists(select 1 from public.pachanga_venue_match_bindings bindings where bindings.canonical_match_id=contexts.canonical_match_id and bindings.status in ('ACTIVE','ACTION_REQUIRED','CONSUMED'))),
      'cancelledReservations',(select count(*) from public.pachanga_venue_reservations reservations join public.pachanga_competition_staff_assignments staff on staff.competition_id=reservations.competition_id and staff.user_id=actor_id and staff.status='active' where reservations.status='CANCELLED'),
      'venueChanges',(select count(*) from public.pachanga_venue_match_bindings bindings join public.pachanga_competition_match_contexts contexts on contexts.id=bindings.competition_match_context_id join public.pachanga_competition_staff_assignments staff on staff.competition_id=contexts.competition_id and staff.user_id=actor_id and staff.status='active' where bindings.previous_binding_id is not null)
    ),
    'latestSequence',coalesce((select max(events.server_sequence) from private.pachanga_venue_events events),0),
    'updatedAt',clock_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_venue_home_status_v1() from public,anon;
grant execute on function public.get_pachanga_venue_home_status_v1() to authenticated,service_role;

reset statement_timeout;
reset lock_timeout;
