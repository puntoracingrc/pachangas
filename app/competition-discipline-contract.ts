export const competitionDisciplineCacheVersion = 1;
export const competitionDisciplineRealtimeTable = "pachanga_competition_invalidations";
export const competitionDisciplineFlagsAggregateId = "00000000-0000-0000-0000-00000000d501";

export const competitionDisciplineActions = [
  "event.record",
  "event.correct",
  "event.annul",
  "counter.rebuild",
  "cycle.reset",
  "sanction.decide",
  "service.record",
  "service.reverse",
  "appeal.submit",
  "appeal.transition",
  "appeal.withdraw",
] as const;

export type CompetitionDisciplineAction = typeof competitionDisciplineActions[number];
export type CompetitionDisciplineJson = Record<string, unknown>;

const actionSet = new Set<string>(competitionDisciplineActions);

export function isCompetitionDisciplineAction(value: string): value is CompetitionDisciplineAction {
  return actionSet.has(value);
}

export function disciplineRecord(value: unknown): CompetitionDisciplineJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as CompetitionDisciplineJson
    : {};
}

export function disciplineArray(value: unknown): CompetitionDisciplineJson[] {
  return Array.isArray(value) ? value.map(disciplineRecord) : [];
}

export function disciplineText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function disciplineNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function disciplineBoolean(value: unknown) {
  return value === true;
}

export function disciplineFlagsEnabled(value: unknown) {
  const flags = disciplineRecord(value);
  return disciplineBoolean(flags.foundationEnabled)
    && disciplineBoolean(flags.eventsEnabled)
    && disciplineBoolean(flags.countersEnabled)
    && disciplineBoolean(flags.sanctionsEnabled);
}

export function disciplineStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = disciplineText(value).toLowerCase();
  if (["active", "blocked", "overturned", "rejected", "suspended"].includes(status)) return "danger";
  if (["available", "resolved", "served", "upheld"].includes(status)) return "success";
  if (["admissible", "provisional", "submitted", "under_review"].includes(status)) return "warning";
  if (["modified", "pending"].includes(status)) return "info";
  return "neutral";
}

export function disciplineCardLabel(value: unknown) {
  const code = disciplineText(value).toUpperCase();
  return ({ BLUE: "Azul", RED: "Roja", YELLOW: "Amarilla" } as Record<string, string>)[code] ?? code;
}

export function disciplineActionLabel(action: string) {
  return ({
    "appeal.submit": "Presentar apelación",
    "appeal.transition": "Resolver apelación",
    "appeal.withdraw": "Retirar apelación",
    "counter.rebuild": "Reconstruir contadores",
    "cycle.reset": "Abrir nuevo ciclo",
    "event.annul": "Anular tarjeta",
    "event.correct": "Corregir tarjeta",
    "event.record": "Registrar tarjeta",
    "sanction.decide": "Resolver sanción",
    "service.record": "Registrar cumplimiento",
    "service.reverse": "Revertir cumplimiento",
  } as Record<string, string>)[action] ?? action;
}
