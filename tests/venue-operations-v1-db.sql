\set ON_ERROR_STOP on

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE9A_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE9A_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object('sub', target_user_id, 'role', target_role))::text,
    true
  );
end;
$$;

do $$
declare
  response jsonb;
  replay jsonb;
  public_profile jsonb;
  private_detail jsonb;
  club_desk jsonb;
  control_center jsonb;
  home_status jsonb;
  venue_id uuid;
  venue_revision bigint;
  pitch_one_id uuid;
  pitch_two_id uuid;
  request_one_id uuid;
  request_one_revision bigint;
  reservation_one_id uuid;
  reservation_one_revision bigint;
  request_two_id uuid;
  request_two_revision bigint;
  reservation_two_id uuid;
  reservation_two_revision bigint;
  overlap_request_id uuid;
  overlap_request_revision bigint;
  hold_request_id uuid;
  hold_request_revision bigint;
  hold_id uuid;
  my_reservations jsonb;
  context_revision bigint;
  winter timestamptz;
  summer timestamptz;
  repeated_summer timestamptz;
  repeated_winter timestamptz;
begin
  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_venue_settings_v1
      where singleton and not venue_foundation_enabled
        and not venue_management_enabled and not venue_payments_enabled) = 1,
    'Wave 9A flags were not born OFF'
  );

  -- Create the pre-existing match official through the production lifecycle.
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_referee_assignment_beta_v1(
    'e9060000-0000-4000-8000-000000000001',
    'e9030000-0000-4000-8000-000000000001', 0, 'assignment.propose',
    jsonb_build_object(
      'refereeProfileId','d6020000-0000-4000-8000-000000000001',
      'sourceKind','competition_generated',
      'sourceId','e9070000-0000-4000-8000-000000000005',
      'requesterKind','COMPETITION',
      'requesterId','c4200000-0000-4000-8000-000000000001',
      'assignmentRole','MAIN_REFEREE',
      'responseDeadline',clock_timestamp()+interval '10 days',
      'feeMode','FIXED','proposedFeeCents',6500,'currency','EUR'
    ), '{"clientVersion":"9.0.0+dbtest","surface":"wave9a-r4d"}'
  );
  perform pg_temp.actor('d6010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_referee_assignment_beta_v1(
    'e9060000-0000-4000-8000-000000000002',
    'e9030000-0000-4000-8000-000000000001', 1, 'assignment.accept',
    '{}', '{"clientVersion":"9.0.0+dbtest","surface":"wave9a-r4d"}'
  );
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_referee_assignment_beta_v1(
    'e9060000-0000-4000-8000-000000000003',
    'e9030000-0000-4000-8000-000000000001', 2, 'assignment.confirm',
    '{}', '{"clientVersion":"9.0.0+dbtest","surface":"wave9a-r4d"}'
  );
  perform pg_temp.assert_true(
    (select status='confirmed' and schedule_state='CURRENT'
     from public.pachanga_referee_assignments
     where id='e9030000-0000-4000-8000-000000000001'),
    'Synthetic official did not reach confirmed through canonical RPCs'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000001');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_venue_reservation_v1(
      'e9100000-0000-4000-8000-000000000001', null, 0, 'venue.create',
      '{"clubId":"e9020000-0000-4000-8000-000000000001","name":"Disabled Venue","slug":"disabled-venue","timezone":"Europe/Madrid"}', '{}'
    )
  $sql$, 'VENUE_FOUNDATION_DISABLED');

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000001');
  response := public.set_pachanga_venue_flags_v1(
    'e9100000-0000-4000-8000-000000000002', 1,
    '{
      "venueFoundationEnabled":true,
      "venueManagementEnabled":true,
      "venuePublicProfilesEnabled":true,
      "venuePublicDirectoryEnabled":true,
      "venueAvailabilityEnabled":true,
      "venueReservationRequestsEnabled":true,
      "venueCounteroffersEnabled":true,
      "venueReservationHoldsEnabled":true,
      "venueCanonicalReservationsEnabled":true,
      "venueMatchBindingEnabled":true,
      "venueR4dIntegrationEnabled":true,
      "demoWorldV34Enabled":true
    }',
    '{"clientVersion":"9.0.0+dbtest","serviceWorkerVersion":"sw-wave9a","installedMode":"standalone","surface":"db"}'
  );
  perform pg_temp.assert_true((response->>'confirmedRevision')::bigint = 2, 'Venue flags revision did not advance');
  perform pg_temp.assert_true(
    not (public.get_pachanga_venue_flags_v1()->>'venuePaymentsEnabled')::boolean
      and not (public.get_pachanga_venue_flags_v1()->>'venueRecurringBookingsEnabled')::boolean,
    'Future payment or recurring flags were activated'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000003', null, 0, 'venue.create',
    '{
      "clubId":"e9020000-0000-4000-8000-000000000001",
      "name":"Centre Esportiu Barris IQ",
      "slug":"centre-esportiu-barris-iq-camps",
      "description":"Instalación sintética para validar disponibilidad y reservas.",
      "municipality":"Barcelona",
      "generalArea":"Zona IQ",
      "timezone":"Europe/Madrid",
      "privateAddress":"Carrer Sintètic 9, porta privada",
      "publicAddress":"Zona Esportiva IQ",
      "privateLatitude":41.390001,
      "privateLongitude":2.170001,
      "publicLatitude":41.390,
      "publicLongitude":2.170,
      "privateAccessInstructions":"Código sintético 9999; nunca público.",
      "privateContactName":"Responsable Sintético",
      "privateContactPhone":"+34000000000",
      "privateContactEmail":"venue-private@example.test",
      "visibility":"PRIVATE"
    }',
    '{"clientVersion":"9.0.0+dbtest","surface":"club-venue-create","unknown":"discarded"}'
  );
  replay := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000003', null, 0, 'venue.create',
    '{
      "clubId":"e9020000-0000-4000-8000-000000000001",
      "name":"Centre Esportiu Barris IQ",
      "slug":"centre-esportiu-barris-iq-camps",
      "description":"Instalación sintética para validar disponibilidad y reservas.",
      "municipality":"Barcelona",
      "generalArea":"Zona IQ",
      "timezone":"Europe/Madrid",
      "privateAddress":"Carrer Sintètic 9, porta privada",
      "publicAddress":"Zona Esportiva IQ",
      "privateLatitude":41.390001,
      "privateLongitude":2.170001,
      "publicLatitude":41.390,
      "publicLongitude":2.170,
      "privateAccessInstructions":"Código sintético 9999; nunca público.",
      "privateContactName":"Responsable Sintético",
      "privateContactPhone":"+34000000000",
      "privateContactEmail":"venue-private@example.test",
      "visibility":"PRIVATE"
    }',
    '{"clientVersion":"9.0.0+dbtest","surface":"club-venue-create","unknown":"discarded"}'
  );
  perform pg_temp.assert_true(response = replay, 'Venue create replay diverged');
  venue_id := (response->>'aggregateId')::uuid;
  venue_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_club_venues where id=venue_id)=1
      and (select count(*) from private.pachanga_venue_operation_receipts where operation_id='e9100000-0000-4000-8000-000000000003')=1,
    'Venue create replay duplicated authority or receipt'
  );
  perform pg_temp.assert_true(
    (select client_metadata ? 'unknown' from private.pachanga_venue_operation_receipts where operation_id='e9100000-0000-4000-8000-000000000003') = false,
    'Client metadata allowlist retained an unknown field'
  );

  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_venue_reservation_v1(
      'e9100000-0000-4000-8000-000000000004', null, 0, 'venue.create',
      '{"clubId":"e9020000-0000-4000-8000-000000000001","name":"Forged Venue","slug":"forged-venue","timezone":"Europe/Madrid","actorId":"e9010000-0000-4000-8000-000000000005"}', '{}'
    )
  $sql$, 'VENUE_ACTION_OR_PAYLOAD_NOT_ALLOWED|VENUE_CLIENT_AUTHORITY_FIELD_FORBIDDEN');

  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000005', venue_id, venue_revision,
    'venue.activate', '{"reasonCode":"SYNTHETIC_ACTIVATION"}', '{}'
  );
  venue_revision := (response->>'confirmedRevision')::bigint;

  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_venue_reservation_v1(
      'e9100000-0000-4000-8000-000000000006', %L::uuid, %s,
      'venue.activate', '{"reasonCode":"STALE"}', '{}'
    )
  $sql$, venue_id, venue_revision-1), 'STALE_REVISION');

  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000007', null, 0, 'pitch.create',
    jsonb_build_object(
      'venueId',venue_id,'name','Campo 1','slug','campo-1','modalities',jsonb_build_array('F7'),
      'surface','ARTIFICIAL_GRASS','environment','OUTDOOR','hasLighting',true,
      'hasChangingRooms',true,'hasShowers',true,'isAccessible',true,'hasParking',true,
      'publicRateKind','FIXED_QUOTE','publicRateAmountMinor',7000,
      'publicRateCurrency','EUR','publicRateNote','Precio orientativo sintético',
      'visibility','PUBLIC','minimumSlotMinutes',60,'bufferMinutes',10
    ), '{}'
  );
  pitch_one_id := (response->>'aggregateId')::uuid;
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000008', null, 0, 'pitch.create',
    jsonb_build_object(
      'venueId',venue_id,'name','Campo 2','slug','campo-2','modalities',jsonb_build_array('F7'),
      'surface','ARTIFICIAL_GRASS','environment','OUTDOOR','hasLighting',true,
      'publicRateKind','CONTACT_CLUB','visibility','PUBLIC','minimumSlotMinutes',60,'bufferMinutes',0
    ), '{}'
  );
  pitch_two_id := (response->>'aggregateId')::uuid;

  perform public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000009', null, 0, 'availability.template.create',
    jsonb_build_object(
      'pitchId',pitch_one_id,'weekday',1,'startLocalTime','18:00','endLocalTime','23:00',
      'slotMinutes',70,'bufferMinutes',10,'validFrom','2027-01-01','validUntil','2027-12-31',
      'timezone','Europe/Madrid','modalities',jsonb_build_array('F7'),'capacity',1,'visibility','PUBLIC'
    ), '{}'
  );
  perform public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000010', null, 0, 'availability.template.create',
    jsonb_build_object(
      'pitchId',pitch_two_id,'weekday',1,'startLocalTime','18:00','endLocalTime','23:00',
      'slotMinutes',70,'bufferMinutes',0,'validFrom','2027-01-01','validUntil','2027-12-31',
      'timezone','Europe/Madrid','modalities',jsonb_build_array('F7'),'capacity',1,'visibility','PUBLIC'
    ), '{}'
  );

  perform pg_temp.expect_failure($sql$
    select public.get_pachanga_public_venue_v1('centre-esportiu-barris-iq-camps')
  $sql$, 'VENUE_PUBLIC_PROFILE_NOT_FOUND');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000011', venue_id, venue_revision,
    'venue.publication.consent',
    '{"selectedFields":{"description":true,"address":false,"coordinates":true},"addressMode":"APPROXIMATE_COORDINATES","publicRateAllowed":true,"reasonCode":"PUBLIC_SYNTHETIC_CONSENT"}', '{}'
  );
  venue_revision := (response->>'confirmedRevision')::bigint;
  public_profile := public.get_pachanga_public_venue_v1('centre-esportiu-barris-iq-camps');
  perform pg_temp.assert_true(
    public_profile->>'address' is null
      and public_profile::text !~* 'Carrer Sintètic|9999|Responsable Sintético|venue-private|\+34000000000'
      and public_profile #>> '{coordinates,precision}' = 'APPROXIMATE',
    'Public Venue projection exposed private location or ignored consent precision'
  );
  perform pg_temp.assert_true(
    public_profile #>> '{pitches,0,publicRate,amountMinor}' = '7000'
      and public_profile #>> '{pitches,0,publicRate,currency}' = 'EUR'
      and public_profile::text ~ 'Pago fuera de Pachangas IQ',
    'Consented public tariff was not projected safely'
  );

  winter := private.pachanga_venue_resolve_local_v1('2027-01-15 20:00','Europe/Madrid',60);
  summer := private.pachanga_venue_resolve_local_v1('2027-07-15 20:00','Europe/Madrid',120);
  repeated_summer := private.pachanga_venue_resolve_local_v1('2027-10-31 02:30','Europe/Madrid',120);
  repeated_winter := private.pachanga_venue_resolve_local_v1('2027-10-31 02:30','Europe/Madrid',60);
  perform pg_temp.assert_true(winter='2027-01-15 19:00:00+00'::timestamptz, 'Winter offset resolution is wrong');
  perform pg_temp.assert_true(summer='2027-07-15 18:00:00+00'::timestamptz, 'Summer offset resolution is wrong');
  perform pg_temp.assert_true(repeated_summer<>repeated_winter, 'Repeated DST hour did not resolve to two instants');
  perform pg_temp.expect_failure($sql$
    select private.pachanga_venue_resolve_local_v1('2027-03-28 02:30','Europe/Madrid',null)
  $sql$, 'VENUE_LOCAL_TIME_DOES_NOT_EXIST');
  perform pg_temp.expect_failure($sql$
    select private.pachanga_venue_resolve_local_v1('2027-10-31 02:30','Europe/Madrid',null)
  $sql$, 'VENUE_LOCAL_TIME_AMBIGUOUS');

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000012', null, 0, 'reservation.request.create',
    jsonb_build_object(
      'venueId',venue_id,'pitchId',pitch_one_id,'requesterKind','TEAM',
      'requesterTeamId','c4100000-0000-4000-8000-000000000002','competitionId','c4200000-0000-4000-8000-000000000001',
      'canonicalMatchId','e9070000-0000-4000-8000-000000000006','ruleRevisionId','e9050000-0000-4000-8000-000000000001',
      'purpose','COMPETITION_MATCH','modality','F7','localStart','2027-05-17 20:00',
      'localEnd','2027-05-17 21:10','timezone','Europe/Madrid','offsetMinutes',120,
      'message','Solicitud sintética del equipo local.'
    ), '{}'
  );
  request_one_id := (response->>'aggregateId')::uuid;
  request_one_revision := (response->>'confirmedRevision')::bigint;
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000013', request_one_id, request_one_revision,
    'reservation.request.submit', '{}', '{}'
  );
  request_one_revision := (response->>'confirmedRevision')::bigint;

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000014', request_one_id, request_one_revision,
    'reservation.review.start', '{}', '{}'
  );
  request_one_revision := (response->>'confirmedRevision')::bigint;
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000015', request_one_id, request_one_revision,
    'reservation.counter',
    jsonb_build_object(
      'pitchId',pitch_one_id,'localStart','2027-05-17 20:00','localEnd','2027-05-17 21:10',
      'timezone','Europe/Madrid','offsetMinutes',120,
      'terms',jsonb_build_object('kind','FIXED_QUOTE','amountMinor',7000,'currency','EUR','publicRateAllowed',true,'privateNotes','Nota privada sintética'),
      'message','Mismo horario, términos confirmados.'
    ), '{}'
  );
  request_one_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.expect_failure($sql$
    select public.get_pachanga_club_venue_desk_v1('c4020000-0000-4000-8000-000000000001')
  $sql$, 'VENUE_CLUB_DESK_AUTHORITY_REQUIRED');
  club_desk := public.get_pachanga_club_venue_desk_v1('e9020000-0000-4000-8000-000000000001');
  perform pg_temp.assert_true(
    jsonb_array_length(club_desk->'availabilityTemplates')=2
      and jsonb_typeof(club_desk->'availabilityExceptions')='array'
      and jsonb_typeof(club_desk->'matchBindings')='array'
      and jsonb_typeof(club_desk->'conflicts')='array'
      and exists(
        select 1 from jsonb_array_elements(club_desk->'requests') item
        where item->>'id'=request_one_id::text
          and item->>'message'='Solicitud sintética del equipo local.'
      ),
    'Club Venue desk omitted canonical availability or requester review context'
  );

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000016', request_one_id, request_one_revision,
    'reservation.accept', '{}', '{}'
  );
  reservation_one_id := (response->>'aggregateId')::uuid;
  reservation_one_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select status from public.pachanga_venue_reservations where id=reservation_one_id)='PENDING_CONFIRMATION',
    'Counter acceptance did not create one pending canonical reservation'
  );
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000017', reservation_one_id, reservation_one_revision,
    'reservation.confirm', '{}', '{}'
  );
  reservation_one_revision := (response->>'confirmedRevision')::bigint;
  private_detail := public.get_pachanga_venue_reservation_v1(reservation_one_id);
  perform pg_temp.assert_true(
    private_detail #>> '{operationalLocation,address}' = 'Carrer Sintètic 9, porta privada'
      and private_detail::text !~ 'Nota privada sintética',
    'Confirmed requester lacks operational location or private terms leaked'
  );

  select revision into context_revision from public.pachanga_competition_match_contexts
  where id='e9070000-0000-4000-8000-000000000008';
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000018', reservation_one_id, reservation_one_revision,
    'reservation.bind_match',
    jsonb_build_object(
      'canonicalMatchId','e9070000-0000-4000-8000-000000000006',
      'competitionMatchContextId','e9070000-0000-4000-8000-000000000008',
      'scheduleItemId','e9070000-0000-4000-8000-000000000005',
      'ruleRevisionId','e9050000-0000-4000-8000-000000000001'
    ), '{}'
  );
  reservation_one_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_match_bindings where canonical_match_id='e9070000-0000-4000-8000-000000000006' and status='ACTIVE')=1,
    'Initial CanonicalMatch binding is not unique and active'
  );

  -- A competing Team can draft a request, but cannot consume the occupied slot.
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000004');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000019', null, 0, 'reservation.request.create',
    jsonb_build_object(
      'venueId',venue_id,'pitchId',pitch_one_id,'requesterKind','TEAM',
      'requesterTeamId','c4100000-0000-4000-8000-000000000003','purpose','STANDALONE_MATCH',
      'modality','F7','localStart','2027-05-17 20:00','localEnd','2027-05-17 21:10',
      'timezone','Europe/Madrid','offsetMinutes',120
    ), '{}'
  );
  overlap_request_id := (response->>'aggregateId')::uuid;
  overlap_request_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_venue_reservation_v1(
      'e9100000-0000-4000-8000-000000000020', %L::uuid, %s,
      'reservation.request.submit', '{}', '{}'
    )
  $sql$, overlap_request_id, overlap_request_revision), 'VENUE_SLOT_CONFLICT');

  -- A second Pitch can be reserved for the same instant and then replace the
  -- venue through R4D without mutating CanonicalMatch identity.
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000021', null, 0, 'reservation.request.create',
    jsonb_build_object(
      'venueId',venue_id,'pitchId',pitch_two_id,'requesterKind','TEAM',
      'requesterTeamId','c4100000-0000-4000-8000-000000000002','competitionId','c4200000-0000-4000-8000-000000000001',
      'canonicalMatchId','e9070000-0000-4000-8000-000000000006','ruleRevisionId','e9050000-0000-4000-8000-000000000001',
      'purpose','COMPETITION_MATCH','modality','F7','localStart','2027-05-17 20:00',
      'localEnd','2027-05-17 21:10','timezone','Europe/Madrid','offsetMinutes',120
    ), '{}'
  );
  request_two_id := (response->>'aggregateId')::uuid;
  request_two_revision := (response->>'confirmedRevision')::bigint;
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000022', request_two_id, request_two_revision,
    'reservation.request.submit', '{}', '{}'
  );
  request_two_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000023', request_two_id, request_two_revision,
    'reservation.accept',
    jsonb_build_object('terms',jsonb_build_object('kind','CONTACT_CLUB')), '{}'
  );
  reservation_two_id := (response->>'aggregateId')::uuid;
  reservation_two_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000024', reservation_two_id, reservation_two_revision,
    'reservation.confirm', '{}', '{}'
  );
  reservation_two_revision := (response->>'confirmedRevision')::bigint;

  select revision into context_revision from public.pachanga_competition_match_contexts
  where id='e9070000-0000-4000-8000-000000000008';
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000025', reservation_two_id, reservation_two_revision,
    'reservation.replace_venue',
    jsonb_build_object(
      'competitionMatchContextId','e9070000-0000-4000-8000-000000000008',
      'expectedContextRevision',context_revision,'reasonCode','PITCH_UNAVAILABLE',
      'publicSummary','Cambio sintético de campo confirmado.'
    ), '{}'
  );
  reservation_two_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_canonical_matches where id='e9070000-0000-4000-8000-000000000006')=1
      and (select count(*) from public.pachanga_venue_match_bindings where canonical_match_id='e9070000-0000-4000-8000-000000000006' and status='ACTIVE')=1
      and (select count(*) from public.pachanga_venue_match_bindings where canonical_match_id='e9070000-0000-4000-8000-000000000006' and status='HISTORICAL')=1,
    'R4D replacement changed CanonicalMatch identity or lost binding lineage'
  );
  perform pg_temp.assert_true(
    (select schedule_state from public.pachanga_referee_assignments where id='e9030000-0000-4000-8000-000000000001')='RECONFIRMATION_REQUIRED',
    'R4D Venue replacement did not require referee reconfirmation'
  );

  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000026', reservation_two_id, reservation_two_revision,
    'reservation.cancel', '{"reasonCode":"SYNTHETIC_CANCELLATION"}', '{}'
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_canonical_matches where id='e9070000-0000-4000-8000-000000000006')='active'
      and (select count(*) from public.pachanga_venue_match_bindings where reservation_id=reservation_two_id and status='ACTION_REQUIRED' and action_required_code='VENUE_ACTION_REQUIRED')=1,
    'Reservation cancellation auto-cancelled the match or omitted Venue action required'
  );

  -- Hold expiry uses server authority and converges to one released claim.
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000004');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000027', null, 0, 'reservation.request.create',
    jsonb_build_object(
      'venueId',venue_id,'pitchId',pitch_one_id,'requesterKind','TEAM',
      'requesterTeamId','c4100000-0000-4000-8000-000000000003','purpose','STANDALONE_MATCH',
      'modality','F7','localStart','2027-03-22 20:00','localEnd','2027-03-22 21:10',
      'timezone','Europe/Madrid','offsetMinutes',60
    ), '{}'
  );
  hold_request_id := (response->>'aggregateId')::uuid;
  hold_request_revision := (response->>'confirmedRevision')::bigint;
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000028', hold_request_id, hold_request_revision,
    'reservation.request.submit', '{}', '{}'
  );
  hold_request_revision := (response->>'confirmedRevision')::bigint;
  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_venue_reservation_v1(
    'e9100000-0000-4000-8000-000000000029', hold_request_id, hold_request_revision,
    'reservation.hold', jsonb_build_object('expiresInMinutes',15), '{}'
  );
  hold_id := (response->>'aggregateId')::uuid;
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000004');
  my_reservations := public.get_pachanga_my_venue_reservations_v1();
  perform pg_temp.assert_true(
    exists(
      select 1 from jsonb_array_elements(my_reservations->'items') item
      where item#>>'{request,id}'=hold_request_id::text
        and item#>>'{hold,id}'=hold_id::text
        and item#>>'{hold,status}'='ACTIVE'
        and item#>>'{hold,claim_id}' is null
        and item#>>'{request,message}' is null
    ),
    'User read model omitted its privacy-filtered active hold'
  );
  update public.pachanga_venue_reservation_holds
  set created_at=clock_timestamp()-interval '2 minutes',
      expires_at=clock_timestamp()-interval '1 second'
  where id=hold_id;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  response := public.expire_pachanga_venue_holds_v1('e9100000-0000-4000-8000-000000000030',100);
  replay := public.expire_pachanga_venue_holds_v1('e9100000-0000-4000-8000-000000000030',100);
  perform pg_temp.assert_true(response=replay and (response#>>'{snapshot,expiredCount}')::integer=1, 'Hold expiry replay diverged');
  perform pg_temp.assert_true(
    (select status from public.pachanga_venue_reservation_holds where id=hold_id)='EXPIRED'
      and (select status from public.pachanga_venue_pitch_claims where source_id=hold_id)='EXPIRED'
      and (select status from public.pachanga_venue_reservation_requests where id=hold_request_id)='EXPIRED',
    'Expired hold did not converge request, hold and claim'
  );

  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_venue_events)=27
      and (select count(*) from private.pachanga_venue_operation_receipts)=27
      and (select count(*) from private.pachanga_venue_events events join private.pachanga_venue_operation_receipts receipts using(operation_id) where events.server_sequence=receipts.server_sequence)=27,
    'Venue event/receipt ledger is incomplete or unordered'
  );
  perform pg_temp.assert_true(
    not exists(select 1 from public.pachanga_venue_pitch_claims a join public.pachanga_venue_pitch_claims b on a.id<b.id and a.conflict_scope_id=b.conflict_scope_id and a.status='ACTIVE' and b.status='ACTIVE' and a.occupied_range&&b.occupied_range),
    'Confirmed or held claims overlap'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000001');
  control_center := public.get_pachanga_venue_control_center_v1();
  perform pg_temp.assert_true(
    (control_center#>>'{counts,venues}')::integer=1
      and (control_center#>>'{counts,pitches}')::integer=2
      and (control_center#>>'{counts,invalidations}')::integer>0
      and (control_center#>>'{indexes,protectedIndexCount}')::integer>=10
      and control_center#>>'{realtime,transport}'='postgres_changes'
      and control_center#>>'{errors,status}'='NOT_IN_CANONICAL_LEDGER'
      and jsonb_array_length(control_center->'partnerCandidates')=1,
    'Venue Control Center omitted canonical health, indexes, Realtime or partner candidates'
  );
  home_status := public.get_pachanga_venue_home_status_v1();
  perform pg_temp.assert_true(
    (home_status#>>'{clubBookingManager,visible}')::boolean
      and (home_status#>>'{clubBookingManager,newRequests}')::integer>=0
      and home_status ? 'teamOwner'
      and home_status ? 'competitionOrganizer',
    'Role-aware Home omitted the authorized Club perspective or canonical role projections'
  );
end;
$$;

-- Direct table writes remain closed even though the Data API roles can execute
-- the command/read functions.
create temporary table venue_operations_v1_test_refs (
  reservation_id uuid not null
) on commit drop;
insert into venue_operations_v1_test_refs(reservation_id)
select id from public.pachanga_venue_reservations order by server_sequence limit 1;
grant select on venue_operations_v1_test_refs to authenticated;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"e9010000-0000-4000-8000-000000000005","role":"authenticated"}',true);
select pg_temp.expect_failure($sql$
  insert into public.pachanga_club_venues(
    club_id,name,slug,operation_id,created_by,updated_by
  ) values (
    'e9020000-0000-4000-8000-000000000001','Direct write','direct-write',
    'e9100000-0000-4000-8000-000000000099',
    'e9010000-0000-4000-8000-000000000005','e9010000-0000-4000-8000-000000000005'
  )
$sql$, 'permission denied|row-level security');
select pg_temp.expect_failure($sql$
  select public.get_pachanga_venue_reservation_v1(
    (select reservation_id from venue_operations_v1_test_refs limit 1)
  )
$sql$, 'VENUE_RESERVATION_READ_FORBIDDEN|VENUE_RESERVATION_NOT_FOUND');
select pg_temp.expect_failure($sql$
  select private.pachanga_club_can_v1(
    'e9020000-0000-4000-8000-000000000001',
    'e9010000-0000-4000-8000-000000000001',
    'venue_read'
  )
$sql$, 'permission denied');
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_venue_invalidations
    where audience_kind='CLUB'
      and audience_id='e9020000-0000-4000-8000-000000000001'
  ),
  'Outsider could read Club-scoped Venue invalidations'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"e9010000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_venue_invalidations
    where audience_kind='CLUB'
      and audience_id='e9020000-0000-4000-8000-000000000001'
  ),
  'Authorized Venue manager could not read Club-scoped invalidations'
);
reset role;

select 'VENUE_OPERATIONS_V1_DB_PASS';
