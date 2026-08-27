import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  tournamentAlgorithmVersion,
  tournamentDrawActions,
  tournamentDrawModes,
  tournamentDrawTargets,
  tournamentPlatformActions,
  tournamentRealtimeTable,
  tournamentWizardSteps,
} from "../app/tournament-draw-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = {
  access: "supabase/migrations/20260826195039_tournament_draw_access_read_models_v1.sql",
  commands: "supabase/migrations/20260826195037_tournament_draw_commands_engine_v1.sql",
  foundation: "supabase/migrations/20260826195034_tournament_foundation_participant_freeze_v1.sql",
  hardening: "supabase/migrations/20260826195040_tournament_draw_hardening_indexes_flags_v1.sql",
  schema: "supabase/migrations/20260826195036_tournament_draw_schema_revisions_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R6A exposes the bounded Tournament command, mode, target and wizard contracts", () => {
  assert.deepEqual(tournamentWizardSteps.map((step) => step.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  assert.deepEqual(tournamentDrawModes, ["PURE_RANDOM", "SEEDED_POTS", "CONSTRAINT_OPTIMIZED", "MANUAL_ASSISTED", "HYBRID"]);
  assert.deepEqual(tournamentDrawTargets, ["GROUP_ASSIGNMENT", "KNOCKOUT_INITIAL_SEEDING", "GROUPS_THEN_KNOCKOUT"]);
  assert.equal(tournamentAlgorithmVersion, "tournament-draw-v1.0.0");
  assert.equal(tournamentDrawActions.length, 26);
  assert.deepEqual(tournamentPlatformActions, [
    "tournament.flags.set", "tournament.kill_switch",
    "tournament.beta_bundle.grant", "tournament.beta_bundle.revoke",
  ]);
});

test("five forward-only migrations install Tournament flags OFF and no match authority", async () => {
  const [foundation, schema, commands, access, hardening] = await Promise.all([
    source(migrations.foundation),
    source(migrations.schema),
    source(migrations.commands),
    source(migrations.access),
    source(migrations.hardening),
  ]);
  assert.match(foundation, /tournament_foundation_enabled boolean not null default false/);
  assert.match(foundation, /tournament_match_generation_enabled boolean not null default false/);
  assert.match(foundation, /tournament_bracket_progression_enabled boolean not null default false/);
  assert.match(schema, /create table public\.pachanga_competition_draw_plans/);
  assert.match(schema, /create table public\.pachanga_competition_draw_revisions/);
  assert.match(commands, /TOURNAMENT_MATCH_GENERATION_NOT_AVAILABLE|tournamentMatchesCreated', 0/);
  assert.match(access, /'tournamentMatches', 0/);
  assert.match(hardening, /pachanga_tournament_reject_match_generation_v1/);
  assert.doesNotMatch(`${foundation}\n${schema}\n${commands}`, /insert into public\.pachanga_competition_match_contexts/i);
});

test("PostgreSQL owns actor, organizer grant, revision, locking, replay and immutable publication", async () => {
  const commands = await source(migrations.commands);
  assert.match(commands, /actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /pachanga_tournament_replay_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /TOURNAMENT_PRIVATE_BETA_GRANT_REQUIRED/);
  assert.match(commands, /PUBLISHED_TOURNAMENT_IMMUTABLE/);
  assert.match(commands, /DRAW_ALREADY_PUBLISHED/);
  assert.match(commands, /tournament_revision = competitions\.tournament_revision \+ 1/);
  assert.match(commands, /pachanga_tournament_store_command_v1/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|actor_id|serverSequence|confirmedRevision|resultChecksum|placements)'/i);
});

test("the deterministic solver is bounded, reproducible and covers groups, constraints, locks and byes", async () => {
  const [schema, commands] = await Promise.all([source(migrations.schema), source(migrations.commands)]);
  assert.match(commands, /tournament-draw-v1\.0\.0/);
  assert.match(commands, /for attempt in 0\.\.127 loop/);
  assert.match(commands, /target_seed \|\| '\|knockout\|'/);
  assert.match(commands, /POT_DISTRIBUTION/);
  assert.match(commands, /SAME_CLUB_AVOIDANCE/);
  assert.match(schema, /TEAM_LEVEL_BALANCE/);
  assert.match(commands, /level_balance/);
  assert.match(commands, /ENTRY_TO_GROUP/);
  assert.match(commands, /BRACKET_HALF/);
  assert.match(commands, /DRAW_UNSATISFIABLE/);
  assert.match(commands, /private\.pachanga_tournament_next_power_of_two_v1/);
  assert.match(commands, /insert into public\.pachanga_competition_draw_byes/);
});

test("participant freeze is immutable, eligible, bounded and invalidated after withdrawal", async () => {
  const [foundation, commands] = await Promise.all([source(migrations.foundation), source(migrations.commands)]);
  assert.match(foundation, /pachanga_tournament_guard_immutable_v1/);
  assert.match(commands, /PARTICIPANT_ROSTER_NOT_ELIGIBLE/);
  assert.match(commands, /participant_count < 4 or participant_count > 64/);
  assert.match(commands, /cardinality\(array\(select distinct value from unnest\(entry_ids\)/);
  assert.match(commands, /DRAW_INPUT_STALE/);
});

test("draw evidence orders canonical revisions by sequence or stable identifiers, never timestamp alone", async () => {
  const sql = (await Promise.all(Object.values(migrations).map(source))).join("\n");
  assert.match(sql, /where revisions\.id = plan_row\.current_revision_id/);
  assert.match(sql, /'serverSequence', revision_row\.server_sequence/);
  assert.match(sql, /order by draw_plans\.server_sequence desc, draw_plans\.id desc limit 1/);
  assert.match(sql, /order by visible\.updated_at desc, visible\.server_sequence desc, visible\.id/);
  assert.doesNotMatch(sql, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|;|\))/i);
});

test("RLS exposes sanitized command and read RPCs without direct authenticated table writes", async () => {
  const sql = (await Promise.all(Object.values(migrations).map(source))).join("\n");
  assert.match(sql, /grant execute on function public\.command_pachanga_tournament_draw_v1/);
  assert.match(sql, /grant execute on function public\.get_pachanga_tournament_snapshot_v1/);
  assert.match(sql, /grant execute on function public\.get_pachanga_tournament_draw_audit_v1/);
  assert.match(sql, /revoke all on table[\s\S]+pachanga_competition_draw_plans[\s\S]+from public, anon, authenticated/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table (?:public|private)\.pachanga_(?:competition_draw|tournament)[^;]+ to authenticated/i);
  assert.match(sql, /Auth identities and private reasons are never exposed/);
});

test("participant command receipts apply the same actor-aware privacy boundary as canonical reads", async () => {
  const [commands, regression] = await Promise.all([
    source(migrations.commands),
    source("tests/tournament-foundation-draw-v1-db.sql"),
  ]);
  assert.match(commands, /pachanga_tournament_command_snapshot_v1\(competition_row\.id, actor_id\)/);
  assert.match(commands, /entries\.status in \('accepted', 'active', 'completed'\)/);
  assert.match(commands, /plans\.status = 'published'/);
  assert.match(commands, /target_actor_id, 'participants_manage'/);
  assert.match(commands, /target_actor_id, 'draw_read'/);
  assert.match(regression, /Participant command response must hide another team pending invitation/);
  assert.match(regression, /Accepted participant response must remain actor-filtered/);
});

test("API accepts only semantic intent and never trusts result, quality, actor or server fields", async () => {
  const [shared, commandRoute, platformRoute] = await Promise.all([
    source("app/api/tournaments/_shared.ts"),
    source("app/api/tournaments/command/route.ts"),
    source("app/api/platform-admin/tournaments/route.ts"),
  ]);
  assert.match(shared, /TOURNAMENT_SERVER_FIELDS_FORBIDDEN/);
  assert.match(shared, /TOURNAMENT_PAYLOAD_FIELD_NOT_ALLOWED/);
  assert.match(shared, /"resultChecksum"/);
  assert.match(shared, /"placements"/);
  assert.match(commandRoute, /requireTournamentOrigin/);
  assert.match(commandRoute, /tournamentWriteGate/);
  assert.match(commandRoute, /operationId/);
  assert.match(commandRoute, /expectedRevision/);
  assert.match(platformRoute, /requireSameOriginMutation/);
  assert.match(platformRoute, /command_pachanga_tournament_platform_v1/);
  assert.doesNotMatch(`${shared}\n${commandRoute}\n${platformRoute}`, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("PWA blocks Tournament writes offline while Realtime only invalidates canonical reads", async () => {
  const client = await source("app/_components/tournament-private-beta-client.tsx");
  assert.equal(tournamentRealtimeTable, "pachanga_tournament_invalidations");
  assert.equal(isKnownClientWriteOperation("api:tournament-draw-command"), true);
  assert.equal(isKnownClientWriteOperation("api:platform-admin-tournaments"), true);
  assert.equal(classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_tournament_draw_v1", { method: "POST" }), "rpc:command_pachanga_tournament_draw_v1");
  assert.match(client, /clientWriteFetch\("api:tournament-draw-command"/);
  assert.match(client, /state === "SUBSCRIBED"/);
  assert.match(client, /window\.addEventListener\("online"/);
  assert.match(client, /Sin conexión: puedes consultar la copia local, pero no modificar el Torneo/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new|offlineQueue|queueOffline|pendingOperations/i);
});

test("Official UI provides all private routes, adaptive Draw Desk, reveal and Control Center", async () => {
  const [client, css, shell, admin] = await Promise.all([
    source("app/_components/tournament-private-beta-client.tsx"),
    source("app/_components/tournament-private-beta-client.module.css"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/admin/competitions/page.tsx"),
  ]);
  for (const route of [
    "app/torneos/page.tsx", "app/torneos/crear/page.tsx",
    "app/competiciones/[competition]/gestion/participantes/page.tsx",
    "app/competiciones/[competition]/gestion/sorteo/page.tsx",
    "app/competiciones/[competition]/sorteo/page.tsx",
    "app/laboratorio-tournament-draw/page.tsx",
  ]) await source(route);
  assert.match(client, /draggable=\{editable\}/);
  assert.match(client, /draw\.entry\.swap/);
  assert.match(client, /Revelar sorteo|Revelar/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /min-width: 0/);
  assert.match(shell, /href="\/torneos"/);
  assert.match(admin, /Tournament Private Beta/);
  assert.match(admin, /Tournament matches/);
});

test("notifications cover invitation, acceptance, freeze, ready, regenerate, assignment, publish and cancel", async () => {
  const commands = await source(migrations.commands);
  for (const notification of [
    "tournament_invitation", "tournament_participant_accepted", "tournament_participant_declined",
    "tournament_participants_frozen", "tournament_draw_ready", "tournament_draw_regenerated",
    "tournament_draw_assignment", "tournament_draw_published", "tournament_draw_cancelled", "tournament_cancelled",
  ]) assert.match(commands, new RegExp(notification));
  assert.doesNotMatch(commands, /tournament_draw_moved|tournament_draft_movement/);
});

test("SQL regression exercises idempotency, deterministic seed, RLS, forged result rejection and zero matches", async () => {
  const sql = await source("tests/tournament-foundation-draw-v1-db.sql");
  for (const marker of [
    "Same seed and inputs must reproduce the result", "exactly four capabilities",
    "TOURNAMENT_SERVER_FIELDS_FORBIDDEN", "TOURNAMENT_READ_FORBIDDEN",
    "permission denied|row-level security", "Tournament matches",
  ]) assert.match(sql, new RegExp(marker, "i"));
  assert.match(sql, /rollback;/i);
  assert.match(sql, /Every R6A foreign key must have a covering index/);
});

test("authenticated staging covers the ten canonical stories, security negatives and branch teardown", async () => {
  const staging = await source("tests/tournament-foundation-draw-v1-staging-e2e.mjs");
  for (const marker of [
    "automaticPublication", "sameSeed", "differentSeed", "sameClubHardAvoid",
    "impossibleConstraint", "manualSwap", "hybridTwoLocks", "knockout14Of16",
    "withdrawalMakesFreezeStale", "concurrentPublish",
  ]) assert.match(staging, new RegExp(marker));
  for (const marker of [
    "organizerWithoutGrant", "foreignDraft", "duplicateParticipant", "entryNotAccepted",
    "potOvercapacity", "duplicatePosition", "contradictoryLocks", "clientResultForged",
    "publishedDrawEdit", "directWrite", "matchGeneration", "bracketProgression",
    "paymentIntent", "aiPublish",
  ]) assert.match(staging, new RegExp(marker));
  assert.match(staging, /TOURNAMENT_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(staging, /EPHEMERAL_BRANCH_TEARDOWN_REQUIRED/);
  assert.match(staging, /pachanga_tournament_invalidations/);
  assert.match(staging, /TOURNAMENT_STAGING_BROWSER_KEY_REQUIRED/);
  assert.match(staging, /server_sequence: nextFixtureServerSequence\(\)/);
  assert.match(staging, /command_pachanga_club_foundation_v1/);
  assert.match(staging, /command_pachanga_club_platform_v1/);
  assert.match(staging, /command_action: "club\.review\.submit"/);
  assert.match(staging, /command_action: "club\.status\.set"/);
  assert.match(staging, /operationalStatus, "draft"/);
  assert.match(staging, /operationalStatus, "pending_review"/);
  assert.match(staging, /operationalStatus, "active"/);
  assert.match(staging, /restore-club-flags/);
  assert.doesNotMatch(staging, /from\("pachanga_clubs"\)\.insert|from\("pachanga_club_memberships"\)\.insert/);
});
