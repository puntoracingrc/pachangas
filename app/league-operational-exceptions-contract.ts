export const leagueOperationalExceptionsCacheVersion = 1;
export const leagueOperationalExceptionsRealtimeTable = "pachanga_competition_invalidations";
export const leagueOperationalExceptionsFlagsAggregateId = "00000000-0000-0000-0000-00000000c4d1";

export const leagueOperationalExceptionActions = [
  "postponement.request",
  "postponement.respond",
  "postponement.withdraw",
  "postponement.expire",
  "fixture.reschedule",
  "fixture.change_venue",
  "fixture.cancel",
  "late_arrival.report",
  "late_arrival.confirm_arrival",
  "late_arrival.escalate",
  "no_show.report",
  "no_show.confirm",
  "no_show.reject",
  "no_show.resolve",
  "suspension.report",
  "suspension.confirm",
  "suspension.schedule_resume",
  "suspension.resume",
  "suspension.order_replay",
  "suspension.resolve",
  "suspension.cancel",
  "administrative_decision.publish",
  "administrative_decision.supersede",
  "administrative_decision.annul",
] as const;

export type LeagueOperationalExceptionAction = typeof leagueOperationalExceptionActions[number];
export type LeagueOperationalJson = Record<string, unknown>;

const actionSet = new Set<string>(leagueOperationalExceptionActions);

export function isLeagueOperationalExceptionAction(value: string): value is LeagueOperationalExceptionAction {
  return actionSet.has(value);
}

export function leagueOperationalRecord(value: unknown): LeagueOperationalJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as LeagueOperationalJson
    : {};
}

export function leagueOperationalArray(value: unknown): LeagueOperationalJson[] {
  return Array.isArray(value) ? value.map(leagueOperationalRecord) : [];
}

export function leagueOperationalText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function leagueOperationalNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function leagueOperationalBoolean(value: unknown) {
  return value === true;
}

export function leagueOperationalStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = leagueOperationalText(value).toLowerCase();
  if (["accepted", "approved", "arrived_within_policy", "confirmed", "play_confirmed", "resolved", "resumed", "scheduled"].includes(status)) return "success";
  if (["abandoned", "annulled", "cancelled", "denied", "rejected", "stale", "withdrawn"].includes(status)) return "danger";
  if (["administrative_review", "awaiting_response", "escalated_to_no_show", "postponed", "reported", "resume_scheduled", "suspended", "under_review"].includes(status)) return "warning";
  if (["inspection_required", "requested"].includes(status)) return "info";
  return "neutral";
}

export function leagueOperationalActionLabel(action: string) {
  const labels: Record<string, string> = {
    "administrative_decision.annul": "Anular decisión",
    "administrative_decision.publish": "Publicar decisión",
    "administrative_decision.supersede": "Sustituir decisión",
    "fixture.cancel": "Cancelar partido",
    "fixture.change_venue": "Cambiar sede",
    "fixture.reschedule": "Reprogramar",
    "late_arrival.confirm_arrival": "Confirmar llegada",
    "late_arrival.escalate": "Escalar retraso",
    "late_arrival.report": "Reportar retraso",
    "no_show.confirm": "Confirmar incomparecencia",
    "no_show.reject": "Rechazar incomparecencia",
    "no_show.report": "Reportar incomparecencia",
    "no_show.resolve": "Cerrar incomparecencia",
    "postponement.expire": "Procesar deadline",
    "postponement.request": "Solicitar aplazamiento",
    "postponement.respond": "Responder solicitud",
    "postponement.withdraw": "Retirar solicitud",
    "suspension.cancel": "Cancelar partido suspendido",
    "suspension.confirm": "Confirmar suspensión",
    "suspension.order_replay": "Ordenar repetición",
    "suspension.report": "Reportar suspensión",
    "suspension.resolve": "Resolver administrativamente",
    "suspension.resume": "Confirmar reanudación",
    "suspension.schedule_resume": "Programar reanudación",
  };
  return labels[action] ?? action;
}

export function leagueOperationalFlagsEnabled(value: unknown) {
  return leagueOperationalBoolean(leagueOperationalRecord(value).foundationEnabled);
}
