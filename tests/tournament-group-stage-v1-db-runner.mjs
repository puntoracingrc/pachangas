import assert from "node:assert/strict";
import { resolve } from "node:path";
import { createR6bPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const harness = createR6bPostgresHarness("full_story");
const database = harness.databaseName("canonical");

try {
  harness.bootstrap(database);
  const output = harness.psql(
    database,
    ["-Atq", "-f", resolve(harness.root, "tests/tournament-group-stage-v1-db.sql")],
    "run R6B canonical full story",
  );
  const reportLine = output.split("\n").find((line) => line.startsWith("R6B_DB_REPORT|"));
  assert.ok(reportLine, "R6B full story did not emit its canonical report");
  const report = JSON.parse(reportLine.slice("R6B_DB_REPORT|".length));
  assert.deepEqual(report, {
    groups: 4,
    fixtures: 24,
    bracketSlots: 8,
    directWrites: 0,
    bracketStatus: "PUBLISHED",
    knockoutMatches: 0,
    canonicalMatches: 24,
    standingSnapshots: 4,
    qualificationStatus: "PUBLISHED",
  });
  assert.equal(Number(harness.query(database, `
    select count(*) from auth.users where email like 'r6a-fixture-%@example.test';
  `)), 0, "transactional R6B story leaked fixture users");
  assert.equal(Number(harness.query(database, `
    select count(*) from public.pachanga_competitions where slug='r6a-concurrency-fixture';
  `)), 0, "transactional R6B story leaked its competition");
  process.stdout.write(`R6B_DB_RUNNER_REPORT|${JSON.stringify({ ...report, migrations: 169, rollback: true })}\n`);
} finally {
  harness.cleanup();
}
