import {
  ADVANCED_TEST_VERSION,
  ATTRIBUTE_KEYS,
  EXPERIENCE_LEVELS,
  FOOTBALL_RATING_ENGINE_VERSION,
  FREQUENCIES,
  INITIAL_TEST_VERSION,
  INITIAL_TECHNICAL_QUESTIONS,
  MODE_LABELS,
  POSITION_LABELS,
  calculateAdvancedRatings,
  calculateApplicableAdvancedQuestions,
  calculateInitialRatings,
  type AnswerValue,
  type AttributeRatings,
  type ExperienceLevelId,
  type FootballMode,
  type FrequencyId,
  type InitialRatingInput,
  type PlayerPosition,
} from "./laboratorio-ficha-jugador/_engine/player-rating-engine";

export type SharedAssessmentKind = "initial" | "advanced";

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function requiredEnum<T extends string>(value: unknown, options: Record<T, unknown>, label: string): T {
  if (typeof value !== "string" || !Object.prototype.hasOwnProperty.call(options, value)) {
    throw new Error(`Invalid ${label}`);
  }
  return value as T;
}

function optionalFiniteNumber(value: unknown, minimum: number, maximum: number, label: string) {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`Invalid ${label}`);
  }
  return value;
}

function requiredAnswer(value: unknown, label: string): Exclude<AnswerValue, null> {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error(`Invalid ${label}`);
  }
  return value as Exclude<AnswerValue, null>;
}

export function canonicalInitialAssessmentInput(value: unknown): InitialRatingInput {
  if (!isRecord(value)) throw new Error("Invalid initial assessment input");

  const primaryPosition = requiredEnum<PlayerPosition>(value.primaryPosition, POSITION_LABELS, "primary position");
  if (!Array.isArray(value.secondaryPositions) || value.secondaryPositions.length > Object.keys(POSITION_LABELS).length) {
    throw new Error("Invalid secondary positions");
  }
  const secondaryPositions = [...new Set(value.secondaryPositions.map((position) =>
    requiredEnum<PlayerPosition>(position, POSITION_LABELS, "secondary position"),
  ))];

  if (!Array.isArray(value.modeShares) || value.modeShares.length < 1 || value.modeShares.length > Object.keys(MODE_LABELS).length) {
    throw new Error("Invalid mode shares");
  }
  const seenModes = new Set<FootballMode>();
  const modeShares = value.modeShares.map((entry) => {
    if (!isRecord(entry)) throw new Error("Invalid mode share");
    const mode = requiredEnum<FootballMode>(entry.mode, MODE_LABELS, "football mode");
    if (seenModes.has(mode)) throw new Error("Duplicate football mode");
    seenModes.add(mode);
    const percentage = optionalFiniteNumber(entry.percentage, 0, 100, "mode percentage");
    if (percentage === undefined) throw new Error("Invalid mode percentage");
    return { mode, percentage };
  });
  const modeTotal = modeShares.reduce((total, share) => total + share.percentage, 0);
  if (Math.round(modeTotal * 100) / 100 !== 100) throw new Error("Mode percentages must sum 100");

  if (!isRecord(value.answers)) throw new Error("Invalid initial answers");
  const answerValues = value.answers;
  const answers = Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [
    question.id,
    requiredAnswer(answerValues[question.id], `answer ${question.id}`),
  ])) as InitialRatingInput["answers"];
  const yearsSinceLevel = optionalFiniteNumber(value.yearsSinceLevel, 0, 80, "years since level");
  if (yearsSinceLevel === undefined || !Number.isInteger(yearsSinceLevel)) throw new Error("Invalid years since level");
  const age = optionalFiniteNumber(value.age, 0, 120, "age");
  const heightCm = optionalFiniteNumber(value.heightCm, 50, 260, "height");
  const weightKg = optionalFiniteNumber(value.weightKg, 15, 300, "weight");

  return {
    ...(age === undefined ? {} : { age }),
    ...(heightCm === undefined ? {} : { heightCm }),
    ...(weightKg === undefined ? {} : { weightKg }),
    answers,
    experienceLevel: requiredEnum<ExperienceLevelId>(value.experienceLevel, EXPERIENCE_LEVELS, "experience level"),
    frequency: requiredEnum<FrequencyId>(value.frequency, FREQUENCIES, "frequency"),
    modeShares,
    primaryPosition,
    secondaryPositions,
    yearsSinceLevel,
  };
}

export function canonicalAdvancedAssessmentInput(value: unknown, initialInput: InitialRatingInput) {
  if (!isRecord(value) || !isRecord(value.answers)) throw new Error("Invalid advanced assessment input");
  const answerValues = value.answers;
  const initial = calculateInitialRatings(initialInput);
  const questions = calculateApplicableAdvancedQuestions(initial);
  const answers = Object.fromEntries(questions.map((question) => [
    question.id,
    requiredAnswer(answerValues[question.id], `answer ${question.id}`),
  ])) as Record<string, Exclude<AnswerValue, null>>;
  return { answers };
}

const appPosition: Record<PlayerPosition, string> = {
  centre_back: "Defensa central",
  full_back: "Lateral derecho",
  defensive_midfielder: "Pivote defensivo",
  central_midfielder: "Mediocentro / pivote",
  attacking_midfielder: "Mediapunta",
  winger: "Extremo derecho",
  striker: "Delantero / punta",
};

function legacyFacets(ratings: AttributeRatings) {
  return {
    ritmo: ratings.pace / 10,
    tiro: ratings.shooting / 10,
    pase: ratings.passing / 10,
    regate: ratings.dribbling / 10,
    defensa: ratings.defending / 10,
    fisico: ratings.physical / 10,
  };
}

export function calculateSharedAssessmentResult(params: {
  advancedAnswers?: Record<string, AnswerValue>;
  initialInput: InitialRatingInput;
  kind: SharedAssessmentKind;
}) {
  const initial = calculateInitialRatings(params.initialInput);
  const advanced = params.kind === "advanced"
    ? calculateAdvancedRatings({ initial, answers: params.advancedAnswers ?? {} })
    : undefined;
  const ratings = advanced?.baseRatings ?? initial.profile.baseRatings;
  const overall = advanced?.baseOverall ?? initial.profile.baseOverall;
  const reliability = advanced?.reliability ?? initial.profile.reliability;
  const currentModifiers = ATTRIBUTE_KEYS.reduce((result, attribute) => {
    result[attribute] = initial.profile.currentRatings[attribute] - initial.profile.baseRatings[attribute];
    return result;
  }, {} as AttributeRatings);

  return {
    advanced,
    initial,
    persisted: {
      calculatedAt: initial.profile.calculatedAt,
      engineResult: params.kind === "initial" ? initial : advanced,
      engineVersion: FOOTBALL_RATING_ENGINE_VERSION,
      facets: legacyFacets(ratings),
      position: appPosition[initial.profile.primaryPosition],
      primaryPosition: initial.profile.primaryPosition,
      questionnaireVersion: params.kind === "initial" ? INITIAL_TEST_VERSION : ADVANCED_TEST_VERSION,
      rating: overall / 10,
      reliability,
      v2Facets: ratings,
      v2CurrentModifiers: currentModifiers,
    },
  };
}
