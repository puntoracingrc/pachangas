export type TournamentJson = Record<string, unknown>;

export const tournamentDrawActions = [
  "tournament.create",
  "tournament.authoring.save",
  "tournament.cancel",
  "participant.invite",
  "participant.accept",
  "participant.decline",
  "participant.withdraw",
  "draw_plan.create",
  "participants.freeze",
  "participants.unfreeze",
  "draw_pot.create",
  "draw_pot.update",
  "draw_constraint.create",
  "draw_constraint.update",
  "draw_constraint.remove",
  "draw.generate",
  "draw.regenerate",
  "draw.entry.place",
  "draw.entry.move",
  "draw.entry.swap",
  "draw.entry.remove",
  "draw.lock.create",
  "draw.lock.remove",
  "draw.validate",
  "draw.publish",
  "draw.cancel",
] as const;

export type TournamentDrawAction = typeof tournamentDrawActions[number];

export const tournamentPlatformActions = [
  "tournament.flags.set",
  "tournament.kill_switch",
  "tournament.beta_bundle.grant",
  "tournament.beta_bundle.revoke",
] as const;

export type TournamentPlatformAction = typeof tournamentPlatformActions[number];

export const tournamentRealtimeTable = "pachanga_tournament_invalidations" as const;
export const tournamentReadCacheVersion = 1 as const;
export const tournamentAlgorithmVersion = "tournament-draw-v1.0.0" as const;

export const tournamentWizardSteps = [
  { id: 1, label: "Identidad" },
  { id: 2, label: "Modalidad" },
  { id: 3, label: "Edición y fechas" },
  { id: 4, label: "Formato" },
  { id: 5, label: "Participantes" },
  { id: 6, label: "Grupos o cuadro" },
  { id: 7, label: "Bombos y cabezas" },
  { id: 8, label: "Modo de sorteo" },
  { id: 9, label: "Restricciones" },
  { id: 10, label: "Reglas deportivas" },
  { id: 11, label: "Disciplina y árbitros" },
  { id: 12, label: "Revisión" },
] as const;

export const tournamentDrawModes = [
  "PURE_RANDOM",
  "SEEDED_POTS",
  "CONSTRAINT_OPTIMIZED",
  "MANUAL_ASSISTED",
  "HYBRID",
] as const;

export const tournamentDrawTargets = [
  "GROUP_ASSIGNMENT",
  "KNOCKOUT_INITIAL_SEEDING",
  "GROUPS_THEN_KNOCKOUT",
] as const;

export function tournamentRecord(value: unknown): TournamentJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as TournamentJson
    : {};
}

export function tournamentArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function tournamentText(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

export function tournamentNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function tournamentBoolean(value: unknown) {
  return value === true;
}

export function isTournamentDrawAction(value: unknown): value is TournamentDrawAction {
  return typeof value === "string"
    && (tournamentDrawActions as readonly string[]).includes(value);
}

export function isTournamentPlatformAction(value: unknown): value is TournamentPlatformAction {
  return typeof value === "string"
    && (tournamentPlatformActions as readonly string[]).includes(value);
}

export function tournamentStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = tournamentText(value).toLowerCase();
  if (["published", "validated", "valid", "active", "accepted"].includes(status)) return "success";
  if (["invalid", "unsatisfiable", "cancelled", "stale", "revoked"].includes(status)) return "danger";
  if (["generated", "participants_frozen", "invited", "pending"].includes(status)) return "warning";
  if (["draft", "not_granted"].includes(status)) return "neutral";
  return "info";
}
