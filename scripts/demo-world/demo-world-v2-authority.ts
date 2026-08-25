import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

export const DEMO_WORLD_V2_AUTHORITY_PROOF_VERSION = 1 as const;

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

export type DemoWorldV2AuthorityProof = {
  authorityHash: string;
  database: "temporary-local-postgresql";
  generatedAt: "2026-08-25T10:00:00.000Z";
  matchCount: 15;
  matches: DemoWorldV2AuthorityProofMatch[];
  migrationCount: number;
  operationReceipts: {
    matchOperations: number;
    operationalExceptions: number;
    scheduling: number;
  };
  remoteWrites: 0;
  rpcFamilies: ["R1", "R4A", "R4B", "R4C", "R4D"];
  roundCount: 5;
  standings: DemoWorldV2AuthorityProofStanding[];
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
