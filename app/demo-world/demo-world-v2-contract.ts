import type { LeagueMatchOperationsJson } from "../league-match-operations-contract";
import type { LeagueSchedulingJson } from "../league-scheduling-contract";
import type { RefereeJson } from "../referee-platform-contract";
import {
  disciplineArray,
  disciplineNumber,
  disciplineRecord,
  disciplineText,
  type CompetitionDisciplineJson,
} from "../competition-discipline-contract";
import {
  DEMO_WORLD_MODE,
  DEMO_WORLD_SEASON,
  demoWorldForbiddenPaths,
  demoWorldIntegrityErrors,
  type DemoWorldActivityChunk,
  type DemoWorldCoreChunk,
  type DemoWorldMatchesChunk,
  type DemoWorldPlayersChunk,
  type DemoWorldPrimaryTab,
  type DemoWorldSnapshot,
} from "./demo-world-contract";

export const DEMO_WORLD_V2_VERSION = 2.8 as const;
export const DEMO_WORLD_V2_SEED = "pachangas-iq-demo-world-v2-8-2026-27" as const;

export type DemoWorldV2PrimaryTab = DemoWorldPrimaryTab
  | "arbitros"
  | "clasificacion"
  | "club"
  | "configuracion"
  | "disciplina"
  | "jornadas"
  | "liga"
  | "planes"
  | "competiciones"
  | "torneo";

export type DemoWorldV2Manifest = {
  chunks: {
    activity: string;
    clubsReferees: string;
    competitions: string;
    configuration: string;
    core: string;
    matches: string;
    organizerBilling: string;
    players: string;
    publicCompetitions: string;
    tournament: string;
  };
  counts: {
    achievements: number;
    canonicalMatches: number;
    challenges: number;
    clubs: number;
    competitions: number;
    matches: number;
    notifications: number;
    organizerBillingScenarios: number;
    players: number;
    publicCompetitions: number;
    referees: number;
    registrationRequests: number;
    ruleRevisions: number;
    rewardBoxes: number;
    rounds: number;
    stories: number;
    teams: number;
    tournamentDrawRevisions: number;
    tournamentGroups: number;
    tournaments: number;
  };
  demoNow: string;
  generatedAt: string;
  hash: string;
  mode: typeof DEMO_WORLD_MODE;
  season: typeof DEMO_WORLD_SEASON;
  seed: typeof DEMO_WORLD_V2_SEED;
  version: typeof DEMO_WORLD_V2_VERSION;
};

export type DemoWorldV2OrganizerBillingPlan = {
  accessModel: "PARTNERSHIP" | "SUBSCRIPTION";
  checkoutAvailable: false;
  description: string;
  displayName: string;
  features: string[];
  limits: Record<string, number | null>;
  organizerKind: "CLUB" | "TEAM";
  planCode: "CLUB_ORGANIZER" | "CLUB_PARTNER" | "TEAM_ORGANIZER_PRO";
  prices: [];
  pricingStatus: "AWAITING_PRICE_APPROVAL" | "PARTNERSHIP_REVIEW";
};

export type DemoWorldV2OrganizerBillingScenario = {
  accessStatus: "active" | "continuity" | "grace";
  accountStatus: "active" | "canceled" | "past_due";
  continuityUntil: string | null;
  creationAllowed: boolean;
  graceEndsAt: string | null;
  id: "canceled_continuity" | "club_active" | "club_partner" | "past_due_grace" | "team_active";
  note: string;
  organizerKind: "CLUB" | "TEAM";
  organizerName: string;
  planCode: DemoWorldV2OrganizerBillingPlan["planCode"];
  renewalAt: string | null;
};

export type DemoWorldV2OrganizerBillingChunk = {
  catalog: {
    liveCheckoutEnabled: false;
    plans: DemoWorldV2OrganizerBillingPlan[];
    status: "CATALOG_AVAILABLE";
  };
  privacy: {
    containsPii: false;
    containsPriceId: false;
    containsStripeCustomerId: false;
    containsStripeSubscriptionId: false;
  };
  provenance: {
    authority: "canonical-read-model-shape";
    source: "deterministic-demo";
    verified: true;
  };
  readOnly: true;
  scenarios: DemoWorldV2OrganizerBillingScenario[];
  transport: {
    methods: ["GET"];
    remoteWrites: 0;
  };
};

export type DemoWorldV2LeagueEntry = {
  id: string;
  rosterId: string;
  status: "accepted";
  teamId: string;
};

export type DemoWorldV2LeagueScorer = {
  goals: number;
  playerId: string;
  side: "away" | "home";
};

export type DemoWorldV2LineageStep = {
  at: string;
  id: string;
  label: string;
  sequence: number;
  type: "fixture_change" | "official_result" | "postponement" | "resumption" | "suspension";
};

export type DemoWorldV2LeagueMatch = {
  awayEntryId: string;
  awayTeamId: string;
  canonicalMatchId: string;
  contextId: string;
  exceptionType: "none" | "no_show" | "postponed" | "suspended_resumed" | "venue_changed";
  homeEntryId: string;
  homeTeamId: string;
  id: string;
  lateArrivalStatus: "arrived_within_policy" | null;
  lineage: DemoWorldV2LineageStep[];
  officialDecision: {
    id: string;
    outcome: "MIRROR_SPORTING_RESULT" | "NO_SHOW";
    publishedAt: string;
    revision: number;
  };
  originalScheduledStart: string;
  partialResult: { away: number; home: number; minute: number } | null;
  result: { away: number; home: number };
  roundId: string;
  roundNumber: number;
  scheduledStart: string;
  scorers: DemoWorldV2LeagueScorer[];
  status: "official";
  venueLabel: string;
};

export type DemoWorldV2StandingRow = {
  draws: number;
  effectivePoints: number;
  entryId: string;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  losses: number;
  played: number;
  position: number;
  team: { displayName: string; id: string };
  teamId: string;
  wins: number;
};

export type DemoWorldV2CompetitionChunk = {
  competition: {
    category: { id: string; name: string; sportFormat: "FOOTBALL_7"; status: "active" };
    division: { id: string; name: string; status: "active" };
    edition: { id: string; name: string; seasonLabel: typeof DEMO_WORLD_SEASON; status: "completed" };
    group: { id: string; name: string; status: "completed" };
    id: string;
    name: "LIGA BARRIOS IQ 2026/27";
    privateBeta: true;
    refereeAssignmentsEnabled: true;
    ruleRevision: { id: string; status: "frozen"; version: 1 };
    slug: "liga-barrios-iq-2026-27";
    stage: { id: string; name: string; status: "completed"; type: "LEAGUE_STAGE" };
    status: "completed";
    visibility: "private";
  };
  delegates: Array<{ entryId: string; id: string; role: "PRIMARY_DELEGATE"; status: "active" }>;
  disciplinePreview: CompetitionDisciplineJson;
  entries: DemoWorldV2LeagueEntry[];
  matchPreviews: Record<string, LeagueMatchOperationsJson>;
  refereeAssignmentDeskPreview: RefereeJson;
  refereeAssignmentPreviews: Record<string, RefereeJson>;
  matchDisciplinePreviews: Record<string, CompetitionDisciplineJson>;
  matches: DemoWorldV2LeagueMatch[];
  provenance: {
    authorityHash: string;
    database: "temporary-local-postgresql";
    migrations: number;
    oracle: "independent-basic-standings-v1";
    rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5"];
    source: "simulation-world";
    verified: true;
  };
  rosters: Array<{ entryId: string; id: string; playerIds: string[]; status: "locked" }>;
  rounds: Array<{ id: string; matchIds: string[]; name: string; number: number; status: "completed" }>;
  schedulePreview: LeagueSchedulingJson;
  standingSnapshot: {
    checksum: string;
    computedResults: 15;
    criteria: string[];
    id: string;
    revision: number;
    rows: DemoWorldV2StandingRow[];
  };
  standingsPreview: LeagueMatchOperationsJson;
};

export type DemoWorldV2Club = {
  clubType: "FOOTBALL_CLUB" | "INDEPENDENT_ORGANIZER" | "SPORTS_CENTER";
  description: string;
  generalArea: { countryCode: "ES"; municipality: string; province: string };
  id: string;
  name: string;
  publicProfile: Record<string, unknown>;
  refereeIds: string[];
  slug: string;
  teamIds: string[];
  verified: boolean;
};

export type DemoWorldV2Referee = {
  availabilityStatus: "AVAILABLE" | "LIMITED";
  clubIds: string[];
  displayName: string;
  id: string;
  marketplaceStatus: "listed";
  modalities: Array<"FOOTBALL_11" | "FOOTBALL_7" | "FUTSAL">;
  municipality: string;
  publicBio: string;
  publicFee: {
    currency: string;
    feeMode: "FIXED" | "FREE" | "NEGOTIABLE" | "VOLUNTEER";
    fromCents: number | null;
    paymentManagedByPachangasIq: false;
  } | null;
  slug: string;
  statistics: {
    assignmentsAccepted: number;
    assignmentsConfirmed: number;
    assignmentsDeclined: number;
    blueCardsShown: number;
    cancellations: number;
    leagueMatchesCompleted: number;
    matchesCompleted: number;
    proposalsReceived: number;
    redCardsShown: number;
    replacements: number;
    yellowCardsShown: number;
  };
  verificationStatus: string;
};

export type DemoWorldV2ClubsRefereesChunk = {
  clubs: DemoWorldV2Club[];
  refereeAssignmentPreview: RefereeJson;
  refereeAssignmentsEnabled: true;
  referees: DemoWorldV2Referee[];
  relationships: Array<{
    clubId: string;
    id: string;
    refereeId?: string;
    status: "active";
    teamId?: string;
    type: "club_referee" | "club_team";
  }>;
};

export type DemoWorldV2ConfigurationRevision = {
  authoringMode: "ADVANCED" | "SIMPLE";
  blueEnabled: boolean;
  cardCodes: Array<"BLUE" | "RED" | "YELLOW">;
  checksum: string;
  effectiveScope: "future_only" | "future_stage";
  feeMode: "FIXED" | "FREE" | "NEGOTIABLE" | "VOLUNTEER";
  feePublicConsent: boolean;
  healthComplete: boolean;
  humanDocumentVerified: boolean;
  matchDurationMinutes: number;
  noShowLoserScore: number;
  noShowWinnerScore: number;
  pointsForDraw: number;
  pointsForLoss: number;
  pointsForWin: number;
  postponementResponseDeadlineHours: number;
  refereeRequiredBeforeReady: boolean;
  refereeUsage: "NONE" | "OPTIONAL" | "REQUIRED";
  revision: number;
  source: "COMPETITION_CONFIGURATION_CENTER_V1" | "LEAGUE_WIZARD_V2";
  sourcePresetId: string | null;
  status: "frozen";
  yellowThreshold: number;
};

export type DemoWorldV2ConfigurationChunk = {
  comparator: {
    baseRevision: 1;
    changedSections: string[];
    targetRevision: 2;
  };
  competitionName: "Liga Wave 5A";
  currentEditionRevision: 2;
  engineConsumption: {
    r5CatalogCodes: Array<"BLUE" | "RED" | "YELLOW">;
    refereePolicy: {
      feeMode: "FIXED";
      publicConsent: false;
      requiredBeforeReady: true;
      usage: "REQUIRED";
    };
  };
  futureCapabilities: {
    automaticRoundRobin: true;
    discipline: boolean;
    hybridPairing: false;
    manualAssistedPairing: false;
    payments: false;
    refereeAssignments: boolean;
    tournaments: false;
  };
  health: {
    complete: true;
    errors: 0;
    globallyDisabled: string[];
    status: "complete";
    warnings: number;
  };
  provenance: {
    authorityHash: string;
    database: "temporary-local-postgresql";
    operationReceipts: number;
    source: "simulation-world";
    verified: true;
  };
  readOnly: true;
  revisions: DemoWorldV2ConfigurationRevision[];
  transport: {
    methods: ["GET"];
    remoteWrites: 0;
  };
};

export type DemoWorldV2TournamentPlacement = {
  entryNumber: number;
  groupNumber: number;
  placementSource: "ENGINE" | "HYBRID_FILL" | "LOCKED" | "MANUAL";
  potNumber: number;
  slotNumber: number;
  team: { id: string; name: string };
};

export type DemoWorldV2TournamentOutcome = {
  algorithmVersion: string;
  groupSizeBalance: number;
  hardViolations: 0;
  inputChecksum: string;
  levelBalance: number;
  locks: Array<{
    entryNumber: number;
    groupNumber: number;
    slotNumber: number;
    team: { id: string; name: string };
  }>;
  manualOverrideCount: number;
  mode: "HYBRID" | "SEEDED_POTS";
  placements: DemoWorldV2TournamentPlacement[];
  potDistribution: number;
  qualityScore: number;
  resultChecksum: string;
  sameClubCollisions: number;
  seed: string;
  softScore: number;
  unassignedEntries: 0;
  version: number;
};

export type DemoWorldV2TournamentTeamRef = { id: string; name: string };

export type DemoWorldV2TournamentGroupMatch = {
  awayTeam: DemoWorldV2TournamentTeamRef;
  disciplineEvents: number;
  groupNumber: number;
  homeTeam: DemoWorldV2TournamentTeamRef;
  incidentType: "DISPUTED_CORRECTED" | "NONE" | "NO_SHOW" | "POSTPONED_RESCHEDULED" | "SUSPENDED_RESUMED";
  matchKey: string;
  refereeNumber?: number;
  roundNumber: number;
  scheduledStart: string;
  score?: { away: number; home: number };
  status: "OFFICIAL" | "SCHEDULED";
  venueLabel: string;
};

export type DemoWorldV2TournamentGroupStanding = {
  criteria: string[];
  draws: number;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  groupNumber: number;
  losses: number;
  played: number;
  points: number;
  position: number;
  qualificationZone: boolean;
  revision: number;
  status: "PROVISIONAL";
  team: DemoWorldV2TournamentTeamRef;
  wins: number;
};

export type DemoWorldV2TournamentGroupStage = {
  currentRound: 2;
  discipline: Array<{
    cardType: "RED" | "YELLOW";
    playerLabel: string;
    status: string;
    team: DemoWorldV2TournamentTeamRef;
  }>;
  fixtureCount: 24;
  groupCount: 4;
  incidents: {
    disputedCorrected: 1;
    noShow: 1;
    postponedRescheduled: 1;
    suspendedResumed: 1;
  };
  matches: DemoWorldV2TournamentGroupMatch[];
  officialMatches: 16;
  qualificationStatus: "PROVISIONAL";
  referees: { confirmedMatches: 12; unassignedMatches: 12 };
  roundCount: 3;
  sanctions: Array<{
    publicSummary: string;
    remainingUnits: number;
    status: string;
    team: DemoWorldV2TournamentTeamRef;
    unitType: string;
  }>;
  scheduledMatches: 8;
  standings: DemoWorldV2TournamentGroupStanding[];
};

export type DemoWorldV2TournamentCompletionProof = {
  bracketSize: 8;
  bracketSources: Array<{
    matchNumber: number;
    side: "A" | "B";
    slotKey: string;
    sourceGroupNumber: number;
    sourceKind: "GROUP_POSITION";
    sourcePosition: number;
    status: string;
  }>;
  bracketStatus: "PUBLISHED";
  canonicalMatches: 24;
  eliminated: 8;
  knockoutMatches: 0;
  officialMatches: 24;
  progressionEnabled: false;
  qualificationChecksum: string;
  qualificationStatus: "PUBLISHED";
  qualifiers: 8;
  standingSnapshots: 4;
};

export type DemoWorldV2TournamentKnockoutNode = {
  awayTeam: DemoWorldV2TournamentTeamRef;
  extraTime?: { away: number; home: number };
  homeTeam: DemoWorldV2TournamentTeamRef;
  loserTeamId: string;
  nodeKey: string;
  nodeOrder: number;
  referee?: { refereeNumber: number; status: "COMPLETED" | "CONFIRMED" };
  regulationScore: { away: number; home: number };
  resolutionKind: "ADMINISTRATIVE_DECISION" | "EXTRA_TIME" | "FORFEIT" | "NO_SHOW" | "PENALTY_SHOOTOUT" | "SPORTING_RESULT";
  roundCode: "FINAL" | "QUARTERFINAL" | "SEMIFINAL" | "THIRD_PLACE";
  roundOrder: number;
  scheduledStart: string;
  score: { away: number; home: number };
  shootout?: { away: number; home: number };
  status: "OFFICIAL";
  venueLabel: string;
  winnerTeamId: string;
};

export type DemoWorldV2TournamentKnockout = {
  authority: {
    activeMatches: 8;
    advanceDecisions: number;
    completionSnapshots: 2;
    correction: {
      nodeHistoryRetained: true;
      oldContextRetired: true;
      oldMatchRetired: true;
      replacementCreated: true;
    };
    dependencyImpacts: 3;
    historicalMatches: 9;
    integrity: {
      billingUnchanged: true;
      conductUnchanged: true;
      ratingV2Unchanged: true;
      rewardsUnchanged: true;
    };
    invalidations: 1;
    noShowResolutionLinked: true;
    penaltySeparation: {
      groupStandingsUnchanged: true;
      shootoutGoalsAddedToSportingScore: false;
    };
    readModelCanonical: true;
    retiredMatches: 1;
  };
  discipline: {
    blockedFromSemifinal: true;
    playerLabel: string;
    ratingChanged: false;
    sanctionApplies: true;
    team: DemoWorldV2TournamentTeamRef;
  };
  format: "SINGLE_MATCH_KNOCKOUT";
  nodes: DemoWorldV2TournamentKnockoutNode[];
  organizerDesk: {
    bracketHealth: "HEALTHY";
    completionHealth: "COMPLETE";
    correctionsWithImpact: 1;
    nextAction: "TOURNAMENT_LOCKED";
    pendingResults: 0;
    unassignedFinals: 0;
    unresolvedNodes: 0;
    unscheduledMatches: 0;
  };
  podium: {
    champion: DemoWorldV2TournamentTeamRef;
    fourthPlace: DemoWorldV2TournamentTeamRef;
    runnerUp: DemoWorldV2TournamentTeamRef;
    thirdPlace: DemoWorldV2TournamentTeamRef;
  };
  referees: {
    final: { refereeNumber: number; status: "confirmed" };
    semifinalReplacement: {
      lineageLinked: true;
      originalRefereeNumber: number;
      originalStatus: "replaced";
      replacementRefereeNumber: number;
      replacementStatus: "confirmed";
    };
  };
  rounds: Array<{
    code: DemoWorldV2TournamentKnockoutNode["roundCode"];
    label: string;
    matches: number;
  }>;
  status: "LOCKED";
  teamJourneys: Array<{
    finalPosition: number | null;
    path: string[];
    status: "CHAMPION" | "ELIMINATED" | "FOURTH_PLACE" | "RUNNER_UP" | "THIRD_PLACE";
    team: DemoWorldV2TournamentTeamRef;
  }>;
  thirdPlaceEnabled: true;
};

export type DemoWorldV2TournamentChunk = {
  comparison: {
    movedTeams: Array<{
      fromGroup: number;
      team: { id: string; name: string };
      toGroup: number;
    }>;
    qualityDelta: number;
    retainedLocks: number;
  };
  competition: {
    acceptedParticipants: 16;
    groupCount: 4;
    name: "COPA BARRIOS IQ 2027";
    planStatus: "published";
    potCount: 4;
    publishedRevision: 5;
    slug: "copa-barrios-iq-2027";
  };
  conflict: {
    attempts: number;
    constraintTypes: string[];
    errorCode: "DRAW_UNSATISFIABLE";
    explanation: string;
    reasonCode: "GROUP_CONSTRAINTS_UNSATISFIABLE";
    suggestions: string[];
  };
  constraints: Array<{
    reason: string;
    strength: "HARD" | "SOFT";
    type: "POT_DISTRIBUTION" | "SAME_CLUB_AVOIDANCE" | "TEAM_LEVEL_BALANCE";
    weight: number;
  }>;
  completionProof: DemoWorldV2TournamentCompletionProof;
  drawOutcomes: [DemoWorldV2TournamentOutcome, DemoWorldV2TournamentOutcome];
  groupStage: DemoWorldV2TournamentGroupStage;
  knockout: DemoWorldV2TournamentKnockout;
  nextPhase: {
    bracketProgression: true;
    knockoutMatches: 8;
    message: "Torneo completado y cuadro bloqueado por PostgreSQL.";
    tournamentMatches: 32;
  };
  provenance: {
    authorityHash: string;
    database: "temporary-local-postgresql";
    operationReceipts: number;
    rpcFamilies: ["R1", "CONFIGURATION_CENTER", "ENTRIES", "R4B", "R4C", "R4D", "R5", "REFEREES", "R6A_DRAW_ENGINE", "R6B_GROUP_STAGE", "R6C_KNOCKOUT"];
    source: "simulation-world";
    verified: true;
  };
  readOnly: true;
  transport: {
    methods: ["GET"];
    remoteWrites: 0;
  };
};

export type DemoWorldV2PublicCompetitionView = {
  bracket: Record<string, unknown> | null;
  calendar: Record<string, unknown>;
  hub: Record<string, unknown>;
  slug: string;
  standings: Record<string, unknown>;
};

export type DemoWorldV2PublicCompetitionsChunk = {
  directory: Record<string, unknown>;
  league: DemoWorldV2PublicCompetitionView;
  organizerPrivate: {
    hub: Record<string, unknown>;
    slug: "liga-privada-organizador-demo";
  };
  operationReceipts: number;
  privacy: {
    containsContactData: false;
    containsOwnerIdentity: false;
    containsPrivateReason: false;
    containsRequestMessage: false;
  };
  provenance: {
    authorityHash: string;
    database: "temporary-local-postgresql";
    rpcFamilies: ["PUBLICATION", "REGISTRATION_REQUESTS", "WAITLIST", "PUBLIC_READ_MODELS"];
    source: "simulation-world";
    verified: true;
  };
  readOnly: true;
  remoteWrites: 0;
  requests: Array<{
    entryCreated: boolean;
    status: "accepted" | "rejected" | "waitlisted" | "withdrawn";
    team: { name: string };
    waitlistPosition: number | null;
  }>;
  tournament: DemoWorldV2PublicCompetitionView;
  transport: {
    methods: ["GET"];
    remoteWrites: 0;
  };
  unlisted: DemoWorldV2PublicCompetitionView;
};

export type DemoWorldV2Snapshot = {
  activity: DemoWorldActivityChunk;
  clubsReferees: DemoWorldV2ClubsRefereesChunk;
  competitions: DemoWorldV2CompetitionChunk;
  configuration: DemoWorldV2ConfigurationChunk;
  core: DemoWorldCoreChunk;
  manifest: DemoWorldV2Manifest;
  matches: DemoWorldMatchesChunk;
  organizerBilling: DemoWorldV2OrganizerBillingChunk;
  players: DemoWorldPlayersChunk;
  publicCompetitions: DemoWorldV2PublicCompetitionsChunk;
  tournament: DemoWorldV2TournamentChunk;
};

export function computeDemoWorldV2Standings(
  entries: readonly DemoWorldV2LeagueEntry[],
  matches: readonly DemoWorldV2LeagueMatch[],
  teamName: (teamId: string) => string,
): DemoWorldV2StandingRow[] {
  const rows = new Map(entries.map((entry) => [entry.id, {
    draws: 0,
    effectivePoints: 0,
    entryId: entry.id,
    goalDifference: 0,
    goalsAgainst: 0,
    goalsFor: 0,
    losses: 0,
    played: 0,
    position: 0,
    team: { displayName: teamName(entry.teamId), id: entry.teamId },
    teamId: entry.teamId,
    wins: 0,
  }]));
  for (const match of matches) {
    const home = rows.get(match.homeEntryId);
    const away = rows.get(match.awayEntryId);
    if (!home || !away) continue;
    home.played += 1;
    away.played += 1;
    home.goalsFor += match.result.home;
    home.goalsAgainst += match.result.away;
    away.goalsFor += match.result.away;
    away.goalsAgainst += match.result.home;
    if (match.result.home === match.result.away) {
      home.draws += 1;
      away.draws += 1;
      home.effectivePoints += 1;
      away.effectivePoints += 1;
    } else if (match.result.home > match.result.away) {
      home.wins += 1;
      away.losses += 1;
      home.effectivePoints += 3;
    } else {
      away.wins += 1;
      home.losses += 1;
      away.effectivePoints += 3;
    }
  }
  return [...rows.values()]
    .map((row) => ({ ...row, goalDifference: row.goalsFor - row.goalsAgainst }))
    .sort((left, right) => right.effectivePoints - left.effectivePoints
      || right.goalDifference - left.goalDifference
      || right.goalsFor - left.goalsFor
      || right.wins - left.wins
      || left.team.displayName.localeCompare(right.team.displayName, "es"))
    .map((row, index) => ({ ...row, position: index + 1 }));
}

export function demoWorldV2IntegrityErrors(snapshot: DemoWorldV2Snapshot): string[] {
  const errors = demoWorldIntegrityErrors(snapshot as unknown as DemoWorldSnapshot);
  const competition = snapshot.competitions;
  const configuration = snapshot.configuration;
  const publicCompetitions = snapshot.publicCompetitions;
  const organizerBilling = snapshot.organizerBilling;
  const teamIds = new Set(snapshot.core.teams.map(({ id }) => id));
  const playerIds = new Set(snapshot.players.players.map(({ id }) => id));
  const entryIds = new Set(competition.entries.map(({ id }) => id));
  const roundIds = new Set(competition.rounds.map(({ id }) => id));
  const canonicalIds = new Set<string>();

  const billingScenarioIds = organizerBilling.scenarios.map(({ id }) => id);
  const billingPlanCodes = organizerBilling.catalog.plans.map(({ planCode }) => planCode);
  if (!organizerBilling.readOnly
      || organizerBilling.transport.remoteWrites !== 0
      || organizerBilling.transport.methods.join(",") !== "GET"
      || !organizerBilling.provenance.verified
      || organizerBilling.provenance.authority !== "canonical-read-model-shape"
      || organizerBilling.catalog.liveCheckoutEnabled
      || organizerBilling.catalog.status !== "CATALOG_AVAILABLE") {
    errors.push("Demo World V2.8 organizer billing authority is invalid");
  }
  if (billingScenarioIds.join(",") !== "club_partner,team_active,club_active,past_due_grace,canceled_continuity"
      || snapshot.manifest.counts.organizerBillingScenarios !== 5
      || billingPlanCodes.join(",") !== "CLUB_PARTNER,CLUB_ORGANIZER,TEAM_ORGANIZER_PRO") {
    errors.push("Demo World V2.8 organizer billing scenarios are incomplete");
  }
  const scenarioById = new Map(organizerBilling.scenarios.map((scenario) => [scenario.id, scenario]));
  if (scenarioById.get("club_partner")?.accessStatus !== "active"
      || scenarioById.get("team_active")?.accountStatus !== "active"
      || scenarioById.get("club_active")?.accountStatus !== "active"
      || scenarioById.get("past_due_grace")?.accessStatus !== "grace"
      || scenarioById.get("past_due_grace")?.accountStatus !== "past_due"
      || scenarioById.get("canceled_continuity")?.accessStatus !== "continuity"
      || scenarioById.get("canceled_continuity")?.accountStatus !== "canceled") {
    errors.push("Demo World V2.8 organizer billing lifecycle is invalid");
  }
  if (organizerBilling.catalog.plans.some(({ checkoutAvailable, prices }) => checkoutAvailable || prices.length)
      || Object.values(organizerBilling.privacy).some(Boolean)
      || /"(?:cus|sub|price|prod)_[A-Za-z0-9_]+"|@example|\+34/i.test(JSON.stringify(organizerBilling))) {
    errors.push("Demo World V2.8 organizer billing leaked commercial or private data");
  }

  if (competition.entries.length !== 6) errors.push("League must have exactly 6 entries");
  if (competition.delegates.length !== 6) errors.push("League must have exactly 6 delegates");
  if (competition.rosters.length !== 6) errors.push("League must have exactly 6 rosters");
  if (competition.rounds.length !== 5) errors.push("League must have exactly 5 rounds");
  if (competition.matches.length !== 15) errors.push("League must have exactly 15 canonical matches");
  if (snapshot.clubsReferees.clubs.length < 3) errors.push("Demo World V2 requires at least 3 clubs");
  if (snapshot.clubsReferees.referees.length < 8) errors.push("Demo World V2 requires at least 8 referees");
  if (!snapshot.clubsReferees.refereeAssignmentsEnabled
      || !competition.competition.refereeAssignmentsEnabled) {
    errors.push("Demo World V2.2 referee assignments must be enabled");
  }
  if (configuration.revisions.length !== 2
      || configuration.currentEditionRevision !== 2
      || configuration.transport.remoteWrites !== 0
      || configuration.transport.methods.join(",") !== "GET"
      || !configuration.readOnly
      || !configuration.provenance.verified
      || configuration.provenance.authorityHash !== competition.provenance.authorityHash) {
    errors.push("Demo World V2.3 configuration authority is invalid");
  }
  const [standardConfiguration, customConfiguration] = configuration.revisions;
  if (!standardConfiguration || !customConfiguration
      || standardConfiguration.authoringMode !== "SIMPLE"
      || standardConfiguration.matchDurationMinutes !== 70
      || standardConfiguration.pointsForWin !== 3
      || standardConfiguration.yellowThreshold !== 3
      || standardConfiguration.blueEnabled
      || standardConfiguration.refereeUsage !== "OPTIONAL"
      || standardConfiguration.feeMode !== "NEGOTIABLE"
      || customConfiguration.authoringMode !== "ADVANCED"
      || customConfiguration.matchDurationMinutes !== 80
      || customConfiguration.pointsForWin !== 2
      || customConfiguration.yellowThreshold !== 4
      || !customConfiguration.blueEnabled
      || customConfiguration.refereeUsage !== "REQUIRED"
      || customConfiguration.feeMode !== "FIXED"
      || customConfiguration.feePublicConsent
      || !configuration.comparator.changedSections.includes("discipline")
      || !configuration.comparator.changedSections.includes("referees")) {
    errors.push("Demo World V2.3 configuration comparison is invalid");
  }
  if (!configuration.health.complete
      || configuration.health.errors !== 0
      || configuration.engineConsumption.r5CatalogCodes.join(",") !== "YELLOW,RED,BLUE"
      || configuration.revisions.some(({ healthComplete, humanDocumentVerified }) => (
        !healthComplete || !humanDocumentVerified
      ))) {
    errors.push("Demo World V2.3 health or engine consumption is invalid");
  }
  if (configuration.futureCapabilities.payments
      || configuration.futureCapabilities.tournaments
      || configuration.futureCapabilities.manualAssistedPairing
      || configuration.futureCapabilities.hybridPairing
      || !configuration.futureCapabilities.automaticRoundRobin) {
    errors.push("Demo World V2.3 exposes an unavailable competition capability");
  }
  if (JSON.stringify(configuration).includes("fixedCents")) {
    errors.push("Demo World V2.3 leaked a private referee fee");
  }
  const directoryItems = Array.isArray(publicCompetitions.directory.items)
    ? publicCompetitions.directory.items as Array<Record<string, unknown>>
    : [];
  const directorySlugs = directoryItems.map((item) => String(
    (item.publication as Record<string, unknown> | undefined)?.slug ?? "",
  ));
  const registrationStatuses = new Map(publicCompetitions.requests.map((request) => [request.status, request]));
  if (!publicCompetitions.readOnly
      || publicCompetitions.remoteWrites !== 0
      || publicCompetitions.transport.remoteWrites !== 0
      || publicCompetitions.transport.methods.join(",") !== "GET"
      || publicCompetitions.provenance.authorityHash !== competition.provenance.authorityHash
      || publicCompetitions.operationReceipts < 16) {
    errors.push("Demo World V2.7 public competition authority is invalid");
  }
  if (directoryItems.length !== 2
      || !directorySlugs.includes("liga-publica-wave-7a")
      || !directorySlugs.includes("copa-barrios-iq-2027")
      || directorySlugs.includes("copa-enlace-demo")
      || directorySlugs.includes("liga-privada-organizador-demo")) {
    errors.push("Demo World V2.7 public directory visibility is invalid");
  }
  if (registrationStatuses.get("accepted")?.entryCreated !== true
      || registrationStatuses.get("waitlisted")?.entryCreated !== false
      || !registrationStatuses.get("waitlisted")?.waitlistPosition
      || registrationStatuses.get("rejected")?.entryCreated !== false
      || registrationStatuses.get("withdrawn")?.entryCreated !== false) {
    errors.push("Demo World V2.7 registration stories are invalid");
  }
  const publicPublication = (publicCompetitions.league.hub.publication ?? {}) as Record<string, unknown>;
  const tournamentPublication = (publicCompetitions.tournament.hub.publication ?? {}) as Record<string, unknown>;
  const unlistedPublication = (publicCompetitions.unlisted.hub.publication ?? {}) as Record<string, unknown>;
  const privatePublication = (publicCompetitions.organizerPrivate.hub.publication ?? {}) as Record<string, unknown>;
  if (publicPublication.visibility !== "public" || publicPublication.status !== "published"
      || tournamentPublication.visibility !== "public" || tournamentPublication.status !== "published"
      || unlistedPublication.visibility !== "unlisted" || unlistedPublication.status !== "published"
      || privatePublication.visibility !== "private" || privatePublication.status !== "draft") {
    errors.push("Demo World V2.7 public competition lifecycle is invalid");
  }
  if (Object.values(publicCompetitions.privacy).some(Boolean)) {
    errors.push("Demo World V2.7 public competition privacy diagnostics failed");
  }
  const publicCompetitionPayload: Record<string, unknown> = { ...publicCompetitions };
  delete publicCompetitionPayload.privacy;
  if (/@example|\+34|privateReason|requestedBy|ownerId|owner_id|"message"/i.test(
    JSON.stringify(publicCompetitionPayload),
  )) {
    errors.push("Demo World V2.7 public competition payload leaked private data");
  }
  const tournament = snapshot.tournament;
  if (tournament.competition.name !== "COPA BARRIOS IQ 2027"
      || tournament.competition.acceptedParticipants !== 16
      || tournament.competition.groupCount !== 4
      || tournament.competition.potCount !== 4
      || tournament.competition.planStatus !== "published"
      || tournament.competition.publishedRevision !== 5
      || !tournament.readOnly
      || tournament.transport.remoteWrites !== 0
      || tournament.transport.methods.join(",") !== "GET"
      || tournament.provenance.authorityHash !== competition.provenance.authorityHash) {
    errors.push("Demo World V2.5 Tournament authority is invalid");
  }
  if (tournament.drawOutcomes.length !== 2
      || tournament.drawOutcomes[0]?.mode !== "SEEDED_POTS"
      || tournament.drawOutcomes[1]?.mode !== "HYBRID") {
    errors.push("Demo World V2.4 must expose automatic and hybrid outcomes");
  }
  for (const outcome of tournament.drawOutcomes) {
    if (outcome.placements.length !== 16
        || new Set(outcome.placements.map(({ team }) => team.id)).size !== 16
        || outcome.hardViolations !== 0
        || outcome.unassignedEntries !== 0
        || outcome.sameClubCollisions !== 0
        || !/^[0-9a-f]{64}$/.test(outcome.inputChecksum)
        || !/^[0-9a-f]{64}$/.test(outcome.resultChecksum)
        || outcome.seed.length < 8) {
      errors.push(`Demo World V2.4 draw revision ${outcome.version} is invalid`);
    }
    for (let groupNumber = 1; groupNumber <= 4; groupNumber += 1) {
      const group = outcome.placements.filter((placement) => placement.groupNumber === groupNumber);
      if (group.length !== 4 || new Set(group.map(({ potNumber }) => potNumber)).size !== 4) {
        errors.push(`Demo World V2.4 group ${groupNumber} violates pot distribution`);
      }
    }
  }
  if (tournament.drawOutcomes[0]?.locks.length !== 0
      || tournament.drawOutcomes[1]?.locks.length !== 2
      || tournament.drawOutcomes[1]?.manualOverrideCount !== 2
      || tournament.comparison.retainedLocks !== 2
      || tournament.comparison.movedTeams.length === 0) {
    errors.push("Demo World V2.4 hybrid comparison is invalid");
  }
  if (tournament.conflict.errorCode !== "DRAW_UNSATISFIABLE"
      || tournament.conflict.reasonCode !== "GROUP_CONSTRAINTS_UNSATISFIABLE"
      || !tournament.conflict.constraintTypes.includes("FIXED_POSITION")
      || tournament.conflict.suggestions.length < 2) {
    errors.push("Demo World V2.4 unsatisfiable scenario is invalid");
  }
  const groupStage = tournament.groupStage;
  if (groupStage.currentRound !== 2
      || groupStage.roundCount !== 3
      || groupStage.groupCount !== 4
      || groupStage.fixtureCount !== 24
      || groupStage.matches.length !== 24
      || new Set(groupStage.matches.map(({ matchKey }) => matchKey)).size !== 24
      || groupStage.officialMatches !== 16
      || groupStage.scheduledMatches !== 8
      || groupStage.standings.length !== 16
      || groupStage.discipline.length !== 4
      || groupStage.sanctions.length < 1
      || groupStage.referees.confirmedMatches !== 12
      || groupStage.referees.unassignedMatches !== 12
      || groupStage.qualificationStatus !== "PROVISIONAL") {
    errors.push("Demo World V2.5 Group Stage public graph is invalid");
  }
  if (groupStage.matches.filter(({ status }) => status === "OFFICIAL").length !== 16
      || groupStage.matches.filter(({ status }) => status === "SCHEDULED").length !== 8
      || groupStage.matches.some((match) => (
        !teamIds.has(match.homeTeam.id)
        || !teamIds.has(match.awayTeam.id)
        || match.homeTeam.id === match.awayTeam.id
        || (match.status === "OFFICIAL") !== Boolean(match.score)
      ))) {
    errors.push("Demo World V2.5 match tracking is invalid");
  }
  for (let groupNumber = 1; groupNumber <= 4; groupNumber += 1) {
    const groupMatches = groupStage.matches.filter((match) => match.groupNumber === groupNumber);
    const groupStandings = groupStage.standings.filter((row) => row.groupNumber === groupNumber);
    if (groupMatches.length !== 6
        || new Set(groupMatches.map(({ roundNumber }) => roundNumber)).size !== 3
        || [1, 2, 3].some((roundNumber) => (
          groupMatches.filter((match) => match.roundNumber === roundNumber).length !== 2
        ))
        || groupStandings.length !== 4
        || groupStandings.some((row) => (
          !teamIds.has(row.team.id) || row.played !== 2 || row.status !== "PROVISIONAL"
        ))) {
      errors.push(`Demo World V2.5 Group ${groupNumber} tracking is invalid`);
    }
  }
  if (Object.values(groupStage.incidents).some((count) => count !== 1)
      || groupStage.discipline.some(({ team }) => !teamIds.has(team.id))
      || groupStage.sanctions.some(({ team }) => !teamIds.has(team.id))) {
    errors.push("Demo World V2.5 exception or discipline projection is invalid");
  }
  const completion = tournament.completionProof;
  if (completion.canonicalMatches !== 24
      || completion.officialMatches !== 24
      || completion.standingSnapshots !== 4
      || completion.qualificationStatus !== "PUBLISHED"
      || completion.qualifiers !== 8
      || completion.eliminated !== 8
      || completion.bracketStatus !== "PUBLISHED"
      || completion.bracketSize !== 8
      || completion.bracketSources.length !== 8
      || completion.knockoutMatches !== 0
      || completion.progressionEnabled
      || !/^[0-9a-f]{64}$/.test(completion.qualificationChecksum)
      || completion.bracketSources.some((slot) => (
        slot.sourceKind !== "GROUP_POSITION"
        || slot.sourceGroupNumber < 1
        || slot.sourceGroupNumber > 4
        || slot.sourcePosition < 1
        || slot.sourcePosition > 2
      ))) {
    errors.push("Demo World V2.5 completion proof is invalid");
  }
  const knockout = tournament.knockout;
  if (knockout.status !== "LOCKED"
      || knockout.format !== "SINGLE_MATCH_KNOCKOUT"
      || !knockout.thirdPlaceEnabled
      || knockout.nodes.length !== 8
      || new Set(knockout.nodes.map(({ nodeKey }) => nodeKey)).size !== 8
      || knockout.rounds.length !== 4
      || knockout.teamJourneys.length !== 8
      || new Set(knockout.teamJourneys.map(({ team }) => team.id)).size !== 8
      || knockout.organizerDesk.bracketHealth !== "HEALTHY"
      || knockout.organizerDesk.completionHealth !== "COMPLETE"
      || knockout.organizerDesk.unresolvedNodes !== 0
      || knockout.organizerDesk.unscheduledMatches !== 0
      || knockout.organizerDesk.pendingResults !== 0) {
    errors.push("Demo World V2.6 knockout public graph is invalid");
  }
  const knockoutRoundCounts = new Map(knockout.rounds.map(({ code, matches }) => [code, matches]));
  if (knockoutRoundCounts.get("QUARTERFINAL") !== 4
      || knockoutRoundCounts.get("SEMIFINAL") !== 2
      || knockoutRoundCounts.get("FINAL") !== 1
      || knockoutRoundCounts.get("THIRD_PLACE") !== 1
      || knockout.nodes.filter(({ roundCode }) => roundCode === "QUARTERFINAL").length !== 4
      || knockout.nodes.filter(({ roundCode }) => roundCode === "SEMIFINAL").length !== 2
      || knockout.nodes.filter(({ roundCode }) => roundCode === "FINAL").length !== 1
      || knockout.nodes.filter(({ roundCode }) => roundCode === "THIRD_PLACE").length !== 1
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "EXTRA_TIME")
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "PENALTY_SHOOTOUT")
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "FORFEIT" || resolutionKind === "NO_SHOW")
      || knockout.nodes.some((node) => (
        !teamIds.has(node.homeTeam.id)
        || !teamIds.has(node.awayTeam.id)
        || !teamIds.has(node.winnerTeamId)
        || !teamIds.has(node.loserTeamId)
        || node.homeTeam.id === node.awayTeam.id
        || node.winnerTeamId === node.loserTeamId
      ))) {
    errors.push("Demo World V2.6 knockout match story is invalid");
  }
  const podiumIds = [
    knockout.podium.champion.id,
    knockout.podium.runnerUp.id,
    knockout.podium.thirdPlace.id,
    knockout.podium.fourthPlace.id,
  ];
  if (new Set(podiumIds).size !== 4
      || podiumIds.some((teamId) => !teamIds.has(teamId))
      || knockout.teamJourneys.filter(({ status }) => status === "CHAMPION").length !== 1
      || knockout.teamJourneys.filter(({ status }) => status === "RUNNER_UP").length !== 1
      || knockout.teamJourneys.filter(({ status }) => status === "THIRD_PLACE").length !== 1
      || !knockout.discipline.sanctionApplies
      || !knockout.discipline.blockedFromSemifinal
      || knockout.discipline.ratingChanged
      || !knockout.referees.semifinalReplacement.lineageLinked
      || knockout.referees.semifinalReplacement.originalStatus !== "replaced"
      || knockout.referees.semifinalReplacement.replacementStatus !== "confirmed"
      || knockout.referees.final.status !== "confirmed") {
    errors.push("Demo World V2.6 linked tournament stories are invalid");
  }
  if (knockout.authority.activeMatches !== 8
      || knockout.authority.historicalMatches !== 9
      || knockout.authority.retiredMatches !== 1
      || knockout.authority.invalidations !== 1
      || knockout.authority.dependencyImpacts !== 3
      || knockout.authority.completionSnapshots !== 2
      || !knockout.authority.correction.oldMatchRetired
      || !knockout.authority.correction.oldContextRetired
      || !knockout.authority.correction.replacementCreated
      || !knockout.authority.correction.nodeHistoryRetained
      || !knockout.authority.noShowResolutionLinked
      || !knockout.authority.penaltySeparation.groupStandingsUnchanged
      || knockout.authority.penaltySeparation.shootoutGoalsAddedToSportingScore
      || !knockout.authority.readModelCanonical
      || Object.values(knockout.authority.integrity).some((valid) => !valid)) {
    errors.push("Demo World V2.6 knockout authority proof is invalid");
  }
  if (tournament.nextPhase.tournamentMatches !== 32
      || !tournament.nextPhase.bracketProgression
      || tournament.nextPhase.knockoutMatches !== 8
      || tournament.nextPhase.message !== "Torneo completado y cuadro bloqueado por PostgreSQL.") {
    errors.push("Demo World V2.6 knockout completion state is invalid");
  }
  if (snapshot.manifest.counts.tournaments !== 1
      || snapshot.manifest.counts.publicCompetitions !== 4
      || snapshot.manifest.counts.registrationRequests !== 4
      || snapshot.manifest.counts.tournamentGroups !== 4
      || snapshot.manifest.counts.tournamentDrawRevisions !== 5
      || snapshot.manifest.counts.canonicalMatches !== 48
      || snapshot.manifest.counts.rounds !== 12) {
    errors.push("Demo World V2.6 Tournament manifest counts are invalid");
  }
  const assignmentItems = Array.isArray(snapshot.clubsReferees.refereeAssignmentPreview.items)
    ? snapshot.clubsReferees.refereeAssignmentPreview.items as Record<string, unknown>[]
    : [];
  const assignmentCounts = assignmentItems.reduce<Record<string, number>>((counts, item) => {
    const status = String(item.status ?? "");
    counts[status] = (counts[status] ?? 0) + 1;
    return counts;
  }, {});
  if (assignmentItems.length !== 16 || assignmentCounts.completed !== 13
      || assignmentCounts.declined !== 1 || assignmentCounts.cancelled !== 1
      || assignmentCounts.replaced !== 1) {
    errors.push("Demo World V2.2 assignment distribution is invalid");
  }
  if (JSON.stringify(snapshot.clubsReferees.refereeAssignmentPreview).includes("privateTerms")) {
    errors.push("Demo World V2.2 leaked private referee terms");
  }

  const discipline = competition.disciplinePreview;
  const disciplineEvents = disciplineArray(discipline.events);
  const disciplineSanctions = disciplineArray(discipline.sanctions);
  const disciplineService = disciplineArray(discipline.serviceEvents);
  const disciplineCards = disciplineEvents.reduce<Record<string, number>>((counts, event) => {
    const code = disciplineText(event.cardTypeCode);
    counts[code] = (counts[code] ?? 0) + 1;
    return counts;
  }, {});
  if (disciplineEvents.length !== 20 || disciplineCards.YELLOW !== 16
      || disciplineCards.RED !== 2 || disciplineCards.BLUE !== 2) {
    errors.push("Demo World V2.1 discipline card distribution is invalid");
  }
  if (disciplineSanctions.length !== 4 || disciplineService.length !== 2) {
    errors.push("Demo World V2.1 discipline sanctions or service history are invalid");
  }
  const eligibility = disciplineArray(discipline.eligibilityTimeline);
  if (JSON.stringify(eligibility.map((item) => disciplineText(item.selectedSlot)))
      !== JSON.stringify(["primary", "primary", "primary", "alternate", "primary"])) {
    errors.push("Demo World V2.1 eligibility chronology is invalid");
  }
  if (disciplineNumber(disciplineRecord(discipline.health).pendingAppeals) !== 0
      || disciplineArray(discipline.appeals).length !== 0) {
    errors.push("Public Demo discipline must not expose appeal records");
  }

  for (const entry of competition.entries) {
    if (!teamIds.has(entry.teamId)) errors.push(`Unknown League team ${entry.teamId}`);
    const roster = competition.rosters.find(({ entryId, id }) => id === entry.rosterId && entryId === entry.id);
    if (!roster) errors.push(`Missing roster for ${entry.id}`);
  }
  for (const roster of competition.rosters) {
    for (const playerId of roster.playerIds) if (!playerIds.has(playerId)) errors.push(`Unknown roster player ${playerId}`);
  }
  for (const match of competition.matches) {
    if (!entryIds.has(match.homeEntryId) || !entryIds.has(match.awayEntryId)) errors.push(`Unknown entry in ${match.id}`);
    if (!roundIds.has(match.roundId)) errors.push(`Unknown round in ${match.id}`);
    if (canonicalIds.has(match.canonicalMatchId)) errors.push(`Duplicate CanonicalMatch ${match.canonicalMatchId}`);
    canonicalIds.add(match.canonicalMatchId);
    const homeGoals = match.scorers.filter(({ side }) => side === "home").reduce((sum, scorer) => sum + scorer.goals, 0);
    const awayGoals = match.scorers.filter(({ side }) => side === "away").reduce((sum, scorer) => sum + scorer.goals, 0);
    if (homeGoals !== match.result.home || awayGoals !== match.result.away) errors.push(`Scorer mismatch in ${match.id}`);
    for (const scorer of match.scorers) if (!playerIds.has(scorer.playerId)) errors.push(`Unknown scorer ${scorer.playerId}`);
    const matchDiscipline = competition.matchDisciplinePreviews[match.id];
    const refereePreview = competition.refereeAssignmentPreviews[match.id];
    if (!refereePreview) errors.push(`Missing referee assignment preview for ${match.id}`);
    if (!matchDiscipline) errors.push(`Missing discipline preview for ${match.id}`);
    else if (disciplineArray(matchDiscipline.events).some((event) => disciplineText(event.canonicalMatchId) !== match.canonicalMatchId)) {
      errors.push(`Discipline event belongs to another match in ${match.id}`);
    } else {
      const matchAssignments = Array.isArray(refereePreview?.items)
        ? refereePreview.items as Record<string, unknown>[]
        : [];
      const wasRefereed = matchAssignments.some((assignment) => ["completed", "replaced"].includes(String(assignment.status ?? "")));
      if (wasRefereed && disciplineArray(matchDiscipline.events).some((event) => !disciplineText(event.refereeAssignmentId))) {
        errors.push(`R5 event lacks referee Assignment lineage in ${match.id}`);
      }
    }
  }
  for (const round of competition.rounds) {
    if (round.matchIds.length !== 3) errors.push(`${round.id} must contain 3 matches`);
    for (const matchId of round.matchIds) if (!competition.matches.some(({ id }) => id === matchId)) errors.push(`Unknown round match ${matchId}`);
  }
  const oracle = computeDemoWorldV2Standings(
    competition.entries,
    competition.matches,
    (teamId) => snapshot.core.teams.find(({ id }) => id === teamId)?.name ?? teamId,
  );
  if (JSON.stringify(oracle) !== JSON.stringify(competition.standingSnapshot.rows)) {
    errors.push("StandingSnapshot differs from the independent oracle");
  }
  const forbidden = demoWorldForbiddenPaths({ clubsReferees: snapshot.clubsReferees, competitions: snapshot.competitions });
  errors.push(...forbidden.map((path) => `Forbidden public field: ${path}`));
  return [...new Set(errors)];
}

export function assertDemoWorldV2Snapshot(snapshot: DemoWorldV2Snapshot) {
  if (snapshot.manifest.version !== DEMO_WORLD_V2_VERSION) throw new Error("Unsupported Demo World V2 version");
  if (snapshot.manifest.seed !== DEMO_WORLD_V2_SEED) throw new Error("Unexpected Demo World V2 seed");
  if (snapshot.manifest.mode !== DEMO_WORLD_MODE) throw new Error("Demo World V2 is not read-only");
  const errors = demoWorldV2IntegrityErrors(snapshot);
  if (errors.length) throw new Error(`Invalid Demo World V2 snapshot:\n${errors.join("\n")}`);
  return snapshot;
}
