export type SeasonStatus = "active" | "closed" | "frozen" | "planned";
export type MatchStatus = "auto_confirmed" | "cancelled" | "confirmed" | "disputed" | "draft";
export type MatchKind = "challenge" | "internal" | "tournament";
export type Position = "DEF" | "DEL" | "MC" | "POR";
export type VolumeModel = "all_saturated" | "best_20" | "hybrid_70_30" | "recent_20" | "recent_25" | "recent_30";
export type RatingConfidenceModel = "challenge_calibrated" | "competitive" | "full" | "graduated";
export type IntegrityMode = "none" | "weighted";

export type Season = {
  endsAt: string;
  id: string;
  label: string;
  startsAt: string;
  status: SeasonStatus;
};

export type Territory = {
  autonomousCommunityCode: string | null;
  autonomousCommunityName: string | null;
  density: "dense" | "medium" | "small";
  provinceCode: string;
  provinceName: string;
  territorialDuplicate: boolean;
  type: "autonomous_city" | "province";
};

export type SyntheticPlayer = {
  accountAgeDays: number;
  id: string;
  joinedSeasonIndex: number;
  latentSkill: number;
  mobility: number;
  position: Position;
  ratingReliability: number;
  ratingV2: number;
  teamIds: string[];
};

export type SyntheticTeam = {
  activityRate: number;
  id: string;
  latentStrength: number;
  ownerClusterId: string;
  playerIds: string[];
  provinceCode: string;
};

export type PlayerMatchEvidence = {
  challengeId: string;
  goals: number;
  individualPerformanceIndex: number;
  kind: MatchKind;
  occurredAt: string;
  opponentClusterId: string;
  opponentIndependence: number;
  opponentRating: number;
  opponentTeamId: string;
  participated: boolean;
  participationConfidence: number;
  provinceCode: string;
  result: 0 | 0.5 | 1;
  status: MatchStatus;
  teamGoalDifference: number;
  teamId: string;
  teamRating: number;
  venueConfidence: number;
  week: number;
};

export type SeasonPlayerInput = {
  player: SyntheticPlayer;
  previousCompetitiveProvinceCode: string | null;
  records: PlayerMatchEvidence[];
  seasonId: string;
};

export type EligibilityConfig = {
  minimumRatingReliability: number;
  minimumUniqueOpponents: number;
  minimumValidChallenges: number;
  recentActivityWeeks: number | null;
};

export type SeasonScoreConfig = {
  densityTop10Minimum: number;
  eligibility: EligibilityConfig;
  id: string;
  integrityMode: IntegrityMode;
  integrityScorePenalty?: boolean;
  label: string;
  opponentDecay: number[];
  ratingConfidenceModel: RatingConfidenceModel;
  volumeModel: VolumeModel;
  weights: {
    competition: number;
    opposition: number;
    quality: number;
  };
};

export type RiskSignals = {
  accountAgeCluster: number;
  abnormalMatchFrequency: number;
  closedNetworkRatio: number;
  impossibleTravelRatio: number;
  opponentIdentityGap: number;
  participationAnomaly: number;
  ratingVsExternalEvidence: number;
  repeatedOpponentRatio: number;
  venueAnomaly: number;
};

export type RiskAssessment = {
  classification: "clean" | "high_risk" | "suspicious" | "watch";
  risk: number;
  signals: RiskSignals;
};

export type ScoreComponents = {
  competition: number;
  integrityFactor: number;
  opposition: number;
  quality: number;
};

export type EligibilityResult = {
  eligible: boolean;
  reasons: string[];
  uniqueOpponents: number;
  validChallenges: number;
};

export type SeasonScoreResult = {
  components: ScoreComponents;
  competitiveProvinceCode: string | null;
  eligibility: EligibilityResult;
  playerId: string;
  risk: RiskAssessment;
  rawScore: number;
  score: number;
  seasonId: string;
  weightedChallenges: number;
};

export type RankedPlayer = SeasonScoreResult & {
  autonomousCommunityRank: number | null;
  nationalRank: number | null;
  provinceRank: number | null;
};

export type FormulaMetrics = {
  candidateId: string;
  eligiblePlayers: number;
  rankCorrelation: number;
  scoreSkillCorrelation: number;
  top10Precision: number;
  top50Precision: number;
  top100Precision: number;
  volumeAdvantage: number;
};

export type AttackKind =
  | "collusion"
  | "fake_matches"
  | "fake_participation"
  | "ghost_teams"
  | "impossible_volume"
  | "opponent_boost"
  | "rating_boost"
  | "repeated_opponent"
  | "sacrifice_accounts"
  | "simultaneous_matches"
  | "smurf"
  | "sybil"
  | "team_hopping"
  | "territory_gaming";

export type AttackResult = {
  attack: AttackKind;
  protectedRisk: number;
  protectedScore: number;
  scoreIncreaseWithoutProtection: number;
  unprotectedScore: number;
};
