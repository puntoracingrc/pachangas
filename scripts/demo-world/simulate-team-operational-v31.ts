import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import {
  assertTeamOperationalV31AuthorityProof,
  teamOperationalV31AuthorityHash,
  type TeamOperationalV31AuthorityProof,
} from "./team-operational-v31-authority";
import {
  assertDemoWorldV2AuthorityProof,
  type DemoWorldV2AuthorityProof,
} from "./demo-world-v2-authority";
import { demoWorldVerificationProjectionHash } from "./demo-world-verification-projection";

const root = path.resolve(import.meta.dirname, "../..");
const manifest = JSON.parse(readFileSync(path.join(root, "supabase/baselines/manifest.json"), "utf8")) as {
  absorbsThrough: string;
  baselinePath: string;
};
const adminUrl = process.env.TEAM_OPERATIONAL_DATABASE_URL
  || "postgresql://postgres:postgres@127.0.0.1:55322/postgres?sslmode=disable";
const psqlBin = process.env.PSQL_BIN || "psql";
const pgDumpBin = process.env.PG_DUMP_BIN || "pg_dump";
const suffix = randomBytes(5).toString("hex");
const databaseName = `pachangas_wave8b_demo_${suffix}`;
const infrastructureDump = path.join(tmpdir(), `pachangas-wave8b-demo-${suffix}.sql`);
const proofPath = path.join(root, "scripts/demo-world/team-operational-v31-authority-proof.json");
let cleanupFailure: unknown;

if (!["127.0.0.1", "localhost", "::1", "[::1]"].includes(new URL(adminUrl).hostname)) {
  throw new Error("TEAM_OPERATIONAL_DEMO_LOCAL_DATABASE_REQUIRED");
}

const migrations = readdirSync(path.join(root, "supabase/migrations"))
  .filter((name) => /^\d{14}_.+\.sql$/.test(name))
  .sort();
assert.equal(migrations.length, 212);
assert.equal(migrations.at(-1), "20260829221312_team_operational_hardening_indexes_flags_v1.sql");

function targetUrl() {
  const value = new URL(adminUrl);
  value.pathname = `/${databaseName}`;
  value.searchParams.set("sslmode", "disable");
  return value.toString();
}

function run(binary: string, args: string[], label: string) {
  const result = spawnSync(binary, args, {
    cwd: root,
    encoding: "utf8",
    env: process.env,
    maxBuffer: 256 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${label} failed (${result.status}):\n${result.stdout ?? ""}${result.stderr ?? ""}`);
  }
  return (result.stdout ?? "").trim();
}

function quote(value: string) {
  return `'${value.replaceAll("'", "''")}'`;
}

function admin(sql: string, label: string) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", "-Atq", adminUrl, "-c", sql], label);
}

function query(args: string[], label: string) {
  return run(psqlBin, ["-X", "-w", "-v", "ON_ERROR_STOP=1", ...args], label);
}

function dropDatabase() {
  const exists = admin(`select count(*) from pg_database where datname=${quote(databaseName)}`, "inspect Demo V3.1 database");
  if (exists !== "1") return;
  admin(`alter database ${databaseName} with allow_connections false`, "close Demo V3.1 database");
  admin("select pg_sleep(0.25)", "wait for Demo V3.1 internal clients");
  admin(`select pg_terminate_backend(activity.pid) from pg_stat_activity activity
    join pg_roles roles on roles.oid=activity.usesysid
    where activity.datname=${quote(databaseName)} and activity.pid<>pg_backend_pid()
      and not roles.rolsuper`, "terminate Demo V3.1 clients");
  admin(`drop database ${databaseName}`, "drop Demo V3.1 database");
}

function buildCompetitionContinuity(authority: DemoWorldV2AuthorityProof) {
  const teamCEntryNumber = 3;
  const canonicalMatch = authority.matches.find((match) => (
    match.homeEntryNumber === teamCEntryNumber
    && match.outcome === "MIRROR_SPORTING_RESULT"
    && match.result.home > match.result.away
  ));
  const standing = authority.standings.find(({ entryNumber }) => entryNumber === teamCEntryNumber);
  const teamDHistory = authority.matches.find((match) => (
    match.outcome === "MIRROR_SPORTING_RESULT"
    && (match.homeEntryNumber === 4 || match.awayEntryNumber === 4)
  ));
  assert.ok(canonicalMatch);
  assert.ok(standing);
  assert.ok(teamDHistory);
  return {
    sourceAuthorityHash: demoWorldVerificationProjectionHash(authority),
    teamC: {
      canonicalResult: canonicalMatch.result,
      existingCompetitionOperationsAllowed: true as const,
      officialResultProvenance: "demo-world-canonical-league-engine" as const,
      pointsAfter: standing.effectivePoints,
      pointsBefore: standing.effectivePoints - 3,
      restrictionPreset: "SOCIAL_ONLY" as const,
      standingsChangedByOfficialResult: true as const,
    },
    teamD: {
      automaticForfeitCreated: false as const,
      automaticNoShowCreated: false as const,
      historicalResultPreserved: true as const,
      newCompetitionRegistrationBlocked: true as const,
    },
  };
}

let proof: TeamOperationalV31AuthorityProof | undefined;
try {
  run(pgDumpBin, [
    "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
    "--exclude-schema=public", "--exclude-schema=private", "--exclude-schema=simulation",
    "--exclude-schema=supabase_migrations", "--exclude-schema=realtime",
    "--file", infrastructureDump, adminUrl,
  ], "export local Supabase infrastructure");
  admin(`create database ${databaseName} template template0`, "create Demo V3.1 database");
  query(["-q", targetUrl(), "-f", infrastructureDump], "restore Demo V3.1 infrastructure");
  query(["-Atq", targetUrl(), "-c", "create publication supabase_realtime"], "create Demo V3.1 Realtime publication");
  const migrationFiles = [
    path.join(root, manifest.baselinePath),
    ...migrations
      .filter((name) => name.slice(0, 14) > manifest.absorbsThrough)
      .map((name) => path.join(root, "supabase/migrations", name)),
  ];
  const migrationArgs = ["-q", "--single-transaction", targetUrl()];
  for (const file of migrationFiles) migrationArgs.push("-f", file);
  query(migrationArgs, "bootstrap Demo V3.1 authority database");
  query(["-q", targetUrl(), "-f", path.join(root, "tests/team-operational-state-v1-fixture.sql")], "load synthetic Team fixture");
  const sqlOutput = query([
    "-Atq", targetUrl(), "-f", path.join(root, "scripts/demo-world/team-operational-v31-simulation.sql"),
  ], "run Team Operational V3.1 simulation");
  const sqlPayload = JSON.parse(sqlOutput.split("\n").filter(Boolean).at(-1) ?? "{}") as Omit<
    TeamOperationalV31AuthorityProof,
    "authorityHash" | "competitionContinuity"
  >;
  const canonicalAuthority = assertDemoWorldV2AuthorityProof(JSON.parse(readFileSync(
    path.join(root, "scripts/demo-world/demo-world-v2-authority-proof.json"),
    "utf8",
  )) as DemoWorldV2AuthorityProof);
  const payload: Omit<TeamOperationalV31AuthorityProof, "authorityHash"> = {
    ...sqlPayload,
    competitionContinuity: buildCompetitionContinuity(canonicalAuthority),
  };
  proof = assertTeamOperationalV31AuthorityProof({
    ...payload,
    authorityHash: teamOperationalV31AuthorityHash(payload),
  });
} finally {
  try {
    dropDatabase();
    rmSync(infrastructureDump, { force: true });
  } catch (error) {
    cleanupFailure = error;
  }
}

if (cleanupFailure) throw cleanupFailure;
assert.ok(proof);

if (process.argv.includes("--write-proof")) {
  writeFileSync(proofPath, `${JSON.stringify(proof, null, 2)}\n`, "utf8");
}
if (process.argv.includes("--verify")) {
  const committed = assertTeamOperationalV31AuthorityProof(JSON.parse(
    readFileSync(proofPath, "utf8"),
  ) as TeamOperationalV31AuthorityProof);
  assert.deepEqual(committed, proof);
}

process.stdout.write(`${JSON.stringify({
  authorityHash: proof.authorityHash,
  cleanup: "PASS",
  database: proof.database,
  operationReceipts: proof.operationReceipts,
  remoteWrites: proof.remoteWrites,
  scenarios: proof.scenarios.length,
  verification: process.argv.includes("--verify") ? "PASS" : "GENERATED",
})}\n`);
