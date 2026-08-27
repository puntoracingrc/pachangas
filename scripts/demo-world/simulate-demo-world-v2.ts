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
    '"operations":{"exceptionPolicy":{"gracePeriodMinutes":10,"maximumMatchDurationMinutes":120,"minimumRestHours":0,"noShowLoserScore":0,"noShowOutcome":"NO_SHOW","noShowWinnerScore":3,"organizerApprovalRequired":true,"organizerCanInterveneAfterDeadline":true,"postponementDeadlinePolicy":"EXPIRE","postponementResponseDeadlineHours":48,"resumptionEligibilityPolicy":{"allowOriginalSquad":true,"allowReplacementForDocumentedInjury":false,"requireOriginalEligibility":true},"resumptionPolicy":"SAME_CANONICAL_MATCH","stageWindowEnd":"2027-06-30T23:59:59Z","stageWindowStart":"2026-07-01T00:00:00Z","venuePolicy":{"allowSavedVenue":true,"allowTbd":true,"allowVenueLabel":true}},"refereePolicy":{"acceptanceIsSufficient":false,"authority":{"observeScore":true,"reportCards":true,"reportIncidents":true},"fee":{"mode":"NEGOTIABLE","paymentProcessing":false,"publicConsent":false,"travelIncluded":false},"modalityRequired":true,"organizerConfirmationRequired":true,"priorClubRelationshipRequired":false,"proposerRoles":["competition_owner","competition_director","competition_referee_manager"],"reconfirmAfterScheduleChange":true,"replacementAllowed":true,"requiredBeforeReady":false,"responseDeadlineHours":72,"role":"MAIN_REFEREE","serviceAreaRequired":true,"usage":"OPTIONAL"},"schedulePolicy":',
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

function extractConfigurationAuthorityProof(): DemoWorldV2AuthorityProof["configuration"] {
  const sql = String.raw`
with target_competition as (
  select competitions.id, competitions.name
  from public.pachanga_competitions competitions
  where competitions.name = 'Liga Wave 5A'
  order by competitions.server_sequence desc, competitions.id desc
  limit 1
), revisions as (
  select
    rule_revisions.*,
    private.pachanga_competition_configuration_human_document_v1(rule_revisions.id) as human_document,
    case when rule_revisions.version = 1 then (
      select private.pachanga_competition_configuration_health_v1(wizards.step_data, wizards.completed_steps)
      from private.pachanga_league_private_beta_wizards wizards
      where wizards.competition_id = target_competition.id
      order by wizards.server_sequence desc, wizards.id desc
      limit 1
    ) else (
      select drafts.validation_snapshot
      from private.pachanga_competition_configuration_drafts drafts
      where drafts.materialized_rule_revision_id = rule_revisions.id
      order by drafts.server_sequence desc, drafts.id desc
      limit 1
    ) end as health
  from target_competition
  join public.pachanga_competition_rule_sets rule_sets
    on rule_sets.competition_id = target_competition.id
  join public.pachanga_competition_rule_revisions rule_revisions
    on rule_revisions.rule_set_id = rule_sets.id
), base_revision as (
  select * from revisions where version = 1
), custom_revision as (
  select * from revisions where version = 2
), comparison as (
  select private.pachanga_competition_configuration_diff_v1(
    base_revision.rule_document,
    custom_revision.rule_document
  ) as value
  from base_revision, custom_revision
), public_revisions as (
  select jsonb_agg(jsonb_build_object(
    'authoringMode', revisions.rule_document #>> '{identity,authoringMode}',
    'blueEnabled', exists (
      select 1
      from jsonb_array_elements(revisions.rule_document #> '{discipline,policy,cardTypeCatalog}') cards
      where cards ->> 'code' = 'BLUE'
    ),
    'cardCodes', (
      select jsonb_agg(cards.value ->> 'code' order by ordinal)
      from jsonb_array_elements(revisions.rule_document #> '{discipline,policy,cardTypeCatalog}')
        with ordinality cards(value, ordinal)
    ),
    'checksum', revisions.checksum,
    'effectiveScope', revisions.effective_scope,
    'feeMode', revisions.rule_document #>> '{operations,refereePolicy,fee,mode}',
    'feePublicConsent', coalesce((revisions.rule_document #>> '{operations,refereePolicy,fee,publicConsent}')::boolean, false),
    'healthComplete', coalesce((revisions.health ->> 'complete')::boolean, false),
    'humanDocumentVerified',
      revisions.human_document #>> '{sections,matches,matchDurationMinutes}'
        = revisions.rule_document #>> '{operations,schedulePolicy,matchDurationMinutes}'
      and revisions.human_document #>> '{sections,scoring,pointsForWin}'
        = revisions.rule_document #>> '{results,scoringPolicy,pointsForWin}'
      and revisions.human_document #>> '{sections,incidents,noShowWinnerScore}'
        = revisions.rule_document #>> '{operations,exceptionPolicy,noShowWinnerScore}'
      and revisions.human_document #>> '{sections,referees,usage}'
        = revisions.rule_document #>> '{operations,refereePolicy,usage}',
    'matchDurationMinutes', (revisions.rule_document #>> '{operations,schedulePolicy,matchDurationMinutes}')::integer,
    'noShowLoserScore', (revisions.rule_document #>> '{operations,exceptionPolicy,noShowLoserScore}')::integer,
    'noShowWinnerScore', (revisions.rule_document #>> '{operations,exceptionPolicy,noShowWinnerScore}')::integer,
    'pointsForDraw', (revisions.rule_document #>> '{results,scoringPolicy,pointsForDraw}')::integer,
    'pointsForLoss', (revisions.rule_document #>> '{results,scoringPolicy,pointsForLoss}')::integer,
    'pointsForWin', (revisions.rule_document #>> '{results,scoringPolicy,pointsForWin}')::integer,
    'postponementResponseDeadlineHours', (revisions.rule_document #>> '{operations,exceptionPolicy,postponementResponseDeadlineHours}')::integer,
    'refereeRequiredBeforeReady', coalesce((revisions.rule_document #>> '{operations,refereePolicy,requiredBeforeReady}')::boolean, false),
    'refereeUsage', revisions.rule_document #>> '{operations,refereePolicy,usage}',
    'revision', revisions.version,
    'source', case when revisions.version = 1 then 'LEAGUE_WIZARD_V2'
      else 'COMPETITION_CONFIGURATION_CENTER_V1' end,
    'sourcePresetId', revisions.rule_document #>> '{identity,sourcePresetId}',
    'status', revisions.status,
    'yellowThreshold', (
      select (cards -> 'accumulation' ->> 'threshold')::integer
      from jsonb_array_elements(revisions.rule_document #> '{discipline,policy,cardTypeCatalog}') cards
      where cards ->> 'code' = 'YELLOW'
      limit 1
    )
  ) order by revisions.version) as value
  from revisions
)
select jsonb_build_object(
  'activeDrafts', (
    select count(*) from private.pachanga_competition_configuration_drafts drafts
    join target_competition on target_competition.id = drafts.competition_id
    where drafts.status in ('draft', 'validated')
  ),
  'comparator', jsonb_build_object(
    'baseRevision', 1,
    'changedSections', (
      select coalesce(jsonb_agg(items.key order by items.key), '[]'::jsonb)
      from comparison, jsonb_each(comparison.value) items
      where coalesce((items.value ->> 'changed')::boolean, false)
    ),
    'targetRevision', 2
  ),
  'competitionName', (select name from target_competition),
  'currentEditionRevision', (
    select revisions.version
    from target_competition
    join public.pachanga_competition_editions editions on editions.competition_id = target_competition.id
    join revisions on revisions.id = editions.rule_revision_id
    order by editions.server_sequence desc, editions.id desc
    limit 1
  ),
  'futureCapabilities', (select rule_document -> 'futureCapabilities' from custom_revision),
  'health', (
    select jsonb_build_object(
      'complete', coalesce((health ->> 'complete')::boolean, false),
      'errors', jsonb_array_length(coalesce(health -> 'errors', '[]'::jsonb)),
      'globallyDisabled', coalesce(health -> 'globallyDisabled', '[]'::jsonb),
      'status', health ->> 'status',
      'warnings', jsonb_array_length(coalesce(health -> 'warnings', '[]'::jsonb))
    ) from custom_revision
  ),
  'operationReceipts', (
    select count(*) from private.pachanga_competition_configuration_receipts receipts
    where receipts.client_metadata ->> 'surface' = 'demo_world_v2_configuration'
  ),
  'publishedDrafts', (
    select count(*) from private.pachanga_competition_configuration_drafts drafts
    join target_competition on target_competition.id = drafts.competition_id
    where drafts.status = 'published'
  ),
  'r5CatalogCodes', (
    select jsonb_agg(cards.value ->> 'code' order by ordinal)
    from custom_revision
    join public.pachanga_competition_discipline_rule_catalogs catalogs
      on catalogs.rule_revision_id = custom_revision.id,
    jsonb_array_elements(catalogs.card_type_catalog) with ordinality cards(value, ordinal)
  ),
  'refereePolicyConsumed', (
    select jsonb_build_object(
      'feeMode', policy.value #>> '{fee,mode}',
      'publicConsent', coalesce((policy.value #>> '{fee,publicConsent}')::boolean, false),
      'requiredBeforeReady', coalesce((policy.value ->> 'requiredBeforeReady')::boolean, false),
      'usage', policy.value ->> 'usage'
    )
    from custom_revision,
    lateral (select private.pachanga_competition_referee_policy_v1(custom_revision.id) as value) policy
  ),
  'remoteWrites', 0,
  'revisions', public_revisions.value
)
from public_revisions;
`;
  return JSON.parse(psql(["-At", "-c", sql], "extract Demo World V2.3 configuration proof")) as DemoWorldV2AuthorityProof["configuration"];
}

function extractTournamentAuthorityProof(): DemoWorldV2AuthorityProof["tournament"] {
  const sql = String.raw`
with target as (
  select competitions.id, competitions.name, competitions.slug
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027'
  order by competitions.server_sequence desc, competitions.id desc
  limit 1
), plan as (
  select plans.*
  from target
  join public.pachanga_competition_draw_plans plans
    on plans.competition_id = target.id
), generated as (
  select revisions.*, quality.hard_violations, quality.soft_score,
    quality.level_balance, quality.same_club_collisions,
    quality.pot_distribution, quality.group_size_balance,
    quality.manual_override_count, quality.unassigned_entries
  from plan
  join public.pachanga_competition_draw_revisions revisions
    on revisions.draw_plan_id = plan.id
  join public.pachanga_competition_draw_quality_snapshots quality
    on quality.draw_revision_id = revisions.id
  where revisions.validation_status = 'PENDING'
  order by revisions.version
), outcomes as (
  select jsonb_agg(jsonb_build_object(
    'algorithmVersion', generated.algorithm_version,
    'groupSizeBalance', generated.group_size_balance,
    'hardViolations', generated.hard_violations,
    'inputChecksum', generated.input_checksum,
    'levelBalance', generated.level_balance,
    'locks', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'entryNumber', substring(teams.team_code from 3)::integer,
        'groupNumber', placements.group_number,
        'slotNumber', placements.slot_number,
        'teamName', teams.name
      ) order by placements.group_number, placements.slot_number, placements.entry_id), '[]'::jsonb)
      from public.pachanga_competition_draw_placements placements
      join public.pachanga_competition_entries entries on entries.id = placements.entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      where placements.draw_revision_id = generated.id
        and placements.placement_source = 'LOCKED'
    ),
    'manualOverrideCount', generated.manual_override_count,
    'mode', generated.mode,
    'placements', (
      select jsonb_agg(jsonb_build_object(
        'entryNumber', substring(teams.team_code from 3)::integer,
        'groupNumber', placements.group_number,
        'placementSource', placements.placement_source,
        'potNumber', placements.pot_number,
        'slotNumber', placements.slot_number,
        'teamName', teams.name
      ) order by placements.group_number, placements.slot_number, placements.entry_id)
      from public.pachanga_competition_draw_placements placements
      join public.pachanga_competition_entries entries on entries.id = placements.entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      where placements.draw_revision_id = generated.id
    ),
    'potDistribution', generated.pot_distribution,
    'qualityScore', generated.quality_score,
    'resultChecksum', generated.result_checksum,
    'sameClubCollisions', generated.same_club_collisions,
    'seed', generated.seed,
    'softScore', generated.soft_score,
    'unassignedEntries', generated.unassigned_entries,
    'version', generated.version
  ) order by generated.version) value
  from generated
), conflict as (
  select evidence.error_code, evidence.error_detail
  from simulation.demo_world_tournament_conflict_evidence evidence
  order by evidence.captured_at desc, evidence.plan_id desc
  limit 1
)
select jsonb_build_object(
  'acceptedParticipants', (
    select count(*) from target
    join public.pachanga_competition_entries entries on entries.competition_id = target.id
    where entries.status in ('accepted', 'active')
  ),
  'competitionName', (select name from target),
  'conflict', (
    select jsonb_build_object(
      'attempts', (conflict.error_detail ->> 'attempts')::integer,
      'constraintTypes', (
        select coalesce(jsonb_agg(types.type order by types.type), '[]'::jsonb)
        from (
          select distinct constraint_item.value ->> 'type' type
          from jsonb_array_elements(conflict.error_detail -> 'constraints') constraint_item(value)
          where constraint_item.value ->> 'type' = 'FIXED_POSITION'
        ) types
      ),
      'errorCode', conflict.error_code,
      'reasonCode', conflict.error_detail ->> 'code',
      'suggestions', conflict.error_detail -> 'suggestions'
    ) from conflict
  ),
  'constraints', (
    select jsonb_agg(jsonb_build_object(
      'reason', constraints.reason,
      'strength', constraints.strength,
      'type', constraints.constraint_type,
      'weight', constraints.weight
    ) order by constraints.constraint_type)
    from plan
    join public.pachanga_competition_draw_constraints constraints
      on constraints.draw_plan_id = plan.id
    where constraints.status = 'active'
  ),
  'drawOutcomes', outcomes.value,
  'generatedOutcomes', (select count(*) from generated),
  'groupCount', (select group_count from plan),
  'operationReceipts', (
    select count(*)
    from private.pachanga_competition_operation_receipts receipts
    where receipts.aggregate_type = 'tournament'
      and receipts.client_metadata ->> 'surface' = 'demo_world_v2_tournament'
  ),
  'planStatus', (select status from plan),
  'potCount', (
    select count(*) from plan
    join public.pachanga_competition_draw_pots pots on pots.draw_plan_id = plan.id
    where pots.status = 'active'
  ),
  'publishedRevision', (
    select revisions.version from plan
    join public.pachanga_competition_draw_revisions revisions
      on revisions.id = plan.current_revision_id
  ),
  'remoteWrites', 0,
  'slug', (select slug from target),
  'totalRevisions', (
    select count(*) from plan
    join public.pachanga_competition_draw_revisions revisions
      on revisions.draw_plan_id = plan.id
  ),
  'tournamentMatches', (
    select count(*) from target
    join public.pachanga_competition_match_contexts contexts
      on contexts.competition_id = target.id
  )
)
from outcomes;
`;
  return JSON.parse(psql(["-At", "-c", sql], "extract Demo World V2.4 Tournament proof")) as DemoWorldV2AuthorityProof["tournament"];
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
), referee_refs as (
  select
    profiles.*,
    values.referee_number
  from generate_series(1, 8) values(referee_number)
  join public.pachanga_referee_profiles profiles
    on profiles.id = md5('demo-world-v2-referee-profile-' || values.referee_number)::uuid
), referee_profiles as (
  select jsonb_agg(jsonb_build_object(
    'availabilityStatus', refs.availability_status,
    'displayName', refs.public_display_name_snapshot,
    'modalities', coalesce((
      select jsonb_agg(modalities.modality order by modalities.modality)
      from public.pachanga_referee_modalities modalities
      where modalities.referee_profile_id = refs.id and modalities.active
    ), '[]'::jsonb),
    'municipality', coalesce((
      select areas.municipality
      from public.pachanga_referee_service_areas areas
      where areas.referee_profile_id = refs.id and areas.status = 'active'
      order by areas.server_sequence, areas.id limit 1
    ), 'Barcelona'),
    'publicBio', refs.bio,
    'publicFee', case
      when refs.public_fee_visibility
        and private.pachanga_referee_public_fee_consent_valid_v1(refs.id)
      then jsonb_build_object(
        'currency', refs.public_fee_currency,
        'feeMode', refs.public_fee_mode,
        'fromCents', refs.public_fee_from_cents,
        'paymentManagedByPachangasIq', false
      ) else null end,
    'refereeNumber', refs.referee_number,
    'slug', refs.slug,
    'statistics', jsonb_build_object(
      'assignmentsAccepted', coalesce(stats.assignments_accepted, 0),
      'assignmentsConfirmed', coalesce(stats.assignments_confirmed, 0),
      'assignmentsDeclined', coalesce(stats.assignments_declined, 0),
      'blueCardsShown', coalesce(stats.blue_cards_shown, 0),
      'cancellations', coalesce(stats.cancellations, 0),
      'leagueMatchesCompleted', coalesce(stats.league_matches_completed, 0),
      'matchesCompleted', coalesce(stats.matches_completed, 0),
      'proposalsReceived', coalesce(stats.proposals_received, 0),
      'redCardsShown', coalesce(stats.red_cards_shown, 0),
      'replacements', coalesce(stats.replacements, 0),
      'yellowCardsShown', coalesce(stats.yellow_cards_shown, 0)
    ),
    'verificationStatus', refs.verification_status
  ) order by refs.referee_number) as value
  from referee_refs refs
  left join public.pachanga_referee_statistics_snapshots stats
    on stats.referee_profile_id = refs.id
), referee_assignments as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignmentKey', assignments.id,
    'effectiveScheduledEnd', assignments.effective_scheduled_end,
    'effectiveScheduledStart', assignments.effective_scheduled_start,
    'matchOrdinal', ordered.ordinal,
    'reconfirmed', assignments.reconfirmed_at is not null,
    'refereeNumber', refs.referee_number,
    'replacedByAssignmentKey', assignments.replaced_by_assignment_id,
    'replacesAssignmentKey', assignments.replaces_assignment_id,
    'revision', assignments.revision,
    'scheduleState', assignments.schedule_state,
    'scheduledEnd', assignments.scheduled_end,
    'scheduledStart', assignments.scheduled_start,
    'status', assignments.status
  ) order by assignments.server_sequence, assignments.id), '[]'::jsonb) as value
  from public.pachanga_referee_assignments assignments
  join ordered on ordered.canonical_match_id = assignments.canonical_match_id
  join referee_refs refs on refs.id = assignments.referee_profile_id
  where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001'
), referee_assignment_summary as (
  select jsonb_build_object(
    'assignments', referee_assignments.value,
    'counts', jsonb_build_object(
      'cancelled', (select count(*) from public.pachanga_referee_assignments assignments where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001' and assignments.status = 'cancelled'),
      'completed', (select count(*) from public.pachanga_referee_assignments assignments where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001' and assignments.status = 'completed'),
      'declined', (select count(*) from public.pachanga_referee_assignments assignments where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001' and assignments.status = 'declined'),
      'replaced', (select count(*) from public.pachanga_referee_assignments assignments where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001' and assignments.status = 'replaced'),
      'unassignedMatches', (select count(*) from ordered where not exists (
        select 1 from public.pachanga_referee_assignments assignments
        where assignments.canonical_match_id = ordered.canonical_match_id
          and assignments.status in ('accepted', 'confirmed', 'completed')
      ))
    ),
    'noActiveOverlaps', not exists (
      select 1
      from public.pachanga_referee_assignments first_assignment
      join public.pachanga_referee_assignments second_assignment
        on second_assignment.referee_profile_id = first_assignment.referee_profile_id
        and second_assignment.id > first_assignment.id
        and second_assignment.status in ('accepted', 'confirmed', 'completed')
        and tstzrange(second_assignment.effective_scheduled_start, second_assignment.effective_scheduled_end, '[)')
          && tstzrange(first_assignment.effective_scheduled_start, first_assignment.effective_scheduled_end, '[)')
      where first_assignment.competition_id = 'e4040000-0000-4000-8000-000000000001'
        and second_assignment.competition_id = first_assignment.competition_id
        and first_assignment.status in ('accepted', 'confirmed', 'completed')
    ),
    'oneMainRefereePerMatch', not exists (
      select assignments.canonical_match_id
      from public.pachanga_referee_assignments assignments
      where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001'
        and assignments.assignment_role = 'MAIN_REFEREE'
        and assignments.status in ('accepted', 'confirmed', 'completed')
      group by assignments.canonical_match_id
      having count(*) > 1
    ),
    'overlapRejected', exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001'
        and assignments.status = 'cancelled'
        and assignments.cancel_reason_code = 'demo_conflict_rejected'
    ),
    'profiles', referee_profiles.value,
    'r5LinkedEvents', jsonb_build_object(
      'linked', (
        select count(*)
        from public.pachanga_competition_disciplinary_events events
        where events.competition_id = 'e4040000-0000-4000-8000-000000000001'
          and events.referee_assignment_id is not null
      ),
      'onRefereedMatches', (
        select count(*)
        from public.pachanga_competition_disciplinary_events events
        where events.competition_id = 'e4040000-0000-4000-8000-000000000001'
          and exists (
            select 1 from public.pachanga_referee_assignments assignments
            where assignments.canonical_match_id = events.canonical_match_id
              and assignments.status in ('completed', 'replaced')
          )
      ),
      'unlinkedEventKeys', coalesce((
        select jsonb_agg(events.creation_operation_id order by events.server_sequence, events.id)
        from public.pachanga_competition_disciplinary_events events
        where events.competition_id = 'e4040000-0000-4000-8000-000000000001'
          and events.referee_assignment_id is null
          and exists (
            select 1 from public.pachanga_referee_assignments assignments
            where assignments.canonical_match_id = events.canonical_match_id
              and assignments.status in ('completed', 'replaced')
          )
      ), '[]'::jsonb)
    ),
    'statisticsConverged', not exists (
      select 1
      from referee_refs refs
      join public.pachanga_referee_statistics_snapshots stats
        on stats.referee_profile_id = refs.id
      where stats.checksum <> encode(extensions.digest(convert_to(
        private.pachanga_referee_statistics_document_v1(refs.id)::text,
        'UTF8'
      ), 'sha256'), 'hex')
    )
  ) as value
  from referee_assignments, referee_profiles
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
    'refereeAssignmentKey', events.referee_assignment_id,
    'reportingRefereeNumber', referee_refs.referee_number,
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
  left join referee_refs on referee_refs.id = events.reporting_referee_profile_id
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
    'refereeAssignments', (select count(*) from private.pachanga_referee_operation_receipts where client_metadata ->> 'surface' = 'demo_world_v2' and (action like 'assignment.%' or action like 'terms.%')),
    'refereeOfficiating', (select count(*) from private.pachanga_referee_operation_receipts where client_metadata ->> 'surface' = 'demo_world_v2' and action in ('discipline.record', 'result.observe')),
    'refereePlatform', (select count(*) from private.pachanga_referee_operation_receipts where client_metadata ->> 'surface' = 'demo_world_v2' and action not like 'assignment.%' and action not like 'terms.%' and action not in ('discipline.record', 'result.observe')),
    'scheduling', (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'league_schedule' and client_metadata ->> 'surface' = 'demo_world_v2')
  ),
  'refereeAssignments', referee_assignment_summary.value,
  'roundCount', (select count(distinct round_number) from ordered),
  'standings', standings.value
)
from matches, standings, discipline_events, discipline_counters,
  discipline_sanctions, discipline_service, discipline_appeals,
  discipline_states, discipline_eligibility, referee_assignment_summary;
`;
  const extracted = JSON.parse(psql(["-At", "-c", sql], "extract Demo World V2 authority proof")) as Omit<DemoWorldV2AuthorityProof, "authorityHash" | "configuration" | "database" | "generatedAt" | "migrationCount" | "remoteWrites" | "rpcFamilies" | "version">;
  const payload: Omit<DemoWorldV2AuthorityProof, "authorityHash"> = {
    ...extracted,
    configuration: extractConfigurationAuthorityProof(),
    database: "temporary-local-postgresql",
    generatedAt: "2026-08-26T10:00:00.000Z",
    migrationCount,
    remoteWrites: 0,
    rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5", "R6A"],
    tournament: extractTournamentAuthorityProof(),
    version: 5,
  };
  return assertDemoWorldV2AuthorityProof({
    ...payload,
    authorityHash: demoWorldV2AuthorityHash(payload),
  });
}

async function committedSnapshot(): Promise<DemoWorldV2Snapshot> {
  const read = async <T>(name: string) => JSON.parse(await readFile(path.join(publicRoot, name), "utf8")) as T;
  const [activity, clubsReferees, competitions, configuration, core, manifest, matches, players, tournament] = await Promise.all([
    read<DemoWorldV2Snapshot["activity"]>("activity.json"),
    read<DemoWorldV2Snapshot["clubsReferees"]>("clubs-referees.json"),
    read<DemoWorldV2Snapshot["competitions"]>("competitions.json"),
    read<DemoWorldV2Snapshot["configuration"]>("configuration.json"),
    read<DemoWorldV2Snapshot["core"]>("core.json"),
    read<DemoWorldV2Snapshot["manifest"]>("manifest.json"),
    read<DemoWorldV2Snapshot["matches"]>("matches.json"),
    read<DemoWorldV2Snapshot["players"]>("players.json"),
    read<DemoWorldV2Snapshot["tournament"]>("tournament.json"),
  ]);
  return { activity, clubsReferees, competitions, configuration, core, manifest, matches, players, tournament };
}

async function dropDatabase() {
  try {
    if (admin(
      `select count(*) from pg_database where datname='${databaseName}'`,
      "inspect Demo World V2 database",
    ) === "0") return;
    admin(`alter database ${databaseName} with allow_connections false`, "close Demo World V2 database");
    admin(`select pg_terminate_backend(activity.pid)
      from pg_stat_activity activity
      join pg_roles roles on roles.rolname=activity.usename
      where activity.datname='${databaseName}'
        and activity.pid<>pg_backend_pid()
        and not roles.rolsuper`, "terminate Demo World V2 connections");
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
    { label: "R5 and Configuration Center", names: incremental.filter((name) => name >= "20260825165834" && name < "20260826195034") },
    { label: "R6A Tournament Foundation", names: incremental.filter((name) => name >= "20260826195034") },
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
    psql(["-f", sqlFile("tests/competition-configuration-center-v1-fixture.sql")], "create Demo World V2.3 configuration fixture through League Wizard V2");
    psql(["-f", sqlFile("scripts/demo-world/demo-world-v2-configuration-operations.sql")], "publish Demo World V2.3 custom RuleRevision through Configuration Center V1");
    applyBatch(migrationBatches[8]!.label, migrationBatches[8]!.names);
    psql([
      "-v", "DEMO_WORLD_V2_PERSIST=1",
      "-f", sqlFile("scripts/demo-world/demo-world-v2-tournament-operations.sql"),
    ], "create Demo World V2.4 Tournament through R1, Entries and R6A RPCs");

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
      rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5", "R6A", "LEAGUE_PRIVATE_BETA_V1"],
      snapshotIdentical: verifyOnly,
    })}\n`);
  } finally {
    await dropDatabase();
    await rm(infrastructureDump, { force: true });
  }
}

await main();
