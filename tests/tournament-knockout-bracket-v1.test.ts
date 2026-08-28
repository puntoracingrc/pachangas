import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  classifySupabaseWrite,
  isKnownClientWriteOperation,
} from "../app/pwa-write-classifier";
import {
  buildTournamentKnockoutReservationIntent,
  tournamentKnockoutActions,
  tournamentKnockoutTopology,
} from "../app/tournament-knockout-contract";

const migrations = [
  "supabase/migrations/20260827205347_tournament_knockout_bracket_authority_v1.sql",
  "supabase/migrations/20260827205351_tournament_knockout_progression_results_v1.sql",
  "supabase/migrations/20260827205356_tournament_knockout_canonical_match_adapter_v1.sql",
  "supabase/migrations/20260827205359_tournament_knockout_read_models_hub_v1.sql",
  "supabase/migrations/20260827205403_tournament_knockout_access_realtime_v1.sql",
  "supabase/migrations/20260827205409_tournament_knockout_hardening_flags_v1.sql",
] as const;
const compatibilityMigration =
  "supabase/migrations/20260828045324_tournament_knockout_flag_authority_compatibility_v1.sql";

function source(path: string) {
  return readFile(new URL(`../${path}`, import.meta.url), "utf8");
}

test("R6C owns exactly six forward migrations after ledger 169", async () => {
  assert.equal(migrations.length, 6);
  const sql = (await Promise.all(migrations.map(source))).join("\n");
  for (const entity of [
    "pachanga_tournament_brackets",
    "pachanga_tournament_bracket_revisions",
    "pachanga_tournament_bracket_nodes",
    "pachanga_tournament_bracket_node_slots",
    "pachanga_tournament_bracket_advance_decisions",
    "pachanga_tournament_completion_snapshots",
  ]) assert.match(sql, new RegExp(`create table public\\.${entity}`));
  assert.doesNotMatch(sql, /create table (?:public\.)?(?:TournamentMatch|TournamentResult|TournamentReferee|TournamentDiscipline|TournamentPlayer)/i);
});

test("the post-release compatibility migration preserves R6C flags across legacy platform writes", async () => {
  const sql = await source(compatibilityMigration);
  assert.match(sql, /coalesce\(\s*current_setting\('pachangas\.r6c_flag_authority', true\) = 'on',\s*false\s*\)/);
  assert.match(sql, /previous_r6c_authority text := current_setting/);
  assert.match(sql, /set_config\('pachangas\.r6c_flag_authority', 'on', true\)/);
  assert.match(sql, /set_config\(\s*'pachangas\.r6c_flag_authority',\s*coalesce\(previous_r6c_authority, 'off'\),\s*true\s*\)/);
  assert.match(sql, /new\.tournament_knockout_foundation_enabled := old\.tournament_knockout_foundation_enabled/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table/i);
});

test("the client exposes only the thirteen semantic knockout commands", () => {
  assert.deepEqual(tournamentKnockoutActions, [
    "bracket.activate", "bracket.reserve_slot", "bracket.node.resolve",
    "bracket.node.generate_match", "bracket.node.invalidate",
    "bracket.result.advance", "bracket.result.recompute",
    "bracket.admin.replace_downstream", "bracket.complete_round",
    "bracket.lock_round", "tournament.completion.rebuild",
    "tournament.complete", "tournament.lock",
  ]);
});

test("single-match topology covers 4, 8, 16 and 14-of-16 with optional third place", () => {
  assert.deepEqual(tournamentKnockoutTopology(4).rounds.map((round) => round.code), ["SEMIFINAL", "FINAL"]);
  assert.equal(tournamentKnockoutTopology(4).operationalMatches, 3);
  assert.equal(tournamentKnockoutTopology(8).operationalMatches, 7);
  assert.deepEqual(tournamentKnockoutTopology(16).rounds.map((round) => round.matchCount), [8, 4, 2, 1]);
  assert.deepEqual(tournamentKnockoutTopology(16, 14), {
    bracketSize: 16,
    byes: 2,
    operationalMatches: 13,
    participantCount: 14,
    roundCount: 4,
    rounds: [
      { code: "ROUND_OF_16", matchCount: 8, order: 1 },
      { code: "QUARTERFINAL", matchCount: 4, order: 2 },
      { code: "SEMIFINAL", matchCount: 2, order: 3 },
      { code: "FINAL", matchCount: 1, order: 4 },
    ],
    thirdPlaceMatches: 0,
  });
  assert.equal(tournamentKnockoutTopology(8, 8, true).thirdPlaceMatches, 1);
  assert.throws(() => tournamentKnockoutTopology(12), /TOURNAMENT_KNOCKOUT_TOPOLOGY_INVALID/);
});

test("reservation intent derives server-safe timestamps without winner or score fields", () => {
  const intent = buildTournamentKnockoutReservationIntent({
    durationMinutes: 90,
    nodeId: "00000000-0000-0000-0000-000000000001",
    startsAt: "2027-06-12T18:00:00.000Z",
    timezone: "Europe/Madrid",
    venueLabel: "Pista Central",
  });
  assert.equal(intent.endsAt, "2027-06-12T19:30:00.000Z");
  assert.equal(intent.resourceKey, "knockout:00000000-0000-0000-0000-000000000001");
  assert.equal("winnerEntryId" in intent, false);
  assert.equal("scoreHome" in intent, false);
});

test("server payload allowlists exclude winner, champion and downstream authority", async () => {
  const shared = await source("app/api/tournaments/_shared.ts");
  assert.match(shared, /TOURNAMENT_KNOCKOUT_PAYLOAD_FIELD_NOT_ALLOWED/);
  assert.match(shared, /new Set\(\["officialDecisionId", "reason"\]\)/);
  assert.match(shared, /new Set\(\["roundCode", "reason"\]\)/);
  assert.match(shared, /const roundCode = payload\.roundCode\.trim\(\)\.toUpperCase\(\)/);
  assert.doesNotMatch(shared, /new Set\([^\n]*(?:winnerEntryId|championEntryId|downstreamMatchId)/);
});

test("platform aggregate parser accepts the full PostgreSQL textual UUID domain", async () => {
  const shared = await source("app/api/tournaments/_shared.ts");
  assert.match(shared, /tournamentUuidPattern = \/\^\[0-9a-f\]\{8\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{4\}-\[0-9a-f\]\{12\}\$\/i/);
  assert.match(await source("app/api/platform-admin/tournaments/route.ts"), /00000000-0000-0000-0000-00000000c6c1/);
});

test("PostgreSQL owns winner resolution, byes, corrections and completion", async () => {
  const sql = (await Promise.all(migrations.map(source))).join("\n");
  for (const marker of [
    "KNOCKOUT_WINNER_REQUIRED", "PENALTY_SHOOTOUT", "EXTRA_TIME", "BYE",
    "DOWNSTREAM_MATCH_ALREADY_STARTED", "pachanga_tournament_completion_rebuild_v1",
    "pachanga_tournament_knockout_apply_official_decision_v1",
    "pachanga_tournament_knockout_replace_downstream_v1",
  ]) assert.match(sql, new RegExp(marker));
  assert.match(sql, /bye[\s\S]+canonical_match_id is null/i);
  assert.match(sql, /'rewardGrants', 0/);
  for (const format of ["twoLegAggregate", "doubleElimination", "awayGoals"]) {
    assert.match(sql, new RegExp(`'${format}', false`));
  }
});

test("R6C reuses CanonicalMatch, R4B, R4C, R4D, R5 and referee assignments", async () => {
  const sql = (await Promise.all([
    ...migrations.map(source),
    source("supabase/migrations/20260824230726_league_operational_exceptions_schema_v1.sql"),
    source("supabase/migrations/20260825165834_competition_discipline_schema_v1.sql"),
  ])).join("\n");
  for (const marker of [
    "pachanga_competition_match_contexts", "pachanga_competition_schedule_slots",
    "pachanga_competition_official_result_decisions", "pachanga_competition_no_show_incidents",
    "pachanga_competition_disciplinary_events", "pachanga_referee_assignments",
    "pachanga_competition_player_sanction_applies_v1",
    "pachanga_referee_match_snapshot_wave4_v1",
    "pachanga_referee_replaced_statistics_sync_v1",
  ]) assert.match(sql, new RegExp(marker));
  assert.match(sql, /sourceId', target_source_id/);
  assert.match(sql, /target_source_id::uuid[\s\S]+pachanga_tournament_bracket_nodes/);
  assert.match(sql, /competition_match_context_id uuid not null references public\.pachanga_competition_match_contexts/);
  assert.match(sql, /canonical_match_id uuid not null references public\.pachanga_canonical_matches/);
  assert.match(sql, /after update of status on public\.pachanga_referee_assignments[\s\S]+new\.status = 'replaced'/);
  assert.match(sql, /pachanga_referee_refresh_statistics_v1\([\s\S]+new\.referee_profile_id/);
});

test("RLS denies direct writes and exposes only authenticated command/read contracts", async () => {
  const sql = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(sql, /grant execute on function public\.get_pachanga_tournament_knockout_v1\(uuid\)\s+to authenticated/);
  assert.match(sql, /grant execute on function public\.command_pachanga_tournament_knockout_v1/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table public\.pachanga_tournament_(?:bracket|knockout|completion)[^;]+ to authenticated/i);
});

test("private APIs are no-store, same-origin and never expose service role", async () => {
  const [shared, readRoute, commandRoute] = await Promise.all([
    source("app/api/tournaments/_shared.ts"),
    source("app/api/tournaments/knockout/[competitionId]/route.ts"),
    source("app/api/tournaments/knockout/command/route.ts"),
  ]);
  assert.match(shared, /noStoreHeaders/);
  assert.match(commandRoute, /requireTournamentOrigin/);
  assert.match(commandRoute, /tournamentWriteGate/);
  assert.match(commandRoute, /operationId/);
  assert.match(commandRoute, /expectedRevision/);
  assert.match(readRoute, /get_pachanga_tournament_knockout_v1/);
  assert.doesNotMatch(`${shared}\n${readRoute}\n${commandRoute}`, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("PWA blocks knockout writes offline and Realtime only invalidates canonical state", async () => {
  const client = await source("app/_components/tournament-group-stage-client.tsx");
  assert.equal(isKnownClientWriteOperation("api:tournament-knockout-command"), true);
  assert.equal(classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_tournament_knockout_v1", { method: "POST" }), "rpc:command_pachanga_tournament_knockout_v1");
  assert.match(client, /clientWriteFetch\(\s*"api:tournament-knockout-command"/);
  assert.match(client, /payload\.extension === "postgres_changes" && payload\.status === "ok"/);
  assert.match(client, /await loadCanonical\(accessToken, userId, "mutation"\)/);
  assert.match(client, /Sin conexión: el cuadro cacheado sigue disponible/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new|offlineQueue|queueOffline|pendingOperations/i);
});

test("Tournament Hub renders an adaptive live bracket without client score authority", async () => {
  const [client, bracket, css] = await Promise.all([
    source("app/_components/tournament-group-stage-client.tsx"),
    source("app/_components/tournament-knockout-bracket.tsx"),
    source("app/_components/tournament-knockout-bracket.module.css"),
  ]);
  assert.match(client, /TournamentKnockoutBracket/);
  assert.match(client, /Activar eliminatorias/);
  assert.match(client, /Cerrar liguilla/);
  assert.match(bracket, /Rondas eliminatorias/);
  assert.match(bracket, /Organizer Desk/);
  assert.match(bracket, /Campeón/);
  assert.doesNotMatch(bracket, /winnerEntryId|championEntryId:\s|scoreHome:\s|scoreAway:\s/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /min-width: 0/);
  assert.match(css, /prefers-reduced-motion/);
});

test("authoritative snapshot selection never relies on a timestamp alone", async () => {
  const sql = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(sql, /order by decisions\.revision desc, decisions\.server_sequence desc,[\s\S]*decisions\.id desc limit 1/);
  assert.match(sql, /order by contexts\.server_sequence desc, contexts\.id desc limit 1/);
  assert.doesNotMatch(sql, /order by\s+(?:created_at|updated_at|completed_at)\s+desc\s*(?:limit|;|\))/i);
});
