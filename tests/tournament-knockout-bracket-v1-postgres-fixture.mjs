import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const R6B_KEEP_TRANSACTION = "R6B_KEEP_TRANSACTION=1";

export function createR6cFixture(harness) {
  const r6bPath = resolve(harness.root, "tests/tournament-group-stage-v1-db.sql");
  const r6cPath = resolve(harness.root, "tests/tournament-knockout-bracket-v1-db.sql");
  const r6aFixturePath = resolve(harness.root, "tests/tournament-foundation-draw-v1-fixture.sql");
  const r6bSource = readFileSync(r6bPath, "utf8").replace(
    "\\ir tournament-foundation-draw-v1-fixture.sql",
    `\\i '${r6aFixturePath.replaceAll("'", "''")}'`,
  );
  const r6cSource = readFileSync(r6cPath, "utf8");

  function sourceThrough(marker) {
    const position = r6cSource.indexOf(marker);
    assert.notEqual(position, -1, `R6C checkpoint marker missing: ${marker}`);
    return `${r6bSource}\n${r6cSource.slice(0, position)}\ncommit;\n`;
  }

  function prepareR6b(database) {
    harness.bootstrap(database);
    harness.psql(database, [
      "-Atq", "-v", R6B_KEEP_TRANSACTION,
    ], "prepare committed R6B checkpoint", `${r6bSource}\ncommit;\n`);
    return database;
  }

  function prepareR6c(database, marker) {
    harness.bootstrap(database);
    harness.psql(database, [
      "-Atq", "-v", R6B_KEEP_TRANSACTION,
    ], `prepare committed R6C checkpoint before ${marker}`, sourceThrough(marker));
    return database;
  }

  return {
    prepareR6b,
    prepareR6c,
    sourceThrough,
  };
}

export const r6cCheckpointMarkers = Object.freeze({
  reserved: "-- Generate the four participant-resolved quarterfinals.",
  quarterfinalsGenerated: "create or replace function pg_temp.r6c_play_node(",
  quarterfinalsAdvanced: "-- Regression R6C-PRODUCT-008:",
  semifinalsAdvanced: "select pg_temp.r6c_assert(\n  (select count(*)=1 and min(status)='match_created'",
  finalAdvanced: "insert into r6c_test_state values (\n  'completion_expected'",
});
