import { calculateSeasonScore, expectedResult } from "./engine";
import { round } from "./random";
import type {
  AttackKind,
  AttackResult,
  PlayerMatchEvidence,
  Position,
  SeasonPlayerInput,
  SeasonScoreConfig,
  SyntheticPlayer,
} from "./types";

type ProfileOptions = {
  accountAgeDays?: number;
  challenges: number;
  goals?: number;
  id: string;
  independence?: number;
  latentSkill?: number;
  logicalOpponents?: number;
  opponentRating: number;
  position?: Position;
  provinceCodes?: string[];
  rating: number;
  reliability?: number;
  sameDay?: boolean;
  technicalOpponents: number;
  teamRating?: number;
  ownTeams?: number;
  venueConfidence?: number;
  participationConfidence?: number;
  winRate: number;
};

export function createPlayer(id: string, rating: number, position: Position = "MC", latentSkill = rating): SyntheticPlayer {
  return {
    accountAgeDays: 600,
    id,
    joinedSeasonIndex: 0,
    latentSkill,
    mobility: 0.1,
    position,
    ratingReliability: 0.86,
    ratingV2: rating,
    teamIds: [`${id}-team`],
  };
}

export function createProfileInput(options: ProfileOptions): SeasonPlayerInput {
  const player = createPlayer(options.id, options.rating, options.position, options.latentSkill);
  player.accountAgeDays = options.accountAgeDays ?? player.accountAgeDays;
  player.ratingReliability = options.reliability ?? 0.86;
  const logicalOpponents = options.logicalOpponents ?? options.technicalOpponents;
  const provinces = options.provinceCodes ?? ["08"];
  const records = Array.from({ length: options.challenges }, (_, index): PlayerMatchEvidence => {
    const outcomeCursor = (index * 0.618_033_988_75 + 0.17) % 1;
    const drawRate = (1 - options.winRate) * 0.35;
    const result = outcomeCursor < options.winRate ? 1 as const
      : outcomeCursor < options.winRate + drawRate ? 0.5 as const : 0 as const;
    const week = options.sameDay ? 12 : 1 + (index * 3) % 48;
    const day = options.sameDay ? 1 : index % 6;
    return {
      challengeId: `${options.id}-challenge-${index + 1}`,
      goals: index < (options.goals ?? 0) ? 1 : 0,
      individualPerformanceIndex: Math.max(0, Math.min(100,
        50
        + ((options.latentSkill ?? options.rating) - 70) * 0.6
        + ((options.latentSkill ?? options.rating) - (options.teamRating ?? options.rating)) * 0.4
        + (result - expectedResult(options.teamRating ?? options.rating, options.opponentRating)) * 20,
      )),
      kind: "challenge",
      occurredAt: new Date(Date.UTC(2028, 7, 1 + week * 7 + day, 18, index % 60)).toISOString(),
      opponentClusterId: `${options.id}-cluster-${index % Math.max(1, logicalOpponents)}`,
      opponentIndependence: options.independence ?? 1,
      opponentRating: options.opponentRating,
      opponentTeamId: `${options.id}-opponent-${index % Math.max(1, options.technicalOpponents)}`,
      participated: true,
      participationConfidence: options.participationConfidence ?? 1,
      provinceCode: provinces[index % provinces.length]!,
      result,
      status: "confirmed",
      teamGoalDifference: result === 1 ? 1 : result === 0 ? -1 : 0,
      teamId: `${options.id}-own-team-${index % Math.max(1, options.ownTeams ?? 1)}`,
      teamRating: options.teamRating ?? options.rating,
      venueConfidence: options.venueConfidence ?? 1,
      week,
    };
  });
  return { player, previousCompetitiveProvinceCode: null, records, seasonId: "season-2028-29" };
}

export function humanProfiles() {
  return [
    createProfileInput({ challenges: 20, id: "A", opponentRating: 84, rating: 90, technicalOpponents: 12, winRate: 0.65 }),
    createProfileInput({ challenges: 70, id: "B", opponentRating: 76, rating: 78, technicalOpponents: 10, winRate: 0.62 }),
    createProfileInput({ challenges: 5, id: "C", opponentRating: 86, rating: 93, technicalOpponents: 3, winRate: 0.8 }),
    createProfileInput({ challenges: 23, id: "D", opponentRating: 90, rating: 85, technicalOpponents: 15, winRate: 0.55 }),
    createProfileInput({ challenges: 50, id: "E", logicalOpponents: 10, opponentRating: 78, rating: 84, technicalOpponents: 10, winRate: 0.75 }),
    createProfileInput({ challenges: 25, goals: 0, id: "F", opponentRating: 85, position: "DEF", rating: 88, teamRating: 87, technicalOpponents: 12, winRate: 0.6 }),
    createProfileInput({ challenges: 25, goals: 20, id: "G", opponentRating: 85, position: "DEL", rating: 86, teamRating: 87, technicalOpponents: 12, winRate: 0.6 }),
  ];
}

export function volumeProfiles() {
  return [10, 20, 40, 80, 120].map((challenges) => createProfileInput({
    challenges,
    id: `volume-${challenges}`,
    opponentRating: 82,
    rating: 84,
    technicalOpponents: 12,
    winRate: 0.58,
  }));
}

export function newcomerProfiles() {
  return [2, 5, 8, 10, 15, 25].map((challenges) => createProfileInput({
    challenges,
    id: `newcomer-${challenges}`,
    latentSkill: 94,
    opponentRating: 86,
    rating: 93,
    reliability: 0.72,
    technicalOpponents: Math.max(2, Math.ceil(challenges / 2)),
    winRate: 0.7,
  }));
}

const attackOptions: Record<AttackKind, Omit<ProfileOptions, "id">> = {
  collusion: { challenges: 35, independence: 0.58, logicalOpponents: 5, opponentRating: 89, rating: 86, technicalOpponents: 5, winRate: 0.9 },
  fake_matches: { challenges: 30, independence: 0.65, logicalOpponents: 8, opponentRating: 88, participationConfidence: 0.6, rating: 84, sameDay: true, technicalOpponents: 8, winRate: 0.9 },
  fake_participation: { challenges: 24, logicalOpponents: 8, opponentRating: 84, participationConfidence: 0.15, rating: 82, technicalOpponents: 8, winRate: 0.75 },
  ghost_teams: { accountAgeDays: 4, challenges: 40, independence: 0.08, logicalOpponents: 2, opponentRating: 91, rating: 90, technicalOpponents: 20, winRate: 0.93 },
  impossible_volume: { challenges: 40, logicalOpponents: 12, opponentRating: 84, rating: 85, sameDay: true, technicalOpponents: 12, winRate: 0.8 },
  opponent_boost: { challenges: 18, independence: 0.42, logicalOpponents: 6, opponentRating: 99, rating: 85, technicalOpponents: 8, winRate: 0.83 },
  rating_boost: { challenges: 8, logicalOpponents: 4, opponentRating: 74, rating: 99, technicalOpponents: 4, winRate: 0.75 },
  repeated_opponent: { challenges: 100, logicalOpponents: 2, opponentRating: 82, rating: 84, technicalOpponents: 10, winRate: 0.78 },
  sacrifice_accounts: { accountAgeDays: 2, challenges: 30, independence: 0.05, logicalOpponents: 1, opponentRating: 96, rating: 91, technicalOpponents: 20, winRate: 1 },
  simultaneous_matches: { challenges: 12, logicalOpponents: 6, opponentRating: 85, provinceCodes: ["08", "17", "43"], rating: 86, sameDay: true, technicalOpponents: 6, winRate: 0.75 },
  smurf: { challenges: 12, latentSkill: 94, logicalOpponents: 6, opponentRating: 76, rating: 45, technicalOpponents: 6, winRate: 0.9 },
  sybil: { accountAgeDays: 1, challenges: 50, independence: 0.04, logicalOpponents: 1, opponentRating: 94, rating: 96, technicalOpponents: 50, winRate: 0.96 },
  team_hopping: { challenges: 60, independence: 0.9, logicalOpponents: 30, opponentRating: 83, rating: 84, technicalOpponents: 30, winRate: 0.62 },
  territory_gaming: { challenges: 16, logicalOpponents: 7, opponentRating: 84, provinceCodes: ["17"], rating: 85, technicalOpponents: 7, venueConfidence: 0.2, winRate: 0.7 },
};

export function attackProfiles() {
  return (Object.entries(attackOptions) as Array<[AttackKind, Omit<ProfileOptions, "id">]>).map(([attack, options]) => ({
    attack,
    input: createProfileInput({ ...options, id: `attack-${attack}` }),
  }));
}

export function evaluateAttacks(unprotected: SeasonScoreConfig, protectedConfig: SeasonScoreConfig): AttackResult[] {
  const honest = createProfileInput({ challenges: 16, id: "honest-control", opponentRating: 82, rating: 80, technicalOpponents: 8, winRate: 0.56 });
  const honestScore = calculateSeasonScore(honest, unprotected).score;
  return attackProfiles().map(({ attack, input }) => {
    const openResult = calculateSeasonScore(input, unprotected);
    const protectedResult = calculateSeasonScore(input, protectedConfig);
    return {
      attack,
      protectedRisk: protectedResult.risk.risk,
      protectedScore: protectedResult.score,
      scoreIncreaseWithoutProtection: round(openResult.score - honestScore),
      unprotectedScore: openResult.score,
    };
  });
}

export function legitimateRiskProfiles() {
  return [
    createProfileInput({ challenges: 24, id: "siblings-shared-network", opponentRating: 82, rating: 82, technicalOpponents: 9, winRate: 0.58 }),
    createProfileInput({ challenges: 28, id: "real-club-four-squads", independence: 0.78, logicalOpponents: 4, opponentRating: 84, rating: 84, technicalOpponents: 4, winRate: 0.57 }),
    createProfileInput({ challenges: 30, id: "same-weekly-venue", opponentRating: 80, rating: 81, technicalOpponents: 10, venueConfidence: 1, winRate: 0.55 }),
    createProfileInput({ challenges: 22, id: "owner-two-teams", independence: 0.75, logicalOpponents: 5, opponentRating: 83, rating: 83, technicalOpponents: 6, winRate: 0.59 }),
    createProfileInput({ challenges: 18, id: "small-league", logicalOpponents: 4, opponentRating: 79, rating: 80, technicalOpponents: 4, winRate: 0.56 }),
  ];
}

export function goalDifferenceExperiment(config: SeasonScoreConfig) {
  const close = createProfileInput({ challenges: 20, id: "close-scorelines", opponentRating: 84, rating: 85, technicalOpponents: 10, winRate: 0.6 });
  const blowout = structuredClone(close);
  blowout.player.id = "blowout-scorelines";
  blowout.records = blowout.records.map((record) => ({
    ...record,
    challengeId: record.challengeId.replace("close-scorelines", "blowout-scorelines"),
    teamGoalDifference: record.result === 1 ? 6 : record.result === 0 ? -1 : 0,
  }));
  const closeScore = calculateSeasonScore(close, config).score;
  const blowoutScore = calculateSeasonScore(blowout, config).score;
  const hypotheticalBonus = (input: SeasonPlayerInput) => round(input.records.reduce((sum, record) => (
    sum + clampGoalDifference(record.teamGoalDifference)
  ), 0) / input.records.length * 10);
  return {
    blowoutCurrentScore: blowoutScore,
    blowoutHypotheticalScore: round(blowoutScore + hypotheticalBonus(blowout)),
    closeCurrentScore: closeScore,
    closeHypotheticalScore: round(closeScore + hypotheticalBonus(close)),
  };
}

function clampGoalDifference(value: number) {
  return Math.max(-3, Math.min(3, value));
}
