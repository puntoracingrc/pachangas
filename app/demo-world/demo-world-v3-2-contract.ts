import type { DemoWorldV2Snapshot } from "./demo-world-v2-contract";

export const SYNTHETIC_SEASON_VERSION = "pachangas-iq-synthetic-season-v1-2026-27" as const;
export const SYNTHETIC_SEASON_SEED = "pachangas-iq-synthetic-season-v1-2026-27" as const;
export const SYNTHETIC_SEASON_ENGINE_VERSION = "synthetic-operations-season-v1" as const;
export const DEMO_WORLD_V32_VERSION = 3.2 as const;
export const DEMO_WORLD_V32_SEED = SYNTHETIC_SEASON_SEED;

export type SyntheticSeasonCheckpointId = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
export type SyntheticSeasonCompetitionKind = "LEAGUE" | "TOURNAMENT";
export type SyntheticSeasonMatchKind = "CHALLENGE" | "LEAGUE" | "TOURNAMENT_GROUP" | "TOURNAMENT_KNOCKOUT";
export type SyntheticSeasonTeamState = "ACTIVE" | "ARCHIVED" | "LIMITED" | "SUSPENDED" | "UNDER_REVIEW";
export type SyntheticSeasonSurface = "bracket" | "clubs" | "discipline" | "incidents" | "leagues" | "marketplace"
  | "matches" | "organizer" | "overview" | "referees" | "rounds" | "standings" | "teams" | "timeline"
  | "tournaments" | "challenges";

export type SyntheticSeasonClub = {
  id: string;
  name: string;
  organizerAccess: "APPROVED_INTEREST" | "PARTNER" | "PRIVATE_BETA";
  publicInDemo: boolean;
  status: "ACTIVE" | "ARCHIVED";
  story: string;
  teamIds: string[];
};

export type SyntheticSeasonTeam = {
  billingState: "ACTIVE" | "INACTIVE";
  challengesAllowed: boolean;
  clubId: string;
  competitionContinuity: boolean;
  id: string;
  marketplaceAllowed: boolean;
  name: string;
  ownerTransferred: boolean;
  publicLocation: string;
  restrictionPreset: "CLEAR" | "NEW_ACTIVITY_ONLY" | "SOCIAL_ONLY";
  state: SyntheticSeasonTeamState;
};

export type SyntheticSeasonPlayer = {
  id: string;
  name: string;
  position: "DC" | "DFC" | "ED" | "EI" | "LD" | "LI" | "MC" | "MCO" | "PIV" | "POR";
  profile: "GUEST" | "IRREGULAR" | "REGULAR" | "SCORER" | "SUBSTITUTE";
  sanctioned: boolean;
  teamId: string;
};

export type SyntheticSeasonReferee = {
  assignmentCount: number;
  clubIds: string[];
  id: string;
  modalities: Array<"FOOTBALL_7" | "FUTSAL">;
  name: string;
  publicFeeConsent: boolean;
  zone: string;
};

export type SyntheticSeasonCompetition = {
  clubId: string;
  id: string;
  kind: SyntheticSeasonCompetitionKind;
  modality: "FOOTBALL_7" | "FUTSAL";
  name: string;
  publicInDemo: boolean;
  refereePolicy: "OPTIONAL" | "REQUIRED";
  ruleRevision: string;
  status: "COMPLETED";
  teamIds: string[];
  visibility: "PRIVATE" | "PUBLIC" | "UNLISTED";
};

export type SyntheticSeasonMatchResult = {
  away: number;
  decidedBy: "EXTRA_TIME" | "FORFEIT" | "NORMAL" | "PENALTIES";
  home: number;
  penaltiesAway: number | null;
  penaltiesHome: number | null;
  winnerTeamId: string | null;
};

export type SyntheticSeasonMatch = {
  anomaly: "DISPUTED" | "NO_SHOW" | "NORMAL" | "POSTPONED" | "SUSPENDED" | "VENUE_CHANGED";
  awayTeamId: string;
  canonicalMatchId: string;
  competitionId: string | null;
  homeTeamId: string;
  kind: SyntheticSeasonMatchKind;
  refereeAssignmentId: string | null;
  refereeId: string | null;
  result: SyntheticSeasonMatchResult;
  round: number;
  scheduledAt: string;
  stage: string;
  venue: string;
  week: number;
};

export type SyntheticSeasonMatchSheet = {
  absentPlayerIds: string[];
  attendance: "CONFIRMED" | "NO_SHOW";
  canonicalMatchId: string;
  id: string;
  sanctionedPlayerIds: string[];
  starterPlayerIds: string[];
  substitutePlayerIds: string[];
  teamId: string;
};

export type SyntheticSeasonStandingRow = {
  draws: number;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  losses: number;
  played: number;
  points: number;
  position: number;
  teamId: string;
  wins: number;
};

export type SyntheticSeasonBracketNode = {
  awayTeamId: string;
  homeTeamId: string;
  id: string;
  matchId: string;
  round: "FINAL" | "QUARTERFINAL" | "SEMIFINAL" | "THIRD_PLACE";
  winnerTeamId: string;
};

export type SyntheticSeasonDisciplineEvent = {
  canonicalMatchId: string;
  card: "BLUE" | "RED" | "SECOND_YELLOW" | "YELLOW";
  id: string;
  playerId: string;
  refereeAssignmentId: string | null;
  reportingRefereeId: string | null;
  week: number;
};

export type SyntheticSeasonSanction = {
  fulfilledAtWeek: number;
  id: string;
  imposedAtWeek: number;
  playerId: string;
  status: "FULFILLED";
};

export type SyntheticSeasonCheckpointHashes = {
  authorityHash: string;
  competitionHash: string;
  disciplineHash: string;
  operationalStateHash: string;
  publicSnapshotHash: string;
  refereeHash: string;
  standingsHash: string;
};

export type SyntheticSeasonCheckpoint = {
  bracket: SyntheticSeasonBracketNode[];
  changes: {
    champion: string | null;
    eliminatedTeamIds: string[];
    incidents: string[];
    newDisciplineEvents: number;
    newOfficialResults: number;
    qualifiedTeamIds: string[];
    refereeChanges: number;
    restrictedTeamIds: string[];
    summary: string[];
  };
  checkpoint: SyntheticSeasonCheckpointId;
  discipline: {
    eventCount: number;
    fulfilledSanctions: number;
    ineligiblePlayers: number;
    sanctionCount: number;
  };
  hashes: SyntheticSeasonCheckpointHashes;
  label: string;
  matches: {
    official: SyntheticSeasonMatch[];
    upcoming: SyntheticSeasonMatch[];
  };
  operationalStates: SyntheticSeasonTeam[];
  refereeStats: Array<{ assignments: number; completed: number; refereeId: string; replacements: number }>;
  standings: Record<string, SyntheticSeasonStandingRow[]>;
  week: number;
};

export type SyntheticSeasonFaultOutcome = {
  canonicalWinner: string;
  code: string;
  loserOutcome: "IDEMPOTENT" | "REJECTED" | "STALE";
  name: string;
  regressionVerified: true;
};

export type SyntheticSeasonNotification = {
  category: "ACCESS_APPROVED" | "CHAMPION" | "CLASSIFICATION" | "MATCH_UPCOMING" | "OPERATIONAL_RESTRICTION"
    | "POSTPONEMENT" | "REFEREE_ASSIGNMENT" | "REGISTRATION" | "RESULT_OFFICIAL" | "RESULT_PENDING" | "SANCTION";
  id: string;
  recipientId: string;
  sink: "SYNTHETIC_NOTIFICATION_SINK";
  week: number;
};

export type SyntheticSeasonProof = {
  authorityAnchors: {
    demoWorldV2AuthorityHash: string;
    demoWorldV31AuthorityHash: string;
    leagueSchedulingEngineVersion: string;
    rpcFamilies: string[];
  };
  authorityExecution: {
    canonicalLeagueMatches: number;
    canonicalTournamentMatches: number;
    database: "temporary-local-postgresql";
    migrationLedger: 212;
    mode: "REAL_RPC_CONFORMANCE_PLUS_DETERMINISTIC_SEASON_PROJECTION";
    rpcFamilies: string[];
    teamOperationalScenarios: number;
  };
  authorityHash: string;
  checkpointHashes: Record<string, SyntheticSeasonCheckpointHashes>;
  cleanup: {
    databaseDestroyed: boolean;
    pendingOperations: number;
    productionRows: number;
    syntheticSessions: number;
  };
  counts: {
    challenges: number;
    checkpoints: number;
    clubs: number;
    competitions: number;
    disciplineEvents: number;
    faultInjections: number;
    leagues: number;
    matchSheets: number;
    matches: number;
    notifications: number;
    organizerApplications: number;
    organizerGrants: number;
    organizers: number;
    players: number;
    refereeAssignments: number;
    referees: number;
    registrationRequests: number;
    sanctions: number;
    teams: number;
    tournaments: number;
    waitlists: number;
    weeks: number;
  };
  engineVersion: typeof SYNTHETIC_SEASON_ENGINE_VERSION;
  faultInjection: SyntheticSeasonFaultOutcome[];
  generatedAt: string;
  inputHash: string;
  invariants: Record<string, boolean>;
  migrationLedger: {
    count: 212;
    latest: "20260829221312_team_operational_hardening_indexes_flags_v1.sql";
    latestHash: "d3335bd87e95bbc7088104ea26a52333034358ed7813e2c3fc441641a87e0c22";
  };
  notificationScan: {
    externalDeliveries: 0;
    invalidRecipients: 0;
    sinkOnly: true;
  };
  oracleHashes: {
    bracket: string;
    discipline: string;
    operationalState: string;
    referee: string;
    squads: string;
    standings: string;
  };
  privacyScan: {
    authUuids: 0;
    emails: 0;
    phones: 0;
    privateEvidence: 0;
    secrets: 0;
    stripeIds: 0;
  };
  publicSnapshotHash: string;
  remoteWrites: 0;
  seed: typeof SYNTHETIC_SEASON_SEED;
  simulationVersion: typeof SYNTHETIC_SEASON_VERSION;
  stripeTouched: false;
};

export type SyntheticSeasonIndex = {
  checkpointFiles: Array<{
    checkpoint: SyntheticSeasonCheckpointId;
    hash: string;
    label: string;
    path: string;
    week: number;
  }>;
  clubs: SyntheticSeasonClub[];
  competitions: SyntheticSeasonCompetition[];
  demoNow: string;
  matchSheets: SyntheticSeasonMatchSheet[];
  matches: SyntheticSeasonMatch[];
  mode: "demo-world-read-only";
  players: SyntheticSeasonPlayer[];
  proof: SyntheticSeasonProof;
  readOnly: true;
  referees: SyntheticSeasonReferee[];
  remoteWrites: 0;
  teams: SyntheticSeasonTeam[];
  transport: { methods: ["GET"]; remoteWrites: 0 };
};

export type DemoWorldV32Manifest = {
  checkpoints: SyntheticSeasonIndex["checkpointFiles"];
  chunks: Record<string, string> & { core: string; season: string };
  counts: Record<string, number> & {
    canonicalMatches: 128;
    checkpoints: 9;
    clubs: 6;
    players: 481;
    referees: 12;
    teams: 32;
  };
  demoNow: string;
  generatedAt: string;
  hash: string;
  mode: "demo-world-read-only";
  season: "2026/27";
  seed: typeof DEMO_WORLD_V32_SEED;
  version: typeof DEMO_WORLD_V32_VERSION;
};

export type DemoWorldV32Snapshot = Omit<DemoWorldV2Snapshot, "manifest"> & {
  manifest: DemoWorldV32Manifest;
  season: SyntheticSeasonIndex;
};

export function syntheticSeasonCheckpointFromValue(value: unknown): SyntheticSeasonCheckpointId | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 8 ? parsed as SyntheticSeasonCheckpointId : null;
}

export function syntheticSeasonPrivacyFindings(serialized: string) {
  const patterns: Array<[string, RegExp]> = [
    ["EMAIL", /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i],
    ["PHONE", /(?:\+34|0034)[\s-]?[6-9](?:[\s-]?\d){8}\b/],
    ["DATABASE_URL", /postgres(?:ql)?:\/\//i],
    ["SUPABASE_URL", /https?:\/\/[^\s"']+\.supabase\.co\b/i],
    ["SERVICE_SECRET", /\b(?:sk|rk)_(?:test|live)_[A-Za-z0-9]{8,}\b|\bwhsec_[A-Za-z0-9]{8,}\b|\bAIza[A-Za-z0-9_-]{20,}\b/],
    ["JWT", /\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\b/],
    ["STRIPE_ID", /\b(?:ch|cus|evt|pi|price|prod|sub)_[A-Za-z0-9]{8,}\b/],
  ];
  return patterns.filter(([, pattern]) => pattern.test(serialized)).map(([label]) => label);
}

export function syntheticSeasonIntegrityErrors(index: SyntheticSeasonIndex, checkpoints: SyntheticSeasonCheckpoint[]) {
  const errors: string[] = [];
  if (!index.readOnly || index.remoteWrites !== 0 || index.transport.methods.join(",") !== "GET") errors.push("Season snapshot is not read-only");
  if (index.proof.seed !== SYNTHETIC_SEASON_SEED || index.proof.simulationVersion !== SYNTHETIC_SEASON_VERSION) errors.push("Season seed/version mismatch");
  if (index.teams.length !== 32) errors.push("Season must contain 32 teams");
  if (index.players.length < 440 || index.players.length > 500) errors.push("Season player count is outside 440-500");
  if (index.clubs.length !== 6 || index.referees.length !== 12) errors.push("Season club/referee counts are invalid");
  if (index.competitions.filter(({ kind }) => kind === "LEAGUE").length !== 2) errors.push("Season must contain 2 leagues");
  if (index.competitions.filter(({ kind }) => kind === "TOURNAMENT").length !== 2) errors.push("Season must contain 2 tournaments");
  if (index.matches.length < 120 || index.matches.length > 160) errors.push("Season canonical match count is outside 120-160");
  if (checkpoints.length !== 9 || checkpoints.map(({ checkpoint }) => checkpoint).join(",") !== "0,1,2,3,4,5,6,7,8") errors.push("Season checkpoint sequence is invalid");
  if (new Set(index.matches.map(({ canonicalMatchId }) => canonicalMatchId)).size !== index.matches.length) errors.push("Duplicate CanonicalMatch detected");
  if (index.players.some(({ teamId }) => !index.teams.some(({ id }) => id === teamId))) errors.push("Player references an unknown team");
  if (index.proof.remoteWrites !== 0 || index.proof.stripeTouched) errors.push("Season proof reports forbidden external activity");
  if (Object.values(index.proof.privacyScan).some((count) => count !== 0)) errors.push("Season privacy scan is not clean");
  if (index.proof.notificationScan.externalDeliveries !== 0 || index.proof.notificationScan.invalidRecipients !== 0 || !index.proof.notificationScan.sinkOnly) errors.push("Season notifications escaped the synthetic sink");
  if (Object.values(index.proof.invariants).some((passed) => !passed)) errors.push("Season invariant failed");
  return errors;
}
