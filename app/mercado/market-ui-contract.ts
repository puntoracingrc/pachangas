export type MarketDayFilter =
  | "Todos"
  | "Hoy"
  | "Mañana"
  | "Esta semana"
  | "Lunes"
  | "Martes"
  | "Miércoles"
  | "Jueves"
  | "Viernes"
  | "Sábado"
  | "Domingo";

export type MarketSort = "relevance" | "distance" | "date" | "level" | "slots";

export type MarketRouteDetail = {
  id: string;
  kind: "match" | "player" | "team";
} | null;

export type MarketRouteFilters = {
  day: MarketDayFilter;
  maxPrice: number | null;
  maxRating: number | null;
  minRating: number | null;
  modality: string;
  position: string;
  radiusKm: number;
  sort: MarketSort;
  zone: string;
  zonePlaceId?: string;
};

export const MARKET_DAY_FILTERS: MarketDayFilter[] = [
  "Todos",
  "Hoy",
  "Mañana",
  "Esta semana",
  "Lunes",
  "Martes",
  "Miércoles",
  "Jueves",
  "Viernes",
  "Sábado",
  "Domingo",
];

export const MARKET_QUICK_DAYS: MarketDayFilter[] = ["Hoy", "Mañana", "Esta semana"];
export const MARKET_CACHE_KEY = "pachangas-market-read-v3d";
export const MARKET_LOCATION_PREFERENCE_KEY = "pachangas-market-location-v3d";
export const MARKET_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

const weekdayLabels: MarketDayFilter[] = [
  "Domingo",
  "Lunes",
  "Martes",
  "Miércoles",
  "Jueves",
  "Viernes",
  "Sábado",
];

const allowedSorts = new Set<MarketSort>(["relevance", "distance", "date", "level", "slots"]);

function boundedNumber(value: string | null, minimum: number, maximum: number) {
  if (value === null || value.trim() === "") return null;
  const numeric = Number(value);
  return Number.isFinite(numeric) ? Math.max(minimum, Math.min(maximum, numeric)) : null;
}

function startOfDay(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

export function marketDayFromParam(value: string | null): MarketDayFilter {
  return MARKET_DAY_FILTERS.includes(value as MarketDayFilter) ? value as MarketDayFilter : "Todos";
}

export function marketSortFromParam(value: string | null): MarketSort {
  return allowedSorts.has(value as MarketSort) ? value as MarketSort : "relevance";
}

export function marketRouteFiltersFromParams(params: URLSearchParams): MarketRouteFilters {
  return {
    day: marketDayFromParam(params.get("dia")),
    maxPrice: boundedNumber(params.get("precioMax"), 0, 1000),
    maxRating: boundedNumber(params.get("nivelMax"), 0, 100),
    minRating: boundedNumber(params.get("nivelMin"), 0, 100),
    modality: params.get("modalidad") || "Todas",
    position: params.get("posicion") || "Todas",
    radiusKm: boundedNumber(params.get("radio"), 1, 100) ?? 30,
    sort: marketSortFromParam(params.get("orden")),
    zone: params.get("zona") || "",
    zonePlaceId: params.get("placeId") || undefined,
  };
}

export function marketRouteDetailFromParams(params: URLSearchParams): MarketRouteDetail {
  const match = params.get("openMatch");
  if (match) return { id: match, kind: "match" };
  const player = params.get("player");
  if (player) return { id: player, kind: "player" };
  const team = params.get("team");
  return team ? { id: team, kind: "team" } : null;
}

export function updateMarketRouteParams(
  current: URLSearchParams,
  values: {
    detail?: MarketRouteDetail;
    filters?: MarketRouteFilters;
    tab?: "equipos" | "jugadores" | "partidos";
  },
) {
  const next = new URLSearchParams(current);
  if (values.tab) next.set("tab", values.tab);

  if (values.filters) {
    const filters = values.filters;
    const setOrDelete = (key: string, value: string | null | undefined, emptyValue?: string) => {
      if (!value || value === emptyValue) next.delete(key);
      else next.set(key, value);
    };
    setOrDelete("zona", filters.zone);
    setOrDelete("placeId", filters.zonePlaceId);
    setOrDelete("dia", filters.day, "Todos");
    setOrDelete("modalidad", filters.modality, "Todas");
    setOrDelete("posicion", filters.position, "Todas");
    setOrDelete("orden", filters.sort, "relevance");
    if (filters.radiusKm === 30) next.delete("radio");
    else next.set("radio", String(filters.radiusKm));
    if (filters.maxPrice === null) next.delete("precioMax");
    else next.set("precioMax", String(filters.maxPrice));
    if (filters.minRating === null) next.delete("nivelMin");
    else next.set("nivelMin", String(filters.minRating));
    if (filters.maxRating === null) next.delete("nivelMax");
    else next.set("nivelMax", String(filters.maxRating));
  }

  if (values.detail !== undefined) {
    next.delete("openMatch");
    next.delete("player");
    next.delete("team");
    if (values.detail) {
      const key = values.detail.kind === "match" ? "openMatch" : values.detail.kind;
      next.set(key, values.detail.id);
    }
  }

  return next;
}

export function marketDayMatches(dateValue: string, filter: MarketDayFilter, now = new Date()) {
  if (filter === "Todos" || filter === "Esta semana" && !dateValue) return true;
  const parsed = new Date(dateValue);
  if (!Number.isFinite(parsed.getTime())) return false;
  if (filter === "Hoy") return startOfDay(parsed).getTime() === startOfDay(now).getTime();
  if (filter === "Mañana") {
    const tomorrow = startOfDay(now);
    tomorrow.setDate(tomorrow.getDate() + 1);
    return startOfDay(parsed).getTime() === tomorrow.getTime();
  }
  if (filter === "Esta semana") {
    const first = startOfDay(now);
    const dayFromMonday = (first.getDay() + 6) % 7;
    first.setDate(first.getDate() - dayFromMonday);
    const last = new Date(first);
    last.setDate(last.getDate() + 7);
    return parsed >= first && parsed < last;
  }
  return weekdayLabels[parsed.getDay()] === filter;
}

export function marketAvailabilityMatches(availability: string, filter: MarketDayFilter, now = new Date()) {
  if (filter === "Todos" || filter === "Esta semana") return true;
  const target = filter === "Hoy"
    ? weekdayLabels[now.getDay()]
    : filter === "Mañana"
      ? weekdayLabels[(now.getDay() + 1) % 7]
      : filter;
  const normalized = availability.toLocaleLowerCase("es").normalize("NFD").replace(/\p{Diacritic}/gu, "");
  const day = target.toLocaleLowerCase("es").normalize("NFD").replace(/\p{Diacritic}/gu, "");
  return normalized.includes(day) || normalized.includes(day.slice(0, 3));
}

export function safeMarketError(error: unknown) {
  const value = error && typeof error === "object" ? error as { code?: string; message?: string } : {};
  const message = String(value.message || "").toLocaleLowerCase("es");
  if (value.code === "PT409" || message.includes("revision") || message.includes("stale")) {
    return { body: "Este partido ha cambiado. Hemos cargado la información actualizada.", stale: true, title: "Información actualizada" };
  }
  if (message.includes("auth") || message.includes("session") || message.includes("jwt")) {
    return { body: "Entra para continuar desde el mismo punto.", stale: false, title: "Sesión necesaria" };
  }
  if (message.includes("permission") || message.includes("not allowed") || message.includes("admin")) {
    return { body: "Tu cuenta no puede realizar esta acción.", stale: false, title: "No tienes permiso" };
  }
  if (message.includes("full") || message.includes("slot") || message.includes("plaza")) {
    return { body: "Ya no quedan plazas disponibles para este partido.", stale: true, title: "Partido completo" };
  }
  if (message.includes("closed") || message.includes("started") || message.includes("finalized")) {
    return { body: "Este partido ya no admite nuevas solicitudes.", stale: true, title: "Partido cerrado" };
  }
  if (message.includes("duplicate") || message.includes("already")) {
    return { body: "Esta acción ya estaba registrada. Hemos actualizado el estado.", stale: true, title: "Estado actualizado" };
  }
  if (message.includes("network") || message.includes("fetch") || message.includes("timeout") || typeof navigator !== "undefined" && !navigator.onLine) {
    return { body: "Necesitas conexión para confirmar esta acción.", stale: false, title: "Sin conexión" };
  }
  return { body: "No se pudo completar la acción. Inténtalo de nuevo.", stale: false, title: "Algo no ha salido bien" };
}

export type MarketReadCache<TProfile, TMatch> = {
  matches: TMatch[];
  profiles: TProfile[];
  updatedAt: string;
  version: 1;
};

export function readMarketReadCache<TProfile, TMatch>(storage: Pick<Storage, "getItem">, now = Date.now()) {
  try {
    const parsed = JSON.parse(storage.getItem(MARKET_CACHE_KEY) || "null") as MarketReadCache<TProfile, TMatch> | null;
    if (!parsed || parsed.version !== 1 || !Array.isArray(parsed.matches) || !Array.isArray(parsed.profiles)) return null;
    const updated = Date.parse(parsed.updatedAt);
    if (!Number.isFinite(updated) || now - updated > MARKET_CACHE_MAX_AGE_MS) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function writeMarketReadCache<TProfile, TMatch>(storage: Pick<Storage, "setItem">, cache: MarketReadCache<TProfile, TMatch>) {
  storage.setItem(MARKET_CACHE_KEY, JSON.stringify(cache));
}

export function readMarketLocationPreference(storage: Pick<Storage, "getItem">) {
  try {
    const parsed = JSON.parse(storage.getItem(MARKET_LOCATION_PREFERENCE_KEY) || "null") as { label?: unknown; placeId?: unknown; radiusKm?: unknown } | null;
    const label = typeof parsed?.label === "string" ? parsed.label.trim().slice(0, 120) : "";
    if (!label) return null;
    return {
      label,
      placeId: typeof parsed?.placeId === "string" ? parsed.placeId.slice(0, 180) : undefined,
      radiusKm: Math.max(1, Math.min(100, Number(parsed?.radiusKm) || 30)),
    };
  } catch {
    return null;
  }
}

export function writeMarketLocationPreference(
  storage: Pick<Storage, "setItem">,
  preference: { label: string; placeId?: string; radiusKm: number },
) {
  storage.setItem(MARKET_LOCATION_PREFERENCE_KEY, JSON.stringify({
    label: preference.label.slice(0, 120),
    placeId: preference.placeId?.slice(0, 180),
    radiusKm: Math.max(1, Math.min(100, preference.radiusKm)),
  }));
}
