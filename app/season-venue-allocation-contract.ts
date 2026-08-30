import {
  venueArray,
  venueNumber,
  venueRecord,
  venueText,
  type VenueJson,
} from "./venue-operations-contract";

export type SeasonVenueSurface =
  | "competition"
  | "planner"
  | "revisions"
  | "recurring-list"
  | "recurring-detail"
  | "pools";

export const seasonVenueModes = ["AUTOMATIC", "MANUAL_ASSISTED", "HYBRID"] as const;

export const seasonVenueStatusLabels: Record<string, string> = {
  accepted: "Aceptado",
  active: "Activo",
  cancelled: "Cancelado",
  conflicted: "Con conflictos",
  draft: "Borrador",
  ended: "Finalizado",
  exhausted: "Agotado",
  generated: "Generado",
  inputs_frozen: "Inputs congelados",
  offered: "Ofrecido",
  partial: "Parcial",
  paused: "Pausado",
  published: "Publicado",
  stale: "Desactualizado",
  validated: "Validado",
};

export function seasonVenueStatus(value: unknown) {
  const status = venueText(value).toLowerCase();
  return seasonVenueStatusLabels[status] ?? (status.replaceAll("_", " ") || "Sin estado");
}

export function seasonVenueMode(value: unknown) {
  const mode = venueText(value).toUpperCase();
  if (mode === "MANUAL_ASSISTED") return "Manual asistido";
  if (mode === "HYBRID") return "Híbrido";
  return "Automático";
}

function cacheKey(scope: string) {
  return `pachangas-season-venue-v1:${scope}`;
}

function containsPrivateKey(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsPrivateKey);
  if (!value || typeof value !== "object") return false;
  return Object.entries(value as VenueJson).some(([key, nested]) => (
    /actor|createdBy|updatedBy|private|contact|latitude|longitude|operationId/i.test(key)
    || containsPrivateKey(nested)
  ));
}

export function readSeasonVenueCache(scope: string) {
  if (typeof localStorage === "undefined") return null;
  try {
    const envelope = venueRecord(JSON.parse(localStorage.getItem(cacheKey(scope)) ?? "null"));
    if (venueNumber(envelope.version) !== 1) return null;
    return venueRecord(envelope.data);
  } catch {
    return null;
  }
}

export function writeSeasonVenueCache(scope: string, data: VenueJson) {
  if (typeof localStorage === "undefined" || containsPrivateKey(data)) return;
  try {
    const serialized = JSON.stringify({
      data,
      serverSequence: venueNumber(data.serverSequence),
      storedAt: new Date().toISOString(),
      version: 1,
    });
    if (serialized.length <= 750_000) localStorage.setItem(cacheKey(scope), serialized);
  } catch {
    // Canonical reads remain available when optional device storage is full.
  }
}

export { venueArray, venueNumber, venueRecord, venueText };
export type { VenueJson };
