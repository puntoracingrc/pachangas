import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  DEMO_WORLD_V35_V32_AUTHORITY_HASH,
  DEMO_WORLD_V35_V34_FIELD_HASH,
  type DemoWorldV35Assignment,
  type DemoWorldV35Plan,
  type DemoWorldV35SeasonFieldAllocation,
} from "../../app/demo-world/demo-world-v3-5-contract";
import type {
  SyntheticSeasonIndex,
  SyntheticSeasonMatch,
} from "../../app/demo-world/demo-world-v3-2-contract";
import type {
  DemoWorldV34FieldOperations,
  DemoWorldV34Pitch,
} from "../../app/demo-world/demo-world-v3-4-contract";

type DatabaseProof = {
  canonicalLifecycle?: string;
  cleanup?: string;
  finalLedger?: number;
  schemaHash?: string;
};

type ProjectedAllocation = {
  index: number;
  match: SyntheticSeasonMatch;
  modality: "F7" | "FUTSAL";
  pitch: DemoWorldV34Pitch | null;
};

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const outputDir = resolve(root, "public/demo-world/v3-5");
const season = JSON.parse(await readFile(resolve(root, "public/demo-world/v3-2/season.json"), "utf8")) as SyntheticSeasonIndex;
const fields = JSON.parse(await readFile(resolve(root, "public/demo-world/v3-4/field-operations.json"), "utf8")) as DemoWorldV34FieldOperations;

const dbOutput = execFileSync(process.execPath, [resolve(root, "tests/season-venue-allocation-v1-db-runner.mjs")], {
  cwd: root,
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
});
const dbProof = JSON.parse(dbOutput.trim().split("\n").at(-1) ?? "{}") as DatabaseProof;
if (dbProof.canonicalLifecycle !== "PASS" || dbProof.cleanup !== "PASS" || dbProof.finalLedger !== 228) {
  throw new Error("DEMO_WORLD_V35_RPC_CONFORMANCE_REQUIRED");
}

const competitions = new Map(season.competitions.map((value) => [value.id, value]));
const teams = new Map(season.teams.map((value) => [value.id, value]));
const pitches = fields.pitches.filter((pitch) => pitch.status === "ACTIVE");
const venues = new Map(fields.venues.map((value) => [value.id, value]));
const autoConflicts = new Set([17, 36, 55, 74, 93, 110, 111]);
const hybridConflict = new Set([111]);
const lockedMatches = new Set([24, 63, 96]);
const movedMatch = 42;
const cancelledReservation = 88;

function modalityFor(match: SyntheticSeasonMatch): "F7" | "FUTSAL" {
  return competitions.get(match.competitionId)?.modality === "FUTSAL" ? "FUTSAL" : "F7";
}

function candidates(modality: "F7" | "FUTSAL") {
  return pitches.filter((pitch) => pitch.modalities.includes(modality));
}

function allocate(mode: "AUTOMATIC" | "HYBRID"): ProjectedAllocation[] {
  const occupied = new Map<string, Array<[number, number]>>();
  const forced = mode === "AUTOMATIC" ? autoConflicts : hybridConflict;
  return season.matches.map((match, index) => {
    const modality = modalityFor(match);
    const start = Date.parse(match.scheduledAt);
    const end = start + 70 * 60_000;
    const options = candidates(modality);
    const offset = mode === "HYBRID" && index === movedMatch ? 1 : 0;
    let selected: DemoWorldV34Pitch | null = null;
    if (!forced.has(index)) {
      for (let step = 0; step < options.length; step += 1) {
        const candidate = options[(index + offset + step) % options.length];
        const collisions = occupied.get(candidate.id) ?? [];
        if (collisions.every(([from, until]) => end <= from || start >= until)) {
          selected = candidate;
          collisions.push([start, end]);
          occupied.set(candidate.id, collisions);
          break;
        }
      }
    }
    return { index, match, modality, pitch: selected };
  });
}

const automatic = allocate("AUTOMATIC");
const hybrid = allocate("HYBRID");

const assignments: DemoWorldV35Assignment[] = hybrid.map(({ index, match, modality, pitch }) => {
  const unassigned = !pitch;
  const cancelled = index === cancelledReservation;
  return {
    assignmentStatus: unassigned ? "UNASSIGNED" : "ASSIGNED",
    awayTeamId: match.awayTeamId,
    awayTeamName: teams.get(match.awayTeamId)?.name ?? "Equipo visitante",
    bindingStatus: unassigned ? "NONE" : cancelled ? "ACTION_REQUIRED" : "ACTIVE",
    canonicalMatchId: match.canonicalMatchId,
    competitionId: match.competitionId ?? "synthetic_friendly_schedule",
    conflictCodes: unassigned ? ["VENUE_ALLOCATION_CONFLICT"] : cancelled ? ["RESERVATION_CANCELLED_AFTER_PUBLISH"] : [],
    homeTeamId: match.homeTeamId,
    homeTeamName: teams.get(match.homeTeamId)?.name ?? "Equipo local",
    lockType: lockedMatches.has(index) ? (index === 96 ? "FINAL_TO_PITCH" : "MATCH_TO_PITCH") : null,
    modality,
    pitchId: pitch?.id ?? null,
    pitchName: pitch?.name ?? null,
    reservationStatus: unassigned ? "NONE" : cancelled ? "CANCELLED" : "CONFIRMED",
    scheduledAfter: match.scheduledAt,
    scheduledBefore: match.scheduledAt,
    sourceKind: unassigned ? null : !match.competitionId ? "EXISTING_BINDING" : match.competitionId.includes("league") && index % 2 === 0 ? "RECURRING_OCCURRENCE" : "AUTHORIZED_PITCH",
    venueId: pitch?.venueId ?? null,
    venueName: pitch ? venues.get(pitch.venueId)?.name ?? null : null,
  };
});

function planChecksum(value: unknown) {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

const plans: DemoWorldV35Plan[] = season.competitions.flatMap((competition, competitionIndex) => {
  const automaticItems = automatic.filter(({ match }) => match.competitionId === competition.id);
  const hybridItems = hybrid.filter(({ match }) => match.competitionId === competition.id);
  const plan = (mode: "AUTOMATIC" | "HYBRID", items: ProjectedAllocation[], suffix: string): DemoWorldV35Plan => {
    const assigned = items.filter((item) => item.pitch).length;
    return {
      algorithmVersion: "season-venue-allocation-v1",
      assignedMatches: assigned,
      competitionId: competition.id,
      hardViolations: 0,
      id: `demo_allocation_${competitionIndex + 1}_${suffix}`,
      lockCount: mode === "HYBRID" ? items.filter(({ index }) => lockedMatches.has(index)).length : 0,
      mode,
      qualityScore: mode === "HYBRID" ? 96.4 : 90.8,
      resultChecksum: planChecksum(items.map(({ match, pitch }) => [match.canonicalMatchId, pitch?.id ?? null])),
      seed: mode === "HYBRID" ? `demo-v35-${competition.id}-hybrid` : `demo-v35-${competition.id}-automatic`,
      unassignedMatches: items.length - assigned,
    };
  };
  return [plan("AUTOMATIC", automaticItems, "automatic"), plan("HYBRID", hybridItems, "hybrid")];
});

const series = season.competitions.map((competition, index) => ({
  competitionId: competition.id,
  endDate: "2027-01-31",
  frequency: (competition.kind === "LEAGUE" ? "WEEKLY" : "BIWEEKLY") as "WEEKLY" | "BIWEEKLY",
  id: `demo_recurring_series_${index + 1}`,
  occurrenceCount: competition.kind === "LEAGUE" ? 16 : 8,
  pitchId: candidates(competition.modality === "FUTSAL" ? "FUTSAL" : "F7")[index % candidates(competition.modality === "FUTSAL" ? "FUTSAL" : "F7").length].id,
  startDate: "2026-10-01",
  status: "PUBLISHED" as const,
  weekday: competition.kind === "LEAGUE" ? 4 : 6,
}));

const pools = season.competitions.map((competition, index) => ({
  competitionId: competition.id,
  id: `demo_venue_pool_${index + 1}`,
  pitchIds: candidates(competition.modality === "FUTSAL" ? "FUTSAL" : "F7").map((pitch) => pitch.id),
  status: "ACTIVE" as const,
}));

const utilization = fields.pitches.map((pitch) => {
  const count = assignments.filter((item) => item.pitchId === pitch.id).length;
  return { assignments: count, pitchId: pitch.id, utilization: Math.round((count / Math.max(1, assignments.length)) * 1000) / 10, venueId: pitch.venueId };
});

const data: DemoWorldV35SeasonFieldAllocation = {
  assignments,
  authority: {
    database: "temporary-local-postgresql",
    executionMode: "REAL_RPC_CONFORMANCE_PLUS_DETERMINISTIC_128_MATCH_PROJECTION",
    migrationLedger: 228,
    rpcConformance: "PASS",
    schemaHash: dbProof.schemaHash,
    temporaryDatabaseDestroyed: true,
    v32AuthorityHash: DEMO_WORLD_V35_V32_AUTHORITY_HASH,
    v34FieldOperationsHash: DEMO_WORLD_V35_V34_FIELD_HASH,
  },
  conflicts: [
    { code: "PITCH_MAINTENANCE", outcome: "Campo excluido", resolved: true, summary: "Municipal A permanece fuera del pool mientras dura el mantenimiento." },
    { code: "RECURRING_OCCURRENCE_CANCELLED", outcome: "Slot alternativo", resolved: true, summary: "Una ocurrencia recurrente cancelada no desplazó la hora del partido." },
    { code: "HOLD_EXPIRED", outcome: "Hold renovado", resolved: true, summary: "El hold expiró sin convertirse en reserva y la revisión se recalculó." },
    { code: "PITCH_SLOT_COMPETITION", outcome: "Ganador canónico", resolved: true, summary: "Dos partidos compitieron por el mismo Pitch; solo uno obtuvo el slot." },
    { code: "VENUE_ALLOCATION_CONFLICT", outcome: "Sin campo asignado", resolved: false, summary: "Un partido permanece visible sin campo; la fecha y la hora no se alteran." },
    { code: "RESERVATION_CANCELLED_AFTER_PUBLISH", outcome: "Acción requerida", resolved: false, summary: "La cancelación preserva el Match y abre el flujo de sustitución R4D." },
    { code: "R4D_VENUE_CHANGE", outcome: "Binding sustituido", resolved: true, summary: "El cambio conserva lineage y solicita reconfirmación al árbitro." },
  ],
  counts: { activeBindings: 126, clubs: 6, competitions: 4, matches: 128, pitches: 8, plans: 8, pools: 4, recurringSeries: 4, reservations: 127, teams: 32, venues: 4, weeks: 16 },
  integrity: { activeBindingDuplicates: 0, confirmedOverlaps: 0, hardViolationsPublished: 0, matchTimesModified: 0, stripeCalls: 0 },
  plans,
  pools,
  perspectives: ["club-booking-manager", "league-organizer", "tournament-organizer", "team-owner", "player", "referee", "platform-reviewer"],
  privacy: { authIds: false, exactPrivateLocations: false, pii: false },
  readOnly: true,
  recurringSeries: series,
  remoteWrites: 0,
  utilization,
  version: 3.5,
};

const bytes = `${JSON.stringify(data)}\n`;
const hash = createHash("sha256").update(bytes).digest("hex");
const manifest = {
  authority: { fieldOperationsHash: DEMO_WORLD_V35_V34_FIELD_HASH, seasonHash: DEMO_WORLD_V35_V32_AUTHORITY_HASH },
  mode: "season-field-allocation-read-only",
  privacy: { authIds: false, pii: false },
  remoteWrites: 0,
  seasonFieldAllocation: { hash, matches: 128, path: `/demo-world/v3-5/season-field-allocation.json?h=${hash.slice(0, 16)}` },
  version: 3.5,
};

await mkdir(outputDir, { recursive: true });
await writeFile(resolve(outputDir, "season-field-allocation.json"), bytes);
await writeFile(resolve(outputDir, "manifest.json"), `${JSON.stringify(manifest)}\n`);
process.stdout.write(`${JSON.stringify({ hash, matches: assignments.length, schemaHash: dbProof.schemaHash, rpcConformance: "PASS", outputDir, venues: venues.size })}\n`);
