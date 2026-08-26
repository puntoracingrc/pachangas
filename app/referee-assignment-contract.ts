import {
  refereeDateLabel,
  refereeNumber,
  refereeRecord,
  refereeText,
  type RefereeJson,
} from "./referee-platform-contract";

export const refereeAssignmentStatuses = [
  "proposed",
  "accepted",
  "declined",
  "confirmed",
  "cancelled",
  "expired",
  "replaced",
  "completed",
] as const;

export const refereeScheduleStates = [
  "CURRENT",
  "STALE_SCHEDULE",
  "RECONFIRMATION_REQUIRED",
  "CANCELLED",
] as const;

export const refereeFeeModes = ["FREE", "FIXED", "NEGOTIABLE", "VOLUNTEER"] as const;

export type RefereeAssignmentStatus = (typeof refereeAssignmentStatuses)[number];
export type RefereeScheduleState = (typeof refereeScheduleStates)[number];
export type RefereeFeeMode = (typeof refereeFeeModes)[number];

const statusLabels: Record<RefereeAssignmentStatus, string> = {
  accepted: "Aceptada",
  cancelled: "Cancelada",
  completed: "Completada",
  confirmed: "Confirmada",
  declined: "Rechazada",
  expired: "Expirada",
  proposed: "Pendiente",
  replaced: "Reemplazada",
};

const scheduleLabels: Record<RefereeScheduleState, string> = {
  CANCELLED: "Partido cancelado",
  CURRENT: "Horario confirmado",
  RECONFIRMATION_REQUIRED: "Reconfirmación necesaria",
  STALE_SCHEDULE: "Nuevo horario pendiente",
};

export function refereeAssignmentStatusLabel(value: unknown) {
  const status = refereeText(value) as RefereeAssignmentStatus;
  return statusLabels[status] ?? refereeText(value).replaceAll("_", " ");
}

export function refereeScheduleStateLabel(value: unknown) {
  const state = refereeText(value) as RefereeScheduleState;
  return scheduleLabels[state] ?? refereeText(value).replaceAll("_", " ");
}

export function refereeAssignmentTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = refereeText(value);
  if (["declined", "cancelled", "expired"].includes(status)) return "danger";
  if (["confirmed", "completed"].includes(status)) return "success";
  if (["proposed", "accepted"].includes(status)) return "warning";
  if (status === "replaced") return "info";
  return "neutral";
}

export function refereeAssignmentTitle(value: unknown) {
  const assignment = refereeRecord(value);
  const referee = refereeRecord(assignment.referee);
  return refereeText(assignment.matchTitle)
    || refereeText(assignment.competitionName)
    || refereeText(referee.displayName)
    || "Partido canónico";
}

export function refereeAssignmentDate(value: unknown) {
  const assignment = refereeRecord(value);
  return refereeDateLabel(
    assignment.effectiveScheduledStart || assignment.scheduledStart,
    assignment.effectiveTimezone || assignment.timezone,
  );
}

export function refereePrivateTerms(value: unknown) {
  const assignment = refereeRecord(value);
  return refereeRecord(assignment.privateTerms);
}

export function refereeFeeLabel(value: unknown) {
  const terms = refereePrivateTerms(value);
  const mode = refereeText(terms.feeMode) as RefereeFeeMode;
  if (mode === "FREE") return "Sin tarifa";
  if (mode === "VOLUNTEER") return "Voluntario";
  if (mode === "NEGOTIABLE" && !refereeNumber(terms.agreedFeeCents)) return "Negociable";
  const cents = refereeNumber(terms.agreedFeeCents)
    || refereeNumber(terms.counterFeeCents)
    || refereeNumber(terms.proposedFeeCents);
  if (!cents) return mode === "FIXED" ? "Tarifa fija" : "Negociable";
  return new Intl.NumberFormat("es-ES", {
    currency: refereeText(terms.currency) || "EUR",
    style: "currency",
  }).format(cents / 100);
}

export function refereeAssignmentActions(value: unknown, capabilities: unknown) {
  const assignment = refereeRecord(value);
  const access = refereeRecord(capabilities);
  const status = refereeText(assignment.status);
  const schedule = refereeText(assignment.scheduleState);
  const terms = refereePrivateTerms(assignment);
  const termsStatus = refereeText(terms.status);
  const feeMode = refereeText(terms.feeMode);
  const refereeOwner = access.refereeOwner === true;
  const requesterManage = access.requesterManage === true;
  const actions: string[] = [];
  if (refereeOwner && status === "proposed") actions.push("assignment.accept", "assignment.decline");
  if (refereeOwner && status === "proposed" && termsStatus === "PROPOSED"
      && ["FIXED", "NEGOTIABLE"].includes(feeMode)) actions.push("terms.counter");
  if (requesterManage && status === "proposed" && termsStatus === "COUNTERED") {
    actions.push("terms.accept", "terms.decline");
  }
  if (refereeOwner && ["STALE_SCHEDULE", "RECONFIRMATION_REQUIRED"].includes(schedule)
      && ["accepted", "confirmed"].includes(status)) actions.push("assignment.reconfirm");
  if (requesterManage && status === "accepted" && schedule === "CURRENT") actions.push("assignment.confirm");
  if ((refereeOwner || requesterManage) && ["proposed", "accepted", "confirmed"].includes(status)) {
    actions.push("assignment.cancel");
  }
  if (requesterManage && status === "confirmed") actions.push("assignment.replace");
  if (refereeOwner && status === "confirmed" && schedule === "CURRENT") {
    actions.push("result.observe", "discipline.record");
  }
  return actions;
}

export function refereeAssignmentRevision(value: unknown) {
  return Math.max(0, Math.floor(refereeNumber(refereeRecord(value).revision)));
}

export function refereeAssignmentArray(value: unknown): RefereeJson[] {
  return Array.isArray(value) ? value.map(refereeRecord) : [];
}
