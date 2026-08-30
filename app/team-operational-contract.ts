export type TeamOperationalJson = Record<string, unknown>;

export const TEAM_OPERATIONAL_REALTIME_TABLE = "pachanga_team_operational_invalidations_v1";

export const teamOperationalOwnerActions = [
  "team.lifecycle.archive",
  "team.lifecycle.restore",
  "team.appeal.create",
  "team.appeal.submit",
  "team.appeal.withdraw",
] as const;

export const teamOperationalPlatformActions = [
  "team.review.open",
  "team.review.close",
  "team.restriction.apply",
  "team.restriction.modify",
  "team.restriction.lift",
  "team.suspend",
  "team.restore",
  "team.continuity.set",
  "team.appeal.review",
  "team.appeal.resolve",
] as const;

export type TeamOperationalOwnerAction = (typeof teamOperationalOwnerActions)[number];
export type TeamOperationalPlatformAction = (typeof teamOperationalPlatformActions)[number];
export type TeamOperationalAction = TeamOperationalOwnerAction | TeamOperationalPlatformAction;

export function teamOperationalRecord(value: unknown): TeamOperationalJson {
  return value && typeof value === "object" && !Array.isArray(value) ? value as TeamOperationalJson : {};
}

export function teamOperationalArray(value: unknown) {
  return Array.isArray(value) ? value.map(teamOperationalRecord) : [];
}

export function teamOperationalText(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

export function teamOperationalNumber(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function teamOperationalBoolean(value: unknown) {
  return value === true;
}

export function isTeamOperationalOwnerAction(value: unknown): value is TeamOperationalOwnerAction {
  return typeof value === "string" && (teamOperationalOwnerActions as readonly string[]).includes(value);
}

export function isTeamOperationalPlatformAction(value: unknown): value is TeamOperationalPlatformAction {
  return typeof value === "string" && (teamOperationalPlatformActions as readonly string[]).includes(value);
}

export function teamOperationalCacheKey(actorId: string) {
  return `pachangas-team-operational-v1:${actorId}`;
}

export function teamOperationalStatusLabel(value: unknown) {
  const status = teamOperationalText(value).toUpperCase();
  return ({
    ACTIVE: "Activo",
    ARCHIVED: "Archivado",
    CLEAR: "Sin limitaciones",
    LIMITED: "Limitado",
    SUSPENDED: "Suspendido",
    UNDER_REVIEW: "En revisión",
  } as Record<string, string>)[status] ?? (status ? status.replaceAll("_", " ") : "Sin estado");
}

export function teamOperationalTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = teamOperationalText(value).toUpperCase();
  if (status === "SUSPENDED" || status === "ARCHIVED") return "danger";
  if (status === "LIMITED") return "warning";
  if (status === "UNDER_REVIEW") return "info";
  if (status === "ACTIVE" || status === "CLEAR") return "success";
  return "neutral";
}

export function teamOperationalScopeLabel(value: unknown) {
  const scope = teamOperationalText(value).toUpperCase();
  return ({
    COMPETITION_ORGANIZER: "Organizar competiciones",
    COMPETITION_REGISTRATION: "Inscribirse en competiciones",
    EXISTING_COMPETITION_OPERATIONS: "Operaciones de competiciones en curso",
    GROUP_MEMBERSHIP: "Gestión de miembros",
    MARKETPLACE: "Mercado",
    NEW_MATCH_CREATION: "Crear partidos",
    ONBOARDING: "Onboarding",
    PUBLIC_DISCOVERY: "Directorios y búsquedas",
    PUBLIC_PROFILE: "Perfil público",
    PUBLIC_TEAM_PROFILE: "Perfil público",
    SOCIAL_CHALLENGES: "Retos",
    TEAM_MEMBERSHIP_ADMINISTRATION: "Gestión de miembros",
  } as Record<string, string>)[scope] ?? scope.replaceAll("_", " ");
}

export function teamOperationalContinuityLabel(value: unknown) {
  const policy = teamOperationalText(value).toUpperCase();
  return ({
    ALLOW_EXISTING_COMPETITIONS_TO_FINISH: "Las competiciones ya iniciadas pueden terminar",
    BLOCK_EXISTING_COMPETITION_OPERATIONS: "Operaciones de competición detenidas por decisión explícita",
    FREEZE_FUTURE_SPORTING_WRITES: "Nuevas operaciones deportivas detenidas",
    HISTORY_ONLY: "Solo se conserva el histórico",
    PLATFORM_MANAGED_EXIT: "La plataforma resolverá cada participación afectada",
    REVIEW_EACH_COMPETITION: "La plataforma revisa cada competición afectada",
  } as Record<string, string>)[policy] ?? policy.replaceAll("_", " ");
}

export function teamOperationalAppealLabel(value: unknown) {
  const status = teamOperationalText(value).toUpperCase();
  return ({
    DRAFT: "Borrador",
    INADMISSIBLE: "No admitida",
    MODIFIED: "Medida modificada",
    OVERTURNED: "Medida retirada",
    SUBMITTED: "Enviada",
    UNDER_REVIEW: "En revisión",
    UPHELD: "Medida confirmada",
    WITHDRAWN: "Retirada",
  } as Record<string, string>)[status] ?? status.replaceAll("_", " ");
}

export function teamOperationalIsRelevant(snapshot: unknown) {
  const state = teamOperationalRecord(snapshot);
  const appeal = teamOperationalRecord(state.appeal);
  return teamOperationalText(state.effectiveStatus, "ACTIVE") !== "ACTIVE"
    || ["DRAFT", "SUBMITTED", "UNDER_REVIEW"].includes(teamOperationalText(appeal.status));
}

export function teamOperationalNextAction(snapshot: unknown) {
  const state = teamOperationalRecord(snapshot);
  const appeal = teamOperationalRecord(state.appeal);
  const appealStatus = teamOperationalText(appeal.status);
  if (appealStatus === "DRAFT") return "Revisa y envía la solicitud";
  if (["SUBMITTED", "UNDER_REVIEW"].includes(appealStatus)) return "Espera la respuesta de la plataforma";
  if (teamOperationalText(state.lifecycle) === "ARCHIVED") return "El owner puede restaurar el equipo";
  if (["LIMITED", "SUSPENDED"].includes(teamOperationalText(state.enforcement))) return "Consulta el impacto o solicita revisión";
  if (teamOperationalText(state.enforcement) === "UNDER_REVIEW") return "No hay bloqueo automático mientras se revisa";
  return "Ninguna acción necesaria";
}
