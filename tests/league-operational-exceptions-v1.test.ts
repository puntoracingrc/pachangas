import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  leagueOperationalExceptionActions,
  leagueOperationalExceptionsRealtimeTable,
} from "../app/league-operational-exceptions-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260824230733_league_operational_exceptions_access_v1.sql",
  commands: "supabase/migrations/20260824230732_league_operational_exceptions_commands_v1.sql",
  databaseSuite: "tests/league-operational-exceptions-v1-db.sql",
  hardening: "supabase/migrations/20260824230734_league_operational_exceptions_hardening_v1.sql",
  schema: "supabase/migrations/20260824230726_league_operational_exceptions_schema_v1.sql",
  venueStatusFix: "supabase/migrations/20260825021800_league_operational_exceptions_venue_status_fix_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R4D normalizes fixture changes, requests, incidents, suspensions and decisions", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_fixture_changes",
    "pachanga_competition_fixture_change_revisions",
    "pachanga_competition_postponement_requests",
    "pachanga_competition_postponement_responses",
    "pachanga_competition_venue_change_requests",
    "pachanga_competition_venue_condition_decisions",
    "pachanga_competition_late_arrival_incidents",
    "pachanga_competition_no_show_incidents",
    "pachanga_competition_match_suspensions",
    "pachanga_competition_match_resumption_decisions",
    "pachanga_competition_administrative_decisions",
    "pachanga_competition_administrative_effects",
  ]) assert.match(schema, new RegExp(`create table (?:if not exists )?public\\.${table}`));
  assert.match(schema, /create table private\.pachanga_competition_operational_evidence/);
  assert.doesNotMatch(schema, /create table[^;]+(?:league_matches|league_players|league_teams)/i);
});

test("all nine R4D flags default off and preserve their dependency graph", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "league_operational_exceptions_foundation_enabled",
    "league_postponements_enabled",
    "league_rescheduling_enabled",
    "league_venue_changes_enabled",
    "league_late_arrival_enabled",
    "league_no_show_enabled",
    "league_match_suspensions_enabled",
    "league_administrative_decisions_enabled",
    "league_public_exception_status_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /not league_operational_exceptions_foundation_enabled[\s\S]+league_match_operations_foundation_enabled/);
  assert.match(schema, /not league_no_show_enabled or \([\s\S]+league_late_arrival_enabled[\s\S]+league_administrative_decisions_enabled/);
});

test("R4D preserves the original R4B schedule and overlays effective revisions", async () => {
  const [schema, commands, access] = await Promise.all([
    source(paths.schema), source(paths.commands), source(paths.access),
  ]);
  assert.match(schema, /original_scheduled_start/);
  assert.match(schema, /effective_scheduled_start/);
  assert.match(schema, /supersedes_fixture_change_id/);
  assert.match(access, /'originalSchedule'/);
  assert.match(access, /'effectiveSchedule'/);
  assert.doesNotMatch(commands, /(?:update|delete from)\s+public\.pachanga_competition_schedule_(?:plans|revisions|items|rounds)/i);
  assert.match(commands, /schedule_item_id/);
});

test("R4D normalizes inherited R4B label-only venues before direct rescheduling", async () => {
  const venueStatusFix = await source(paths.venueStatusFix);
  assert.match(venueStatusFix, /normalized_change_type = 'RESCHEDULE'/);
  assert.match(venueStatusFix, /target_venue_id is not null then 'SAVED'/);
  assert.match(venueStatusFix, /target_venue_label[\s\S]+then 'LABEL'/);
  assert.match(venueStatusFix, /else 'TBD'/);
});

test("the server owns actor, policy, time, sequence, idempotency and stale-write rejection", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /operation_id uuid[\s\S]+aggregate_id uuid[\s\S]+expected_revision bigint[\s\S]+action text[\s\S]+command_payload jsonb/);
  assert.match(commands, /declare actor_id uuid := auth\.uid\(\)/);
  assert.match(commands, /pachanga_league_operational_replay_v1/);
  assert.match(commands, /pachanga_league_operational_request_hash_v1/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /clock_timestamp\(\)/);
  assert.match(commands, /nextval\('private\.pachanga_competition_sequence'\)/);
  assert.match(commands, /pachanga_league_operational_policy_v1/);
  assert.match(commands, /server_now < context_row\.scheduled_start/);
  assert.doesNotMatch(commands, /make_interval\(\s*(?:mins|hours)\s*=>\s*(?:5|10|15|24|48|72)\s*\)/i);
  for (const action of leagueOperationalExceptionActions) {
    assert.match(commands, new RegExp(action.replaceAll(".", "\\.")));
  }
});

test("the isolated SQL suite replays every R4D action with one receipt and event", async () => {
  const databaseSuite = await source(paths.databaseSuite);
  assert.match(databaseSuite, /response = replay/);
  assert.match(databaseSuite, /receipt_count_before = 1 and event_count_before = 1/);
  assert.match(databaseSuite, /notification_count_before/);
  for (const action of leagueOperationalExceptionActions) {
    const escaped = action.replaceAll(".", "\\.");
    assert.match(
      databaseSuite,
      new RegExp(`(?:command_replay|service_command_replay)\\([\\s\\S]{0,700}?'${escaped}'`),
      `${action} must have an idempotent replay story`,
    );
  }
});

test("R4D limits team operations to owners and PRIMARY_DELEGATE and adds an operations manager", async () => {
  const commands = await source(paths.commands);
  const roleStart = commands.indexOf("when 'competition_operations_manager'");
  const roleEnd = commands.indexOf("when 'competition_schedule_manager'", roleStart);
  const roleBlock = commands.slice(roleStart, roleEnd);
  assert.match(commands, /TEAM_OWNER', 'PRIMARY_DELEGATE/);
  assert.match(roleBlock, /operations_read/);
  assert.match(roleBlock, /operations_manage/);
  assert.doesNotMatch(roleBlock, /billing|rules|discipline/);
});

test("no-show and suspension official results are derived from server evidence", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /pachanga_league_operational_no_show_result_v1/);
  assert.match(commands, /noShowWinnerScore/);
  assert.match(commands, /noShowLoserScore/);
  assert.match(commands, /pachanga_league_operational_suspension_result_v1/);
  assert.match(commands, /partialScoreHome/);
  assert.match(commands, /partialScoreAway/);
  assert.match(commands, /sporting_score_home/);
  assert.match(commands, /pachanga_league_standings_rebuild_v1/);
  assert.match(commands, /R4D_CLIENT_AUTHORITY_FIELD_FORBIDDEN/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:scoreHome|scoreAway|effectiveScoreHome|effectiveScoreAway)'/i);
});

test("typed administrative effects fail closed for R5 and billing", async () => {
  const commands = await source(paths.commands);
  for (const effect of [
    "RESCHEDULE_MATCH", "CHANGE_VENUE", "CANCEL_MATCH", "RESUME_FROM_MINUTE",
    "ORDER_REPLAY", "SET_OFFICIAL_RESULT", "ANNUL_OFFICIAL_RESULT",
  ]) assert.match(commands, new RegExp(effect));
  for (const forbidden of [
    "DEDUCT_POINTS", "CREATE_SANCTION", "REVERSE_SANCTION_SERVICE",
    "CREATE_COMPETITION_CHARGE", "CREATE_COMPETITION_CREDIT",
  ]) assert.match(commands, new RegExp(forbidden));
  assert.match(commands, /FEATURE_NOT_AVAILABLE_UNTIL_R5/);
});

test("replays and resumptions keep one CanonicalMatch and the partial score lineage", async () => {
  const [schema, commands] = await Promise.all([source(paths.schema), source(paths.commands)]);
  assert.match(schema, /reuse_canonical_match boolean not null default true/);
  assert.match(schema, /check \(reuse_canonical_match\)/);
  assert.match(commands, /sameCanonicalMatch', true/);
  assert.match(commands, /partialResultRevisionId/);
  assert.doesNotMatch(commands, /insert into public\.pachanga_canonical_matches/i);
});

test("public reads expose status and schedules without evidence or reporter identity", async () => {
  const access = await source(paths.access);
  const publicStart = access.indexOf("create or replace function public.get_pachanga_public_league_fixture_status_v1");
  const publicEnd = access.indexOf("revoke all on function public.get_pachanga_public_league_fixture_status_v1", publicStart);
  const publicRead = access.slice(publicStart, publicEnd);
  assert.match(publicRead, /originalSchedule/);
  assert.match(publicRead, /effectiveSchedule/);
  assert.match(publicRead, /statusLabel/);
  assert.doesNotMatch(publicRead, /evidence|reasonText|reportedBy|requestedBy|decidedBy/i);
  assert.doesNotMatch(access, /order by\s+created_at\s+desc\s*(?:limit|\)|;|$)/i);
  assert.match(access, /server_sequence desc, [^\n]*id desc/);
});

test("RLS revokes direct writes and keeps operational evidence private", async () => {
  const schema = await source(paths.schema);
  assert.match(schema, /enable row level security/);
  assert.match(schema, /revoke all on table public\.%I from anon, authenticated/);
  assert.match(schema, /revoke all on table private\.pachanga_competition_operational_evidence from anon, authenticated/);
  assert.match(schema, /grant select, insert, update, delete on table private\.pachanga_competition_operational_evidence to service_role/);
  assert.doesNotMatch(schema, /grant (?:insert|update|delete|all) on table public\.pachanga_competition_(?:fixture_changes|postponement_requests|late_arrival_incidents|no_show_incidents|match_suspensions|administrative_decisions) to authenticated/i);
});

test("the browser sends semantic intent only through a no-store authenticated API", async () => {
  const [shared, route] = await Promise.all([
    source("app/api/competitions/operational-exceptions/_shared.ts"),
    source("app/api/competitions/operational-exceptions/command/route.ts"),
  ]);
  assert.match(shared, /const actionKeys/);
  assert.match(shared, /Object\.keys\(input\)\.some/);
  assert.match(shared, /headers: noStoreHeaders/);
  assert.match(route, /requireLeagueOperationalOrigin/);
  assert.match(route, /leagueOperationalWriteGate/);
  assert.match(route, /leagueOperationalCommandPayload/);
  assert.doesNotMatch(`${shared}\n${route}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
});

test("PWA blocks R4D writes and keeps optional read cache non-authoritative", async () => {
  for (const rpc of [
    "command_pachanga_league_operational_exceptions_v1",
    "command_pachanga_league_operational_exceptions_platform_v1",
  ]) {
    assert.equal(
      classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }),
      `rpc:${rpc}`,
    );
  }
  assert.equal(isKnownClientWriteOperation("api:league-operational-exceptions-command"), true);
  const client = await source("app/_components/league-operational-exceptions-client.tsx");
  assert.match(client, /Optional read cache only\. PostgreSQL remains authoritative/);
  assert.match(client, /navigator\.onLine/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /Cambio confirmado por PostgreSQL/);
  assert.match(client, /status === "SUBSCRIBED"/);
  assert.match(client, /loadCanonical\(token, actorId, "realtime"\)/);
  assert.match(client, /\["cancelled", "official", "retired"\]\.includes\(status \|\| publicStatus\)/);
  assert.doesNotMatch(client, /surface === "public" \|\|/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
});

test("Realtime uses invalidation plus refetch rather than WAL payload authority", async () => {
  const [client, access] = await Promise.all([
    source("app/_components/league-operational-exceptions-client.tsx"),
    source(paths.access),
  ]);
  assert.equal(leagueOperationalExceptionsRealtimeTable, "pachanga_competition_invalidations");
  assert.match(client, /leagueOperationalExceptionsRealtimeTable/);
  assert.match(client, /status === "SUBSCRIBED"[\s\S]+loadCanonical\(token, actorId, "realtime"\)/);
  assert.match(client, /if \(!supabase\) return/);
  assert.doesNotMatch(client, /if \(!supabase \|\| !token\) return/);
  assert.match(client, /addEventListener\("online", reconcile\)/);
  assert.match(access, /insert into public\.pachanga_competition_invalidations/);
});

test("Official UI includes all required product surfaces and an isolated noindex lab", async () => {
  const [client, css, lab, labLayout] = await Promise.all([
    source("app/_components/league-operational-exceptions-client.tsx"),
    source("app/_components/league-operational-exceptions-client.module.css"),
    source("app/laboratorio-league-operational-exceptions/page.tsx"),
    source("app/laboratorio-league-operational-exceptions/layout.tsx"),
  ]);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /ProductState/);
  assert.match(client, /ProductFeedback/);
  assert.match(client, /managesEntry/);
  assert.match(client, /ORGANIZER_APPROVAL/);
  assert.match(client, /suspension\.schedule_resume/);
  assert.match(client, /administrative_decision\.publish/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(css, /\.commandBand[\s\S]+min-width: 0/);
  assert.match(css, /\.formGrid[\s\S]+max-width: 100%[\s\S]+min-width: 0/);
  assert.match(css, /\.commandGroups > div[\s\S]+min-width: 0/);
  assert.match(lab, /previewData=/);
  assert.match(labLayout, /index: false/);
  for (const route of [
    "app/competiciones/[competition]/partidos/[match]/operaciones/page.tsx",
    "app/competiciones/[competition]/partidos/[match]/estado/page.tsx",
    "app/competiciones/[competition]/gestion/aplazamientos/page.tsx",
    "app/competiciones/[competition]/gestion/incidencias/page.tsx",
    "app/competiciones/[competition]/gestion/decisiones/page.tsx",
    "app/mis-competiciones/solicitudes/page.tsx",
  ]) assert.match(await source(route), /export default/);
});

test("Control Center audits and gates all R4D flags through its platform RPC", async () => {
  const [data, page, client, route, access] = await Promise.all([
    source("app/admin/_lib/platform-data.ts"),
    source("app/admin/competitions/page.tsx"),
    source("app/admin/competitions/competition-admin-client.tsx"),
    source("app/api/platform-admin/competitions/route.ts"),
    source(paths.access),
  ]);
  assert.match(data, /get_pachanga_platform_league_operational_exceptions_v1/);
  assert.match(page, /League Operational Exceptions R4D/);
  assert.match(client, /league_operational_exceptions_flags\.set/);
  assert.match(route, /command_pachanga_league_operational_exceptions_platform_v1/);
  assert.match(access, /private\.pachanga_platform_require_v1\('flags\.write'\)/);
});

test("R4D does not write Rating, rewards, Conduct, discipline, billing or referee assignments", async () => {
  const sql = `${await source(paths.schema)}\n${await source(paths.commands)}\n${await source(paths.access)}\n${await source(paths.hardening)}`;
  for (const forbiddenWrite of [
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_player_(?:rating|assessment)/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_(?:reward|achievement)/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_conduct/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_competition_discipline/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_(?:billing|payment|charge|credit)/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_referee_assignment/i,
  ]) assert.doesNotMatch(sql, forbiddenWrite);
});

test("notifications are idempotent, scoped and never broadcast to the full roster", async () => {
  const hardening = await source(paths.hardening);
  assert.match(hardening, /pachanga_league_operational_event_notifications_v1/);
  assert.match(hardening, /PRIMARY_DELEGATE/);
  assert.match(hardening, /'r4d:' \|\| target_operation_id::text \|\| ':' \|\| target_kind \|\| ':' \|\| recipient\.user_id::text/);
  assert.doesNotMatch(hardening, /pachanga_competition_roster_members/);
  assert.doesNotMatch(hardening, /evidenceRefs|reasonText|reportedBy|requestedBy|decidedBy/i);
});
