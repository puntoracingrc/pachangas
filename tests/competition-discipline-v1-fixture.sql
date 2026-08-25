-- Deterministic R5 fixture layered on the canonical R4C League graph.
-- The caller owns cleanup (transaction rollback or temporary database removal).

\ir league-match-operations-v1-fixture.sql

-- Upgrade only the rollback-bound R5 fixture to the complete current beta
-- bundle. The shared R4C fixture remains valid at its historical migration cut.
update public.pachanga_competition_entitlement_grants set
  program_key = 'LEAGUE_PRIVATE_BETA_V1',
  bundle_id = 'c4b00000-0000-4000-8000-000000000001',
  beta_team_cap = 12,
  reason = 'LEAGUE_PRIVATE_BETA_V1: R5 rollback fixture',
  valid_from = '2026-01-01T00:00:00Z',
  expires_at = '2099-12-31T23:59:59Z'
where organizer_kind = 'TEAM'
  and organizer_group_id = 'c4100000-0000-4000-8000-000000000001';

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  valid_from, expires_at, reason, granted_by,
  program_key, bundle_id, beta_team_cap
) select
  'TEAM', 'c4100000-0000-4000-8000-000000000001', capabilities.capability,
  'platform_grant', 'active', '2026-01-01T00:00:00Z', '2099-12-31T23:59:59Z',
  'LEAGUE_PRIVATE_BETA_V1: R5 rollback fixture',
  'c4010000-0000-4000-8000-000000000001',
  'LEAGUE_PRIVATE_BETA_V1', 'c4b00000-0000-4000-8000-000000000001', 12
from unnest(array[
  'competition_create',
  'competition_staff',
  'competition_rules',
  'competition_categories_manage',
  'competition_entries_manage',
  'competition_rosters_review',
  'competition_operations',
  'competition_discipline_manage',
  'competition_discipline_review',
  'competition_appeals_manage'
]::text[]) capabilities(capability);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values (
  'c4010000-0000-4000-8000-000000000010',
  'r5-home-alternate@example.test', clock_timestamp(),
  '{"full_name":"Home alternate"}'
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (
  'c4100000-0000-4000-8000-000000000002',
  'c4010000-0000-4000-8000-000000000010', 'player', 'Home alternate'
);

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, display_name, phone, position
) values (
  'c4300000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000010',
  'c4100000-0000-4000-8000-000000000002',
  'Home alternate', '', 'Defensa'
);

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
) values (
  'c4200000-0000-4000-8000-000000000021',
  'c4200000-0000-4000-8000-000000000015',
  'c4200000-0000-4000-8000-000000000017',
  'c4200000-0000-4000-8000-000000000011',
  'c4300000-0000-4000-8000-000000000003',
  'c4100000-0000-4000-8000-000000000002',
  'c4010000-0000-4000-8000-000000000010', 'eligible',
  '{"displayName":"Home alternate","position":"DEF"}', 'eligibility.r5_fixture'
);

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  competition_discipline_foundation_enabled = true,
  competition_disciplinary_events_enabled = true,
  competition_disciplinary_counters_enabled = true,
  competition_sanctions_enabled = true,
  competition_sanction_service_enabled = true,
  competition_discipline_appeals_enabled = true,
  competition_public_discipline_enabled = false
where singleton;

insert into public.pachanga_competition_discipline_rule_catalogs(
  rule_revision_id, competition_id, policy_version, card_type_catalog,
  cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
  checksum, created_by
)
select
  'c4200000-0000-4000-8000-000000000003',
  'c4200000-0000-4000-8000-000000000001',
  policy ->> 'policyVersion', policy -> 'cardTypeCatalog',
  policy -> 'cyclePolicy', policy -> 'sanctionPolicy',
  policy -> 'appealPolicy', policy -> 'publicReasonCategories',
  encode(extensions.digest(convert_to(policy::text, 'UTF8'), 'sha256'), 'hex'),
  'c4010000-0000-4000-8000-000000000002'
from (select private.pachanga_competition_discipline_default_policy_v1() policy) source
on conflict (rule_revision_id) do nothing;

insert into public.pachanga_competition_rounds(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, schedule_revision_id, round_number, leg_number,
  display_name, starts_at, ends_at, status, rule_revision_id,
  revision, created_by, published_at
) values
  ('c4500000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4400000-0000-4000-8000-000000000002', 2, 1, 'Jornada 2', '2027-03-08T19:00:00Z', '2027-03-08T21:00:00Z', 'published', 'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002', clock_timestamp()),
  ('c4600000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4400000-0000-4000-8000-000000000002', 3, 1, 'Jornada 3', '2027-03-15T19:00:00Z', '2027-03-15T21:00:00Z', 'published', 'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002', clock_timestamp()),
  ('c4700000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4400000-0000-4000-8000-000000000002', 4, 1, 'Jornada 4', '2027-03-22T19:00:00Z', '2027-03-22T21:00:00Z', 'published', 'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002', clock_timestamp());

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, division_id, competition_group_id,
  starts_at, ends_at, timezone, venue_label, resource_key, status, revision, created_by
) values
  ('c4500000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', '2027-03-08T19:00:00Z', '2027-03-08T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'r5-pista-2', 'assigned', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4600000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', '2027-03-15T19:00:00Z', '2027-03-15T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'r5-pista-3', 'assigned', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4700000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', '2027-03-22T19:00:00Z', '2027-03-22T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'r5-pista-4', 'assigned', 1, 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_canonical_matches(id, status, revision, created_by) values
  ('c4500000-0000-4000-8000-000000000006', 'active', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4600000-0000-4000-8000-000000000006', 'active', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4700000-0000-4000-8000-000000000006', 'active', 1, 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
  pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, status, canonical_match_id,
  competition_match_context_id, revision
) values
  ('c4500000-0000-4000-8000-000000000005', 'c4400000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', repeat('2', 64) || ':1', 1, 'c4500000-0000-4000-8000-000000000004', '2027-03-08T19:00:00Z', '2027-03-08T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'validated', 'c4500000-0000-4000-8000-000000000006', null, 1),
  ('c4600000-0000-4000-8000-000000000005', 'c4400000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', repeat('3', 64) || ':1', 1, 'c4600000-0000-4000-8000-000000000004', '2027-03-15T19:00:00Z', '2027-03-15T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'validated', 'c4600000-0000-4000-8000-000000000006', null, 1),
  ('c4700000-0000-4000-8000-000000000005', 'c4400000-0000-4000-8000-000000000002', 'c4700000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', repeat('4', 64) || ':1', 1, 'c4700000-0000-4000-8000-000000000004', '2027-03-22T19:00:00Z', '2027-03-22T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'validated', 'c4700000-0000-4000-8000-000000000006', null, 1);

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_id, relation_kind,
  binding_status, revision, created_by
) values
  ('c4500000-0000-4000-8000-000000000007', 'c4500000-0000-4000-8000-000000000006', 'competition_generated', 'c4500000-0000-4000-8000-000000000005', 'authoritative_source', 'active', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4600000-0000-4000-8000-000000000007', 'c4600000-0000-4000-8000-000000000006', 'competition_generated', 'c4600000-0000-4000-8000-000000000005', 'authoritative_source', 'active', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4700000-0000-4000-8000-000000000007', 'c4700000-0000-4000-8000-000000000006', 'competition_generated', 'c4700000-0000-4000-8000-000000000005', 'authoritative_source', 'active', 1, 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
  division_id, competition_group_id, rule_revision_id, round_id,
  schedule_item_id, home_entry_id, away_entry_id, slot_id,
  scheduled_start, scheduled_end, timezone, venue_label, venue_status,
  source_kind, status, revision, created_by
) values
  ('c4500000-0000-4000-8000-000000000008', 'c4500000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003', 'c4500000-0000-4000-8000-000000000003', 'c4500000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', 'c4500000-0000-4000-8000-000000000004', '2027-03-08T19:00:00Z', '2027-03-08T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'COMPETITION_GENERATED', 'scheduled', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4600000-0000-4000-8000-000000000008', 'c4600000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', 'c4600000-0000-4000-8000-000000000004', '2027-03-15T19:00:00Z', '2027-03-15T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'COMPETITION_GENERATED', 'scheduled', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4700000-0000-4000-8000-000000000008', 'c4700000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003', 'c4700000-0000-4000-8000-000000000003', 'c4700000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000012', 'c4700000-0000-4000-8000-000000000004', '2027-03-22T19:00:00Z', '2027-03-22T20:10:00Z', 'Europe/Madrid', 'Pista R5', 'CONFIRMED', 'COMPETITION_GENERATED', 'scheduled', 1, 'c4010000-0000-4000-8000-000000000002');

update public.pachanga_competition_schedule_items items set
  competition_match_context_id = source.context_id,
  status = 'published', revision = 2
from (values
  ('c4500000-0000-4000-8000-000000000005'::uuid, 'c4500000-0000-4000-8000-000000000008'::uuid),
  ('c4600000-0000-4000-8000-000000000005'::uuid, 'c4600000-0000-4000-8000-000000000008'::uuid),
  ('c4700000-0000-4000-8000-000000000005'::uuid, 'c4700000-0000-4000-8000-000000000008'::uuid)
) source(item_id, context_id)
where items.id = source.item_id;

-- J1-J3 keep the same player on the submitted sheet so accumulation is real.
-- J4 starts with that player too, allowing the lock-time sanction test.
insert into public.pachanga_competition_match_squads(
  id, canonical_match_id, competition_match_context_id, entry_id,
  roster_id, roster_revision_id, rule_revision_id, side, status,
  revision, created_by, submitted_by, submitted_at
) values
  ('c4800000-0000-4000-8000-000000000011', 'c4400000-0000-4000-8000-000000000006', 'c4400000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 'HOME', 'submitted', 1, 'c4010000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000003', clock_timestamp()),
  ('c4800000-0000-4000-8000-000000000012', 'c4500000-0000-4000-8000-000000000006', 'c4500000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 'HOME', 'submitted', 1, 'c4010000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000003', clock_timestamp()),
  ('c4800000-0000-4000-8000-000000000013', 'c4600000-0000-4000-8000-000000000006', 'c4600000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 'HOME', 'submitted', 1, 'c4010000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000003', clock_timestamp()),
  ('c4800000-0000-4000-8000-000000000014', 'c4700000-0000-4000-8000-000000000006', 'c4700000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 'HOME', 'submitted', 1, 'c4010000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000003', clock_timestamp());

insert into public.pachanga_competition_match_squad_revisions(
  id, squad_id, version, squad_status, roster_revision_id, rule_revision_id,
  member_count, starter_count, substitute_count, captain_player_profile_id,
  member_set_checksum, lineup_checksum, reason, created_by
) values
  ('c4900000-0000-4000-8000-000000000011', 'c4800000-0000-4000-8000-000000000011', 1, 'submitted', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 1, 1, 0, 'c4300000-0000-4000-8000-000000000001', repeat('1', 64), repeat('a', 64), 'R5 J1 submitted squad', 'c4010000-0000-4000-8000-000000000003'),
  ('c4900000-0000-4000-8000-000000000012', 'c4800000-0000-4000-8000-000000000012', 1, 'submitted', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 1, 1, 0, 'c4300000-0000-4000-8000-000000000001', repeat('2', 64), repeat('b', 64), 'R5 J2 submitted squad', 'c4010000-0000-4000-8000-000000000003'),
  ('c4900000-0000-4000-8000-000000000013', 'c4800000-0000-4000-8000-000000000013', 1, 'submitted', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 1, 1, 0, 'c4300000-0000-4000-8000-000000000001', repeat('3', 64), repeat('c', 64), 'R5 J3 submitted squad', 'c4010000-0000-4000-8000-000000000003'),
  ('c4900000-0000-4000-8000-000000000014', 'c4800000-0000-4000-8000-000000000014', 1, 'submitted', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000003', 1, 1, 0, 'c4300000-0000-4000-8000-000000000001', repeat('4', 64), repeat('d', 64), 'R5 J4 sanctioned candidate', 'c4010000-0000-4000-8000-000000000003');

update public.pachanga_competition_match_squads squads set current_revision_id = source.revision_id
from (values
  ('c4800000-0000-4000-8000-000000000011'::uuid, 'c4900000-0000-4000-8000-000000000011'::uuid),
  ('c4800000-0000-4000-8000-000000000012'::uuid, 'c4900000-0000-4000-8000-000000000012'::uuid),
  ('c4800000-0000-4000-8000-000000000013'::uuid, 'c4900000-0000-4000-8000-000000000013'::uuid),
  ('c4800000-0000-4000-8000-000000000014'::uuid, 'c4900000-0000-4000-8000-000000000014'::uuid)
) source(squad_id, revision_id)
where squads.id = source.squad_id;

insert into public.pachanga_competition_match_squad_members(
  id, squad_revision_id, roster_member_id, player_profile_id, member_role,
  shirt_number, position_order, is_captain, public_snapshot
) values
  ('c4a00000-0000-4000-8000-000000000011', 'c4900000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000019', 'c4300000-0000-4000-8000-000000000001', 'STARTER', 9, 1, true, '{"displayName":"Home player"}'),
  ('c4a00000-0000-4000-8000-000000000012', 'c4900000-0000-4000-8000-000000000012', 'c4200000-0000-4000-8000-000000000019', 'c4300000-0000-4000-8000-000000000001', 'STARTER', 9, 1, true, '{"displayName":"Home player"}'),
  ('c4a00000-0000-4000-8000-000000000013', 'c4900000-0000-4000-8000-000000000013', 'c4200000-0000-4000-8000-000000000019', 'c4300000-0000-4000-8000-000000000001', 'STARTER', 9, 1, true, '{"displayName":"Home player"}'),
  ('c4a00000-0000-4000-8000-000000000014', 'c4900000-0000-4000-8000-000000000014', 'c4200000-0000-4000-8000-000000000019', 'c4300000-0000-4000-8000-000000000001', 'STARTER', 9, 1, true, '{"displayName":"Home player"}');
