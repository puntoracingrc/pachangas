import type { DemoWorldPerspectiveId } from "./demo-world-contract";
import type { DemoWorldV34Manifest, DemoWorldV34Snapshot } from "./demo-world-v3-4-contract";

export const DEMO_WORLD_V35_VERSION = 3.5 as const;
export const DEMO_WORLD_V35_V32_AUTHORITY_HASH = "763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1" as const;
export const DEMO_WORLD_V35_V34_FIELD_HASH = "c44b327f4ea0296ca6843f389dd043eaca06901ef14a5426ad877c989d3c3def" as const;

export type DemoWorldV35Perspective = Extract<DemoWorldPerspectiveId,
  "league-organizer" | "team-owner" | "player" | "referee" | "platform-reviewer"
> | "club-booking-manager" | "tournament-organizer";

export type DemoWorldV35Assignment = {
  assignmentStatus: "ASSIGNED" | "UNASSIGNED";
  bindingStatus: "ACTIVE" | "ACTION_REQUIRED" | "NONE";
  canonicalMatchId: string;
  competitionId: string;
  conflictCodes: string[];
  homeTeamId: string;
  homeTeamName: string;
  awayTeamId: string;
  awayTeamName: string;
  lockType: string | null;
  modality: "F7" | "FUTSAL";
  pitchId: string | null;
  pitchName: string | null;
  reservationStatus: "CONFIRMED" | "CANCELLED" | "NONE";
  scheduledAfter: string;
  scheduledBefore: string;
  sourceKind: string | null;
  venueId: string | null;
  venueName: string | null;
};

export type DemoWorldV35Series = {
  competitionId: string;
  endDate: string;
  frequency: "WEEKLY" | "BIWEEKLY";
  id: string;
  occurrenceCount: number;
  pitchId: string;
  startDate: string;
  status: "PUBLISHED";
  weekday: number;
};

export type DemoWorldV35Pool = {
  competitionId: string;
  id: string;
  pitchIds: string[];
  status: "ACTIVE";
};

export type DemoWorldV35Plan = {
  algorithmVersion: "season-venue-allocation-v1";
  assignedMatches: number;
  competitionId: string;
  hardViolations: 0;
  id: string;
  lockCount: number;
  mode: "AUTOMATIC" | "HYBRID";
  qualityScore: number;
  resultChecksum: string;
  seed: string;
  unassignedMatches: number;
};

export type DemoWorldV35Incident = {
  code: string;
  outcome: string;
  resolved: boolean;
  summary: string;
};

export type DemoWorldV35SeasonFieldAllocation = {
  assignments: DemoWorldV35Assignment[];
  authority: {
    database: "temporary-local-postgresql";
    executionMode: "REAL_RPC_CONFORMANCE_PLUS_DETERMINISTIC_128_MATCH_PROJECTION";
    migrationLedger: 228;
    rpcConformance: "PASS";
    schemaHash: string;
    temporaryDatabaseDestroyed: true;
    v32AuthorityHash: typeof DEMO_WORLD_V35_V32_AUTHORITY_HASH;
    v34FieldOperationsHash: typeof DEMO_WORLD_V35_V34_FIELD_HASH;
  };
  conflicts: DemoWorldV35Incident[];
  counts: {
    activeBindings: 126;
    clubs: 6;
    competitions: 4;
    matches: 128;
    pitches: 8;
    plans: 8;
    pools: 4;
    recurringSeries: 4;
    reservations: 127;
    teams: 32;
    venues: 4;
    weeks: 16;
  };
  integrity: {
    activeBindingDuplicates: 0;
    confirmedOverlaps: 0;
    hardViolationsPublished: 0;
    matchTimesModified: 0;
    stripeCalls: 0;
  };
  plans: DemoWorldV35Plan[];
  pools: DemoWorldV35Pool[];
  perspectives: DemoWorldV35Perspective[];
  privacy: { authIds: false; exactPrivateLocations: false; pii: false };
  readOnly: true;
  recurringSeries: DemoWorldV35Series[];
  remoteWrites: 0;
  utilization: Array<{ assignments: number; pitchId: string; utilization: number; venueId: string }>;
  version: typeof DEMO_WORLD_V35_VERSION;
};

export type DemoWorldV35PresentationManifest = {
  authority: {
    fieldOperationsHash: typeof DEMO_WORLD_V35_V34_FIELD_HASH;
    seasonHash: typeof DEMO_WORLD_V35_V32_AUTHORITY_HASH;
  };
  mode: "season-field-allocation-read-only";
  privacy: { authIds: false; pii: false };
  remoteWrites: 0;
  seasonFieldAllocation: { hash: string; matches: 128; path: string };
  version: typeof DEMO_WORLD_V35_VERSION;
};

export type DemoWorldV35Manifest = Omit<DemoWorldV34Manifest, "version"> & {
  seasonFieldAllocation: DemoWorldV35PresentationManifest;
  version: typeof DEMO_WORLD_V35_VERSION;
};

export type DemoWorldV35Snapshot = Omit<DemoWorldV34Snapshot, "manifest"> & {
  manifest: DemoWorldV35Manifest;
};

export function assertDemoWorldV35SeasonFieldAllocation(value: DemoWorldV35SeasonFieldAllocation) {
  if (value.version !== DEMO_WORLD_V35_VERSION) throw new Error("DEMO_WORLD_V35_VERSION_MISMATCH");
  if (value.counts.matches !== 128 || value.assignments.length !== 128) throw new Error("DEMO_WORLD_V35_MATCH_COUNT_MISMATCH");
  if (value.counts.clubs !== 6 || value.counts.teams !== 32 || value.counts.competitions !== 4) throw new Error("DEMO_WORLD_V35_SEASON_COUNT_MISMATCH");
  if (value.counts.venues !== 4 || value.counts.pitches !== 8) throw new Error("DEMO_WORLD_V35_FIELD_COUNT_MISMATCH");
  if (value.remoteWrites !== 0 || value.integrity.stripeCalls !== 0) throw new Error("DEMO_WORLD_V35_REMOTE_SIDE_EFFECT");
  if (value.privacy.pii || value.privacy.authIds || value.integrity.matchTimesModified !== 0
      || value.integrity.confirmedOverlaps !== 0 || value.integrity.activeBindingDuplicates !== 0
      || value.integrity.hardViolationsPublished !== 0) throw new Error("DEMO_WORLD_V35_INTEGRITY_FAILURE");
  if (value.assignments.some((item) => item.scheduledBefore !== item.scheduledAfter)) throw new Error("DEMO_WORLD_V35_SCHEDULE_MUTATION");
  return value;
}
