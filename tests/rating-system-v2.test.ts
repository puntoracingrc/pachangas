import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";
import {
  INITIAL_TECHNICAL_QUESTIONS,
  calculateAdvancedRatings,
  calculateInitialRatings,
  type AttributeRatings,
  type InitialRatingInput,
} from "../app/laboratorio-ficha-jugador/_engine/player-rating-engine";
import { calculateSharedAssessmentResult } from "../app/rating-assessment-contract";
import {
  RATING_COMPARISON_OPTIONS,
  RATING_SYSTEM_V2_ENGINE_VERSION,
  activeEvidenceByEvaluator,
  aggregateOfficialObservation,
  buildRelativeObservations,
  calibrateFacets,
  calculateRatingCardLayers,
  comparisonObservation,
  countValidSharedMatches,
  detectReciprocalMaximumRatings,
  directionalRatingEligibility,
  externallyCalibratedTeamLevel,
  guestProvisionalLevel,
  goalkeeperRatingContract,
  lineupLevel,
  reconstructCardFromHistory,
  selectStableGroupPlayers,
  stableGroupLevel,
  stableJson,
  socialRatingDisclosure,
  type IndividualRatingEvidence,
  type RatingHistoryEvent,
  type SharedMatchCandidate,
} from "../app/rating-system-v2";

const FACETS_60: AttributeRatings = {
  pace: 60,
  shooting: 60,
  passing: 60,
  dribbling: 60,
  defending: 60,
  physical: 60,
};

test("authoritative revision conflicts are HTTP-safe and renamed implementations preserve qualifiers", () => {
  const migrationsDirectory = new URL("../supabase/migrations/", import.meta.url);
  const ratingMigrationSql = readdirSync(migrationsDirectory)
    .filter((name) => name.includes("rating_v2") || name.includes("rating_system_v2"))
    .map((name) => readFileSync(new URL(name, migrationsDirectory), "utf8"))
    .join("\n");
  const baseSchemaSql = readFileSync(new URL("../supabase/pachangas.sql", import.meta.url), "utf8");
  const conflictMigration = readFileSync(
    new URL("../supabase/migrations/20260803053937_rating_v2_http_conflicts.sql", import.meta.url),
    "utf8",
  );

  assert.doesNotMatch(ratingMigrationSql, /errcode\s*=\s*'40001'/i);
  assert.doesNotMatch(baseSchemaSql, /errcode\s*=\s*'40001'/i);
  assert.equal(conflictMigration.match(/rename to [a-z0-9_]+_impl;/g)?.length, 28);
  assert.equal(
    conflictMigration.match(
      /exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available/g,
    )?.length,
    28,
  );
  assert.match(conflictMigration, /raise sqlstate 'PT409'/);
  assert.match(conflictMigration, /raise sqlstate 'PT422'/);
  assert.doesNotMatch(conflictMigration, /grant execute on function public\.[a-z0-9_]+_impl/i);
  assert.equal(
    conflictMigration.match(/revoke all on function public\.[a-z0-9_]+_impl/g)?.length,
    28,
  );
  assert.match(conflictMigration, /pg_get_functiondef\(implementation\.oid\)/);
  assert.match(conflictMigration, /regexp_replace\(implementation\.implementation_name, '_impl\$', ''\)/);
  assert.match(conflictMigration, /Expected 28 Rating V2 implementations/);
});

function facets(value: number): AttributeRatings {
  return {
    pace: value,
    shooting: value,
    passing: value,
    dribbling: value,
    defending: value,
    physical: value,
  };
}

function evidence(id: string, evaluatorId: string, value: number, confidence = 50): IndividualRatingEvidence {
  return {
    id,
    evaluatorId,
    targetId: "target",
    groupId: "group",
    createdAt: `2026-01-${id.padStart(2, "0")}T10:00:00.000Z`,
    state: "active",
    observations: facets(value),
    evaluatorConfidence: confidence,
  };
}

function permutations<T>(items: T[]): T[][] {
  if (items.length <= 1) return [items];
  return items.flatMap((item, index) =>
    permutations([...items.slice(0, index), ...items.slice(index + 1)]).map((tail) => [item, ...tail]),
  );
}

function sharedMatch(id: string, overrides: Partial<SharedMatchCandidate> = {}): SharedMatchCandidate {
  return {
    finalized: true,
    finalizedAt: `2026-02-${id.padStart(2, "0")}T21:00:00.000Z`,
    id,
    evaluator: { attendanceConfirmed: true, playing: true },
    target: { attendanceConfirmed: true, playing: true },
    ...overrides,
  };
}

function assessmentInput(): InitialRatingInput {
  return {
    age: 31,
    heightCm: 178,
    weightKg: 76,
    primaryPosition: "central_midfielder",
    secondaryPositions: ["attacking_midfielder"],
    modeShares: [
      { mode: "futsal_5", percentage: 10 },
      { mode: "football_7", percentage: 70 },
      { mode: "football_11", percentage: 20 },
    ],
    experienceLevel: "social_league",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, 3])) as InitialRatingInput["answers"],
    calculatedAt: "2026-02-01T00:00:00.000Z",
  };
}

test("converts semantic comparisons into immutable relative observations", () => {
  assert.deepEqual(RATING_COMPARISON_OPTIONS.map((option) => option.label), ["Mucho peor", "Peor", "Parecido", "Mejor", "Mucho mejor"]);
  assert.equal(comparisonObservation(65, "MEJOR"), 70);
  assert.equal(comparisonObservation(4, "MUCHO_PEOR"), 0);
  assert.equal(comparisonObservation(97, "MUCHO_MEJOR"), 100);
  assert.deepEqual(
    buildRelativeObservations(FACETS_60, {
      pace: "MUCHO_PEOR",
      shooting: "PEOR",
      passing: "PARECIDO",
      dribbling: "MEJOR",
      defending: "MUCHO_MEJOR",
      physical: "PARECIDO",
    }),
    { pace: 50, shooting: 55, passing: 60, dribbling: 65, defending: 70, physical: 60 },
  );
});

test("first directional rating is available with zero shared matches", () => {
  assert.deepEqual(directionalRatingEligibility({ matches: [] }), {
    canRate: true,
    firstRating: true,
    requiredMatches: 0,
    sharedMatches: 0,
  });
});

test("a replacement is blocked at 0, 1 and 2 shared matches and allowed at 3", () => {
  const activeRatingAt = "2026-02-01T00:00:00.000Z";
  for (const count of [0, 1, 2]) {
    const eligibility = directionalRatingEligibility({ activeRatingAt, matches: Array.from({ length: count }, (_, index) => sharedMatch(String(index + 2))) });
    assert.equal(eligibility.canRate, false);
    assert.equal(eligibility.sharedMatches, count);
  }
  assert.equal(directionalRatingEligibility({ activeRatingAt, matches: [sharedMatch("2"), sharedMatch("3"), sharedMatch("4")] }).canRate, true);
});

test("shared match counting ignores absences, reserves, cancelled, deleted, pending and duplicate matches", () => {
  const valid = sharedMatch("2");
  const candidates: SharedMatchCandidate[] = [
    valid,
    { ...valid },
    sharedMatch("3", { evaluator: null }),
    sharedMatch("4", { target: { attendanceConfirmed: false, playing: true } }),
    sharedMatch("5", { evaluator: { attendanceConfirmed: true, playing: true, reserve: true } }),
    sharedMatch("6", { cancelled: true }),
    sharedMatch("7", { deleted: true }),
    sharedMatch("8", { finalized: false }),
    sharedMatch("9", { finalizedAt: "2026-01-01T21:00:00.000Z" }),
  ];
  assert.equal(countValidSharedMatches(candidates, "2026-02-01T00:00:00.000Z"), 1);
});

test("teammates and internal rivals count equally because eligibility depends on joint participation", () => {
  const teammates = sharedMatch("2");
  const rivals = sharedMatch("3");
  assert.equal(countValidSharedMatches([teammates, rivals]), 2);
});

test("A to B eligibility is independent from B to A", () => {
  const matches = [sharedMatch("2"), sharedMatch("3"), sharedMatch("4")];
  assert.equal(directionalRatingEligibility({ activeRatingAt: "2026-02-01T00:00:00.000Z", matches }).canRate, true);
  assert.equal(directionalRatingEligibility({ matches }).firstRating, true);
});

test("calibration is commutative for every permutation of the same votes", () => {
  const votes = [evidence("1", "a", 40, 10), evidence("2", "b", 65, 40), evidence("3", "c", 80, 90), evidence("4", "d", 55, 100)];
  const results = permutations(votes).map((items) => stableJson(calibrateFacets({ baseFacets: FACETS_60, baseReliability: 55, evidence: items })));
  assert.equal(new Set(results).size, 1);
});

test("one evaluator contributes one active opinion and superseded history stays reconstructible", () => {
  const events: RatingHistoryEvent[] = [
    { ...evidence("1", "a", 55), supersededAt: "2026-02-01T00:00:00.000Z" },
    { ...evidence("2", "a", 70), createdAt: "2026-02-01T00:00:00.000Z" },
    { ...evidence("3", "b", 65), createdAt: "2026-02-02T00:00:00.000Z", voidedAt: "2026-03-01T00:00:00.000Z" },
  ];

  assert.deepEqual(activeEvidenceByEvaluator(events, "2026-01-20T00:00:00.000Z").map((item) => item.id), ["1"]);
  assert.deepEqual(activeEvidenceByEvaluator(events, "2026-02-10T00:00:00.000Z").map((item) => item.id), ["2", "3"]);
  assert.deepEqual(activeEvidenceByEvaluator(events, "2026-03-10T00:00:00.000Z").map((item) => item.id), ["2"]);

  const before = reconstructCardFromHistory({
    at: "2026-01-20T00:00:00.000Z",
    baseFacets: FACETS_60,
    baseReliability: 50,
    events,
    primaryPosition: "central_midfielder",
  });
  const after = reconstructCardFromHistory({
    at: "2026-03-10T00:00:00.000Z",
    baseFacets: FACETS_60,
    baseReliability: 50,
    events,
    primaryPosition: "central_midfielder",
  });
  assert.ok((after.currentOverall ?? 0) > (before.currentOverall ?? 0));
});

test("an extreme vote is limited around the base and cannot cause an extreme jump", () => {
  const result = calibrateFacets({ baseFacets: FACETS_60, baseReliability: 20, evidence: [evidence("1", "a", 100, 100)] });
  assert.ok(result.pace > 60);
  assert.ok(result.pace < 65);
});

test("self-assessment reliability changes the prior weight as specified", () => {
  const low = calibrateFacets({ baseFacets: FACETS_60, baseReliability: 0, evidence: [evidence("1", "a", 75, 100)] });
  const high = calibrateFacets({ baseFacets: FACETS_60, baseReliability: 100, evidence: [evidence("1", "a", 75, 100)] });
  assert.ok(low.pace > high.pace);
});

test("all calculated layers stay finite and within 0..100", () => {
  const result = calculateRatingCardLayers({
    baseFacets: facets(Number.POSITIVE_INFINITY),
    baseReliability: Number.NaN,
    currentModifiers: facets(-500),
    evidence: [evidence("1", "a", Number.NaN, Number.POSITIVE_INFINITY)],
    primaryPosition: "striker",
  });
  for (const layer of [result.baseFacets, result.calibratedFacets, result.currentFacets]) {
    for (const value of Object.values(layer)) assert.ok(Number.isFinite(value) && value >= 0 && value <= 100);
  }
  assert.equal(result.engineVersion, RATING_SYSTEM_V2_ENGINE_VERSION);
});

test("stable group level uses all with 5 or 11 and only 11 habitual players with 12 or 15", () => {
  for (const count of [5, 11, 12, 15]) {
    const candidates = Array.from({ length: count }, (_, index) => ({
      id: `p-${String(index).padStart(2, "0")}`,
      calibratedOverall: 50 + index,
      confirmedAppearancesLast12Months: index,
      lastConfirmedAppearanceAt: `2026-01-${String((index % 28) + 1).padStart(2, "0")}T00:00:00.000Z`,
    }));
    const selected = selectStableGroupPlayers(candidates);
    assert.equal(selected.length, Math.min(11, count));
    assert.ok(stableGroupLevel(candidates) !== null);
    if (count > 11) assert.deepEqual(selected.map((item) => item.id), candidates.slice(-11).reverse().map((item) => item.id));
  }
});

test("lineup level uses real attending participants and guests, not reserves or absences", () => {
  assert.equal(lineupLevel([
    { id: "member", actualOverall: 60, active: true, attendanceConfirmed: true },
    { id: "guest", actualOverall: 80, active: true, attendanceConfirmed: true },
    { id: "reserve", actualOverall: 100, active: true, attendanceConfirmed: true, reserve: true },
    { id: "absent", actualOverall: 100, active: true, attendanceConfirmed: false },
    { id: "inactive", actualOverall: 100, active: false, attendanceConfirmed: true },
  ]), 70);
});

test("multiple administrators create one official observation without multiplying group weight", () => {
  assert.equal(aggregateOfficialObservation([60, 70, 80]), 70);
  assert.equal(aggregateOfficialObservation([]), null);
});

test("social aggregate stays private with 0, 1 and 2 evaluators and opens at 3", () => {
  for (const count of [0, 1, 2]) {
    const disclosure = socialRatingDisclosure(count);
    assert.equal(disclosure.state, "calibrating");
    assert.equal(disclosure.canShowAggregate, false);
    assert.equal(disclosure.label, "Calibración en curso");
    assert.equal(disclosure.remaining, 3 - count);
  }
  assert.equal(socialRatingDisclosure(3).state, "ready");
  assert.equal(socialRatingDisclosure(3).canShowAggregate, true);
});

test("external team calibration uses a stable prior, source weights, twelve months and B plus or minus 10", () => {
  const observations = [
    { id: "rival", observation: 100, occurredAt: "2026-07-01T00:00:00.000Z", source: "rival_admin" as const },
    { id: "guest", observation: 0, occurredAt: "2026-06-01T00:00:00.000Z", source: "guest" as const },
    { id: "old", observation: 100, occurredAt: "2025-01-01T00:00:00.000Z", source: "rival_admin" as const },
  ];
  const expected = (5 * 60 + 1 * 70 + 0.5 * 50) / 6.5;
  const direct = externallyCalibratedTeamLevel({ at: "2026-08-02T00:00:00.000Z", baseLevel: 60, observations });
  const reversed = externallyCalibratedTeamLevel({ at: "2026-08-02T00:00:00.000Z", baseLevel: 60, observations: [...observations].reverse() });
  assert.equal(direct.level, expected);
  assert.equal(reversed.level, expected);
  assert.equal(direct.evidenceCount, 2);
  assert.equal(externallyCalibratedTeamLevel({ at: "2026-08-02T00:00:00.000Z", baseLevel: 60, observations: [] }).level, 60);
  assert.ok(direct.level >= 0 && direct.level <= 100);
});

test("guest provisional level is an order-independent arithmetic mean with count and date", () => {
  const observations = [
    { id: "one", observation: 45, occurredAt: "2026-05-01T00:00:00.000Z" },
    { id: "two", observation: 75, occurredAt: "2026-07-01T00:00:00.000Z" },
  ];
  assert.deepEqual(guestProvisionalLevel(observations), {
    lastObservedAt: "2026-07-01T00:00:00.000Z",
    level: 60,
    observationCount: 2,
  });
  assert.deepEqual(guestProvisionalLevel([...observations].reverse()), guestProvisionalLevel(observations));
  assert.deepEqual(guestProvisionalLevel([]), { lastObservedAt: null, level: null, observationCount: 0 });
});

test("goalkeepers never fall through to an outfield overall formula", () => {
  const result = calculateRatingCardLayers({
    baseFacets: FACETS_60,
    baseReliability: 50,
    domain: "goalkeeper",
    evidence: [],
    primaryPosition: "striker",
  });
  assert.equal(result.baseOverall, null);
  assert.equal(result.calibratedOverall, null);
  assert.equal(result.currentOverall, null);
  assert.equal(goalkeeperRatingContract().questionnaireStatus, "pending");
});

test("reciprocal maximum ratings are informational and do not alter evidence", () => {
  const events: RatingHistoryEvent[] = [
    { ...evidence("1", "a", 100), targetId: "b" },
    { ...evidence("2", "b", 100), targetId: "a" },
  ];
  assert.equal(detectReciprocalMaximumRatings(events).length, 2);
  assert.equal(events[0].state, "active");
});

test("stable JSON is independent of object key order", () => {
  assert.equal(stableJson({ b: 2, a: { d: 4, c: 3 } }), stableJson({ a: { c: 3, d: 4 }, b: 2 }));
});

test("advanced assessment persistence uses exactly the shared TypeScript engine result", () => {
  const initialInput = assessmentInput();
  const answers = { "TEC-01": 5, "PAS-01": 4, "DEF-01": 2 } as const;
  const initial = calculateInitialRatings(initialInput);
  const expected = calculateAdvancedRatings({ initial, answers });
  const shared = calculateSharedAssessmentResult({ advancedAnswers: answers, initialInput, kind: "advanced" });

  assert.deepEqual(shared.advanced?.baseRatings, expected.baseRatings);
  assert.equal(shared.advanced?.baseOverall, expected.baseOverall);
  assert.equal(shared.advanced?.reliability, expected.reliability);
  assert.deepEqual(shared.advanced?.explanations, expected.explanations);
  assert.deepEqual(shared.advanced?.moduleSummaries, expected.moduleSummaries);
  assert.equal(shared.advanced?.contradictionCount, expected.contradictionCount);
  assert.deepEqual(shared.persisted.v2Facets, expected.baseRatings);
  assert.deepEqual(shared.persisted.v2CurrentModifiers, {
    pace: initial.profile.currentRatings.pace - initial.profile.baseRatings.pace,
    shooting: initial.profile.currentRatings.shooting - initial.profile.baseRatings.shooting,
    passing: initial.profile.currentRatings.passing - initial.profile.baseRatings.passing,
    dribbling: initial.profile.currentRatings.dribbling - initial.profile.baseRatings.dribbling,
    defending: initial.profile.currentRatings.defending - initial.profile.baseRatings.defending,
    physical: initial.profile.currentRatings.physical - initial.profile.baseRatings.physical,
  });
  assert.equal(shared.persisted.rating, expected.baseOverall / 10);
  assert.equal(shared.persisted.reliability, expected.reliability);
});
