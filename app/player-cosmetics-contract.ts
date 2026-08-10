export const PLAYER_COSMETIC_SLOTS = [
  "frame",
  "background",
  "accent",
  "effect",
  "title",
] as const;

export type PlayerCosmeticSlot = (typeof PLAYER_COSMETIC_SLOTS)[number];

export type PlayerCosmeticRarity = "common" | "uncommon" | "rare" | "epic" | "legendary";

export type PlayerCosmeticRenderContract = Record<string, string | number | boolean>;

export type PlayerCosmeticItem = {
  acquiredAt: string | null;
  collection: string | null;
  description: string;
  key: string;
  layerOrder: number;
  material: string | null;
  name: string;
  rarity: PlayerCosmeticRarity;
  render: PlayerCosmeticRenderContract;
  seenAt: string | null;
  serverSequence: number;
  slot: PlayerCosmeticSlot;
  sourceBoxId: string | null;
};

export type PlayerFeaturedBadge = {
  achievementKey: string;
  grantId: string;
  occurredAt?: string | null;
  rarity: PlayerCosmeticRarity;
  title: string;
};

export type PlayerCosmeticLoadout = {
  accentKey: string | null;
  backgroundKey: string | null;
  effectKey: string | null;
  featuredBadgeGrantId: string | null;
  frameKey: string | null;
  titleKey: string | null;
};

export type PlayerCosmeticsSnapshot = {
  enabled: boolean;
  featuredBadges: PlayerFeaturedBadge[];
  loadout: PlayerCosmeticLoadout;
  owned: PlayerCosmeticItem[];
  playerProfileId: string;
  revision: number;
  serverSequence: number;
  updatedAt: string | null;
};

export type PublicPlayerCosmeticsSnapshot = {
  enabled: boolean;
  equipped: PlayerCosmeticItem[];
  featuredBadge: PlayerFeaturedBadge | null;
  loadout: PlayerCosmeticLoadout;
  playerProfileId: string;
  revision: number;
  serverSequence: number;
  updatedAt: string | null;
};

export const EMPTY_PLAYER_COSMETIC_LOADOUT: PlayerCosmeticLoadout = {
  accentKey: null,
  backgroundKey: null,
  effectKey: null,
  featuredBadgeGrantId: null,
  frameKey: null,
  titleKey: null,
};

const CACHE_VERSION = 1;
const CACHE_PREFIX = "pachangas-player-cosmetics";

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function text(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numeric(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function rarity(value: unknown): PlayerCosmeticRarity {
  return value === "uncommon" || value === "rare" || value === "epic" || value === "legendary"
    ? value
    : "common";
}

function slot(value: unknown): PlayerCosmeticSlot | null {
  return PLAYER_COSMETIC_SLOTS.find((candidate) => candidate === value) ?? null;
}

function loadout(value: unknown): PlayerCosmeticLoadout {
  if (!isRecord(value)) return { ...EMPTY_PLAYER_COSMETIC_LOADOUT };
  return {
    accentKey: text(value.accentKey),
    backgroundKey: text(value.backgroundKey),
    effectKey: text(value.effectKey),
    featuredBadgeGrantId: text(value.featuredBadgeGrantId),
    frameKey: text(value.frameKey),
    titleKey: text(value.titleKey),
  };
}

function item(value: unknown): PlayerCosmeticItem | null {
  if (!isRecord(value)) return null;
  const key = text(value.key);
  const itemSlot = slot(value.slot);
  if (!key || !itemSlot) return null;
  return {
    acquiredAt: text(value.acquiredAt),
    collection: text(value.collection),
    description: text(value.description) ?? "",
    key,
    layerOrder: numeric(value.layerOrder),
    material: text(value.material),
    name: text(value.name) ?? key,
    rarity: rarity(value.rarity),
    render: isRecord(value.render)
      ? Object.entries(value.render).reduce<PlayerCosmeticRenderContract>((result, [key, entry]) => {
        if (typeof entry === "string" || typeof entry === "number" || typeof entry === "boolean") result[key] = entry;
        return result;
      }, {})
      : {},
    seenAt: text(value.seenAt),
    serverSequence: numeric(value.serverSequence),
    slot: itemSlot,
    sourceBoxId: text(value.sourceBoxId),
  };
}

function badge(value: unknown): PlayerFeaturedBadge | null {
  if (!isRecord(value)) return null;
  const grantId = text(value.grantId);
  const achievementKey = text(value.achievementKey);
  const title = text(value.title);
  if (!grantId || !achievementKey || !title) return null;
  return {
    achievementKey,
    grantId,
    occurredAt: text(value.occurredAt),
    rarity: rarity(value.rarity),
    title,
  };
}

export function normalizePlayerCosmeticsSnapshot(value: unknown): PlayerCosmeticsSnapshot | null {
  if (!isRecord(value)) return null;
  const playerProfileId = text(value.playerProfileId);
  if (!playerProfileId) return null;
  return {
    enabled: value.enabled === true,
    featuredBadges: Array.isArray(value.featuredBadges)
      ? value.featuredBadges.map(badge).filter((entry): entry is PlayerFeaturedBadge => Boolean(entry))
      : [],
    loadout: loadout(value.loadout),
    owned: Array.isArray(value.owned)
      ? value.owned.map(item).filter((entry): entry is PlayerCosmeticItem => Boolean(entry))
      : [],
    playerProfileId,
    revision: Math.max(0, numeric(value.revision)),
    serverSequence: Math.max(0, numeric(value.serverSequence)),
    updatedAt: text(value.updatedAt),
  };
}

export function normalizePublicPlayerCosmeticsSnapshot(value: unknown): PublicPlayerCosmeticsSnapshot | null {
  if (!isRecord(value)) return null;
  const playerProfileId = text(value.playerProfileId);
  if (!playerProfileId) return null;
  return {
    enabled: value.enabled === true,
    equipped: Array.isArray(value.equipped)
      ? value.equipped.map(item).filter((entry): entry is PlayerCosmeticItem => Boolean(entry))
      : [],
    featuredBadge: badge(value.featuredBadge),
    loadout: loadout(value.loadout),
    playerProfileId,
    revision: Math.max(0, numeric(value.revision)),
    serverSequence: Math.max(0, numeric(value.serverSequence)),
    updatedAt: text(value.updatedAt),
  };
}

export function cosmeticKeyForSlot(loadoutValue: PlayerCosmeticLoadout, targetSlot: PlayerCosmeticSlot) {
  if (targetSlot === "frame") return loadoutValue.frameKey;
  if (targetSlot === "background") return loadoutValue.backgroundKey;
  if (targetSlot === "accent") return loadoutValue.accentKey;
  if (targetSlot === "effect") return loadoutValue.effectKey;
  return loadoutValue.titleKey;
}

export function withCosmeticKey(
  loadoutValue: PlayerCosmeticLoadout,
  targetSlot: PlayerCosmeticSlot,
  cosmeticKey: string | null,
): PlayerCosmeticLoadout {
  const next = { ...loadoutValue };
  if (targetSlot === "frame") next.frameKey = cosmeticKey;
  else if (targetSlot === "background") next.backgroundKey = cosmeticKey;
  else if (targetSlot === "accent") next.accentKey = cosmeticKey;
  else if (targetSlot === "effect") next.effectKey = cosmeticKey;
  else next.titleKey = cosmeticKey;
  return next;
}

export function playerCosmeticLoadoutsEqual(left: PlayerCosmeticLoadout, right: PlayerCosmeticLoadout) {
  return PLAYER_COSMETIC_SLOTS.every((targetSlot) => (
    cosmeticKeyForSlot(left, targetSlot) === cosmeticKeyForSlot(right, targetSlot)
  )) && left.featuredBadgeGrantId === right.featuredBadgeGrantId;
}

export function unseenCosmeticsBySlot(items: PlayerCosmeticItem[]) {
  return Object.fromEntries(PLAYER_COSMETIC_SLOTS.map((targetSlot) => [
    targetSlot,
    items.filter((entry) => entry.slot === targetSlot && !entry.seenAt).length,
  ])) as Record<PlayerCosmeticSlot, number>;
}

export function cosmeticCacheKey(userId: string) {
  return `${CACHE_PREFIX}:v${CACHE_VERSION}:${userId}`;
}

export function readPlayerCosmeticsCache(storage: Storage, userId: string) {
  try {
    return normalizePlayerCosmeticsSnapshot(JSON.parse(storage.getItem(cosmeticCacheKey(userId)) ?? "null"));
  } catch {
    return null;
  }
}

export function writePlayerCosmeticsCache(storage: Storage, userId: string, snapshot: PlayerCosmeticsSnapshot) {
  storage.setItem(cosmeticCacheKey(userId), JSON.stringify(snapshot));
}

export function playerCosmeticSportingChecksum(value: {
  facets: Array<{ key: string; value: number | string }>;
  position: string;
  score: number | string;
}) {
  return JSON.stringify({ facets: value.facets, position: value.position, score: value.score });
}
