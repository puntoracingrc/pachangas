import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createClient } from "@supabase/supabase-js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const productionRef = "qonbngfrnrqgmxbdfbea";
const expectedProjectRef = "cvoeasffqzpnbcnbgssn";
const env = {
  confirmation: process.env.PUBLIC_COMPETITIONS_STAGING_CONFIRM,
  databaseUrl: process.env.PUBLIC_COMPETITIONS_STAGING_DATABASE_URL,
  previewUrl: process.env.PUBLIC_COMPETITIONS_STAGING_PREVIEW_URL,
  projectRef: process.env.PUBLIC_COMPETITIONS_STAGING_PROJECT_REF,
  publishableKey: process.env.PUBLIC_COMPETITIONS_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.PUBLIC_COMPETITIONS_STAGING_SERVICE_ROLE_KEY,
  url: process.env.PUBLIC_COMPETITIONS_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (!value) throw new Error(`PUBLIC_COMPETITIONS_STAGING_${key.toUpperCase()}_REQUIRED`);
}

const apiRef = new URL(env.url).hostname.split(".")[0];
const databaseIdentity = decodeURIComponent(new URL(env.databaseUrl).username);
if (
  env.confirmation !== "PUBLIC_COMPETITIONS_STAGING_ONLY"
  || env.projectRef !== expectedProjectRef
  || apiRef !== expectedProjectRef
  || apiRef === productionRef
  || databaseIdentity.includes(productionRef)
  || env.databaseUrl.includes(productionRef)
  || /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)
) throw new Error("PUBLIC_COMPETITIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN");

const ownerId = "64010000-0000-4000-8000-000000000001";
const ownerEmail = "demo-tournament-team-1@example.test";
const platformId = "64010000-0000-4000-8000-000000000090";
const platformEmail = "demo-tournament-platform@example.test";
const password = `Wave7A-${randomUUID()}-Qa!`;
const clients = [];

function client(key = env.publishableKey) {
  const value = createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  clients.push(value);
  return value;
}

const admin = client(env.serviceRoleKey);
const anonymous = client();

function redact(value) {
  return String(value)
    .replaceAll(env.databaseUrl, "[DATABASE_URL_REDACTED]")
    .replaceAll(env.serviceRoleKey, "[SERVICE_ROLE_REDACTED]");
}

function psql(args, label, input) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", env.databaseUrl, ...args,
  ], {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${redact(`${result.stdout ?? ""}${result.stderr ?? ""}`)}`);
  }
  return (result.stdout ?? "").trim();
}

function queryJson(sql, label) {
  return JSON.parse(psql(["-At", "-c", sql], label));
}

async function previewHtml(path) {
  const response = await fetch(new URL(path, env.previewUrl), {
    cache: "no-store",
    redirect: "manual",
  });
  if (response.status >= 300 && response.status < 400) {
    const result = spawnSync("vercel", [
      "curl", path, "--deployment", env.previewUrl,
    ], {
      cwd: root,
      encoding: "utf8",
      env: process.env,
      maxBuffer: 8 * 1024 * 1024,
    });
    if (result.error) throw result.error;
    if (result.status !== 0) {
      throw new Error(`protected Preview read failed (${result.status}):\n${redact(result.stderr ?? "")}`);
    }
    return result.stdout ?? "";
  }
  assert.equal(response.status, 200);
  return response.text();
}

function replaceExactlyOnce(source, from, to, label) {
  assert.equal(source.split(from).length - 1, 1, `WAVE7A_TOURNAMENT_MARKER_DRIFT:${label}`);
  return source.replace(from, to);
}

function tournamentFixtureSql() {
  let source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-tournament-operations.sql"),
    "utf8",
  );
  source = replaceExactlyOnce(
    source,
    "from generate_series(1, 16) team_number;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    "from generate_series(1, 16) team_number\non conflict (id) do nothing;\n\ninsert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values",
    "precreated-owner",
  );
  return replaceExactlyOnce(
    source,
    "('64010000-0000-4000-8000-000000000090', 'demo-tournament-platform@example.test', clock_timestamp(), '{\"full_name\":\"Demo Tournament Platform\"}');",
    "('64010000-0000-4000-8000-000000000090', 'demo-tournament-platform@example.test', clock_timestamp(), '{\"full_name\":\"Demo Tournament Platform\"}') on conflict (id) do nothing;",
    "precreated-platform",
  );
}

function prerequisiteFlagsSql() {
  const source = readFileSync(resolve(root, "tests/tournament-group-stage-v1-staging-e2e.mjs"), "utf8");
  const match = source.match(/const prerequisiteFlagsSql = `([\s\S]*?)`;\n/);
  assert.ok(match, "WAVE7A_TOURNAMENT_PREREQUISITE_MARKER_DRIFT");
  return match[1];
}

function refereeFixtureSql() {
  const source = readFileSync(
    resolve(root, "scripts/demo-world/demo-world-v2-referee-assignment-operations.sql"),
    "utf8",
  );
  const boundaryIndex = source.indexOf("do $demo_assignments$");
  assert.notEqual(boundaryIndex, -1, "WAVE7A_TOURNAMENT_REFEREE_BOUNDARY_DRIFT");
  const refereeOnly = source
    .slice(0, boundaryIndex)
    .replaceAll("e4010000-0000-4000-8000-000000000001", platformId);
  return `
\\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.demo_v2_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;
${refereeOnly}
commit;
`;
}

async function ensureAccount(id, email) {
  const existing = await admin.auth.admin.getUserById(id);
  if (existing.error) {
    const created = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      id,
      password,
      user_metadata: { qaFixture: "PUBLIC_COMPETITIONS_TOURNAMENT_V1" },
    });
    if (created.error) throw created.error;
    return;
  }
  const updated = await admin.auth.admin.updateUserById(id, {
    email_confirm: true,
    password,
    user_metadata: { qaFixture: "PUBLIC_COMPETITIONS_TOURNAMENT_V1" },
  });
  if (updated.error) throw updated.error;
}

async function signIn(email) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({ email, password });
  if (result.error) throw result.error;
  return supabase;
}

function metadata(surface) {
  return {
    clientVersion: "7.0.0+wave7a-tournament-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "7.0.0+wave7a-tournament-staging",
    sessionId: "wave7a-tournament-staging",
    surface,
  };
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw new Error(`${name} [${result.error.code}] ${result.error.message}`, { cause: result.error });
  return result.data;
}

function assertPublicSafe(value, path = "$") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertPublicSafe(item, `${path}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      assert.equal(
        new Set(["privatereason", "evidencerefs", "operationid", "email", "phone", "attendance"]).has(key.toLowerCase()),
        false,
        `WAVE7A_PRIVATE_KEY_LEAK:${path}.${key}`,
      );
      assertPublicSafe(child, `${path}.${key}`);
    }
    return;
  }
  if (typeof value === "string") {
    assert.doesNotMatch(value, /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i, `WAVE7A_EMAIL_LEAK:${path}`);
    assert.doesNotMatch(value, /\+34[\s.-]*(?:6|7)(?:[\s.-]*\d){8}\b/, `WAVE7A_PHONE_LEAK:${path}`);
  }
}

async function setPublicFlags(platform) {
  const current = await rpc(platform, "get_pachanga_public_competition_flags_v1");
  const enabled = await rpc(platform, "set_pachanga_public_competition_flags_v1", {
    client_metadata: metadata("wave7a-tournament-flags"),
    expected_revision: current.revision,
    flag_patch: {
      autoAccept: false,
      bracket: true,
      calendar: true,
      discipline: false,
      discovery: true,
      exceptionStatus: true,
      foundation: true,
      publication: true,
      referees: true,
      registrationRequests: true,
      results: true,
      standings: true,
      waitlist: true,
    },
    operation_id: randomUUID(),
    reason: "Wave 7A isolated unlisted Tournament staging proof",
  });
  assert.equal(enabled.snapshot.discipline, false);
  assert.equal(enabled.snapshot.autoAccept, false);
}

async function publicationCommand(owner, target, action, payload) {
  const result = await rpc(owner, "command_pachanga_competition_publication_v1", {
    aggregate_id: target.competitionId,
    client_metadata: metadata("wave7a-tournament-publication"),
    command_action: action,
    command_payload: payload,
    expected_revision: target.revision,
    operation_id: randomUUID(),
  });
  target.publicationId ??= result.snapshot.publication.id;
  target.revision = result.confirmedRevision;
  return result;
}

async function moderationCommand(platform, target, action) {
  const result = await rpc(platform, "command_pachanga_public_competition_moderation_v1", {
    aggregate_id: target.publicationId,
    client_metadata: metadata("wave7a-tournament-moderation"),
    command_action: action,
    command_payload: {
      publicReason: action === "publication.approve" ? "Publicacion aprobada." : "Competicion publicada.",
      reason: "Independent Wave 7A staging review",
    },
    expected_revision: target.revision,
    operation_id: randomUUID(),
  });
  target.revision = result.confirmedRevision;
}

async function main() {
  const initial = queryJson(`
    select jsonb_build_object(
      'ledger', (select count(*) from supabase_migrations.schema_migrations),
      'lastMigration', (select max(version) from supabase_migrations.schema_migrations),
      'tournaments', (select count(*) from public.pachanga_competitions where slug='copa-barrios-iq-2027')
    )::text;
  `, "inspect isolated Tournament staging baseline");
  assert.equal(initial.ledger, 183);
  assert.equal(initial.lastMigration, "20260828072053");

  await ensureAccount(ownerId, ownerEmail);
  await ensureAccount(platformId, platformEmail);
  if (initial.tournaments === 0) {
    psql(["-v", "DEMO_WORLD_V2_PERSIST=1"], "create canonical R6A Tournament", tournamentFixtureSql());
    psql([], "activate isolated R4A-R5 prerequisites", prerequisiteFlagsSql());
    psql([], "create canonical referee fixtures", refereeFixtureSql());
    psql([
      "-v", "DEMO_WORLD_V2_PERSIST=1",
      "-f", resolve(root, "scripts/demo-world/demo-world-v2-tournament-group-stage-operations.sql"),
    ], "operate canonical R6B Tournament group stage");
    psql([
      "-v", "DEMO_WORLD_V2_PERSIST=1",
      "-f", resolve(root, "scripts/demo-world/demo-world-v2-tournament-knockout-operations.sql"),
    ], "operate canonical R6C Tournament knockout");
  } else {
    assert.equal(initial.tournaments, 1, "WAVE7A_TOURNAMENT_DUPLICATE_CANONICAL_FIXTURE");
  }

  const owner = await signIn(ownerEmail);
  const platform = await signIn(platformEmail);
  await setPublicFlags(platform);

  const proof = queryJson(`
    with target as (
      select competitions.id from public.pachanga_competitions competitions
      where competitions.slug='copa-barrios-iq-2027'
    )
    select jsonb_build_object(
      'competitionId', (select id from target),
      'editionId', (select editions.id from target join public.pachanga_competition_editions editions
        on editions.competition_id=target.id order by editions.created_at, editions.id limit 1),
      'categoryId', (select categories.id from target
        join public.pachanga_competition_editions editions on editions.competition_id=target.id
        join public.pachanga_competition_categories categories on categories.edition_id=editions.id
        order by categories.created_at, categories.id limit 1),
      'contexts', (select count(*) from target join public.pachanga_competition_match_contexts contexts
        on contexts.competition_id=target.id where contexts.status <> 'retired'),
      'officialResults', (select count(*) from target
        join public.pachanga_competition_match_contexts contexts on contexts.competition_id=target.id
        join public.pachanga_competition_match_sheets sheets on sheets.competition_match_context_id=contexts.id
        where contexts.status <> 'retired' and sheets.active_official_decision_id is not null),
      'standingStates', (select count(*) from target join public.pachanga_competition_standing_states states
        on states.competition_id=target.id where states.current_snapshot_id is not null),
      'bracketRounds', (select jsonb_array_length(models.public_snapshot -> 'rounds') from target
        join public.pachanga_tournament_knockout_read_models models on models.competition_id=target.id)
    )::text;
  `, "read canonical R6 Tournament proof");
  assert.ok(proof.competitionId);
  assert.ok(proof.contexts >= 32);
  assert.ok(proof.officialResults >= 32);
  assert.equal(proof.standingStates, 4);
  assert.ok(proof.bracketRounds >= 3);

  const existingPublication = queryJson(`
    select coalesce((select jsonb_build_object(
      'id', publications.id,
      'revision', publications.revision,
      'status', publications.lifecycle_status,
      'visibility', publications.visibility
    ) from public.pachanga_competition_publications publications
      where publications.competition_id='${proof.competitionId}'::uuid), 'null'::jsonb)::text;
  `, "inspect canonical Tournament publication");
  const publication = {
    competitionId: proof.competitionId,
    publicationId: existingPublication?.id ?? null,
    revision: existingPublication?.revision ?? 0,
  };
  if (!existingPublication) {
    await publicationCommand(owner, publication, "publication.prepare", {
      categoryId: proof.categoryId,
      editionId: proof.editionId,
      publicProfile: {
        badge: "BETA",
        description: "Copa demostrativa con fase de grupos y eliminatorias completas.",
        format: "Torneo",
        generalArea: "Barcelona",
        municipality: "Barcelona",
        name: "Copa Barrios IQ 2027",
        rulesSummary: "Fase de grupos, cuadro eliminatorio y resultados oficiales.",
      },
      publicSections: {
        bracket: true,
        calendar: true,
        discipline: false,
        referees: true,
        results: true,
        standings: true,
        teams: true,
        venueDetail: false,
      },
      reason: "Prepare unlisted Tournament staging projection",
      slug: "copa-barrios-iq-2027",
      visibility: "unlisted",
    });
    await publicationCommand(owner, publication, "registration.configure", {
      mode: "CLOSED",
      reason: "Completed demo Tournament is read only",
    });
    await publicationCommand(owner, publication, "publication.consent", {
      purpose: "Publicar por enlace el torneo ficticio de staging.",
      reason: "Explicit unlisted staging consent",
      statements: {
        authorizedRepresentative: true,
        indexingAccepted: true,
        informationAccurate: true,
        teamAssetsAuthorized: true,
      },
    });
    await publicationCommand(owner, publication, "publication.submit", {
      reason: "Submit unlisted Tournament for independent review",
    });
    await moderationCommand(platform, publication, "publication.approve");
    await moderationCommand(platform, publication, "publication.publish");
  } else {
    assert.equal(existingPublication.status, "published");
    assert.equal(existingPublication.visibility, "unlisted");
  }

  const [directory, hub, calendar, standings, bracket, sitemap] = await Promise.all([
    rpc(anonymous, "get_pachanga_public_competition_directory_v1"),
    rpc(anonymous, "get_pachanga_public_competition_v1", { target_slug: "copa-barrios-iq-2027" }),
    rpc(anonymous, "get_pachanga_public_competition_calendar_v1", {
      page_offset: 0, page_size: 100, target_slug: "copa-barrios-iq-2027",
    }),
    rpc(anonymous, "get_pachanga_public_competition_standings_v1", { target_slug: "copa-barrios-iq-2027" }),
    rpc(anonymous, "get_pachanga_public_competition_bracket_v1", { target_slug: "copa-barrios-iq-2027" }),
    rpc(anonymous, "get_pachanga_public_competition_sitemap_v1"),
  ]);
  assert.equal(directory.items.some((item) => item.publication?.slug === "copa-barrios-iq-2027"), false);
  assert.equal(sitemap.some((item) => item.slug === "copa-barrios-iq-2027"), false);
  assert.equal(hub.publication.visibility, "unlisted");
  assert.equal(hub.registration.mode, "CLOSED");
  assert.ok(calendar.total >= 32);
  assert.ok(calendar.items.filter((item) => item.result?.status === "OFFICIAL").length >= 32);
  assert.equal(standings.items.length, 4);
  assert.ok(bracket.rounds.length >= 3);
  assert.equal(hub.privacy.containsRoster, false);
  assert.equal(hub.privacy.containsAttendance, false);
  assert.equal(hub.privacy.containsContactData, false);
  assertPublicSafe({ bracket, calendar, directory, hub, sitemap, standings });

  const html = await previewHtml("/competiciones/copa-barrios-iq-2027");
  assert.match(html, /noindex/i);
  assert.doesNotMatch(html, /SECRET_PRIVATE|privateReason|evidenceRefs/i);

  process.stdout.write(`${JSON.stringify({
    bracketRounds: bracket.rounds.length,
    calendarFixtures: calendar.total,
    directoryIndexed: false,
    officialResults: calendar.items.filter((item) => item.result?.status === "OFFICIAL").length,
    previewNoindex: true,
    projectRef: env.projectRef,
    registration: hub.registration.mode,
    standings: standings.items.length,
    visibility: hub.publication.visibility,
  })}\n`);
}

try {
  await main();
} finally {
  await Promise.all(clients.map((supabase) => supabase.auth.signOut({ scope: "local" })));
  await Promise.all(clients.map((supabase) => supabase.realtime.disconnect()));
}
