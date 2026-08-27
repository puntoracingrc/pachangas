import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createR6bPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const harness = createR6bPostgresHarness("scale");
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
  assert.notEqual(position, -1, `R6B scale marker missing: ${marker}`);
  return `${source.slice(0, position)}\ncommit;\n`;
}

function counts(database) {
  return JSON.parse(harness.query(database, `
    select jsonb_build_object(
      'contexts', (select count(*) from public.pachanga_competition_match_contexts),
      'officialResults', (select count(*) from public.pachanga_competition_official_result_decisions),
      'standingSnapshots', (select count(*) from public.pachanga_competition_standing_snapshots),
      'qualificationSnapshots', (select count(*) from public.pachanga_tournament_qualification_snapshots)
    )::text;
  `, "read R6B scale counts"));
}

const matrixDatabase = harness.databaseName("matrix");
const volumeDatabase = harness.databaseName("volume");

try {
  harness.bootstrap(matrixDatabase);
  const matrixOutput = harness.psql(matrixDatabase, [
    "-Atq", "-v", "R6A_ENGINE_KEEP=1",
    "-c", "begin",
    "-f", resolve(harness.root, "tests/tournament-foundation-draw-v1-engine.sql"),
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-scale-matrix.sql"),
    "-c", "rollback",
  ], "run R6B 16/32/64 scale matrix");
  const matrix = report(matrixOutput, "R6B_SCALE_MATRIX_REPORT|");
  assert.deepEqual(
    matrix.scenarios.map((scenario) => ({
      canonicalMatches: scenario.canonicalMatches,
      fixtures: scenario.fixtures,
      groups: scenario.groups,
      matchContexts: scenario.matchContexts,
      schedulePlans: scenario.schedulePlans,
      teams: scenario.teams,
    })),
    [
      { canonicalMatches: 24, fixtures: 24, groups: 4, matchContexts: 24, schedulePlans: 4, teams: 16 },
      { canonicalMatches: 48, fixtures: 48, groups: 8, matchContexts: 48, schedulePlans: 8, teams: 32 },
      { canonicalMatches: 96, fixtures: 96, groups: 16, matchContexts: 96, schedulePlans: 16, teams: 64 },
    ],
  );
  assert.equal(matrix.knockoutMatches, 0);
  assert.deepEqual(counts(matrixDatabase), {
    contexts: 0,
    officialResults: 0,
    qualificationSnapshots: 0,
    standingSnapshots: 0,
  });

  harness.bootstrap(volumeDatabase);
  harness.psql(
    volumeDatabase,
    ["-Atq"],
    "load R6B validated volume checkpoint",
    committedPrefix("insert into r6b_test_state values (\n  'publish_expected',"),
  );
  const baseline = counts(volumeDatabase);
  const volumeOutput = harness.psql(volumeDatabase, [
    "-Atq", "-c", "begin",
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-volume.sql"),
    "-c", "rollback",
  ], "run R6B transactional volume scale");
  const volume = report(volumeOutput, "R6B_VOLUME_REPORT|");
  assert.deepEqual(volume, {
    groupMatches: 10000,
    knockoutMatches: 0,
    officialResults: 10000,
    qualificationSnapshots: 1000,
    standingSnapshots: 1000,
    statementTimeoutMs: 240000,
  });
  assert.deepEqual(counts(volumeDatabase), baseline, "R6B volume transaction did not roll back fully");

  process.stdout.write(`R6B_SCALE_REPORT|${JSON.stringify({
    matrix,
    migrations: 169,
    rollback: true,
    volume,
  })}\n`);
} finally {
  harness.cleanup();
}
