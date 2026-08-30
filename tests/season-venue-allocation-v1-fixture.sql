-- Wave 9B synthetic fixture layered on the canonical Wave 9A/R4D graph.
-- Setup rows are deterministic; every Wave 9B mutation in the suite uses RPC authority.

\ir venue-operations-v1-fixture.sql

insert into public.pachanga_club_venues(
  id,club_id,name,slug,description,municipality,general_area,timezone,
  private_address,visibility,lifecycle,operation_id,created_by,updated_by
) values(
  'e9b20000-0000-4000-8000-000000000001',
  'e9020000-0000-4000-8000-000000000001',
  'Season Allocation Centre','season-allocation-centre',
  'Synthetic Venue used only inside isolated Wave 9B databases.',
  'Barcelona','Zona Synthetic','Europe/Madrid','Synthetic private address',
  'PRIVATE','ACTIVE','e9b00000-0000-4000-8000-000000000001',
  'e9010000-0000-4000-8000-000000000001',
  'e9010000-0000-4000-8000-000000000001'
);

insert into public.pachanga_venue_pitches(
  id,venue_id,conflict_scope_id,name,slug,modalities,surface,environment,
  has_lighting,status,visibility,minimum_slot_minutes,buffer_minutes,
  operation_id,created_by,updated_by
) values
  (
    'e9b20000-0000-4000-8000-000000000011',
    'e9b20000-0000-4000-8000-000000000001',
    'e9b20000-0000-4000-8000-000000000011','Pitch Alpha','pitch-alpha',
    array['F7']::text[],'ARTIFICIAL_GRASS','OUTDOOR',true,'ACTIVE','PRIVATE',
    60,5,'e9b00000-0000-4000-8000-000000000011',
    'e9010000-0000-4000-8000-000000000001',
    'e9010000-0000-4000-8000-000000000001'
  ),
  (
    'e9b20000-0000-4000-8000-000000000012',
    'e9b20000-0000-4000-8000-000000000001',
    'e9b20000-0000-4000-8000-000000000012','Pitch Beta','pitch-beta',
    array['F7']::text[],'ARTIFICIAL_GRASS','OUTDOOR',true,'ACTIVE','PRIVATE',
    60,5,'e9b00000-0000-4000-8000-000000000012',
    'e9010000-0000-4000-8000-000000000001',
    'e9010000-0000-4000-8000-000000000001'
  );

insert into public.pachanga_venue_availability_templates(
  id,venue_id,pitch_id,weekday,start_local_time,end_local_time,slot_minutes,
  buffer_minutes,valid_from,valid_until,timezone,modalities,capacity,
  visibility,status,operation_id,created_by,updated_by
) values
  (
    'e9b20000-0000-4000-8000-000000000021',
    'e9b20000-0000-4000-8000-000000000001',
    'e9b20000-0000-4000-8000-000000000011',1,'17:00','23:00',60,5,
    '2027-01-01','2027-12-31','Europe/Madrid',array['F7']::text[],1,
    'PRIVATE','ACTIVE','e9b00000-0000-4000-8000-000000000021',
    'e9010000-0000-4000-8000-000000000001',
    'e9010000-0000-4000-8000-000000000001'
  ),
  (
    'e9b20000-0000-4000-8000-000000000022',
    'e9b20000-0000-4000-8000-000000000001',
    'e9b20000-0000-4000-8000-000000000012',1,'17:00','23:00',60,5,
    '2027-01-01','2027-12-31','Europe/Madrid',array['F7']::text[],1,
    'PRIVATE','ACTIVE','e9b00000-0000-4000-8000-000000000022',
    'e9010000-0000-4000-8000-000000000001',
    'e9010000-0000-4000-8000-000000000001'
  );

-- Wave 9B requires the explicit competition Venue capability.
insert into public.pachanga_competition_entitlement_grants(
  organizer_kind,organizer_group_id,capability,grant_source,status,reason,granted_by
) select competitions.organizer_kind,competitions.organizer_group_id,
  'competition_venues','platform_grant','active','Wave 9B synthetic Venue authority',
  'c4010000-0000-4000-8000-000000000001'
from public.pachanga_competitions competitions
where competitions.id='c4200000-0000-4000-8000-000000000001'
on conflict do nothing;
