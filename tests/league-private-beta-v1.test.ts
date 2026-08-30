import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  leaguePrivateBetaActions,
  leaguePrivateBetaPlatformActions,
  leaguePrivateBetaRealtimeTable,
  leaguePrivateBetaSteps,
} from "../app/league-private-beta-contract";
import { classifySupabaseWrite, isKnownClientWriteOperation } from "../app/pwa-write-classifier";

const root = new URL("../", import.meta.url);
const paths = {
  access: "supabase/migrations/20260825074358_league_private_beta_access_v1.sql",
  commands: "supabase/migrations/20260825074353_league_private_beta_commands_v1.sql",
  databaseSuite: "tests/league-private-beta-v1-db.sql",
  draftEditionFix: "supabase/migrations/20260825115500_league_private_beta_draft_edition_fix.sql",
  indexes: "supabase/migrations/20260825102400_league_private_beta_fk_indexes_v1.sql",
  schema: "supabase/migrations/20260825074304_league_private_beta_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("League Private Beta exposes the six Wizard V2 commands, four platform commands and twelve canonical steps", () => {
  assert.deepEqual(leaguePrivateBetaActions, [
    "wizard.create", "wizard.mode.set", "wizard.preset.apply", "wizard.step.save", "wizard.cancel", "wizard.finalize",
  ]);
  assert.deepEqual(leaguePrivateBetaPlatformActions, [
    "beta.flags.set", "beta.kill_switch", "beta.bundle.grant", "beta.bundle.revoke",
  ]);
  assert.equal(leaguePrivateBetaSteps.length, 12);
  assert.deepEqual(leaguePrivateBetaSteps.map((step) => step.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
});

test("productization installs fully disabled and does not create product data", async () => {
  const schema = await source(paths.schema);
  for (const flag of [
    "league_private_beta_enabled",
    "league_private_beta_creation_enabled",
    "league_private_beta_public_discovery_enabled",
  ]) assert.match(schema, new RegExp(`${flag} boolean not null default false`));
  assert.match(schema, /creates no League, grant or fixture and leaves every gate OFF/i);
  assert.doesNotMatch(schema, /insert into public\.pachanga_competitions\b/i);
  assert.doesNotMatch(schema, /insert into public\.pachanga_competition_entitlement_grants\b/i);
});

test("wizard finalization keeps the Edition draft until canonical registration opens", async () => {
  const migration = await source(paths.draftEditionFix);
  assert.match(migration, /before insert on public\.pachanga_competition_editions/);
  assert.match(migration, /new\.status := 'draft'/);
  assert.match(migration, /new\.registration_opens_at := null/);
  assert.match(migration, /target_action = 'wizard\.finalize'/);
  assert.match(migration, /open_registration/);
  assert.match(migration, /editionStatus/);
  assert.doesNotMatch(migration, /update\s+public\.pachanga_competition_editions/i);
});

test("the schema reuses canonical entitlements and enforces private League shape", async () => {
  const schema = await source(paths.schema);
  assert.match(schema, /alter table public\.pachanga_competition_entitlement_grants/);
  assert.match(schema, /program_key text/);
  assert.match(schema, /bundle_id uuid/);
  assert.match(schema, /beta_team_cap smallint/);
  assert.match(schema, /LEAGUE_PRIVATE_BETA_V1/);
  assert.match(schema, /pachanga_beta_active_team_competition_idx/);
  assert.match(schema, /pachanga_beta_active_club_competition_idx/);
  assert.match(schema, /league_private_beta_max_active_editions_per_organizer smallint not null default 1/);
  assert.match(schema, /team_cap between 4 and 20/i);
  assert.match(schema, /not league_private_beta_public_discovery_enabled/);
  assert.match(schema, /not league_public_registration_enabled/);
  assert.match(schema, /not league_public_calendar_enabled/);
  assert.match(schema, /not league_public_standings_enabled/);
  assert.match(schema, /not league_public_exception_status_enabled/);
});

test("server commands require global gates plus an unexpired organizer bundle", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /pachanga_league_private_beta_active_bundle_id_v1/);
  assert.match(commands, /LEAGUE_PRIVATE_BETA_DISABLED/);
  assert.match(commands, /LEAGUE_PRIVATE_BETA_CREATION_DISABLED/);
  assert.match(commands, /LEAGUE_PRIVATE_BETA_GRANT_REQUIRED/);
  assert.match(commands, /program_key = 'LEAGUE_PRIVATE_BETA_V1'/);
  assert.match(commands, /expires_at is null or[^;]+expires_at > statement_timestamp\(\)/s);
  assert.match(commands, /TEAM_OWNER_REQUIRED/);
  assert.match(commands, /CLUB_COMPETITION_MANAGER_REQUIRED/);
  assert.match(commands, /actor_role is distinct from 'team_owner'/);
});

test("capacity and one-edition limits fail closed", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /team_cap < 4 or team_cap > 20/);
  assert.match(commands, /team_cap > 12 and not coalesce/);
  assert.match(commands, /BETA_CAPACITY_LIMIT/);
  assert.match(commands, /LEAGUE_BETA_ACTIVE_EDITION_LIMIT/);
  assert.match(commands, /product_key = 'LEAGUE_PRIVATE_BETA_V1'/);
  assert.match(commands, /'LEAGUE', 'private', 'draft', 'LEAGUE_PRIVATE_BETA_V1'/);
  assert.match(commands, /registration_mode[^;]+INVITE_ONLY/s);
});

test("PostgreSQL owns actor, revision, sequence, idempotency and final materialization", async () => {
  const commands = await source(paths.commands);
  assert.match(commands, /actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(commands, /pg_advisory_xact_lock/);
  assert.match(commands, /pachanga_league_private_beta_replay_v1/);
  assert.match(commands, /STALE_REVISION/);
  assert.match(commands, /nextval\('private\.pachanga_competition_sequence'\)/);
  assert.match(commands, /insert into public\.pachanga_competitions/);
  assert.match(commands, /insert into public\.pachanga_competition_rule_revisions/);
  assert.match(commands, /insert into public\.pachanga_competition_editions/);
  assert.match(commands, /insert into public\.pachanga_competition_stages/);
  assert.match(commands, /status[^;]+'frozen'/s);
  assert.doesNotMatch(commands, /payload\s*->>\s*'(?:actorId|actor_id|serverSequence|confirmedAt|revision)'/i);
});

test("payments and tournaments stay unavailable while Wave 5A derives discipline and referee policy", async () => {
  const [commands, access, rules] = await Promise.all([
    source(paths.commands),
    source(paths.access),
    source("supabase/migrations/20260826123100_competition_configuration_rules_v1.sql"),
  ]);
  for (const domain of ["payments", "tournaments"]) {
    assert.match(commands, new RegExp(`['\"]${domain}['\"][^\n]+false`));
  }
  assert.match(access, /competition_discipline/);
  assert.match(access, /referee_assignments/);
  assert.match(access, /payments/);
  assert.match(access, /tournaments/);
  assert.match(rules, /'refereeAssignments', referee_step ->> 'usage' <> 'NONE'/);
  assert.match(rules, /'discipline', coalesce\(\(discipline_step ->> 'enabled'\)::boolean, false\)/);
});

test("private read models are bounded, stable and never ordered by timestamp alone", async () => {
  const access = await source(paths.access);
  for (const rpc of [
    "get_pachanga_league_private_beta_flags_v1",
    "get_pachanga_league_private_beta_wizard_v1",
    "get_my_pachanga_league_private_beta_v1",
    "get_pachanga_platform_league_private_beta_v1",
  ]) assert.match(access, new RegExp(`create or replace function public\\.${rpc}`));
  assert.match(access, /server_sequence desc, [^\n]*id desc/);
  assert.doesNotMatch(access, /order by\s+(?:created_at|updated_at|confirmed_at)\s+desc\s*(?:limit|\)|;|$)/i);
  assert.match(access, /least\(greatest\(coalesce\(page_size, 30\), 1\), 100\)/);
  assert.match(access, /bounded_candidates[\s\S]+limit 100/);
  assert.match(access, /bounded_bundles[\s\S]+limit 100/);
  assert.match(access, /target_wizards[\s\S]+server_sequence desc[\s\S]+limit 100/);
  assert.match(access, /pachanga_league_private_beta_actor_can_read_wizard_v1/);
  assert.match(access, /publicExposureViolations/);
});

test("RLS and grants expose reads and RPCs without direct canonical writes", async () => {
  const [schema, commands, access] = await Promise.all([
    source(paths.schema), source(paths.commands), source(paths.access),
  ]);
  const sql = `${schema}\n${commands}\n${access}`;
  for (const table of [
    "pachanga_league_private_beta_wizards",
    "pachanga_league_private_beta_operation_receipts",
    "pachanga_league_private_beta_events",
  ]) assert.match(sql, new RegExp(`revoke all on table (?:public|private)\\.${table}[\\s\\S]{0,80}from public, anon, authenticated`));
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table (?:public|private)\.pachanga_league_private_beta_[^;]+ to authenticated/i);
  assert.match(commands, /grant execute on function public\.command_pachanga_league_private_beta_v1/);
  assert.match(commands, /grant execute on function public\.command_pachanga_league_private_beta_platform_v1/);
});

test("every productization foreign key reported by staging advisors has a covering index", async () => {
  const indexes = await source(paths.indexes);
  for (const column of [
    "actor_id",
    "competition_id",
    "organizer_club_id",
    "organizer_group_id",
    "wizard_id",
  ]) assert.match(indexes, new RegExp(`\\(${column}\\)`));
  assert.equal((indexes.match(/create index if not exists/g) ?? []).length, 8);
  assert.doesNotMatch(indexes, /insert|update|delete|league_private_beta_enabled\s*=/i);
});

test("API accepts semantic intent only, is no-store and carries no service role", async () => {
  const [shared, commandRoute, readRoute, wizardRoute, platformRoute] = await Promise.all([
    source("app/api/leagues/private-beta/_shared.ts"),
    source("app/api/leagues/private-beta/command/route.ts"),
    source("app/api/leagues/private-beta/my/route.ts"),
    source("app/api/leagues/private-beta/wizard/[wizardId]/route.ts"),
    source("app/api/platform-admin/league-private-beta/route.ts"),
  ]);
  assert.match(shared, /const stepKeys/);
  assert.match(shared, /Object\.keys\(data\)\.some/);
  assert.match(shared, /headers: noStoreHeaders/);
  assert.match(commandRoute, /requireLeagueBetaOrigin/);
  assert.match(commandRoute, /leagueBetaWriteGate/);
  assert.match(commandRoute, /operationId/);
  assert.match(commandRoute, /expectedRevision/);
  assert.match(platformRoute, /requireSameOriginMutation/);
  assert.match(platformRoute, /clientWriteGateResponse/);
  assert.doesNotMatch(`${shared}\n${commandRoute}\n${readRoute}\n${wizardRoute}\n${platformRoute}`, /SUPABASE_SERVICE_ROLE_KEY|service_role/i);
});

test("PWA classifies both RPC and API writes and never queues an offline sporting mutation", async () => {
  for (const rpc of [
    "command_pachanga_league_private_beta_v1",
    "command_pachanga_league_private_beta_platform_v1",
  ]) {
    assert.equal(
      classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }),
      `rpc:${rpc}`,
    );
  }
  assert.equal(isKnownClientWriteOperation("api:league-private-beta-command"), true);
  assert.equal(isKnownClientWriteOperation("api:platform-admin-league-private-beta"), true);
  const client = await source("app/_components/league-private-beta-client.tsx");
  assert.match(client, /clientWriteFetch\("api:league-private-beta-command"/);
  assert.match(client, /Esperando confirmación de PostgreSQL/);
  assert.match(client, /Cambio confirmado por el servidor/);
  assert.doesNotMatch(client, /pending(?:Operations|Mutations)|offlineQueue|queueOffline/i);
});

test("Realtime invalidates and refetches canonical state instead of trusting WAL", async () => {
  const [client, access] = await Promise.all([
    source("app/_components/league-private-beta-client.tsx"),
    source(paths.access),
  ]);
  assert.equal(leaguePrivateBetaRealtimeTable, "pachanga_league_private_beta_invalidations");
  assert.match(client, /state === "SUBSCRIBED"/);
  assert.match(client, /loadDashboard\(token, actorId, "realtime"\)/);
  assert.match(client, /loadWizard\(leagueBetaText\(currentWizard\.id\), token\)/);
  assert.match(client, /addEventListener\("online", reconcile\)/);
  assert.match(client, /removeEventListener\("online", reconcile\)/);
  assert.doesNotMatch(client, /setData\([^)]*payload\.new/);
  assert.match(access, /alter publication supabase_realtime[\s\S]+add table public\.pachanga_league_private_beta_invalidations/);
});

test("Official UI provides private eligibility, twelve-step wizard and responsive game layouts", async () => {
  const [page, client, css, shell, adminPage, adminClient, navigation] = await Promise.all([
    source("app/ligas/page.tsx"),
    source("app/_components/league-private-beta-client.tsx"),
    source("app/_components/league-private-beta-client.module.css"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/admin/competitions/page.tsx"),
    source("app/admin/competitions/league-private-beta-admin-client.tsx"),
    source("app/_components/product-navigation-contract.ts"),
  ]);
  assert.match(page, /follow: false, index: false/);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /Esta beta está disponible únicamente para organizadores autorizados/);
  assert.match(client, /Liga privada/);
  assert.match(client, /Fuera de esta fase/);
  assert.match(client, /Disciplina R5/);
  assert.match(client, /Árbitros asignados/);
  assert.match(client, /Reglas configurables, congeladas y auditables/);
  assert.match(client, /pachangas-league-private-beta-read-v1/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(css, /min-width: 0/);
  assert.match(shell, /contextualDestinationsForPerspective\(perspective\)/);
  assert.match(navigation, /href: "\/ligas"/);
  assert.match(adminPage, /League Private Beta/);
  assert.match(adminClient, /Apagado inmediato/);
  assert.match(adminClient, /Conceder 11 capacidades/);
});

test("SQL suite covers authorization, replay, stale revisions, privacy and protected domains", async () => {
  const sql = await source(paths.databaseSuite);
  for (const evidence of [
    "TEAM_OWNER_REQUIRED",
    "LEAGUE_PRIVATE_BETA_GRANT_REQUIRED",
    "Idempotent replay",
    "STALE_REVISION",
    "INVITE_ONLY",
    "public exposure",
    "Rating V2",
    "conduct or moderation",
  ]) assert.match(sql, new RegExp(evidence, "i"));
});

test("the authenticated staging runner composes R1 through R4D and restores the private gates", async () => {
  const [runner, scheduling, matchOperations, exceptions, packageJson] = await Promise.all([
    source("tests/league-private-beta-v1-staging-e2e.mjs"),
    source("tests/league-scheduling-v1-staging-e2e.mjs"),
    source("tests/league-match-operations-v1-staging-extension.mjs"),
    source("tests/league-operational-exceptions-v1-staging-extension.mjs"),
    source("package.json"),
  ]);
  assert.match(runner, /LEAGUE_PRIVATE_BETA_STAGING_EXTENSION = "1"/);
  assert.match(runner, /R4C_STAGING_EXTENSION = "1"/);
  assert.match(runner, /R4D_STAGING_EXTENSION = "1"/);
  assert.match(packageJson, /test:league-private-beta:staging/);
  assert.match(scheduling, /Expired grant negative case/);
  assert.match(scheduling, /valid_from: new Date\(expiredAt\.getTime\(\) - 60_000\)/);
  assert.match(scheduling, /Public registration negative case/);
  assert.match(scheduling, /LEAGUE_PUBLIC_REGISTRATION_DISABLED/);
  assert.match(scheduling, /activeQaBundles/);
  assert.match(scheduling, /PUBLIC_CALENDAR_DISABLED/);
  assert.match(scheduling, /updateUserById\(member\.userId/);
  assert.match(scheduling, /R4B_STAGING_SIGN_IN_FAILED:\$\{role\}/);
  assert.match(scheduling, /from\("pachanga_competition_categories"\)/);
  assert.doesNotMatch(scheduling, /betaCompetitionState\.categories/);
  assert.match(scheduling, /"userId" in invitedDelegate, false/);
  assert.match(scheduling, /r4b-qa-private-beta-/);
  assert.match(scheduling, /notificationCount, PRIVATE_BETA_EXTENSION \? 12 : 6/);
  assert.match(scheduling, /organizerModel\(organizerClient, organizerKind, organizerId\)/);
  assert.match(scheduling, /const WIZARD_V2_WINDOW = PRIVATE_BETA_EXTENSION/);
  assert.match(scheduling, /League Private Beta Wizard V2 dependency window/);
  assert.match(scheduling, /League Private Beta Wizard V2 restore/);
  assert.match(scheduling, /\["beta", cleanupReadback\.beta, initialFlagState\.beta\]/);
  assert.match(scheduling, /\["configuration", cleanupReadback\.configuration, initialFlagState\.configuration\]/);
  assert.match(scheduling, /typeof value === "boolean"/);
  assert.match(scheduling, /actual\[key\], value, `\$\{label\}\.\$\{key\} must match the initial snapshot`/);
  assert.match(scheduling, /flags: "restored_initial"/);
  const activationOrder = [
    "League Private Beta gate enabled before dependencies",
    "League Private Beta R4B dependency window",
    "League Private Beta R4C dependency window",
    "League Private Beta R4D dependency window",
    "League Private Beta creation enabled after dependencies",
  ].map((marker) => scheduling.indexOf(marker));
  assert.equal(activationOrder.every((index) => index >= 0), true);
  assert.deepEqual([...activationOrder].sort((left, right) => left - right), activationOrder);
  assert.match(matchOperations, /if \(!privateBeta\)[\s\S]+R4C authenticated staging window/);
  assert.match(exceptions, /if \(!privateBeta\)[\s\S]+R4D staging dependency window/);
  assert.match(matchOperations, /PUBLIC_STANDINGS_DISABLED/);
  assert.match(exceptions, /PUBLIC_EXCEPTION_STATUS_DISABLED/);
  assert.match(exceptions, /stageContext\(accepted, "scheduled"/);
  assert.match(exceptions, /stageContext\(raceFixture, "scheduled"/);
  assert.match(exceptions, /currentSportingScore\(resumed\)/);
  assert.match(exceptions, /partialScoreHome: resumedScore\.scoreHome/);
  assert.match(exceptions, /R4D_SUSPENSION_RESULT_CONFLICT/);
  assert.match(exceptions, /administrative_result_conflict_blocked/);
});

test("the scale command provisions an isolated local database instead of trusting a prepared target", async () => {
  const [runner, packageJson] = await Promise.all([
    source("tests/league-private-beta-v1-db-runner.mjs"),
    source("package.json"),
  ]);
  assert.match(packageJson, /LEAGUE_PRIVATE_BETA_INCLUDE_SCALE=1 node tests\/league-private-beta-v1-db-runner\.mjs/);
  assert.match(runner, /LEAGUE_PRIVATE_BETA_DB_TEST_LOCAL_DATABASE_REQUIRED/);
  assert.match(runner, /league-private-beta-v1-scale\.sql/);
  assert.match(runner, /dropDatabase\(\)/);
});
