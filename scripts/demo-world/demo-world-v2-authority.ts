import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

export const DEMO_WORLD_V2_AUTHORITY_PROOF_VERSION = 5 as const;

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
  operationReceipts: number;
  planStatus: "published";
  potCount: 4;
  publishedRevision: 5;
  remoteWrites: 0;
  slug: "copa-barrios-iq-2027";
  totalRevisions: 5;
  tournamentMatches: 0;
};

export type DemoWorldV2AuthorityProof = {
  authorityHash: string;
  configuration: DemoWorldV2AuthorityProofConfiguration;
  database: "temporary-local-postgresql";
  discipline: DemoWorldV2AuthorityProofDiscipline;
  generatedAt: "2026-08-26T10:00:00.000Z";
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
  refereeAssignments: DemoWorldV2AuthorityProofRefereeAssignments;
  remoteWrites: 0;
  rpcFamilies: ["R1", "R3", "R4A", "R4B", "R4C", "R4D", "R5", "R6A"];
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
    throw new Error("DEMO_WORLD_V2_2_REFEREE_ASSIGNMENT_AUTHORITY_INVALID");
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
      || tournament.tournamentMatches !== 0
      || tournament.remoteWrites !== 0) {
    throw new Error("DEMO_WORLD_V2_4_TOURNAMENT_GRAPH_INVALID");
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
