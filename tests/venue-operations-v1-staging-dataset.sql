\set ON_ERROR_STOP on

begin;

do $$
declare
  flags jsonb;
  response jsonb;
begin
  perform set_config('request.jwt.claims','{"sub":"c4010000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  flags := public.get_pachanga_club_foundation_flags_v1();
  response := public.command_pachanga_club_platform_v1(
    private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-club-flags'),
    '00000000-0000-0000-0000-00000000c101', (flags->>'revision')::bigint,
    'club_flags.set',
    '{"competitionOrganizerEnabled":true,"foundationEnabled":true,"publicProfilesEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"reason":"Wave 9A isolated staging dependency"}',
    '{"clientVersion":"9.0.0+staging","installedMode":"standalone","serviceWorkerVersion":"9.0.0+staging","surface":"wave9a-staging-dataset"}'
  );
  if not (response#>>'{snapshot,foundationEnabled}')::boolean then
    raise exception 'WAVE9A_STAGING_CLUB_FLAGS_NOT_ENABLED';
  end if;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values
  ('e9200000-0000-4000-8000-000000000001', 'wave9a-cert-owner-a@example.test', clock_timestamp(), '{"full_name":"Wave 9A Cert Owner A"}'),
  ('e9200000-0000-4000-8000-000000000002', 'wave9a-cert-owner-b@example.test', clock_timestamp(), '{"full_name":"Wave 9A Cert Owner B"}');

do $$
declare
  response jsonb;
begin
  perform set_config('request.jwt.claims','{"sub":"e9200000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  response := public.command_pachanga_club_foundation_v1(
    private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-club-a'),
    'e9210000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"clubType":"SPORTS_CENTER","countryCode":"ES","municipality":"Barcelona","name":"Pavelló Nocturn IQ","province":"Barcelona","reason":"Wave 9A staging dataset","slug":"pavello-nocturn-iq-staging","visibility":"private"}',
    '{"clientVersion":"9.0.0+staging","installedMode":"standalone","serviceWorkerVersion":"9.0.0+staging","surface":"wave9a-staging-dataset"}'
  );

  perform set_config('request.jwt.claims','{"sub":"e9200000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  response := public.command_pachanga_club_foundation_v1(
    private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-club-b'),
    'e9210000-0000-4000-8000-000000000002', 0, 'club.create',
    '{"clubType":"SPORTS_CENTER","countryCode":"ES","municipality":"Badalona","name":"Complex Relàmpag IQ","province":"Barcelona","reason":"Wave 9A staging dataset","slug":"complex-relampag-iq-staging","visibility":"private"}',
    '{"clientVersion":"9.0.0+staging","installedMode":"standalone","serviceWorkerVersion":"9.0.0+staging","surface":"wave9a-staging-dataset"}'
  );
end;
$$;

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, payload_revision, billing_status
) values
  ('e9220000-0000-4000-8000-000000000001','e9200000-0000-4000-8000-000000000001','Barris IQ Nord','W9ANORD','{"matches":[],"players":[],"siteSettings":{},"venues":[],"qaFixture":"WAVE9A_STAGING"}',1,'trial'),
  ('e9220000-0000-4000-8000-000000000002','e9200000-0000-4000-8000-000000000001','Barris IQ Sud','W9ASUD','{"matches":[],"players":[],"siteSettings":{},"venues":[],"qaFixture":"WAVE9A_STAGING"}',1,'trial'),
  ('e9220000-0000-4000-8000-000000000003','e9200000-0000-4000-8000-000000000002','Relàmpag IQ','W9AREL','{"matches":[],"players":[],"siteSettings":{},"venues":[],"qaFixture":"WAVE9A_STAGING"}',1,'trial');

insert into public.pachanga_group_members(group_id,user_id,role,display_name)
values
  ('e9220000-0000-4000-8000-000000000001','e9200000-0000-4000-8000-000000000001','owner','Wave 9A Cert Owner A'),
  ('e9220000-0000-4000-8000-000000000002','e9200000-0000-4000-8000-000000000001','owner','Wave 9A Cert Owner A'),
  ('e9220000-0000-4000-8000-000000000003','e9200000-0000-4000-8000-000000000002','owner','Wave 9A Cert Owner B');

do $$
declare
  actor_id uuid;
  club_id uuid;
  venue_id uuid;
  pitch_id uuid;
  response jsonb;
  venue_index integer;
  pitch_index integer := 0;
begin
  for venue_index in 1..5 loop
    if venue_index = 1 then
      actor_id := 'e9010000-0000-4000-8000-000000000001';
      club_id := 'e9020000-0000-4000-8000-000000000001';
    elsif venue_index <= 3 then
      actor_id := 'e9200000-0000-4000-8000-000000000001';
      club_id := 'e9210000-0000-4000-8000-000000000001';
    else
      actor_id := 'e9200000-0000-4000-8000-000000000002';
      club_id := 'e9210000-0000-4000-8000-000000000002';
    end if;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'role','authenticated')::text,true);
    response := public.command_pachanga_venue_reservation_v1(
      private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-venue-create-' || venue_index),
      null, 0, 'venue.create',
      jsonb_build_object(
        'clubId',club_id,'name','Instalación IQ ' || venue_index,
        'slug','instalacion-iq-staging-' || venue_index,'municipality','Barcelona',
        'generalArea','Zona sintética ' || venue_index,'timezone','Europe/Madrid',
        'privateAddress','Ubicación sintética privada ' || venue_index,'visibility','PRIVATE'
      ),
      '{"clientVersion":"9.0.0+staging","installedMode":"standalone","serviceWorkerVersion":"9.0.0+staging","surface":"wave9a-staging-dataset"}'
    );
    venue_id := (response->>'aggregateId')::uuid;
    response := public.command_pachanga_venue_reservation_v1(
      private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-venue-activate-' || venue_index),
      venue_id, (response->>'confirmedRevision')::bigint, 'venue.activate',
      '{"reasonCode":"STAGING_DATASET"}', '{}'
    );

    for pitch_in_venue in 1..2 loop
      pitch_index := pitch_index + 1;
      response := public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-pitch-create-' || pitch_index),
        null, 0, 'pitch.create',
        jsonb_build_object(
          'venueId',venue_id,'name','Campo IQ ' || pitch_index,
          'slug','campo-iq-staging-' || pitch_index,'modalities',jsonb_build_array('F7'),
          'surface','ARTIFICIAL_GRASS','environment','OUTDOOR','hasLighting',true,
          'visibility','PRIVATE','minimumSlotMinutes',60,'bufferMinutes',5
        ), '{}'
      );
      pitch_id := (response->>'aggregateId')::uuid;
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-availability-' || pitch_index),
        null, 0, 'availability.template.create',
        jsonb_build_object(
          'pitchId',pitch_id,'weekday',6,'startLocalTime','09:00','endLocalTime','22:00',
          'slotMinutes',65,'bufferMinutes',5,'validFrom','2027-01-01','validUntil','2027-12-31',
          'timezone','Europe/Madrid','modalities',jsonb_build_array('F7'),'capacity',1,
          'visibility','PRIVATE'
        ), '{}'
      );
    end loop;
  end loop;
end;
$$;

set local session_replication_role = replica;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_club_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  'e9260000-0000-4000-8000-000000000001','CLUB',
  'e9210000-0000-4000-8000-000000000001','Torneo Campos Wave 9A',
  'torneo-campos-wave9a-staging','TOURNAMENT','private','draft',
  'e9200000-0000-4000-8000-000000000001'
);

insert into public.pachanga_canonical_matches(id,status,revision,created_by)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-staging-canonical-match-' || series),
  'active', 1, 'e9200000-0000-4000-8000-000000000001'
from generate_series(1,14) series;

set local session_replication_role = origin;

do $$
begin
  if (select count(*) from public.pachanga_clubs) <> 3
     or (select count(*) from public.pachanga_groups) <> 6
     or (select count(*) from public.pachanga_club_venues) <> 6
     or (select count(*) from public.pachanga_venue_pitches) <> 12
     or (select count(*) from public.pachanga_competitions where competition_type='LEAGUE') <> 1
     or (select count(*) from public.pachanga_competitions where competition_type='TOURNAMENT') <> 1
     or (select count(*) from public.pachanga_canonical_matches) <> 20 then
    raise exception 'WAVE9A_STAGING_DATASET_COUNT_MISMATCH';
  end if;
end;
$$;

commit;

select 'VENUE_OPERATIONS_V1_STAGING_DATASET_PASS';
