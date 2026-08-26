import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  competitionConfigurationActions,
  competitionConfigurationRealtimeTable,
} from "../app/competition-configuration-contract";
import {
  leaguePrivateBetaActions,
  leaguePrivateBetaPresets,
  leaguePrivateBetaSteps,
} from "../app/league-private-beta-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const migrations = {
  commands: "supabase/migrations/20260826123300_competition_configuration_commands_v1.sql",
  control: "supabase/migrations/20260826123500_competition_configuration_control_center_v1.sql",
  engines: "supabase/migrations/20260826123400_competition_configuration_engine_policy_v1.sql",
  rules: "supabase/migrations/20260826123100_competition_configuration_rules_v1.sql",
  schema: "supabase/migrations/20260826123000_competition_configuration_center_schema_v1.sql",
  wizard: "supabase/migrations/20260826123200_league_wizard_v2_commands.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("Wave 5A exposes four presets, twelve wizard steps and the bounded configuration command set", () => {
  assert.deepEqual(leaguePrivateBetaPresets.map(({ key }) => key), [
    "LEAGUE_F7_STANDARD", "LEAGUE_F5_QUICK", "LEAGUE_F11", "LEAGUE_FUTSAL",
  ]);
  assert.deepEqual(leaguePrivateBetaSteps.map(({ id }) => id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  assert.deepEqual(leaguePrivateBetaActions, [
    "wizard.create", "wizard.mode.set", "wizard.preset.apply", "wizard.step.save", "wizard.cancel", "wizard.finalize",
  ]);
  assert.deepEqual(competitionConfigurationActions, [
    "draft.create", "draft.clone", "draft.mode.set", "draft.preset.apply",
    "draft.section.save", "draft.validate", "draft.publish", "draft.cancel",
  ]);
});

test("the API accepts bounded semantic authoring intent and rejects unknown modes, presets and actions", async () => {
  const shared = await source("app/api/competitions/configuration/_shared.ts");
  assert.match(shared, /isCompetitionConfigurationAction/);
  assert.match(shared, /INVALID_COMPETITION_CONFIGURATION_COMMAND/);
  assert.match(shared, /\["SIMPLE", "ADVANCED"\]\.includes/);
  assert.match(shared, /LEAGUE_F5_QUICK/);
  assert.match(shared, /LEAGUE_F7_STANDARD/);
  assert.match(shared, /LEAGUE_F11/);
  assert.match(shared, /LEAGUE_FUTSAL/);
  assert.match(shared, /confirmImpact: input\.confirmImpact === true/);
  assert.match(shared, /confirmRuleSummary: input\.confirmRuleSummary === true/);
  assert.doesNotMatch(shared, /actorId|serverSequence|confirmedRevision/);
});

test("schema installs Configuration Center and Wizard V2 disabled with private receipts and public invalidations", async () => {
  const schema = await source(migrations.schema);
  assert.match(schema, /competition_configuration_center_enabled boolean not null default false/);
  assert.match(schema, /league_wizard_v2_enabled boolean not null default false/);
  assert.match(schema, /create table private\.pachanga_competition_configuration_drafts/);
  assert.match(schema, /create table private\.pachanga_competition_configuration_receipts/);
  assert.match(schema, /operation_id uuid not null unique/);
  assert.match(schema, /server_sequence bigint not null unique/);
  assert.match(schema, /create table public\.pachanga_competition_configuration_invalidations/);
  assert.match(schema, /alter publication supabase_realtime[\s\S]+pachanga_competition_configuration_invalidations/);
  assert.doesNotMatch(schema, /insert into public\.pachanga_competitions\b/i);
});

test("presets materialize one canonical schema with health, human summaries and future capabilities kept off", async () => {
  const rules = await source(migrations.rules);
  for (const preset of ["LEAGUE_F5_QUICK", "LEAGUE_F7_STANDARD", "LEAGUE_F11", "LEAGUE_FUTSAL"]) {
    assert.match(rules, new RegExp(preset));
  }
  assert.match(rules, /competition-configuration\.v1/);
  assert.match(rules, /pachanga_competition_configuration_health_v1/);
  assert.match(rules, /pachanga_competition_configuration_human_document_v1/);
  assert.match(rules, /pachanga_competition_configuration_diff_v1/);
  assert.match(rules, /'payments', false, 'tournaments', false/);
  assert.match(rules, /'manualAssistedPairing', false, 'hybridPairing', false/);
  assert.match(rules, /'pairingMode', 'AUTOMATIC_ROUND_ROBIN'/);
});

test("Wizard V2 initializes all twelve sections and V1 clients delegate into the same authority", async () => {
  const wizard = await source(migrations.wizard);
  assert.match(wizard, /wizard_version := 2/);
  assert.match(wizard, /array\[1,2,3,4,5,6,7,8,9,10,11,12\]/);
  assert.match(wizard, /wizard\.mode\.set/);
  assert.match(wizard, /wizard\.preset\.apply/);
  assert.match(wizard, /command_pachanga_league_private_beta_legacy_v1/);
  assert.match(wizard, /create or replace function public\.command_pachanga_league_private_beta_v2/);
  assert.match(wizard, /create or replace function public\.command_pachanga_league_private_beta_v1/);
  assert.match(wizard, /LEAGUE_BETA_CONFIGURATION_INVALID/);
  assert.match(wizard, /LEAGUE_BETA_CONSENT_REQUIRED/);
});

test("PostgreSQL owns actor, locking, revisions, idempotency, validation and immutable publication", async () => {
  const commands = await source(migrations.commands);
  assert.match(commands, /actor_id uuid:=auth\.uid\(\)/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /pachanga_competition_configuration_replay_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /COMPETITION_CONFIGURATION_REVALIDATION_REQUIRED/);
  assert.match(commands, /COMPETITION_CONFIGURATION_CONFIRMATION_REQUIRED/);
  assert.match(commands, /insert into public\.pachanga_competition_rule_revisions/);
  assert.match(commands, /effective_scope/);
  assert.match(commands, /status='published',materialized_rule_revision_id=new_revision_id/);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|actor_id|serverSequence|confirmedRevision)'/i);
  assert.doesNotMatch(commands, /update\s+public\.pachanga_competition_rule_revisions/i);
});

test("read models redact private fixed fees and order revisions by version plus stable id", async () => {
  const commands = await source(migrations.commands);
  assert.match(commands, /public_referee -> 'fee'.*array\['fixedCents'\]/s);
  assert.match(commands, /rule_revisions\.version desc,rule_revisions\.id desc limit 50/);
  assert.match(commands, /get_pachanga_competition_configuration_v1/);
  assert.doesNotMatch(commands, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|;|\))/i);
});

test("R5 and Referee Assignments consume the frozen RuleRevision rather than browser policy", async () => {
  const engines = await source(migrations.engines);
  assert.match(engines, /pachanga_competition_discipline_policy_for_rule_v1/);
  assert.match(engines, /pachanga_competition_discipline_rule_catalogs/);
  assert.match(engines, /pachanga_competition_referee_policy_v1\(context_row\.rule_revision_id\)/);
  assert.match(engines, /REFEREE_ASSIGNMENTS_DISABLED_BY_RULE_REVISION/);
  assert.match(engines, /REFEREE_REQUIRED_BEFORE_MATCH_READY/);
  assert.match(engines, /new\.fee_mode:=configured_mode/);
  assert.match(engines, /new\.proposed_fee_cents:=\(fee ->> 'fixedCents'\)::integer/);
  assert.match(engines, /command_pachanga_referee_incident_observation_v1/);
  assert.doesNotMatch(engines, /payload\s*->>\s*'(?:ruleDocument|cardTypeCatalog|refereePolicy)'/i);
});

test("cross-engine guards serialize configuration against registration, scheduling, results, discipline and assignments", async () => {
  const engines = await source(migrations.engines);
  for (const trigger of [
    "aa_pachanga_competition_configuration_edition_guard_v1",
    "aa_pachanga_competition_configuration_schedule_guard_v1",
    "aa_pachanga_competition_configuration_result_guard_v1",
    "aa_pachanga_competition_configuration_discipline_guard_v1",
    "aa_pachanga_competition_configuration_assignment_guard_v1",
  ]) assert.match(engines, new RegExp(trigger));
  assert.match(engines, /pachanga_competition_configuration_engine_guard_v1/);
  assert.match(engines, /pg_advisory_xact_lock/);
});

test("RLS and grants expose only command/read RPCs and no direct client mutation", async () => {
  const sql = (await Promise.all(Object.values(migrations).map(source))).join("\n");
  assert.match(sql, /grant execute on function public\.command_pachanga_competition_configuration_v1/);
  assert.match(sql, /grant execute on function public\.get_pachanga_competition_configuration_v1/);
  assert.match(sql, /revoke all on table[\s\S]+pachanga_competition_configuration_drafts[\s\S]+from public, anon, authenticated/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table (?:public|private)\.pachanga_competition_configuration_[^;]+ to authenticated/i);
  assert.equal(competitionConfigurationRealtimeTable, "pachanga_competition_configuration_invalidations");
});

test("API, PWA and Realtime enforce server confirmation without an offline sporting queue", async () => {
  const [shared, route, readRoute, client] = await Promise.all([
    source("app/api/competitions/configuration/_shared.ts"),
    source("app/api/competitions/configuration/command/route.ts"),
    source("app/api/competitions/configuration/[competitionId]/route.ts"),
    source("app/_components/competition-configuration-client.tsx"),
  ]);
  assert.match(shared, /headers: noStoreHeaders/);
  assert.match(route, /requireConfigurationOrigin/);
  assert.match(route, /configurationWriteGate/);
  assert.match(route, /operationId/);
  assert.match(route, /expectedRevision/);
  assert.match(readRoute, /get_pachanga_competition_configuration_v1/);
  assert.doesNotMatch(`${shared}\n${route}\n${readRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
  assert.match(client, /clientWriteFetch\("api:competition-configuration-command"/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /state === "SUBSCRIBED"/);
  assert.match(client, /load\(token, actorId, "realtime"\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new|offlineQueue|queueOffline|pendingOperations/i);
  assert.equal(isKnownClientWriteOperation("api:competition-configuration-command"), true);
  assert.equal(
    classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_competition_configuration_v1", { method: "POST" }),
    "rpc:command_pachanga_competition_configuration_v1",
  );
  assert.equal(
    classifySupabaseWrite("https://example.supabase.co/rest/v1/rpc/command_pachanga_referee_incident_observation_v1", { method: "POST" }),
    "rpc:command_pachanga_referee_incident_observation_v1",
  );
});

test("Official UI exposes Configuration Center, twelve-step authoring and Control Center health", async () => {
  const [leagueClient, configurationClient, fields, adminPage, css] = await Promise.all([
    source("app/_components/league-private-beta-client.tsx"),
    source("app/_components/competition-configuration-client.tsx"),
    source("app/_components/competition-configuration-fields.tsx"),
    source("app/admin/competitions/page.tsx"),
    source("app/_components/competition-configuration-client.module.css"),
  ]);
  assert.match(leagueClient, /leaguePrivateBetaSteps/);
  assert.match(leagueClient, /CompetitionConfigurationFields/);
  assert.match(leagueClient, /Sencillo/);
  assert.match(leagueClient, /Avanzado/);
  assert.match(leagueClient, /href=\{`\/competiciones\/\$\{id\}\/configuracion`\}/);
  assert.match(configurationClient, /Impacto y diferencias/);
  assert.match(configurationClient, /Publicar RuleRevision/);
  assert.match(configurationClient, /Funciones apagadas/);
  assert.match(fields, /step === 10/);
  assert.match(fields, /step === 11/);
  assert.match(adminPage, /Competition Configuration Center/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /min-width: 0/);
});

test("Control Center remains coupled to League Private Beta and keeps public competition surfaces off", async () => {
  const control = await source(migrations.control);
  assert.match(control, /pachanga_competition_configuration_gate_dependencies_v1/);
  assert.match(control, /new\.competition_configuration_center_enabled := false/);
  assert.match(control, /new\.league_wizard_v2_enabled := false/);
  assert.match(control, /get_pachanga_platform_competition_configuration_v1/);
  assert.match(control, /publicSurfacesOff/);
  assert.match(control, /legacyBackfillCount/);
});

test("SQL regression suite protects idempotency, privacy, engines and unrelated domains", async () => {
  const sql = await source("tests/competition-configuration-center-v1-db.sql");
  for (const marker of [
    "COMPETITION_CONFIGURATION_CENTER_V1_DB_OK",
    "idempotent create replay",
    "STALE_REVISION",
    "fixedCents",
    "R5",
    "Referee",
    "Rating",
    "Rewards",
    "Conduct",
    "Billing",
  ]) assert.match(sql, new RegExp(marker, "i"));
});
