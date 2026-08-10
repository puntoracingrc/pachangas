export const TERRITORY_READINESS_STATES = [
  "ranking_inactive",
  "ranking_active",
  "trophy_not_ready",
  "trophy_ready",
] as const;

export type TerritoryReadinessState = typeof TERRITORY_READINESS_STATES[number];

export function isTerritoryReadinessState(value: string): value is TerritoryReadinessState {
  return (TERRITORY_READINESS_STATES as readonly string[]).includes(value);
}

export const TERRITORY_READINESS_REASONS = [
  "insufficient_active_teams",
  "insufficient_ranking_population",
  "insufficient_award_candidates",
  "insufficient_independent_competition",
  "insufficient_valid_challenges",
  "insufficient_history",
  "ready",
] as const;

export type TerritoryReadinessReason = typeof TERRITORY_READINESS_REASONS[number];

export type TerritoryReadinessSignals = {
  activePlayers: number;
  activeTeams: number;
  awardCandidatePlayers: number;
  independentOpponentEdges: number;
  independentTeamCoverage: number;
  logicalOpponentEdges: number;
  medianChallenges: number;
  medianCompetitiveConfidence: number;
  medianLogicalOpponents: number;
  rankingEligiblePlayers: number;
  validChallenges: number;
  observedHistoryWeeks: number;
};

export type TerritoryReadinessPolicy = {
  award: {
    minimumActiveTeams: number;
    minimumAwardCandidates: number;
    minimumHistoryWeeks: number;
    minimumIndependentOpponentEdges: number;
    minimumIndependentTeamCoverage: number;
    minimumRankingPopulation: number;
    minimumValidChallenges: number;
  };
  hysteresis: {
    demotionWindows: number;
    promotionWindows: Record<Exclude<TerritoryReadinessState, "ranking_inactive">, number>;
  };
  ranking: {
    minimumActiveTeams: number;
    minimumHistoryWeeks: number;
    minimumIndependentOpponentEdges: number;
    minimumRankingPopulation: number;
    minimumValidChallenges: number;
  };
};

export const PROVINCIAL_READINESS_POLICY: TerritoryReadinessPolicy = {
  award: {
    minimumActiveTeams: 11,
    minimumAwardCandidates: 10,
    minimumHistoryWeeks: 20,
    minimumIndependentOpponentEdges: 20,
    minimumIndependentTeamCoverage: 0.7,
    minimumRankingPopulation: 10,
    minimumValidChallenges: 250,
  },
  hysteresis: {
    demotionWindows: 3,
    promotionWindows: {
      ranking_active: 2,
      trophy_not_ready: 2,
      trophy_ready: 3,
    },
  },
  ranking: {
    minimumActiveTeams: 4,
    minimumHistoryWeeks: 4,
    minimumIndependentOpponentEdges: 4,
    minimumRankingPopulation: 5,
    minimumValidChallenges: 75,
  },
};

export type TerritoryReadinessSnapshot = {
  calculatedAt: string;
  observedReasons: TerritoryReadinessReason[];
  observedState: TerritoryReadinessState;
  policyVersion: "territory-award-readiness-v1";
  readinessState: TerritoryReadinessState;
  revision: number;
  season: string;
  signals: TerritoryReadinessSignals;
  stability: {
    direction: "demotion_pending" | "promotion_pending" | "stable";
    observedWindows: number;
    requiredWindows: number;
  };
  territory: string;
};

export type ProvincialFeatureFlags = {
  provincialAwardsEnabled: boolean;
  provincialRankingsEnabled: boolean;
};

export const PROVINCIAL_FEATURE_FLAG_KEYS = {
  awards: "provincial_awards_enabled",
  rankings: "provincial_rankings_enabled",
} as const;

export const PROVINCIAL_PILOT_FLAGS: ProvincialFeatureFlags = {
  provincialAwardsEnabled: false,
  provincialRankingsEnabled: true,
};

export function resolveProvincialFeatureFlags(source: Record<string, string | undefined>) {
  const enabled = (value: string | undefined, fallback: boolean) => value === undefined
    ? fallback
    : value.trim().toLowerCase() === "true";
  return {
    provincialAwardsEnabled: enabled(source[PROVINCIAL_FEATURE_FLAG_KEYS.awards], PROVINCIAL_PILOT_FLAGS.provincialAwardsEnabled),
    provincialRankingsEnabled: enabled(source[PROVINCIAL_FEATURE_FLAG_KEYS.rankings], PROVINCIAL_PILOT_FLAGS.provincialRankingsEnabled),
  } satisfies ProvincialFeatureFlags;
}

export const RANKING_SCOPE_RELEASE = {
  autonomousCommunity: "lab_only",
  national: "lab_only",
  province: "pilot_ready",
} as const;

const stateLevel = new Map<TerritoryReadinessState, number>(
  TERRITORY_READINESS_STATES.map((state, index) => [state, index]),
);

function level(state: TerritoryReadinessState) {
  return stateLevel.get(state)!;
}

function assertSignals(signals: TerritoryReadinessSignals) {
  for (const [name, value] of Object.entries(signals)) {
    if (!Number.isFinite(value) || value < 0) throw new Error(`INVALID_TERRITORY_SIGNAL:${name}`);
  }
  if (signals.independentTeamCoverage > 1) throw new Error("INVALID_TERRITORY_SIGNAL:independentTeamCoverage");
}

function rankingReasons(signals: TerritoryReadinessSignals, policy: TerritoryReadinessPolicy) {
  const reasons: TerritoryReadinessReason[] = [];
  if (signals.activeTeams < policy.ranking.minimumActiveTeams) reasons.push("insufficient_active_teams");
  if (signals.rankingEligiblePlayers < policy.ranking.minimumRankingPopulation) reasons.push("insufficient_ranking_population");
  if (signals.validChallenges < policy.ranking.minimumValidChallenges) reasons.push("insufficient_valid_challenges");
  if (signals.independentOpponentEdges < policy.ranking.minimumIndependentOpponentEdges) reasons.push("insufficient_independent_competition");
  if (signals.observedHistoryWeeks < policy.ranking.minimumHistoryWeeks) reasons.push("insufficient_history");
  return reasons;
}

function awardReasons(signals: TerritoryReadinessSignals, policy: TerritoryReadinessPolicy) {
  const reasons: TerritoryReadinessReason[] = [];
  if (signals.activeTeams < policy.award.minimumActiveTeams) reasons.push("insufficient_active_teams");
  if (signals.rankingEligiblePlayers < policy.award.minimumRankingPopulation) reasons.push("insufficient_ranking_population");
  if (signals.awardCandidatePlayers < policy.award.minimumAwardCandidates) reasons.push("insufficient_award_candidates");
  if (
    signals.independentOpponentEdges < policy.award.minimumIndependentOpponentEdges
    || signals.independentTeamCoverage < policy.award.minimumIndependentTeamCoverage
  ) reasons.push("insufficient_independent_competition");
  if (signals.validChallenges < policy.award.minimumValidChallenges) reasons.push("insufficient_valid_challenges");
  if (signals.observedHistoryWeeks < policy.award.minimumHistoryWeeks) reasons.push("insufficient_history");
  return reasons;
}

export function observeTerritoryReadiness(
  signals: TerritoryReadinessSignals,
  policy: TerritoryReadinessPolicy = PROVINCIAL_READINESS_POLICY,
) {
  assertSignals(signals);
  const inactiveReasons = rankingReasons(signals, policy);
  if (inactiveReasons.length > 0) {
    return { reasons: inactiveReasons, state: "ranking_inactive" as const };
  }
  const notReadyReasons = awardReasons(signals, policy);
  if (signals.rankingEligiblePlayers < policy.award.minimumRankingPopulation) {
    return { reasons: notReadyReasons, state: "ranking_active" as const };
  }
  if (notReadyReasons.length > 0) {
    return { reasons: notReadyReasons, state: "trophy_not_ready" as const };
  }
  return { reasons: ["ready" as const], state: "trophy_ready" as const };
}

function consecutiveObservedWindows(
  history: TerritoryReadinessSnapshot[],
  observedState: TerritoryReadinessState,
  direction: "down" | "up",
) {
  const target = level(observedState);
  let count = 1;
  for (let index = history.length - 1; index >= 0; index -= 1) {
    const previous = level(history[index]!.observedState);
    const qualifies = direction === "up" ? previous >= target : previous <= target;
    if (!qualifies) break;
    count += 1;
  }
  return count;
}

export function createTerritoryReadinessSnapshot(options: {
  calculatedAt: string;
  history?: TerritoryReadinessSnapshot[];
  policy?: TerritoryReadinessPolicy;
  season: string;
  signals: TerritoryReadinessSignals;
  territory: string;
}): TerritoryReadinessSnapshot {
  const policy = options.policy ?? PROVINCIAL_READINESS_POLICY;
  const history = options.history ?? [];
  const observed = observeTerritoryReadiness(options.signals, policy);
  const latest = history.at(-1);
  let readinessState = latest?.readinessState ?? observed.state;
  let direction: TerritoryReadinessSnapshot["stability"]["direction"] = "stable";
  let observedWindows = 1;
  let requiredWindows = 1;

  if (latest && observed.state !== latest.readinessState) {
    const promotion = level(observed.state) > level(latest.readinessState);
    direction = promotion ? "promotion_pending" : "demotion_pending";
    observedWindows = consecutiveObservedWindows(history, observed.state, promotion ? "up" : "down");
    requiredWindows = promotion
      ? policy.hysteresis.promotionWindows[observed.state as Exclude<TerritoryReadinessState, "ranking_inactive">]
      : policy.hysteresis.demotionWindows;
    if (observedWindows >= requiredWindows) {
      readinessState = observed.state;
      direction = "stable";
    }
  }

  return {
    calculatedAt: options.calculatedAt,
    observedReasons: observed.reasons,
    observedState: observed.state,
    policyVersion: "territory-award-readiness-v1",
    readinessState,
    revision: (latest?.revision ?? 0) + 1,
    season: options.season,
    signals: { ...options.signals },
    stability: { direction, observedWindows, requiredWindows },
    territory: options.territory,
  };
}

export function readinessPublicSurface(snapshot: TerritoryReadinessSnapshot, flags: ProvincialFeatureFlags) {
  const rankingVisible = flags.provincialRankingsEnabled && snapshot.readinessState !== "ranking_inactive";
  const awardsAvailable = rankingVisible
    && flags.provincialAwardsEnabled
    && snapshot.readinessState === "trophy_ready";
  const message = !rankingVisible
    ? "La clasificación se mostrará cuando exista suficiente actividad competitiva en la zona."
    : snapshot.readinessState === "ranking_active"
      ? "Clasificación en desarrollo."
      : snapshot.readinessState === "trophy_not_ready"
        ? "El ranking está activo. Los premios de temporada se habilitarán cuando exista suficiente actividad competitiva en la zona."
        : flags.provincialAwardsEnabled
          ? "Esta temporada puede optar a reconocimientos provinciales."
          : "La clasificación está preparada. Los reconocimientos permanecen desactivados durante el piloto.";
  return { awardsAvailable, message, rankingVisible };
}

export type ProvincialAwardCandidate = {
  individualDecision: "clean" | "not_eligible" | "pending_integrity_review";
  playerId: string;
  rank: number;
};

export type ProvincialSeasonAward = {
  playerId: string;
  rank: number;
  status: "certified" | "pending_integrity_review";
};

export const PROVINCIAL_SEASON_CLOSE_PHASES = [
  "season_active",
  "season_frozen",
  "territory_readiness_final",
  "integrity_reconciliation",
  "award_certification",
  "season_closed",
] as const;

export function closeProvincialSeason(options: {
  candidates: ProvincialAwardCandidate[];
  flags: ProvincialFeatureFlags;
  previousAwards?: ProvincialSeasonAward[];
  readiness: TerritoryReadinessSnapshot;
}) {
  const surface = readinessPublicSurface(options.readiness, options.flags);
  const previousAwards = options.previousAwards ?? [];
  const awards = [...previousAwards];
  if (surface.awardsAvailable) {
    for (const candidate of options.candidates.filter(({ rank }) => rank <= 10)) {
      if (awards.some(({ playerId }) => playerId === candidate.playerId)) continue;
      if (candidate.individualDecision === "clean") {
        awards.push({ playerId: candidate.playerId, rank: candidate.rank, status: "certified" });
      } else if (candidate.individualDecision === "pending_integrity_review") {
        awards.push({ playerId: candidate.playerId, rank: candidate.rank, status: "pending_integrity_review" });
      }
    }
  }
  return {
    archived: surface.rankingVisible,
    awards: awards.sort((left, right) => left.rank - right.rank || left.playerId.localeCompare(right.playerId)),
    classification: !surface.rankingVisible
      ? "ranking_not_launched"
      : surface.awardsAvailable
        ? "archived_with_awards"
        : "archived_without_certified_awards",
    grantedAwardsPreserved: previousAwards.every((previous) => awards.some(({ playerId, rank, status }) => (
      playerId === previous.playerId && rank === previous.rank && status === previous.status
    ))),
    promotedRank11: false,
  } as const;
}

export function territoryReadinessTelemetry(snapshot: TerritoryReadinessSnapshot) {
  return {
    calculatedAt: snapshot.calculatedAt,
    observedReasons: [...snapshot.observedReasons],
    observedState: snapshot.observedState,
    readinessState: snapshot.readinessState,
    revision: snapshot.revision,
    season: snapshot.season,
    signals: { ...snapshot.signals },
    territory: snapshot.territory,
  };
}
