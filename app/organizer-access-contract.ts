export type OrganizerAccessJson = Record<string, unknown>;

export const organizerAccessActions = [
  "application.create",
  "application.update",
  "application.submit",
  "application.withdraw",
  "application.respond_information",
  "application.reconsider",
  "onboarding.refresh",
  "competition.launch",
] as const;

export const organizerAccessPlatformActions = [
  "review.start",
  "review.request_information",
  "review.approve",
  "review.reject",
  "review.expire",
  "settings.flags",
  "rate_limit.override",
] as const;

export type OrganizerAccessAction = typeof organizerAccessActions[number];
export type OrganizerAccessPlatformAction = typeof organizerAccessPlatformActions[number];

export const organizerAccessRealtimeTable = "pachanga_organizer_access_invalidations_v1";
export const organizerAccessCacheVersion = 1;
export const organizerAccessSettingsAggregateId = "00000000-0000-0000-0000-00000000a8a0";

const actionSet = new Set<string>(organizerAccessActions);
const platformActionSet = new Set<string>(organizerAccessPlatformActions);

export function isOrganizerAccessAction(value: unknown): value is OrganizerAccessAction {
  return typeof value === "string" && actionSet.has(value);
}

export function isOrganizerAccessPlatformAction(value: unknown): value is OrganizerAccessPlatformAction {
  return typeof value === "string" && platformActionSet.has(value);
}

export function organizerAccessRecord(value: unknown): OrganizerAccessJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as OrganizerAccessJson
    : {};
}

export function organizerAccessArray(value: unknown): OrganizerAccessJson[] {
  return Array.isArray(value) ? value.map(organizerAccessRecord) : [];
}

export function organizerAccessText(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

export function organizerAccessNumber(value: unknown, fallback = 0) {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function organizerAccessBoolean(value: unknown) {
  return value === true;
}

export function organizerAccessDate(value: unknown, includeTime = false) {
  const raw = organizerAccessText(value);
  const date = new Date(raw);
  if (!raw || Number.isNaN(date.getTime())) return "Pendiente";
  return new Intl.DateTimeFormat("es-ES", includeTime
    ? { dateStyle: "medium", timeStyle: "short", timeZone: "Europe/Madrid" }
    : { dateStyle: "medium", timeZone: "Europe/Madrid" }).format(date);
}

export function organizerAccessStatusLabel(value: unknown) {
  const labels: Record<string, string> = {
    approved: "Aprobada",
    approved_interest: "Interés registrado",
    draft: "Borrador",
    expired: "Expirada",
    needs_information: "Necesita información",
    rejected: "Rechazada",
    submitted: "Enviada",
    under_review: "En revisión",
    withdrawn: "Retirada",
  };
  const key = organizerAccessText(value).toLowerCase();
  return labels[key] ?? (key.replaceAll("_", " ") || "Sin estado");
}

export function organizerAccessTone(value: unknown): "danger" | "good" | "info" | "muted" | "warning" {
  const status = organizerAccessText(value).toLowerCase();
  if (["approved", "active", "completed"].includes(status)) return "good";
  if (["submitted", "under_review", "approved_interest"].includes(status)) return "info";
  if (["needs_information", "draft"].includes(status)) return "warning";
  if (["rejected", "expired", "withdrawn", "revoked"].includes(status)) return "danger";
  return "muted";
}

export function organizerAccessNextActionLabel(value: unknown) {
  const labels: Record<string, string> = {
    ACCESS_APPROVED: "Abrir onboarding",
    COMPLETE_ORGANIZER_PROFILE: "Completar identidad",
    CONFIGURE_RULES: "Configurar reglas",
    CONTINUE_COMPETITION_DRAFT: "Continuar borrador",
    CREATE_FIRST_COMPETITION: "Crear primera competición",
    GENERATE_SCHEDULE: "Generar calendario",
    INVITE_TEAMS: "Invitar equipos",
    ONBOARDING_COMPLETE: "Abrir mis competiciones",
    PREPARE_DRAW: "Preparar sorteo",
    PREPARE_FIRST_MATCH: "Preparar primer partido",
    PUBLISH_COMPETITION: "Publicar competición",
    RESPOND_INFORMATION: "Responder a la plataforma",
    WAIT_FOR_REVIEW: "Esperar revisión",
  };
  const key = organizerAccessText(value);
  return labels[key] ?? "Continuar";
}

export function organizerAccessCacheKey(actorId: string) {
  return `pachangas-organizer-access-v${organizerAccessCacheVersion}:${actorId}`;
}
