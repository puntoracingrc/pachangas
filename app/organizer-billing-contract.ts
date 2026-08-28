export type OrganizerBillingJson = Record<string, unknown>;

export const organizerFeatureLabels: Record<string, string> = {
  competition_appeals_manage: "Resolver apelaciones",
  competition_categories_manage: "Gestionar categorias",
  competition_create: "Crear competiciones",
  competition_discipline: "Aplicar disciplina",
  competition_discipline_manage: "Gestionar expedientes",
  competition_discipline_review: "Revisar disciplina",
  competition_entries_manage: "Gestionar inscripciones",
  competition_manage: "Gestionar competiciones",
  competition_operations: "Operaciones de partido",
  competition_referees: "Coordinar arbitros",
  competition_results: "Oficializar resultados",
  competition_rosters_review: "Revisar plantillas",
  competition_rules: "Configurar reglamento",
  competition_schedule: "Crear calendario",
  competition_staff: "Gestionar staff",
  competition_standings: "Publicar clasificaciones",
  tournament_create: "Crear torneos",
  tournament_draw: "Preparar sorteos",
  tournament_draw_publish: "Publicar sorteos",
  tournament_manage: "Gestionar torneos",
};

export const organizerLimitLabels: Record<string, string> = {
  activeCompetitions: "Competiciones activas",
  activeEditions: "Ediciones activas",
  leagueCreation: "Ligas",
  maxTeamsPerCompetition: "Equipos por competicion",
  publicCompetitions: "Competiciones publicas",
  refereeAssignments: "Asignaciones arbitrales",
  scheduledMatches: "Partidos programados",
  staffSeats: "Miembros de staff",
  storageDocuments: "Documentos",
  tournamentCreation: "Torneos",
};

const billingStatusLabels: Record<string, string> = {
  active: "Activo",
  ACTIVE: "Activo",
  AWAITING_PRICE_APPROVAL: "Precio pendiente de aprobacion",
  canceled: "Cancelado",
  CATALOG_AVAILABLE: "Catalogo disponible",
  continuity: "Continuidad",
  expired: "Expirado",
  grace: "Periodo de gracia",
  incomplete: "Incompleto",
  NOT_APPLICABLE: "No aplica",
  NOT_AVAILABLE: "No disponible",
  open: "Pendiente",
  paid: "Pagada",
  PARTNERSHIP_REVIEW: "Partnership auditada",
  past_due: "Pago pendiente",
  trialing: "Periodo de prueba",
  unpaid: "Impagado",
};

export function organizerBillingRecord(value: unknown): OrganizerBillingJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as OrganizerBillingJson
    : {};
}

export function organizerBillingArray(value: unknown) {
  return Array.isArray(value) ? value.map(organizerBillingRecord) : [];
}

export function organizerBillingText(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

export function organizerBillingNumber(value: unknown, fallback = 0) {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function organizerBillingBoolean(value: unknown) {
  return value === true;
}

export function organizerBillingStatus(value: unknown) {
  const status = organizerBillingText(value);
  const fallback = status.replaceAll("_", " ").toLowerCase() || "Sin estado";
  return billingStatusLabels[status] ?? fallback;
}

export function organizerBillingDate(value: unknown, includeTime = false) {
  const raw = organizerBillingText(value);
  const date = new Date(raw);
  if (!raw || Number.isNaN(date.getTime())) return "No disponible";
  return new Intl.DateTimeFormat("es-ES", includeTime
    ? { dateStyle: "medium", timeStyle: "short" }
    : { dateStyle: "medium" }).format(date);
}

export function organizerBillingMoney(amount: unknown, currency: unknown) {
  const value = organizerBillingNumber(amount, Number.NaN);
  const code = organizerBillingText(currency, "eur").toUpperCase();
  if (!Number.isFinite(value) || !/^[A-Z]{3}$/.test(code)) return "Precio pendiente de publicacion";
  return new Intl.NumberFormat("es-ES", { currency: code, style: "currency" }).format(value / 100);
}

export function organizerBillingSafeUrl(value: unknown) {
  const raw = organizerBillingText(value);
  if (!raw) return "";
  try {
    const url = new URL(raw);
    return url.protocol === "https:" ? url.toString() : "";
  } catch {
    return "";
  }
}

export function organizerBillingTone(value: unknown) {
  const status = organizerBillingText(value).toLowerCase();
  if (/active|paid|processed|approved|available|continuity/.test(status)) return "good";
  if (/past_due|pending|grace|trial|awaiting|incomplete/.test(status)) return "warning";
  if (/cancel|expired|failed|unpaid|blocked|rejected/.test(status)) return "danger";
  return "muted";
}

export function organizerBillingCacheKey(kind: string, id: string) {
  return `pachangas-organizer-billing-v1:${kind.toUpperCase()}:${id}`;
}

export function organizerBillingPlanForKind(plans: OrganizerBillingJson[], kind: string) {
  return plans.find((plan) => organizerBillingText(plan.organizerKind) === kind.toUpperCase()
    && organizerBillingText(plan.accessModel) === "SUBSCRIPTION") ?? null;
}
