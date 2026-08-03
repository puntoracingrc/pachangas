import type { TeamChallengeModality, TeamSummary } from "./team-social-contract";

export const CHALLENGEABLE_TEAM_CACHE_VERSION = "challengeable-teams-v1";
export const CHALLENGEABLE_PROFILE_CACHE_MAX_AGE_MS = 5 * 60 * 1000;
export const CHALLENGEABLE_SEARCH_CACHE_MAX_AGE_MS = 2 * 60 * 1000;

export type ChallengeableAvailabilitySlot = {
  day: number;
  end: string;
  start: string;
};

export type ChallengeableTeamZone = {
  label: string;
  lat: number | null;
  lng: number | null;
  placeId: string | null;
};

export type ChallengeableTeamProfile = {
  availability: ChallengeableAvailabilitySlot[];
  enabled: boolean;
  maxOpponentLevel: number;
  minOpponentLevel: number;
  modalities: TeamChallengeModality[];
  travelRadiusKm: number;
  zone: ChallengeableTeamZone;
};

export type ChallengeableTeamProfileSnapshot = {
  canManage: boolean;
  confirmedRevision: number;
  group: TeamSummary;
  levelRevision: number;
  ownLevel: number | null;
  profile: ChallengeableTeamProfile;
  profileRevision: number;
  searchRevision: number;
  serverSequence: number;
  updatedAt: string;
};

export type ChallengeableTeamSearchItem = {
  availability: ChallengeableAvailabilitySlot[];
  distanceKm: number | null;
  groupId: string;
  levelCompatibility: "compatible" | "unknown";
  maxOpponentLevel: number;
  minOpponentLevel: number;
  modalities: TeamChallengeModality[];
  name: string;
  profileRevision: number;
  teamLevel: number | null;
  travelRadiusKm: number;
  updatedAt: string;
  zoneLabel: string;
};

export type ChallengeableTeamSearchSnapshot = {
  confirmedRevision: number;
  hasMore: boolean;
  items: ChallengeableTeamSearchItem[];
  page: number;
  pageSize: number;
  requesterLevel: number | null;
  requestingGroupId: string;
  searchRevision: number;
  serverSequence: number;
  updatedAt: string;
};

export type ChallengeableTeamSearchFilters = {
  day: number | null;
  end: string | null;
  maxDistanceKm: number | null;
  maxTeamLevel: number | null;
  minTeamLevel: number | null;
  modality: TeamChallengeModality | null;
  start: string | null;
  zoneLabel: string;
  zoneLat: number | null;
  zoneLng: number | null;
};

type CachedValue<T> = {
  cachedAt: number;
  value: T;
  version: typeof CHALLENGEABLE_TEAM_CACHE_VERSION;
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

function finiteNumber(value: unknown) {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function nonNegativeInteger(value: unknown) {
  return Math.max(0, Math.trunc(finiteNumber(value) ?? 0));
}

function level(value: unknown) {
  const parsed = finiteNumber(value);
  return parsed === null ? null : Math.max(0, Math.min(100, parsed));
}

function modality(value: unknown): TeamChallengeModality | null {
  return value === "sala" || value === "futbol7" || value === "futbol11" ? value : null;
}

function modalities(value: unknown) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(modality).filter((item): item is TeamChallengeModality => Boolean(item)))];
}

function availabilitySlot(value: unknown): ChallengeableAvailabilitySlot | null {
  if (!isRecord(value)) return null;
  const day = Math.trunc(finiteNumber(value.day) ?? 0);
  const start = text(value.start);
  const end = text(value.end);
  if (day < 1 || day > 7 || !/^([01]\d|2[0-3]):[0-5]\d$/.test(start) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(end) || end <= start) {
    return null;
  }
  return { day, end, start };
}

function availability(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.map(availabilitySlot).filter((slot): slot is ChallengeableAvailabilitySlot => Boolean(slot));
}

function teamSummary(value: unknown): TeamSummary | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const name = text(value.name);
  const teamCode = text(value.teamCode);
  return groupId && name ? { groupId, name, teamCode } : null;
}

function profile(value: unknown): ChallengeableTeamProfile | null {
  if (!isRecord(value)) return null;
  const zoneValue = isRecord(value.zone) ? value.zone : {};
  return {
    availability: availability(value.availability),
    enabled: value.enabled === true,
    maxOpponentLevel: level(value.maxOpponentLevel) ?? 100,
    minOpponentLevel: level(value.minOpponentLevel) ?? 0,
    modalities: modalities(value.modalities),
    travelRadiusKm: Math.max(1, Math.min(100, nonNegativeInteger(value.travelRadiusKm) || 20)),
    zone: {
      label: text(zoneValue.label),
      lat: finiteNumber(zoneValue.lat),
      lng: finiteNumber(zoneValue.lng),
      placeId: nullableText(zoneValue.placeId),
    },
  };
}

export function normalizeChallengeableTeamProfileSnapshot(value: unknown): ChallengeableTeamProfileSnapshot | null {
  if (!isRecord(value)) return null;
  const group = teamSummary(value.group);
  const normalizedProfile = profile(value.profile);
  if (!group || !normalizedProfile) return null;
  const profileRevision = nonNegativeInteger(value.profileRevision ?? value.confirmedRevision);
  return {
    canManage: value.canManage === true,
    confirmedRevision: Math.max(profileRevision, nonNegativeInteger(value.confirmedRevision)),
    group,
    levelRevision: nonNegativeInteger(value.levelRevision),
    ownLevel: level(value.ownLevel),
    profile: normalizedProfile,
    profileRevision,
    searchRevision: nonNegativeInteger(value.searchRevision),
    serverSequence: nonNegativeInteger(value.serverSequence),
    updatedAt: text(value.updatedAt),
  };
}

function searchItem(value: unknown): ChallengeableTeamSearchItem | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const name = text(value.name);
  const zoneLabel = text(value.zoneLabel);
  if (!groupId || !name || !zoneLabel) return null;
  return {
    availability: availability(value.availability),
    distanceKm: finiteNumber(value.distanceKm),
    groupId,
    levelCompatibility: value.levelCompatibility === "compatible" ? "compatible" : "unknown",
    maxOpponentLevel: level(value.maxOpponentLevel) ?? 100,
    minOpponentLevel: level(value.minOpponentLevel) ?? 0,
    modalities: modalities(value.modalities),
    name,
    profileRevision: nonNegativeInteger(value.profileRevision),
    teamLevel: level(value.teamLevel),
    travelRadiusKm: Math.max(1, Math.min(100, nonNegativeInteger(value.travelRadiusKm) || 20)),
    updatedAt: text(value.updatedAt),
    zoneLabel,
  };
}

export function normalizeChallengeableTeamSearchSnapshot(value: unknown): ChallengeableTeamSearchSnapshot | null {
  if (!isRecord(value)) return null;
  const requestingGroupId = text(value.requestingGroupId);
  if (!requestingGroupId) return null;
  const items = Array.isArray(value.items)
    ? value.items.map(searchItem).filter((item): item is ChallengeableTeamSearchItem => Boolean(item))
    : [];
  const searchRevision = nonNegativeInteger(value.searchRevision ?? value.confirmedRevision);
  return {
    confirmedRevision: Math.max(searchRevision, nonNegativeInteger(value.confirmedRevision)),
    hasMore: value.hasMore === true,
    items,
    page: Math.max(1, nonNegativeInteger(value.page) || 1),
    pageSize: Math.max(1, Math.min(24, nonNegativeInteger(value.pageSize) || 12)),
    requesterLevel: level(value.requesterLevel),
    requestingGroupId,
    searchRevision,
    serverSequence: nonNegativeInteger(value.serverSequence),
    updatedAt: text(value.updatedAt),
  };
}

function readCache<T>(
  storage: Pick<Storage, "getItem">,
  key: string,
  normalize: (value: unknown) => T | null,
  maxAgeMs: number,
  now: number,
) {
  try {
    const parsed = JSON.parse(storage.getItem(key) ?? "null") as unknown;
    if (!isRecord(parsed) || parsed.version !== CHALLENGEABLE_TEAM_CACHE_VERSION) return null;
    const cachedAt = finiteNumber(parsed.cachedAt);
    if (cachedAt === null || now - cachedAt > maxAgeMs) return null;
    return normalize(parsed.value);
  } catch {
    return null;
  }
}

function writeCache<T>(storage: Pick<Storage, "setItem">, key: string, value: T, now: number) {
  const cached: CachedValue<T> = { cachedAt: now, value, version: CHALLENGEABLE_TEAM_CACHE_VERSION };
  storage.setItem(key, JSON.stringify(cached));
}

export function challengeableProfileCacheKey(userId: string, groupId: string) {
  return `pachangas:${CHALLENGEABLE_TEAM_CACHE_VERSION}:profile:${userId}:${groupId}`;
}

export function readChallengeableProfileCache(
  storage: Pick<Storage, "getItem">,
  userId: string,
  groupId: string,
  now = Date.now(),
) {
  return readCache(
    storage,
    challengeableProfileCacheKey(userId, groupId),
    normalizeChallengeableTeamProfileSnapshot,
    CHALLENGEABLE_PROFILE_CACHE_MAX_AGE_MS,
    now,
  );
}

export function writeChallengeableProfileCache(
  storage: Pick<Storage, "setItem">,
  userId: string,
  groupId: string,
  snapshot: ChallengeableTeamProfileSnapshot,
  now = Date.now(),
) {
  writeCache(storage, challengeableProfileCacheKey(userId, groupId), snapshot, now);
}

export function challengeableSearchFingerprint(filters: ChallengeableTeamSearchFilters) {
  return JSON.stringify({
    day: filters.day,
    end: filters.end,
    maxDistanceKm: filters.maxDistanceKm,
    maxTeamLevel: filters.maxTeamLevel,
    minTeamLevel: filters.minTeamLevel,
    modality: filters.modality,
    start: filters.start,
    zoneLabel: filters.zoneLabel.trim().toLocaleLowerCase("es"),
    zoneLat: filters.zoneLat,
    zoneLng: filters.zoneLng,
  });
}

export function challengeableSearchCacheKey(
  userId: string,
  groupId: string,
  filters: ChallengeableTeamSearchFilters,
  page: number,
) {
  return `pachangas:${CHALLENGEABLE_TEAM_CACHE_VERSION}:search:${userId}:${groupId}:${page}:${challengeableSearchFingerprint(filters)}`;
}

export function readChallengeableSearchCache(
  storage: Pick<Storage, "getItem">,
  userId: string,
  groupId: string,
  filters: ChallengeableTeamSearchFilters,
  page: number,
  now = Date.now(),
) {
  return readCache(
    storage,
    challengeableSearchCacheKey(userId, groupId, filters, page),
    normalizeChallengeableTeamSearchSnapshot,
    CHALLENGEABLE_SEARCH_CACHE_MAX_AGE_MS,
    now,
  );
}

export function writeChallengeableSearchCache(
  storage: Pick<Storage, "setItem">,
  userId: string,
  groupId: string,
  filters: ChallengeableTeamSearchFilters,
  page: number,
  snapshot: ChallengeableTeamSearchSnapshot,
  now = Date.now(),
) {
  writeCache(storage, challengeableSearchCacheKey(userId, groupId, filters, page), snapshot, now);
}

export function challengeableDayLabel(day: number) {
  return ["", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][day] ?? "Día";
}

export function challengeableModalityLabel(value: TeamChallengeModality) {
  if (value === "sala") return "Fútbol sala";
  if (value === "futbol11") return "Fútbol 11";
  return "Fútbol 7";
}
