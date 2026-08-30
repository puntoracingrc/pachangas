import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createClient } from "@supabase/supabase-js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const productionRef = "qonbngfrnrqgmxbdfbea";
const confirmation = "SYNTHETIC_SEASON_EPHEMERAL_ONLY";
const localMigrationVersions = readdirSync(resolve(root, "supabase/migrations"))
  .map((filename) => filename.match(/^(\d+)_.*\.sql$/)?.[1])
  .filter(Boolean)
  .sort();
const env = {
  confirmation: process.env.SYNTHETIC_SEASON_CONFIRM,
  databaseUrl: process.env.SYNTHETIC_SEASON_STAGING_DATABASE_URL,
  projectRef: process.env.SYNTHETIC_SEASON_STAGING_PROJECT_REF,
  publishableKey: process.env.SYNTHETIC_SEASON_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.SYNTHETIC_SEASON_STAGING_SERVICE_ROLE_KEY,
  url: process.env.SYNTHETIC_SEASON_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (!value) throw new Error(`SYNTHETIC_SEASON_STAGING_${key.toUpperCase()}_REQUIRED`);
}

const apiRef = new URL(env.url).hostname.split(".")[0];
const databaseIdentity = decodeURIComponent(new URL(env.databaseUrl).username);
if (
  env.confirmation !== confirmation
  || apiRef !== env.projectRef
  || apiRef === productionRef
  || databaseIdentity.includes(productionRef)
) throw new Error("SYNTHETIC_SEASON_STAGING_PRODUCTION_TARGET_FORBIDDEN");

const runId = randomUUID().slice(0, 8);
const ownerId = "64010000-0000-4000-8000-000000000001";
const ownerEmail = "demo-tournament-team-1@example.test";
const ownerPassword = `W8c-${randomUUID()}-Qa!`;
const clients = [];
const channels = [];
let currentStage = "preflight";

function client(key = env.publishableKey) {
  const value = createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 40 } },
  });
  clients.push(value);
  return value;
}

const fixtureAdmin = client(env.serviceRoleKey);

function redact(value) {
  return String(value)
    .replaceAll(env.databaseUrl, "[DATABASE_URL_REDACTED]")
    .replaceAll(env.serviceRoleKey, "[SERVICE_ROLE_REDACTED]");
}

function psql(args, label, input) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", env.databaseUrl, ...args,
  ], {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const safeTail = redact(`${result.stdout ?? ""}${result.stderr ?? ""}`)
      .trim()
      .slice(-12_000);
    throw new Error(`${label} failed (${result.status}):\n${safeTail}`);
  }
  return (result.stdout ?? "").trim();
}

function enterStage(stage) {
  currentStage = stage;
  process.stdout.write(`${JSON.stringify({ stage, status: "START" })}\n`);
}

function passStage(stage) {
  process.stdout.write(`${JSON.stringify({ stage, status: "PASS" })}\n`);
}

function queryJson(sql, label) {
  return JSON.parse(psql(["-At", "-c", sql], label));
}

function replaceExpected(source, from, to, count, label) {
  assert.equal(source.split(from).length - 1, count, `W8C_STAGING_MARKER_DRIFT:${label}`);
  return source.replaceAll(from, to);
}

function expectMarker(source, marker, count, label) {
  assert.equal(source.split(marker).length - 1, count, `W8C_STAGING_MARKER_DRIFT:${label}`);
}

function tournamentFoundationSql() {
  let source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-tournament-operations.sql"),
    "utf8",
  );
  source = replaceExpected(source, "generate_series(1, 16) team_number", "generate_series(1, 12) team_number", 3, "tournament-team-series");
  source = replaceExpected(
    source,
    "from generate_series(1, 12) team_number;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    "from generate_series(1, 12) team_number\non conflict (id) do nothing;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    1,
    "precreated-auth-owner",
  );
  source = replaceExpected(
    source,
    "  (12, 'Nexe Granollers'),\n  (13, 'Línia Cerdanyola'),\n  (14, 'Vector Sant Cugat'),\n  (15, 'Ronda Mollet'),\n  (16, 'Taller Barberà')",
    "  (12, 'Nexe Granollers')",
    1,
    "twelve-team-catalog",
  );
  source = replaceExpected(source, "generate_series(1, 4) club_number", "generate_series(1, 3) club_number", 3, "three-clubs");
  source = replaceExpected(source, "participantCap\":16", "participantCap\":12", 3, "participant-cap");
  source = replaceExpected(source, "for team_number in 1..16 loop", "for team_number in 1..12 loop", 1, "participant-loop");
  source = replaceExpected(source, "for pot_number in 1..4 loop", "for pot_number in 1..3 loop", 1, "three-pots");
  source = replaceExpected(source, "accepted_participants=16", "accepted_participants=12", 1, "foundation-proof");
  return source;
}

function refereeFixtureSql() {
  const source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-referee-assignment-operations.sql"),
    "utf8",
  );
  const boundary = "do $demo_assignments$";
  const boundaryIndex = source.indexOf(boundary);
  assert.notEqual(boundaryIndex, -1, "W8C_STAGING_REFEREE_BOUNDARY_DRIFT");
  let refereeOnly = source.slice(0, boundaryIndex);
  refereeOnly = replaceExpected(
    refereeOnly,
    "e4010000-0000-4000-8000-000000000001",
    "64010000-0000-4000-8000-000000000090",
    1,
    "referee-platform-actor",
  );
  refereeOnly = replaceExpected(refereeOnly, "for value in 1..8 loop", "for value in 1..6 loop", 1, "six-referees");
  return `
\\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.demo_v2_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;
${refereeOnly}
commit;
`;
}

function tournamentGroupStageSql() {
  let source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-tournament-group-stage-operations.sql"),
    "utf8",
  );
  source = replaceExpected(source, "generate_series(1, 16) team_number", "generate_series(1, 12) team_number", 3, "group-team-series");
  source = replaceExpected(source, "generate_series(1, 8) player_number", "generate_series(1, 10) player_number", 3, "ten-player-series");
  source = replaceExpected(source, "for player_number in 1..8 loop", "for player_number in 1..10 loop", 1, "ten-player-roster");
  source = replaceExpected(source, "generate_series(1, 8) candidates(player_number)", "generate_series(1, 10) candidates(player_number)", 2, "ten-player-squads");
  source = replaceExpected(source, "% 8);", "% 6);", 1, "six-referee-rotation");
  source = replaceExpected(source, "'fixtureCount', 24", "'fixtureCount', 12", 1, "public-fixture-count");
  source = replaceExpected(source, "<> 16\n     or (public_snapshot ->> 'scheduledMatches')::integer <> 8\n     or jsonb_array_length(public_snapshot -> 'standings') <> 16\n     or jsonb_array_length(public_snapshot -> 'discipline') <> 4", "<> 8\n     or (public_snapshot ->> 'scheduledMatches')::integer <> 4\n     or jsonb_array_length(public_snapshot -> 'standings') <> 12\n     or jsonb_array_length(public_snapshot -> 'discipline') <> 2", 1, "public-proof-counts");
  source = replaceExpected(source, "<> 24\n     or (final_proof ->> 'officialMatches')::integer <> 24", "<> 12\n     or (final_proof ->> 'officialMatches')::integer <> 12", 1, "final-group-counts");
  source = replaceExpected(source, "(final_proof ->> 'eliminated')::integer <> 8", "(final_proof ->> 'eliminated')::integer <> 4", 1, "eliminated-count");
  source = replaceExpected(source, "if match_row.ordinal = 11 then", "if match_row.ordinal = 5 then", 1, "reduced-suspension-scenario");
  source = replaceExpected(source, "if match_row.ordinal = 14 then", "if match_row.ordinal = 6 then", 1, "reduced-dispute-scenario");
  expectMarker(source, "generate_series(1, 6) slot_number", 1, "three-round-rest-safe-slots");
  return source;
}

function tournamentKnockoutSql() {
  let source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-tournament-knockout-operations.sql"),
    "utf8",
  );
  for (const [from, to, count, label] of [
    ["DW00004", "DW00005", 1, "discipline-source-team"],
    ["demo-world-v2-5-player-profile-4-1", "demo-world-v2-5-player-profile-5-1", 4, "discipline-source-player"],
    ["knockout-carry-red-team-4", "knockout-carry-red-team-5", 2, "discipline-event-operation"],
    ["knockout-carry-sanction-team-4", "knockout-carry-sanction-team-5", 1, "discipline-sanction-operation"],
    ["'teamNumber', 4", "'teamNumber', 5", 1, "discipline-proof-team"],
    ["'playerLabel', 'Jugador Copa 4.1'", "'playerLabel', 'Jugador Copa 5.1'", 1, "discipline-proof-player"],
  ]) {
    source = replaceExpected(source, from, to, count, label);
  }
  for (const [from, to, label] of [
    ["demo-world-v2-referee-profile-6", "demo-world-v2-referee-profile-5", "semifinal-original-profile"],
    ["demo-world-v2-referee-user-6", "demo-world-v2-referee-user-5", "semifinal-original-user"],
    ["demo-world-v2-referee-profile-8", "demo-world-v2-referee-profile-6", "semifinal-replacement-profile"],
    ["demo-world-v2-referee-user-8", "demo-world-v2-referee-user-6", "semifinal-replacement-user"],
    ["demo-world-v2-referee-profile-7", "demo-world-v2-referee-profile-4", "final-profile"],
    ["demo-world-v2-referee-user-7", "demo-world-v2-referee-user-4", "final-user"],
    ["replacementRefereeNumber', 8", "replacementRefereeNumber', 6", "replacement-proof"],
    ["'refereeNumber', 7", "'refereeNumber', 4", "final-proof"],
  ]) source = replaceExpected(source, from, to, 1, label);
  return source;
}

const prerequisiteFlagsSql = `
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
update private.pachanga_competition_foundation_settings settings set
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
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = true,
  competition_discipline_foundation_enabled = true,
  competition_disciplinary_events_enabled = true,
  competition_disciplinary_counters_enabled = true,
  competition_sanctions_enabled = true,
  competition_sanction_service_enabled = true,
  competition_discipline_appeals_enabled = true,
  league_public_registration_enabled = false,
  league_public_calendar_enabled = false,
  league_public_standings_enabled = false,
  league_public_exception_status_enabled = false,
  league_private_beta_public_discovery_enabled = false,
  competition_public_discipline_enabled = false,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '64010000-0000-4000-8000-000000000090',
  updated_at = clock_timestamp()
where settings.singleton;
commit;
`;

const leagueFixtureSql = String.raw`
\set ON_ERROR_STOP on
set lock_timeout = '5s';
set statement_timeout = '240s';
begin;

create or replace function pg_temp.wave8c_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.wave8c_schedule_command(
  operation_key text,
  aggregate_id uuid,
  expected_revision bigint,
  action_name text,
  action_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.wave8c_actor('64010000-0000-4000-8000-000000000011');
  return public.command_pachanga_league_scheduling_v1(
    md5('wave8c-staging-league:' || operation_key)::uuid,
    aggregate_id,
    expected_revision,
    action_name,
    action_payload,
    '{"clientVersion":"wave8c-staging","serviceWorkerVersion":"wave8c-staging","installedMode":"standalone","surface":"synthetic-season-staging"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.wave8c_match_command(
  context_id uuid,
  actor_id uuid,
  operation_key text,
  action_name text,
  action_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select contexts.revision into current_revision
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = context_id;
  perform pg_temp.wave8c_actor(actor_id);
  return public.command_pachanga_league_match_operations_v1(
    md5('wave8c-staging-league-result:' || context_id || ':' || operation_key)::uuid,
    context_id,
    current_revision,
    action_name,
    action_payload,
    '{"clientVersion":"wave8c-staging","serviceWorkerVersion":"wave8c-staging","installedMode":"standalone","surface":"synthetic-season-staging"}'::jsonb
  );
end;
$$;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  '65040000-0000-4000-8000-000000000001', 'TEAM',
  '64020000-0000-4000-8000-000000000012', 'Wave 8C Staging League',
  'wave8c-staging-league', 'LEAGUE', 'private', 'draft',
  '64010000-0000-4000-8000-000000000012'
);

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  valid_from, expires_at, reason, granted_by,
  program_key, bundle_id, beta_team_cap
)
select
  'TEAM', '64020000-0000-4000-8000-000000000012', capabilities.capability,
  'platform_grant', 'active', statement_timestamp() - interval '1 minute',
  statement_timestamp() + interval '30 days',
  'LEAGUE_PRIVATE_BETA_V1: Wave 8C ephemeral staging',
  '64010000-0000-4000-8000-000000000090',
  'LEAGUE_PRIVATE_BETA_V1', '650c0000-0000-4000-8000-000000000001', 12
from unnest(private.pachanga_league_private_beta_capabilities_v1()) capabilities(capability);

insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values ('65050000-0000-4000-8000-000000000001', '65040000-0000-4000-8000-000000000001', 'Wave 8C rules', 'active', '64010000-0000-4000-8000-000000000012');

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select '65060000-0000-4000-8000-000000000001',
  '65050000-0000-4000-8000-000000000001', 1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'frozen', 1, 'Wave 8C double round robin',
  '64010000-0000-4000-8000-000000000012'
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{"rosterPolicy":{"minimumSize":10,"maximumSize":10,"closeRequiresApprovedRosters":true},"matchSheetPolicy":{"squadMin":1,"squadMax":10,"starterMin":1,"starterMax":7,"substituteMax":9}},
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
  "operations":{"schedulePolicy":{"format":"ROUND_ROBIN","legs":2,"matchDurationMinutes":70,"requiredBufferMinutes":10,"minimumRestMinutes":0,"homeAwayPolicy":"MIRRORED_SECOND_LEG","venueRequired":false,"maximumHomeAwayStreak":3,"hardHomeAwayStreak":false,"windowStartsAt":"2027-01-01T00:00:00Z","windowEndsAt":"2027-04-30T23:59:59Z","rosterStatuses":["approved","locked"],"softPreferenceWeights":{"day":60,"time":30,"homeAway":10}}},
  "results":{"scoringPolicy":{"pointsForWin":3,"pointsForDraw":1,"pointsForLoss":0},"tieBreakCriteria":["POINTS","GOAL_DIFFERENCE","GOALS_FOR","WINS"],"confirmationPolicy":{"mode":"BILATERAL","responseDeadlineHours":48,"autoOfficialAfterConfirmation":true},"publicationPolicy":{"resultsPublic":false,"standingsPublic":false}},
  "discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb)) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_closed_at,
  registration_rule_revision_id, revision, created_by
) values (
  '65070000-0000-4000-8000-000000000001', '65040000-0000-4000-8000-000000000001',
  'Wave 8C 2027', '2027', '2027-01-01', '2027-04-30', 'registration_closed',
  '65060000-0000-4000-8000-000000000001', 'CLOSED', clock_timestamp(),
  '65060000-0000-4000-8000-000000000001', 1, '64010000-0000-4000-8000-000000000012'
);

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
) values (
  '650b0000-0000-4000-8000-000000000001', '65070000-0000-4000-8000-000000000001',
  'Senior', 'senior', 'FOOTBALL_7', 'private', 'active',
  '65060000-0000-4000-8000-000000000001', 1, '64010000-0000-4000-8000-000000000012'
);

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
) values (
  '65080000-0000-4000-8000-000000000001', '65070000-0000-4000-8000-000000000001',
  'Liga regular', 'LEAGUE_STAGE', 0, false, 'draft',
  '65060000-0000-4000-8000-000000000001', 1, '64010000-0000-4000-8000-000000000012'
);

insert into public.pachanga_competition_divisions(id, stage_id, name, division_order, level_label, status, created_by)
values ('65090000-0000-4000-8000-000000000001', '65080000-0000-4000-8000-000000000001', 'Division 1', 0, 'Open', 'draft', '64010000-0000-4000-8000-000000000012');
insert into public.pachanga_competition_groups(id, stage_id, division_id, name, group_order, status, created_by)
values ('650a0000-0000-4000-8000-000000000001', '65080000-0000-4000-8000-000000000001', '65090000-0000-4000-8000-000000000001', 'Grupo A', 0, 'draft', '64010000-0000-4000-8000-000000000012');

insert into public.pachanga_competition_staff_assignments(competition_id, user_id, staff_role, status, assigned_by) values
  ('65040000-0000-4000-8000-000000000001', '64010000-0000-4000-8000-000000000012', 'competition_director', 'active', '64010000-0000-4000-8000-000000000012'),
  ('65040000-0000-4000-8000-000000000001', '64010000-0000-4000-8000-000000000011', 'competition_schedule_manager', 'active', '64010000-0000-4000-8000-000000000012');

do $wave8c_schedule_acl$
begin
  if not private.pachanga_competition_can_v1(
    '65040000-0000-4000-8000-000000000001',
    '64010000-0000-4000-8000-000000000011',
    'schedule_manage'
  ) then
    raise exception 'W8C_STAGING_SCHEDULE_MANAGER_NOT_AUTHORIZED';
  end if;
  perform pg_temp.wave8c_actor('64010000-0000-4000-8000-000000000010');
  begin
    perform public.command_pachanga_league_scheduling_v1(
      md5('wave8c-staging-league:outsider-cannot-schedule')::uuid,
      '65080000-0000-4000-8000-000000000001',
      1,
      'schedule_plan.create',
      '{"categoryId":"650b0000-0000-4000-8000-000000000001","divisionId":"65090000-0000-4000-8000-000000000001","groupId":"650a0000-0000-4000-8000-000000000001","ruleRevisionId":"65060000-0000-4000-8000-000000000001","legs":2,"reason":"Wave 8C outsider ACL regression"}'::jsonb,
      '{"clientVersion":"wave8c-staging","serviceWorkerVersion":"wave8c-staging","installedMode":"standalone","surface":"synthetic-season-staging"}'::jsonb
    );
    raise exception 'W8C_STAGING_UNAUTHORIZED_SCHEDULE_ACCEPTED';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'COMPETITION_SCHEDULE_MANAGER_REQUIRED' then
        raise;
      end if;
  end;
end;
$wave8c_schedule_acl$;

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source, status,
  rule_revision_id, accepted_by, accepted_at, reason_code, created_by
)
select md5('wave8c-league-entry-' || value)::uuid,
  '65040000-0000-4000-8000-000000000001',
  '65070000-0000-4000-8000-000000000001',
  '650b0000-0000-4000-8000-000000000001',
  ('64020000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'ORGANIZER_INVITATION', 'accepted', '65060000-0000-4000-8000-000000000001',
  '64010000-0000-4000-8000-000000000012', clock_timestamp(),
  'wave8c.fixture.accepted', '64010000-0000-4000-8000-000000000012'
from generate_series(1, 6) value;

insert into public.pachanga_competition_stage_memberships(
  id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
  status, reason, assigned_by
)
select md5('wave8c-league-membership-' || value)::uuid,
  md5('wave8c-league-entry-' || value)::uuid,
  '65080000-0000-4000-8000-000000000001',
  '65090000-0000-4000-8000-000000000001',
  '650a0000-0000-4000-8000-000000000001',
  '65060000-0000-4000-8000-000000000001',
  'active', 'Wave 8C fixture membership', '64010000-0000-4000-8000-000000000012'
from generate_series(1, 6) value;

insert into public.pachanga_competition_rosters(
  id, entry_id, category_id, rule_revision_id, status, revision, created_by
)
select md5('wave8c-league-roster-' || value)::uuid,
  md5('wave8c-league-entry-' || value)::uuid,
  '650b0000-0000-4000-8000-000000000001',
  '65060000-0000-4000-8000-000000000001',
  'locked', 1, '64010000-0000-4000-8000-000000000012'
from generate_series(1, 6) value;

insert into public.pachanga_competition_roster_revisions(
  id, roster_id, revision_number, roster_status, rule_revision_id,
  member_count, eligibility_summary, member_set_checksum, reason, created_by
)
select md5('wave8c-league-roster-revision-' || value)::uuid,
  md5('wave8c-league-roster-' || value)::uuid,
  1, 'locked', '65060000-0000-4000-8000-000000000001', 0, '{}'::jsonb,
  encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex'),
  'Wave 8C canonical roster', '64010000-0000-4000-8000-000000000012'
from generate_series(1, 6) value;

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
)
select md5('wave8c-league-roster-member-' || team_number || '-' || player_number)::uuid,
  md5('wave8c-league-roster-' || team_number)::uuid,
  md5('wave8c-league-roster-revision-' || team_number)::uuid,
  md5('wave8c-league-entry-' || team_number)::uuid,
  md5('demo-world-v2-5-player-profile-' || team_number || '-' || player_number)::uuid,
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  md5('demo-world-v2-5-player-user-' || team_number || '-' || player_number)::uuid,
  'eligible',
  jsonb_build_object('displayName', 'Jugador Copa ' || team_number || '.' || player_number),
  'eligibility.wave8c_staging'
from generate_series(1, 6) team_number
cross join generate_series(1, 10) player_number;

do $wave8c_rosters$
declare value integer;
declare roster_id uuid;
declare revision_id uuid;
begin
  for value in 1..6 loop
    roster_id := md5('wave8c-league-roster-' || value)::uuid;
    revision_id := md5('wave8c-league-roster-revision-' || value)::uuid;
    perform private.pachanga_league_finalize_roster_revision_v1(revision_id);
    update public.pachanga_competition_rosters
    set current_revision_id = revision_id
    where id = roster_id;
  end loop;
end;
$wave8c_rosters$;

do $wave8c_schedule$
declare response jsonb;
declare plan_id uuid;
begin
  response := pg_temp.wave8c_schedule_command(
    'plan', '65080000-0000-4000-8000-000000000001', 1,
    'schedule_plan.create',
    '{"categoryId":"650b0000-0000-4000-8000-000000000001","divisionId":"65090000-0000-4000-8000-000000000001","groupId":"650a0000-0000-4000-8000-000000000001","ruleRevisionId":"65060000-0000-4000-8000-000000000001","legs":2,"reason":"Wave 8C double round robin"}'::jsonb
  );
  plan_id := (response #>> '{snapshot,plan,id}')::uuid;
  response := pg_temp.wave8c_schedule_command(
    'slots', plan_id, (response ->> 'confirmedRevision')::bigint,
    'schedule_slot.bulk_create',
    '{"startDate":"2027-01-04","endDate":"2027-02-28","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista Wave 8C","resourceKey":"wave8c-staging-pitch"}'::jsonb
  );
  response := pg_temp.wave8c_schedule_command(
    'generate', plan_id, (response ->> 'confirmedRevision')::bigint,
    'schedule.generate', '{"seed":"pachangas-iq-synthetic-season-v1-staging"}'::jsonb
  );
  if (response #>> '{snapshot,counts,rounds}')::integer <> 10
     or (response #>> '{snapshot,counts,items}')::integer <> 30 then
    raise exception 'W8C_STAGING_LEAGUE_TOPOLOGY_INVALID:%', response;
  end if;
  response := pg_temp.wave8c_schedule_command(
    'validate', plan_id, (response ->> 'confirmedRevision')::bigint,
    'schedule.validate', '{"reason":"Wave 8C canonical validation"}'::jsonb
  );
  if response #>> '{snapshot,validation,status}' <> 'VALID' then
    raise exception 'W8C_STAGING_LEAGUE_VALIDATION_FAILED:%', response;
  end if;
  response := pg_temp.wave8c_schedule_command(
    'publish', plan_id, (response ->> 'confirmedRevision')::bigint,
    'schedule.publish', '{"reason":"Wave 8C canonical publication"}'::jsonb
  );
  if (response #>> '{snapshot,publication,canonicalMatchCount}')::integer <> 30 then
    raise exception 'W8C_STAGING_LEAGUE_PUBLICATION_FAILED:%', response;
  end if;
end;
$wave8c_schedule$;

do $wave8c_results$
declare match_row record;
declare home_owner uuid;
declare away_owner uuid;
begin
  for match_row in
    select contexts.*,
      row_number() over(order by rounds.round_number, items.pairing_key, contexts.id)::integer ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
    where contexts.competition_id = '65040000-0000-4000-8000-000000000001'
    order by rounds.round_number, items.pairing_key, contexts.id
  loop
    select groups.owner_id into home_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.home_entry_id;
    select groups.owner_id into away_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.away_entry_id;
    update public.pachanga_competition_match_contexts contexts set
      status = 'played', revision = contexts.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where contexts.id = match_row.id;
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id, created_by
    ) values (
      match_row.canonical_match_id, match_row.id,
      '64010000-0000-4000-8000-000000000012'
    );
    perform pg_temp.wave8c_match_command(
      match_row.id, home_owner, 'submit', 'sporting_result.submit',
      jsonb_build_object(
        'entryId', match_row.home_entry_id,
        'scoreHome', 1 + (match_row.ordinal % 3),
        'scoreAway', match_row.ordinal % 2
      )
    );
    perform pg_temp.wave8c_match_command(
      match_row.id, away_owner, 'accept', 'sporting_result.accept',
      jsonb_build_object('entryId', match_row.away_entry_id)
    );
  end loop;
  if (select count(*)
      from public.pachanga_competition_official_result_decisions decisions
      where decisions.competition_match_context_id in (
        select contexts.id
        from public.pachanga_competition_match_contexts contexts
        where contexts.competition_id = '65040000-0000-4000-8000-000000000001'
      )) <> 30
     or (select count(distinct decisions.competition_match_context_id)
         from public.pachanga_competition_official_result_decisions decisions
         where decisions.competition_match_context_id in (
           select contexts.id
           from public.pachanga_competition_match_contexts contexts
           where contexts.competition_id = '65040000-0000-4000-8000-000000000001'
         )) <> 30 then
    raise exception 'W8C_STAGING_LEAGUE_OFFICIAL_DECISION_COUNT_INVALID';
  end if;
end;
$wave8c_results$;

commit;
`;

function subscribeToTournamentInvalidations(
  supabase,
  competitionId,
  label,
  expectedEntityType,
  expectEvent = true,
) {
  let resolveEvent;
  let rejectEvent;
  const event = expectEvent
    ? new Promise((resolvePromise, rejectPromise) => {
      resolveEvent = resolvePromise;
      rejectEvent = rejectPromise;
    })
    : Promise.resolve(null);
  const timeout = expectEvent
    ? setTimeout(() => rejectEvent(new Error(`W8C_STAGING_REALTIME_TIMEOUT:${label}`)), 35_000)
    : null;
  const channel = supabase
    .channel(`wave8c-${label}-${runId}`)
    .on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "pachanga_tournament_invalidations",
      filter: `competition_id=eq.${competitionId}`,
    }, (payload) => {
      if (payload.new?.entity_type !== expectedEntityType) return;
      if (timeout) clearTimeout(timeout);
      if (resolveEvent) resolveEvent(payload);
    });
  const cancel = () => {
    if (timeout) clearTimeout(timeout);
  };
  channels.push([supabase, channel, cancel]);
  const subscribed = new Promise((resolvePromise, rejectPromise) => {
    const subscriptionTimeout = setTimeout(
      () => rejectPromise(new Error(`W8C_STAGING_SUBSCRIPTION_TIMEOUT:${label}`)),
      45_000,
    );
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(subscriptionTimeout);
        resolvePromise(status);
      } else if (["CHANNEL_ERROR", "TIMED_OUT"].includes(status)) {
        clearTimeout(subscriptionTimeout);
        rejectPromise(new Error(`W8C_STAGING_SUBSCRIPTION_FAILED:${label}:${status}`));
      }
    });
  });
  return { cancel, channel, event, subscribed };
}

async function releaseRealtimeSubscription(supabase, subscription) {
  subscription.cancel();
  await supabase.removeChannel(subscription.channel);
  const channelIndex = channels.findIndex(([, channel]) => channel === subscription.channel);
  if (channelIndex >= 0) channels.splice(channelIndex, 1);
}

async function signInDevice(label) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({
    email: ownerEmail,
    password: ownerPassword,
  });
  if (result.error) throw new Error(`W8C_STAGING_SIGN_IN_FAILED:${label}`, { cause: result.error });
  assert.equal(result.data.user.id, ownerId);
  return supabase;
}

async function tournamentHub(supabase, competitionId) {
  const result = await supabase.rpc("get_pachanga_tournament_group_hub_v1", {
    competition_id: competitionId,
  });
  if (result.error) throw result.error;
  assert.equal(result.data?.kind, "TournamentGroupStageHub");
  return result.data;
}

async function completeGroupStageWithTwoDevices(competitionId) {
  const deviceA = await signInDevice("device-a");
  const deviceB = await signInDevice("device-b");
  const maximumAttempts = 3;
  const beforeA = await tournamentHub(deviceA, competitionId);
  const beforeB = await tournamentHub(deviceB, competitionId);
  const expectedRevision = beforeA.groupStage.revision;
  assert.equal(expectedRevision, beforeB.groupStage.revision);

  const realtimeA = subscribeToTournamentInvalidations(
    deviceA, competitionId, "device-a-attempt-1", "tournament",
  );
  const realtimeB = subscribeToTournamentInvalidations(
    deviceB, competitionId, "device-b-attempt-1", "tournament",
  );
  await Promise.all([realtimeA.subscribed, realtimeB.subscribed]);
  process.stdout.write(`${JSON.stringify({ attempt: 1, devices: 2, stage: "realtime-subscription", status: "PASS" })}\n`);
  await new Promise((resolvePromise) => setTimeout(resolvePromise, 2_000));

  const operationA = randomUUID();
  const operationB = randomUUID();
  const args = (operationId) => ({
    aggregate_id: competitionId,
    client_metadata: {
      clientVersion: "8.3.0+wave8c-staging",
      installedMode: "standalone",
      serviceWorkerVersion: "8.3.0+wave8c-staging",
      sessionId: `wave8c-${runId}`,
      surface: "synthetic-season-staging",
    },
    command_action: "group_stage.complete",
    command_payload: { reason: "Wave 8C hosted two-device completion" },
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
  const [writeA, writeB] = await Promise.all([
    deviceA.rpc("command_pachanga_tournament_group_stage_v1", args(operationA)),
    deviceB.rpc("command_pachanga_tournament_group_stage_v1", args(operationB)),
  ]);
  const successes = [writeA, writeB].filter(({ error }) => !error);
  const conflicts = [writeA, writeB].filter(({ error }) => error);
  assert.equal(successes.length, 1);
  assert.equal(conflicts.length, 1);
  assert.match(`${conflicts[0].error.code} ${conflicts[0].error.message}`, /PT409|STALE_REVISION/);

  const winningOperation = successes[0] === writeA ? operationA : operationB;
  const winningDevice = successes[0] === writeA ? deviceA : deviceB;
  const replay = await winningDevice.rpc(
    "command_pachanga_tournament_group_stage_v1",
    args(winningOperation),
  );
  if (replay.error) throw replay.error;
  assert.deepEqual(replay.data, successes[0].data);

  const realtimeResults = await Promise.allSettled([realtimeA.event, realtimeB.event]);
  const afterA = await tournamentHub(deviceA, competitionId);
  const afterB = await tournamentHub(deviceB, competitionId);
  assert.equal(afterA.groupStage.revision, afterB.groupStage.revision);
  assert.equal(afterA.groupStage.revision, expectedRevision + 1);
  assert.equal(afterA.groupStage.status, "complete");
  await Promise.all([
    releaseRealtimeSubscription(deviceA, realtimeA),
    releaseRealtimeSubscription(deviceB, realtimeB),
  ]);

  const deliveredEvents = realtimeResults.filter(({ status }) => status === "fulfilled").length;
  if (deliveredEvents === 2) {
    process.stdout.write(`${JSON.stringify({
      attempt: 1,
      canonicalDevices: 2,
      deliveredEvents,
      devices: 2,
      reconnects: 0,
      stage: "realtime-invalidation",
      status: "PASS",
    })}\n`);
    return;
  }
  if (deliveredEvents === 0) {
    throw new Error("W8C_STAGING_REALTIME_DELIVERY_MISSING");
  }

  for (let attempt = 2; attempt <= maximumAttempts; attempt += 1) {
    const reconnectA = subscribeToTournamentInvalidations(
      deviceA, competitionId, `device-a-attempt-${attempt}`, "tournament", false,
    );
    const reconnectB = subscribeToTournamentInvalidations(
      deviceB, competitionId, `device-b-attempt-${attempt}`, "tournament", false,
    );
    try {
      await Promise.all([reconnectA.subscribed, reconnectB.subscribed]);
      process.stdout.write(`${JSON.stringify({ attempt, devices: 2, stage: "realtime-subscription", status: "PASS" })}\n`);
      const reconnectedA = await tournamentHub(deviceA, competitionId);
      const reconnectedB = await tournamentHub(deviceB, competitionId);
      assert.equal(reconnectedA.groupStage.revision, afterA.groupStage.revision);
      assert.equal(reconnectedB.groupStage.revision, afterA.groupStage.revision);
      assert.equal(reconnectedA.groupStage.status, "complete");
      assert.equal(reconnectedB.groupStage.status, "complete");
      process.stdout.write(`${JSON.stringify({
        attempt,
        canonicalDevices: 2,
        canonicalRevision: afterA.groupStage.revision,
        deliveredEvents,
        stage: "realtime-reconnect",
        status: "PASS",
      })}\n`);
      return;
    } catch (error) {
      process.stdout.write(`${JSON.stringify({
        attempt,
        stage: "realtime-reconnect",
        status: attempt < maximumAttempts ? "RETRY" : "EXHAUSTED",
      })}\n`);
      if (attempt === maximumAttempts) throw error;
      await new Promise((resolvePromise) => setTimeout(resolvePromise, 2_000));
    } finally {
      await Promise.all([
        releaseRealtimeSubscription(deviceA, reconnectA),
        releaseRealtimeSubscription(deviceB, reconnectB),
      ]);
    }
  }

  throw new Error("W8C_STAGING_REALTIME_RECONNECT_EXHAUSTED");
}

async function main() {
  enterStage("pristine-baseline");
  const initial = queryJson(`
    select jsonb_build_object(
      'migrations', (select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),
      'users', (select count(*) from auth.users),
      'clubs', (select count(*) from public.pachanga_clubs),
      'teams', (select count(*) from public.pachanga_groups),
      'competitions', (select count(*) from public.pachanga_competitions)
    )::text;
  `, "inspect pristine ephemeral baseline");
  assert.deepEqual(initial.migrations, localMigrationVersions);
  assert.equal(initial.migrations.length, 212);
  assert.deepEqual(
    { clubs: initial.clubs, competitions: initial.competitions, teams: initial.teams, users: initial.users },
    { clubs: 0, competitions: 0, teams: 0, users: 0 },
  );
  passStage("pristine-baseline");

  enterStage("synthetic-owner");
  const account = await fixtureAdmin.auth.admin.createUser({
    id: ownerId,
    email: ownerEmail,
    email_confirm: true,
    password: ownerPassword,
    user_metadata: { qaFixture: "SYNTHETIC_OPERATIONS_SEASON_V1", runId },
  });
  if (account.error) throw account.error;
  passStage("synthetic-owner");

  enterStage("tournament-foundation");
  psql(["-v", "DEMO_WORLD_V2_PERSIST=1"], "create twelve-team Tournament authority", tournamentFoundationSql());
  passStage("tournament-foundation");
  enterStage("sporting-prerequisites");
  psql([], "activate isolated sporting prerequisites", prerequisiteFlagsSql);
  passStage("sporting-prerequisites");
  enterStage("referee-profiles");
  psql([], "create six canonical referee profiles", refereeFixtureSql());
  passStage("referee-profiles");
  enterStage("tournament-group-stage");
  psql(["-v", "DEMO_WORLD_V2_PERSIST=1"], "operate twelve-team Tournament group stage", tournamentGroupStageSql());
  passStage("tournament-group-stage");

  const tournament = queryJson(`
    select jsonb_build_object(
      'id', competitions.id,
      'canonicalMatches', count(contexts.id),
      'officialMatches', count(contexts.id) filter (where contexts.status='official')
    )::text
    from public.pachanga_competitions competitions
    join public.pachanga_competition_match_contexts contexts on contexts.competition_id=competitions.id
    where competitions.slug='copa-barrios-iq-2027'
    group by competitions.id;
  `, "read Tournament group-stage authority");
  assert.equal(tournament.canonicalMatches, 12);
  assert.equal(tournament.officialMatches, 12);

  enterStage("two-device-group-completion");
  await completeGroupStageWithTwoDevices(tournament.id);
  passStage("two-device-group-completion");
  enterStage("tournament-knockout");
  psql(["-v", "DEMO_WORLD_V2_PERSIST=1"], "operate canonical Tournament knockout", tournamentKnockoutSql());
  passStage("tournament-knockout");
  enterStage("league-double-round-robin");
  psql([], "operate canonical double round-robin League", leagueFixtureSql);
  passStage("league-double-round-robin");

  enterStage("canonical-proof");
  const proof = queryJson(`
    with target_competitions as (
      select id, competition_type, slug
      from public.pachanga_competitions
      where slug in ('copa-barrios-iq-2027', 'wave8c-staging-league')
    ), target_matches as (
      select contexts.*, targets.competition_type, targets.slug
      from target_competitions targets
      join public.pachanga_competition_match_contexts contexts
        on contexts.competition_id=targets.id
      where contexts.status <> 'retired'
    ), retired_lineage_matches as (
      select contexts.id
      from target_competitions targets
      join public.pachanga_competition_match_contexts contexts
        on contexts.competition_id=targets.id
      where contexts.status = 'retired'
    ), overlapping_referees as (
      select assignments.referee_profile_id, contexts.scheduled_start, count(*) total
      from target_matches contexts
      join public.pachanga_referee_assignments assignments
        on assignments.canonical_match_id=contexts.canonical_match_id
       and assignments.status in ('accepted','confirmed','completed')
       and assignments.assignment_role='MAIN_REFEREE'
      group by assignments.referee_profile_id, contexts.scheduled_start
      having count(*) > 1
    ), non_synthetic_recipients as (
      select notifications.id
      from public.pachanga_user_notifications notifications
      join auth.users users on users.id=notifications.recipient_user_id
      where users.email is null or users.email not like '%.test'
    )
    select jsonb_build_object(
      'ledger', (select count(*) from supabase_migrations.schema_migrations),
      'lastMigration', (select max(version) from supabase_migrations.schema_migrations),
      'clubs', (select count(*) from public.pachanga_clubs where slug like 'club-demo-tournament-%'),
      'teams', (select count(*) from public.pachanga_groups where team_code like 'DW%'),
      'players', (select count(*) from public.pachanga_player_profiles where display_name like 'Jugador Copa %'),
      'referees', (select count(*) from public.pachanga_referee_profiles where slug like 'arbitro-demo-%'),
      'leagues', (select count(*) from target_competitions where competition_type='LEAGUE'),
      'tournaments', (select count(*) from target_competitions where competition_type='TOURNAMENT'),
      'canonicalMatches', (select count(*) from target_matches),
      'retiredLineageMatches', (select count(*) from retired_lineage_matches),
      'officialMatches', (select count(*) from target_matches where status='official'),
      'leagueMatches', (select count(*) from target_matches where slug='wave8c-staging-league'),
      'tournamentGroupMatches', (select count(*) from target_matches contexts
        join public.pachanga_competition_stages stages on stages.id=contexts.stage_id
        where contexts.slug='copa-barrios-iq-2027' and stages.stage_type='GROUP_STAGE'),
      'tournamentKnockoutMatches', (select count(*) from target_matches contexts
        join public.pachanga_competition_stages stages on stages.id=contexts.stage_id
        where contexts.slug='copa-barrios-iq-2027' and stages.stage_type='KNOCKOUT'),
      'champions', (select count(*) from public.pachanga_tournament_brackets brackets
        join public.pachanga_tournament_completion_snapshots snapshots
          on snapshots.id=brackets.current_completion_snapshot_id
        join target_competitions targets on targets.id=snapshots.competition_id
        where snapshots.champion_entry_id is not null),
      'completionSnapshotLineage', (select count(*)
        from public.pachanga_tournament_completion_snapshots snapshots
        join target_competitions targets on targets.id=snapshots.competition_id),
      'leagueActiveStaff', (select count(*)
        from public.pachanga_competition_staff_assignments assignments
        join target_competitions targets on targets.id=assignments.competition_id
        where targets.slug='wave8c-staging-league' and assignments.status='active'),
      'leagueDistinctActiveStaff', (select count(distinct assignments.user_id)
        from public.pachanga_competition_staff_assignments assignments
        join target_competitions targets on targets.id=assignments.competition_id
        where targets.slug='wave8c-staging-league' and assignments.status='active'),
      'leagueBundleCapabilities', (select count(distinct grants.capability)
        from public.pachanga_competition_entitlement_grants grants
        where grants.bundle_id='650c0000-0000-4000-8000-000000000001'
          and grants.status='active'),
      'leagueRequiredCapabilities', cardinality(private.pachanga_league_private_beta_capabilities_v1()),
      'leagueOfficialDecisions', (select count(*)
        from public.pachanga_competition_official_result_decisions decisions
        join target_matches contexts on contexts.id=decisions.competition_match_context_id
        where contexts.slug='wave8c-staging-league'),
      'leagueOfficialDecisionMatches', (select count(distinct decisions.competition_match_context_id)
        from public.pachanga_competition_official_result_decisions decisions
        join target_matches contexts on contexts.id=decisions.competition_match_context_id
        where contexts.slug='wave8c-staging-league'),
      'standingStates', (select count(*) from public.pachanga_competition_standing_states states
        join target_competitions targets on targets.id=states.competition_id
        where states.current_snapshot_id is not null),
      'mainRefereeOverlaps', (select count(*) from overlapping_referees),
      'nonSyntheticNotificationRecipients', (select count(*) from non_synthetic_recipients),
      'realEmailRecipients', 0,
      'realPushRecipients', 0,
      'stripeCalls', 0
    )::text;
  `, "read exact reduced-season proof");

  assert.deepEqual(
    {
      canonicalMatches: proof.canonicalMatches,
      clubs: proof.clubs,
      leagueMatches: proof.leagueMatches,
      leagues: proof.leagues,
      players: proof.players,
      referees: proof.referees,
      teams: proof.teams,
      tournamentGroupMatches: proof.tournamentGroupMatches,
      tournamentKnockoutMatches: proof.tournamentKnockoutMatches,
      tournaments: proof.tournaments,
    },
    {
      canonicalMatches: 50,
      clubs: 3,
      leagueMatches: 30,
      leagues: 1,
      players: 120,
      referees: 6,
      teams: 12,
      tournamentGroupMatches: 12,
      tournamentKnockoutMatches: 8,
      tournaments: 1,
    },
  );
  assert.equal(proof.officialMatches, 50);
  assert.equal(proof.retiredLineageMatches, 1);
  assert.equal(proof.champions, 1);
  assert.equal(proof.completionSnapshotLineage, 2);
  assert.equal(proof.leagueActiveStaff, 2);
  assert.equal(proof.leagueDistinctActiveStaff, 2);
  assert.equal(proof.leagueBundleCapabilities, proof.leagueRequiredCapabilities);
  assert.equal(proof.leagueOfficialDecisions, 30);
  assert.equal(proof.leagueOfficialDecisionMatches, 30);
  assert.ok(proof.standingStates >= 5);
  assert.equal(proof.mainRefereeOverlaps, 0);
  assert.equal(proof.nonSyntheticNotificationRecipients, 0);
  assert.equal(proof.realEmailRecipients, 0);
  assert.equal(proof.realPushRecipients, 0);
  assert.equal(proof.stripeCalls, 0);
  passStage("canonical-proof");

  process.stdout.write(`${JSON.stringify({
    ...proof,
    branch: env.projectRef,
    concurrency: "ONE_WINNER_ONE_STALE",
    devices: 2,
    realtime: "POSTGRES_CHANGES_RECEIVED_AND_CANONICAL_REFETCHED",
    status: "WAVE8C_REDUCED_AUTHENTICATED_SEASON_PASS",
  })}\n`);
}

try {
  await main();
} catch (error) {
  const message = redact(error instanceof Error ? error.message : String(error))
    .trim()
    .slice(-12_000);
  process.stderr.write(`${JSON.stringify({
    message,
    stage: currentStage,
    status: "WAVE8C_REDUCED_AUTHENTICATED_SEASON_FAIL",
  })}\n`);
  throw new Error(`WAVE8C_STAGING_FAILED_AT:${currentStage}:${message}`);
} finally {
  for (const [, , cancel] of channels) cancel();
  await Promise.all(channels.map(([supabase, channel]) => supabase.removeChannel(channel)));
  await Promise.all(clients.map((supabase) => supabase.auth.signOut({ scope: "local" })));
}
