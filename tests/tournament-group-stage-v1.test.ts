import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  buildTournamentGroupStageSlotIntents,
  compareTournamentGroupStageSnapshots,
  tournamentGroupStageActions,
  tournamentGroupStageReadCacheVersion,
  tournamentGroupStageTabs,
} from "../app/tournament-group-stage-contract";
import { tournamentPlatformActions } from "../app/tournament-draw-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = [
  "supabase/migrations/20260827105014_tournament_group_stage_schema_qualification_v1.sql",
  "supabase/migrations/20260827105018_tournament_group_stage_r4b_adapter_v1.sql",
  "supabase/migrations/20260827105022_tournament_group_stage_canonical_matches_v1.sql",
  "supabase/migrations/20260827105027_tournament_group_stage_read_models_hub_v1.sql",
  "supabase/migrations/20260827105033_tournament_group_stage_access_realtime_v1.sql",
  "supabase/migrations/20260827105036_tournament_group_stage_hardening_flags_v1.sql",
] as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R6B exposes a bounded command, Hub tab and read-cache contract", () => {
  assert.deepEqual(tournamentPlatformActions, [
    "tournament.flags.set", "tournament.kill_switch",
    "tournament.beta_bundle.grant", "tournament.beta_bundle.revoke",
    "tournament.group_stage.flags.set",
  ]);
  assert.equal(tournamentGroupStageReadCacheVersion, 2);
  assert.deepEqual(tournamentGroupStageActions, [
    "group_stage.prepare", "group_schedule.create", "group_schedule.generate",
    "group_schedule.validate", "group_schedule.publish", "group_stage.activate",
    "group_stage.complete", "qualification.rebuild", "qualification.validate",
    "qualification.publish", "bracket_template.create", "bracket_template.publish",
  ]);
  assert.deepEqual(tournamentGroupStageTabs, [
    "summary", "rounds", "matches", "standings", "teams", "discipline",
    "referees", "incidents", "rules", "bracket",
  ]);
});

test("slot proposals are deterministic semantic intent and never contain server fields", () => {
  const slots = buildTournamentGroupStageSlotIntents({
    firstStartsAt: "2027-06-01T18:00:00.000Z",
    fixtureCount: 6,
    matchDurationMinutes: 60,
    slotCadenceMinutes: 90,
    timezone: "Europe/Madrid",
    venueLabel: "Pista Norte",
  });
  assert.equal(slots.length, 6);
  assert.deepEqual(slots[0], {
    endsAt: "2027-06-01T19:00:00.000Z",
    startsAt: "2027-06-01T18:00:00.000Z",
    timezone: "Europe/Madrid",
    venueLabel: "Pista Norte",
  });
  assert.equal(slots[1].startsAt, "2027-06-01T19:30:00.000Z");
  assert.doesNotMatch(JSON.stringify(slots), /resourceKey|createdBy|serverSequence|revision/);
  assert.throws(() => buildTournamentGroupStageSlotIntents({
    firstStartsAt: "invalid", fixtureCount: 6, matchDurationMinutes: 60,
    slotCadenceMinutes: 90, timezone: "Europe/Madrid",
  }), /TOURNAMENT_GROUP_SLOT_INTENT_INVALID/);
});

test("cached snapshots are ordered by server sequence, revision, timestamp and stable id", () => {
  const older = { cache: { entityId: "a", revision: 9, serverSequence: 41, updatedAt: "2027-01-01T00:00:00Z" } };
  const newer = { cache: { entityId: "b", revision: 1, serverSequence: 42, updatedAt: "2026-01-01T00:00:00Z" } };
  assert.equal(compareTournamentGroupStageSnapshots(older, newer) < 0, true);
  assert.equal(compareTournamentGroupStageSnapshots(newer, older) > 0, true);
});

test("six forward migrations reuse R4 authorities and create no duplicate match or result engine", async () => {
  const sql = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(sql, /pachanga_tournament_group_schedule_generate_v1/);
  assert.match(sql, /pachanga_league_schedule_generate_revision_v1/);
  assert.match(sql, /pachanga_competition_match_contexts/);
  assert.match(sql, /pachanga_competition_official_result_decisions/);
  assert.match(sql, /pachanga_competition_standing_snapshots/);
  assert.match(sql, /pachanga_competition_disciplinary_events/);
  assert.match(sql, /pachanga_referee_assignments/);
  assert.doesNotMatch(sql, /create table (?:public\.)?(?:tournament_match|tournament_result|tournament_standing|tournament_attendance|tournament_referee|tournament_discipline)\b/i);
});

test("group schedule seeds use stable sporting order instead of opaque Group ids", async () => {
  const sql = await source(migrations[1]);
  const generator = sql.match(/create or replace function private\.pachanga_tournament_group_schedule_generate_v1[\s\S]*?revoke all on function private\.pachanga_tournament_group_schedule_generate_v1/)?.[0] ?? "";
  assert.match(generator, /':group-order:' \|\| mapping_row\.group_order::text/);
  assert.doesNotMatch(generator, /seed_value[\s\S]{0,400}mapping_row\.competition_group_id::text/);
});

test("publication is atomic, idempotent and exactly 1:1 with CanonicalMatch contexts", async () => {
  const sql = await source(migrations[2]);
  assert.match(sql, /pachanga_tournament_group_schedule_publish_v1/);
  assert.match(sql, /pachanga_league_schedule_publish_v1/);
  assert.match(sql, /published_fixture_total <> expected_fixture_total/);
  assert.match(sql, /canonical_total <> expected_fixture_total/);
  assert.match(sql, /context_total <> expected_fixture_total/);
  assert.match(sql, /having count\(bindings\.id\) <> 1 or count\(contexts\.id\) <> 1/);
  assert.match(sql, /TOURNAMENT_CANONICAL_MATCH_CARDINALITY_VIOLATION/);
  assert.match(sql, /TOURNAMENT_GROUP_SCHEDULE_ALREADY_PUBLISHED/);
  assert.match(sql, /competition_match_context_id/);
});

test("qualification is explicit and bracket publication cannot progress knockout matches", async () => {
  const [schema, engine, hardening] = await Promise.all([
    source(migrations[0]), source(migrations[2]), source(migrations[5]),
  ]);
  for (const policy of [
    "TOP_N_PER_GROUP", "TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP",
    "TOP_N_PER_GROUP_PLUS_BEST_THIRDS",
  ]) assert.match(`${schema}\n${engine}`, new RegExp(policy));
  assert.match(engine, /CROSS_GROUP_QUALIFICATION_POLICY_REQUIRED/);
  assert.match(engine, /'progressionEnabled', false/);
  assert.match(hardening, /tournament_knockout_match_generation_enabled := false/);
  assert.match(hardening, /tournament_bracket_progression_enabled := false/);
});

test("qualification checksum covers sporting content and not opaque evidence ids", async () => {
  const sql = await source(migrations[2]);
  const rebuild = sql.match(/create or replace function private\.pachanga_tournament_qualification_rebuild_v1[\s\S]*?revoke all on function private\.pachanga_tournament_qualification_rebuild_v1/)?.[0] ?? "";
  const checksum = rebuild.match(/checksum_value := private\.pachanga_tournament_json_checksum_v1\([\s\S]*?\n  \)\);/)?.[0] ?? "";
  assert.match(checksum, /sourceStandingChecksums/);
  assert.match(checksum, /qualificationRows/);
  assert.match(checksum, /drawChecksum/);
  assert.doesNotMatch(checksum, /sourceStandingSnapshotIds|groupId|preparationId/);
});

test("the Hub exposes canonical scheduling, journey operations and sanitized participant data", async () => {
  const hub = await source(migrations[3]);
  assert.match(hub, /'schedule'.*'slotCount'.*'fixtureCount'/s);
  assert.match(hub, /'attendance'/);
  assert.match(hub, /'squad'/);
  assert.match(hub, /'sanctions'/);
  assert.match(hub, /'referee'/);
  assert.match(hub, /'incidents'/);
  assert.match(hub, /'status', 'NOT_SUBMITTED'/);
  assert.match(hub, /'status', 'UNASSIGNED'/);
  assert.doesNotMatch(hub, /'feeSnapshot'|'evidence'|'reportedBy'/i);
});

test("API accepts intent only, returns no-store responses and never uses service role", async () => {
  const [shared, readRoute, commandRoute] = await Promise.all([
    source("app/api/tournaments/_shared.ts"),
    source("app/api/tournaments/group-stage/[competitionId]/route.ts"),
    source("app/api/tournaments/group-stage/command/route.ts"),
  ]);
  assert.match(shared, /TOURNAMENT_GROUP_STAGE_PAYLOAD_FIELD_NOT_ALLOWED/);
  assert.match(shared, /TOURNAMENT_GROUP_SLOT_FIELD_NOT_ALLOWED/);
  assert.match(commandRoute, /requireTournamentOrigin/);
  assert.match(commandRoute, /tournamentWriteGate/);
  assert.match(commandRoute, /operationId/);
  assert.match(commandRoute, /expectedRevision/);
  assert.match(commandRoute, /command_pachanga_tournament_group_stage_v1/);
  assert.match(readRoute, /TOURNAMENT_GROUP_STAGE_NOT_PREPARED/);
  assert.match(`${readRoute}\n${commandRoute}`, /tournamentJson/);
  assert.doesNotMatch(`${shared}\n${readRoute}\n${commandRoute}`, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("PWA writes are gated, offline stays read-only and Realtime invalidates canonical snapshots", async () => {
  const [client, worker] = await Promise.all([
    source("app/_components/tournament-group-stage-client.tsx"),
    source("app/service-worker-source.ts"),
  ]);
  assert.equal(isKnownClientWriteOperation("api:tournament-group-stage-command"), true);
  assert.equal(
    classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_tournament_group_stage_v1", { method: "POST" }),
    "rpc:command_pachanga_tournament_group_stage_v1",
  );
  assert.match(client, /clientWriteFetch\(\s*"api:tournament-group-stage-command"/);
  assert.match(client, /payload\.extension === "postgres_changes" && payload\.status === "ok"/);
  assert.match(client, /\.on\("postgres_changes"/);
  assert.match(client, /window\.addEventListener\("online"/);
  assert.match(client, /no se permiten operaciones deportivas/);
  assert.doesNotMatch(client, /subscribe\(\([^)]*\)\s*=>[\s\S]*loadCanonical/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new|offlineQueue|queueOffline|pendingOperations/i);
  assert.match(worker, /CACHEABLE_NAVIGATION_PATTERNS/);
  assert.match(worker, /competiciones\\\/\[0-9a-f-\]/);
});

test("Official UI includes Tournament Hub, adaptive game layout and audited Group Stage control", async () => {
  const [client, css, adminClient, adminPage, home] = await Promise.all([
    source("app/_components/tournament-group-stage-client.tsx"),
    source("app/_components/tournament-group-stage-client.module.css"),
    source("app/admin/competitions/tournament-private-beta-admin-client.tsx"),
    source("app/admin/competitions/page.tsx"),
    source("app/_components/tournament-private-beta-client.tsx"),
  ]);
  await source("app/competiciones/[competition]/torneo/page.tsx");
  for (const label of ["Resumen", "Jornadas", "Partidos", "Clasificación", "Equipos", "Disciplina", "Árbitros", "Incidencias", "Reglamento", "Cuadro"]) {
    assert.match(client, new RegExp(label));
  }
  assert.match(client, /TournamentTeamJourney|Mi equipo|Convocatoria/);
  assert.match(client, /const round = rounds\.some/);
  assert.doesNotMatch(client, /useEffect\(\(\) => \{[\s\S]{0,500}setRound/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /min-width: 0/);
  assert.match(adminClient, /tournament\.group_stage\.flags\.set/);
  assert.match(adminPage, /Fases de grupo/);
  assert.match(home, /Tournament Hub/);
});

test("SQL full story covers 24 canonical fixtures, standings, qualification and zero knockout", async () => {
  const sql = await source("tests/tournament-group-stage-v1-db.sql");
  for (const marker of [
    "24 fixtures", "exactly one MatchContext and CanonicalMatch", "TeamJourney",
    "per-group schedule readiness", "provisional standings", "bracket", "knockoutMatches",
  ]) assert.match(sql, new RegExp(marker, "i"));
  assert.match(sql, /set role authenticated/);
  assert.match(sql, /rollback;/i);
});
