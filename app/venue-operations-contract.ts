export type VenueJson = Record<string, unknown>;

export const VENUE_MODALITIES = ["F5", "F7", "F11", "FUTSAL"] as const;
export const VENUE_ENVIRONMENTS = ["INDOOR", "OUTDOOR", "COVERED"] as const;
export const VENUE_SURFACES = ["ARTIFICIAL_GRASS", "NATURAL_GRASS", "PARQUET", "CONCRETE", "OTHER"] as const;

export const venueStatusLabels: Record<string, string> = {
  ACCEPTED: "Aceptada por el Club",
  ACTION_REQUIRED: "Requiere acción",
  ACTIVE: "Activa",
  AVAILABLE: "Disponible",
  BLOCKED: "Bloqueado",
  CANCELLED: "Cancelada",
  CONFIRMED: "Confirmada",
  CONSUMED: "Finalizada",
  COUNTER_PROPOSED: "Contrapropuesta",
  DRAFT: "Borrador",
  EXPIRED: "Caducada",
  HELD: "Bloqueo temporal",
  MAINTENANCE: "Mantenimiento",
  OCCUPIED: "Ocupado",
  PENDING_CONFIRMATION: "Pendiente de confirmar",
  PENDING_REVIEW: "Pendiente de revisión",
  REJECTED: "Rechazada",
  SUBMITTED: "Enviada",
  SUSPENDED: "Suspendida",
  UNDER_REVIEW: "En revisión",
  UNASSIGNED: "Sin campo",
  WITHDRAWN: "Retirada",
};

export function venueRecord(value: unknown): VenueJson {
  return value && typeof value === "object" && !Array.isArray(value) ? value as VenueJson : {};
}

export function venueArray(value: unknown): VenueJson[] {
  return Array.isArray(value) ? value.map(venueRecord) : [];
}

export function venueTextArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

export function venueText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function venueNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function venueBoolean(value: unknown) {
  return value === true;
}

export function venueStatusLabel(value: unknown) {
  const status = venueText(value).toUpperCase();
  const fallback = status.replaceAll("_", " ").toLocaleLowerCase("es-ES");
  return venueStatusLabels[status] ?? (fallback || "Sin estado");
}

export function venueDateTime(value: unknown, timezone = "Europe/Madrid") {
  const raw = venueText(value);
  if (!raw || Number.isNaN(Date.parse(raw))) return "Fecha pendiente";
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: timezone,
  }).format(new Date(raw));
}

export function venueMoney(amountMinor: unknown, currency: unknown) {
  const amount = venueNumber(amountMinor);
  const code = venueText(currency) || "EUR";
  return new Intl.NumberFormat("es-ES", { currency: code, style: "currency" }).format(amount / 100);
}

export function venueCacheKey(scope: string, actorId = "public") {
  return "pachangas-venue-read-v1:" + scope + ":" + actorId;
}

export function readVenueCache(scope: string, actorId?: string) {
  if (typeof localStorage === "undefined") return null;
  try {
    const envelope = venueRecord(JSON.parse(localStorage.getItem(venueCacheKey(scope, actorId)) ?? "null"));
    return venueNumber(envelope.version) === 1 ? venueRecord(envelope.data) : null;
  } catch {
    return null;
  }
}

export function writeVenueCache(scope: string, data: VenueJson, actorId?: string) {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(venueCacheKey(scope, actorId), JSON.stringify({
      data,
      storedAt: new Date().toISOString(),
      version: 1,
    }));
  } catch {
    // The canonical read remains available when the optional cache is full.
  }
}

export function venueUuid(value: unknown) {
  const candidate = venueText(value);
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(candidate)
    ? candidate
    : "";
}
