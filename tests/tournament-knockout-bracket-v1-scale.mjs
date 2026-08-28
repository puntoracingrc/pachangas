import assert from "node:assert/strict";
import { resolve } from "node:path";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";
import {
  createR6cFixture,
  r6cCheckpointMarkers,
} from "./tournament-knockout-bracket-v1-postgres-fixture.mjs";

const harness = createR6cPostgresHarness("scale");
const fixture = createR6cFixture(harness);
const database = harness.databaseName("volume");

function counts() {
  return JSON.parse(harness.query(database, `
    select jsonb_build_object(
      'brackets', (select count(*) from public.pachanga_tournament_brackets),
      'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes),
      'slots', (select count(*) from public.pachanga_tournament_bracket_node_slots),
      'advanceDecisions', (select count(*) from public.pachanga_tournament_bracket_advance_decisions),
      'canonicalMatches', (select count(*) from public.pachanga_canonical_matches),
      'completionSnapshots', (select count(*) from public.pachanga_tournament_completion_snapshots)
    )::text;
  `, "read R6C scale counts"));
}

try {
  fixture.prepareR6c(database, r6cCheckpointMarkers.finalAdvanced);
  const baseline = counts();
  const output = harness.psql(database, [
    "-Atq", "-c", "begin",
    "-f", resolve(harness.root, "tests/tournament-knockout-bracket-v1-scale.sql"),
    "-c", "rollback",
  ], "run R6C transactional scale matrix");
  const line = output.split("\n").find((value) => value.startsWith("R6C_SCALE_REPORT|"));
  assert.ok(line, "R6C scale report missing");
  const report = JSON.parse(line.slice("R6C_SCALE_REPORT|".length));
  assert.deepEqual(report, {
    advanceDecisions: 50000,
    brackets: 10000,
    canonicalMatches: 20000,
    completionSnapshots: 10000,
    nodes: 100000,
    slots: 100000,
    statementTimeoutMs: 240000,
  });
  assert.deepEqual(counts(), baseline, "R6C scale transaction did not roll back fully");
  process.stdout.write(`R6C_SCALE_RUNNER_REPORT|${JSON.stringify({
    ...report,
    migrations: 176,
    rollback: true,
  })}\n`);
} finally {
  harness.cleanup();
}
