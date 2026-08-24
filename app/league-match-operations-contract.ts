export const leagueMatchOperationsCacheVersion = 1;
export const leagueMatchOperationsRealtimeTable = "pachanga_competition_invalidations";
export const leagueMatchOperationsFlagsAggregateId = "00000000-0000-0000-0000-00000000c4c1";

export const leagueMatchOperationsActions = [
  "squad.create",
  "squad.member.add",
  "squad.member.remove",
  "squad.submit",
  "squad.validate",
  "squad.reject",
  "squad.lock",
  "attendance.set",
  "attendance.close",
  "match.mark_ready",
  "match.start",
  "match.mark_played",
  "sporting_result.submit",
  "sporting_result.accept",
  "sporting_result.propose_change",
  "sporting_result.dispute",
  "official_result.publish",
  "official_result.supersede",
  "official_result.annul",
  "standings.rebuild",
  "standings.draw_lot.confirm",
  "round.complete",
  "round.lock",
] as const;

export type LeagueMatchOperationsAction = typeof leagueMatchOperationsActions[number];
export type LeagueMatchOperationsJson = Record<string, unknown>;

const actionSet = new Set<string>(leagueMatchOperationsActions);

export function isLeagueMatchOperationsAction(value: string): value is LeagueMatchOperationsAction {
  return actionSet.has(value);
}

export function leagueMatchRecord(value: unknown): LeagueMatchOperationsJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as LeagueMatchOperationsJson
    : {};
}

export function leagueMatchArray(value: unknown): LeagueMatchOperationsJson[] {
  return Array.isArray(value) ? value.map(leagueMatchRecord) : [];
}

export function leagueMatchText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function leagueMatchNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function leagueMatchBoolean(value: unknown) {
  return value === true;
}

export function leagueMatchStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = leagueMatchText(value).toLowerCase();
  if (["accepted", "completed", "confirmed", "current", "going", "locked", "official", "ready", "validated"].includes(status)) return "success";
  if (["annulled", "disputed", "error", "not_going", "rejected", "stale"].includes(status)) return "danger";
  if (["change_proposed", "in_progress", "pending", "played", "result_pending", "submitted"].includes(status)) return "warning";
  if (["draft", "scheduled"].includes(status)) return "info";
  return "neutral";
}

export function leagueMatchActionLabel(action: string) {
  const labels: Record<string, string> = {
    "attendance.close": "Cerrar asistencia",
    "attendance.set": "Actualizar asistencia",
    "match.mark_played": "Marcar como jugado",
    "match.mark_ready": "Preparar partido",
    "match.start": "Iniciar partido",
    "official_result.annul": "Anular resultado oficial",
    "official_result.publish": "Publicar resultado oficial",
    "official_result.supersede": "Corregir resultado oficial",
    "round.complete": "Completar jornada",
    "round.lock": "Bloquear jornada",
    "sporting_result.accept": "Aceptar resultado",
    "sporting_result.dispute": "Abrir disputa",
    "sporting_result.propose_change": "Proponer cambio",
    "sporting_result.submit": "Enviar resultado",
    "squad.create": "Crear convocatoria",
    "squad.lock": "Bloquear convocatoria",
    "squad.member.add": "Añadir jugador",
    "squad.member.remove": "Quitar jugador",
    "squad.reject": "Rechazar convocatoria",
    "squad.submit": "Enviar convocatoria",
    "squad.validate": "Validar convocatoria",
    "standings.draw_lot.confirm": "Confirmar sorteo",
    "standings.rebuild": "Reconstruir clasificación",
  };
  return labels[action] ?? action;
}
