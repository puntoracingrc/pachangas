export const leagueSchedulingEngineVersion = "league-round-robin-v1";
export const leagueSchedulingMinimumEntries = 2;
export const leagueSchedulingMaximumEntries = 32;
export const leagueSchedulingCacheVersion = 1;
export const leagueSchedulingRealtimeTable = "pachanga_competition_invalidations";
export const leagueSchedulingFlagsAggregateId = "00000000-0000-0000-0000-00000000c4b1";

export const leagueSchedulingActions = [
  "schedule_plan.create",
  "schedule_slot.create",
  "schedule_slot.bulk_create",
  "schedule_slot.update",
  "schedule_slot.retire",
  "schedule.generate",
  "schedule.regenerate",
  "schedule_item.move_slot",
  "schedule_item.swap_slot",
  "schedule_item.swap_home_away",
  "round.rename",
  "schedule.validate",
  "schedule.publish",
  "schedule.cancel",
] as const;

export type LeagueSchedulingAction = typeof leagueSchedulingActions[number];
export type LeagueSchedulingJson = Record<string, unknown>;

const actionSet = new Set<string>(leagueSchedulingActions);

export function isLeagueSchedulingAction(value: string): value is LeagueSchedulingAction {
  return actionSet.has(value);
}

export function scheduleRecord(value: unknown): LeagueSchedulingJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as LeagueSchedulingJson
    : {};
}

export function scheduleArray(value: unknown): LeagueSchedulingJson[] {
  return Array.isArray(value) ? value.map(scheduleRecord) : [];
}

export function scheduleText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function scheduleNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function scheduleStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = scheduleText(value).toLowerCase();
  if (["current", "published", "scheduled", "valid", "validated"].includes(status)) return "success";
  if (["cancelled", "conflicted", "invalid", "stale_input"].includes(status)) return "danger";
  if (["assigned", "generated", "pending", "tbd", "unassigned"].includes(status)) return "warning";
  if (["draft", "available"].includes(status)) return "info";
  return "neutral";
}

export function scheduleActionLabel(action: string) {
  const labels: Record<string, string> = {
    "round.rename": "Renombrar jornada",
    "schedule.cancel": "Cancelar borrador",
    "schedule.generate": "Generar calendario",
    "schedule.publish": "Publicar calendario",
    "schedule.regenerate": "Nueva revisión",
    "schedule.validate": "Validar calendario",
    "schedule_item.move_slot": "Mover partido",
    "schedule_item.swap_home_away": "Invertir localía",
    "schedule_item.swap_slot": "Intercambiar horarios",
    "schedule_slot.bulk_create": "Duplicar patrón semanal",
    "schedule_slot.create": "Crear horario",
    "schedule_slot.retire": "Retirar horario",
    "schedule_slot.update": "Editar horario",
  };
  return labels[action] ?? action;
}
