-- Minimal published R4A/R4B League graph for isolated R4C database tests.
-- The caller owns the surrounding transaction and must roll it back.

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('c4010000-0000-4000-8000-000000000001', 'r4c-platform@example.test', clock_timestamp(), '{"full_name":"Platform"}'),
  ('c4010000-0000-4000-8000-000000000002', 'r4c-director@example.test', clock_timestamp(), '{"full_name":"Director"}'),
  ('c4010000-0000-4000-8000-000000000003', 'r4c-home-owner@example.test', clock_timestamp(), '{"full_name":"Home owner"}'),
  ('c4010000-0000-4000-8000-000000000004', 'r4c-away-owner@example.test', clock_timestamp(), '{"full_name":"Away owner"}'),
  ('c4010000-0000-4000-8000-000000000005', 'r4c-home-player@example.test', clock_timestamp(), '{"full_name":"Home player"}'),
  ('c4010000-0000-4000-8000-000000000006', 'r4c-away-player@example.test', clock_timestamp(), '{"full_name":"Away player"}'),
  ('c4010000-0000-4000-8000-000000000007', 'r4c-outsider@example.test', clock_timestamp(), '{"full_name":"Outsider"}'),
  ('c4010000-0000-4000-8000-000000000008', 'r4c-viewer@example.test', clock_timestamp(), '{"full_name":"Viewer"}'),
  ('c4010000-0000-4000-8000-000000000009', 'r4c-independent-director@example.test', clock_timestamp(), '{"full_name":"Independent director"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('c4010000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision) values
  ('c4100000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000002', 'R4C Organizer', 'R4CORG1', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('c4100000-0000-4000-8000-000000000002', 'c4010000-0000-4000-8000-000000000003', 'R4C Local', 'R4CHOME', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('c4100000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000004', 'R4C Visitante', 'R4CAWAY', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('c4100000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000002', 'owner', 'Director'),
  ('c4100000-0000-4000-8000-000000000002', 'c4010000-0000-4000-8000-000000000003', 'owner', 'Home owner'),
  ('c4100000-0000-4000-8000-000000000002', 'c4010000-0000-4000-8000-000000000005', 'player', 'Home player'),
  ('c4100000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000004', 'owner', 'Away owner'),
  ('c4100000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000006', 'player', 'Away player');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, display_name, phone, position
) values
  ('c4300000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000005', 'c4100000-0000-4000-8000-000000000002', 'Home player', '', 'Delantero'),
  ('c4300000-0000-4000-8000-000000000002', 'c4010000-0000-4000-8000-000000000006', 'c4100000-0000-4000-8000-000000000003', 'Away player', '', 'Delantero');

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  'c4200000-0000-4000-8000-000000000001', 'TEAM', 'c4100000-0000-4000-8000-000000000001',
  'R4C League 2027', 'r4c-qa-league-2027', 'LEAGUE', 'public', 'draft',
  'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  reason, granted_by
) values
  ('TEAM', 'c4100000-0000-4000-8000-000000000001', 'competition_manage', 'platform_grant', 'active', 'R4C DB fixture', 'c4010000-0000-4000-8000-000000000001'),
  ('TEAM', 'c4100000-0000-4000-8000-000000000001', 'competition_schedule', 'platform_grant', 'active', 'R4C DB fixture', 'c4010000-0000-4000-8000-000000000001'),
  ('TEAM', 'c4100000-0000-4000-8000-000000000001', 'competition_results', 'platform_grant', 'active', 'R4C DB fixture', 'c4010000-0000-4000-8000-000000000001'),
  ('TEAM', 'c4100000-0000-4000-8000-000000000001', 'competition_standings', 'platform_grant', 'active', 'R4C DB fixture', 'c4010000-0000-4000-8000-000000000001');

insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values ('c4200000-0000-4000-8000-000000000002', 'c4200000-0000-4000-8000-000000000001', 'R4C Rules', 'active', 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select 'c4200000-0000-4000-8000-000000000003',
  'c4200000-0000-4000-8000-000000000002', 1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'frozen', 1, 'R4C deterministic DB rules',
  'c4010000-0000-4000-8000-000000000002'
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{
    "rosterPolicy":{"minimumSize":1,"maximumSize":30,"closeRequiresApprovedRosters":true},
    "matchSheetPolicy":{"squadMin":1,"squadMax":3,"starterMin":1,"starterMax":1,"substituteMax":2}
  },
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
  "operations":{"schedulePolicy":{"format":"ROUND_ROBIN","legs":1,"matchDurationMinutes":70,"requiredBufferMinutes":10,"minimumRestMinutes":0,"homeAwayPolicy":"BALANCED","venueRequired":false,"maximumHomeAwayStreak":3,"hardHomeAwayStreak":false,"windowStartsAt":"2027-01-01T00:00:00Z","windowEndsAt":"2027-12-31T23:59:59Z","rosterStatuses":["approved","locked"],"softPreferenceWeights":{"day":60,"time":30,"homeAway":10}}},
  "results":{
    "scoringPolicy":{"pointsForWin":3,"pointsForDraw":1,"pointsForLoss":0},
    "tieBreakCriteria":["POINTS","GOAL_DIFFERENCE","GOALS_FOR","WINS","HEAD_TO_HEAD_POINTS","HEAD_TO_HEAD_GOAL_DIFFERENCE","HEAD_TO_HEAD_GOALS_FOR"],
    "scorerDetailPolicy":"OPTIONAL",
    "allowUnknownScorer":false,
    "confirmationPolicy":{"mode":"BILATERAL","responseDeadlineHours":48,"autoOfficialAfterConfirmation":true},
    "standingsPolicy":{"allowSharedPositions":true},
    "publicationPolicy":{"resultsPublic":true,"standingsPublic":true}
  },
  "discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb)) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_closed_at,
  registration_rule_revision_id, revision, created_by
) values (
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001',
  'Edition 2027', '2027', '2027-01-01', '2027-12-31', 'scheduled',
  'c4200000-0000-4000-8000-000000000003', 'CLOSED', clock_timestamp(),
  'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
) values (
  'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000004',
  'Senior', 'senior', 'FOOTBALL_7', 'public', 'active',
  'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
) values (
  'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000004',
  'Liga regular', 'LEAGUE_STAGE', 0, false, 'draft',
  'c4200000-0000-4000-8000-000000000003', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_divisions(
  id, stage_id, name, division_order, level_label, status, created_by
) values (
  'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000006',
  'División 1', 0, 'Open', 'draft', 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_groups(
  id, stage_id, division_id, name, group_order, status, created_by
) values (
  'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000007', 'Grupo A', 0, 'draft',
  'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
) values
  ('c4200000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000002', 'competition_director', 'active', 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000009', 'competition_director', 'active', 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000001', 'c4010000-0000-4000-8000-000000000008', 'viewer', 'active', 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source, status,
  rule_revision_id, accepted_by, accepted_at, reason_code, created_by
) values
  ('c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4100000-0000-4000-8000-000000000002', 'ORGANIZER_INVITATION', 'accepted', 'c4200000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000002', clock_timestamp(), 'r4c.fixture.accepted', 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000012', 'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005', 'c4100000-0000-4000-8000-000000000003', 'ORGANIZER_INVITATION', 'accepted', 'c4200000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000002', clock_timestamp(), 'r4c.fixture.accepted', 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_stage_memberships(
  id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
  status, reason, assigned_by
) values
  ('c4200000-0000-4000-8000-000000000013', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003', 'active', 'R4C fixture membership', 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000014', 'c4200000-0000-4000-8000-000000000012', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003', 'active', 'R4C fixture membership', 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_rosters(
  id, entry_id, category_id, rule_revision_id, status, revision, created_by
) values
  ('c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000003', 'locked', 1, 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000016', 'c4200000-0000-4000-8000-000000000012', 'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000003', 'locked', 1, 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_roster_revisions(
  id, roster_id, revision_number, roster_status, rule_revision_id, member_count,
  eligibility_summary, member_set_checksum, reason, created_by
) values
  ('c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000015', 1, 'locked', 'c4200000-0000-4000-8000-000000000003', 1, '{"eligible":1,"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}', repeat('1', 64), 'R4C locked home roster', 'c4010000-0000-4000-8000-000000000002'),
  ('c4200000-0000-4000-8000-000000000018', 'c4200000-0000-4000-8000-000000000016', 1, 'locked', 'c4200000-0000-4000-8000-000000000003', 1, '{"eligible":1,"pending":0,"reviewRequired":0,"ineligible":0,"expired":0}', repeat('2', 64), 'R4C locked away roster', 'c4010000-0000-4000-8000-000000000002');

update public.pachanga_competition_rosters set current_revision_id = 'c4200000-0000-4000-8000-000000000017'
where id = 'c4200000-0000-4000-8000-000000000015';
update public.pachanga_competition_rosters set current_revision_id = 'c4200000-0000-4000-8000-000000000018'
where id = 'c4200000-0000-4000-8000-000000000016';

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
) values
  ('c4200000-0000-4000-8000-000000000019', 'c4200000-0000-4000-8000-000000000015', 'c4200000-0000-4000-8000-000000000017', 'c4200000-0000-4000-8000-000000000011', 'c4300000-0000-4000-8000-000000000001', 'c4100000-0000-4000-8000-000000000002', 'c4010000-0000-4000-8000-000000000005', 'eligible', '{"displayName":"Home player","position":"DEL"}', 'eligibility.fixture'),
  ('c4200000-0000-4000-8000-000000000020', 'c4200000-0000-4000-8000-000000000016', 'c4200000-0000-4000-8000-000000000018', 'c4200000-0000-4000-8000-000000000012', 'c4300000-0000-4000-8000-000000000002', 'c4100000-0000-4000-8000-000000000003', 'c4010000-0000-4000-8000-000000000006', 'eligible', '{"displayName":"Away player","position":"DEL"}', 'eligibility.fixture');

insert into public.pachanga_competition_schedule_plans(
  id, competition_id, edition_id, category_id, stage_id, division_id,
  competition_group_id, rule_revision_id, legs, entry_count, status,
  revision, created_by
) values (
  'c4400000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007',
  'c4200000-0000-4000-8000-000000000008', 'c4200000-0000-4000-8000-000000000003',
  1, 2, 'draft', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_schedule_revisions(
  id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
  input_checksum, rule_revision_id, entry_snapshot_checksum,
  slot_snapshot_checksum, constraint_snapshot_checksum,
  preference_snapshot_checksum, entry_order, quality_score, validation_status,
  generated_by, validated_by, validated_at, published_by, published_at, revision
) values (
  'c4400000-0000-4000-8000-000000000002', 'c4400000-0000-4000-8000-000000000001',
  1, 'generated', 'published', 'league-round-robin-v1', 'r4c-db-fixture',
  repeat('a', 64), 'c4200000-0000-4000-8000-000000000003', repeat('b', 64),
  repeat('c', 64), repeat('d', 64), repeat('e', 64),
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
  'c4400000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007',
  'c4200000-0000-4000-8000-000000000008', 'c4400000-0000-4000-8000-000000000002',
  1, 1, 'Jornada 1', '2027-03-01T19:00:00Z', '2027-03-01T21:00:00Z',
  'published', 'c4200000-0000-4000-8000-000000000003', 1,
  'c4010000-0000-4000-8000-000000000002', clock_timestamp()
);

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, division_id, competition_group_id,
  starts_at, ends_at, timezone, venue_label, resource_key, status, revision, created_by
) values (
  'c4400000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004', 'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008',
  '2027-03-01T19:00:00Z', '2027-03-01T20:10:00Z', 'Europe/Madrid',
  'Pista R4C', 'r4c-pista-1', 'assigned', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
  pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, status, revision
) values (
  'c4400000-0000-4000-8000-000000000005', 'c4400000-0000-4000-8000-000000000002',
  'c4400000-0000-4000-8000-000000000003', 'c4200000-0000-4000-8000-000000000011',
  'c4200000-0000-4000-8000-000000000012', repeat('f', 64) || ':1', 1,
  'c4400000-0000-4000-8000-000000000004', '2027-03-01T19:00:00Z',
  '2027-03-01T20:10:00Z', 'Europe/Madrid', 'Pista R4C', 'CONFIRMED', 'validated', 1
);

insert into public.pachanga_canonical_matches(id, status, revision, created_by)
values ('c4400000-0000-4000-8000-000000000006', 'active', 1, 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_id, relation_kind,
  binding_status, revision, created_by
) values (
  'c4400000-0000-4000-8000-000000000007', 'c4400000-0000-4000-8000-000000000006',
  'competition_generated', 'c4400000-0000-4000-8000-000000000005',
  'authoritative_source', 'active', 1, 'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
  division_id, competition_group_id, rule_revision_id, round_id,
  schedule_item_id, home_entry_id, away_entry_id, slot_id,
  scheduled_start, scheduled_end, timezone, venue_label, venue_status,
  source_kind, status, revision, created_by
) values (
  'c4400000-0000-4000-8000-000000000008', 'c4400000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000004',
  'c4200000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008',
  'c4200000-0000-4000-8000-000000000003', 'c4400000-0000-4000-8000-000000000003',
  'c4400000-0000-4000-8000-000000000005', 'c4200000-0000-4000-8000-000000000011',
  'c4200000-0000-4000-8000-000000000012', 'c4400000-0000-4000-8000-000000000004',
  '2027-03-01T19:00:00Z', '2027-03-01T20:10:00Z', 'Europe/Madrid', 'Pista R4C',
  'CONFIRMED', 'COMPETITION_GENERATED', 'scheduled', 1,
  'c4010000-0000-4000-8000-000000000002'
);

update public.pachanga_competition_schedule_items set
  canonical_match_id = 'c4400000-0000-4000-8000-000000000006',
  competition_match_context_id = 'c4400000-0000-4000-8000-000000000008',
  status = 'published', revision = 2
where id = 'c4400000-0000-4000-8000-000000000005';

update public.pachanga_competition_schedule_plans set
  current_revision_id = 'c4400000-0000-4000-8000-000000000002',
  status = 'published', published_at = clock_timestamp(), revision = 2
where id = 'c4400000-0000-4000-8000-000000000001';
