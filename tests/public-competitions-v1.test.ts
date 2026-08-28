import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  classifySupabaseWrite,
  isKnownClientWriteOperation,
} from "../app/pwa-write-classifier";
import {
  publicCompetitionPublicationActions,
  publicCompetitionRegistrationActions,
} from "../app/public-competition-contract";

const migrations = [
  "supabase/migrations/20260828072045_tournament_knockout_fk_index_hardening_v1.sql",
  "supabase/migrations/20260828072047_public_competition_publication_consent_v1.sql",
  "supabase/migrations/20260828072048_competition_registration_requests_waitlist_v1.sql",
  "supabase/migrations/20260828072049_public_competition_read_models_directory_v1.sql",
  "supabase/migrations/20260828072051_public_competition_commands_authority_v1.sql",
  "supabase/migrations/20260828072052_public_competition_access_realtime_v1.sql",
  "supabase/migrations/20260828072053_public_competition_product_flags_hardening_v1.sql",
] as const;

function source(path: string) {
  return readFile(new URL(`../${path}`, import.meta.url), "utf8");
}

async function migrationSource() {
  return (await Promise.all(migrations.map(source))).join("\n");
}

test("Wave 7A owns exactly seven forward migrations after ledger 176", async () => {
  assert.equal(migrations.length, 7);
  const sql = await migrationSource();
  for (const marker of [
    "pachanga_competition_publications",
    "pachanga_competition_publication_consents",
    "pachanga_competition_publication_reviews",
    "pachanga_competition_registration_requests",
    "pachanga_competition_registration_request_revisions",
    "pachanga_public_competition_read_models",
    "pachanga_public_competition_fixture_read_models",
  ]) assert.match(sql, new RegExp(marker));
  assert.doesNotMatch(sql, /create table (?:public\.)?(?:PublicLeague|PublicTournament|PublicCompetitionCopy|PublicRegistrationCompetition)\b/i);
});

test("publication, registration and moderation expose only semantic actions", () => {
  assert.deepEqual(publicCompetitionPublicationActions, [
    "publication.prepare", "publication.update", "publication.consent",
    "publication.submit", "publication.withdraw", "publication.unpublish",
    "registration.configure",
  ]);
  assert.deepEqual(publicCompetitionRegistrationActions, [
    "registration.submit", "registration.message.update", "registration.withdraw",
    "registration.under_review", "registration.waitlist", "registration.accept",
    "registration.reject", "waitlist.reorder", "competition.report",
  ]);
});

test("browser payload allowlists exclude actor, capacity, snapshots and sequence", async () => {
  const shared = await source("app/api/competitions/public/_shared.ts");
  assert.match(shared, /publicCompetitionUuidPattern = \/\^\[0-9a-f\]\{8\}/);
  assert.match(shared, /if \(Object\.keys\(source\)\.some\(\(key\) => !\(key in limits\)\)\)/);
  assert.match(shared, /new Set\(\["teamId", "message", "reason"\]\)|action === "registration\.submit"/);
  assert.match(shared, /message: boundedText\(input\.message, 1000\)/);
  assert.match(shared, /teamId: uuid\(input\.teamId\)/);
  assert.match(shared, /PUBLIC_COMPETITION_DISCIPLINE_DISABLED/);
  assert.doesNotMatch(shared, /\b(?:actorId|actor_id|capacitySnapshot|teamSnapshot|serverSequence)\s*:\s*(?:input|source|payload)/);
});

test("every Wave 7A write is classified by the permanent PWA bridge", () => {
  for (const operation of [
    "api:platform-admin-public-competitions",
    "api:public-competition-command",
    "api:public-competition-publication",
  ]) assert.equal(isKnownClientWriteOperation(operation), true, operation);
  for (const rpc of [
    "command_pachanga_competition_publication_v1",
    "command_pachanga_competition_registration_request_v1",
    "command_pachanga_public_competition_moderation_v1",
    "set_pachanga_public_competition_flags_v1",
  ]) {
    assert.equal(
      classifySupabaseWrite(`https://example.supabase.co/rest/v1/rpc/${rpc}`, { method: "POST" }),
      `rpc:${rpc}`,
      rpc,
    );
  }
  assert.equal(classifySupabaseWrite("https://example.test/api/competitions/public/directory", { method: "GET" }), null);
});

test("write APIs are no-store, same-origin, version-gated and canonical-response only", async () => {
  const [shared, command, publication, admin] = await Promise.all([
    source("app/api/competitions/public/_shared.ts"),
    source("app/api/competitions/public/command/route.ts"),
    source("app/_components/competition-publication-control.tsx"),
    source("app/api/platform-admin/public-competitions/route.ts"),
  ]);
  assert.match(shared, /noStoreHeaders/);
  assert.match(command, /requirePublicCompetitionOrigin\(request\)/);
  assert.match(command, /publicCompetitionWriteGate\(request\)/);
  assert.match(command, /operationId/);
  assert.match(command, /expectedRevision/);
  assert.match(command, /canonical: result\.data/);
  assert.match(publication, /clientWriteFetch\("api:public-competition-publication"/);
  assert.match(admin, /requireSameOriginMutation\(request\)/);
  assert.match(admin, /clientWriteGateResponse\(request\)/);
  assert.doesNotMatch(`${shared}\n${command}\n${admin}`, /SUPABASE_SERVICE_ROLE_KEY/);
});

test("PostgreSQL owns identity, idempotency, revisions, time and concurrency", async () => {
  const sql = await migrationSource();
  assert.match(sql, /declare actor_id uuid := \(select auth\.uid\(\)\)/);
  assert.match(sql, /clock_timestamp\(\)/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /STALE_REVISION/);
  assert.match(sql, /IDEMPOTENCY_KEY_REUSED/);
  assert.match(sql, /operation_id uuid not null unique/);
  assert.match(sql, /server_sequence bigint not null unique/);
  assert.doesNotMatch(sql, /actor_id\s*:=\s*\(payload\s*->>/i);
});

test("publication requires consent and platform review before public indexing", async () => {
  const sql = await migrationSource();
  assert.match(sql, /'draft', 'pending_review', 'approved', 'published', 'rejected'/);
  assert.match(sql, /SELF_REVIEW_FORBIDDEN/);
  assert.match(sql, /CURRENT_CONSENT_REQUIRED/);
  assert.match(sql, /content_fingerprint/);
  assert.match(sql, /visibility = 'public' and publication_row\.lifecycle_status = 'published'/);
  assert.match(sql, /is_indexable/);
});

test("registration acceptance is atomic, capacity-locked and creates one canonical Entry", async () => {
  const sql = await source("supabase/migrations/20260828072051_public_competition_commands_authority_v1.sql");
  assert.match(sql, /pachanga_league_assert_team_owner_v1\(selected_team_id, actor_id\)/);
  assert.match(sql, /COMPETITION_ENTRY_ALREADY_EXISTS/);
  assert.match(sql, /REGISTRATION_REQUEST_ALREADY_EXISTS/);
  assert.match(sql, /COMPETITION_CAPACITY_REACHED/);
  assert.match(sql, /insert into public\.pachanga_competition_entries/);
  assert.match(sql, /entry_source,[\s\S]+PUBLIC_APPLICATION/);
  assert.match(sql, /status = 'accepted', entry_id = entry_id_value/);
  assert.match(sql, /exception[\s\S]+unique_violation[\s\S]+REGISTRATION_REQUEST_CONFLICT/);
});

test("waitlist ordering is explicit, stable and revisioned", async () => {
  const sql = await migrationSource();
  assert.match(sql, /waitlist_position bigint/);
  assert.match(sql, /pachanga_competition_registration_waitlist_position_idx/);
  assert.match(sql, /order by requests\.waitlist_position, requests\.id/);
  assert.match(sql, /revision = requests\.revision \+ 1/);
  assert.doesNotMatch(sql, /order by\s+requests\.created_at\s+desc/i);
});

test("RLS blocks direct writes and grants only the intended RPC contracts", async () => {
  const sql = await migrationSource();
  for (const table of [
    "pachanga_competition_publications",
    "pachanga_competition_registration_requests",
    "pachanga_public_competition_read_models",
  ]) assert.match(sql, new RegExp(`revoke all on table public\\.${table}|revoke all on table public\\.%I`, "i"));
  assert.match(sql, /grant execute on function public\.command_pachanga_competition_publication_v1/);
  assert.match(sql, /grant execute on function public\.command_pachanga_competition_registration_request_v1/);
  assert.match(sql, /grant execute on function public\.get_pachanga_public_competition_directory_v1/);
  assert.doesNotMatch(sql, /grant (?:insert|update|delete|all) on table public\.pachanga_(?:competition_public|public_competition|competition_registration)[^;]+ to authenticated/i);
});

test("public read models expose only approved projections and official results", async () => {
  const sql = await source("supabase/migrations/20260828072049_public_competition_read_models_directory_v1.sql");
  assert.match(sql, /models\.is_indexable/);
  assert.match(sql, /models\.visibility in \('public', 'unlisted'\)/);
  assert.match(sql, /pachanga_competition_official_result_decisions/);
  assert.match(sql, /profiles\.visibility = 'public'/);
  assert.match(sql, /assignments\.status in \('confirmed', 'completed'\)/);
  for (const privateField of ["email", "phone", "attendance", "privateReason", "privateNotes", "feeAmount"]) {
    assert.doesNotMatch(sql, new RegExp(`'${privateField}'\\s*,`, "i"), privateField);
  }
});

test("public directory, hub, filters and product management surfaces are wired", async () => {
  const [directory, hub, config, admin] = await Promise.all([
    source("app/competiciones/competition-directory-client.tsx"),
    source("app/competiciones/[competition]/public-competition-hub.tsx"),
    source("app/_components/competition-publication-control.tsx"),
    source("app/admin/competitions/public-competition-admin-client.tsx"),
  ]);
  for (const label of ["Tipo", "Modalidad", "Estado", "Registro", "Zona"]) assert.match(directory, new RegExp(label));
  for (const label of ["Resumen", "Formato", "Equipos", "Calendario", "Resultados", "Clasificación", "Cuadro", "Reglamento", "Árbitros", "Inscripción"]) assert.match(hub, new RegExp(label));
  assert.match(config, /REQUEST_APPROVAL/);
  assert.match(config, /<option value="private">/);
  assert.match(config, /<option value="unlisted">/);
  assert.match(config, /<option value="public">/);
  assert.match(admin, /Gates públicos/);
  assert.match(admin, /flags\.set/);
});

test("public competition dates hydrate deterministically in the product timezone", async () => {
  const [directory, hub] = await Promise.all([
    source("app/competiciones/competition-directory-client.tsx"),
    source("app/competiciones/[competition]/public-competition-hub.tsx"),
  ]);
  assert.match(directory, /timeZone: "Europe\/Madrid"/);
  assert.equal((hub.match(/timeZone: "Europe\/Madrid"/g) ?? []).length, 2);
});

test("Realtime invalidates and refetches canonical state without applying WAL as authority", async () => {
  const clients = (await Promise.all([
    source("app/competiciones/[competition]/public-competition-hub.tsx"),
    source("app/_components/competition-publication-control.tsx"),
  ])).join("\n");
  assert.match(clients, /postgres_changes/);
  assert.match(clients, /SUBSCRIBED/);
  assert.match(clients, /loadHub\("realtime"/);
  assert.match(clients, /Sin conexión\. La acción no se ha enviado ni confirmado/);
  assert.doesNotMatch(clients, /set(?:Snapshot|Data|Publication)\([^)]*payload\.new|offlineQueue|queueOffline|pendingOperations|fakeSuccess/i);
});

test("PWA caches only public navigation and never caches API writes", async () => {
  const worker = await source("app/service-worker-source.ts");
  assert.match(worker, /"\/competiciones"/);
  assert.match(worker, /CACHEABLE_NAVIGATION_PATTERNS/);
  assert.match(worker, /competiciones\\\\\/\[a-z0-9\]/);
  assert.match(worker, /pathname\.startsWith\("\/api\/"\)/);
  assert.match(worker, /if \(request\.method !== "GET"\) return/);
  assert.match(worker, /networkFirstNavigation/);
});

test("SEO indexes only canonical public publications", async () => {
  const [page, robots, sitemap, sql] = await Promise.all([
    source("app/competiciones/[competition]/page.tsx"),
    source("app/robots.ts"),
    source("app/sitemap.ts"),
    source("supabase/migrations/20260828072049_public_competition_read_models_directory_v1.sql"),
  ]);
  assert.match(page, /alternates/);
  assert.match(page, /canonical/);
  assert.match(page, /openGraph/);
  assert.match(page, /robots/);
  assert.match(robots, /\/admin\//);
  assert.match(robots, /\/demo/);
  assert.match(sitemap, /getPublicCompetitionSitemap/);
  assert.match(sql, /where models\.is_indexable/);
});

test("public layouts adapt across portrait, landscape and PWA safe areas", async () => {
  const css = (await Promise.all([
    source("app/competiciones/public-competitions.module.css"),
    source("app/competiciones/[competition]/public-competition-hub.module.css"),
    source("app/_components/competition-publication-control.module.css"),
  ])).join("\n");
  assert.match(css, /max-width: 620px/);
  assert.match(css, /orientation: landscape/);
  assert.match(css, /pointer: coarse/);
  assert.match(css, /env\(safe-area-inset-bottom\)/);
  assert.match(css, /min-width: 0/);
  assert.match(css, /max-width: 740px/);
  assert.match(css, /grid-template-columns: 165px minmax\(0, 1fr\) 115px/);
  assert.match(css, /heroMetrics > div:last-child strong \{ font-size: \.75rem; \}/);
});

test("public competition shell agrees with League and Tournament grammatical gender", async () => {
  const hub = await source("app/competiciones/[competition]/public-competition-hub.tsx");
  assert.match(hub, /=== "TOURNAMENT" \? "público" : "pública"/);
  assert.doesNotMatch(hub, /`\$\{publicCompetitionTypeLabel\(competition\.type\)\} pública`/);
});

test("isolated staging Tournament runner proves unlisted discovery and canonical R6 read models", async () => {
  const runner = await source("tests/public-competitions-v1-staging-tournament-e2e.mjs");
  assert.match(runner, /expectedProjectRef = "cvoeasffqzpnbcnbgssn"/);
  assert.match(runner, /PUBLIC_COMPETITIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(runner, /demo-world-v2-tournament-operations\.sql/);
  assert.match(runner, /demo-world-v2-tournament-group-stage-operations\.sql/);
  assert.match(runner, /demo-world-v2-tournament-knockout-operations\.sql/);
  assert.match(runner, /visibility: "unlisted"/);
  assert.match(runner, /registration\.configure[\s\S]+mode: "CLOSED"/);
  assert.match(runner, /get_pachanga_public_competition_sitemap_v1/);
  assert.match(runner, /assert\.equal\(directory\.items\.some/);
  assert.match(runner, /assert\.match\(html, \/noindex\/i/);
});

test("Wave 7A does not mutate Rating, Rewards, Conduct or Billing domains", async () => {
  const sql = (await migrationSource()).replace(/--.*$/gm, "");
  assert.doesNotMatch(sql, /(?:insert into|update|delete from|alter table)\s+(?:public\.|private\.)?[^\s;(]*(?:rating|reward|conduct|billing|stripe|payment)/i);
  assert.doesNotMatch(sql, /public_competition_discipline_enabled\s*=\s*true/i);
  assert.doesNotMatch(sql, /public_competition_auto_accept_enabled\s*=\s*true/i);
});
