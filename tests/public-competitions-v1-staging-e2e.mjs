import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const env = {
  confirmation: process.env.PUBLIC_COMPETITIONS_STAGING_CONFIRM,
  databaseUrl: process.env.PUBLIC_COMPETITIONS_STAGING_DATABASE_URL,
  keepFlags: process.env.PUBLIC_COMPETITIONS_STAGING_KEEP_FLAGS === "1",
  previewUrl: process.env.PUBLIC_COMPETITIONS_STAGING_PREVIEW_URL || null,
  projectRef: process.env.PUBLIC_COMPETITIONS_STAGING_PROJECT_REF,
  publishableKey: process.env.PUBLIC_COMPETITIONS_STAGING_PUBLISHABLE_KEY,
  serviceRoleKey: process.env.PUBLIC_COMPETITIONS_STAGING_SERVICE_ROLE_KEY,
  url: process.env.PUBLIC_COMPETITIONS_STAGING_URL,
};

for (const [key, value] of Object.entries(env)) {
  if (key !== "previewUrl" && key !== "keepFlags" && !value) {
    throw new Error(`PUBLIC_COMPETITIONS_STAGING_${key.toUpperCase()}_REQUIRED`);
  }
}

const productionRef = "qonbngfrnrqgmxbdfbea";
const expectedProjectRef = "cvoeasffqzpnbcnbgssn";
const actualRef = new URL(env.url).hostname.split(".")[0];
const parsedDatabaseUrl = new URL(env.databaseUrl);
if (
  env.confirmation !== "PUBLIC_COMPETITIONS_STAGING_ONLY"
  || env.projectRef !== expectedProjectRef
  || actualRef !== expectedProjectRef
  || actualRef === productionRef
  || !parsedDatabaseUrl.hostname.endsWith(".pooler.supabase.com")
  || !decodeURIComponent(parsedDatabaseUrl.username).endsWith(`.${expectedProjectRef}`)
  || env.databaseUrl.includes(productionRef)
) {
  throw new Error("PUBLIC_COMPETITIONS_STAGING_PRODUCTION_TARGET_FORBIDDEN");
}
if (env.previewUrl && /(^|\.)pachangasiq\.com$/i.test(new URL(env.previewUrl).hostname)) {
  throw new Error("PUBLIC_COMPETITIONS_STAGING_PREVIEW_PRODUCTION_TARGET_FORBIDDEN");
}

function isBrowserPublicKey(value) {
  if (/^sb_publishable_/i.test(value)) return true;
  if (!/^eyJ/i.test(value)) return false;
  try {
    const payload = JSON.parse(Buffer.from(value.split(".")[1], "base64url").toString("utf8"));
    return payload.role === "anon";
  } catch {
    return false;
  }
}

if (
  !isBrowserPublicKey(env.publishableKey)
  || /^sb_secret_/i.test(env.publishableKey)
  || env.publishableKey === env.serviceRoleKey
) {
  throw new Error("PUBLIC_COMPETITIONS_STAGING_BROWSER_KEY_REQUIRED");
}

const runId = randomUUID().replaceAll("-", "").slice(0, 10);
const password = `Wave7A-${randomUUID()}-Qa!`;
const clients = [];
const channels = [];
const accounts = [];
const groups = [];
const ids = {
  category: randomUUID(),
  competition: randomUUID(),
  edition: randomUUID(),
  ruleRevision: randomUUID(),
  ruleSet: randomUUID(),
  stage: randomUUID(),
};
const slug = `liga-publica-wave7a-${runId}`;
const report = {
  auth: null,
  cleanup: "EPHEMERAL_BRANCH_TEARDOWN_REQUIRED",
  concurrency: null,
  flags: null,
  notifications: null,
  preview: null,
  privacy: null,
  projectRef: env.projectRef,
  publication: null,
  realtime: null,
  registration: null,
  rls: null,
  runId,
};

function client(key = env.publishableKey) {
  return createClient(env.url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 40 } },
  });
}

const fixtureAdmin = client(env.serviceRoleKey);
const anonymous = client();

function metadata(surface) {
  return {
    clientVersion: "7.0.0+wave7a-staging",
    installedMode: "standalone",
    serviceWorkerVersion: "7.0.0+wave7a-staging",
    sessionId: `wave7a-${runId}`,
    surface,
  };
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) {
    throw new Error(`${name} [${result.error.code}] ${result.error.message}`, {
      cause: result.error,
    });
  }
  return result.data;
}

function diagnostic(result) {
  return [result.error?.code, result.error?.message, result.error?.details, result.error?.hint]
    .filter(Boolean)
    .join(" ");
}

function expectError(result, pattern, label) {
  assert.ok(result.error, `${label}: expected an error`);
  assert.match(diagnostic(result), pattern, `${label}: ${diagnostic(result)}`);
  return diagnostic(result);
}

async function bestEffort(label, action) {
  try {
    await action();
  } catch (error) {
    console.error(`[cleanup:${label}]`, error instanceof Error ? error.message : error);
  }
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  const result = spawnSync("psql", [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", env.databaseUrl,
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      PGOPTIONS: "-c lock_timeout=5s -c statement_timeout=120s",
    },
    input: sql,
    maxBuffer: 32 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

async function createAccount(label) {
  const account = {
    email: `wave7a-${label}-${runId}@pachangasiq.test`,
    id: randomUUID(),
    label,
  };
  const result = await fixtureAdmin.auth.admin.createUser({
    email: account.email,
    email_confirm: true,
    id: account.id,
    password,
    user_metadata: { qaFixture: "PUBLIC_COMPETITIONS_V1", runId },
  });
  if (result.error) throw result.error;
  accounts.push(account);
  return account;
}

async function signIn(account, label) {
  const supabase = client();
  const result = await supabase.auth.signInWithPassword({
    email: account.email,
    password,
  });
  if (result.error) throw new Error(`WAVE7A_STAGING_SIGN_IN_FAILED:${label}`, { cause: result.error });
  assert.equal(result.data.user.id, account.id);
  clients.push(supabase);
  return supabase;
}

async function ensurePlatformOwner(account) {
  const current = await fixtureAdmin.rpc("get_pachanga_platform_access_service_v1", {
    target_user_id: account.id,
  });
  if (current.error) throw current.error;
  if (current.data) return;
  const result = await fixtureAdmin.rpc("bootstrap_pachanga_platform_owner_v1", {
    operation_id: randomUUID(),
    reason: `Wave 7A isolated staging ${runId}`,
    target_user_id: account.id,
  });
  if (result.error && /already bootstrapped/i.test(result.error.message)) {
    runSql(`
      insert into private.pachanga_platform_admin_roles(user_id, role, active)
      values (${sqlLiteral(account.id)}::uuid, 'platform_admin', true)
      on conflict (user_id) do update set role = excluded.role, active = true;
    `, "grant temporary Wave 7A staging platform admin");
    temporaryPlatformAdminUserId = account.id;
    return;
  }
  if (result.error) throw result.error;
  assert.equal(result.data.role, "platform_owner");
}

function seedFixture(organizer, teamOwners) {
  const allOwners = [organizer, ...teamOwners];
  for (let index = 0; index < allOwners.length; index += 1) {
    groups.push({
      id: randomUUID(),
      name: index === 0 ? `Wave 7A Organizer ${runId}` : `Wave 7A Team ${index} ${runId}`,
      owner: allOwners[index],
      teamCode: `W7${runId.slice(0, 5)}${String(index).padStart(2, "0")}`.toUpperCase(),
    });
  }
  const groupRows = groups.map((group) => `(
    ${sqlLiteral(group.id)}::uuid,
    ${sqlLiteral(group.owner.id)}::uuid,
    ${sqlLiteral(group.name)},
    ${sqlLiteral(group.teamCode)},
    jsonb_build_object(
      'matches', '[]'::jsonb,
      'players', '[]'::jsonb,
      'siteSettings', jsonb_build_object(
        'privatePhone', '+34 600 000 000',
        'privateEmail', ${sqlLiteral(`private-${runId}@example.test`)}
      ),
      'venues', '[]'::jsonb,
      'qaFixture', 'PUBLIC_COMPETITIONS_V1',
      'runId', ${sqlLiteral(runId)}
    ),
    1
  )`).join(",\n");
  const memberRows = groups.map((group) => `(
    ${sqlLiteral(group.id)}::uuid,
    ${sqlLiteral(group.owner.id)}::uuid,
    'owner',
    ${sqlLiteral(`${group.name} Owner`)}
  )`).join(",\n");
  const rules = JSON.stringify({
    discipline: {},
    format: { modality: "futbol7" },
    futureCapabilities: {},
    governance: {},
    operations: {},
    publication: {},
    registration: {
      registrationPolicy: { teamLimits: { maximum: 2, minimum: 2 } },
      rosterPolicy: { closeRequiresApprovedRosters: false, maximumSize: 30, minimumSize: 0 },
    },
    results: {},
    structure: { stageGraph: { edges: [], nodes: [{ id: "league-stage", root: true }] } },
  });
  runSql(`
begin;
insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
values ${groupRows};
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values ${memberRows};
insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, description,
  competition_type, visibility, status, general_area, created_by
) values (
  ${sqlLiteral(ids.competition)}::uuid, 'TEAM', ${sqlLiteral(groups[0].id)}::uuid,
  ${sqlLiteral(`Liga Publica Wave 7A ${runId}`)}, ${sqlLiteral(slug)},
  'SECRET_PRIVATE_DESCRIPTION ${runId}', 'LEAGUE', 'private', 'draft',
  'Barcelona', ${sqlLiteral(organizer.id)}::uuid
);
insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
values (
  ${sqlLiteral(ids.ruleSet)}::uuid, ${sqlLiteral(ids.competition)}::uuid,
  'Wave 7A Rules', 'active', ${sqlLiteral(organizer.id)}::uuid
);
insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select ${sqlLiteral(ids.ruleRevision)}::uuid, ${sqlLiteral(ids.ruleSet)}::uuid,
  1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'frozen', 1,
  'Wave 7A authenticated staging rules', ${sqlLiteral(organizer.id)}::uuid
from (values (${sqlLiteral(rules)}::jsonb)) source(document);
insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_rule_revision_id,
  revision, created_by
) values (
  ${sqlLiteral(ids.edition)}::uuid, ${sqlLiteral(ids.competition)}::uuid,
  'Temporada 2027', '2027', '2027-09-01', '2028-06-30', 'draft',
  ${sqlLiteral(ids.ruleRevision)}::uuid, 'INVITE_ONLY',
  ${sqlLiteral(ids.ruleRevision)}::uuid, 1, ${sqlLiteral(organizer.id)}::uuid
);
insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
) values (
  ${sqlLiteral(ids.category)}::uuid, ${sqlLiteral(ids.edition)}::uuid,
  'Senior', 'senior', 'FOOTBALL_7', 'public', 'active',
  ${sqlLiteral(ids.ruleRevision)}::uuid, 1, ${sqlLiteral(organizer.id)}::uuid
);
insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
) values (
  ${sqlLiteral(ids.stage)}::uuid, ${sqlLiteral(ids.edition)}::uuid,
  'Liga regular', 'LEAGUE_STAGE', 0, false, 'draft',
  ${sqlLiteral(ids.ruleRevision)}::uuid, 1, ${sqlLiteral(organizer.id)}::uuid
);
insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
) values (
  ${sqlLiteral(ids.competition)}::uuid, ${sqlLiteral(organizer.id)}::uuid,
  'competition_owner', 'active', ${sqlLiteral(organizer.id)}::uuid
);
commit;
`, "seed authenticated Wave 7A staging fixture");
}

async function commandPublication(supabase, state, action, payload, operationId = randomUUID()) {
  const result = await supabase.rpc("command_pachanga_competition_publication_v1", {
    aggregate_id: ids.competition,
    client_metadata: metadata("wave7a-publication-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: state.revision,
    operation_id: operationId,
  });
  if (result.error) throw new Error(`${action}: ${diagnostic(result)}`, { cause: result.error });
  state.revision = result.data.confirmedRevision;
  state.publicationId ??= result.data.snapshot.publication.id;
  return result.data;
}

async function commandModeration(supabase, state, action, payload, operationId = randomUUID()) {
  const result = await supabase.rpc("command_pachanga_public_competition_moderation_v1", {
    aggregate_id: state.publicationId,
    client_metadata: metadata("wave7a-moderation-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: state.revision,
    operation_id: operationId,
  });
  if (result.error) throw new Error(`${action}: ${diagnostic(result)}`, { cause: result.error });
  state.revision = result.data.confirmedRevision;
  return result.data;
}

async function registrationCommand(supabase, aggregateId, expectedRevision, action, payload, operationId = randomUUID()) {
  return supabase.rpc("command_pachanga_competition_registration_request_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("wave7a-registration-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function subscribeInvalidations(supabase, competitionId, label) {
  const buffered = [];
  const waiters = [];
  const channel = supabase.channel(`wave7a-${label}-${runId}`);
  channels.push(channel);
  channel.on("postgres_changes", {
    event: "INSERT",
    filter: `competition_id=eq.${competitionId}`,
    schema: "public",
    table: "pachanga_competition_invalidations",
  }, (payload) => {
    const row = payload.new;
    const index = waiters.findIndex((waiter) => waiter.predicate(row));
    if (index >= 0) {
      const [waiter] = waiters.splice(index, 1);
      clearTimeout(waiter.timeout);
      waiter.resolve(row);
    } else {
      buffered.push(row);
    }
  });
  let rejectPostgres;
  const postgresReady = new Promise((resolve, reject) => {
    rejectPostgres = reject;
    const timeout = setTimeout(() => {
      reject(new Error(`WAVE7A_REALTIME_POSTGRES_READY_TIMEOUT:${label}`));
    }, 20_000);
    channel.on("system", {}, (payload) => {
      if (payload.extension !== "postgres_changes") return;
      clearTimeout(timeout);
      if (payload.status === "ok") resolve();
      else reject(new Error(`WAVE7A_REALTIME_POSTGRES_${String(payload.status).toUpperCase()}:${label}`));
    });
  });
  const subscribed = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      const error = new Error(`WAVE7A_REALTIME_SUBSCRIBE_TIMEOUT:${label}`);
      rejectPostgres(error);
      reject(error);
    }, 20_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        const error = new Error(`WAVE7A_REALTIME_${status}:${label}`);
        rejectPostgres(error);
        reject(error);
      }
    });
  });
  await Promise.all([subscribed, postgresReady]);
  return {
    waitFor(predicate) {
      const bufferedIndex = buffered.findIndex(predicate);
      if (bufferedIndex >= 0) return Promise.resolve(buffered.splice(bufferedIndex, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { predicate, resolve, timeout: null };
        waiter.timeout = setTimeout(() => {
          const index = waiters.indexOf(waiter);
          if (index >= 0) waiters.splice(index, 1);
          reject(new Error(`WAVE7A_REALTIME_EVENT_TIMEOUT:${label}`));
        }, 30_000);
        waiters.push(waiter);
      });
    },
  };
}

function flagPatch(flags) {
  return {
    autoAccept: false,
    bracket: Boolean(flags.bracket),
    calendar: Boolean(flags.calendar),
    discipline: false,
    discovery: Boolean(flags.discovery),
    exceptionStatus: Boolean(flags.exceptionStatus),
    foundation: Boolean(flags.foundation),
    publication: Boolean(flags.publication),
    referees: Boolean(flags.referees),
    registrationRequests: Boolean(flags.registrationRequests),
    results: Boolean(flags.results),
    standings: Boolean(flags.standings),
    waitlist: Boolean(flags.waitlist),
  };
}

async function setFlags(platform, patch, reason) {
  const current = await rpc(platform, "get_pachanga_public_competition_flags_v1");
  return rpc(platform, "set_pachanga_public_competition_flags_v1", {
    client_metadata: metadata("wave7a-flags-staging"),
    expected_revision: current.revision,
    flag_patch: patch,
    operation_id: randomUUID(),
    reason,
  });
}

let platform;
let organizer;
let initialFlags;
let flagsChanged = false;
let temporaryPlatformAdminUserId = null;

try {
  const platformAccount = await createAccount("platform");
  const organizerAccount = await createAccount("organizer");
  const teamAccounts = [];
  for (let index = 1; index <= 5; index += 1) {
    teamAccounts.push(await createAccount(`team-${index}`));
  }
  const outsiderAccount = await createAccount("outsider");
  await ensurePlatformOwner(platformAccount);

  platform = await signIn(platformAccount, "platform");
  organizer = await signIn(organizerAccount, "organizer");
  const organizerDevice2 = await signIn(organizerAccount, "organizer-device-2");
  const teamClients = [];
  for (let index = 0; index < teamAccounts.length; index += 1) {
    teamClients.push(await signIn(teamAccounts[index], `team-${index + 1}`));
  }
  const outsider = await signIn(outsiderAccount, "outsider");
  report.auth = { accounts: accounts.length, devices: clients.length };

  seedFixture(organizerAccount, teamAccounts);

  initialFlags = await rpc(platform, "get_pachanga_public_competition_flags_v1");
  const enabled = await setFlags(platform, {
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
  }, `Wave 7A isolated staging activation ${runId}`);
  flagsChanged = true;
  assert.equal(enabled.snapshot.discipline, false);
  assert.equal(enabled.snapshot.autoAccept, false);
  report.flags = { safeEnabled: true, unsafeOff: true };
  report.flags.leftEnabledForPreview = env.keepFlags;

  const publication = { publicationId: null, revision: 0 };
  await commandPublication(organizer, publication, "publication.prepare", {
    categoryId: ids.category,
    editionId: ids.edition,
    publicProfile: {
      badge: "BETA",
      description: "Liga abierta de futbol 7 para equipos de Barcelona.",
      format: "Liga",
      generalArea: "Barcelona",
      municipality: "Barcelona",
      name: `Liga Publica Wave 7A ${runId}`,
      publicVenue: "Sede publica consentida",
      rulesSummary: "Dos plazas y resultados oficiales.",
    },
    publicSections: {
      bracket: false,
      calendar: true,
      discipline: false,
      referees: true,
      results: true,
      standings: true,
      teams: true,
      venueDetail: false,
    },
    reason: "Prepare public projection",
    slug,
    visibility: "public",
  });
  await commandPublication(organizer, publication, "registration.configure", {
    closesAt: "2029-01-01T00:00:00Z",
    mode: "REQUEST_APPROVAL",
    opensAt: "2026-01-01T00:00:00Z",
    reason: "Open registration",
  });
  await commandPublication(organizer, publication, "publication.consent", {
    purpose: "Publicar la liga y admitir solicitudes de equipos.",
    reason: "Explicit staging consent",
    statements: {
      authorizedRepresentative: true,
      indexingAccepted: true,
      informationAccurate: true,
      teamAssetsAuthorized: true,
    },
  });
  await commandPublication(organizer, publication, "publication.submit", {
    reason: "Submit for independent review",
  });

  const forbiddenModeration = await organizer.rpc("command_pachanga_public_competition_moderation_v1", {
    aggregate_id: publication.publicationId,
    client_metadata: metadata("wave7a-forbidden-self-review"),
    command_action: "publication.approve",
    command_payload: { reason: "Organizer cannot self approve" },
    expected_revision: publication.revision,
    operation_id: randomUUID(),
  });
  expectError(forbiddenModeration, /PLATFORM|CAPABILITY|ACCESS|42501/i, "organizer moderation");

  await commandModeration(platform, publication, "publication.approve", {
    publicReason: "Publicacion aprobada.",
    reason: "Independent review passed",
  });
  await commandModeration(platform, publication, "publication.publish", {
    publicReason: "Competicion publicada.",
    reason: "Publish approved competition",
  });
  report.publication = { lifecycle: "published", reviewedByDifferentActor: true };

  const directory = await rpc(anonymous, "get_pachanga_public_competition_directory_v1");
  const publicHub = await rpc(anonymous, "get_pachanga_public_competition_v1", {
    target_slug: slug,
  });
  assert.ok(directory.items.some((item) => item.publication?.slug === slug));
  assert.equal(publicHub.publication.slug, slug);
  const publicText = JSON.stringify({ directory, publicHub });
  assert.doesNotMatch(publicText, /SECRET_PRIVATE_DESCRIPTION|private-.*@example\.test|\+34 600 000/i);
  assert.equal(publicHub.privacy.containsRoster, false);
  assert.equal(publicHub.privacy.containsAttendance, false);
  assert.equal(publicHub.privacy.containsContactData, false);
  assert.equal(publicHub.privacy.containsEvidence, false);
  assert.equal(publicHub.privacy.containsFees, false);
  report.privacy = { anonymousPublicRead: true, piiLeaks: 0, privateRosterLeaks: 0 };

  const directUpdate = await organizer
    .from("pachanga_competition_publications")
    .update({ lifecycle_status: "published" })
    .eq("id", publication.publicationId);
  expectError(directUpdate, /permission|denied|42501/i, "direct publication update");
  const outsiderQueue = await outsider.rpc("get_pachanga_competition_registration_queue_v1", {
    page_offset: 0,
    page_size: 20,
    status_filter: null,
    target_competition_id: ids.competition,
  });
  expectError(outsiderQueue, /MANAGER_REQUIRED|permission|42501/i, "outsider queue");
  report.rls = { directWritesDenied: true, outsiderQueueDenied: true };

  const organizerFeed = await subscribeInvalidations(organizer, ids.competition, "organizer");
  const teamOneFeed = await subscribeInvalidations(teamClients[0], ids.competition, "team-one");
  const submitOperation = randomUUID();
  const submitted = await registrationCommand(
    teamClients[0],
    publication.publicationId,
    publication.revision,
    "registration.submit",
    { message: "Queremos participar.", reason: "Initial team request", teamId: groups[1].id },
    submitOperation,
  );
  if (submitted.error) throw new Error(diagnostic(submitted), { cause: submitted.error });
  const replay = await registrationCommand(
    teamClients[0],
    publication.publicationId,
    publication.revision,
    "registration.submit",
    { message: "Queremos participar.", reason: "Initial team request", teamId: groups[1].id },
    submitOperation,
  );
  if (replay.error) throw new Error(diagnostic(replay), { cause: replay.error });
  assert.deepEqual(replay.data, submitted.data);
  const requestOne = submitted.data.snapshot;
  const organizerEvent = await organizerFeed.waitFor((row) => (
    row.entity_id === requestOne.id && Number(row.revision) === 1
  ));
  assert.doesNotMatch(JSON.stringify(organizerEvent), /message|private_reason|email|phone/i);
  const queueAfterEvent = await rpc(organizer, "get_pachanga_competition_registration_queue_v1", {
    page_offset: 0,
    page_size: 20,
    status_filter: null,
    target_competition_id: ids.competition,
  });
  assert.equal(queueAfterEvent.items.find((item) => item.id === requestOne.id).status, "submitted");

  const accepted = await registrationCommand(
    organizer,
    requestOne.id,
    requestOne.revision,
    "registration.accept",
    { publicReason: "Equipo aceptado.", reason: "First place accepted" },
  );
  if (accepted.error) throw new Error(diagnostic(accepted), { cause: accepted.error });
  assert.ok(accepted.data.snapshot.entryId);
  const teamEvent = await teamOneFeed.waitFor((row) => (
    row.entity_id === requestOne.id && Number(row.revision) === 2
  ));
  assert.doesNotMatch(JSON.stringify(teamEvent), /message|private_reason|email|phone/i);
  const teamOneReadback = await rpc(teamClients[0], "get_my_pachanga_competition_registration_requests_v1", {
    page_offset: 0,
    page_size: 20,
    target_team_id: groups[1].id,
  });
  assert.equal(teamOneReadback.items[0].status, "accepted");
  report.realtime = { canonicalRefetch: true, privatePayloadFields: 0, received: true };

  async function submitTeam(index, message) {
    const result = await registrationCommand(
      teamClients[index - 1],
      publication.publicationId,
      publication.revision,
      "registration.submit",
      { message, reason: `Team ${index} request`, teamId: groups[index].id },
    );
    if (result.error) throw new Error(diagnostic(result), { cause: result.error });
    return result.data.snapshot;
  }

  const requestTwo = await submitTeam(2, "Solicitud concurrente A.");
  const requestThree = await submitTeam(3, "Solicitud concurrente B.");
  const race = await Promise.all([
    registrationCommand(organizer, requestTwo.id, 1, "registration.accept", {
      publicReason: "Equipo aceptado.", reason: "Last place race A",
    }),
    registrationCommand(organizerDevice2, requestThree.id, 1, "registration.accept", {
      publicReason: "Equipo aceptado.", reason: "Last place race B",
    }),
  ]);
  const winners = race.map((result, index) => ({ index, result })).filter(({ result }) => !result.error);
  const losers = race.map((result, index) => ({ index, result })).filter(({ result }) => result.error);
  assert.equal(winners.length, 1);
  assert.equal(losers.length, 1);
  assert.match(diagnostic(losers[0].result), /CAPACITY_REACHED|STALE_REVISION|PT409/i);
  const raceRequests = [requestTwo, requestThree];
  const losingRequest = raceRequests[losers[0].index];
  const losingClient = teamClients[losers[0].index + 1];
  const loserFeed = await subscribeInvalidations(losingClient, ids.competition, "race-loser");
  const waitlisted = await registrationCommand(
    organizer,
    losingRequest.id,
    1,
    "registration.waitlist",
    {
      privateReason: "Audited staging waitlist",
      publicReason: "Equipo en lista de espera.",
      reason: "Capacity reached",
    },
  );
  if (waitlisted.error) throw new Error(diagnostic(waitlisted), { cause: waitlisted.error });
  const waitlistEvent = await loserFeed.waitFor((row) => (
    row.entity_id === losingRequest.id && Number(row.revision) === 2
  ));
  assert.doesNotMatch(JSON.stringify(waitlistEvent), /private_reason|message|email|phone/i);
  const loserReadback = await rpc(losingClient, "get_my_pachanga_competition_registration_requests_v1", {
    page_offset: 0,
    page_size: 20,
    target_team_id: groups[losers[0].index + 2].id,
  });
  assert.equal(loserReadback.items[0].status, "waitlisted");
  report.concurrency = { accepted: 1, conflicts: 1, lastPlaceProtected: true };

  const requestFour = await submitTeam(4, "Solicitud que sera rechazada.");
  const rejected = await registrationCommand(organizer, requestFour.id, 1, "registration.reject", {
    privateReason: "Private review stays private.",
    publicReason: "La solicitud no encaja en esta edicion.",
    reason: "Format mismatch",
  });
  if (rejected.error) throw new Error(diagnostic(rejected), { cause: rejected.error });
  assert.equal(rejected.data.snapshot.status, "rejected");

  const requestFive = await submitTeam(5, "Solicitud que sera retirada.");
  const withdrawn = await registrationCommand(teamClients[4], requestFive.id, 1, "registration.withdraw", {
    reason: "Team withdrew before acceptance",
  });
  if (withdrawn.error) throw new Error(diagnostic(withdrawn), { cause: withdrawn.error });
  assert.equal(withdrawn.data.snapshot.status, "withdrawn");
  report.registration = {
    accepted: 2,
    idempotentReplay: true,
    rejected: 1,
    waitlisted: 1,
    withdrawn: 1,
  };

  const organizerNotifications = await rpc(organizer, "get_pachanga_notification_center_v1");
  const teamNotifications = await rpc(losingClient, "get_pachanga_notification_center_v1");
  const organizerKinds = new Set(organizerNotifications.map((item) => item.kind));
  const teamKinds = new Set(teamNotifications.map((item) => item.kind));
  assert.ok(organizerKinds.has("competition_registration_request"));
  assert.ok(teamKinds.has("competition_registration_waitlisted"));
  report.notifications = {
    organizerRequest: true,
    teamWaitlist: true,
  };

  const platformHealth = await rpc(platform, "get_pachanga_public_competition_platform_health_v1");
  assert.equal(platformHealth.readModels.privacyViolations, 0);
  assert.equal(platformHealth.readModels.indexingViolations, 0);

  if (env.previewUrl) {
    for (const path of [
      "/competiciones",
      `/competiciones/${slug}`,
      "/admin?section=public-competitions",
      "/?demo=1&world=public-competitions",
    ]) {
      const response = await fetch(new URL(path, env.previewUrl), { redirect: "manual" });
      assert.ok(response.status < 500, `${path} returned ${response.status}`);
    }
    const manifest = await fetch(new URL("/manifest.webmanifest", env.previewUrl), { cache: "no-store" });
    assert.equal(manifest.status, 200);
    const worker = await fetch(new URL("/sw.js", env.previewUrl), { cache: "no-store" });
    assert.equal(worker.status, 200);
    assert.match(await worker.text(), /CACHE_VERSION|CACHE_NAME|service/i);
    report.preview = { manifest: true, routes: true, serviceWorker: true };
  }

  console.log(JSON.stringify(report));
} finally {
  if (platform && flagsChanged && initialFlags && !env.keepFlags) {
    await bestEffort("restore-public-competition-flags", async () => {
      await setFlags(platform, flagPatch(initialFlags), `Wave 7A staging flag restore ${runId}`);
    });
  }
  for (const channel of channels) {
    await bestEffort("remove-channel", () => channel.unsubscribe());
  }
  for (const supabase of clients) {
    await bestEffort("sign-out", () => supabase.auth.signOut());
    await bestEffort("disconnect-realtime", () => supabase.realtime.disconnect());
  }
  await bestEffort("disconnect-anonymous-realtime", () => anonymous.realtime.disconnect());
  await bestEffort("disconnect-service-realtime", () => fixtureAdmin.realtime.disconnect());
  if (temporaryPlatformAdminUserId) {
    await bestEffort("revoke-temporary-platform-admin", async () => {
      runSql(`
        delete from private.pachanga_platform_admin_roles
        where user_id = ${sqlLiteral(temporaryPlatformAdminUserId)}::uuid
          and role = 'platform_admin';
      `, "revoke temporary Wave 7A staging platform admin");
    });
  }
}
