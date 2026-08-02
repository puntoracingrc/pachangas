import {
  ADVANCED_TEST_VERSION,
  ATTRIBUTE_KEYS,
  FOOTBALL_RATING_ENGINE_VERSION,
  INITIAL_TEST_VERSION,
  calculateAdvancedRatings,
  calculateInitialRatings,
  type AnswerValue,
  type AttributeRatings,
  type InitialRatingInput,
  type PlayerPosition,
} from "./laboratorio-ficha-jugador/_engine/player-rating-engine";

export type SharedAssessmentKind = "initial" | "advanced";

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
