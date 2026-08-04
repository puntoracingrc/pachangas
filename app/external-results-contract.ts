export const EXTERNAL_RESULTS_CACHE_VERSION = "external-results-v1";
export const EXTERNAL_RESULTS_CACHE_MAX_AGE_MS = 5 * 60 * 1000;

export type ExternalMatchState =
  | "auto_confirmed"
  | "cancelled"
  | "change_proposed"
  | "confirmed"
  | "disputed"
  | "draft"
  | "needs_scorer_fix"
  | "pending_rival"
  | "unverified"
  | "annulled";

export type ExternalRosterPlayer = {
  active: boolean;
  currentOverall: number | null;
  localPlayerId: string;
  name: string;
  playerProfileId: string | null;
  position: string | null;
};

export type ExternalMatchParticipant = {
  cardSnapshot: Record<string, unknown>;
  groupId: string;
  localPlayerId: string;
  name: string;
  playerProfileId: string | null;
};

export type ExternalMatchScorer = {
  goals: number;
  groupId: string;
  localPlayerId: string;
};

export type ExternalTeamSummary = {
  groupId: string;
  levelSnapshot: number | null;
  name: string;
  teamCode: string;
};

export type ExternalMatch = {
  activeVersion: number | null;
  autoConfirmationBlocked: boolean;
  awayTeam: ExternalTeamSummary;
  canonicalScoreAway: number | null;
  canonicalScoreHome: number | null;
  challengeId: string;
  field: { address: string; mapsUrl: string | null; name: string; placeId: string | null };
  homeTeam: ExternalTeamSummary;
  id: string;
  modality: "futbol11" | "futbol7" | "sala";
  officialAt: string | null;
  officialVersion: number | null;
  participants: ExternalMatchParticipant[];
  pendingResponseFromGroupId: string | null;
  proposedByGroupId: string | null;
  responseDeadline: string | null;
  revision: number;
  scheduledAt: string;
  scoreAway: number | null;
  scoreHome: number | null;
  scorers: ExternalMatchScorer[];
  serverSequence: number;
  side: "away" | "home";
  state: ExternalMatchState;
  unassignedAway: number;
  unassignedHome: number;
  updatedAt: string;
};

export type ExternalResultsSnapshot = {
  canManage: boolean;
  confirmedRevision: number;
  groupId: string;
  groupName: string;
  matches: ExternalMatch[];
  roster: ExternalRosterPlayer[];
  serverSequence: number;
  updatedAt: string;
};

type CachedExternalResults = {
  cachedAt: number;
  snapshot: ExternalResultsSnapshot;
  version: typeof EXTERNAL_RESULTS_CACHE_VERSION;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function text(value: unknown) {
  return typeof value === "string" ? value : "";
}

function nullableText(value: unknown) {
  return typeof value === "string" && value ? value : null;
}

function numberValue(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nullableNumber(value: unknown) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function state(value: unknown): ExternalMatchState {
  if (
    value === "auto_confirmed" || value === "cancelled" || value === "change_proposed"
    || value === "confirmed" || value === "disputed" || value === "needs_scorer_fix"
    || value === "pending_rival" || value === "unverified" || value === "annulled"
  ) return value;
  return "draft";
}

function modality(value: unknown): ExternalMatch["modality"] {
  if (value === "futbol11" || value === "sala") return value;
  return "futbol7";
}

function team(value: unknown): ExternalTeamSummary | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const name = text(value.name);
  if (!groupId || !name) return null;
  return {
    groupId,
    levelSnapshot: nullableNumber(value.levelSnapshot),
    name,
    teamCode: text(value.teamCode),
  };
}

function rosterPlayer(value: unknown): ExternalRosterPlayer | null {
  if (!isRecord(value)) return null;
  const localPlayerId = text(value.localPlayerId);
  const name = text(value.name);
  if (!localPlayerId || !name) return null;
  return {
    active: value.active !== false,
    currentOverall: nullableNumber(value.currentOverall),
    localPlayerId,
    name,
    playerProfileId: nullableText(value.playerProfileId),
    position: nullableText(value.position),
  };
}

function participant(value: unknown): ExternalMatchParticipant | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const localPlayerId = text(value.localPlayerId);
  if (!groupId || !localPlayerId) return null;
  return {
    cardSnapshot: isRecord(value.cardSnapshot) ? value.cardSnapshot : {},
    groupId,
    localPlayerId,
    name: text(value.name) || "Jugador",
    playerProfileId: nullableText(value.playerProfileId),
  };
}

function scorer(value: unknown): ExternalMatchScorer | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const localPlayerId = text(value.localPlayerId);
  const goals = Math.max(0, Math.floor(numberValue(value.goals)));
  if (!groupId || !localPlayerId || goals < 1) return null;
  return { goals, groupId, localPlayerId };
}

export function normalizeExternalMatch(value: unknown): ExternalMatch | null {
  if (!isRecord(value)) return null;
  const homeTeam = team(value.homeTeam);
  const awayTeam = team(value.awayTeam);
  const id = text(value.id);
  const challengeId = text(value.challengeId);
  const scheduledAt = text(value.scheduledAt);
  if (!homeTeam || !awayTeam || !id || !challengeId || !scheduledAt) return null;
  const field = isRecord(value.field) ? value.field : {};
  return {
    activeVersion: nullableNumber(value.activeVersion),
    autoConfirmationBlocked: value.autoConfirmationBlocked === true,
    awayTeam,
    canonicalScoreAway: nullableNumber(value.canonicalScoreAway),
    canonicalScoreHome: nullableNumber(value.canonicalScoreHome),
    challengeId,
    field: {
      address: text(field.address),
      mapsUrl: nullableText(field.mapsUrl),
      name: text(field.name),
      placeId: nullableText(field.placeId),
    },
    homeTeam,
    id,
    modality: modality(value.modality),
    officialAt: nullableText(value.officialAt),
    officialVersion: nullableNumber(value.officialVersion),
    participants: Array.isArray(value.participants)
      ? value.participants.map(participant).filter((item): item is ExternalMatchParticipant => Boolean(item))
      : [],
    pendingResponseFromGroupId: nullableText(value.pendingResponseFromGroupId),
    proposedByGroupId: nullableText(value.proposedByGroupId),
    responseDeadline: nullableText(value.responseDeadline),
    revision: Math.max(1, Math.floor(numberValue(value.revision))),
    scheduledAt,
    scoreAway: nullableNumber(value.scoreAway),
    scoreHome: nullableNumber(value.scoreHome),
    scorers: Array.isArray(value.scorers)
      ? value.scorers.map(scorer).filter((item): item is ExternalMatchScorer => Boolean(item))
      : [],
    serverSequence: Math.max(0, Math.floor(numberValue(value.serverSequence))),
    side: value.side === "away" ? "away" : "home",
    state: state(value.state),
    unassignedAway: Math.max(0, Math.floor(numberValue(value.unassignedAway))),
    unassignedHome: Math.max(0, Math.floor(numberValue(value.unassignedHome))),
    updatedAt: text(value.updatedAt),
  };
}

export function normalizeExternalResultsSnapshot(value: unknown): ExternalResultsSnapshot | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  if (!groupId) return null;
  return {
    canManage: value.canManage === true,
    confirmedRevision: Math.max(0, Math.floor(numberValue(value.confirmedRevision))),
    groupId,
    groupName: text(value.groupName),
    matches: Array.isArray(value.matches)
      ? value.matches.map(normalizeExternalMatch).filter((item): item is ExternalMatch => Boolean(item))
      : [],
    roster: Array.isArray(value.roster)
      ? value.roster.map(rosterPlayer).filter((item): item is ExternalRosterPlayer => Boolean(item))
      : [],
    serverSequence: Math.max(0, Math.floor(numberValue(value.serverSequence))),
    updatedAt: text(value.updatedAt),
  };
}

export function externalResultsCacheKey(userId: string, groupId: string) {
  return `pachangas:${EXTERNAL_RESULTS_CACHE_VERSION}:${userId}:${groupId}`;
}

export function readExternalResultsCache(
  storage: Pick<Storage, "getItem">,
  userId: string,
  groupId: string,
  now = Date.now(),
) {
  try {
    const parsed = JSON.parse(storage.getItem(externalResultsCacheKey(userId, groupId)) ?? "null") as unknown;
    if (!isRecord(parsed) || parsed.version !== EXTERNAL_RESULTS_CACHE_VERSION) return null;
    const cachedAt = numberValue(parsed.cachedAt);
    if (!cachedAt || now - cachedAt > EXTERNAL_RESULTS_CACHE_MAX_AGE_MS) return null;
    return normalizeExternalResultsSnapshot(parsed.snapshot);
  } catch {
    return null;
  }
}

export function writeExternalResultsCache(
  storage: Pick<Storage, "setItem">,
  userId: string,
  groupId: string,
  snapshot: ExternalResultsSnapshot,
  now = Date.now(),
) {
  const cached: CachedExternalResults = {
    cachedAt: now,
    snapshot,
    version: EXTERNAL_RESULTS_CACHE_VERSION,
  };
  storage.setItem(externalResultsCacheKey(userId, groupId), JSON.stringify(cached));
}

export function externalMatchStateLabel(value: ExternalMatchState) {
  if (value === "pending_rival") return "Pendiente del rival";
  if (value === "change_proposed") return "Corrección propuesta";
  if (value === "needs_scorer_fix") return "Faltan goleadores";
  if (value === "confirmed") return "Confirmado";
  if (value === "auto_confirmed") return "Autoconfirmado";
  if (value === "disputed") return "En discrepancia";
  if (value === "cancelled") return "Cancelado";
  if (value === "annulled") return "Anulado";
  if (value === "unverified") return "Sin verificar";
  return "Sin resultado";
}
