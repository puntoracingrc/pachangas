import type { Metadata } from "next";
import { TournamentPrivateBetaClient } from "../_components/tournament-private-beta-client";
import type { TournamentJson } from "../tournament-draw-contract";

export const metadata: Metadata = {
  robots: { follow: false, index: false },
  title: "Laboratorio Tournament Draw · Pachangas IQ",
};

const entryIds = Array.from({ length: 16 }, (_, index) => `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`);
const teamNames = [
  "Cobalto Raval", "Vértice Gràcia", "Carboni Terrassa", "Atlètic Besòs",
  "Montjuïc 27", "Marina Badalona", "Sants Nord", "Diagonal United",
  "Poblenou IQ", "Llevant Sant Adrià", "Clot Academy", "Collserola FC",
  "Eixample 1908", "Barceloneta Sur", "Vallès Central", "Maresme Eleven",
];

const entries = entryIds.map((entryId, index) => ({
  clubId: index % 5 === 0 ? "10000000-0000-4000-8000-000000000001" : null,
  entryId,
  teamId: `20000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
  teamLevel: 64 + ((index * 7) % 24),
  teamName: teamNames[index],
}));

const placements = entries.map((entry, index) => ({
  entryId: entry.entryId,
  groupNumber: (index % 4) + 1,
  placementSource: index < 2 ? "LOCKED" : "HYBRID_FILL",
  potNumber: Math.floor(index / 4) + 1,
  slotNumber: Math.floor(index / 4) + 1,
}));

const preview: TournamentJson = {
  capabilities: { manage: true, publish: true, validate: true },
  expectedRevision: 18,
  flags: { automaticEnabled: true, drawEnabled: true, hybridEnabled: true, manualEnabled: true },
  participantFreeze: {
    checksum: "demo-participant-freeze-v2-4",
    entries,
    participantCount: 16,
  },
  plan: {
    constraints: [
      { id: "c1", publicAttribution: true, strength: "HARD", type: "POT_DISTRIBUTION" },
      { id: "c2", publicAttribution: true, strength: "HARD", type: "SAME_CLUB_AVOIDANCE" },
      { id: "c3", publicAttribution: true, strength: "SOFT", type: "TEAM_LEVEL_BALANCE", weight: 50 },
    ],
    groupCount: 4,
    id: "30000000-0000-4000-8000-000000000001",
    manualLocks: [
      { entryId: entryIds[0], id: "l1", lockType: "ENTRY_TO_GROUP", targetGroupNumber: 1 },
      { entryId: entryIds[1], id: "l2", lockType: "ENTRY_TO_GROUP", targetGroupNumber: 2 },
    ],
    mode: "HYBRID",
    placements,
    pots: Array.from({ length: 4 }, (_, index) => ({
      capacity: 4,
      entryIds: entryIds.slice(index * 4, index * 4 + 4),
      id: `p${index + 1}`,
      label: `Bombo ${index + 1}`,
      potNumber: index + 1,
    })),
    quality: {
      hardViolations: 0,
      levelBalance: 94.2,
      manualOverrideCount: 2,
      sameClubCollisions: 0,
      softScore: 96.8,
    },
    revision: 7,
    revisionSnapshot: {
      algorithmVersion: "tournament-draw-v1.0.0",
      id: "40000000-0000-4000-8000-000000000001",
      inputChecksum: "e128ed0f0e80c456",
      resultChecksum: "99db196f36a6b842",
      seed: "COPA-BARRIOS-IQ-2027-HYBRID",
      validationStatus: "VALID",
      version: 2,
    },
    status: "generated",
    targetType: "GROUP_ASSIGNMENT",
  },
  revision: 18,
  serverSequence: 24017,
};

export default function TournamentDrawLabPage() {
  return <TournamentPrivateBetaClient competitionId="50000000-0000-4000-8000-000000000001" previewData={preview} surface="lab" />;
}
