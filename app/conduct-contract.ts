import { CLIENT_VERSION } from "./client-version-contract";
import { currentClientDisplayMode, pwaBridgeSnapshot } from "./pwa-client-bridge";

export type AttendanceOutcome = "played" | "excused_absence" | "late_cancellation" | "unexcused_no_show";

export type AttendanceFact = {
  currentOutcome: AttendanceOutcome;
  displayName: string;
  disputeDeadline?: string;
  groupId: string;
  id: string;
  matchId: string;
  originalOutcome: AttendanceOutcome;
  playerId: string;
  responseState: string;
  revision: number;
  serverSequence: number;
};

export type ConductAction = {
  category?: string;
  effectiveUntil?: string;
  reference: string;
  revision: number;
  serverSequence: number;
  state: string;
  type?: string;
};

export type ConductAppeal = {
  actionKind: "warning" | "restriction";
  reference: string;
  revision: number;
  state: string;
};

export type SubmittedConductReport = {
  category: string;
  contextId: string;
  contextKind: string;
  createdAt: string;
  reference: string;
  state: string;
};

export type MyConductSnapshot = {
  appeals: ConductAppeal[];
  attendance: AttendanceFact[];
  policyVersion: string;
  restrictions: ConductAction[];
  revision: number;
  submittedReports: SubmittedConductReport[];
  warnings: ConductAction[];
};

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function text(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function integer(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.floor(parsed)) : fallback;
}

function rows(value: unknown) {
  return Array.isArray(value) ? value : [];
}

export function conductClientMetadata(surface: string) {
  const bridge = pwaBridgeSnapshot();
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    serviceWorkerVersion: bridge.serviceWorkerVersion,
    surface,
  };
}

export function normalizeMyConductSnapshot(value: unknown): MyConductSnapshot {
  const source = record(value) ?? {};
  return {
    appeals: rows(source.appeals).flatMap((value) => {
      const row = record(value);
      if (!row || !text(row.reference)) return [];
      const actionKind = row.actionKind === "restriction" ? "restriction" : "warning";
      return [{ actionKind, reference: text(row.reference), revision: integer(row.revision, 1), state: text(row.state) }];
    }),
    attendance: rows(source.attendance).flatMap((value) => {
      const row = record(value);
      if (!row || !text(row.id)) return [];
      const currentOutcome = text(row.currentOutcome) as AttendanceOutcome;
      const originalOutcome = text(row.originalOutcome) as AttendanceOutcome;
      return [{
        currentOutcome,
        displayName: text(row.displayName, "Jugador"),
        disputeDeadline: text(row.disputeDeadline) || undefined,
        groupId: text(row.groupId),
        id: text(row.id),
        matchId: text(row.matchId),
        originalOutcome,
        playerId: text(row.playerId),
        responseState: text(row.responseState),
        revision: integer(row.revision, 1),
        serverSequence: integer(row.serverSequence),
      }];
    }),
    policyVersion: text(source.policyVersion, "conduct-v1"),
    restrictions: normalizeActions(source.restrictions),
    revision: integer(source.revision),
    submittedReports: rows(source.submittedReports).flatMap((value) => {
      const row = record(value);
      if (!row || !text(row.reference)) return [];
      return [{
        category: text(row.category), contextId: text(row.contextId), contextKind: text(row.contextKind),
        createdAt: text(row.createdAt), reference: text(row.reference), state: text(row.state),
      }];
    }),
    warnings: normalizeActions(source.warnings),
  };
}

function normalizeActions(value: unknown): ConductAction[] {
  return rows(value).flatMap((value) => {
    const row = record(value);
    if (!row || !text(row.reference)) return [];
    return [{
      category: text(row.category) || undefined,
      effectiveUntil: text(row.effectiveUntil) || undefined,
      reference: text(row.reference),
      revision: integer(row.revision, 1),
      serverSequence: integer(row.serverSequence),
      state: text(row.state),
      type: text(row.type) || undefined,
    }];
  });
}

export const attendanceOutcomeLabels: Record<AttendanceOutcome, string> = {
  played: "Jugó",
  excused_absence: "Ausencia justificada",
  late_cancellation: "Cancelación tardía",
  unexcused_no_show: "No asistencia sin aviso",
};

export const conductCategoryLabels: Record<string, string> = {
  abusive_behavior: "Comportamiento abusivo",
  harassment: "Acoso",
  threats_or_violence: "Amenazas o violencia",
  discriminatory_behavior: "Comportamiento discriminatorio",
  deliberate_cheating: "Trampa deliberada",
  repeated_disruption: "Interrupciones reiteradas",
  other: "Otro",
};
