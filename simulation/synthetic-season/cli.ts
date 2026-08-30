import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { syntheticSeasonIntegrityErrors } from "../../app/demo-world/demo-world-v3-2-contract";
import { generateDemoWorldV32, writeDemoWorldV32 } from "../../scripts/demo-world/generate-demo-world-v3-2";
import { assertSyntheticSeasonEnvironment } from "./environment";
import { syntheticSeasonOracleReport } from "./oracles";

const execute = promisify(execFile);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function commandArgument(name: string) {
  const direct = process.argv.find((value) => value.startsWith(`--${name}=`));
  if (direct) return direct.slice(name.length + 3);
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

async function verifyProductAuthority() {
  const options = { cwd: root, env: process.env, maxBuffer: 20 * 1024 * 1024 };
  const v2 = await execute("npm", ["run", "demo-world:v2:verify"], options);
  const v31 = await execute("npm", ["run", "demo-world:v31:verify"], options);
  const demoWorldV2 = JSON.parse(v2.stdout.trim().split("\n").at(-1)!);
  const teamOperationalV31 = JSON.parse(v31.stdout.trim().split("\n").at(-1)!);
  assert.equal(demoWorldV2.database, "temporary-local-postgresql");
  assert.equal(demoWorldV2.destroyedAfterRun, true);
  assert.equal(demoWorldV2.migrations, 212);
  assert.equal(demoWorldV2.remoteWrites, 0);
  assert.ok(Array.isArray(demoWorldV2.rpcFamilies) && demoWorldV2.rpcFamilies.length >= 13);
  assert.equal(teamOperationalV31.database, "temporary-local-postgresql");
  assert.equal(teamOperationalV31.cleanup, "PASS");
  assert.equal(teamOperationalV31.remoteWrites, 0);
  assert.equal(teamOperationalV31.verification, "PASS");
  return { demoWorldV2, teamOperationalV31 };
}

function verifyBuild() {
  const first = generateDemoWorldV32();
  const second = generateDemoWorldV32();
  assert.equal(first.snapshot.manifest.hash, second.snapshot.manifest.hash, "manifest replay diverged");
  assert.equal(first.snapshot.season.proof.authorityHash, second.snapshot.season.proof.authorityHash, "authority replay diverged");
  assert.equal(first.snapshot.season.proof.publicSnapshotHash, second.snapshot.season.proof.publicSnapshotHash, "public replay diverged");
  assert.deepEqual(first.snapshot.season.proof.checkpointHashes, second.snapshot.season.proof.checkpointHashes, "checkpoint replay diverged");
  const integrity = syntheticSeasonIntegrityErrors(first.snapshot.season, first.checkpoints);
  assert.deepEqual(integrity, []);
  const oracle = syntheticSeasonOracleReport({
    checkpoints: first.checkpoints,
    disciplineEvents: first.disciplineEvents,
    index: first.snapshot.season,
    sanctions: first.sanctions,
  });
  assert.deepEqual(oracle.errors, []);
  return first;
}

async function simulate() {
  assertSyntheticSeasonEnvironment(process.env);
  const authority = await verifyProductAuthority();
  const written = await writeDemoWorldV32(root);
  const replay = verifyBuild();
  return {
    authority,
    cleanup: replay.snapshot.season.proof.cleanup,
    mode: "simulate",
    remoteWrites: 0,
    ...written,
  };
}

async function verify() {
  assertSyntheticSeasonEnvironment(process.env);
  const authority = await verifyProductAuthority();
  const generated = verifyBuild();
  const proofPath = path.join(root, "simulation/synthetic-season/generated/synthetic-season-proof.json");
  const frozen = JSON.parse(await readFile(proofPath, "utf8"));
  assert.equal(frozen.authorityHash, generated.snapshot.season.proof.authorityHash);
  assert.equal(frozen.publicSnapshotHash, generated.snapshot.season.proof.publicSnapshotHash);
  return {
    authority,
    authorityHash: frozen.authorityHash,
    mode: "verify",
    publicSnapshotHash: frozen.publicSnapshotHash,
    remoteWrites: 0,
    replayIdentical: true,
  };
}

function replay() {
  const generated = verifyBuild();
  return {
    authorityHash: generated.snapshot.season.proof.authorityHash,
    checkpointHashes: generated.snapshot.season.proof.checkpointHashes,
    mode: "replay",
    publicSnapshotHash: generated.snapshot.season.proof.publicSnapshotHash,
    replayIdentical: true,
  };
}

function checkpoint() {
  const requested = Number(commandArgument("week"));
  if (!Number.isInteger(requested) || requested < 0 || requested > 16) throw new Error("SYNTHETIC_SEASON_WEEK_INVALID");
  const generated = generateDemoWorldV32();
  const selected = [...generated.checkpoints].reverse().find(({ week }) => week <= requested) ?? generated.checkpoints[0]!;
  return { mode: "checkpoint", requestedWeek: requested, selected };
}

function inspect() {
  const generated = generateDemoWorldV32();
  return {
    authorityAnchors: generated.snapshot.season.proof.authorityAnchors,
    cleanup: generated.snapshot.season.proof.cleanup,
    counts: generated.snapshot.season.proof.counts,
    hashes: {
      authority: generated.snapshot.season.proof.authorityHash,
      checkpoints: generated.snapshot.season.proof.checkpointHashes,
      publicSnapshot: generated.snapshot.season.proof.publicSnapshotHash,
    },
    mode: "inspect",
    notificationScan: generated.snapshot.season.proof.notificationScan,
    privacyScan: generated.snapshot.season.proof.privacyScan,
    remoteWrites: generated.snapshot.season.remoteWrites,
    stripeTouched: generated.snapshot.season.proof.stripeTouched,
  };
}

const command = process.argv[2] ?? "inspect";
const result = command === "simulate"
  ? await simulate()
  : command === "verify"
    ? await verify()
    : command === "replay"
      ? replay()
      : command === "checkpoint"
        ? checkpoint()
        : command === "inspect"
          ? inspect()
          : (() => { throw new Error(`SYNTHETIC_SEASON_COMMAND_UNKNOWN:${command}`); })();

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
