-- Deterministic Wave 9A fixture layered on the canonical League/R4D/referee graph.
-- All identities and locations are synthetic. The runner destroys the database.

\ir referee-assignments-private-beta-v1-fixture.sql

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('e9010000-0000-4000-8000-000000000001', 'wave9a-club-owner@example.test', clock_timestamp(), '{"full_name":"Wave 9A Club Owner"}'),
  ('e9010000-0000-4000-8000-000000000002', 'wave9a-venue-manager@example.test', clock_timestamp(), '{"full_name":"Wave 9A Venue Manager"}'),
  ('e9010000-0000-4000-8000-000000000003', 'wave9a-booking-manager@example.test', clock_timestamp(), '{"full_name":"Wave 9A Booking Manager"}'),
  ('e9010000-0000-4000-8000-000000000004', 'wave9a-club-viewer@example.test', clock_timestamp(), '{"full_name":"Wave 9A Club Viewer"}'),
  ('e9010000-0000-4000-8000-000000000005', 'wave9a-outsider@example.test', clock_timestamp(), '{"full_name":"Wave 9A Outsider"}');

insert into public.pachanga_clubs(
  id, name, slug, description, club_type, country_code, province,
  municipality, general_area, visibility, operational_status,
  verification_status, partnership_status, primary_owner_id, created_by
) values (
  'e9020000-0000-4000-8000-000000000001',
  'Centre Esportiu Barris IQ', 'centre-esportiu-barris-iq',
  'Synthetic Club used only by the Wave 9A isolated database suite.',
  'SPORTS_CENTER', 'ES', 'Barcelona', 'Barcelona', 'Zona IQ',
  'private', 'active', 'unverified', 'none',
  'e9010000-0000-4000-8000-000000000001',
  'e9010000-0000-4000-8000-000000000001'
);

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, accepted_at, invited_by
) values
  ('e9020000-0000-4000-8000-000000000001', 'e9010000-0000-4000-8000-000000000001', 'club_owner', 'active', clock_timestamp(), 'e9010000-0000-4000-8000-000000000001'),
  ('e9020000-0000-4000-8000-000000000001', 'e9010000-0000-4000-8000-000000000002', 'club_venue_manager', 'active', clock_timestamp(), 'e9010000-0000-4000-8000-000000000001'),
  ('e9020000-0000-4000-8000-000000000001', 'e9010000-0000-4000-8000-000000000003', 'club_reservation_manager', 'active', clock_timestamp(), 'e9010000-0000-4000-8000-000000000001'),
  ('e9020000-0000-4000-8000-000000000001', 'e9010000-0000-4000-8000-000000000004', 'club_viewer', 'active', clock_timestamp(), 'e9010000-0000-4000-8000-000000000001');

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select
  'e9050000-0000-4000-8000-000000000001', revisions.rule_set_id, 2,
  revisions.schema_version, policy.document,
  private.pachanga_competition_rule_checksum_v1(revisions.schema_version, policy.document),
  clock_timestamp(), 'future_only', 'frozen', 1,
  'Wave 9A synthetic referee policy revision',
  'c4010000-0000-4000-8000-000000000002'
from public.pachanga_competition_rule_revisions revisions
cross join lateral (select jsonb_set(
  jsonb_set(
    revisions.rule_document,
    '{operations,refereePolicy}',
    '{
    "usage":"REQUIRED",
    "role":"MAIN_REFEREE",
    "proposerRoles":["competition_owner","competition_director"],
    "acceptanceIsSufficient":false,
    "organizerConfirmationRequired":true,
    "responseDeadlineHours":72,
    "reconfirmAfterScheduleChange":true,
    "modalityRequired":true,
    "serviceAreaRequired":true,
    "priorClubRelationshipRequired":false,
    "replacementAllowed":true,
    "requiredBeforeReady":true,
    "authority":{"reportCards":true,"reportIncidents":true,"observeScore":true},
    "fee":{"mode":"NEGOTIABLE","travelIncluded":false,"publicConsent":false,"paymentProcessing":false}
    }'::jsonb,
    true
  ),
  '{operations,exceptionPolicy}',
  '{
    "postponementResponseDeadlineHours":48,
    "postponementDeadlinePolicy":"EXPIRE",
    "organizerApprovalRequired":true,
    "organizerCanInterveneAfterDeadline":true,
    "gracePeriodMinutes":10,
    "minimumRestHours":0,
    "maximumMatchDurationMinutes":120,
    "noShowOutcome":"NO_SHOW",
    "noShowWinnerScore":3,
    "noShowLoserScore":0,
    "resumptionPolicy":"SAME_CANONICAL_MATCH",
    "stageWindowStart":"2027-01-01T00:00:00Z",
    "stageWindowEnd":"2027-12-31T23:59:59Z",
    "venuePolicy":{"allowSavedVenue":true,"allowVenueLabel":true,"allowTbd":true},
    "resumptionEligibilityPolicy":{"allowOriginalSquad":true,"allowReplacementForDocumentedInjury":false,"requireOriginalEligibility":true}
  }'::jsonb,
  true
) document) policy
where revisions.id = 'c4200000-0000-4000-8000-000000000003';

-- A self-contained published schedule keeps the inherited R4/R5 history
-- immutable while exercising Venue binding and R4D against real authorities.
insert into public.pachanga_competition_schedule_plans(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, rule_revision_id, legs, entry_count, status,
  revision, created_by
) values (
  'e9070000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007',
  null, 'e9050000-0000-4000-8000-000000000001',
  1, 2, 'draft', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_schedule_revisions(
  id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
  input_checksum, rule_revision_id, entry_snapshot_checksum,
  slot_snapshot_checksum, constraint_snapshot_checksum,
  preference_snapshot_checksum, entry_order, quality_score, validation_status,
  generated_by, validated_by, validated_at, published_by, published_at, revision
) values (
  'e9070000-0000-4000-8000-000000000002', 'e9070000-0000-4000-8000-000000000001',
  1, 'generated', 'published', 'league-round-robin-v1', 'wave9a-venue-r4d',
  repeat('1',64), 'e9050000-0000-4000-8000-000000000001', repeat('2',64),
  repeat('3',64), repeat('4',64), repeat('5',64),
  '["c4200000-0000-4000-8000-000000000011","c4200000-0000-4000-8000-000000000012"]',
  100, 'VALID', 'c4010000-0000-4000-8000-000000000002',
  'c4010000-0000-4000-8000-000000000002', clock_timestamp(),
  'c4010000-0000-4000-8000-000000000002', clock_timestamp(), 1
);

insert into public.pachanga_competition_rounds(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, schedule_revision_id, round_number, leg_number,
  display_name, starts_at, ends_at, status, rule_revision_id,
  revision, created_by, published_at
) values (
  'e9070000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007',
  null, 'e9070000-0000-4000-8000-000000000002',
  3, 1, 'Jornada Venue', '2027-05-17T18:00:00Z', '2027-05-17T20:00:00Z',
  'published', 'e9050000-0000-4000-8000-000000000001', 1,
  'c4010000-0000-4000-8000-000000000002', clock_timestamp()
);

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, division_id, competition_group_id,
  starts_at, ends_at, timezone, venue_label, resource_key, status, revision, created_by
) values (
  'e9070000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000007', null,
  '2027-05-17T18:00:00Z', '2027-05-17T19:10:00Z', 'Europe/Madrid',
  'Venue TBD', 'wave9a-venue-slot', 'assigned', 1,
  'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
  pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, status, revision
) values (
  'e9070000-0000-4000-8000-000000000005', 'e9070000-0000-4000-8000-000000000002',
  'e9070000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000011',
  'c4200000-0000-4000-8000-000000000012', repeat('9',64) || ':1', 1,
  'e9070000-0000-4000-8000-000000000004', '2027-05-17T18:00:00Z',
  '2027-05-17T19:10:00Z', 'Europe/Madrid', 'Venue TBD', 'TBD', 'validated', 1
);

insert into public.pachanga_canonical_matches(id, status, revision, created_by)
values (
  'e9070000-0000-4000-8000-000000000006', 'active', 1,
  'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_id, relation_kind,
  binding_status, revision, created_by
) values (
  'e9070000-0000-4000-8000-000000000007',
  'e9070000-0000-4000-8000-000000000006', 'competition_generated',
  'e9070000-0000-4000-8000-000000000005', 'authoritative_source',
  'active', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
  division_id, competition_group_id, rule_revision_id, round_id,
  schedule_item_id, home_entry_id, away_entry_id, slot_id,
  scheduled_start, scheduled_end, timezone, venue_label, venue_status,
  source_kind, status, revision, created_by
) values (
  'e9070000-0000-4000-8000-000000000008', 'e9070000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004',
  'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000007', null,
  'e9050000-0000-4000-8000-000000000001', 'e9070000-0000-4000-8000-000000000003',
  'e9070000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000011',
  'c4200000-0000-4000-8000-000000000012', 'e9070000-0000-4000-8000-000000000004',
  '2027-05-17T18:00:00Z', '2027-05-17T19:10:00Z', 'Europe/Madrid',
  'Venue TBD', 'TBD', 'COMPETITION_GENERATED', 'scheduled', 1,
  'c4010000-0000-4000-8000-000000000002'
);

update public.pachanga_competition_schedule_items set
  canonical_match_id = 'e9070000-0000-4000-8000-000000000006',
  competition_match_context_id = 'e9070000-0000-4000-8000-000000000008',
  status = 'published', revision = 2
where id = 'e9070000-0000-4000-8000-000000000005';

update public.pachanga_competition_schedule_plans set
  current_revision_id = 'e9070000-0000-4000-8000-000000000002',
  status = 'published', published_at = clock_timestamp(), revision = 2
where id = 'e9070000-0000-4000-8000-000000000001';

update private.pachanga_referee_foundation_settings
set referee_assignment_private_beta_enabled = true,
    referee_assignments_enabled = true,
    revision = revision + 1
where singleton;
