import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  refereeAssignmentActions,
  refereeAssignmentStatusLabel,
  refereeFeeLabel,
  refereeScheduleStateLabel,
} from "../app/referee-assignment-contract";
import { refereeHttpStatus } from "../app/referee-error-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = [
  "supabase/migrations/20260826014905_referee_assignment_private_beta_schema_v1.sql",
  "supabase/migrations/20260826014910_referee_assignment_private_beta_authority_v1.sql",
  "supabase/migrations/20260826014916_referee_match_officiating_commands_v1.sql",
  "supabase/migrations/20260826014920_referee_assignment_private_beta_access_v1.sql",
] as const;

async function source(path: string) { return readFile(new URL(path, root), "utf8"); }

test("Wave 4 extends the R3 authority with a gated canonical lifecycle", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(combined, /alter table public\.pachanga_referee_assignments/);
  assert.match(combined, /source_kind = 'competition_generated'/);
  assert.match(combined, /referee_assignment_private_beta_enabled boolean not null default false/);
  const lifecycle = combined.match(/pachanga_referee_assignments_status_check check \(\s*status in \(([^)]+)\)/)?.[1] ?? "";
  assert.deepEqual(
    new Set(lifecycle.match(/'[a-z_]+'/g)?.map((status) => status.slice(1, -1))),
    new Set(["proposed", "accepted", "declined", "confirmed", "cancelled", "expired", "replaced", "completed"]),
  );
  assert.match(combined, /REFEREE_CANONICAL_MATCH_REQUIRED/);
  assert.match(combined, /MAIN_REFEREE/);
  assert.match(
    combined,
    /old\.status = 'completed'[\s\S]*new\.status = 'cancelled'[\s\S]*new\.cancel_reason_code = 'completion_voided'/,
  );
  assert.match(
    combined,
    /old\.status in \('declined', 'cancelled', 'expired', 'replaced', 'completed'\)[\s\S]*new\.status is distinct from old\.status[\s\S]*and not \([\s\S]*old\.status = 'completed'[\s\S]*new\.status = 'cancelled'[\s\S]*new\.cancel_reason_code = 'completion_voided'[\s\S]*new\.cancelled_by is not null[\s\S]*new\.completed_at is null[\s\S]*\) then[\s\S]*REFEREE_ASSIGNMENT_TERMINAL/,
  );
  assert.doesNotMatch(combined, /RefereeAssignmentV2|LeagueRefereeAssignment|TournamentRefereeAssignment|DemoRefereeAssignment/);
});

test("effective R4D schedules, one MAIN slot and referee overlaps fail closed", async () => {
  const [schema, authority, commands] = await Promise.all([
    source(migrations[0]),
    source(migrations[1]),
    source(migrations[2]),
  ]);
  assert.match(schema, /drop constraint if exists pachanga_competition_match_s_discipline_validation_status_check/);
  assert.match(authority, /RECONFIRMATION_REQUIRED/);
  assert.match(authority, /STALE_SCHEDULE/);
  assert.match(authority, /REFEREE_ASSIGNMENT_TIME_CONFLICT/);
  assert.match(authority, /REFEREE_ASSIGNMENT_SLOT_TAKEN/);
  assert.match(authority, /pachanga_referee_r4d_schedule_sync_v1/);
  assert.match(commands, /CompetitionMatchContext -> RefereeAssignment|locked_match_context_id/);
  assert.match(commands, /for update;[\s\S]*?REFEREE_ASSIGNMENT_NOT_FOUND/);
});

test("every Wave 4 foreign key has a covering index in the canonical schema migration", async () => {
  const schema = await source(migrations[0]);
  for (const indexName of [
    "pachanga_referee_assignments_canonical_binding_idx",
    "pachanga_referee_assignments_competition_context_idx",
    "pachanga_referee_assignments_requester_competition_idx",
    "pachanga_referee_assignment_terms_proposed_by_idx",
    "pachanga_referee_assignment_terms_countered_by_idx",
    "pachanga_referee_assignment_terms_accepted_by_idx",
    "pachanga_referee_assignment_term_revisions_actor_idx",
    "pachanga_referee_assignment_revisions_profile_idx",
    "pachanga_referee_assignment_revisions_match_idx",
    "pachanga_referee_assignment_revisions_replaces_idx",
    "pachanga_referee_assignment_revisions_replaced_by_idx",
    "pachanga_referee_assignment_revisions_actor_idx",
    "pachanga_discipline_reporting_referee_idx",
  ]) {
    assert.match(schema, new RegExp(`create index if not exists ${indexName}`));
  }
});

test("private terms are immutable evidence and never become Pachangas IQ payments", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  assert.match(combined, /fee_mode in \('FREE', 'FIXED', 'NEGOTIABLE', 'VOLUNTEER'\)/);
  assert.match(combined, /private\.pachanga_referee_assignment_term_revisions/);
  assert.match(combined, /after insert or update on private\.pachanga_referee_assignment_terms/);
  assert.match(combined, /pachanga_referee_term_revisions_immutable_v1/);
  assert.match(combined, /REFEREE_IMMUTABLE_HISTORY/);
  assert.match(combined, /paymentManagedByPachangasIq', false/);
  assert.doesNotMatch(combined, /insert into\s+(?:public\.|private\.)?pachanga_(?:stripe|billing|payment)/i);
});

test("only the current confirmed referee can record narrow R5 evidence", async () => {
  const commands = await source(migrations[2]);
  const officiating = commands.match(/create or replace function public\.command_pachanga_referee_officiating_v1[\s\S]*?\n\$\$;/)?.[0] ?? "";
  assert.match(officiating, /assignment\.status <> 'confirmed' or assignment\.schedule_state <> 'CURRENT'/);
  assert.match(officiating, /referee_assignment_id, reporting_referee_profile_id/);
  assert.match(officiating, /r4cOfficialResultChanged', false/);
  assert.match(officiating, /officialResultChanged', false/);
  for (const forbidden of ["sanction", "counter", "waiver", "appeal", "officialResult", "standings", "rating", "facets", "grl"]) {
    assert.match(officiating, new RegExp(`'${forbidden}'`));
  }
});

test("read models keep terms private and expose canonical product surfaces", async () => {
  const reads = await source(migrations[3]);
  for (const rpc of [
    "get_my_pachanga_referee_assignments_v1",
    "get_pachanga_referee_assignment_beta_v1",
    "get_pachanga_referee_match_assignment_v1",
    "get_pachanga_referee_competition_desk_v1",
    "get_pachanga_referee_club_assignments_v1",
    "get_pachanga_platform_referee_health_v1",
  ]) assert.match(reads, new RegExp(rpc));
  assert.match(reads, /pachanga_referee_assignment_can_view_terms_v1/);
  assert.match(reads, /manager_access or assignments\.status in \('confirmed', 'replaced', 'completed'\)/);
  assert.match(reads, /Ordinary participants never receive proposal or fee details/);
  assert.doesNotMatch(reads.match(/pachanga_referee_public_snapshot_v1[\s\S]*?\$\$;/)?.[0] ?? "", /email|phone|bank|private_terms_note/i);
});

test("product APIs use authenticated user clients, no-store reads and PWA write gates", async () => {
  const paths = [
    "app/api/referee-assignments/me/route.ts",
    "app/api/referee-assignments/assignment/[assignmentId]/route.ts",
    "app/api/referee-assignments/match/[matchId]/route.ts",
    "app/api/referee-assignments/competition/[competitionId]/route.ts",
    "app/api/referee-assignments/club/[clubId]/route.ts",
    "app/api/referee-assignments/command/route.ts",
    "app/api/referee-assignments/officiating/route.ts",
    "app/api/referee-assignments/public-fee/route.ts",
  ];
  const contents = await Promise.all(paths.map(source));
  for (const route of contents) {
    assert.match(route, /refereeSession|from "\.\.\/.*_shared"|from "\.\.\/\_shared"/);
    assert.doesNotMatch(route, /SERVICE_ROLE|service_role/i);
  }
  for (const route of contents.slice(-3)) {
    assert.match(route, /requireRefereeOrigin\(request\)/);
    assert.match(route, /refereeWriteGate\(request\)/);
    assert.match(route, /operationId|refereeAssignmentEnvelope/);
  }
});

test("the PWA bridge recognizes every Wave 4 mutation and never queues a sport write", () => {
  for (const rpc of [
    "command_pachanga_referee_assignment_beta_admin_v1",
    "command_pachanga_referee_assignment_beta_v1",
    "command_pachanga_referee_officiating_v1",
    "command_pachanga_referee_public_fee_v1",
  ]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:referee-assignment-command"), true);
  assert.equal(isKnownClientWriteOperation("api:referee-officiating-command"), true);
  assert.equal(isKnownClientWriteOperation("api:referee-public-fee-command"), true);
});

test("referee APIs preserve recoverable server, conflict, permission and input semantics", () => {
  assert.equal(refereeHttpStatus("REFEREE_INTEGRATION_NOT_CONFIGURED"), 503);
  assert.equal(refereeHttpStatus("REFEREE_ASSIGNMENT_PRIVATE_BETA_DISABLED", "0A000"), 503);
  assert.equal(refereeHttpStatus("REFEREE_ASSIGNMENT_ACTION_NOT_AVAILABLE", "PT409"), 409);
  assert.equal(refereeHttpStatus("REFEREE_ASSIGNMENT_AUTHORITY_REQUIRED", "42501"), 403);
  assert.equal(refereeHttpStatus("REFEREE_CANONICAL_MATCH_REQUIRED", "22023"), 400);
});

test("staging failures identify the exact canonical command without exposing credentials", async () => {
  const staging = await source("tests/referee-assignments-private-beta-v1-staging-extension.mjs");
  for (const prefix of ["admin:", "officiating:", "discipline:", "operational:"]) {
    assert.match(staging, new RegExp(`\\\`${prefix}\\\$\\{action\\}:`));
  }
  assert.match(staging, /result\.error\.code \?\? "UNKNOWN"/);
  assert.doesNotMatch(staging, /SERVICE_ROLE_KEY|ANON_KEY|PASSWORD/);
});

test("staging Preview covers every Wave 4 product surface", async () => {
  const staging = await source("tests/league-scheduling-v1-staging-e2e.mjs");
  assert.match(staging, /if \(REFEREE_ASSIGNMENTS_EXTENSION\) productPaths\.push/);
  for (const path of [
    "/laboratorio-referee-platform?surface=confirmed",
    "/mis-asignaciones-arbitrales",
    "/gestion/arbitros",
    "/mercado?market=referees",
  ]) assert.match(staging, new RegExp(path.replace(/[?]/g, "\\?")));
});

test("staging privacy uses a real player without manager authority", async () => {
  const [base, staging] = await Promise.all([
    source("tests/league-scheduling-v1-staging-e2e.mjs"),
    source("tests/referee-assignments-private-beta-v1-staging-extension.mjs"),
  ]);
  assert.match(base, /team\.participantClient = await signIn/);
  assert.match(base, /participantClient: team\.participantClient \?\? teamClient/);
  assert.match(staging, /participantEntry\.participantClient/);
  assert.match(staging, /const managerRead = await rpc\([\s\S]*staffA/);
  assert.match(staging, /managerRead\.canonicalMatchId, participantRead\.canonicalMatchId/);
});

test("assignment UI contract explains lifecycle, schedule and private fee without a referee Rating", () => {
  assert.equal(refereeAssignmentStatusLabel("confirmed"), "Confirmada");
  assert.equal(refereeScheduleStateLabel("RECONFIRMATION_REQUIRED"), "Reconfirmación necesaria");
  assert.equal(refereeFeeLabel({ privateTerms: { agreedFeeCents: 7500, currency: "EUR", feeMode: "FIXED" } }), "75,00 €");
  assert.deepEqual(refereeAssignmentActions(
    { scheduleState: "CURRENT", status: "confirmed" },
    { refereeOwner: true, requesterManage: false },
  ), ["assignment.cancel", "result.observe", "discipline.record"]);
});

test("product surfaces converge on the Wave 4 APIs and canonical refetch contract", async () => {
  const [client, market, leagueMatch, club, organizerPage, inboxPage, refereeProfile, refereePlatform, adminRoute, adminClient] = await Promise.all([
    source("app/_components/referee-assignments-client.tsx"),
    source("app/mercado/referee-marketplace-panel.tsx"),
    source("app/_components/league-match-operations-client.tsx"),
    source("app/clubes/gestionar/club-manager-client.tsx"),
    source("app/competiciones/[competition]/gestion/arbitros/page.tsx"),
    source("app/mis-asignaciones-arbitrales/page.tsx"),
    source("app/arbitros/[slug]/public-referee-profile.tsx"),
    source("app/_components/referee-platform-client.tsx"),
    source("app/api/platform-admin/referees/route.ts"),
    source("app/admin/referees/referee-admin-client.tsx"),
  ]);
  assert.match(market, /api:referee-assignment-command/);
  assert.match(market, /assignment\.replace[\s\S]*assignment\.propose/);
  assert.match(market, /requesterKind[\s\S]*sourceKind/);
  assert.doesNotMatch(market, /\/api\/referees\/command/);
  assert.match(leagueMatch, /id: "arbitraje"[\s\S]*RefereeAssignmentsClient/);
  assert.match(club, /RefereeAssignmentsClient clubId=\{clubId\} embedded surface="club"/);
  assert.match(organizerPage, /surface="competition"/);
  assert.match(inboxPage, /surface="my"/);
  assert.match(refereeProfile, /publicFee/);
  assert.match(refereePlatform, /api:referee-public-fee-command/);
  assert.match(refereePlatform, /El acuerdo y el pago se realizan fuera de Pachangas IQ/);
  assert.match(adminRoute, /command_pachanga_referee_assignment_beta_admin_v1/);
  assert.match(adminClient, /assignment_beta\.flags\.set/);
  assert.match(client, /pachanga_referee_invalidations/);
  assert.match(client, /loadCanonical\(token, actorId, "realtime"\)/);
  assert.doesNotMatch(client, /setData\(row\)|setData\(payload/);
  assert.match(client, /Optional read cache[\s\S]*never authorizes or confirms/);
});

test("Wave 4 migrations do not mutate Rating, Rewards, Conduct, Player Cosmetics, Team Cosmetics or Billing", async () => {
  const combined = (await Promise.all(migrations.map(source))).join("\n");
  for (const table of [
    "pachanga_player_rating_votes", "pachanga_player_rating_snapshots",
    "pachanga_reward_grants", "pachanga_conduct_reports",
    "pachanga_player_cosmetic_loadouts", "pachanga_team_shield_loadouts",
    "pachanga_stripe_webhook_events",
  ]) {
    assert.doesNotMatch(combined, new RegExp(`(?:insert into|update|delete from)\\s+(?:public\\.|private\\.)?${table}`, "i"));
  }
  assert.doesNotMatch(combined, /canonical\.backfill|TournamentMatch/i);
});
