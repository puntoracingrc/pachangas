import {
  ATTRIBUTE_KEYS,
  calculateOverall,
  type AttributeKey,
  type AttributeRatings,
  type PlayerPosition,
} from "./laboratorio-ficha-jugador/_engine/player-rating-engine";

export const RATING_SYSTEM_V2_ENGINE_VERSION = "pachangas-rating-v2";
export const RATING_SYSTEM_V2_REVIEW_MATCHES = 3;
export const SOCIAL_RATING_MIN_EVALUATORS = 3;
export const EXTERNAL_TEAM_BASE_PRIOR_WEIGHT = 5;

export type RatingComparison = "MUCHO_PEOR" | "PEOR" | "PARECIDO" | "MEJOR" | "MUCHO_MEJOR";
export type RatingEvidenceState = "active" | "superseded" | "void";
export type RatingDomain = "field" | "goalkeeper" | "goalkeeper_legacy";

export const RATING_COMPARISON_DELTAS: Record<RatingComparison, number> = {
  MUCHO_PEOR: -10,
  PEOR: -5,
  PARECIDO: 0,
  MEJOR: 5,
  MUCHO_MEJOR: 10,
};

export const RATING_COMPARISON_OPTIONS: Array<{ id: RatingComparison; label: string }> = [
  { id: "MUCHO_PEOR", label: "Mucho peor" },
  { id: "PEOR", label: "Peor" },
  { id: "PARECIDO", label: "Parecido" },
  { id: "MEJOR", label: "Mejor" },
  { id: "MUCHO_MEJOR", label: "Mucho mejor" },
];

export const OUTFIELD_FACET_LABELS: Record<AttributeKey, string> = {
  pace: "Ritmo",
  shooting: "Tiro",
  passing: "Pase",
  dribbling: "Regate",
  defending: "Defensa",
  physical: "Físico",
};

export const GOALKEEPER_FACET_KEYS = ["rushing", "saves", "distribution", "reflexes", "speed", "positioning"] as const;
export type GoalkeeperFacetKey = (typeof GOALKEEPER_FACET_KEYS)[number];
export type GoalkeeperFacets = Record<GoalkeeperFacetKey, number>;

export const GOALKEEPER_FACET_LABELS: Record<GoalkeeperFacetKey, string> = {
  rushing: "Salidas",
  saves: "Paradas",
  distribution: "Saque",
  reflexes: "Reflejos",
  speed: "Velocidad",
  positioning: "Posición",
};

export type IndividualRatingEvidence = {
  id: string;
  evaluatorId: string;
  targetId: string;
  groupId: string;
  createdAt: string;
  state: RatingEvidenceState;
  supersededAt?: string | null;
  voidedAt?: string | null;
  observations: AttributeRatings;
  evaluatorConfidence: number;
};

export type RatingCardLayers = {
  baseFacets: AttributeRatings;
  calibratedFacets: AttributeRatings;
  currentFacets: AttributeRatings;
  baseOverall: number | null;
  calibratedOverall: number | null;
  currentOverall: number | null;
  reliability: number;
  evaluatorCount: number;
  engineVersion: string;
};

export type StableGroupCandidate = {
  calibratedOverall: number;
  confirmedAppearancesLast12Months: number;
  id: string;
  lastConfirmedAppearanceAt?: string | null;
};

export type LineupParticipant = {
  actualOverall: number;
  active: boolean;
  attendanceConfirmed: boolean;
  id: string;
  reserve?: boolean;
};

export type RatingHistoryEvent = IndividualRatingEvidence & {
  sequence?: number;
};

export type SharedMatchCandidate = {
  cancelled?: boolean;
  deleted?: boolean;
  evaluator: { attendanceConfirmed: boolean; playing: boolean; reserve?: boolean } | null;
  finalized: boolean;
  finalizedAt: string;
  id: string;
  target: { attendanceConfirmed: boolean; playing: boolean; reserve?: boolean } | null;
};

export type ExternalTeamObservation = {
  id: string;
  observation: number;
  occurredAt: string;
  source: "guest" | "rival_admin";
};

export type GuestLevelObservation = {
  id: string;
  observation: number;
  occurredAt: string;
};

function clamp(value: number, min = 0, max = 100) {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

export function normalizeReliability(value: number) {
  return clamp(value, 0, 100);
}

export function normalizeFacets(facets: Partial<AttributeRatings>, fallback = 50): AttributeRatings {
  return {
    pace: clamp(facets.pace ?? fallback),
    shooting: clamp(facets.shooting ?? fallback),
    passing: clamp(facets.passing ?? fallback),
    dribbling: clamp(facets.dribbling ?? fallback),
    defending: clamp(facets.defending ?? fallback),
    physical: clamp(facets.physical ?? fallback),
  };
}

export function comparisonDelta(comparison: RatingComparison) {
  return RATING_COMPARISON_DELTAS[comparison];
}

export function comparisonObservation(referenceValue: number, comparison: RatingComparison) {
  return clamp(referenceValue + comparisonDelta(comparison));
}

export function buildRelativeObservations(
  evaluatorSnapshot: AttributeRatings,
  comparisons: Record<AttributeKey, RatingComparison>,
) {
  return ATTRIBUTE_KEYS.reduce((result, facet) => {
    result[facet] = comparisonObservation(evaluatorSnapshot[facet], comparisons[facet]);
    return result;
  }, {} as AttributeRatings);
}

export function baseEvidenceWeight(reliability: number) {
  return 2 + 3 * (normalizeReliability(reliability) / 100);
}

export function evaluatorEvidenceWeight(confidence: number) {
  return 0.5 + 0.5 * (normalizeReliability(confidence) / 100);
}

export function calibrateFacets(params: {
  baseFacets: AttributeRatings;
  baseReliability: number;
  evidence: Array<Pick<IndividualRatingEvidence, "evaluatorConfidence" | "observations">>;
}): AttributeRatings {
  const baseFacets = normalizeFacets(params.baseFacets);
  const priorWeight = baseEvidenceWeight(params.baseReliability);

  return ATTRIBUTE_KEYS.reduce((result, facet) => {
    let weightedTotal = priorWeight * baseFacets[facet];
    let totalWeight = priorWeight;

    for (const item of params.evidence) {
      const weight = evaluatorEvidenceWeight(item.evaluatorConfidence);
      const adjustedObservation = clamp(item.observations[facet], baseFacets[facet] - 15, baseFacets[facet] + 15);
      weightedTotal += weight * adjustedObservation;
      totalWeight += weight;
    }

    result[facet] = clamp(weightedTotal / totalWeight);
    return result;
  }, {} as AttributeRatings);
}

export function applyCurrentModifiers(calibratedFacets: AttributeRatings, modifiers: Partial<AttributeRatings>): AttributeRatings {
  return ATTRIBUTE_KEYS.reduce((result, facet) => {
    result[facet] = clamp(calibratedFacets[facet] + (modifiers[facet] ?? 0));
    return result;
  }, {} as AttributeRatings);
}

export function calculateLayerOverall(
  facets: AttributeRatings,
  primaryPosition: PlayerPosition,
  domain: RatingDomain = "field",
) {
  if (domain !== "field") return null;
  return clamp(calculateOverall(facets, primaryPosition));
}

export function calculateRatingCardLayers(params: {
  baseFacets: AttributeRatings;
  baseReliability: number;
  currentModifiers?: Partial<AttributeRatings>;
  domain?: RatingDomain;
  evidence: Array<Pick<IndividualRatingEvidence, "evaluatorConfidence" | "observations">>;
  primaryPosition: PlayerPosition;
}): RatingCardLayers {
  const baseFacets = normalizeFacets(params.baseFacets);
  const calibratedFacets = calibrateFacets({
    baseFacets,
    baseReliability: params.baseReliability,
    evidence: params.evidence,
  });
  const currentFacets = applyCurrentModifiers(calibratedFacets, params.currentModifiers ?? {});
  const domain = params.domain ?? "field";

  return {
    baseFacets,
    calibratedFacets,
    currentFacets,
    baseOverall: calculateLayerOverall(baseFacets, params.primaryPosition, domain),
    calibratedOverall: calculateLayerOverall(calibratedFacets, params.primaryPosition, domain),
    currentOverall: calculateLayerOverall(currentFacets, params.primaryPosition, domain),
    reliability: normalizeReliability(params.baseReliability),
    evaluatorCount: params.evidence.length,
    engineVersion: RATING_SYSTEM_V2_ENGINE_VERSION,
  };
}

export function activeEvidenceByEvaluator(events: RatingHistoryEvent[], at = new Date().toISOString()) {
  const cutoff = Date.parse(at);
  const byEvaluator = new Map<string, RatingHistoryEvent>();

  for (const event of events) {
    const createdAt = Date.parse(event.createdAt);
    const supersededAt = event.supersededAt ? Date.parse(event.supersededAt) : Number.POSITIVE_INFINITY;
    const voidedAt = event.voidedAt ? Date.parse(event.voidedAt) : Number.POSITIVE_INFINITY;
    if (!Number.isFinite(createdAt) || createdAt > cutoff || supersededAt <= cutoff || voidedAt <= cutoff) continue;

    const current = byEvaluator.get(event.evaluatorId);
    const currentTime = current ? Date.parse(current.createdAt) : Number.NEGATIVE_INFINITY;
    if (!current || createdAt > currentTime || (createdAt === currentTime && event.id.localeCompare(current.id) > 0)) {
      byEvaluator.set(event.evaluatorId, event);
    }
  }

  return [...byEvaluator.values()].sort((a, b) => a.evaluatorId.localeCompare(b.evaluatorId));
}

export function countValidSharedMatches(matches: SharedMatchCandidate[], sinceAt?: string | null) {
  const since = sinceAt ? Date.parse(sinceAt) : Number.NEGATIVE_INFINITY;
  const validIds = new Set<string>();
  for (const match of matches) {
    const finalizedAt = Date.parse(match.finalizedAt);
    if (!match.finalized || match.cancelled || match.deleted || !Number.isFinite(finalizedAt) || finalizedAt <= since) continue;
    if (!match.evaluator?.attendanceConfirmed || !match.target?.attendanceConfirmed) continue;
    if (!match.evaluator.playing || !match.target.playing || match.evaluator.reserve || match.target.reserve) continue;
    validIds.add(match.id);
  }
  return validIds.size;
}

export function directionalRatingEligibility(params: {
  activeRatingAt?: string | null;
  matches: SharedMatchCandidate[];
}) {
  if (!params.activeRatingAt) {
    return { canRate: true, firstRating: true, requiredMatches: 0, sharedMatches: 0 };
  }
  const sharedMatches = countValidSharedMatches(params.matches, params.activeRatingAt);
  return {
    canRate: sharedMatches >= RATING_SYSTEM_V2_REVIEW_MATCHES,
    firstRating: false,
    requiredMatches: RATING_SYSTEM_V2_REVIEW_MATCHES,
    sharedMatches,
  };
}

export function reconstructCardFromHistory(params: {
  at?: string;
  baseFacets: AttributeRatings;
  baseReliability: number;
  currentModifiers?: Partial<AttributeRatings>;
  domain?: RatingDomain;
  events: RatingHistoryEvent[];
  primaryPosition: PlayerPosition;
}) {
  const active = activeEvidenceByEvaluator(params.events, params.at);
  return calculateRatingCardLayers({
    baseFacets: params.baseFacets,
    baseReliability: params.baseReliability,
    currentModifiers: params.currentModifiers,
    domain: params.domain,
    evidence: active,
    primaryPosition: params.primaryPosition,
  });
}

export function selectStableGroupPlayers(candidates: StableGroupCandidate[], limit = 11) {
  return [...candidates]
    .sort((left, right) => {
      const appearances = right.confirmedAppearancesLast12Months - left.confirmedAppearancesLast12Months;
      if (appearances !== 0) return appearances;
      const recent = Date.parse(right.lastConfirmedAppearanceAt ?? "") - Date.parse(left.lastConfirmedAppearanceAt ?? "");
      if (Number.isFinite(recent) && recent !== 0) return recent;
      return left.id.localeCompare(right.id);
    })
    .slice(0, Math.max(0, limit));
}

export function stableGroupLevel(candidates: StableGroupCandidate[]) {
  const selected = selectStableGroupPlayers(candidates, 11);
  if (selected.length === 0) return null;
  return selected.reduce((total, candidate) => total + clamp(candidate.calibratedOverall), 0) / selected.length;
}

export function lineupLevel(participants: LineupParticipant[]) {
  const eligible = participants.filter((participant) => participant.active && participant.attendanceConfirmed && !participant.reserve);
  if (eligible.length === 0) return null;
  return eligible.reduce((total, participant) => total + clamp(participant.actualOverall), 0) / eligible.length;
}

export function aggregateOfficialObservation(observations: number[]) {
  if (observations.length === 0) return null;
  return clamp(observations.reduce((total, observation) => total + clamp(observation), 0) / observations.length);
}

export function socialRatingDisclosure(evaluatorCount: number) {
  const count = Math.max(0, Math.trunc(Number.isFinite(evaluatorCount) ? evaluatorCount : 0));
  const ready = count >= SOCIAL_RATING_MIN_EVALUATORS;
  return {
    canShowAggregate: ready,
    evaluatorCount: count,
    label: ready ? "Valoración social disponible" : "Calibración en curso",
    remaining: Math.max(0, SOCIAL_RATING_MIN_EVALUATORS - count),
    requiredEvaluators: SOCIAL_RATING_MIN_EVALUATORS,
    state: ready ? "ready" as const : "calibrating" as const,
  };
}

export function externallyCalibratedTeamLevel(params: {
  at: string;
  baseLevel: number;
  observations: ExternalTeamObservation[];
}) {
  const baseLevel = clamp(params.baseLevel);
  const at = Date.parse(params.at);
  const earliest = Number.isFinite(at) ? at - (365 * 24 * 60 * 60 * 1000) : Number.NEGATIVE_INFINITY;
  const eligible = params.observations.filter((item) => {
    const occurredAt = Date.parse(item.occurredAt);
    return Number.isFinite(occurredAt) && occurredAt >= earliest && occurredAt <= at;
  });
  let weightedTotal = EXTERNAL_TEAM_BASE_PRIOR_WEIGHT * baseLevel;
  let totalWeight = EXTERNAL_TEAM_BASE_PRIOR_WEIGHT;
  for (const item of eligible) {
    const weight = item.source === "guest" ? 0.5 : 1;
    weightedTotal += weight * clamp(item.observation, baseLevel - 10, baseLevel + 10);
    totalWeight += weight;
  }
  return {
    baseLevel,
    basePriorWeight: EXTERNAL_TEAM_BASE_PRIOR_WEIGHT,
    engineVersion: RATING_SYSTEM_V2_ENGINE_VERSION,
    evidenceCount: eligible.length,
    level: clamp(weightedTotal / totalWeight),
    totalEvidenceWeight: totalWeight - EXTERNAL_TEAM_BASE_PRIOR_WEIGHT,
  };
}

export function guestProvisionalLevel(observations: GuestLevelObservation[]) {
  const valid = observations.filter((item) => Number.isFinite(item.observation) && Number.isFinite(Date.parse(item.occurredAt)));
  if (valid.length === 0) return { lastObservedAt: null, level: null, observationCount: 0 };
  return {
    lastObservedAt: valid.reduce((latest, item) => item.occurredAt > latest ? item.occurredAt : latest, valid[0].occurredAt),
    level: valid.reduce((total, item) => total + clamp(item.observation), 0) / valid.length,
    observationCount: valid.length,
  };
}

export function detectReciprocalMaximumRatings(events: RatingHistoryEvent[]) {
  const active = activeEvidenceByEvaluator(events);
  const maximumByPair = new Set(
    active
      .filter((event) => ATTRIBUTE_KEYS.every((facet) => event.observations[facet] >= 99.999))
      .map((event) => `${event.evaluatorId}:${event.targetId}`),
  );

  return active.filter((event) =>
    maximumByPair.has(`${event.evaluatorId}:${event.targetId}`) &&
    maximumByPair.has(`${event.targetId}:${event.evaluatorId}`),
  );
}

export function goalkeeperRatingContract() {
  return {
    domain: "goalkeeper" as const,
    engineVersion: null,
    facets: GOALKEEPER_FACET_KEYS,
    questionnaireStatus: "pending" as const,
    overallStatus: "pending" as const,
  };
}

export function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableJson(item)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value);
}
