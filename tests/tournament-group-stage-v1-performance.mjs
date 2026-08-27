import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createR6bPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const harness = createR6bPostgresHarness("performance");
const source = readFileSync(resolve(harness.root, "tests/tournament-group-stage-v1-db.sql"), "utf8")
  .replace(
    "\\ir tournament-foundation-draw-v1-fixture.sql",
    `\\i '${resolve(harness.root, "tests/tournament-foundation-draw-v1-fixture.sql").replaceAll("'", "''")}'`,
  );

function report(output, prefix) {
  const line = output.split("\n").find((value) => value.startsWith(prefix));
  assert.ok(line, `${prefix} missing`);
  return JSON.parse(line.slice(prefix.length));
}

function committedPrefix(marker) {
  const position = source.indexOf(marker);
  assert.notEqual(position, -1, `R6B performance marker missing: ${marker}`);
  return `${source.slice(0, position)}\ncommit;\n`;
}

function assertBounded(operations) {
  for (const [operation, metrics] of Object.entries(operations)) {
    assert.ok(metrics.samples >= 7, `${operation} has too few samples`);
    assert.ok(metrics.p50Ms >= 0, `${operation} p50 is invalid`);
    assert.ok(metrics.p95Ms >= metrics.p50Ms, `${operation} p95 precedes p50`);
    assert.ok(metrics.p95Ms < 120000, `${operation} exceeded the 120-second bound`);
  }
}

const matrixDatabase = harness.databaseName("matrix");
const trackingDatabase = harness.databaseName("tracking");

try {
  harness.bootstrap(matrixDatabase);
  const matrixOutput = harness.psql(matrixDatabase, [
    "-Atq", "-v", "R6A_ENGINE_KEEP=1",
    "-c", "begin",
    "-c", "select set_config('pachangas.r6b_performance','on',false)",
    "-f", resolve(harness.root, "tests/tournament-foundation-draw-v1-engine.sql"),
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-scale-matrix.sql"),
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-performance-matrix-report.sql"),
    "-c", "rollback",
  ], "measure R6B matrix performance");
  const matrix = report(matrixOutput, "R6B_PERFORMANCE_MATRIX_REPORT|");
  assertBounded(matrix.operations);

  harness.bootstrap(trackingDatabase);
  harness.psql(
    trackingDatabase,
    ["-Atq"],
    "load R6B official-results performance checkpoint",
    committedPrefix("insert into r6b_test_state values (\n  'qualification_rebuild_expected',"),
  );
  const trackingOutput = harness.psql(trackingDatabase, [
    "-Atq", "-c", "begin",
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-performance-tracking.sql"),
    "-c", "rollback",
  ], "measure R6B tracking performance");
  const tracking = report(trackingOutput, "R6B_PERFORMANCE_TRACKING_REPORT|");
  assertBounded(tracking.operations);

  const required = [
    "stage prepare 16",
    "schedule generation 16",
    "schedule generation 32",
    "schedule generation 64",
    "schedule validation 16",
    "canonical match publication 16",
    "Tournament Hub populated",
    "Round Tracker populated",
    "Group Standings",
    "Qualification rebuild",
    "Qualification publish",
  ];
  const operations = { ...matrix.operations, ...tracking.operations };
  for (const name of required) assert.ok(operations[name], `missing required metric: ${name}`);

  process.stdout.write(`R6B_PERFORMANCE_REPORT|${JSON.stringify({
    boundedStatementTimeoutMs: 120000,
    matrix,
    migrations: 169,
    rollback: true,
    tracking,
  })}\n`);
} finally {
  harness.cleanup();
}
