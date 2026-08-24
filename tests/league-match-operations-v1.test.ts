import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { leagueMatchOperationsActions } from "../app/league-match-operations-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260824165810_league_match_operations_access_v1.sql",
  commands: "supabase/migrations/20260824165804_league_match_operations_commands_v1.sql",
  hardening: "supabase/migrations/20260824165815_league_match_operations_hardening_v1.sql",
  schema: "supabase/migrations/20260824165759_league_match_operations_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R4C extends CanonicalMatch with normalized squads, results, decisions and standings", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_match_squads",
    "pachanga_competition_match_squad_revisions",
    "pachanga_competition_match_squad_members",
    "pachanga_competition_match_sheets",
    "pachanga_competition_sporting_results",
    "pachanga_competition_sporting_result_revisions",
    "pachanga_competition_sporting_result_scorers",
    "pachanga_competition_result_responses",
    "pachanga_competition_official_result_decisions",
    "pachanga_competition_standing_states",
    "pachanga_competition_standing_snapshots",
    "pachanga_competition_standing_rows",
    "pachanga_competition_tie_break_explanations",
    "pachanga_competition_persisted_draw_lots",
    "pachanga_competition_standing_rebuild_receipts",
  ]) assert.match(schema, new RegExp(`create table (?:if not exists )?(?:public|private)\\.${table}`));
  assert.doesNotMatch(schema, /create table[^;]+(?:league_matches|league_attendance|league_players|league_teams)/i);
  assert.match(schema, /competition_match_context_id uuid not null references public\.pachanga_competition_match_contexts/);
});

test("all eight R4C flags default off and preserve the dependency graph", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "league_match_operations_foundation_enabled",
    "league_match_squads_enabled",
    "league_match_attendance_enabled",
    "league_sporting_results_enabled",
    "league_result_confirmation_enabled",
    "league_official_results_enabled",
    "league_standings_enabled",
    "league_public_standings_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /not league_result_confirmation_enabled or league_sporting_results_enabled/);
  assert.match(schema, /not league_official_results_enabled or \([\s\S]*league_result_confirmation_enabled/);
  assert.match(schema, /not league_standings_enabled or league_official_results_enabled/);
  assert.match(schema, /not league_public_standings_enabled or league_standings_enabled/);
});

test("the server owns actor, rule revision, time, sequence, idempotency and stale-write rejection", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /operation_id uuid[\s\S]+aggregate_id uuid[\s\S]+expected_revision bigint[\s\S]+action text[\s\S]+command_payload jsonb/);
  assert.match(commands, /declare actor_id uuid := auth\.uid\(\)/);
  assert.match(commands, /pachanga_league_match_operation_replay_v1/);
  assert.match(commands, /pachanga_league_match_request_hash_v1/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /clock_timestamp\(\)/);
  assert.match(commands, /nextval\('private\.pachanga_competition_sequence'\)/);
  assert.match(commands, /rule_revision_id/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|actor_id|serverSequence|confirmedAt|ruleRevisionId)'/i);
  for (const action of leagueMatchOperationsActions) assert.match(commands, new RegExp(action.replaceAll(".", "\\.")));
});

test("R4C is LEAGUE-only and explicitly fails closed for future domains", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /competition_type <> 'LEAGUE'[\s\S]+FEATURE_NOT_AVAILABLE/);
  for (const futureAction of [
    "match.postpone", "match.suspend", "match.abandon", "match.cancel",
    "referee.assign", "referee.report", "temporary_player.add",
    "discipline.apply", "points_adjustment.apply",
  ]) assert.match(commands, new RegExp(futureAction.replaceAll(".", "\\.")));
  assert.match(commands, /FEATURE_NOT_AVAILABLE_UNTIL_R5/);
});

test("attendance reuses canonical match participants instead of creating a second ledger", async () => {
  const [schema, commands] = await Promise.all([source(paths.schema), source(paths.commands)]);
  assert.doesNotMatch(schema, /create table (?:if not exists )?(?:public|private)\.[a-z0-9_]*attendance[a-z0-9_]*/i);
  assert.match(commands, /pachanga_match_participants/);
  assert.match(commands, /attendance\.set/);
  assert.match(commands, /attendance\.close/);
});

test("sporting submissions are bilateral and scorers remain side-scoped", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /confirmationPolicy/);
  assert.match(commands, /sporting_result\.accept/);
  assert.match(commands, /sporting_result\.propose_change/);
  assert.match(commands, /sporting_result\.dispute/);
  assert.match(commands, /R4C_SCORER_NOT_IN_LOCKED_SQUAD/);
  assert.match(commands, /squads\.entry_id = target_proposing_entry_id/);
  assert.match(commands, /R4C_SCORER_TOTAL_EXCEEDS_SCORE/);
});

test("official decisions and standings rebuild commit as one coordinated server transaction", async () => {
  const commands = await source(paths.commands);
  const decisionStart = commands.indexOf("create or replace function private.pachanga_league_official_result_decide_v1");
  const decisionEnd = commands.indexOf("revoke all on function private.pachanga_league_official_result_decide_v1", decisionStart);
  const decision = commands.slice(decisionStart, decisionEnd);
  assert.match(decision, /insert into public\.pachanga_competition_official_result_decisions/);
  assert.match(decision, /insert into private\.pachanga_competition_official_result_evidence/);
  assert.match(decision, /pachanga_league_standings_rebuild_v1/);
  assert.match(commands, /join public\.pachanga_competition_official_result_decisions decisions[\s\S]+decisions\.id = sheets\.active_official_decision_id/);
  assert.match(commands, /PERSISTED_DRAW_LOT/);
  assert.match(commands, /HEAD_TO_HEAD_POINTS/);
});

test("canonical snapshots expose safe roster context and permission-aware actions without private evidence", async () => {
  const [commands, access] = await Promise.all([source(paths.commands), source(paths.access)]);
  assert.match(commands, /'eligibleRoster', jsonb_build_object/);
  assert.match(commands, /'competition', \(select jsonb_build_object/);
  assert.match(commands, /'ruleRevision', \(select jsonb_build_object/);
  assert.match(commands, /'nextValidActions', next_actions/);
  assert.match(commands, /pachanga_competition_can_v1\([^;]+target_actor_id/);
  const snapshotStart = commands.indexOf("create or replace function private.pachanga_league_match_snapshot_v1");
  const snapshotEnd = commands.indexOf("revoke all on function private.pachanga_league_match_snapshot_v1", snapshotStart);
  assert.doesNotMatch(commands.slice(snapshotStart, snapshotEnd), /evidenceReference|privateReason|created_by/);
  assert.doesNotMatch(access, /evidenceReference|privateReason/);
  assert.doesNotMatch(access, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|\)|;|$)/i);
  assert.match(access, /server_sequence desc, [^\n]*id desc/);
});

test("RLS revokes direct writes and keeps official evidence service-only", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_match_squads",
    "pachanga_competition_sporting_results",
    "pachanga_competition_official_result_decisions",
    "pachanga_competition_standing_snapshots",
  ]) assert.match(schema, new RegExp(`revoke all on table public\\.${table} from public, anon, authenticated`));
  assert.match(schema, /revoke all on table private\.pachanga_competition_official_result_evidence from public, anon, authenticated/);
  assert.match(schema, /grant all on table private\.pachanga_competition_official_result_evidence to service_role/);
  assert.doesNotMatch(schema, /grant (?:insert|update|delete|all) on table public\.pachanga_competition_(?:match_squads|sporting_results|official_result_decisions|standing_snapshots) to authenticated/i);
});

test("the browser sends semantic intent only and rejects calculated or forged authority", async () => {
  const shared = await source("app/api/competitions/match-operations/_shared.ts");
  assert.match(shared, /assertOnlyKeys\(input, \["entryId", "reason", "rosterMemberId", "status"\]\)/);
  assert.match(shared, /assertOnlyKeys\(item, \["displayName", "goals", "rosterMemberId", "unknownSlot"\]\)/);
  assert.match(shared, /input\.pointsAdjustments != null[\s\S]+input\.pointsAdjustments\.length > 0[\s\S]+FEATURE_NOT_AVAILABLE/);
  assert.match(shared, /privateEvidence[\s\S]+evidenceReference[\s\S]+privateReason/);
  assert.doesNotMatch(shared, /actorId|actor_id|serverSequence|confirmedAt|ruleRevisionId|standingsSnapshot|rating/i);
});

test("API routes are no-store, same-origin, PWA-gated and carry no service role", async () => {
  const [shared, commandRoute, platformRoute] = await Promise.all([
    source("app/api/competitions/match-operations/_shared.ts"),
    source("app/api/competitions/match-operations/command/route.ts"),
    source("app/api/platform-admin/competitions/route.ts"),
  ]);
  assert.match(shared, /headers: noStoreHeaders/);
  assert.match(shared, /assertOnlyKeys/);
  assert.match(commandRoute, /requireLeagueMatchOrigin/);
  assert.match(commandRoute, /leagueMatchWriteGate/);
  assert.match(commandRoute, /leagueMatchCommandPayload/);
  assert.match(platformRoute, /command_pachanga_league_match_operations_platform_v1/);
  assert.doesNotMatch(`${shared}\n${commandRoute}\n${platformRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
});

test("PWA blocks every R4C write while canonical reads remain locally cacheable", async () => {
  for (const rpc of ["command_pachanga_league_match_operations_v1", "command_pachanga_league_match_operations_platform_v1"]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:league-match-operations-command"), true);
  const client = await source("app/_components/league-match-operations-client.tsx");
  assert.match(client, /cache: "no-store"/);
  assert.match(client, /This read cache is optional and never authoritative/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /Cambio confirmado por PostgreSQL/);
  assert.match(client, /status === "SUBSCRIBED"/);
  assert.match(client, /loadCanonical\(token, actorId, "realtime"\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
});

test("Official UI exposes match, result desk, standings, rounds, my matches and an isolated lab", async () => {
  const [client, css, lab, labLayout, roundClient] = await Promise.all([
    source("app/_components/league-match-operations-client.tsx"),
    source("app/_components/league-match-operations-client.module.css"),
    source("app/laboratorio-league-match-operations/page.tsx"),
    source("app/laboratorio-league-match-operations/layout.tsx"),
    source("app/_components/league-scheduling-client.tsx"),
  ]);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /Mesa de resultados/);
  assert.match(client, /Clasificación/);
  assert.match(client, /Mis partidos de Liga/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(lab, /previewData=/);
  assert.match(lab, /Laboratorio R4C/);
  assert.match(labLayout, /index: false/);
  assert.match(roundClient, /Abrir operación del partido/);
  for (const route of [
    "app/competiciones/[competition]/partidos/[match]/page.tsx",
    "app/competiciones/[competition]/gestion/resultados/page.tsx",
    "app/competiciones/[competition]/clasificacion/page.tsx",
    "app/competiciones/[competition]/jornadas/[round]/page.tsx",
    "app/mis-competiciones/partidos/page.tsx",
  ]) assert.match(await source(route), /export default/);
});

test("Control Center audits and gates all R4C switches through its platform RPC", async () => {
  const [data, page, client, route, access] = await Promise.all([
    source("app/admin/_lib/platform-data.ts"),
    source("app/admin/competitions/page.tsx"),
    source("app/admin/competitions/competition-admin-client.tsx"),
    source("app/api/platform-admin/competitions/route.ts"),
    source(paths.access),
  ]);
  assert.match(data, /get_pachanga_platform_league_match_operations_v1/);
  assert.match(page, /League Match Operations R4C/);
  assert.match(client, /league_match_operations_flags\.set/);
  assert.match(route, /command_pachanga_league_match_operations_platform_v1/);
  assert.match(access, /private\.pachanga_platform_require_v1\('flags\.write'\)/);
});

test("R4C does not write Rating, rewards, Conduct, billing, referee assignments or discipline", async () => {
  const sql = `${await source(paths.schema)}\n${await source(paths.commands)}\n${await source(paths.access)}\n${await source(paths.hardening)}`;
  for (const forbiddenWrite of [
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_player_rating/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_player_assessment/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_reward/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_conduct/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_billing/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_referee_assignment/i,
    /(?:insert into|update|delete from)\s+(?:public\.)?pachanga_competition_discipline/i,
  ]) assert.doesNotMatch(sql, forbiddenWrite);
  assert.match(sql, /discipline_validation_status text not null default 'NOT_AVAILABLE'/);
});
