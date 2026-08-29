import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

export const DEMO_WORLD_V2_AUTHORITY_PROOF_VERSION = 10 as const;

export type DemoWorldV2AuthorityProofOrganizerBillingScenario = {
  accessStatus: "active" | "continuity" | "grace" | "pending";
  accountStatus: "active" | "canceled" | "checkout_pending" | "past_due";
  billingInterval: "month" | "year" | null;
  continuityUntil: string | null;
  creationAllowed: boolean;
  graceEndsAt: string | null;
  id: "club_annual_active" | "club_monthly_active" | "club_partner" | "club_canceled_continuity"
    | "team_active" | "team_checkout_pending" | "team_past_due_grace";
  note: string;
  organizerKind: "CLUB" | "TEAM";
  organizerName: string;
  planCode: "CLUB_ORGANIZER" | "CLUB_PARTNER" | "TEAM_ORGANIZER_PRO";
  renewalAt: string | null;
};

export type DemoWorldV2AuthorityProofOrganizerBilling = {
  catalogMappings: 4;
  liveCheckoutEnabled: false;
  liveMappings: 0;
  livePortalEnabled: false;
  operationReceipts: number;
  privacy: {
    containsPii: false;
    containsPriceId: false;
    containsStripeCustomerId: false;
    containsStripeSubscriptionId: false;
  };
  readModelVerified: true;
  remoteWrites: 0;
  scenarios: DemoWorldV2AuthorityProofOrganizerBillingScenario[];
  stripeEvents: number;
  testRuntimeReady: true;
};

export type DemoWorldV3AuthorityProofOrganizerAccessScenario = {
  applicationStatus: "approved" | "approved_interest" | "rejected" | "withdrawn";
  checkoutAvailable: false;
  decisionCode: string | null;
  decisionType: "APPROVED" | "APPROVED_INTEREST" | "REJECTED" | null;
  firstCompetition: {
    canonicalMatches: number;
    name: string;
    status: "PUBLIC_ACTIVE";
    type: "LEAGUE";
    visibility: "public";
  } | null;
  grant: {
    source: "PARTNERSHIP" | "PRIVATE_BETA";
    status: "active";
    validUntil: string | null;
  } | null;
  history: string[];
  id: "club_paid_interest" | "club_partner_approved" | "club_withdrawn"
    | "team_needs_information_beta" | "team_owner_transfer" | "team_rejected";
  onboarding: {
    completedCheckpoints: number;
    nextAction: string;
    status: "active" | "completed";
    totalCheckpoints: 10;
  } | null;
  organizerKind: "CLUB" | "TEAM";
  organizerName: string;
  ownerTransferred: boolean;
  planCode: "CLUB_ORGANIZER" | "CLUB_PARTNER" | "TEAM_ORGANIZER_PRO";
};

export type DemoWorldV3AuthorityProofOrganizerAccess = {
  firstCompetitionLaunches: 1;
  grantCount: 3;
  liveCheckoutEnabled: false;
  onboardingCompleted: 1;
  operationReceipts: number;
  privacy: {
    containsAuthUuid: false;
    containsEmail: false;
    containsPhone: false;
    containsPrivateNote: false;
    containsStripeId: false;
  };
  remoteWrites: 0;
  rpcFamilies: ["ORGANIZER_ACCESS", "LEAGUE_PRIVATE_BETA_V2", "LEAGUE_PARTICIPATION", "LEAGUE_SCHEDULING", "PUBLICATION"];
  scenarioCount: 6;
  scenarios: DemoWorldV3AuthorityProofOrganizerAccessScenario[];
  stripeTouched: false;
  subscriptionGrants: 0;
  version: 1;
};

export type DemoWorldV2AuthorityProofConfigurationRevision = {
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

export type DemoWorldV2AuthorityProofConfiguration = {
  activeDrafts: 0;
  comparator: {
    baseRevision: 1;
    changedSections: string[];
    targetRevision: 2;
  };
  competitionName: "Liga Wave 5A";
  currentEditionRevision: 2;
  futureCapabilities: {
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
  operationReceipts: number;
  publishedDrafts: 1;
  r5CatalogCodes: Array<"BLUE" | "RED" | "YELLOW">;
  refereePolicyConsumed: {
    feeMode: "FIXED";
    publicConsent: false;
    requiredBeforeReady: true;
    usage: "REQUIRED";
  };
  remoteWrites: 0;
  revisions: DemoWorldV2AuthorityProofConfigurationRevision[];
};

export type DemoWorldV2AuthorityProofPlayerRef = {
  entryNumber: number;
  playerSlot: "alternate" | "primary";
};

export type DemoWorldV2AuthorityProofDisciplineEvent = DemoWorldV2AuthorityProofPlayerRef & {
  cardTypeCode: "BLUE" | "RED" | "YELLOW";
  context: "in_match";
  eventKey: string;
  matchOrdinal: number;
  minute: number;
  publicReasonCategory: string;
  publicSummary: string;
  refereeAssignmentKey: string | null;
  reportingRefereeNumber: number | null;
  revisionVersion: number;
  sanction: {
    remainingUnits: number;
    status: string;
    unitType: string;
  } | null;
  status: string;
  temporaryDismissal: Record<string, unknown> | null;
  visualType: string;
};

export type DemoWorldV2AuthorityProofRefereeAssignment = {
  assignmentKey: string;
  effectiveScheduledEnd: string;
  effectiveScheduledStart: string;
  matchOrdinal: number;
  reconfirmed: boolean;
  refereeNumber: number;
  replacedByAssignmentKey: string | null;
  replacesAssignmentKey: string | null;
  revision: number;
  scheduleState: "CANCELLED" | "CURRENT" | "RECONFIRMATION_REQUIRED" | "STALE_SCHEDULE";
  scheduledEnd: string;
  scheduledStart: string;
  status: "accepted" | "cancelled" | "completed" | "confirmed" | "declined" | "expired" | "proposed" | "replaced";
};

export type DemoWorldV2AuthorityProofReferee = {
  availabilityStatus: "AVAILABLE" | "LIMITED";
  displayName: string;
  modalities: Array<"FOOTBALL_11" | "FOOTBALL_7" | "FUTSAL">;
  municipality: string;
  publicBio: string;
  publicFee: {
    currency: string;
    feeMode: "FIXED" | "FREE" | "NEGOTIABLE" | "VOLUNTEER";
    fromCents: number | null;
    paymentManagedByPachangasIq: false;
  } | null;
  refereeNumber: number;
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

export type DemoWorldV2AuthorityProofRefereeAssignments = {
  assignments: DemoWorldV2AuthorityProofRefereeAssignment[];
  counts: {
    cancelled: number;
    completed: number;
    declined: number;
    replaced: number;
    unassignedMatches: number;
  };
  noActiveOverlaps: boolean;
  oneMainRefereePerMatch: boolean;
  overlapRejected: boolean;
  profiles: DemoWorldV2AuthorityProofReferee[];
  r5LinkedEvents: {
    linked: number;
    onRefereedMatches: number;
    unlinkedEventKeys: string[];
  };
  statisticsConverged: boolean;
  unconvergedRefereeNumbers: number[];
};

export type DemoWorldV2AuthorityProofDiscipline = {
  appeals: Array<{
    sourceEventKey: string;
    status: string;
  }>;
  cardCounts: { BLUE: number; RED: number; YELLOW: number };
  counters: Array<DemoWorldV2AuthorityProofPlayerRef & {
    cardTypeCode: "BLUE" | "RED" | "YELLOW";
    eventCount: number;
    points: number;
    thresholdHits: number;
  }>;
  eligibilityTimeline: Array<{
    matchOrdinal: number;
    primaryAvailable: boolean;
    roundNumber: number;
    selectedSlot: "alternate" | "primary";
  }>;
  events: DemoWorldV2AuthorityProofDisciplineEvent[];
  playerStates: Array<DemoWorldV2AuthorityProofPlayerRef & {
    cards: Record<string, unknown>;
    remainingUnits: number;
    status: string;
    unitType: string | null;
  }>;
  sanctions: Array<DemoWorldV2AuthorityProofPlayerRef & {
    outcome: string;
    publicReasonCategory: string;
    publicSummary: string;
    remainingUnits: number;
    sourceEventKey: string;
    status: string;
    totalUnits: number;
    unitType: string;
  }>;
  serviceEvents: Array<{
    eventType: "SERVED";
    matchOrdinal: number;
    remainingAfter: number;
    remainingBefore: number;
    sourceEventKey: string;
    units: number;
  }>;
};

export type DemoWorldV2AuthorityProofMatch = {
  awayEntryNumber: number;
  exceptionType: "none" | "no_show" | "postponed" | "suspended_resumed" | "venue_changed";
  homeEntryNumber: number;
  lateArrivalStatus: "arrived_within_policy" | null;
  lineage: Array<"fixture_change" | "official_result" | "postponement" | "resumption" | "suspension">;
  originalScheduledStart: string;
  outcome: "MIRROR_SPORTING_RESULT" | "NO_SHOW";
  partialResult: { away: number; home: number; minute: number } | null;
  result: { away: number; home: number };
  roundNumber: number;
  scheduledStart: string;
  venueLabel: string;
};

export type DemoWorldV2AuthorityProofStanding = {
  draws: number;
  effectivePoints: number;
  entryNumber: number;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  losses: number;
  played: number;
  position: number;
  wins: number;
};

export type DemoWorldV2AuthorityProofTournamentPlacement = {
  entryNumber: number;
  groupNumber: number;
  placementSource: "ENGINE" | "HYBRID_FILL" | "LOCKED" | "MANUAL";
  potNumber: number;
  slotNumber: number;
  teamName: string;
};

export type DemoWorldV2AuthorityProofTournamentOutcome = {
  algorithmVersion: string;
  groupSizeBalance: number;
  hardViolations: 0;
  inputChecksum: string;
  levelBalance: number;
  locks: Array<{
    entryNumber: number;
    groupNumber: number;
    slotNumber: number;
    teamName: string;
  }>;
  manualOverrideCount: number;
  mode: "HYBRID" | "SEEDED_POTS";
  placements: DemoWorldV2AuthorityProofTournamentPlacement[];
  potDistribution: number;
  qualityScore: number;
  resultChecksum: string;
  sameClubCollisions: number;
  seed: string;
  softScore: number;
  unassignedEntries: 0;
  version: number;
};

export type DemoWorldV2AuthorityProofTournamentGroupMatch = {
  awayTeamNumber: number;
  disciplineEvents: number;
  groupNumber: number;
  homeTeamNumber: number;
  incidentType: "DISPUTED_CORRECTED" | "NONE" | "NO_SHOW" | "POSTPONED_RESCHEDULED" | "SUSPENDED_RESUMED";
  matchKey: string;
  refereeNumber?: number;
  roundNumber: number;
  scheduledStart: string;
  score?: { away: number; home: number };
  status: "OFFICIAL" | "SCHEDULED";
  venueLabel: string;
};

export type DemoWorldV2AuthorityProofTournamentStanding = {
  criteria?: string[];
  draws: number;
  goalDifference: number;
  goalsAgainst: number;
  goalsFor: number;
  groupNumber: number;
  losses: number;
  played: number;
  points: number;
  position: number;
  qualificationZone?: boolean;
  revision?: number;
  status?: "PROVISIONAL";
  teamNumber: number;
  wins: number;
};

export type DemoWorldV2AuthorityProofTournamentGroupStagePublic = {
  currentRound: 2;
  discipline: Array<{
    cardType: "RED" | "YELLOW";
    playerLabel: string;
    status: string;
    teamNumber: number;
  }>;
  fixtureCount: 24;
  groupCount: 4;
  incidents: {
    disputedCorrected: 1;
    noShow: 1;
    postponedRescheduled: 1;
    suspendedResumed: 1;
  };
  matches: DemoWorldV2AuthorityProofTournamentGroupMatch[];
  officialMatches: 16;
  qualificationStatus: "PROVISIONAL";
  referees: { confirmedMatches: 12; unassignedMatches: 12 };
  remoteWrites: 0;
  roundCount: 3;
  sanctions: Array<{
    publicSummary: string;
    remainingUnits: number;
    status: string;
    teamNumber: number;
    unitType: string;
  }>;
  scheduledMatches: 8;
  standings: DemoWorldV2AuthorityProofTournamentStanding[];
};

export type DemoWorldV2AuthorityProofTournamentGroupStageFinal = {
  bracketProgressionEnabled: false;
  bracketSize: 8;
  bracketSlots: Array<{
    matchNumber: number;
    side: "A" | "B";
    slotKey: string;
    sourceGroupNumber: number;
    sourceKind: "GROUP_POSITION";
    sourcePosition: number;
    status: string;
    teamNumber: number;
  }>;
  bracketStatus: "PUBLISHED";
  canonicalMatches: 24;
  eliminated: 8;
  finalStandings: DemoWorldV2AuthorityProofTournamentStanding[];
  fixtureCount: 24;
  groupCount: 4;
  groupStageStatus: string;
  knockoutMatches: 0;
  officialMatches: 24;
  qualificationChecksum: string;
  qualificationRows: Array<{
    crossGroupRank: number | null;
    groupNumber: number;
    groupPosition: number;
    outcome: "DIRECT_QUALIFIER" | "ELIMINATED" | "EXTRA_QUALIFIER";
    targetBracketSlot: string | null;
    teamNumber: number;
  }>;
  qualificationStatus: "PUBLISHED";
  qualifiers: 8;
  remoteWrites: 0;
  standingSnapshots: 4;
};

export type DemoWorldV2AuthorityProofTournamentKnockoutTeam = {
  name: string;
  teamNumber: number;
};

export type DemoWorldV2AuthorityProofTournamentKnockoutNode = {
  awayTeam: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
  extraTime?: { away: number; home: number };
  homeTeam: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
  loserTeamNumber: number;
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
  winnerTeamNumber: number;
};

export type DemoWorldV2AuthorityProofTournamentKnockoutPublic = {
  competitionName: "COPA BARRIOS IQ 2027";
  discipline: {
    blockedFromSemifinal: true;
    playerLabel: string;
    ratingChanged: false;
    sanctionApplies: true;
    teamNumber: number;
  };
  format: "SINGLE_MATCH_KNOCKOUT";
  nodes: DemoWorldV2AuthorityProofTournamentKnockoutNode[];
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
    champion: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
    fourthPlace: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
    runnerUp: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
    thirdPlace: DemoWorldV2AuthorityProofTournamentKnockoutTeam;
  };
  publicSafe: true;
  rounds: Array<{
    code: "FINAL" | "QUARTERFINAL" | "SEMIFINAL" | "THIRD_PLACE";
    label: string;
    matches: number;
  }>;
  status: "LOCKED";
  teamJourneys: Array<{
    finalPosition: number | null;
    path: string[];
    status: "CHAMPION" | "ELIMINATED" | "FOURTH_PLACE" | "RUNNER_UP" | "THIRD_PLACE";
    teamName: string;
    teamNumber: number;
  }>;
  thirdPlaceEnabled: true;
  transport: { methods: ["GET"]; remoteWrites: 0 };
};

export type DemoWorldV2AuthorityProofTournamentKnockout = {
  bracket: {
    advancedNodes: number;
    currentSlots: number;
    fixtureReservations: number;
    nodeCount: number;
    revision: number;
    revisionCount: number;
    roundCount: number;
    size: number;
    slotRevisions: number;
    status: "locked";
    thirdPlaceEnabled: true;
  };
  completion: {
    championTeamNumber: number;
    fourthPlaceTeamNumber: number;
    rewardGrants: number | string;
    runnerUpTeamNumber: number;
    snapshots: number;
    thirdPlaceTeamNumber: number;
  };
  correction: {
    nodeHistoryRetained: true;
    oldContextRetired: true;
    oldMatchKey: string;
    oldMatchRetired: true;
    replacementCreated: true;
    replacementMatchKey: string;
  };
  integrity: {
    billingUnchanged: true;
    conductUnchanged: true;
    ratingV2Unchanged: true;
    remoteWrites: 0;
    rewardsUnchanged: true;
  };
  matches: {
    active: number;
    finals: number;
    historical: number;
    quarterfinals: number;
    retired: number;
    semifinals: number;
    thirdPlace: number;
  };
  penaltySeparation: {
    extraTimeAway: number;
    extraTimeHome: number;
    groupStandingsUnchanged: true;
    regulationAway: number;
    regulationHome: number;
    shootoutAway: number;
    shootoutGoalsAddedToSportingScore: false;
    shootoutHome: number;
  };
  policy: Record<string, unknown>;
  progression: {
    activeAdvanceDecisions: number;
    advanceDecisions: number;
    dependencyImpacts: number;
    invalidations: number;
    resolutionKinds: Partial<Record<
      "ADMINISTRATIVE_DECISION" | "EXTRA_TIME" | "FORFEIT" | "NO_SHOW" | "PENALTY_SHOOTOUT" | "SPORTING_RESULT",
      number
    >>;
  };
  r4d: { confirmedNoShows: number; knockoutNoShowResolution: true };
  r5: {
    blockedFromSemifinal: true;
    playerLabel: string;
    ratingChanged: false;
    sanctionApplies: true;
    teamNumber: number;
  };
  readModel: { checksumPresent: true; revision: number; serverSequencePresent: true };
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
  remoteWrites: 0;
};

export type DemoWorldV2AuthorityProofTournament = {
  acceptedParticipants: 16;
  competitionName: "COPA BARRIOS IQ 2027";
  conflict: {
    attempts: number;
    constraintTypes: string[];
    errorCode: "DRAW_UNSATISFIABLE";
    reasonCode: "GROUP_CONSTRAINTS_UNSATISFIABLE";
    suggestions: string[];
  };
  constraints: Array<{
    reason: string;
    strength: "HARD" | "SOFT";
    type: "POT_DISTRIBUTION" | "SAME_CLUB_AVOIDANCE" | "TEAM_LEVEL_BALANCE";
    weight: number;
  }>;
  drawOutcomes: DemoWorldV2AuthorityProofTournamentOutcome[];
  generatedOutcomes: 2;
  groupCount: 4;
  groupStageFinal: DemoWorldV2AuthorityProofTournamentGroupStageFinal;
  groupStagePublic: DemoWorldV2AuthorityProofTournamentGroupStagePublic;
  knockoutProof: DemoWorldV2AuthorityProofTournamentKnockout;
  knockoutPublic: DemoWorldV2AuthorityProofTournamentKnockoutPublic;
  operationReceipts: number;
  planStatus: "published";
  potCount: 4;
  publishedRevision: 5;
  remoteWrites: 0;
  slug: "copa-barrios-iq-2027";
  totalRevisions: 5;
  tournamentMatches: 24;
};

export type DemoWorldV2AuthorityProofPublicCompetitionView = {
  bracket: Record<string, unknown> | null;
  calendar: Record<string, unknown>;
  hub: Record<string, unknown>;
  slug: string;
  standings: Record<string, unknown>;
};

export type DemoWorldV2AuthorityProofPublicCompetitions = {
  directory: Record<string, unknown>;
  league: DemoWorldV2AuthorityProofPublicCompetitionView;
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
  remoteWrites: 0;
  requests: Array<{
    entryCreated: boolean;
    status: "accepted" | "rejected" | "waitlisted" | "withdrawn";
    team: { name: string };
    waitlistPosition: number | null;
  }>;
  tournament: DemoWorldV2AuthorityProofPublicCompetitionView;
  unlisted: DemoWorldV2AuthorityProofPublicCompetitionView;
};

export type DemoWorldV2AuthorityProof = {
  authorityHash: string;
  configuration: DemoWorldV2AuthorityProofConfiguration;
  database: "temporary-local-postgresql";
  discipline: DemoWorldV2AuthorityProofDiscipline;
  generatedAt: "2026-08-28T14:00:00.000Z";
  matchCount: 15;
  matches: DemoWorldV2AuthorityProofMatch[];
  migrationCount: number;
  operationReceipts: {
    discipline: number;
    matchOperations: number;
    operationalExceptions: number;
    refereeAssignments: number;
    refereeOfficiating: number;
    refereePlatform: number;
    scheduling: number;
  };
  organizerBilling: DemoWorldV2AuthorityProofOrganizerBilling;
  organizerAccess: DemoWorldV3AuthorityProofOrganizerAccess;
  refereeAssignments: DemoWorldV2AuthorityProofRefereeAssignments;
  publicCompetitions: DemoWorldV2AuthorityProofPublicCompetitions;
  remoteWrites: 0;
  rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5", "R6A", "R6B", "R6C", "PUBLIC_COMPETITIONS", "ORGANIZER_BILLING", "ORGANIZER_ACCESS"];
  roundCount: 5;
  standings: DemoWorldV2AuthorityProofStanding[];
  tournament: DemoWorldV2AuthorityProofTournament;
  version: typeof DEMO_WORLD_V2_AUTHORITY_PROOF_VERSION;
};

export function demoWorldV2AuthorityHash(proof: Omit<DemoWorldV2AuthorityProof, "authorityHash">) {
  return createHash("sha256").update(JSON.stringify(proof)).digest("hex");
}

export function assertDemoWorldV2AuthorityProof(value: DemoWorldV2AuthorityProof) {
  if (value.version !== DEMO_WORLD_V2_AUTHORITY_PROOF_VERSION) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_VERSION_INVALID");
  }
  if (value.database !== "temporary-local-postgresql" || value.remoteWrites !== 0) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_DATABASE_INVALID");
  }
  if (value.roundCount !== 5 || value.matchCount !== 15 || value.matches.length !== 15) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_GRAPH_INVALID");
  }
  if (value.standings.length !== 6 || value.standings.some((row) => row.played !== 5)) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_STANDINGS_INVALID");
  }
  if (value.discipline.events.length !== 20
      || value.discipline.cardCounts.YELLOW !== 16
      || value.discipline.cardCounts.RED !== 2
      || value.discipline.cardCounts.BLUE !== 2) {
    throw new Error("DEMO_WORLD_V2_1_AUTHORITY_CARD_DISTRIBUTION_INVALID");
  }
  if (value.discipline.sanctions.length !== 4
      || value.discipline.serviceEvents.length !== 2
      || value.discipline.appeals.length !== 2) {
    throw new Error("DEMO_WORLD_V2_1_AUTHORITY_DISCIPLINE_GRAPH_INVALID");
  }
  const restoredEligibility = value.discipline.sanctions.find(({ entryNumber, playerSlot }) => (
    entryNumber === 4 && playerSlot === "primary"
  ));
  if (restoredEligibility?.status !== "served"
      || restoredEligibility.totalUnits !== 1
      || restoredEligibility.remainingUnits !== 0) {
    throw new Error("DEMO_WORLD_V2_1_APPEAL_SERVICE_ACCOUNTING_INVALID");
  }
  if (value.discipline.events.filter(({ revisionVersion }) => revisionVersion > 1).length !== 1
      || value.discipline.appeals.some(({ status }) => !["modified", "upheld"].includes(status))) {
    throw new Error("DEMO_WORLD_V2_1_AUTHORITY_DISCIPLINE_STORIES_INVALID");
  }
  if (JSON.stringify(value.discipline.eligibilityTimeline.map(({ primaryAvailable, selectedSlot }) => ({
    primaryAvailable,
    selectedSlot,
  }))) !== JSON.stringify([
    { primaryAvailable: true, selectedSlot: "primary" },
    { primaryAvailable: true, selectedSlot: "primary" },
    { primaryAvailable: true, selectedSlot: "primary" },
    { primaryAvailable: false, selectedSlot: "alternate" },
    { primaryAvailable: true, selectedSlot: "primary" },
  ])) {
    throw new Error("DEMO_WORLD_V2_1_AUTHORITY_ELIGIBILITY_TIMELINE_INVALID");
  }
  const exceptions = value.matches.reduce<Record<string, number>>((counts, match) => {
    counts[match.exceptionType] = (counts[match.exceptionType] ?? 0) + 1;
    return counts;
  }, {});
  if (exceptions.none !== 11 || exceptions.postponed !== 1 || exceptions.venue_changed !== 1
      || exceptions.no_show !== 1 || exceptions.suspended_resumed !== 1) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_STORIES_INVALID");
  }
  if (value.matches.filter(({ lateArrivalStatus }) => lateArrivalStatus === "arrived_within_policy").length !== 1) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_LATE_ARRIVAL_INVALID");
  }
  if (value.refereeAssignments.profiles.length !== 8
      || value.refereeAssignments.counts.completed !== 13
      || value.refereeAssignments.counts.declined !== 1
      || value.refereeAssignments.counts.cancelled !== 1
      || value.refereeAssignments.counts.replaced !== 1
      || value.refereeAssignments.counts.unassignedMatches !== 2) {
    throw new Error("DEMO_WORLD_V2_2_REFEREE_ASSIGNMENT_DISTRIBUTION_INVALID");
  }
  if (!value.refereeAssignments.overlapRejected
      || !value.refereeAssignments.noActiveOverlaps
      || !value.refereeAssignments.oneMainRefereePerMatch
      || !value.refereeAssignments.statisticsConverged) {
    throw new Error(`DEMO_WORLD_V2_2_REFEREE_ASSIGNMENT_AUTHORITY_INVALID:${JSON.stringify({
      noActiveOverlaps: value.refereeAssignments.noActiveOverlaps,
      oneMainRefereePerMatch: value.refereeAssignments.oneMainRefereePerMatch,
      overlapRejected: value.refereeAssignments.overlapRejected,
      statisticsConverged: value.refereeAssignments.statisticsConverged,
      unconvergedRefereeNumbers: value.refereeAssignments.unconvergedRefereeNumbers,
    })}`);
  }
  if (value.refereeAssignments.r5LinkedEvents.onRefereedMatches
      !== value.refereeAssignments.r5LinkedEvents.linked
      || value.refereeAssignments.r5LinkedEvents.unlinkedEventKeys.length !== 0) {
    throw new Error(`DEMO_WORLD_V2_2_REFEREE_R5_LINEAGE_INVALID:${JSON.stringify(value.refereeAssignments.r5LinkedEvents)}`);
  }
  const rescheduledAssignment = value.refereeAssignments.assignments.find(({ matchOrdinal, status }) => (
    matchOrdinal === 3 && status === "completed"
  ));
  if (!rescheduledAssignment?.reconfirmed
      || rescheduledAssignment.scheduledStart === rescheduledAssignment.effectiveScheduledStart
      || rescheduledAssignment.scheduleState !== "CURRENT") {
    throw new Error("DEMO_WORLD_V2_2_REFEREE_RECONFIRMATION_INVALID");
  }
  const replacement = value.refereeAssignments.assignments.find(({ replacesAssignmentKey }) => replacesAssignmentKey !== null);
  if (!replacement || replacement.status !== "completed"
      || !value.refereeAssignments.assignments.some(({ assignmentKey, replacedByAssignmentKey, status }) => (
        assignmentKey === replacement.replacesAssignmentKey
        && replacedByAssignmentKey === replacement.assignmentKey
        && status === "replaced"
      ))) {
    throw new Error("DEMO_WORLD_V2_2_REFEREE_REPLACEMENT_INVALID");
  }
  if (value.configuration.remoteWrites !== 0
      || value.configuration.competitionName !== "Liga Wave 5A"
      || value.configuration.revisions.length !== 2
      || value.configuration.activeDrafts !== 0
      || value.configuration.publishedDrafts !== 1
      || value.configuration.currentEditionRevision !== 2) {
    throw new Error("DEMO_WORLD_V2_3_CONFIGURATION_GRAPH_INVALID");
  }
  const [standardConfiguration, customConfiguration] = value.configuration.revisions;
  if (!standardConfiguration || !customConfiguration
      || standardConfiguration.revision !== 1
      || standardConfiguration.source !== "LEAGUE_WIZARD_V2"
      || standardConfiguration.authoringMode !== "SIMPLE"
      || standardConfiguration.sourcePresetId !== "LEAGUE_F7_STANDARD"
      || standardConfiguration.matchDurationMinutes !== 70
      || standardConfiguration.pointsForWin !== 3
      || standardConfiguration.yellowThreshold !== 3
      || standardConfiguration.blueEnabled
      || standardConfiguration.refereeUsage !== "OPTIONAL"
      || standardConfiguration.feeMode !== "NEGOTIABLE"
      || standardConfiguration.noShowWinnerScore !== 3
      || standardConfiguration.postponementResponseDeadlineHours !== 48) {
    throw new Error("DEMO_WORLD_V2_3_STANDARD_CONFIGURATION_INVALID");
  }
  if (customConfiguration.revision !== 2
      || customConfiguration.source !== "COMPETITION_CONFIGURATION_CENTER_V1"
      || customConfiguration.authoringMode !== "ADVANCED"
      || customConfiguration.matchDurationMinutes !== 80
      || customConfiguration.pointsForWin !== 2
      || customConfiguration.yellowThreshold !== 4
      || !customConfiguration.blueEnabled
      || customConfiguration.refereeUsage !== "REQUIRED"
      || customConfiguration.feeMode !== "FIXED"
      || customConfiguration.feePublicConsent
      || customConfiguration.noShowWinnerScore !== 4
      || customConfiguration.postponementResponseDeadlineHours !== 36
      || standardConfiguration.checksum === customConfiguration.checksum
      || value.configuration.r5CatalogCodes.join(",") !== "YELLOW,RED,BLUE") {
    throw new Error("DEMO_WORLD_V2_3_CUSTOM_CONFIGURATION_INVALID");
  }
  if (!value.configuration.health.complete
      || value.configuration.health.errors !== 0
      || value.configuration.comparator.baseRevision !== 1
      || value.configuration.comparator.targetRevision !== 2
      || !value.configuration.comparator.changedSections.includes("discipline")
      || !value.configuration.comparator.changedSections.includes("referees")
      || value.configuration.revisions.some(({ healthComplete, humanDocumentVerified }) => (
        !healthComplete || !humanDocumentVerified
      ))) {
    throw new Error("DEMO_WORLD_V2_3_CONFIGURATION_EVIDENCE_INVALID");
  }
  if (JSON.stringify(value.configuration).includes("fixedCents")) {
    throw new Error("DEMO_WORLD_V2_3_PRIVATE_FEE_LEAK");
  }
  const tournament = value.tournament;
  if (tournament.competitionName !== "COPA BARRIOS IQ 2027"
      || tournament.acceptedParticipants !== 16
      || tournament.groupCount !== 4
      || tournament.potCount !== 4
      || tournament.generatedOutcomes !== 2
      || tournament.totalRevisions !== 5
      || tournament.publishedRevision !== 5
      || tournament.planStatus !== "published"
      || tournament.tournamentMatches !== 24
      || tournament.remoteWrites !== 0) {
    throw new Error("DEMO_WORLD_V2_4_TOURNAMENT_GRAPH_INVALID");
  }
  const groupStage = tournament.groupStagePublic;
  if (groupStage.currentRound !== 2
      || groupStage.roundCount !== 3
      || groupStage.groupCount !== 4
      || groupStage.fixtureCount !== 24
      || groupStage.officialMatches !== 16
      || groupStage.scheduledMatches !== 8
      || groupStage.matches.length !== 24
      || groupStage.standings.length !== 16
      || groupStage.discipline.length !== 4
      || groupStage.sanctions.length < 1
      || groupStage.referees.confirmedMatches !== 12
      || groupStage.referees.unassignedMatches !== 12
      || groupStage.qualificationStatus !== "PROVISIONAL"
      || groupStage.remoteWrites !== 0
      || Object.values(groupStage.incidents).some((count) => count !== 1)) {
    throw new Error("DEMO_WORLD_V2_5_PUBLIC_GROUP_STAGE_INVALID");
  }
  if (groupStage.matches.filter(({ status }) => status === "OFFICIAL").length !== 16
      || groupStage.matches.filter(({ status }) => status === "SCHEDULED").length !== 8
      || groupStage.standings.some(({ played, status }) => played !== 2 || status !== "PROVISIONAL")) {
    throw new Error("DEMO_WORLD_V2_5_PUBLIC_TRACKING_INVALID");
  }
  const final = tournament.groupStageFinal;
  if (final.groupCount !== 4
      || final.fixtureCount !== 24
      || final.canonicalMatches !== 24
      || final.officialMatches !== 24
      || final.standingSnapshots !== 4
      || final.qualificationStatus !== "PUBLISHED"
      || final.qualifiers !== 8
      || final.eliminated !== 8
      || final.qualificationRows.length !== 16
      || final.finalStandings.length !== 16
      || final.bracketStatus !== "PUBLISHED"
      || final.bracketSize !== 8
      || final.bracketSlots.length !== 8
      || final.knockoutMatches !== 0
      || final.bracketProgressionEnabled
      || final.remoteWrites !== 0
      || !/^[0-9a-f]{64}$/.test(final.qualificationChecksum)) {
    throw new Error("DEMO_WORLD_V2_5_FINAL_GROUP_STAGE_INVALID");
  }
  for (let groupNumber = 1; groupNumber <= 4; groupNumber += 1) {
    const standings = final.finalStandings.filter((row) => row.groupNumber === groupNumber);
    if (standings.length !== 4
        || standings.some(({ played }) => played !== 3)
        || new Set(standings.map(({ position }) => position)).size !== 4) {
      throw new Error(`DEMO_WORLD_V2_5_FINAL_STANDINGS_INVALID:${groupNumber}`);
    }
  }
  if (tournament.drawOutcomes.length !== 2
      || tournament.drawOutcomes[0]?.mode !== "SEEDED_POTS"
      || tournament.drawOutcomes[1]?.mode !== "HYBRID"
      || tournament.drawOutcomes.some((outcome) => (
        outcome.placements.length !== 16
        || outcome.hardViolations !== 0
        || outcome.unassignedEntries !== 0
        || new Set(outcome.placements.map(({ entryNumber }) => entryNumber)).size !== 16
      ))) {
    throw new Error("DEMO_WORLD_V2_4_DRAW_OUTCOMES_INVALID");
  }
  for (const outcome of tournament.drawOutcomes) {
    for (let groupNumber = 1; groupNumber <= 4; groupNumber += 1) {
      const group = outcome.placements.filter((placement) => placement.groupNumber === groupNumber);
      if (group.length !== 4 || new Set(group.map(({ potNumber }) => potNumber)).size !== 4) {
        throw new Error("DEMO_WORLD_V2_4_POT_DISTRIBUTION_INVALID");
      }
    }
  }
  if (tournament.drawOutcomes[0]!.locks.length !== 0
      || tournament.drawOutcomes[1]!.locks.length !== 2
      || tournament.drawOutcomes[1]!.manualOverrideCount !== 2
      || tournament.conflict.errorCode !== "DRAW_UNSATISFIABLE"
      || tournament.conflict.reasonCode !== "GROUP_CONSTRAINTS_UNSATISFIABLE"
      || tournament.conflict.suggestions.length < 2) {
    throw new Error("DEMO_WORLD_V2_4_HYBRID_OR_CONFLICT_INVALID");
  }
  const knockout = tournament.knockoutPublic;
  if (knockout.competitionName !== "COPA BARRIOS IQ 2027"
      || knockout.status !== "LOCKED"
      || knockout.format !== "SINGLE_MATCH_KNOCKOUT"
      || !knockout.thirdPlaceEnabled
      || !knockout.publicSafe
      || knockout.transport.remoteWrites !== 0
      || knockout.nodes.length !== 8
      || knockout.teamJourneys.length !== 8
      || knockout.rounds.length !== 4
      || knockout.organizerDesk.bracketHealth !== "HEALTHY"
      || knockout.organizerDesk.completionHealth !== "COMPLETE"
      || knockout.organizerDesk.unresolvedNodes !== 0
      || knockout.organizerDesk.unscheduledMatches !== 0
      || knockout.organizerDesk.pendingResults !== 0) {
    throw new Error("DEMO_WORLD_V2_6_PUBLIC_KNOCKOUT_INVALID");
  }
  const roundCounts = new Map(knockout.rounds.map(({ code, matches }) => [code, matches]));
  if (roundCounts.get("QUARTERFINAL") !== 4
      || roundCounts.get("SEMIFINAL") !== 2
      || roundCounts.get("FINAL") !== 1
      || roundCounts.get("THIRD_PLACE") !== 1
      || knockout.nodes.some(({ status }) => status !== "OFFICIAL")
      || knockout.nodes.filter(({ roundCode }) => roundCode === "QUARTERFINAL").length !== 4
      || knockout.nodes.filter(({ roundCode }) => roundCode === "SEMIFINAL").length !== 2
      || knockout.nodes.filter(({ roundCode }) => roundCode === "FINAL").length !== 1
      || knockout.nodes.filter(({ roundCode }) => roundCode === "THIRD_PLACE").length !== 1
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "EXTRA_TIME")
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "PENALTY_SHOOTOUT")
      || !knockout.nodes.some(({ resolutionKind }) => resolutionKind === "FORFEIT" || resolutionKind === "NO_SHOW")
      || new Set(knockout.teamJourneys.map(({ teamNumber }) => teamNumber)).size !== 8
      || knockout.teamJourneys.filter(({ status }) => status === "CHAMPION").length !== 1
      || knockout.teamJourneys.filter(({ status }) => status === "RUNNER_UP").length !== 1
      || knockout.teamJourneys.filter(({ status }) => status === "THIRD_PLACE").length !== 1) {
    throw new Error("DEMO_WORLD_V2_6_PUBLIC_BRACKET_STORY_INVALID");
  }
  const knockoutProof = tournament.knockoutProof;
  const noShowResolutions = (knockoutProof.progression.resolutionKinds.NO_SHOW ?? 0)
    + (knockoutProof.progression.resolutionKinds.FORFEIT ?? 0);
  if (knockoutProof.bracket.status !== "locked"
      || knockoutProof.bracket.size !== 8
      || knockoutProof.bracket.nodeCount !== 8
      || knockoutProof.bracket.advancedNodes !== 8
      || knockoutProof.bracket.currentSlots !== 16
      || knockoutProof.bracket.fixtureReservations !== 8
      || !knockoutProof.bracket.thirdPlaceEnabled
      || knockoutProof.matches.active !== 8
      || knockoutProof.matches.historical !== 9
      || knockoutProof.matches.retired !== 1
      || knockoutProof.matches.quarterfinals !== 4
      || knockoutProof.matches.semifinals !== 2
      || knockoutProof.matches.finals !== 1
      || knockoutProof.matches.thirdPlace !== 1
      || knockoutProof.progression.activeAdvanceDecisions !== 8
      || knockoutProof.progression.invalidations !== 1
      || knockoutProof.progression.dependencyImpacts !== 3
      || knockoutProof.progression.resolutionKinds.EXTRA_TIME !== 1
      || knockoutProof.progression.resolutionKinds.PENALTY_SHOOTOUT !== 1
      || knockoutProof.progression.resolutionKinds.ADMINISTRATIVE_DECISION !== 1
      || noShowResolutions !== 1) {
    throw new Error("DEMO_WORLD_V2_6_KNOCKOUT_AUTHORITY_INVALID");
  }
  if (!knockoutProof.penaltySeparation.groupStandingsUnchanged
      || knockoutProof.penaltySeparation.regulationHome !== 1
      || knockoutProof.penaltySeparation.regulationAway !== 1
      || knockoutProof.penaltySeparation.shootoutHome !== 5
      || knockoutProof.penaltySeparation.shootoutAway !== 4
      || knockoutProof.penaltySeparation.shootoutGoalsAddedToSportingScore
      || !knockoutProof.correction.oldMatchRetired
      || !knockoutProof.correction.oldContextRetired
      || !knockoutProof.correction.replacementCreated
      || !knockoutProof.correction.nodeHistoryRetained
      || !knockoutProof.r4d.knockoutNoShowResolution
      || !knockoutProof.r5.sanctionApplies
      || !knockoutProof.r5.blockedFromSemifinal
      || knockoutProof.r5.ratingChanged
      || knockoutProof.referees.semifinalReplacement.originalStatus !== "replaced"
      || knockoutProof.referees.semifinalReplacement.replacementStatus !== "confirmed"
      || !knockoutProof.referees.semifinalReplacement.lineageLinked
      || knockoutProof.referees.final.status !== "confirmed") {
    throw new Error("DEMO_WORLD_V2_6_LINKED_AUTHORITY_INVALID");
  }
  if (knockoutProof.completion.snapshots !== 2
      || Number(knockoutProof.completion.rewardGrants) !== 0
      || new Set([
        knockoutProof.completion.championTeamNumber,
        knockoutProof.completion.runnerUpTeamNumber,
        knockoutProof.completion.thirdPlaceTeamNumber,
        knockoutProof.completion.fourthPlaceTeamNumber,
      ]).size !== 4
      || !knockoutProof.integrity.ratingV2Unchanged
      || !knockoutProof.integrity.rewardsUnchanged
      || !knockoutProof.integrity.conductUnchanged
      || !knockoutProof.integrity.billingUnchanged
      || knockoutProof.integrity.remoteWrites !== 0
      || !knockoutProof.readModel.serverSequencePresent
      || !knockoutProof.readModel.checksumPresent
      || knockoutProof.remoteWrites !== 0) {
    throw new Error("DEMO_WORLD_V2_6_COMPLETION_OR_INTEGRITY_INVALID");
  }
  if (!value.rpcFamilies.includes("R6C")) {
    throw new Error("DEMO_WORLD_V2_6_RPC_FAMILY_MISSING");
  }
  const publicCompetitions = value.publicCompetitions;
  const directoryItems = Array.isArray(publicCompetitions.directory.items)
    ? publicCompetitions.directory.items as Array<Record<string, unknown>>
    : [];
  const directorySlugs = directoryItems.map((item) => String(
    (item.publication as Record<string, unknown> | undefined)?.slug ?? "",
  ));
  if (directoryItems.length !== 3
      || !directorySlugs.includes("liga-publica-wave-7a")
      || !directorySlugs.includes("copa-barrios-iq-2027")
      || !directorySlugs.includes("liga-marina-v3")
      || directorySlugs.includes("copa-enlace-demo")
      || directorySlugs.includes("liga-privada-organizador-demo")) {
    throw new Error("DEMO_WORLD_V2_7_PUBLIC_DIRECTORY_INVALID");
  }
  const publicViews = [publicCompetitions.league, publicCompetitions.tournament];
  if (publicViews.some(({ hub }) => {
    const publication = (hub.publication ?? {}) as Record<string, unknown>;
    return publication.visibility !== "public" || publication.status !== "published";
  })) {
    throw new Error("DEMO_WORLD_V2_7_PUBLIC_HUB_INVALID");
  }
  const unlistedPublication = (publicCompetitions.unlisted.hub.publication ?? {}) as Record<string, unknown>;
  const privatePublication = (publicCompetitions.organizerPrivate.hub.publication ?? {}) as Record<string, unknown>;
  if (unlistedPublication.visibility !== "unlisted" || unlistedPublication.status !== "published"
      || privatePublication.visibility !== "private" || privatePublication.status !== "draft") {
    throw new Error("DEMO_WORLD_V2_7_VISIBILITY_INVALID");
  }
  const statuses = new Map(publicCompetitions.requests.map((request) => [request.status, request]));
  if (!["accepted", "waitlisted", "rejected", "withdrawn"].every((status) => statuses.has(status as never))
      || statuses.get("accepted")?.entryCreated !== true
      || statuses.get("waitlisted")?.entryCreated !== false
      || !statuses.get("waitlisted")?.waitlistPosition
      || statuses.get("rejected")?.entryCreated !== false
      || statuses.get("withdrawn")?.entryCreated !== false) {
    throw new Error("DEMO_WORLD_V2_7_REGISTRATION_STORIES_INVALID");
  }
  if (publicCompetitions.remoteWrites !== 0) {
    throw new Error("DEMO_WORLD_V2_7_REMOTE_WRITES_INVALID");
  }
  if (publicCompetitions.operationReceipts < 16) {
    throw new Error("DEMO_WORLD_V2_7_OPERATION_RECEIPTS_INVALID");
  }
  if (Object.values(publicCompetitions.privacy).some(Boolean)) {
    throw new Error("DEMO_WORLD_V2_7_PRIVACY_FLAGS_INVALID");
  }
  const publicCompetitionPayload: Record<string, unknown> = { ...publicCompetitions };
  delete publicCompetitionPayload.privacy;
  if (/@example|\+34|privateReason|requestedBy|ownerId|owner_id|"message"/i.test(
    JSON.stringify(publicCompetitionPayload),
  )) {
    throw new Error("DEMO_WORLD_V2_7_PRIVATE_FIELD_LEAK");
  }
  if (!value.rpcFamilies.includes("PUBLIC_COMPETITIONS")) {
    throw new Error("DEMO_WORLD_V2_7_RPC_FAMILY_MISSING");
  }
  const organizerBilling = value.organizerBilling;
  if (organizerBilling.scenarios.map(({ id }) => id).join(",")
      !== "club_partner,club_monthly_active,club_annual_active,team_active,team_checkout_pending,team_past_due_grace,club_canceled_continuity"
      || organizerBilling.catalogMappings !== 4
      || organizerBilling.liveMappings !== 0
      || organizerBilling.liveCheckoutEnabled
      || organizerBilling.livePortalEnabled
      || !organizerBilling.testRuntimeReady
      || !organizerBilling.readModelVerified
      || organizerBilling.remoteWrites !== 0
      || organizerBilling.operationReceipts < 20
      || organizerBilling.stripeEvents !== 7
      || Object.values(organizerBilling.privacy).some(Boolean)) {
    throw new Error("DEMO_WORLD_V2_9_ORGANIZER_BILLING_AUTHORITY_INVALID");
  }
  if (!value.rpcFamilies.includes("ORGANIZER_BILLING")) {
    throw new Error("DEMO_WORLD_V2_9_RPC_FAMILY_MISSING");
  }
  if (/(?:cus|sub|price|prod)_[A-Za-z0-9_]+|@example|\+34/i.test(JSON.stringify(organizerBilling))) {
    throw new Error("DEMO_WORLD_V2_9_ORGANIZER_BILLING_PRIVATE_FIELD_LEAK");
  }
  const organizerAccess = value.organizerAccess;
  const organizerAccessScenarioIds = organizerAccess.scenarios.map(({ id }) => id).join(",");
  if (organizerAccessScenarioIds
      !== "club_partner_approved,club_paid_interest,team_needs_information_beta,team_rejected,club_withdrawn,team_owner_transfer"
      || organizerAccess.scenarioCount !== 6
      || organizerAccess.grantCount !== 3
      || organizerAccess.subscriptionGrants !== 0
      || organizerAccess.firstCompetitionLaunches !== 1
      || organizerAccess.onboardingCompleted !== 1
      || organizerAccess.liveCheckoutEnabled
      || organizerAccess.stripeTouched
      || organizerAccess.remoteWrites !== 0
      || Object.values(organizerAccess.privacy).some(Boolean)) {
    throw new Error("DEMO_WORLD_V3_ORGANIZER_ACCESS_AUTHORITY_INVALID");
  }
  const accessScenarios = new Map(organizerAccess.scenarios.map((scenario) => [scenario.id, scenario]));
  if (accessScenarios.get("club_partner_approved")?.grant?.source !== "PARTNERSHIP"
      || accessScenarios.get("club_partner_approved")?.onboarding?.status !== "completed"
      || accessScenarios.get("club_partner_approved")?.firstCompetition?.status !== "PUBLIC_ACTIVE"
      || accessScenarios.get("club_paid_interest")?.applicationStatus !== "approved_interest"
      || accessScenarios.get("club_paid_interest")?.grant !== null
      || accessScenarios.get("team_needs_information_beta")?.grant?.source !== "PRIVATE_BETA"
      || accessScenarios.get("team_rejected")?.applicationStatus !== "rejected"
      || accessScenarios.get("team_rejected")?.grant !== null
      || accessScenarios.get("club_withdrawn")?.applicationStatus !== "withdrawn"
      || accessScenarios.get("club_withdrawn")?.grant !== null
      || !accessScenarios.get("team_owner_transfer")?.ownerTransferred) {
    throw new Error("DEMO_WORLD_V3_ORGANIZER_ACCESS_STORIES_INVALID");
  }
  if (!value.rpcFamilies.includes("ORGANIZER_ACCESS")
      || organizerAccess.rpcFamilies.join(",")
        !== "ORGANIZER_ACCESS,LEAGUE_PRIVATE_BETA_V2,LEAGUE_PARTICIPATION,LEAGUE_SCHEDULING,PUBLICATION") {
    throw new Error("DEMO_WORLD_V3_ORGANIZER_ACCESS_RPC_FAMILY_MISSING");
  }
  const organizerAccessJson = JSON.stringify(organizerAccess);
  if (/(?:cus|sub|price|prod)_[A-Za-z0-9_]+|@example|\+34/i.test(organizerAccessJson)
      || /"(?:privateNote|assignedReviewer)"\s*:/i.test(organizerAccessJson)) {
    throw new Error("DEMO_WORLD_V3_ORGANIZER_ACCESS_PRIVATE_FIELD_LEAK");
  }
  if (JSON.stringify(tournament).match(/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i)) {
    throw new Error("DEMO_WORLD_V2_4_INTERNAL_ID_LEAK");
  }
  const { authorityHash, ...payload } = value;
  if (authorityHash !== demoWorldV2AuthorityHash(payload)) {
    throw new Error("DEMO_WORLD_V2_AUTHORITY_HASH_INVALID");
  }
  return value;
}

export function loadDemoWorldV2AuthorityProof(
  root = path.resolve(import.meta.dirname, "../.."),
) {
  const value = JSON.parse(readFileSync(
    path.join(root, "scripts/demo-world/demo-world-v2-authority-proof.json"),
    "utf8",
  )) as DemoWorldV2AuthorityProof;
  return assertDemoWorldV2AuthorityProof(value);
}
