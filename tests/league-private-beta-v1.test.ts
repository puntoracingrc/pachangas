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
  schema: "supabase/migrations/20260825074304_league_private_beta_schema_v1.sql",
} as const;

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

test("League Private Beta exposes the four user commands, four platform commands and ten canonical steps", () => {
  assert.deepEqual(leaguePrivateBetaActions, [
    "wizard.create", "wizard.step.save", "wizard.cancel", "wizard.finalize",
  ]);
  assert.deepEqual(leaguePrivateBetaPlatformActions, [
    "beta.flags.set", "beta.kill_switch", "beta.bundle.grant", "beta.bundle.revoke",
  ]);
  assert.equal(leaguePrivateBetaSteps.length, 10);
  assert.deepEqual(leaguePrivateBetaSteps.map((step) => step.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
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

test("future domains remain explicitly unavailable", async () => {
  const [commands, access] = await Promise.all([source(paths.commands), source(paths.access)]);
  for (const domain of ["discipline", "refereeAssignments", "payments", "tournaments"]) {
    assert.match(commands, new RegExp(`['\"]${domain}['\"][^\n]+false`));
  }
  assert.match(access, /competition_discipline/);
  assert.match(access, /referee_assignments/);
  assert.match(access, /payments/);
  assert.match(access, /tournaments/);
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

test("Official UI provides private eligibility, ten-step wizard and responsive game layouts", async () => {
  const [page, client, css, shell, adminPage, adminClient] = await Promise.all([
    source("app/ligas/page.tsx"),
    source("app/_components/league-private-beta-client.tsx"),
    source("app/_components/league-private-beta-client.module.css"),
    source("app/_components/official-product-shell-v2.tsx"),
    source("app/admin/competitions/page.tsx"),
    source("app/admin/competitions/league-private-beta-admin-client.tsx"),
  ]);
  assert.match(page, /follow: false, index: false/);
  assert.match(client, /OfficialProductShellV2/);
  assert.match(client, /Esta beta está disponible únicamente para organizadores autorizados/);
  assert.match(client, /Liga privada/);
  assert.match(client, /No disponible en esta beta/);
  assert.match(client, /Reglas propias congeladas/);
  assert.match(client, /pachangas-league-private-beta-read-v1/);
  assert.match(css, /orientation: portrait/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(css, /min-width: 0/);
  assert.match(shell, /href="\/ligas"/);
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
  assert.match(scheduling, /Public registration negative case/);
  assert.match(scheduling, /activeQaBundles/);
  assert.match(scheduling, /PUBLIC_CALENDAR_DISABLED/);
  assert.match(matchOperations, /PUBLIC_STANDINGS_DISABLED/);
  assert.match(exceptions, /PUBLIC_EXCEPTION_STATUS_DISABLED/);
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
