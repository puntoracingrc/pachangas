import assert from "node:assert/strict";
import { resolve } from "node:path";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const harness = createR6cPostgresHarness("full_story");
const database = harness.databaseName("canonical");

try {
  harness.bootstrap(database);
  const output = harness.psql(
    database,
    [
      "-Atq",
      "-v", "R6B_KEEP_TRANSACTION=1",
      "-f", resolve(harness.root, "tests/tournament-group-stage-v1-db.sql"),
      "-f", resolve(harness.root, "tests/tournament-knockout-bracket-v1-db.sql"),
    ],
    "run R6C canonical full story",
  );
  const reportLine = output.split("\n").find((line) => line.startsWith("R6C_DB_REPORT|"));
  assert.ok(reportLine, "R6C full story did not emit its canonical report");
  const report = JSON.parse(reportLine.slice("R6C_DB_REPORT|".length));
  assert.deepEqual(report, {
    advances: 7,
    bracketStatus: "locked",
    championSnapshots: 2,
    knockoutMatches: 7,
    nodes: 7,
    resultKinds: 3,
    rewardGrants: 0,
    slotRevisions: 20,
    slots: 14,
  });
  assert.equal(Number(harness.query(database, `
    select count(*) from auth.users where email like 'r6a-fixture-%@example.test';
  `)), 0, "transactional R6C story leaked fixture users");
  assert.equal(Number(harness.query(database, `
    select count(*) from public.pachanga_tournament_brackets;
  `)), 0, "transactional R6C story leaked its bracket");
  process.stdout.write(`R6C_DB_RUNNER_REPORT|${JSON.stringify({
    ...report,
    migrations: 175,
    rollback: true,
  })}\n`);
} finally {
  harness.cleanup();
}
