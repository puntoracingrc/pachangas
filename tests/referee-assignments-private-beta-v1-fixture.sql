-- Deterministic Wave 4 fixture layered on the canonical R4/R5 League graph.
-- The caller owns cleanup through a temporary database or transaction rollback.

\ir competition-discipline-v1-fixture.sql

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('d6010000-0000-4000-8000-000000000001', 'wave4-referee-a@example.test', clock_timestamp(), '{"full_name":"Wave 4 Referee A"}'),
  ('d6010000-0000-4000-8000-000000000002', 'wave4-referee-b@example.test', clock_timestamp(), '{"full_name":"Wave 4 Referee B"}'),
  ('d6010000-0000-4000-8000-000000000003', 'wave4-referee-c@example.test', clock_timestamp(), '{"full_name":"Wave 4 Referee C"}'),
  ('d6010000-0000-4000-8000-000000000004', 'wave4-referee-limited@example.test', clock_timestamp(), '{"full_name":"Wave 4 Limited Referee"}');

insert into public.pachanga_referee_profiles(
  id, user_id, slug, public_display_name_snapshot, bio,
  operational_status, verification_status, visibility, marketplace_status,
  availability_status, available_for_assignments, share_recurring_availability
) values
  ('d6020000-0000-4000-8000-000000000001', 'd6010000-0000-4000-8000-000000000001', 'wave4-referee-a', 'Wave 4 Referee A', 'Fixture referee A', 'active', 'verified', 'private', 'not_listed', 'AVAILABLE', true, true),
  ('d6020000-0000-4000-8000-000000000002', 'd6010000-0000-4000-8000-000000000002', 'wave4-referee-b', 'Wave 4 Referee B', 'Fixture referee B', 'active', 'verified', 'private', 'not_listed', 'AVAILABLE', true, true),
  ('d6020000-0000-4000-8000-000000000003', 'd6010000-0000-4000-8000-000000000003', 'wave4-referee-c', 'Wave 4 Referee C', 'Fixture referee C', 'active', 'verified', 'private', 'not_listed', 'AVAILABLE', true, true),
  ('d6020000-0000-4000-8000-000000000004', 'd6010000-0000-4000-8000-000000000004', 'wave4-referee-limited', 'Wave 4 Limited Referee', 'Fixture referee outside the recurring window', 'active', 'verified', 'private', 'not_listed', 'AVAILABLE', true, true);

insert into public.pachanga_referee_modalities(
  referee_profile_id, modality, active, experience_since_year, public_note
) select profiles.id, 'FOOTBALL_7', true, 2020, 'Wave 4 deterministic fixture'
from public.pachanga_referee_profiles profiles
where profiles.id in (
  'd6020000-0000-4000-8000-000000000001',
  'd6020000-0000-4000-8000-000000000002',
  'd6020000-0000-4000-8000-000000000003',
  'd6020000-0000-4000-8000-000000000004'
);

insert into public.pachanga_referee_service_areas(
  referee_profile_id, country_code, province, municipality, general_area,
  travel_radius_km, status
) select profiles.id, 'ES', 'Barcelona', 'Barcelona', 'Pista', 50, 'active'
from public.pachanga_referee_profiles profiles
where profiles.id in (
  'd6020000-0000-4000-8000-000000000001',
  'd6020000-0000-4000-8000-000000000002',
  'd6020000-0000-4000-8000-000000000003',
  'd6020000-0000-4000-8000-000000000004'
);

-- League fixture dates are Mondays at 20:00 local time. Three referees cover
-- the slot; the limited referee deliberately does not.
insert into public.pachanga_referee_availability_windows(
  referee_profile_id, weekday, start_local_time, end_local_time, timezone,
  public_visible, status
) select profiles.id, 1, '18:00', '23:30', 'Europe/Madrid', true, 'active'
from public.pachanga_referee_profiles profiles
where profiles.id in (
  'd6020000-0000-4000-8000-000000000001',
  'd6020000-0000-4000-8000-000000000002',
  'd6020000-0000-4000-8000-000000000003'
);

insert into public.pachanga_referee_availability_windows(
  referee_profile_id, weekday, start_local_time, end_local_time, timezone,
  public_visible, status
) values (
  'd6020000-0000-4000-8000-000000000004', 1,
  '08:00', '10:00', 'Europe/Madrid', true, 'active'
);

-- A fully bound legacy group match exists only to prove that the old R3 write
-- RPC is rejected by the Wave 4 guard after all of its historical checks pass.
update public.pachanga_groups groups set
  payload = jsonb_set(
    groups.payload,
    '{matches}',
    '[{"id":"wave4-legacy-match","date":"2027-04-05T19:00:00Z","kind":"futbol7"}]'::jsonb,
    true
  ),
  payload_revision = groups.payload_revision + 1
where groups.id = 'c4100000-0000-4000-8000-000000000002';

insert into public.pachanga_match_read_model(
  group_id, match_id, match_state, match_version, configured, lineup_closed,
  finalized, target_players, reserve_limit, source_payload_revision
) values (
  'c4100000-0000-4000-8000-000000000002', 'wave4-legacy-match',
  'published', 1, true, false, false, 14, 2,
  (select payload_revision from public.pachanga_groups
   where id = 'c4100000-0000-4000-8000-000000000002')
);

insert into public.pachanga_canonical_matches(id, status, revision, created_by)
values (
  'd6050000-0000-4000-8000-000000000001', 'active', 1,
  'c4010000-0000-4000-8000-000000000003'
);

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_group_id, source_id,
  relation_kind, binding_status, revision, created_by
) values (
  'd6050000-0000-4000-8000-000000000002',
  'd6050000-0000-4000-8000-000000000001',
  'group_match', 'c4100000-0000-4000-8000-000000000002',
  'wave4-legacy-match', 'manual_verified', 'active', 1,
  'c4010000-0000-4000-8000-000000000003'
);

-- Jornada 4 receives an R4D time change that overlaps Jornada 3. They remain
-- different CanonicalMatches, which makes the referee-level overlap guard the
-- only valid authority while the published fixture remains immutable.
insert into public.pachanga_competition_fixture_changes(
  id, competition_id, canonical_match_id, competition_match_context_id,
  schedule_item_id, rule_revision_id, change_type, status, source_type,
  original_scheduled_start, original_scheduled_end, original_timezone,
  original_venue_label, original_venue_status, creation_operation_id, created_by
) values (
  'd6060000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000001',
  'c4700000-0000-4000-8000-000000000006',
  'c4700000-0000-4000-8000-000000000008',
  'c4700000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000003',
  'TIME_CHANGE', 'active', 'DIRECT_OPERATION',
  '2027-03-22T19:00:00Z', '2027-03-22T20:10:00Z', 'Europe/Madrid',
  'Pista R5', 'CONFIRMED',
  'd6060000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000002'
);
insert into public.pachanga_competition_fixture_change_revisions(
  id, fixture_change_id, version, change_type,
  effective_scheduled_start, effective_scheduled_end, effective_timezone,
  effective_venue_label, effective_venue_status, effective_resource_key,
  public_reason_code, public_summary, operation_id, created_by
) values (
  'd6060000-0000-4000-8000-000000000002',
  'd6060000-0000-4000-8000-000000000001', 1, 'TIME_CHANGE',
  '2027-03-15T19:30:00Z', '2027-03-15T20:40:00Z', 'Europe/Madrid',
  'Pista R5', 'SAVED', 'wave4-overlap-pista',
  'wave4.fixture.time_change', 'Cambio horario determinista para probar solapes',
  'd6060000-0000-4000-8000-000000000004',
  'c4010000-0000-4000-8000-000000000002'
);
update public.pachanga_competition_fixture_changes set
  current_revision_id = 'd6060000-0000-4000-8000-000000000002'
where id = 'd6060000-0000-4000-8000-000000000001';

-- Keep every Wave 4 test inside the existing private League beta. Public
-- discovery remains OFF and no canonical backfill is executed.
update private.pachanga_competition_foundation_settings set
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_public_exception_status_enabled = false,
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = false,
  league_private_beta_public_discovery_enabled = false
where singleton;

update private.pachanga_referee_foundation_settings set
  referee_foundation_enabled = true,
  referee_self_service_enabled = true,
  referee_public_profiles_enabled = true,
  referee_marketplace_enabled = true,
  referee_club_relationships_enabled = true,
  referee_assignments_enabled = false,
  referee_assignment_private_beta_enabled = false
where singleton;
