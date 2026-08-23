import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";
import { leagueSchedulingActions } from "../app/league-scheduling-contract";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260823224235_league_scheduling_access_v1.sql",
  commands: "supabase/migrations/20260823224218_league_scheduling_commands_v1.sql",
  hardening: "supabase/migrations/20260823224236_league_scheduling_hardening_v1.sql",
  schema: "supabase/migrations/20260823224156_league_scheduling_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R4B persists normalized plans, revisions, slots, rounds, byes, items and evidence", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_schedule_plans",
    "pachanga_competition_schedule_revisions",
    "pachanga_competition_schedule_slots",
    "pachanga_competition_rounds",
    "pachanga_competition_round_byes",
    "pachanga_competition_schedule_items",
    "pachanga_competition_schedule_validations",
    "pachanga_competition_schedule_conflicts",
    "pachanga_competition_schedule_quality_snapshots",
  ]) assert.match(schema, new RegExp(`create table if not exists (?:public|private)\\.${table}`));
  assert.doesNotMatch(schema, /create table[^;]+(?:league_match|league_result|league_attendance|league_lineup|league_scorer)/i);
});

test("all six R4B flags are false and encode their dependency graph", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "league_scheduling_foundation_enabled",
    "league_schedule_generation_enabled",
    "league_schedule_editing_enabled",
    "league_schedule_publication_enabled",
    "league_public_calendar_enabled",
    "league_canonical_fixture_creation_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /not league_schedule_generation_enabled or league_scheduling_foundation_enabled/);
  assert.match(schema, /not league_schedule_editing_enabled or league_schedule_generation_enabled/);
  assert.match(schema, /not league_canonical_fixture_creation_enabled or league_schedule_publication_enabled/);
});

test("global platform flags use the canonical platform RPC and emit valid R4B invalidations", async () => {
  const [access, staging] = await Promise.all([
    source(paths.access),
    source("tests/league-scheduling-v1-staging-e2e.mjs"),
  ]);
  assert.match(
    access,
    /entity_type in \('league_participation_flags', 'league_scheduling_flags'\)/,
  );
  assert.match(
    access,
    /target_entity_type in \('league_participation_flags', 'league_scheduling_flags'\)/,
  );
  const competitionFlagHelper = staging.slice(
    staging.indexOf("async function setCompetitionFlags"),
    staging.indexOf("async function setParticipationFlags"),
  );
  assert.match(competitionFlagHelper, /command_pachanga_competition_platform_v1/);
  assert.doesNotMatch(competitionFlagHelper, /foundation\(platform/);
});

test("the server owns generation inputs, actor identity, sequence and idempotency", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /pachanga_competition_replay_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /nextval\('private\.pachanga_competition_sequence'\)/);
  assert.match(commands, /pachanga_league_schedule_inputs_v1/);
  assert.match(commands, /league-round-robin-v1/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|actor_id|pairings|canonicalMatchId|conflicts)'/i);
  for (const action of leagueSchedulingActions) assert.match(commands, new RegExp(action.replaceAll(".", "\\.")));
});

test("round robin supports 2-32 entries, one or two legs, byes and mirrored return legs", async () => {
  const [engine, commands] = await Promise.all([
    source("app/league-round-robin-engine.ts"),
    source(paths.commands),
  ]);
  assert.match(engine, /leagueSchedulingMinimumEntries/);
  assert.match(engine, /leagueSchedulingMaximumEntries/);
  assert.match(engine, /rotation\.push\(null\)/);
  assert.match(engine, /awayEntryId: fixture\.homeEntryId/);
  assert.match(commands, /SCHEDULE_ENGINE_CAPACITY_EXCEEDED/);
  assert.match(commands, /pachanga_competition_round_byes/);
  assert.doesNotMatch(commands, /BYE FC|DESCANSA/);
});

test("assignment separates hard legality from weighted explainable quality", async () => {
  const commands = await source(paths.commands);
  const conflictContract = `${await source(paths.schema)}\n${commands}`;
  for (const conflict of [
    "TEAM_UNAVAILABLE", "TEAM_OVERLAP", "VENUE_OVERLAP", "INSUFFICIENT_SLOT_DURATION",
    "EDITION_RANGE", "STAGE_RANGE", "MINIMUM_REST", "MISSING_VENUE", "MISSING_SLOT",
    "DUPLICATE_PAIRING", "ROSTER_NOT_READY", "ENTRY_NOT_ELIGIBLE", "RULE_REVISION_MISMATCH",
  ]) assert.match(conflictContract, new RegExp(conflict));
  assert.match(commands, /SCHEDULE_CAPACITY_DEFICIT/);
  assert.match(commands, /SCHEDULE_UNSATISFIABLE/);
  assert.match(commands, /softPreferenceWeights/);
  assert.match(commands, /preferenceSatisfiedCount/);
  assert.match(commands, /maximumHomeStreak/);
  assert.match(commands, /maximumAwayStreak/);
});

test("Europe Madrid slots and UI labels remain stable across DST and midnight", async () => {
  const [commands, client] = await Promise.all([
    source(paths.commands),
    source("app/_components/league-scheduling-client.tsx"),
  ]);
  assert.match(commands, /\(generated_date \+ local_time_value\) at time zone timezone_value/);
  assert.match(client, /timeZone: timezone \|\| "Europe\/Madrid"/);

  const localParts = (instant: string) => Object.fromEntries(
    new Intl.DateTimeFormat("en-GB", {
      day: "2-digit",
      hour: "2-digit",
      hourCycle: "h23",
      minute: "2-digit",
      month: "2-digit",
      timeZone: "Europe/Madrid",
      year: "numeric",
    }).formatToParts(new Date(instant)).map((part) => [part.type, part.value]),
  );
  for (const [instant, expected] of [
    ["2027-03-27T19:00:00Z", ["27", "20", "00"]],
    ["2027-03-28T18:00:00Z", ["28", "20", "00"]],
    ["2027-10-30T18:00:00Z", ["30", "20", "00"]],
    ["2027-10-31T19:00:00Z", ["31", "20", "00"]],
    ["2027-03-28T22:30:00Z", ["29", "00", "30"]],
    ["2027-10-30T22:30:00Z", ["31", "00", "30"]],
  ] as const) {
    const parts = localParts(instant);
    assert.deepEqual([parts.day, parts.hour, parts.minute], expected, instant);
  }
});

test("manual changes clone immutable revisions and publication is atomic and canonical", async () => {
  const [commands, hardening] = await Promise.all([source(paths.commands), source(paths.hardening)]);
  assert.match(commands, /pachanga_league_schedule_clone_revision_v1/);
  assert.match(commands, /manual_move|manual_swap|home_away_swap|round_rename/);
  assert.match(commands, /pachanga_league_schedule_publish_v1/);
  assert.match(commands, /competition_generated/);
  assert.match(commands, /pachanga_canonical_matches/);
  assert.match(commands, /pachanga_competition_match_contexts/);
  assert.match(commands, /status[^\n]+scheduled/);
  assert.match(commands, /POST_PUBLICATION_CHANGE_REQUIRES_R4C/);
  assert.match(hardening, /SCHEDULE_REVISION_IMMUTABLE/);
  assert.match(hardening, /QUALITY_SNAPSHOT_IMMUTABLE/);
  assert.match(hardening, /guard_r4b_append_only_v1/);
  assert.match(hardening, /archive_pachanga_league_schedule_qa_v1/);
  assert.match(hardening, /R4B_QA_ARCHIVE_SCOPE_FORBIDDEN/);
  assert.match(hardening, /'draft', 'generated', 'validated', 'published', 'cancelled'/);
  assert.match(hardening, /rounds\.status <> 'cancelled'/);
  assert.match(hardening, /to service_role/);
  assert.doesNotMatch(
    hardening.slice(hardening.indexOf("archive_pachanga_league_schedule_qa_v1")),
    /grant execute[\s\S]{0,180}to (?:anon|authenticated)/i,
  );
});

test("publication emits summaries and invalidations without a notification storm", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /pachanga_league_schedule_notify_published_v1/);
  assert.match(commands, /match_competition_schedule_published/);
  assert.match(commands, /league_schedule/);
  assert.match(commands, /league_round/);
  assert.match(commands, /league_team_calendar/);
  assert.doesNotMatch(commands, /foreach[\s\S]{0,240}pachanga_notifications/i);
});

test("read models are scoped, stable and do not expose private constraints publicly", async () => {
  const access = await source(paths.access);
  for (const rpc of [
    "get_pachanga_league_schedule_workbench_v1",
    "get_pachanga_league_schedule_for_competition_v1",
    "get_pachanga_my_league_schedule_v1",
    "get_pachanga_public_league_calendar_v1",
    "get_pachanga_league_round_detail_v1",
    "get_pachanga_platform_league_scheduling_v1",
  ]) assert.match(access, new RegExp(`create or replace function public\\.${rpc}`));
  assert.match(access, /order by plans\.server_sequence desc, plans\.id desc/);
  assert.match(access, /order by slots\.starts_at, slots\.server_sequence, slots\.id/);
  assert.match(access, /plan_row\.status in \('published', 'cancelled'\)/);
  assert.match(access, /ARCHIVED_SNAPSHOT/);
  assert.doesNotMatch(access, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|\)|;|$)/i);
  const publicRead = access.slice(access.indexOf("create or replace function public.get_pachanga_public_league_calendar_v1"), access.indexOf("create or replace function public.get_pachanga_league_round_detail_v1"));
  assert.doesNotMatch(publicRead, /constraint|preference|conflict|roster|quality/i);
});

test("RLS revokes direct writes and keeps private evidence private", async () => {
  const access = await source(paths.access);
  assert.match(access, /revoke all on table public\.pachanga_competition_schedule_plans from public, anon, authenticated/);
  assert.match(access, /revoke all on table private\.pachanga_competition_schedule_conflicts from public, anon, authenticated/);
  assert.match(access, /Authorized actors read schedule plans/);
  assert.match(access, /Schedule managers read slots/);
  assert.doesNotMatch(access, /grant (?:insert|update|delete|all) on table public\.pachanga_competition_schedule_(?:plans|items|slots) to authenticated/i);
});

test("API payloads are whitelisted, no-store and never carry service authority", async () => {
  const [shared, commandRoute, policyContract] = await Promise.all([
    source("app/api/competitions/scheduling/_shared.ts"),
    source("app/api/competitions/scheduling/command/route.ts"),
    source("app/api/client-policy/_contract.ts"),
  ]);
  assert.match(shared, /headers: noStoreHeaders/);
  assert.match(policyContract, /"Cache-Control": "private, no-store/);
  assert.match(shared, /assertOnlyKeys/);
  assert.match(commandRoute, /requireScheduleOrigin/);
  assert.match(commandRoute, /scheduleWriteGate/);
  assert.match(commandRoute, /scheduleCommandPayload/);
  assert.doesNotMatch(`${shared}\n${commandRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  assert.doesNotMatch(shared, /actorId|actor_id|canonicalMatchId|pairings/);
});

test("PWA protects every R4B write and only caches canonical reads", async () => {
  for (const rpc of ["command_pachanga_league_scheduling_v1", "command_pachanga_league_scheduling_platform_v1"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:league-scheduling-command"), true);
  const client = await source("app/_components/league-scheduling-client.tsx");
  assert.match(client, /cache: "no-store"/);
  assert.match(client, /The cache is optional and never authoritative/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /Cambio confirmado por PostgreSQL/);
  assert.match(client, /loadCanonical\(token, actorId, "realtime"\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
});

test("Official UI V2.1 exposes all gated routes and local laboratory scenarios", async () => {
  const [client, css, lab, labLayout] = await Promise.all([
    source("app/_components/league-scheduling-client.tsx"),
    source("app/_components/league-scheduling-client.module.css"),
    source("app/laboratorio-league-scheduling/page.tsx"),
    source("app/laboratorio-league-scheduling/layout.tsx"),
  ]);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /roundRail/);
  assert.match(client, /ConflictSummary/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /overflow-x: auto/);
  assert.match(css, /\.organizerControls\[data-open="true"\]/);
  assert.match(css, /\.portraitDetailBackdrop\[data-open="true"\]/);
  assert.match(css, /\.portraitDetailAction/);
  assert.match(css, /\.landscapeToolsToggle\s*\{[\s\S]*?position:\s*absolute\s*!important/);
  assert.match(css, /\.organizerControls\s*\{[\s\S]*?position:\s*absolute\s*!important/);
  assert.match(css, /\.slotBuilder\s*>\s*div\s*\{\s*grid-template-columns:\s*repeat\(4,/);
  assert.match(css, /max-width:\s*720px[\s\S]*?repeat\(3,\s*minmax\(0,\s*1fr\)\)/);
  assert.match(client, /Cerrar herramientas/);
  assert.match(client, /role="dialog"/);
  assert.match(client, /aria-label="Detalle del partido"/);
  assert.match(client, /Ver detalle/);
  assert.match(client, /scheduleText\(plan\.status\) !== "published"/);
  assert.match(client, /Array\.isArray\(data\.nextValidActions\)\s*\?\s*actions/);
  assert.match(labLayout, /follow: false, index: false/);
  assert.match(lab, /leagueSchedulingScenarios/);
  for (const route of [
    "app/competiciones/[competition]/gestion/calendario/page.tsx",
    "app/competiciones/[competition]/calendario/page.tsx",
    "app/competiciones/[competition]/jornadas/[round]/page.tsx",
    "app/mis-competiciones/calendario/page.tsx",
  ]) assert.match(await source(route), /LeagueSchedulingClient/);
});

test("Control Center keeps legacy canonical health separate and controls six R4B flags", async () => {
  const [page, client, route] = await Promise.all([
    source("app/admin/competitions/page.tsx"),
    source("app/admin/competitions/competition-admin-client.tsx"),
    source("app/api/platform-admin/competitions/route.ts"),
  ]);
  assert.match(page, /League Scheduling R4B/);
  assert.match(page, /generatedCanonicalMatches/);
  assert.match(client, /league_scheduling_flags\.set/);
  for (const flag of ["scheduleFoundationEnabled", "scheduleGenerationEnabled", "scheduleEditingEnabled", "schedulePublicationEnabled", "schedulePublicCalendarEnabled", "scheduleCanonicalFixtureCreationEnabled"]) assert.match(client, new RegExp(flag));
  assert.match(route, /command_pachanga_league_scheduling_platform_v1/);
});

test("R4B does not write results, standings, Rating, discipline, rewards, conduct, billing or ranking", async () => {
  const combined = `${await source(paths.schema)}\n${await source(paths.commands)}\n${await source(paths.access)}\n${await source(paths.hardening)}`;
  for (const table of [
    "pachanga_player_rating_snapshots", "pachanga_individual_rating_evidence", "pachanga_match_participants",
    "pachanga_match_scorers", "pachanga_external_results", "pachanga_disciplinary_events",
    "pachanga_reward_grants", "pachanga_conduct_reports", "pachanga_stripe_webhook_events",
    "pachanga_provincial_ranking_entries",
  ]) assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.|private\\.)?${table}`, "i"));
  assert.doesNotMatch(combined, /CRON_SECRET|canonical\.backfill|standing_snapshot|sporting_result/i);
});

test("bootstrap, concurrency, scale, performance and staging remain explicit release gates", async () => {
  const [bootstrap, concurrency, scale, performance, staging, packageJson] = await Promise.all([
    source("tests/league-scheduling-v1-bootstrap.mjs"),
    source("tests/league-scheduling-v1-concurrency.mjs"),
    source("tests/league-scheduling-v1-scale.mjs"),
    source("tests/league-scheduling-v1-performance.mjs"),
    source("tests/league-scheduling-v1-staging-e2e.mjs"),
    source("package.json"),
  ]);
  assert.match(bootstrap, /upgradeFromLedger: 119/);
  assert.match(bootstrap, /schemasEqual: true/);
  assert.match(concurrency, /publishRace/);
  assert.match(scale, /95000/);
  assert.match(performance, /teamCount: 32/);
  assert.match(performance, /get_pachanga_public_league_calendar_v1/);
  assert.match(staging, /R4B_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(staging, /async function selectClubOwner/);
  assert.match(staging, /activeDrafts < 3 && recentCreations < 5/);
  assert.match(staging, /R4B_STAGING_CLUB_CREATOR_POOL_EXHAUSTED/);
  assert.match(packageJson, /test:league-scheduling:bootstrap/);
});
