import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const databaseUrl = process.env.TEAM_SHIELD_DATABASE_URL;
const psqlBin = process.env.PSQL_BIN || "psql";
const sqlTimeoutMs = Number(process.env.TEAM_SHIELD_SQL_TIMEOUT_MS || 30_000);

if (!databaseUrl) throw new Error("TEAM_SHIELD_DATABASE_URL is required");

function sqlText(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function runSql(sql, label) {
  return new Promise((resolve, reject) => {
    const child = spawn(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", databaseUrl], {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGKILL"), sqlTimeoutMs);
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ code, label, stderr: stderr.trim(), stdout: stdout.trim() });
    });
    child.stdin.end(sql);
  });
}

async function runOk(sql, label) {
  const result = await runSql(sql, label);
  if (result.code !== 0) throw new Error(`${label} failed\n${result.stderr}`);
  return result.stdout;
}

function lastJson(output, label) {
  const line = output.split("\n").filter(Boolean).at(-1);
  if (!line) throw new Error(`${label} returned no JSON`);
  return JSON.parse(line);
}

function authenticatedSql(userId, statement) {
  return `begin;
set local role authenticated;
select set_config('request.jwt.claims', ${sqlText(JSON.stringify({ sub: userId, role: "authenticated" }))}, true);
${statement};
commit;`;
}

function config(initials, shapeKey) {
  return {
    schemaVersion: 1,
    shapeKey,
    backgroundKey: "team.shield.background.duotone",
    patternKey: "team.shield.pattern.diagonal",
    primaryColorKey: "team.shield.color.midnight",
    secondaryColorKey: "team.shield.color.cyan",
    primarySymbolKey: "team.shield.symbol.ball_iq",
    secondarySymbolKey: null,
    borderKey: "team.shield.border.clean",
    topOrnamentKey: null,
    sideOrnamentKey: null,
    bottomOrnamentKey: null,
    initials,
    foundationYear: "2026",
    effectKey: null,
    primarySymbolScale: 1,
    primarySymbolRotation: 0,
  };
}

const userId = randomUUID();
const groupId = randomUUID();
const operationA = randomUUID();
const operationB = randomUUID();
const configA = config("A11", "team.shield.shape.hex_iq");
const configB = config("B11", "team.shield.shape.barrio");

const setupSql = `
insert into auth.users(id, email) values (${sqlText(userId)}::uuid, ${sqlText(`shield-${userId}@example.test`)});
insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values (${sqlText(groupId)}::uuid, ${sqlText(userId)}::uuid, 'Shield concurrency', ${sqlText(`SC${userId.slice(0, 6)}`)}, '{"players":[],"matches":[]}');
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (${sqlText(groupId)}::uuid, ${sqlText(userId)}::uuid, 'owner', 'Concurrency Owner');
update private.pachanga_team_cosmetic_settings
set team_cosmetics_enabled = true, updated_at = clock_timestamp()
where singleton;
`;

const cleanupSql = `
delete from public.pachanga_user_notifications where recipient_user_id = ${sqlText(userId)}::uuid;
delete from public.pachanga_groups where id = ${sqlText(groupId)}::uuid;
delete from auth.users where id = ${sqlText(userId)}::uuid;
update private.pachanga_team_cosmetic_settings
set team_cosmetics_enabled = false, updated_at = clock_timestamp()
where singleton;
`;

function saveSql(operationId, targetConfig) {
  return authenticatedSql(userId, `select public.save_pachanga_team_shield_loadout_v1(
    ${sqlText(groupId)}::uuid,
    ${sqlText(JSON.stringify(targetConfig))}::jsonb,
    ${sqlText(operationId)}::uuid,
    0,
    '{"clientVersion":"2.0.0+concurrency","displayMode":"browser","surface":"team-identity"}'::jsonb
  )`);
}

try {
  await runOk(setupSql, "team shield concurrency setup");
  const race = await Promise.all([
    runSql(saveSql(operationA, configA), "client A save"),
    runSql(saveSql(operationB, configB), "client B save"),
  ]);
  const successes = race.filter(({ code }) => code === 0);
  const conflicts = race.filter(({ code }) => code !== 0);
  assert.equal(successes.length, 1, JSON.stringify(race));
  assert.equal(conflicts.length, 1, JSON.stringify(race));
  assert.match(conflicts[0].stderr, /PT409|revision is newer|stale/i);

  const winnerIndex = race.findIndex(({ code }) => code === 0);
  const winningOperation = winnerIndex === 0 ? operationA : operationB;
  const winningConfig = winnerIndex === 0 ? configA : configB;
  const winningResponse = lastJson(successes[0].stdout, "winning shield response");
  assert.equal(winningResponse.confirmedRevision, 1);

  const replays = await Promise.all([
    runSql(saveSql(winningOperation, winningConfig), "desktop replay"),
    runSql(saveSql(winningOperation, winningConfig), "mobile replay"),
  ]);
  assert.ok(replays.every(({ code }) => code === 0), JSON.stringify(replays));
  assert.deepEqual(lastJson(replays[0].stdout, "desktop replay"), lastJson(replays[1].stdout, "mobile replay"));

  const canonical = lastJson(await runOk(
    authenticatedSql(userId, `select public.get_pachanga_team_shield_snapshot_v1(${sqlText(groupId)}::uuid)`),
    "canonical shield snapshot",
  ), "canonical shield snapshot");
  assert.equal(canonical.revision, 1);
  assert.deepEqual(canonical.config, winningConfig);

  const receipts = Number(await runOk(
    `select count(*) from public.pachanga_team_shield_operation_receipts where group_id = ${sqlText(groupId)}::uuid`,
    "shield receipt count",
  ));
  assert.equal(receipts, 1);

  process.stdout.write(`${JSON.stringify({ canonicalRevision: 1, conflict: true, idempotentReplay: true, receipts, winner: winnerIndex === 0 ? "client-a" : "client-b" })}\n`);
} finally {
  await runOk(cleanupSql, "team shield concurrency cleanup");
}
