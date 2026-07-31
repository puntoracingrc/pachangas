import assert from "node:assert/strict";
import test from "node:test";
import {
  ATTRIBUTE_KEYS,
  type AnswerValue,
  type CurrentLimitationInput,
  type InitialRatingInput,
  INITIAL_TECHNICAL_QUESTIONS,
  SELF_ASSESSMENT_ATTRIBUTE_MAX,
  SELF_ASSESSMENT_RELIABILITY_MAX,
  calculateAdvancedRatings,
  calculateCurrentRatings,
  calculateInitialRatings,
  calculateOverall,
  overallWeightsAreValid,
  responseToScore,
} from "../app/laboratorio-ficha-jugador/_engine/player-rating-engine";

const baseAnswers = Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, 3])) as InitialRatingInput["answers"];

function makeInitial(overrides: Partial<InitialRatingInput> = {}): InitialRatingInput {
  return {
    age: 28,
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
    answers: baseAnswers,
    calculatedAt: "2026-07-31T00:00:00.000Z",
    ...overrides,
  };
}

function values(record: Record<string, number>) {
  return ATTRIBUTE_KEYS.map((attribute) => record[attribute]);
}

test("keeps rating and reliability self-assessment limits", () => {
  const answers = Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, 5])) as InitialRatingInput["answers"];
  const initial = calculateInitialRatings(makeInitial({ experienceLevel: "professional", frequency: "four_plus_weekly", answers }));
  const advanced = calculateAdvancedRatings({
    initial,
    answers: Object.fromEntries(["TEC-01", "PAS-01", "TIR-01", "DEF-01", "RIT-01", "FIS-01", "INT-01"].map((id) => [id, 5] as const)),
  });

  assert.ok(values(advanced.baseRatings).every((value) => value >= 0 && value <= SELF_ASSESSMENT_ATTRIBUTE_MAX));
  assert.ok(advanced.reliability <= SELF_ASSESSMENT_RELIABILITY_MAX);
});

test("is deterministic for the same input", () => {
  const a = calculateInitialRatings(makeInitial());
  const b = calculateInitialRatings(makeInitial());
  assert.deepEqual(a.profile.baseRatings, b.profile.baseRatings);
  assert.equal(a.profile.baseOverall, b.profile.baseOverall);
  assert.equal(a.profile.reliability, b.profile.reliability);
});

test("does not convert unknown answers into zero", () => {
  assert.equal(responseToScore(null), null);
  const answers = { ...baseAnswers, controlUnderPressure: null as AnswerValue, ballCarrying: null as AnswerValue };
  const result = calculateInitialRatings(makeInitial({ answers }));
  assert.ok(result.technicalComposites.C > 0);
  assert.ok(result.profile.baseRatings.dribbling > 0);
});

test("modality changes confidence but not direct initial attributes", () => {
  const futsal = calculateInitialRatings(makeInitial({ modeShares: [{ mode: "futsal_5", percentage: 100 }, { mode: "football_7", percentage: 0 }, { mode: "football_11", percentage: 0 }] }));
  const eleven = calculateInitialRatings(makeInitial({ modeShares: [{ mode: "futsal_5", percentage: 0 }, { mode: "football_7", percentage: 0 }, { mode: "football_11", percentage: 100 }] }));

  assert.deepEqual(futsal.profile.baseRatings, eleven.profile.baseRatings);
  assert.notDeepEqual(futsal.modeConfidence, eleven.modeConfidence);
});

test("age height and weight do not modify football attributes", () => {
  const young = calculateInitialRatings(makeInitial({ age: 25, heightCm: 165, weightKg: 60 }));
  const veteran = calculateInitialRatings(makeInitial({ age: 45, heightCm: 195, weightKg: 100 }));
  assert.deepEqual(young.profile.baseRatings, veteran.profile.baseRatings);
});

test("old high experience decays toward neutral experience", () => {
  const current = calculateInitialRatings(makeInitial({ experienceLevel: "professional", yearsSinceLevel: 0 }));
  const old = calculateInitialRatings(makeInitial({ experienceLevel: "professional", yearsSinceLevel: 15 }));
  assert.ok(old.experienceEffective < current.experienceEffective);
  assert.ok(old.experienceEffective > 50);
});

test("a recovered injury changes nothing", () => {
  const initial = calculateInitialRatings(makeInitial());
  const current = calculateCurrentRatings({
    baseRatings: initial.profile.baseRatings,
    primaryPosition: initial.profile.primaryPosition,
    frequencyAdjustment: 0,
    lifestyle: { sleep: null, training: null, recovery: null, habits: null },
    limitation: { consent: true, recovered: true, severity: 1, frequency: 1, actions: ["sprinting"] },
  });
  assert.deepEqual(current.currentRatings, initial.profile.baseRatings);
});

test("current sprinting limitation affects current ratings, not base ratings", () => {
  const initial = calculateInitialRatings(makeInitial());
  const limitation: CurrentLimitationInput = { consent: true, recovered: false, severity: 1, frequency: 1, actions: ["sprinting"] };
  const current = calculateCurrentRatings({
    baseRatings: initial.profile.baseRatings,
    primaryPosition: initial.profile.primaryPosition,
    frequencyAdjustment: 0,
    lifestyle: { sleep: null, training: null, recovery: null, habits: null },
    limitation,
  });

  assert.deepEqual(initial.profile.baseRatings, calculateInitialRatings(makeInitial()).profile.baseRatings);
  assert.ok(current.currentRatings.pace < initial.profile.baseRatings.pace);
  assert.ok(current.currentRatings.physical < initial.profile.baseRatings.physical);
  assert.equal(current.currentRatings.passing, initial.profile.baseRatings.passing);
  assert.equal(current.currentRatings.shooting, initial.profile.baseRatings.shooting);
});

test("lifestyle replaces provisional frequency adjustment", () => {
  const initial = calculateInitialRatings(makeInitial({ frequency: "four_plus_weekly" }));
  const withLifestyle = calculateCurrentRatings({
    baseRatings: initial.profile.baseRatings,
    primaryPosition: initial.profile.primaryPosition,
    frequencyAdjustment: initial.frequencyAdjustment,
    lifestyle: { sleep: 1, training: 1, recovery: 1, habits: 1 },
    limitation: { consent: false, recovered: false, severity: 0, frequency: 0.25, actions: [] },
  });

  assert.equal(withLifestyle.usedLifestyleModule, true);
  assert.ok(withLifestyle.currentRatings.pace < initial.profile.baseRatings.pace);
  assert.ok(withLifestyle.currentRatings.physical < initial.profile.baseRatings.physical);
});

test("advanced answers can raise and lower without automatic completion points", () => {
  const initial = calculateInitialRatings(makeInitial());
  const high = calculateAdvancedRatings({ initial, answers: { "TEC-01": 5, "TEC-02": 5, "TEC-03": 5, "TEC-04": 5, "TEC-05": 5, "TEC-06": 5 } });
  const low = calculateAdvancedRatings({ initial, answers: { "TEC-01": 1, "TEC-02": 1, "TEC-03": 1, "TEC-04": 1, "TEC-05": 1, "TEC-06": 1 } });
  const unknown = calculateAdvancedRatings({ initial, answers: { "TEC-01": null, "TEC-02": null, "TEC-03": null, "TEC-04": null, "TEC-05": null, "TEC-06": null } });

  assert.ok(high.baseRatings.dribbling > initial.profile.baseRatings.dribbling);
  assert.ok(low.baseRatings.dribbling < initial.profile.baseRatings.dribbling);
  assert.equal(unknown.baseRatings.dribbling, initial.profile.baseRatings.dribbling);
});

test("one advanced question cannot create an extreme change and full coverage is capped", () => {
  const initial = calculateInitialRatings(makeInitial());
  const oneQuestion = calculateAdvancedRatings({ initial, answers: { "RIT-01": 5 } });
  const allHigh = calculateAdvancedRatings({
    initial,
    answers: Object.fromEntries(["RIT-01", "RIT-02", "RIT-03", "RIT-04", "FIS-01", "FIS-02", "FIS-03"].map((id) => [id, 5] as const)),
  });

  assert.ok(oneQuestion.baseRatings.pace - initial.profile.baseRatings.pace <= 8);
  assert.ok(allHigh.baseRatings.pace - initial.profile.baseRatings.pace <= 18.00001);
  assert.ok(allHigh.baseRatings.pace <= SELF_ASSESSMENT_ATTRIBUTE_MAX);
});

test("contradictions reduce evidence weight and reliability gain, not direct arbitrary points", () => {
  const initial = calculateInitialRatings(makeInitial());
  const coherent = calculateAdvancedRatings({ initial, answers: { "TEC-01": 5, "PAS-01": 5 } });
  const contradictory = calculateAdvancedRatings({ initial, answers: { "TEC-01": 5, "PAS-01": 1 } });

  assert.ok(contradictory.contradictionCount > 0);
  assert.ok(contradictory.reliability <= coherent.reliability);
  assert.ok(contradictory.explanations.some((explanation) => explanation.evidence.some((item) => item.consistencyMultiplier < 1)));
});

test("overall formulas are valid and position sensitive", () => {
  assert.equal(overallWeightsAreValid(), true);
  const ratings = { pace: 80, shooting: 45, passing: 70, dribbling: 65, defending: 82, physical: 78 };
  assert.notEqual(calculateOverall(ratings, "centre_back"), calculateOverall(ratings, "striker"));
});
