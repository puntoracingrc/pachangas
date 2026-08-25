import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { leagueOperationalFixtureSql } from "../../tests/league-operational-exceptions-v1-fixture.mjs";
import type { DemoWorldV2Snapshot } from "../../app/demo-world/demo-world-v2-contract";
import {
  assertDemoWorldV2AuthorityProof,
  demoWorldV2AuthorityHash,
  type DemoWorldV2AuthorityProof,
} from "./demo-world-v2-authority";
import { generateDemoWorldV2, writeDemoWorldV2 } from "./generate-demo-world-v2";

type BaselineManifest = {
  absorbsThrough: string;
  baselinePath: string;
};

const root = path.resolve(import.meta.dirname, "../..");
const adminUrl = process.env.DEMO_WORLD_V2_DATABASE_URL
  ?? "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const parsedAdminUrl = new URL(adminUrl);
const localHosts = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);
const verifyOnly = process.argv.includes("--verify");
const psqlBin = process.env.PSQL_BIN ?? "psql";
const pgDumpBin = process.env.PG_DUMP_BIN ?? "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_demo_world_v2_${suffix}`;
const infrastructureDump = path.join(tmpdir(), `pachangas-demo-world-v2-${suffix}.sql`);
const publicRoot = path.join(root, "public/demo-world/v2");
const authorityProofPath = path.join(root, "scripts/demo-world/demo-world-v2-authority-proof.json");

if (!localHosts.has(parsedAdminUrl.hostname)) throw new Error("DEMO_WORLD_V2_LOCAL_DATABASE_REQUIRED");

function run(binary: string, args: string[], label: string, input?: string) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 96 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function admin(sql: string, label: string) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function psql(args: string[], label: string, input?: string) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(), ...args], label, input);
}

function sqlFile(file: string) {
  return path.join(root, file);
}

function replaceExactlyOnce(source: string, from: string, to: string, label: string) {
  assert.equal(source.split(from).length - 1, 1, `DEMO_WORLD_V2_FIXTURE_MARKER_DRIFT:${label}`);
  return source.replace(from, to);
}

async function demoWorldV2ScheduleFixtureSql() {
  const source = await readFile(sqlFile("tests/league-scheduling-v1-db.sql"), "utf8");
  const endMarker = "insert into r4b_invariants_before";
  const markerIndex = source.indexOf(endMarker);
  assert.notEqual(markerIndex, -1, "DEMO_WORLD_V2_R4B_FIXTURE_BOUNDARY_DRIFT");
  let fixture = source.slice(0, markerIndex);
  fixture = replaceExactlyOnce(
    fixture,
    '"registration":{"rosterPolicy":{"minimumSize":0,"maximumSize":30,"closeRequiresApprovedRosters":true}},',
    '"registration":{"rosterPolicy":{"minimumSize":0,"maximumSize":30,"closeRequiresApprovedRosters":true},"matchSheetPolicy":{"squadMin":1,"squadMax":3,"starterMin":1,"starterMax":1,"substituteMax":2}},',
    "match-sheet-policy",
  );
  fixture = replaceExactlyOnce(
    fixture,
    '"operations":{"schedulePolicy":',
    '"operations":{"exceptionPolicy":{"gracePeriodMinutes":10,"maximumMatchDurationMinutes":120,"minimumRestHours":0,"noShowLoserScore":0,"noShowOutcome":"NO_SHOW","noShowWinnerScore":3,"organizerApprovalRequired":true,"organizerCanInterveneAfterDeadline":true,"postponementDeadlinePolicy":"EXPIRE","postponementResponseDeadlineHours":48,"resumptionEligibilityPolicy":{"allowOriginalSquad":true,"allowReplacementForDocumentedInjury":false,"requireOriginalEligibility":true},"resumptionPolicy":"SAME_CANONICAL_MATCH","stageWindowEnd":"2027-06-30T23:59:59Z","stageWindowStart":"2026-07-01T00:00:00Z","venuePolicy":{"allowSavedVenue":true,"allowTbd":true,"allowVenueLabel":true}},"schedulePolicy":',
    "exception-policy",
  );
  fixture = replaceExactlyOnce(
    fixture,
    '"windowStartsAt":"2027-01-15T00:00:00Z","windowEndsAt":"2027-11-30T23:59:59Z",',
    '"windowStartsAt":"2026-07-01T00:00:00Z","windowEndsAt":"2027-06-30T23:59:59Z",',
    "schedule-window",
  );
  fixture = replaceExactlyOnce(
    fixture,
    '"results":{},"discipline":{}',
    '"results":{"scoringPolicy":{"pointsForWin":3,"pointsForDraw":1,"pointsForLoss":0},"tieBreakCriteria":["POINTS","GOAL_DIFFERENCE","GOALS_FOR","WINS"],"scorerDetailPolicy":"OPTIONAL","allowUnknownScorer":false,"confirmationPolicy":{"mode":"BILATERAL","responseDeadlineHours":48,"autoOfficialAfterConfirmation":true},"standingsPolicy":{"allowSharedPositions":true},"publicationPolicy":{"resultsPublic":true,"standingsPublic":true}},"discipline":{}',
    "results-policy",
  );
  fixture = replaceExactlyOnce(
    fixture,
    "'Season 2027', '2027', '2027-01-01', '2027-12-31'",
    "'Temporada 2026/27', '2026/27', '2026-07-01', '2027-06-30'",
    "edition-window",
  );

  return `${fixture}
do $demo$
declare response jsonb;
declare plan_id uuid;
begin
  delete from public.pachanga_team_availability_constraints
  where entry_id in (
    select md5('r4b-entry-' || value)::uuid
    from generate_series(1, 6) value
  );
  delete from public.pachanga_team_schedule_preferences
  where entry_id in (
    select md5('r4b-entry-' || value)::uuid
    from generate_series(1, 6) value
  );
  update private.pachanga_competition_foundation_settings set
    foundation_enabled = true,
    league_participation_foundation_enabled = true,
    league_registration_enabled = true,
    league_rosters_enabled = true,
    league_scheduling_foundation_enabled = true,
    league_schedule_generation_enabled = true,
    league_schedule_editing_enabled = true,
    league_schedule_publication_enabled = true,
    league_public_calendar_enabled = true,
    league_canonical_fixture_creation_enabled = true
  where singleton;
  perform pg_temp.actor('e4010000-0000-4000-8000-000000000003');
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-world-v2-schedule-plan')::uuid,
    'e4080000-0000-4000-8000-000000000001', 1,
    'schedule_plan.create',
    '{"categoryId":"e40b0000-0000-4000-8000-000000000001","divisionId":"e4090000-0000-4000-8000-000000000001","groupId":"e40a0000-0000-4000-8000-000000000001","ruleRevisionId":"e4060000-0000-4000-8000-000000000001","legs":1,"reason":"Demo World V2 canonical plan"}'::jsonb,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  plan_id := (response #>> '{snapshot,plan,id}')::uuid;
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-world-v2-schedule-slots')::uuid, plan_id, 1,
    'schedule_slot.bulk_create',
    '{"startDate":"2026-08-01","endDate":"2026-08-21","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista Demo Liga","resourceKey":"demo-world-v2-pitch"}'::jsonb,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-world-v2-schedule-generate')::uuid, plan_id, 2,
    'schedule.generate', '{"seed":"pachangas-iq-demo-world-v2-2026-27"}'::jsonb,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  if (response #>> '{snapshot,counts,rounds}')::integer <> 5
     or (response #>> '{snapshot,counts,items}')::integer <> 15 then
    raise exception 'DEMO_WORLD_V2_SCHEDULE_TOPOLOGY_INVALID';
  end if;
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-world-v2-schedule-validate')::uuid, plan_id, 3,
    'schedule.validate', '{"reason":"Demo World V2 authority validation"}'::jsonb,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  if response #>> '{snapshot,validation,status}' <> 'VALID' then
    raise exception 'DEMO_WORLD_V2_SCHEDULE_VALIDATION_FAILED';
  end if;
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-world-v2-schedule-publish')::uuid, plan_id, 4,
    'schedule.publish', '{"reason":"Demo World V2 canonical publication"}'::jsonb,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  if (response #>> '{snapshot,publication,canonicalMatchCount}')::integer <> 15 then
    raise exception 'DEMO_WORLD_V2_CANONICAL_PUBLICATION_FAILED';
  end if;
end;
$demo$;
`;
}

async function committedAuthorityProof() {
  return assertDemoWorldV2AuthorityProof(JSON.parse(
    await readFile(authorityProofPath, "utf8"),
  ) as DemoWorldV2AuthorityProof);
}

function extractAuthorityProof(migrationCount: number) {
  const sql = String.raw`
with ordered as (
  select
    contexts.*,
    items.scheduled_start as original_scheduled_start,
    rounds.round_number,
    row_number() over(order by rounds.round_number, items.pairing_key)::integer as ordinal,
    substring(home_groups.name from '([0-9]+)$')::integer as home_entry_number,
    substring(away_groups.name from '([0-9]+)$')::integer as away_entry_number,
    decisions.outcome,
    decisions.effective_score_home,
    decisions.effective_score_away,
    (
      select incidents.status
      from public.pachanga_competition_late_arrival_incidents incidents
      where incidents.competition_match_context_id = contexts.id
      order by incidents.server_sequence desc, incidents.id desc
      limit 1
    ) as late_arrival_status,
    case
      when exists (select 1 from public.pachanga_competition_no_show_incidents incidents where incidents.competition_match_context_id = contexts.id and incidents.status in ('confirmed','resolved')) then 'no_show'
      when exists (select 1 from public.pachanga_competition_match_suspensions suspensions where suspensions.competition_match_context_id = contexts.id and suspensions.status = 'resumed') then 'suspended_resumed'
      when exists (select 1 from public.pachanga_competition_postponement_requests requests where requests.competition_match_context_id = contexts.id and requests.status = 'approved') then 'postponed'
      when exists (select 1 from public.pachanga_competition_venue_condition_decisions venue where venue.competition_match_context_id = contexts.id and venue.outcome = 'venue_changed') then 'venue_changed'
      else 'none'
    end as exception_type
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  join public.pachanga_competition_entries home_entries on home_entries.id = contexts.home_entry_id
  join public.pachanga_groups home_groups on home_groups.id = home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id = contexts.away_entry_id
  join public.pachanga_groups away_groups on away_groups.id = away_entries.team_id
  join public.pachanga_competition_match_sheets sheets on sheets.competition_match_context_id = contexts.id
  join public.pachanga_competition_official_result_decisions decisions on decisions.id = sheets.active_official_decision_id
  where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001'
), profile_refs as (
  select distinct
    members.player_profile_id,
    substring(groups.name from '([0-9]+)$')::integer as entry_number,
    case when members.player_profile_id = md5(
      'demo-world-v2-profile-alt-' || substring(groups.name from '([0-9]+)$')
    )::uuid then 'alternate' else 'primary' end as player_slot
  from public.pachanga_competition_roster_members members
  join public.pachanga_competition_entries entries on entries.id = members.entry_id
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_events as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'cardTypeCode', revisions.card_type_code,
    'context', revisions.event_context,
    'entryNumber', refs.entry_number,
    'eventKey', events.creation_operation_id,
    'matchOrdinal', ordered.ordinal,
    'minute', revisions.match_minute,
    'playerSlot', refs.player_slot,
    'publicReasonCategory', revisions.public_reason_category,
    'publicSummary', revisions.public_summary,
    'revisionVersion', revisions.version,
    'sanction', case when sanctions.id is null then null else jsonb_build_object(
      'remainingUnits', sanctions.remaining_units,
      'status', sanctions.status,
      'unitType', sanctions.unit_type
    ) end,
    'status', revisions.event_status,
    'temporaryDismissal', revisions.rule_outcome -> 'temporaryDismissal',
    'visualType', revisions.rule_outcome ->> 'visualType'
  ) order by events.server_sequence, events.id), '[]'::jsonb) as value
  from public.pachanga_competition_disciplinary_events events
  join public.pachanga_competition_disciplinary_event_revisions revisions
    on revisions.id = events.current_revision_id
  join profile_refs refs on refs.player_profile_id = events.player_profile_id
  join ordered on ordered.canonical_match_id = events.canonical_match_id
  left join public.pachanga_competition_sanctions sanctions
    on sanctions.source_event_id = events.id
  where events.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_counters as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'cardTypeCode', counters.card_type_code,
    'entryNumber', refs.entry_number,
    'eventCount', counters.active_event_count,
    'playerSlot', refs.player_slot,
    'points', counters.accumulation_points,
    'thresholdHits', counters.threshold_hits
  ) order by counters.server_sequence, counters.id), '[]'::jsonb) as value
  from public.pachanga_competition_disciplinary_counters counters
  join profile_refs refs on refs.player_profile_id = counters.player_profile_id
  where counters.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_sanctions as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryNumber', refs.entry_number,
    'outcome', sanctions.sanction_outcome,
    'playerSlot', refs.player_slot,
    'publicReasonCategory', revisions.public_reason_category,
    'publicSummary', revisions.public_summary,
    'remainingUnits', sanctions.remaining_units,
    'sourceEventKey', events.creation_operation_id,
    'status', sanctions.status,
    'totalUnits', sanctions.total_units,
    'unitType', sanctions.unit_type
  ) order by sanctions.server_sequence, sanctions.id), '[]'::jsonb) as value
  from public.pachanga_competition_sanctions sanctions
  join public.pachanga_competition_disciplinary_events events on events.id = sanctions.source_event_id
  join public.pachanga_competition_sanction_revisions revisions on revisions.id = sanctions.current_revision_id
  join profile_refs refs on refs.player_profile_id = sanctions.player_profile_id
  where sanctions.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_service as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'eventType', service.event_type,
    'matchOrdinal', ordered.ordinal,
    'remainingAfter', service.remaining_after,
    'remainingBefore', service.remaining_before,
    'sourceEventKey', events.creation_operation_id,
    'units', service.units
  ) order by service.server_sequence, service.id), '[]'::jsonb) as value
  from public.pachanga_competition_sanction_service_events service
  join public.pachanga_competition_sanctions sanctions on sanctions.id = service.sanction_id
  join public.pachanga_competition_disciplinary_events events on events.id = sanctions.source_event_id
  join ordered on ordered.canonical_match_id = service.canonical_match_id
  where service.competition_id = 'e4040000-0000-4000-8000-000000000001'
    and service.event_type = 'SERVED'
), discipline_appeals as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'sourceEventKey', events.creation_operation_id,
    'status', appeals.status
  ) order by appeals.server_sequence, appeals.id), '[]'::jsonb) as value
  from public.pachanga_competition_sanction_appeals appeals
  join public.pachanga_competition_sanctions sanctions on sanctions.id = appeals.sanction_id
  join public.pachanga_competition_disciplinary_events events on events.id = sanctions.source_event_id
  where appeals.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_states as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'cards', states.card_summary,
    'entryNumber', refs.entry_number,
    'playerSlot', refs.player_slot,
    'remainingUnits', states.remaining_units,
    'status', states.sanction_status,
    'unitType', states.unit_type
  ) order by states.server_sequence, states.id), '[]'::jsonb) as value
  from public.pachanga_competition_discipline_player_states states
  join profile_refs refs on refs.player_profile_id = states.player_profile_id
  where states.competition_id = 'e4040000-0000-4000-8000-000000000001'
), discipline_eligibility as (
  select jsonb_agg(jsonb_build_object(
    'matchOrdinal', ordered.ordinal,
    'primaryAvailable', refs.player_slot = 'primary',
    'roundNumber', ordered.round_number,
    'selectedSlot', refs.player_slot
  ) order by ordered.round_number, ordered.ordinal) as value
  from ordered
  join public.pachanga_competition_match_squads squads
    on squads.competition_match_context_id = ordered.id
    and squads.entry_id = md5('r4b-entry-2')::uuid
  join public.pachanga_competition_match_squad_members members
    on members.squad_revision_id = squads.current_revision_id
  join profile_refs refs on refs.player_profile_id = members.player_profile_id
), matches as (
  select jsonb_agg(jsonb_build_object(
    'awayEntryNumber', away_entry_number,
    'exceptionType', exception_type,
    'homeEntryNumber', home_entry_number,
    'lateArrivalStatus', late_arrival_status,
    'lineage', case exception_type
      when 'postponed' then '["postponement","fixture_change","official_result"]'::jsonb
      when 'venue_changed' then '["fixture_change","official_result"]'::jsonb
      when 'suspended_resumed' then '["suspension","resumption","official_result"]'::jsonb
      else '["official_result"]'::jsonb end,
    'originalScheduledStart', original_scheduled_start,
    'outcome', outcome,
    'partialResult', case when exception_type = 'suspended_resumed' then (
      select jsonb_build_object('away', suspensions.sporting_score_away, 'home', suspensions.sporting_score_home, 'minute', suspensions.reported_minute)
      from public.pachanga_competition_match_suspensions suspensions
      where suspensions.competition_match_context_id = ordered.id
      order by suspensions.server_sequence desc, suspensions.id desc limit 1
    ) else null end,
    'result', jsonb_build_object('away', effective_score_away, 'home', effective_score_home),
    'roundNumber', round_number,
    'scheduledStart', scheduled_start,
    'venueLabel', coalesce(venue_label, 'Pista Demo Liga')
  ) order by ordinal) as value from ordered
), standings as (
  select jsonb_agg(jsonb_build_object(
    'draws', rows.draws,
    'effectivePoints', rows.effective_points,
    'entryNumber', substring(groups.name from '([0-9]+)$')::integer,
    'goalDifference', rows.goal_difference,
    'goalsAgainst', rows.goals_against,
    'goalsFor', rows.goals_for,
    'losses', rows.losses,
    'played', rows.played,
    'position', rows.position,
    'wins', rows.wins
  ) order by rows.position, rows.entry_id) as value
  from public.pachanga_competition_standing_states states
  join public.pachanga_competition_standing_rows rows on rows.standing_snapshot_id = states.current_snapshot_id
  join public.pachanga_competition_entries entries on entries.id = rows.entry_id
  join public.pachanga_groups groups on groups.id = entries.team_id
  where states.competition_id = 'e4040000-0000-4000-8000-000000000001'
)
select jsonb_build_object(
  'discipline', jsonb_build_object(
    'appeals', discipline_appeals.value,
    'cardCounts', jsonb_build_object(
      'BLUE', (select count(*) from public.pachanga_competition_disciplinary_events events join public.pachanga_competition_disciplinary_event_revisions revisions on revisions.id = events.current_revision_id where events.competition_id = 'e4040000-0000-4000-8000-000000000001' and revisions.card_type_code = 'BLUE' and revisions.event_status <> 'annulled'),
      'RED', (select count(*) from public.pachanga_competition_disciplinary_events events join public.pachanga_competition_disciplinary_event_revisions revisions on revisions.id = events.current_revision_id where events.competition_id = 'e4040000-0000-4000-8000-000000000001' and revisions.card_type_code = 'RED' and revisions.event_status <> 'annulled'),
      'YELLOW', (select count(*) from public.pachanga_competition_disciplinary_events events join public.pachanga_competition_disciplinary_event_revisions revisions on revisions.id = events.current_revision_id where events.competition_id = 'e4040000-0000-4000-8000-000000000001' and revisions.card_type_code = 'YELLOW' and revisions.event_status <> 'annulled')
    ),
    'counters', discipline_counters.value,
    'eligibilityTimeline', discipline_eligibility.value,
    'events', discipline_events.value,
    'playerStates', discipline_states.value,
    'sanctions', discipline_sanctions.value,
    'serviceEvents', discipline_service.value
  ),
  'matchCount', (select count(*) from ordered),
  'matches', matches.value,
  'operationReceipts', jsonb_build_object(
    'discipline', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'competition_discipline' and client_metadata ->> 'surface' = 'demo_world_v2'),
    'matchOperations', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'league_match_operations' and client_metadata ->> 'surface' = 'demo_world_v2'),
    'operationalExceptions', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'league_operational_exceptions' and client_metadata ->> 'surface' = 'demo_world_v2'),
    'scheduling', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'league_schedule' and client_metadata ->> 'surface' = 'demo_world_v2')
  ),
  'roundCount', (select count(distinct round_number) from ordered),
  'standings', standings.value
)
from matches, standings, discipline_events, discipline_counters,
  discipline_sanctions, discipline_service, discipline_appeals,
  discipline_states, discipline_eligibility;
`;
  const extracted = JSON.parse(psql(["-At", "-c", sql], "extract Demo World V2 authority proof")) as Omit<DemoWorldV2AuthorityProof, "authorityHash" | "database" | "generatedAt" | "migrationCount" | "remoteWrites" | "rpcFamilies" | "version">;
  const payload: Omit<DemoWorldV2AuthorityProof, "authorityHash"> = {
    ...extracted,
    database: "temporary-local-postgresql",
    generatedAt: "2026-08-25T10:00:00.000Z",
    migrationCount,
    remoteWrites: 0,
    rpcFamilies: ["R1", "R4A", "R4B", "R4C", "R4D", "R5"],
    version: 2,
  };
  return assertDemoWorldV2AuthorityProof({
    ...payload,
    authorityHash: demoWorldV2AuthorityHash(payload),
  });
}

async function committedSnapshot(): Promise<DemoWorldV2Snapshot> {
  const read = async <T>(name: string) => JSON.parse(await readFile(path.join(publicRoot, name), "utf8")) as T;
  const [activity, clubsReferees, competitions, core, manifest, matches, players] = await Promise.all([
    read<DemoWorldV2Snapshot["activity"]>("activity.json"),
    read<DemoWorldV2Snapshot["clubsReferees"]>("clubs-referees.json"),
    read<DemoWorldV2Snapshot["competitions"]>("competitions.json"),
    read<DemoWorldV2Snapshot["core"]>("core.json"),
    read<DemoWorldV2Snapshot["manifest"]>("manifest.json"),
    read<DemoWorldV2Snapshot["matches"]>("matches.json"),
    read<DemoWorldV2Snapshot["players"]>("players.json"),
  ]);
  return { activity, clubsReferees, competitions, core, manifest, matches, players };
}

async function dropDatabase() {
  try {
    admin(`alter database ${databaseName} with allow_connections false`, "close Demo World V2 database");
    admin(`select pg_terminate_backend(pid) from pg_stat_activity where datname='${databaseName}' and pid<>pg_backend_pid()`, "terminate Demo World V2 connections");
    admin(`drop database if exists ${databaseName}`, "drop Demo World V2 database");
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  }
}

async function main() {
  const baseline = JSON.parse(await readFile(path.join(root, "supabase/baselines/manifest.json"), "utf8")) as BaselineManifest;
  const migrationNames = (await readdir(path.join(root, "supabase/migrations")))
    .filter((name) => /^\d{14}_.+\.sql$/.test(name))
    .sort();
  const incremental = migrationNames.filter((name) => name.slice(0, 14) > baseline.absorbsThrough);
  const migrationBatches = [
    { label: "R1, Clubs and Referees foundation", names: incremental.filter((name) => name < "20260822192929") },
    { label: "R4A", names: incremental.filter((name) => name >= "20260822192929" && name < "20260823224156") },
    { label: "R4B", names: incremental.filter((name) => name >= "20260823224156" && name < "20260824101500") },
    { label: "Clubs and Referees beta bridge", names: incremental.filter((name) => name >= "20260824101500" && name < "20260824165759") },
    { label: "R4C", names: incremental.filter((name) => name >= "20260824165759" && name < "20260824230726") },
    { label: "R4D", names: incremental.filter((name) => name >= "20260824230726" && name < "20260825074304") },
    { label: "League Private Beta", names: incremental.filter((name) => name >= "20260825074304" && name < "20260825165834") },
    { label: "R5", names: incremental.filter((name) => name >= "20260825165834") },
  ];
  assert.equal(migrationBatches.flatMap(({ names }) => names).length, incremental.length);

  const applyBatch = (label: string, names: string[]) => {
    if (!names.length) return;
    psql([
      "--single-transaction",
      ...names.flatMap((name) => ["-f", path.join(root, "supabase/migrations", name)]),
    ], `apply ${label} migrations`);
  };

  try {
    run(pgDumpBin, [
      "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
      "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
      "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
      "--file", infrastructureDump, adminUrl,
    ], "export local Supabase infrastructure");
    admin(`create database ${databaseName} template template0`, "create Demo World V2 database");
    psql(["-f", infrastructureDump], "restore local Supabase infrastructure");
    psql(["-c", "create publication supabase_realtime;"], "create Realtime publication");
    psql(["--single-transaction", "-f", path.join(root, baseline.baselinePath)], "apply canonical baseline");

    applyBatch(migrationBatches[0]!.label, migrationBatches[0]!.names);
    psql(["-f", sqlFile("tests/competition-organizer-foundation-v1-db.sql")], "R1 real RPC/RLS suite");
    applyBatch(migrationBatches[1]!.label, migrationBatches[1]!.names);
    psql([
      "-c", "begin",
      "-f", sqlFile("tests/league-participation-v1-db.sql"),
      "-f", sqlFile("tests/league-participation-v1-adversarial.sql"),
      "-c", "rollback",
    ], "R4A real RPC/RLS suite");
    applyBatch(migrationBatches[2]!.label, migrationBatches[2]!.names);
    psql(["-c", "begin", "-f", sqlFile("tests/league-scheduling-v1-db.sql"), "-c", "rollback"], "R4B real RPC/RLS suite");
    applyBatch(migrationBatches[3]!.label, migrationBatches[3]!.names);
    applyBatch(migrationBatches[4]!.label, migrationBatches[4]!.names);
    psql(["-c", "begin", "-f", sqlFile("tests/league-match-operations-v1-db.sql"), "-c", "rollback"], "R4C real RPC/RLS suite");
    applyBatch(migrationBatches[5]!.label, migrationBatches[5]!.names);
    psql([], "load R4D canonical fixture", `begin;\n${leagueOperationalFixtureSql({ enableFlags: true })}\ncommit;\n`);
    psql(["-f", sqlFile("tests/league-operational-exceptions-v1-db.sql")], "R4D real RPC/RLS suite");
    applyBatch(migrationBatches[6]!.label, migrationBatches[6]!.names);
    psql(["-f", sqlFile("tests/league-private-beta-v1-db.sql")], "League Private Beta grant and orchestration suite");
    applyBatch(migrationBatches[7]!.label, migrationBatches[7]!.names);
    psql([], "create Demo World V2 canonical League through R4B RPCs", await demoWorldV2ScheduleFixtureSql());
    psql(["-f", sqlFile("scripts/demo-world/demo-world-v2-authority-operations.sql")], "operate Demo World V2 through R4C, R4D and R5 RPCs");

    const authorityProof = extractAuthorityProof(migrationNames.length);
    const generated = generateDemoWorldV2(authorityProof);
    if (verifyOnly) {
      assert.deepEqual(authorityProof, await committedAuthorityProof(), "DEMO_WORLD_V2_AUTHORITY_PROOF_DRIFT");
      assert.deepEqual(generated, await committedSnapshot(), "DEMO_WORLD_V2_SNAPSHOT_DRIFT");
    } else {
      await writeFile(authorityProofPath, `${JSON.stringify(authorityProof, null, 2)}\n`, "utf8");
      await writeDemoWorldV2(generated, publicRoot);
    }

    process.stdout.write(`${JSON.stringify({
      database: "temporary-local-postgresql",
      destroyedAfterRun: true,
      exported: !verifyOnly,
      flags: "synthetic-only",
      authorityHash: authorityProof.authorityHash,
      hash: generated.manifest.hash,
      migrations: migrationNames.length,
      mode: verifyOnly ? "verify" : "simulate",
      remoteWrites: 0,
      rpcFamilies: ["R1", "R4A", "R4B", "R4C", "R4D", "R5", "LEAGUE_PRIVATE_BETA_V1"],
      snapshotIdentical: verifyOnly,
    })}\n`);
  } finally {
    await dropDatabase();
    await rm(infrastructureDump, { force: true });
  }
}

await main();
