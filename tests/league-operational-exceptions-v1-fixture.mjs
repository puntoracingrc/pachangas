import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export const r4dIds = Object.freeze({
  awayEntry: "c4200000-0000-4000-8000-000000000012",
  awayOwner: "c4010000-0000-4000-8000-000000000004",
  canonicalMatch: "c4400000-0000-4000-8000-000000000006",
  clubAdmin: "d4010000-0000-4000-8000-000000000014",
  clubOwner: "d4010000-0000-4000-8000-000000000015",
  competition: "c4200000-0000-4000-8000-000000000001",
  context: "c4400000-0000-4000-8000-000000000008",
  director: "c4010000-0000-4000-8000-000000000002",
  homeDelegate: "d4010000-0000-4000-8000-000000000013",
  homeEntry: "c4200000-0000-4000-8000-000000000011",
  homeOwner: "c4010000-0000-4000-8000-000000000003",
  operationsManager: "d4010000-0000-4000-8000-000000000010",
  outsider: "c4010000-0000-4000-8000-000000000007",
  platformAdmin: "d4010000-0000-4000-8000-000000000016",
  platformOwner: "c4010000-0000-4000-8000-000000000001",
  player: "c4010000-0000-4000-8000-000000000005",
  resultManager: "d4010000-0000-4000-8000-000000000012",
  round: "c4400000-0000-4000-8000-000000000003",
  ruleRevision: "c4200000-0000-4000-8000-000000000003",
  scheduleItem: "c4400000-0000-4000-8000-000000000005",
  scheduleManager: "d4010000-0000-4000-8000-000000000011",
  support: "d4010000-0000-4000-8000-000000000017",
  teamAdmin: "d4010000-0000-4000-8000-000000000018",
  viewer: "c4010000-0000-4000-8000-000000000008",
});

export const r4dExceptionPolicy = Object.freeze({
  gracePeriodMinutes: 10,
  maximumMatchDurationMinutes: 120,
  minimumRestHours: 0,
  noShowLoserScore: 0,
  noShowOutcome: "NO_SHOW",
  noShowWinnerScore: 3,
  organizerApprovalRequired: true,
  organizerCanInterveneAfterDeadline: true,
  postponementDeadlinePolicy: "EXPIRE",
  postponementResponseDeadlineHours: 48,
  resumptionEligibilityPolicy: {
    allowOriginalSquad: true,
    allowReplacementForDocumentedInjury: false,
    requireOriginalEligibility: true,
  },
  resumptionPolicy: "SAME_CANONICAL_MATCH",
  stageWindowEnd: "2027-12-31T23:59:59Z",
  stageWindowStart: "2027-01-01T00:00:00Z",
  venuePolicy: {
    allowSavedVenue: true,
    allowTbd: true,
    allowVenueLabel: true,
  },
});

function fixtureWithPolicy() {
  const source = readFileSync(resolve(root, "tests/league-match-operations-v1-fixture.sql"), "utf8");
  const marker = '"operations":{"schedulePolicy":';
  assert.equal(source.split(marker).length - 1, 1, "R4C fixture operations marker changed");
  return source.replace(
    marker,
    `"operations":{"exceptionPolicy":${JSON.stringify(r4dExceptionPolicy)},"schedulePolicy":`,
  );
}

export function leagueOperationalFixtureSql({ enableFlags = true } = {}) {
  const flags = enableFlags ? `
update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_public_calendar_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_public_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_public_exception_status_enabled = true,
  revision = revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = 'c4010000-0000-4000-8000-000000000001',
  updated_at = clock_timestamp()
where singleton;
` : "";

  return `${fixtureWithPolicy()}

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('d4010000-0000-4000-8000-000000000010', 'r4d-operations-manager@example.test', clock_timestamp(), '{"full_name":"Operations manager"}'),
  ('d4010000-0000-4000-8000-000000000011', 'r4d-schedule-manager@example.test', clock_timestamp(), '{"full_name":"Schedule manager"}'),
  ('d4010000-0000-4000-8000-000000000012', 'r4d-result-manager@example.test', clock_timestamp(), '{"full_name":"Result manager"}'),
  ('d4010000-0000-4000-8000-000000000013', 'r4d-home-delegate@example.test', clock_timestamp(), '{"full_name":"Home delegate"}'),
  ('d4010000-0000-4000-8000-000000000014', 'r4d-club-admin@example.test', clock_timestamp(), '{"full_name":"Club admin"}'),
  ('d4010000-0000-4000-8000-000000000015', 'r4d-club-owner@example.test', clock_timestamp(), '{"full_name":"Club owner"}'),
  ('d4010000-0000-4000-8000-000000000016', 'r4d-platform-admin@example.test', clock_timestamp(), '{"full_name":"Platform admin"}'),
  ('d4010000-0000-4000-8000-000000000017', 'r4d-support@example.test', clock_timestamp(), '{"full_name":"Support"}'),
  ('d4010000-0000-4000-8000-000000000018', 'r4d-team-admin@example.test', clock_timestamp(), '{"full_name":"Team admin"}');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('c4100000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000013', 'admin', 'Home delegate'),
  ('c4100000-0000-4000-8000-000000000002', 'd4010000-0000-4000-8000-000000000018', 'admin', 'Team admin');

insert into public.pachanga_competition_team_delegates(
  id, entry_id, user_id, delegate_role, status, valid_from,
  invited_by, accepted_at
) values (
  'd4200000-0000-4000-8000-000000000013',
  'c4200000-0000-4000-8000-000000000011',
  'd4010000-0000-4000-8000-000000000013',
  'PRIMARY_DELEGATE', 'active', clock_timestamp(),
  'c4010000-0000-4000-8000-000000000003', clock_timestamp()
);

insert into public.pachanga_competition_staff_assignments(
  id, competition_id, user_id, staff_role, status, assigned_by
) values
  ('d4200000-0000-4000-8000-000000000010', 'c4200000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000010', 'competition_operations_manager', 'active', 'c4010000-0000-4000-8000-000000000002'),
  ('d4200000-0000-4000-8000-000000000011', 'c4200000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000011', 'competition_schedule_manager', 'active', 'c4010000-0000-4000-8000-000000000002'),
  ('d4200000-0000-4000-8000-000000000012', 'c4200000-0000-4000-8000-000000000001', 'd4010000-0000-4000-8000-000000000012', 'competition_result_manager', 'active', 'c4010000-0000-4000-8000-000000000002');

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source,
  status, reason, granted_by
) values (
  'TEAM', 'c4100000-0000-4000-8000-000000000001',
  'competition_operations', 'platform_grant', 'active',
  'R4D isolated database fixture', 'c4010000-0000-4000-8000-000000000001'
);

insert into public.pachanga_clubs(
  id, name, slug, club_type, visibility, operational_status,
  primary_owner_id, created_by
) values (
  'd4100000-0000-4000-8000-000000000014', 'R4D unrelated club',
  'r4d-unrelated-club', 'FOOTBALL_CLUB', 'private', 'draft',
  'd4010000-0000-4000-8000-000000000015',
  'd4010000-0000-4000-8000-000000000015'
);

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, invited_by, accepted_at
) values
  ('d4100000-0000-4000-8000-000000000014', 'd4010000-0000-4000-8000-000000000015', 'club_owner', 'active', 'd4010000-0000-4000-8000-000000000015', clock_timestamp()),
  ('d4100000-0000-4000-8000-000000000014', 'd4010000-0000-4000-8000-000000000014', 'club_admin', 'active', 'd4010000-0000-4000-8000-000000000015', clock_timestamp());

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('d4010000-0000-4000-8000-000000000016', 'platform_admin', true),
  ('d4010000-0000-4000-8000-000000000017', 'support', true);

${flags}
set constraints all immediate;
`;
}
