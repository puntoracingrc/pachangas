import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  competitionDisciplineActions,
  disciplineFlagsEnabled,
  isCompetitionDisciplineAction,
} from "../app/competition-discipline-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260825165843_competition_discipline_access_v1.sql",
  appealServiceAccounting: "supabase/migrations/20260825203500_competition_discipline_appeal_service_accounting_v1.sql",
  commands: "supabase/migrations/20260825165838_competition_discipline_commands_v1.sql",
  hardening: "supabase/migrations/20260825165849_competition_discipline_hardening_v1.sql",
  privatePolicyRevoke: "supabase/migrations/20260825211825_competition_discipline_private_policy_revoke_v1.sql",
  schema: "supabase/migrations/20260825165834_competition_discipline_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("R5 models immutable events, counters, sanctions, service and appeals without a second match authority", async () => {
  const schema = await source(paths.schema);
  for (const table of [
    "pachanga_competition_discipline_rule_catalogs",
    "pachanga_competition_disciplinary_cycles",
    "pachanga_competition_disciplinary_events",
    "pachanga_competition_disciplinary_event_revisions",
    "pachanga_competition_disciplinary_counters",
    "pachanga_competition_sanctions",
    "pachanga_competition_sanction_revisions",
    "pachanga_competition_sanction_proposals",
    "pachanga_competition_sanction_service_events",
    "pachanga_competition_sanction_appeals",
    "pachanga_competition_sanction_appeal_revisions",
    "pachanga_competition_discipline_player_states",
  ]) assert.match(schema, new RegExp(`create table public\\.${table}`));
  assert.match(schema, /canonical_match_id uuid not null references public\.pachanga_canonical_matches/);
  assert.doesNotMatch(schema, /create table[^;]+(?:discipline_match|disciplinary_match)/i);
});

test("all seven R5 feature flags are born off and preserve dependency order", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "competition_discipline_foundation_enabled",
    "competition_disciplinary_events_enabled",
    "competition_disciplinary_counters_enabled",
    "competition_sanctions_enabled",
    "competition_sanction_service_enabled",
    "competition_discipline_appeals_enabled",
    "competition_public_discipline_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /not competition_sanctions_enabled[\s\S]+competition_disciplinary_counters_enabled/);
  assert.match(schema, /not competition_sanction_service_enabled[\s\S]+competition_sanctions_enabled/);
  assert.match(schema, /not competition_discipline_appeals_enabled[\s\S]+competition_sanctions_enabled/);
});

test("card semantics are RuleRevision-bound and generic across yellow, red and temporary dismissals", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /cardTypeCatalog/);
  assert.match(commands, /accumulationThreshold/);
  assert.match(commands, /dismissalThresholdInMatch/);
  assert.match(commands, /temporaryDismissal/);
  assert.match(commands, /durationMinutes/);
  assert.match(commands, /endOnOpponentGoal/);
  assert.match(commands, /replacementPolicy/);
  assert.match(commands, /NO_SANCTION[\s\S]+FIXED_SANCTION[\s\S]+PROVISIONAL_SANCTION[\s\S]+COMMITTEE_REQUIRED[\s\S]+SANCTION_RANGE/);
});

test("appeal reductions preserve service already completed and canonical revision alignment", async () => {
  const migration = await source(paths.appealServiceAccounting);
  assert.match(migration, /decision_factors ->> 'appealOutcome'[\s\S]+<> 'modified'/);
  assert.match(migration, /previous_row\.total_units[\s\S]+previous_row\.remaining_units/);
  assert.match(migration, /new\.remaining_units := greatest\(coalesce\(new\.total_units, 0\) - served_units, 0\)/);
  assert.match(migration, /new\.status := case when new\.remaining_units = 0 then 'served' else 'active' end/);
  assert.match(migration, /new\.current_revision_id is not distinct from old\.current_revision_id/);
  assert.match(migration, /new\.remaining_units := revision_row\.remaining_units/);
});

test("the private R5 policy helper has no inherited client execute grant", async () => {
  const migration = await source(paths.privatePolicyRevoke);
  assert.match(
    migration,
    /revoke all on function private\.pachanga_competition_discipline_default_policy_v1\(\)[\s\S]+from public, anon, authenticated/,
  );
  assert.doesNotMatch(migration, /grant\s+execute/i);
});

test("server command envelope owns actor, rules, counters, deadlines, sequence and idempotency", async () => {
  const [commands, schema, client] = await Promise.all([
    source(paths.commands),
    source(paths.schema),
    source("app/_components/competition-discipline-client.tsx"),
  ]);
  assert.match(commands, /operation_id uuid[\s\S]+competition_id uuid[\s\S]+aggregate_id uuid[\s\S]+expected_revision bigint/);
  assert.match(commands, /declare actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(commands, /pachanga_competition_discipline_replay_v1/);
  assert.match(commands, /pachanga_competition_discipline_request_hash_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(schema, /discipline_revision bigint not null default 0/);
  assert.match(commands, /competition_row\.discipline_revision <> expected_revision/);
  assert.match(commands, /discipline_revision = competitions\.discipline_revision \+ 1/);
  assert.match(client, /disciplineNumber\(data\.revision\)/);
  assert.match(commands, /pachanga_competition_discipline_guard_locked_squads_v1/);
  assert.match(commands, /clock_timestamp\(\)/);
  assert.match(commands, /nextval\('private\.pachanga_competition_sequence'\)/);
  assert.match(commands, /deadline_hours := nullif\(appeal_policy ->> 'deadlineHours'/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|createdBy|counter|serverSequence|confirmedRevision|ruleRevisionId)'/i);
  for (const action of competitionDisciplineActions) {
    assert.equal(isCompetitionDisciplineAction(action), true);
    assert.match(commands, new RegExp(action.replaceAll(".", "\\.")));
  }
  assert.equal(isCompetitionDisciplineAction("rating.modify"), false);
});

test("RLS revokes direct writes and keeps evidence private", async () => {
  const [access, schema] = await Promise.all([source(paths.access), source(paths.schema)]);
  assert.match(access, /enable row level security/);
  assert.match(access, /revoke all on table public\.%I from public, anon, authenticated/);
  assert.match(access, /revoke all on table private\.pachanga_competition_discipline_evidence/);
  assert.match(access, /grant all on table private\.pachanga_competition_discipline_evidence to service_role/);
  assert.match(schema, /private\.pachanga_competition_discipline_evidence/);
  assert.doesNotMatch(access, /evidence_refs|private_notes|decision_reason_private/);
});

test("eligibility is enforced in PostgreSQL and not only presented in UI", async () => {
  const hardening = await source(paths.hardening);
  assert.match(hardening, /pachanga_competition_player_sanction_applies_v1/);
  assert.match(hardening, /pachanga_league_match_validate_squad_v1/);
  assert.match(hardening, /R4C_SQUAD_CONTAINS_DISCIPLINARY_INELIGIBLE_PLAYER/);
  assert.match(hardening, /perform private\.pachanga_league_match_validate_squad_v1\(new\.id\)/);
  assert.match(hardening, /if sheet_row\.id is null then return new; end if/);
});

test("public discipline stays minimized and disabled independently", async () => {
  const access = await source(paths.access);
  const publicStart = access.indexOf("create or replace function public.get_pachanga_public_competition_discipline_v1");
  const publicEnd = access.indexOf("revoke all on function public.get_pachanga_public_competition_discipline_v1", publicStart);
  const publicRead = access.slice(publicStart, publicEnd);
  assert.match(publicRead, /competition_public_discipline_enabled/);
  assert.match(publicRead, /PUBLIC_COMPETITION_DISCIPLINE_DISABLED/);
  assert.match(publicRead, /'events'[\s\S]+'sanctions'[\s\S]+'playerStates'/);
  assert.doesNotMatch(publicRead, /appeals|evidence|appellant|created_by|proposal|privateReason/i);
});

test("the API accepts semantic intent only and never exposes service role", async () => {
  const [shared, commandRoute] = await Promise.all([
    source("app/api/competitions/discipline/_shared.ts"),
    source("app/api/competitions/discipline/command/route.ts"),
  ]);
  assert.match(shared, /const actionKeys/);
  assert.match(shared, /"service\.record": \[\]/);
  assert.match(shared, /Object\.keys\(input\)\.some\(\(key\) => !allowed\.has\(key\)\)/);
  assert.match(commandRoute, /requireDisciplineOrigin/);
  assert.match(commandRoute, /disciplineWriteGate/);
  assert.match(commandRoute, /operationId[\s\S]+expectedRevision/);
  assert.match(commandRoute, /canonical: result\.data/);
  assert.doesNotMatch(`${shared}\n${commandRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
});

test("PWA caches reads but blocks all R5 writes while offline", async () => {
  for (const rpc of [
    "command_pachanga_competition_discipline_v1",
    "command_pachanga_competition_discipline_platform_v1",
    "command_pachanga_league_private_beta_r5_bundle_upgrade_v1",
  ]) {
    assert.equal(classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(isKnownClientWriteOperation("api:competition-discipline-command"), true);
  const client = await source("app/_components/competition-discipline-client.tsx");
  assert.match(client, /localStorage/);
  assert.match(client, /Optional read cache only\. PostgreSQL remains authoritative/);
  assert.match(client, /clientWriteFetch/);
  assert.match(client, /state === "SUBSCRIBED"/);
  assert.match(client, /loadCanonical\(token, userId, "realtime"\)/);
  assert.match(client, /\["active", "blocked", "provisional", "suspended"\]/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
});

test("Official UI exposes match discipline, desk, player context and responsive layouts", async () => {
  const [client, css, matchOperations] = await Promise.all([
    source("app/_components/competition-discipline-client.tsx"),
    source("app/_components/competition-discipline-client.module.css"),
    source("app/_components/league-match-operations-client.tsx"),
  ]);
  assert.match(client, /Mesa disciplinaria/);
  assert.match(client, /Registrar tarjeta/);
  assert.match(client, /Apelaciones/);
  assert.match(client, /No disponible por sanción/);
  assert.match(client, /disciplineBoolean\(item\.canAppeal\)/);
  assert.match(client, /Retirar apelación/);
  assert.match(client, /Modificar/);
  assert.match(matchOperations, /Disciplina/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  for (const route of [
    "app/competiciones/[competition]/gestion/disciplina/page.tsx",
    "app/competiciones/[competition]/partidos/[match]/disciplina/page.tsx",
    "app/competiciones/[competition]/jugadores/[player]/disciplina/page.tsx",
    "app/competiciones/[competition]/disciplina/page.tsx",
  ]) assert.match(await source(route), /export default/);
});

test("flag helpers require the complete authoritative calculation chain", () => {
  assert.equal(disciplineFlagsEnabled({
    countersEnabled: true,
    eventsEnabled: true,
    foundationEnabled: true,
    sanctionsEnabled: true,
  }), true);
  assert.equal(disciplineFlagsEnabled({
    countersEnabled: true,
    eventsEnabled: true,
    foundationEnabled: true,
    sanctionsEnabled: false,
  }), false);
});

test("the explicit beta upgrade is reachable through canonical platform capabilities", async () => {
  const hardening = await source(paths.hardening);
  assert.match(hardening, /command_pachanga_league_private_beta_r5_bundle_upgrade_v1/);
  assert.match(hardening, /pachanga_platform_require_v1\('competitions\.manage'\)/);
  assert.match(hardening, /pachanga_platform_require_v1\('flags\.write'\)/);
  assert.doesNotMatch(hardening, /pachanga_platform_require_v1\('entitlements\.write'\)/);
});

test("the R5 rollback bundle extends the historical public R4C fixture without changing it", async () => {
  const [fixture, r5Fixture, databaseStory] = await Promise.all([
    source("tests/league-match-operations-v1-fixture.sql"),
    source("tests/competition-discipline-v1-fixture.sql"),
    source("tests/competition-discipline-v1-db.sql"),
  ]);
  assert.match(fixture, /'R4C League 2027'[\s\S]+?'LEAGUE', 'public', 'draft'/);
  assert.match(fixture, /'Senior', 'senior', 'FOOTBALL_7', 'public', 'active'/);
  assert.equal(
    (databaseStory.match(/from public\.pachanga_competition_discipline_rule_catalogs\s+where competition_id = 'c4200000-0000-4000-8000-000000000001'/g) ?? []).length,
    2,
  );
  for (const capability of [
    "competition_discipline_manage",
    "competition_discipline_review",
    "competition_appeals_manage",
  ]) assert.match(r5Fixture, new RegExp(`'${capability}'`));
  assert.doesNotMatch(fixture, /competition_discipline_manage|LEAGUE_PRIVATE_BETA_V1: R5 rollback fixture/);
  assert.match(r5Fixture, /bundle_id = 'c4b00000-0000-4000-8000-000000000001'/);
  assert.match(r5Fixture, /valid_from = '2026-01-01T00:00:00Z',[\s\S]+expires_at = '2099-12-31T23:59:59Z'/);
});
