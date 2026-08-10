import type { CertificationState } from "../../season-ranking-lab/src/integrity-v3";

export type SyntheticWorldStatus = "active" | "completed" | "paused";
export type SyntheticWorldMode = "ephemeral" | "persistent";
export type SyntheticModality = "futbol11" | "futbol7" | "sala";
export type SyntheticPersona =
  | "casual"
  | "competitive"
  | "dormant"
  | "hyperactive"
  | "loyal"
  | "low_activity"
  | "mercenary"
  | "multi_team"
  | "newcomer"
  | "regular"
  | "returning"
  | "slow_responder"
  | "social"
  | "unreliable";
export type SyntheticAttackProfile =
  | "colluder"
  | "fake_team_operator"
  | "ghost_participant"
  | "none"
  | "opponent_farmer"
  | "rating_manipulator"
  | "sybil_operator"
  | "team_hopper"
  | "territory_gamer";
export type SyntheticAttendanceProfile =
  | "correct_rejector"
  | "early_canceller"
  | "injury_prone"
  | "late_canceller"
  | "normal"
  | "occasional_no_show"
  | "repeat_no_show"
  | "stops_responding";
export type SyntheticConductProfile =
  | "conflict_prone"
  | "coordinated_false_reporter"
  | "fair"
  | "occasional_unsporting"
  | "repeat_offender"
  | "retaliatory";
export type SyntheticNotificationCategory = "achievement" | "challenge" | "group" | "market" | "match" | "security";

export type SyntheticProvince = {
  city: string;
  code: string;
  communityCode: string;
  communityName: string;
  density: "dense" | "medium" | "small";
  lat: number;
  lng: number;
  name: string;
};

export type SyntheticVenue = SyntheticProvince & {
  id: string;
  modality: SyntheticModality;
  name: string;
  placeId: string;
};

export type SyntheticAgent = {
  attackProfile: SyntheticAttackProfile;
  attendanceProfile: SyntheticAttendanceProfile;
  availableFrom: string;
  behavior: {
    acceptance: number;
    marketAffinity: number;
    notificationDelayHours: number;
    reliability: number;
    socialAffinity: number;
  };
  city: string;
  conductProfile: SyntheticConductProfile;
  displayName: string;
  facets: Record<"defensa" | "fisico" | "pase" | "regate" | "ritmo" | "tiro", number>;
  id: string;
  kind: "guest" | "registered";
  notificationPreferences: Record<SyntheticNotificationCategory, { email: boolean; inApp: boolean; push: boolean }>;
  persona: SyntheticPersona;
  position: "DEF" | "DEL" | "MC" | "POR";
  productUserId: string | null;
  provinceCode: string;
  ratingReliability: number;
  ratingV2: number;
  status: "active" | "dormant" | "future" | "unavailable";
  teamIds: string[];
  unavailableReason: "synthetic_injury" | null;
  unavailableUntil: string | null;
};

export type SyntheticTeam = {
  activity: "abandoned" | "casual" | "high" | "low" | "regular";
  adminAgentIds: string[];
  challengePolicy: "invite_only" | "private" | "public" | "temporarily_unavailable";
  city: string;
  id: string;
  integrityClusterId: string;
  marketPolicy: "active" | "never" | "seasonal";
  modality: SyntheticModality;
  name: string;
  ownerAgentId: string;
  playerIds: string[];
  productGroupId: string | null;
  provinceCode: string;
  strength: number;
  style: "balanced" | "closed_friends" | "high_rotation" | "stable" | "veteran" | "young";
};

export type SyntheticChallenge = {
  awayTeamId: string;
  createdAt: string;
  id: string;
  operationId: string;
  homeTeamId: string;
  productChallengeId: string | null;
  proposedAt: string;
  state: "accepted" | "cancelled" | "countered" | "expired" | "pending" | "rejected";
};

export type SyntheticMatch = {
  awayGoals: number | null;
  awayTeamId: string | null;
  confidence: number;
  evidenceExcluded: boolean;
  guestIds: string[];
  homeGoals: number | null;
  homeTeamId: string;
  id: string;
  kind: "challenge" | "internal";
  occurredAt: string;
  participantIds: string[];
  productMatchId: string | null;
  provinceCode: string;
  scorerGoals: Record<string, number>;
  state: "auto_confirmed" | "cancelled" | "confirmed" | "disputed" | "scheduled";
  venueId: string;
};

export type SyntheticNotification = {
  agentId: string;
  category: SyntheticNotificationCategory;
  createdAt: string;
  id: string;
  kind: string;
  mandatoryInApp: boolean;
  readAt: string | null;
  relatedEntityId: string | null;
  visibleInApp: boolean;
};

export type SyntheticAttendanceRecord = {
  agentId: string;
  canonicalNoShowDistinguishable: boolean;
  changedAt: string;
  finalOutcome: "cancelled_early" | "cancelled_late" | "injured" | "no_show" | "played" | "rejected";
  id: string;
  initialStatus: "no" | "voy";
  matchId: string;
  teamId: string;
};

export type SyntheticConductScenario = {
  coverageFixture?: boolean;
  id: string;
  independentSourceTeams: number;
  kind:
    | "conflict_prone_incident"
    | "coordinated_false_report"
    | "fair_play_control"
    | "guest_withdrawal_review"
    | "independent_team_reports"
    | "mutual_conflict"
    | "occasional_unsporting"
    | "repeat_offender"
    | "same_team_report_burst"
    | "single_clean_history_report";
  matchId: string;
  productCapability: "implemented_guest_withdrawal_only" | "not_implemented" | "not_required";
  relatedMatchIds?: string[];
  reporterAgentIds: string[];
  sourceTeamIds?: string[];
  status: "dismissed" | "pending" | "reviewed";
  targetAgentId: string;
  virtualDate: string;
};

export type SyntheticRewardBox = {
  agentId: string | null;
  cosmeticGranted: boolean | null;
  cosmeticKey: string | null;
  createdAt: string;
  duplicatePoints: number;
  id: string;
  openedAt: string | null;
  points: number | null;
  teamId: string;
};

export type SyntheticPlayerCosmeticInventoryItem = {
  acquiredAt: string;
  agentId: string;
  cosmeticKey: string;
  seenAt: string | null;
  sourceBoxId: string;
};

export type SyntheticPlayerCosmeticLoadout = {
  accentKey: string | null;
  agentId: string;
  backgroundKey: string | null;
  effectKey: string | null;
  frameKey: string | null;
  revision: number;
  titleKey: string | null;
  updatedAt: string;
};

export type SyntheticRatingOpinion = {
  createdAt: string;
  evaluatorAgentId: string;
  id: string;
  operationId: string;
  sharedMatchesAtCreation: number;
  status: "active" | "annulled" | "superseded";
  targetAgentId: string;
  values: Record<"defensa" | "fisico" | "pase" | "regate" | "ritmo" | "tiro", -1 | 0 | 1>;
};

export type SyntheticAchievement = {
  agentId: string | null;
  claimedAt: string | null;
  earnedAt: string;
  id: string;
  key: string;
  progress: number;
  scope: "individual" | "team";
  teamId: string;
};

export type SyntheticRankingRow = {
  agentId: string;
  certification: CertificationState;
  certificationReasons: string[];
  competition: number;
  integrityRisk: number;
  logicalOpponents: number;
  movement: number;
  opposition: number;
  provinceCode: string;
  quality: number;
  rank: number;
  score: number;
  validChallenges: number;
};

export type SyntheticEvent = {
  actorAgentId: string | null;
  entityIds: string[];
  eventType: string;
  expected: Record<string, unknown>;
  flow: string;
  operationId: string;
  payload: Record<string, unknown>;
  sequence: number;
  status: "failed" | "pass" | "pending";
  virtualDate: string;
};

export type SyntheticIncidentCategory =
  | "ACHIEVEMENT_ERROR"
  | "AUTHORIZATION_BUG"
  | "CONCURRENCY_ERROR"
  | "DATA_INCONSISTENCY"
  | "DEAD_END_UX"
  | "DUPLICATE_EFFECT"
  | "FLOW_ERROR"
  | "INTEGRITY_ERROR"
  | "INVARIANT_FAILURE"
  | "MISSING_NOTIFICATION"
  | "NEEDS_PRODUCT_DECISION"
  | "PERFORMANCE_ANOMALY"
  | "RANKING_ERROR"
  | "RATING_ERROR"
  | "REWARD_ERROR"
  | "RLS_FAILURE"
  | "TESTABILITY_GAP"
  | "TIMEOUT_ERROR"
  | "WRONG_NOTIFICATION"
  | "PRODUCT_BUG"
  | "SIMULATION_BUG"
  | "ENVIRONMENT_ISSUE";

export type SyntheticIncident = {
  actual: Record<string, unknown>;
  actorAgentId: string | null;
  afterState: Record<string, unknown>;
  beforeState: Record<string, unknown>;
  category: SyntheticIncidentCategory;
  expected: Record<string, unknown>;
  id: string;
  occurrenceCount: number;
  operation: string;
  relatedEntityIds: string[];
  reproductionSteps: string[];
  resolution?: {
    evidence: string[];
    fixed: boolean;
    regressionVerified: boolean;
  };
  severity: "critical" | "high" | "info" | "low" | "medium";
  status: "confirmed_bug" | "false_positive" | "fixed" | "needs_product_decision" | "open" | "regression_verified";
  virtualDate: string;
};

export type SyntheticCoverage = {
  failures: number;
  flow: string;
  lastExecution: string | null;
  passes: number;
  scenario: string;
  status: "FAIL" | "NO_COVERAGE" | "PASS";
  timesExecuted: number;
};

export type SyntheticWorldState = {
  achievements: SyntheticAchievement[];
  agents: SyntheticAgent[];
  attendanceRecords: SyntheticAttendanceRecord[];
  boxes: SyntheticRewardBox[];
  challenges: SyntheticChallenge[];
  coverage: SyntheticCoverage[];
  conductScenarios: SyntheticConductScenario[];
  eventSequence: number;
  events: SyntheticEvent[];
  incidents: SyntheticIncident[];
  matches: SyntheticMatch[];
  notifications: SyntheticNotification[];
  playerCosmeticInventory: SyntheticPlayerCosmeticInventoryItem[];
  playerCosmeticLoadouts: SyntheticPlayerCosmeticLoadout[];
  ratingOpinions: SyntheticRatingOpinion[];
  rankings: SyntheticRankingRow[];
  teams: SyntheticTeam[];
  venues: SyntheticVenue[];
};

export type SyntheticWorld = {
  config: SyntheticWorldConfig;
  createdAt: string;
  currentDate: string;
  id: string;
  mode: SyntheticWorldMode;
  name: string;
  revision: number;
  seasonId: string;
  seed: number;
  sourceCommit: string;
  startDate: string;
  state: SyntheticWorldState;
  status: SyntheticWorldStatus;
};

export type SyntheticWorldConfig = {
  agentCount: number;
  attackRate: number;
  guestCount: number;
  initialFreeAgentCount: number;
  rankingAuditScenario?: {
    id: "A" | "B" | "C" | "D" | "E";
    mutation: "challenge_density_plus_25" | "none" | "rotation_not_applied";
    sourceWorldId: string;
    strategy: "evidence_exclusion" | "exclusion_and_hold";
    trophyMinimumChallenges: number;
    trophyMinimumLogicalOpponents: number;
  };
  seasonEnd: string;
  teamCount: number;
};
