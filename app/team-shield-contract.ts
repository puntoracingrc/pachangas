import type { PlayerCosmeticRarity } from "./player-cosmetics-contract";

export const TEAM_SHIELD_SCHEMA_VERSION = 1 as const;

export const TEAM_SHIELD_COSMETIC_SLOTS = [
  "shape",
  "background",
  "pattern",
  "primary_symbol",
  "secondary_symbol",
  "border",
  "top_ornament",
  "side_ornament",
  "bottom_ornament",
  "effect",
] as const;

export type TeamShieldCosmeticSlot = (typeof TEAM_SHIELD_COSMETIC_SLOTS)[number];

export type TeamShieldConfig = {
  backgroundKey: string;
  borderKey: string;
  bottomOrnamentKey: string | null;
  effectKey: string | null;
  foundationYear: string;
  initials: string;
  patternKey: string | null;
  primaryColorKey: string;
  primarySymbolKey: string;
  primarySymbolRotation: number;
  primarySymbolScale: number;
  schemaVersion: typeof TEAM_SHIELD_SCHEMA_VERSION;
  secondaryColorKey: string;
  secondarySymbolKey: string | null;
  shapeKey: string;
  sideOrnamentKey: string | null;
  topOrnamentKey: string | null;
};

export type TeamShieldRenderableItem = {
  acquiredAt?: string | null;
  availability?: "achievement" | "base" | "prototype" | "reward_box";
  collection?: string | null;
  description?: string;
  key: string;
  material?: string | null;
  name?: string;
  rarity?: PlayerCosmeticRarity;
  render: Record<string, unknown>;
  seenAt?: string | null;
  serverSequence?: number;
  slot?: TeamShieldCosmeticSlot | null;
  unlocked?: boolean;
};

export const TEAM_SHIELD_DEFAULT_CONFIG: TeamShieldConfig = {
  backgroundKey: "team.shield.background.duotone",
  borderKey: "team.shield.border.clean",
  bottomOrnamentKey: null,
  effectKey: null,
  foundationYear: "",
  initials: "PIQ",
  patternKey: "team.shield.pattern.diagonal",
  primaryColorKey: "team.shield.color.midnight",
  primarySymbolKey: "team.shield.symbol.ball_iq",
  primarySymbolRotation: 0,
  primarySymbolScale: 1,
  schemaVersion: TEAM_SHIELD_SCHEMA_VERSION,
  secondaryColorKey: "team.shield.color.cyan",
  secondarySymbolKey: null,
  shapeKey: "team.shield.shape.classic_iq",
  sideOrnamentKey: null,
  topOrnamentKey: null,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function nullableText(value: unknown) {
  const normalized = text(value);
  return normalized || null;
}

function boundedNumber(value: unknown, fallback: number, min: number, max: number) {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : fallback;
}

export function normalizeTeamShieldConfig(value: unknown): TeamShieldConfig | null {
  if (!isRecord(value) || Number(value.schemaVersion) !== TEAM_SHIELD_SCHEMA_VERSION) return null;
  const required = {
    backgroundKey: text(value.backgroundKey),
    borderKey: text(value.borderKey),
    primaryColorKey: text(value.primaryColorKey),
    primarySymbolKey: text(value.primarySymbolKey),
    secondaryColorKey: text(value.secondaryColorKey),
    shapeKey: text(value.shapeKey),
  };
  const initials = text(value.initials).toUpperCase().replace(/\s/g, "").slice(0, 4);
  if (Object.values(required).some((entry) => !entry) || !initials) return null;
  return {
    ...required,
    bottomOrnamentKey: nullableText(value.bottomOrnamentKey),
    effectKey: nullableText(value.effectKey),
    foundationYear: text(value.foundationYear).replace(/[^0-9]/g, "").slice(0, 4),
    initials,
    patternKey: nullableText(value.patternKey),
    primarySymbolRotation: boundedNumber(value.primarySymbolRotation, 0, -12, 12),
    primarySymbolScale: boundedNumber(value.primarySymbolScale, 1, 0.8, 1.2),
    schemaVersion: TEAM_SHIELD_SCHEMA_VERSION,
    secondarySymbolKey: nullableText(value.secondarySymbolKey),
    sideOrnamentKey: nullableText(value.sideOrnamentKey),
    topOrnamentKey: nullableText(value.topOrnamentKey),
  };
}


export function teamShieldDesignEquals(left: TeamShieldConfig, right: TeamShieldConfig) {
  return JSON.stringify(left) === JSON.stringify(right);
}

export function teamShieldEquippedKeys(config: TeamShieldConfig) {
  return [...new Set([
    config.shapeKey,
    config.backgroundKey,
    config.patternKey,
    config.primaryColorKey,
    config.secondaryColorKey,
    config.primarySymbolKey,
    config.secondarySymbolKey,
    config.borderKey,
    config.topOrnamentKey,
    config.sideOrnamentKey,
    config.bottomOrnamentKey,
    config.effectKey,
  ].filter((entry): entry is string => Boolean(entry)))];
}

export function teamShieldSportingChecksum(value: {
  rating: number | string;
  seasonScore: number | string;
  facets: Array<{ key: string; value: number | string }>;
  tops: Array<{ key: string; value: number | string }>;
}) {
  return JSON.stringify(value);
}
