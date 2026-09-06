export type SocialInboxDomain = "CHALLENGE" | "MARKET" | "MATCH" | "TEAM" | "REWARD";
export type SocialInboxView = "all" | "pending";
export type SocialInboxAttentionState = "ACTION_REQUIRED" | "INFORMATIONAL" | "RESOLVED";
export type SocialInboxReadState = "READ" | "UNREAD";

export type SocialInboxItem = {
  archiveState: "ACTIVE" | "ARCHIVED";
  attentionState: SocialInboxAttentionState;
  category: string;
  context: string;
  ctaLabel: string;
  deepLink?: string;
  id: string;
  kind: string;
  occurredAt: string;
  priority: "critical" | "high" | "normal";
  readState: SocialInboxReadState;
  revision: number;
  serverSequence: number;
  sourceDomain: SocialInboxDomain;
  sourceId?: string;
  statusLabel: string;
  summary: string;
  title: string;
  updatedAt: string;
};

export type SocialInboxCursor = {
  notificationId: string;
  serverSequence: number;
  sortRank: number;
};

export type SocialInboxSnapshot = {
  domain: SocialInboxDomain | null;
  fetchedAt: string;
  filters: SocialInboxDomain[];
  hasMore: boolean;
  items: SocialInboxItem[];
  nextCursor: SocialInboxCursor | null;
  pageSize: number;
  pendingCount: number;
  serverSequence: number;
  unreadCount: number;
  view: SocialInboxView;
};

export type SocialInboxGroup = "attention" | "older" | "today" | "week";

export const SOCIAL_INBOX_DOMAINS: Array<{ id: SocialInboxDomain; label: string }> = [
  { id: "MATCH", label: "Partidos" },
  { id: "CHALLENGE", label: "Retos" },
  { id: "MARKET", label: "Mercado" },
  { id: "TEAM", label: "Equipo" },
  { id: "REWARD", label: "Premios" },
];

const safePaths = new Set([
  "/",
  "/equipo",
  "/equipo/invitaciones",
  "/mercado",
  "/partido-invitado",
  "/retos",
  "/ruleta",
]);

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function integer(value: unknown, minimum = 0) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? Math.max(minimum, Math.floor(numeric)) : minimum;
}

function text(value: unknown, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

function socialDomain(value: unknown): SocialInboxDomain | null {
  return value === "MATCH" || value === "CHALLENGE" || value === "MARKET" || value === "TEAM" || value === "REWARD"
    ? value
    : null;
}

export function safeSocialInboxDeepLink(value: unknown): string | undefined {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//")) return undefined;
  try {
    const url = new URL(value, "https://pachangasiq.local");
    if (url.origin !== "https://pachangasiq.local" || !safePaths.has(url.pathname)) return undefined;
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return undefined;
  }
}

export function normalizeSocialInboxItem(value: unknown): SocialInboxItem | null {
  const row = record(value);
  if (!row || typeof row.id !== "string") return null;
  const sourceDomain = socialDomain(row.sourceDomain);
  if (!sourceDomain) return null;
  const attentionState: SocialInboxAttentionState = row.attentionState === "ACTION_REQUIRED"
    || row.attentionState === "RESOLVED" ? row.attentionState : "INFORMATIONAL";
  const readState: SocialInboxReadState = row.readState === "READ" ? "READ" : "UNREAD";
  const priority = row.priority === "critical" || row.priority === "high" ? row.priority : "normal";
  return {
    archiveState: row.archiveState === "ARCHIVED" ? "ARCHIVED" : "ACTIVE",
    attentionState,
    category: text(row.category, sourceDomain.toLocaleLowerCase("es")),
    context: text(row.context, SOCIAL_INBOX_DOMAINS.find((entry) => entry.id === sourceDomain)?.label ?? "Actividad"),
    ctaLabel: text(row.ctaLabel, "Abrir"),
    deepLink: safeSocialInboxDeepLink(row.deepLink),
    id: row.id,
    kind: text(row.kind, "social_activity"),
    occurredAt: text(row.occurredAt),
    priority,
    readState,
    revision: integer(row.revision, 1),
    serverSequence: integer(row.serverSequence),
    sourceDomain,
    sourceId: typeof row.sourceId === "string" ? row.sourceId : undefined,
    statusLabel: text(row.statusLabel, attentionState === "ACTION_REQUIRED" ? "Necesita respuesta" : "Actividad"),
    summary: text(row.summary),
    title: text(row.title, "Aviso"),
    updatedAt: text(row.updatedAt, text(row.occurredAt)),
  };
}

export function normalizeSocialInboxSnapshot(value: unknown): SocialInboxSnapshot | null {
  const row = record(value);
  if (!row) return null;
  const view: SocialInboxView = row.view === "all" ? "all" : "pending";
  const domain = socialDomain(row.domain);
  const cursorRow = record(row.nextCursor);
  const cursorId = cursorRow && typeof cursorRow.notificationId === "string" ? cursorRow.notificationId : "";
  const nextCursor = cursorId ? {
    notificationId: cursorId,
    serverSequence: integer(cursorRow?.serverSequence),
    sortRank: integer(cursorRow?.sortRank),
  } : null;
  const filters = Array.isArray(row.filters)
    ? row.filters.map(socialDomain).filter((entry): entry is SocialInboxDomain => Boolean(entry))
    : SOCIAL_INBOX_DOMAINS.map((entry) => entry.id);
  return {
    domain,
    fetchedAt: text(row.fetchedAt, new Date(0).toISOString()),
    filters,
    hasMore: row.hasMore === true,
    items: Array.isArray(row.items)
      ? row.items.map(normalizeSocialInboxItem).filter((item): item is SocialInboxItem => Boolean(item))
      : [],
    nextCursor,
    pageSize: integer(row.pageSize, 1),
    pendingCount: integer(row.pendingCount),
    serverSequence: integer(row.serverSequence),
    unreadCount: integer(row.unreadCount),
    view,
  };
}

export function socialInboxGroup(item: SocialInboxItem, now = new Date()): SocialInboxGroup {
  if (item.attentionState === "ACTION_REQUIRED") return "attention";
  const occurred = new Date(item.occurredAt);
  if (Number.isNaN(occurred.getTime())) return "older";
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  if (occurred.getTime() >= startToday) return "today";
  if (occurred.getTime() >= startToday - 6 * 24 * 60 * 60 * 1000) return "week";
  return "older";
}

export function socialInboxError(error: unknown, fallback = "No pudimos actualizar tus avisos.") {
  const message = error && typeof error === "object" && "message" in error
    ? String((error as { message?: unknown }).message ?? "")
    : String(error ?? "");
  const normalized = message.toLocaleLowerCase("es");
  if (normalized.includes("authentication_required") || normalized.includes("jwt")) return "Inicia sesión para consultar tus avisos.";
  if (normalized.includes("not_found")) return "Este aviso ya no está disponible.";
  if (normalized.includes("stale") || normalized.includes("pt409")) return "Este aviso ha cambiado. Hemos cargado la información actualizada.";
  if (normalized.includes("client_update_required")) return "Actualiza Pachangas IQ para continuar.";
  if (normalized.includes("timeout") || normalized.includes("fetch")) return "La conexión está tardando. Puedes volver a intentarlo.";
  return fallback;
}
