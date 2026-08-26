import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(resolve(root, "supabase/baselines/manifest.json"), "utf8"));
const adminUrl = process.env.COMPETITION_CONFIGURATION_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const templateDatabase = `pachangas_wave5_concurrency_${suffix}`;
const infrastructureDump = resolve(tmpdir(), `pachangas-wave5-concurrency-${suffix}.sql`);
const caseDatabases = new Set();

const owner = "5a010000-0000-4000-8000-000000000001";
const director = "c4010000-0000-4000-8000-000000000002";
const wave4Competition = "c4200000-0000-4000-8000-000000000001";
const wave4Player = "c4300000-0000-4000-8000-000000000001";
const wave4Match = {
  canonical: "c4400000-0000-4000-8000-000000000006",
  context: "c4400000-0000-4000-8000-000000000008",
};
const referee = {
  user: "d6010000-0000-4000-8000-000000000001",
  profile: "d6020000-0000-4000-8000-000000000001",
};

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("WAVE5_CONCURRENCY_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(resolve(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 158);

function targetUrl(databaseName) {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary, args, label, input = undefined) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    input,
    maxBuffer: 128 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function admin(sql, label) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(databaseName, sql, label = "query Wave 5 concurrency database") {
  return run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName), "-c", sql],
    label,
  );
}

function authenticated(actorId, statement, tail = "") {
  return `
begin;
set local role authenticated;
select set_config('request.jwt.claims', ${quote(JSON.stringify({ role: "authenticated", sub: actorId }))}, true);
${statement};
${tail}
commit;
`;
}

function configSql(actorId, operationId, aggregateId, expectedRevision, action, payload = {}, tail = "") {
  return authenticated(actorId, `select public.command_pachanga_competition_configuration_v1(
    ${quote(operationId)}::uuid, ${quote(aggregateId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"5.1.0+wave5-concurrency","serviceWorkerVersion":"sw-wave5-concurrency","installedMode":"standalone","surface":"wave5_concurrency"}'::jsonb
  )`, tail);
}

function registrationSql(operationId, editionId, expectedRevision, ruleRevisionId) {
  return authenticated(owner, `select public.command_pachanga_league_participation_v1(
    ${quote(operationId)}::uuid, ${quote(editionId)}::uuid, ${expectedRevision},
    'registration.open',
    ${quote(JSON.stringify({
      registrationMode: "INVITE_ONLY",
      ruleRevisionId,
      closesAt: "2027-02-28T23:59:59Z",
      reason: "Wave 5 concurrency registration",
    }))}::jsonb,
    '{"clientVersion":"5.1.0+wave5-concurrency","surface":"wave5_concurrency"}'::jsonb
  )`);
}

function disciplineSql(operationId, expectedRevision) {
  return authenticated(director, `select public.command_pachanga_competition_discipline_v1(
    ${quote(operationId)}::uuid,
    ${quote(wave4Competition)}::uuid,
    ${quote(wave4Match.canonical)}::uuid,
    ${expectedRevision},
    'event.record',
    ${quote(JSON.stringify({
      playerProfileId: wave4Player,
      cardTypeCode: "YELLOW",
      context: "in_match",
      minute: 24,
      publicReasonCategory: "accumulation",
      publicSummary: "Wave 5 concurrency yellow",
    }))}::jsonb,
    '{"clientVersion":"5.1.0+wave5-concurrency","surface":"wave5_concurrency"}'::jsonb
  )`);
}

function assignmentSql(actorId, operationId, assignmentId, expectedRevision, action, payload = {}) {
  return authenticated(actorId, `select public.command_pachanga_referee_assignment_beta_v1(
    ${quote(operationId)}::uuid, ${quote(assignmentId)}::uuid, ${expectedRevision},
    ${quote(action)}, ${quote(JSON.stringify(payload))}::jsonb,
    '{"clientVersion":"5.1.0+wave5-concurrency","serviceWorkerVersion":"sw-wave5-concurrency","installedMode":"standalone","surface":"wave5_concurrency"}'::jsonb
  )`);
}

function parseLastJson(output, label) {
  const line = output.split("\n").filter(Boolean).at(-1);
  assert.ok(line, `${label} returned no JSON`);
  return JSON.parse(line);
}

function command(databaseName, sql, label) {
  return parseLastJson(query(databaseName, sql, label), label);
}

function concurrent(databaseName, sql, label) {
  return new Promise((resolveResult) => {
    const child = spawn(
      psqlBin,
      ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", targetUrl(databaseName)],
      { cwd: root, env: process.env, stdio: ["pipe", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("close", (code) => resolveResult({ code, label, stderr: stderr.trim(), stdout: stdout.trim() }));
    child.stdin.end(sql);
  });
}

async function race(databaseName, left, right) {
  return Promise.all([
    concurrent(databaseName, left.sql, left.label),
    concurrent(databaseName, right.sql, right.label),
  ]);
}

function assertOneWinner(results, label) {
  const winners = results.filter((result) => result.code === 0);
  const losers = results.filter((result) => result.code !== 0);
  assert.equal(winners.length, 1, `${label} expected one winner: ${JSON.stringify(results)}`);
  assert.equal(losers.length, 1, `${label} expected one explicit loser`);
  assert.match(
    losers[0].stderr,
    /STALE_REVISION|COMPETITION_CONFIGURATION_(?:FROZEN|IN_PROGRESS|DRAFT_NOT_EDITABLE|DISCIPLINE_IN_USE|REFEREE_POLICY_IN_USE)|PT409/i,
    `${label} loser was not an explicit stale/conflict: ${losers[0].stderr}`,
  );
  return { winner: winners[0], loser: losers[0] };
}

function cloneCase(label) {
  const safe = label.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase();
  const databaseName = `pachangas_wave5_${safe}_${suffix}`;
  admin(`create database ${databaseName} template ${templateDatabase}`, `clone ${label}`);
  caseDatabases.add(databaseName);
  return databaseName;
}

function dropDatabase(databaseName) {
  admin(`alter database ${databaseName} with allow_connections false`, `close ${databaseName}`);
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.rolname=activity.usename
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, `terminate ${databaseName}`);
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const connections = Number(admin(
      `select count(*) from pg_stat_activity where datname=${quote(databaseName)}`,
      `inspect ${databaseName}`,
    ));
    if (connections === 0) break;
    spawnSync("sleep", ["0.1"]);
    if (attempt === 29) {
      throw new Error(`WAVE5_CONCURRENCY_CLEANUP_CONNECTIONS_REMAIN:${databaseName}:${connections}`);
    }
  }
  admin(`drop database if exists ${databaseName}`, `drop ${databaseName}`);
  caseDatabases.delete(databaseName);
}

function findWave5Competition(databaseName) {
  return query(
    databaseName,
    "select id from public.pachanga_competitions where name='Liga Wave 5A' order by server_sequence desc,id desc limit 1",
    "find Wave 5 competition",
  );
}

function prepareDraft(databaseName, competitionId, actorId, reason) {
  const competitionRevision = Number(query(
    databaseName,
    `select revision from public.pachanga_competitions where id=${quote(competitionId)}::uuid`,
    "read competition revision",
  ));
  const response = command(
    databaseName,
    configSql(actorId, randomUUID(), competitionId, competitionRevision, "draft.create", {
      authoringMode: "ADVANCED",
      reason,
    }),
    `create ${reason} draft`,
  );
  return {
    id: response.snapshot.id,
    revision: response.confirmedRevision,
    steps: response.snapshot.steps,
  };
}

function mutateStep(step, path, value) {
  const clone = structuredClone(step);
  let cursor = clone;
  for (const key of path.slice(0, -1)) cursor = cursor[key];
  cursor[path.at(-1)] = value;
  return clone;
}

function proposeAndAccept(databaseName) {
  const assignmentId = randomUUID();
  command(databaseName, assignmentSql(
    director,
    randomUUID(),
    assignmentId,
    0,
    "assignment.propose",
    {
      refereeProfileId: referee.profile,
      sourceKind: "competition_generated",
      sourceId: "c4400000-0000-4000-8000-000000000005",
      requesterKind: "COMPETITION",
      requesterId: wave4Competition,
      responseDeadline: new Date(Date.now() + 10 * 24 * 60 * 60 * 1000).toISOString(),
      feeMode: "FREE",
    },
  ), "propose referee assignment");
  command(databaseName, assignmentSql(
    referee.user, randomUUID(), assignmentId, 1, "assignment.accept",
  ), "accept referee assignment");
  return assignmentId;
}

function prepareRefereePolicy(databaseName) {
  const policy = {
    usage: "OPTIONAL",
    role: "MAIN_REFEREE",
    proposerRoles: ["competition_director", "competition_owner", "competition_referee_manager"],
    acceptanceIsSufficient: false,
    organizerConfirmationRequired: true,
    responseDeadlineHours: 72,
    reconfirmAfterScheduleChange: true,
    modalityRequired: true,
    serviceAreaRequired: true,
    priorClubRelationshipRequired: false,
    replacementAllowed: true,
    requiredBeforeReady: false,
    authority: {
      reportCards: true,
      reportIncidents: true,
      observeScore: true,
      officialResult: false,
      standings: false,
      rating: false,
    },
    fee: {
      mode: "FREE",
      fixedCents: null,
      travelIncluded: false,
      publicConsent: false,
      currency: "EUR",
      paymentProcessing: false,
    },
  };
  query(databaseName, `alter table public.pachanga_competition_rule_revisions
      disable trigger guard_pachanga_competition_rule_history_v1;
    with patched as (
      select revisions.id,revisions.schema_version,
        jsonb_set(revisions.rule_document,'{operations,refereePolicy}',${quote(JSON.stringify(policy))}::jsonb,true) document
      from public.pachanga_competition_rule_revisions revisions
      where revisions.id=(select contexts.rule_revision_id
        from public.pachanga_competition_match_contexts contexts
        where contexts.id=${quote(wave4Match.context)}::uuid)
    )
    update public.pachanga_competition_rule_revisions revisions set
      rule_document=patched.document,
      checksum=private.pachanga_competition_rule_checksum_v1(revisions.schema_version,patched.document)
    from patched where revisions.id=patched.id`, "prepare canonical referee policy in disposable fixture");
  query(databaseName, "alter table public.pachanga_competition_rule_revisions enable trigger guard_pachanga_competition_rule_history_v1", "restore RuleRevision immutability guard");
}

try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${templateDatabase} template template0`, "create Wave 5 concurrency template");
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", infrastructureDump],
    "restore concurrency infrastructure",
  );
  query(templateDatabase, "create publication supabase_realtime;", "create concurrency publication");
  const applyArgs = [
    "-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", "--single-transaction",
    targetUrl(templateDatabase), "-f", resolve(root, manifest.baselinePath),
  ];
  for (const name of migrations.filter((name) => name.slice(0, 14) > manifest.absorbsThrough)) {
    applyArgs.push("-f", resolve(root, "supabase/migrations", name));
  }
  run(psqlBin, applyArgs, "bootstrap Wave 5 concurrency template");
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", resolve(root, "tests/referee-assignments-private-beta-v1-fixture.sql")],
    "load Wave 4 canonical fixture",
  );
  run(
    psqlBin,
    ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-q", targetUrl(templateDatabase), "-f", resolve(root, "tests/competition-configuration-center-v1-fixture.sql")],
    "load Wave 5 canonical fixture",
  );

  const summaries = {};
  let databaseName = cloneCase("two_configuration_edits");
  let competitionId = findWave5Competition(databaseName);
  let draft = prepareDraft(databaseName, competitionId, owner, "two edits");
  let results = await race(
    databaseName,
    { label: "simple", sql: configSql(owner, randomUUID(), draft.id, draft.revision, "draft.mode.set", { mode: "SIMPLE" }) },
    { label: "advanced", sql: configSql(owner, randomUUID(), draft.id, draft.revision, "draft.mode.set", { mode: "ADVANCED" }) },
  );
  assertOneWinner(results, "two configuration edits");
  summaries.twoEdits = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("publish_vs_edit");
  competitionId = findWave5Competition(databaseName);
  draft = prepareDraft(databaseName, competitionId, owner, "publish versus edit");
  let validated = command(
    databaseName,
    configSql(owner, randomUUID(), draft.id, draft.revision, "draft.validate", {
      effectiveScope: "FUTURE_ONLY",
      reason: "concurrency validation",
    }),
    "validate publish race draft",
  );
  results = await race(
    databaseName,
    { label: "publish", sql: configSql(owner, randomUUID(), draft.id, validated.confirmedRevision, "draft.publish", {
      confirmImpact: true,
      confirmRuleSummary: true,
      reason: "concurrency publication",
    }) },
    { label: "edit", sql: configSql(owner, randomUUID(), draft.id, validated.confirmedRevision, "draft.mode.set", { mode: "SIMPLE" }) },
  );
  assertOneWinner(results, "publish versus edit");
  summaries.publishVsEdit = "1 winner / 1 stale";
  dropDatabase(databaseName);

  databaseName = cloneCase("registration_vs_structural_edit");
  competitionId = findWave5Competition(databaseName);
  draft = prepareDraft(databaseName, competitionId, owner, "registration versus format");
  const edition = JSON.parse(query(
    databaseName,
    `select jsonb_build_object('id',editions.id,'revision',editions.revision,'ruleRevisionId',editions.rule_revision_id)
     from public.pachanga_competition_editions editions
     where editions.competition_id=${quote(competitionId)}::uuid and editions.status='draft'
     order by editions.server_sequence desc,editions.id desc limit 1`,
    "read registration race edition",
  ));
  const formatStep = mutateStep(draft.steps["4"], ["maximumTeams"], 10);
  results = await race(
    databaseName,
    { label: "registration", sql: registrationSql(randomUUID(), edition.id, edition.revision, edition.ruleRevisionId) },
    { label: "structural-edit", sql: configSql(owner, randomUUID(), draft.id, draft.revision, "draft.section.save", { step: 4, data: formatStep }) },
  );
  assertOneWinner(results, "registration.open versus structural edit");
  summaries.registrationVsStructuralEdit = "1 winner / 1 freeze conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("schedule_publish_vs_rule_change");
  query(databaseName, "alter table public.pachanga_competition_schedule_items disable trigger guard_pachanga_schedule_item_v1", "disable terminal schedule guard");
  query(databaseName, `update public.pachanga_competition_schedule_items items set status='validated',revision=items.revision+1
    from public.pachanga_competition_rounds rounds
    join public.pachanga_competition_schedule_revisions revisions on revisions.id=rounds.schedule_revision_id
    join public.pachanga_competition_schedule_plans plans on plans.id=revisions.schedule_plan_id
    where items.round_id=rounds.id and plans.competition_id=${quote(wave4Competition)}::uuid`, "prepare unpublished schedule");
  query(databaseName, "alter table public.pachanga_competition_schedule_items enable trigger guard_pachanga_schedule_item_v1", "restore terminal schedule guard");
  draft = prepareDraft(databaseName, wave4Competition, director, "schedule versus match policy");
  const scheduleItem = query(databaseName, `select items.id from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id=items.round_id
    join public.pachanga_competition_schedule_revisions revisions on revisions.id=rounds.schedule_revision_id
    join public.pachanga_competition_schedule_plans plans on plans.id=revisions.schedule_plan_id
    where plans.competition_id=${quote(wave4Competition)}::uuid order by items.server_sequence,items.id limit 1`, "find schedule item");
  const matchStep = mutateStep(draft.steps["7"], ["matchDurationMinutes"], Number(draft.steps["7"].matchDurationMinutes) + 5);
  results = await race(
    databaseName,
    { label: "schedule-publish", sql: `begin; update public.pachanga_competition_schedule_items items set status='published',revision=items.revision+1 where items.id=${quote(scheduleItem)}::uuid; commit;` },
    { label: "match-policy", sql: configSql(director, randomUUID(), draft.id, draft.revision, "draft.section.save", { step: 7, data: matchStep }) },
  );
  assertOneWinner(results, "schedule.publish versus rule change");
  summaries.scheduleVsRule = "1 winner / 1 freeze conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("official_result_vs_scoring_change");
  query(databaseName, `update public.pachanga_competition_match_contexts contexts
    set status='scheduled',revision=contexts.revision+1
    where contexts.competition_id=${quote(wave4Competition)}::uuid`, "prepare non-official match contexts");
  draft = prepareDraft(databaseName, wave4Competition, director, "official result versus scoring");
  const scoringStep = mutateStep(draft.steps["6"], ["pointsForWin"], 2);
  results = await race(
    databaseName,
    { label: "official-result", sql: `begin; update public.pachanga_competition_match_contexts contexts set status='official',revision=contexts.revision+1 where contexts.id=${quote(wave4Match.context)}::uuid; commit;` },
    { label: "scoring-policy", sql: configSql(director, randomUUID(), draft.id, draft.revision, "draft.section.save", { step: 6, data: scoringStep }) },
  );
  assertOneWinner(results, "official result versus scoring change");
  summaries.officialResultVsScoring = "1 winner / 1 freeze conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("discipline_event_vs_catalog_change");
  draft = prepareDraft(databaseName, wave4Competition, director, "discipline event versus catalog");
  const disciplineStep = mutateStep(draft.steps["10"], ["yellow", "threshold"], 4);
  const disciplineRevision = Number(query(databaseName,
    `select discipline_revision from public.pachanga_competitions where id=${quote(wave4Competition)}::uuid`,
    "read discipline revision"));
  results = await race(
    databaseName,
    { label: "discipline-event", sql: disciplineSql(randomUUID(), disciplineRevision) },
    { label: "discipline-policy", sql: configSql(director, randomUUID(), draft.id, draft.revision, "draft.section.save", { step: 10, data: disciplineStep }) },
  );
  assertOneWinner(results, "disciplinary event versus catalog change");
  summaries.disciplineVsCatalog = "1 winner / 1 in-use conflict";
  dropDatabase(databaseName);

  databaseName = cloneCase("assignment_confirm_vs_referee_policy");
  prepareRefereePolicy(databaseName);
  const assignmentId = proposeAndAccept(databaseName);
  draft = prepareDraft(databaseName, wave4Competition, director, "assignment confirmation versus referee policy");
  const refereeStep = mutateStep(draft.steps["11"], ["responseDeadlineHours"], 96);
  results = await race(
    databaseName,
    { label: "assignment-confirm", sql: assignmentSql(director, randomUUID(), assignmentId, 2, "assignment.confirm") },
    { label: "referee-policy", sql: configSql(director, randomUUID(), draft.id, draft.revision, "draft.section.save", { step: 11, data: refereeStep }) },
  );
  assertOneWinner(results, "assignment confirm versus referee policy change");
  summaries.assignmentVsRefereePolicy = "1 winner / 1 in-use conflict";
  dropDatabase(databaseName);

  process.stdout.write(`${JSON.stringify({
    database: "temporary clones",
    migrations: migrations.length,
    races: summaries,
  })}\n`);
} finally {
  for (const databaseName of [...caseDatabases]) dropDatabase(databaseName);
  if (admin(`select count(*) from pg_database where datname=${quote(templateDatabase)}`, "find Wave 5 template") === "1") {
    dropDatabase(templateDatabase);
  }
  rmSync(infrastructureDump, { force: true });
}
