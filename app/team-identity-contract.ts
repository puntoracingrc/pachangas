export const TEAM_IDENTITY_CACHE_VERSION = "team-identity-v1";
export const TEAM_IDENTITY_CACHE_MAX_AGE_MS = 15 * 60 * 1000;

export type CrestDesign = {
  adornmentKey: string | null;
  borderKey: string;
  effectKey: string | null;
  initials: string;
  paletteKey: string | null;
  patternKey: string;
  primaryColorKey: string;
  secondaryColorKey: string;
  shapeKey: string;
  symbolKey: string | null;
};

export type CrestCatalogItem = {
  availability: "achievement" | "base";
  description: string;
  family: "adornment" | "border" | "color" | "effect" | "palette" | "pattern" | "shape" | "symbol";
  key: string;
  name: string;
  rarity: "common" | "epic" | "legendary" | "rare" | "uncommon";
  render: Record<string, unknown>;
  unlocked: boolean;
};

export type CrestVersion = {
  design: CrestDesign;
  id: string;
  previousVersionId: string | null;
  publishedAt: string;
  sourceDraftRevision: number;
  version: number;
};

export type CrestDraft = {
  basedOnVersion: number | null;
  design: CrestDesign;
  draftRevision: number;
  updatedAt: string;
};

export type TeamCrestSnapshot = {
  canManage: boolean;
  catalog: CrestCatalogItem[];
  confirmedRevision: number;
  crestRevision: number;
  defaultDesign: CrestDesign;
  draft: CrestDraft | null;
  group: { groupId: string; name: string };
  history: CrestVersion[];
  published: CrestVersion | null;
  serverSequence: number;
  updatedAt: string;
};

export type ProgressionAchievement = {
  awardedAt: string;
  description: string;
  grantId: string;
  isFirst: boolean;
  key: string;
  matchFactId: string;
  occurredAt: string;
  rarity: CrestCatalogItem["rarity"];
  repeatable: boolean;
  rewardKey: string | null;
  sequenceCount: number;
  scope: "external" | "internal";
  state: "active" | "revoked";
  title: string;
};

export type IndividualAchievementProgress = {
  awardedAt: string | null;
  category: string;
  currentValue: number;
  description: string;
  grantId: string | null;
  key: string;
  occurrenceCount: number;
  progressPercent: number;
  rarity: CrestCatalogItem["rarity"];
  repeatable: boolean;
  rewardKey: string | null;
  rewardKind: "none";
  scope: "external" | "internal";
  threshold: number;
  title: string;
  unlocked: boolean;
};

export type PendingReward = {
  achievement: {
    awardedAt: string;
    description: string;
    isFirst: boolean;
    key: string;
    occurredAt: string;
    rarity: CrestCatalogItem["rarity"];
    sequenceCount: number;
    title: string;
  };
  boxId: string;
  generatedAt: string;
  matchFactId: string;
  openedAt: string | null;
  recipientRevision: number;
  rewardGrantedAt: string | null;
  rewardGrantId: string;
  rewardKey: string;
  rewardKind: "collective_box" | "team_cosmetic";
  rewardPayload: Record<string, unknown> | null;
  sourceCorrection: Record<string, unknown> | null;
  status: "opened" | "pending" | "revoked" | "skipped";
};

export type ProgressionSnapshot = {
  confirmedRevision: number;
  groupId: string;
  groupRevision: number;
  personalAchievementCatalog: IndividualAchievementProgress[];
  personalAchievements: ProgressionAchievement[];
  rewards: PendingReward[];
  serverSequence: number;
  teamAchievements: ProgressionAchievement[];
  userRevision: number;
  updatedAt: string;
};

type CachedTeamIdentity = {
  cachedAt: number;
  crest: TeamCrestSnapshot | null;
  progression: ProgressionSnapshot | null;
  version: typeof TEAM_IDENTITY_CACHE_VERSION;
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

function rarity(value: unknown): CrestCatalogItem["rarity"] {
  if (value === "uncommon" || value === "rare" || value === "epic" || value === "legendary") return value;
  return "common";
}

function family(value: unknown): CrestCatalogItem["family"] | null {
  if (
    value === "adornment" || value === "border" || value === "color" || value === "effect"
    || value === "palette" || value === "pattern" || value === "shape" || value === "symbol"
  ) return value;
  return null;
}

function design(value: unknown): CrestDesign | null {
  if (!isRecord(value)) return null;
  const shapeKey = text(value.shapeKey);
  const primaryColorKey = text(value.primaryColorKey);
  const secondaryColorKey = text(value.secondaryColorKey);
  const patternKey = text(value.patternKey);
  const borderKey = text(value.borderKey);
  const initials = text(value.initials);
  if (!shapeKey || !primaryColorKey || !secondaryColorKey || !patternKey || !borderKey || !initials) return null;
  return {
    adornmentKey: nullableText(value.adornmentKey),
    borderKey,
    effectKey: nullableText(value.effectKey),
    initials,
    paletteKey: nullableText(value.paletteKey),
    patternKey,
    primaryColorKey,
    secondaryColorKey,
    shapeKey,
    symbolKey: nullableText(value.symbolKey),
  };
}

function catalogItem(value: unknown): CrestCatalogItem | null {
  if (!isRecord(value)) return null;
  const itemFamily = family(value.family);
  const key = text(value.key);
  if (!itemFamily || !key) return null;
  return {
    availability: value.availability === "achievement" ? "achievement" : "base",
    description: text(value.description),
    family: itemFamily,
    key,
    name: text(value.name),
    rarity: rarity(value.rarity),
    render: isRecord(value.render) ? value.render : {},
    unlocked: value.unlocked === true,
  };
}

function crestVersion(value: unknown): CrestVersion | null {
  if (!isRecord(value)) return null;
  const normalizedDesign = design(value.design);
  const id = text(value.id);
  if (!normalizedDesign || !id) return null;
  return {
    design: normalizedDesign,
    id,
    previousVersionId: nullableText(value.previousVersionId),
    publishedAt: text(value.publishedAt),
    sourceDraftRevision: Math.max(1, Math.floor(numberValue(value.sourceDraftRevision))),
    version: Math.max(1, Math.floor(numberValue(value.version))),
  };
}

function crestDraft(value: unknown): CrestDraft | null {
  if (!isRecord(value)) return null;
  const normalizedDesign = design(value.design);
  if (!normalizedDesign) return null;
  return {
    basedOnVersion: value.basedOnVersion === null || value.basedOnVersion === undefined
      ? null
      : Math.max(1, Math.floor(numberValue(value.basedOnVersion))),
    design: normalizedDesign,
    draftRevision: Math.max(1, Math.floor(numberValue(value.draftRevision))),
    updatedAt: text(value.updatedAt),
  };
}

export function normalizeTeamCrestSnapshot(value: unknown): TeamCrestSnapshot | null {
  if (!isRecord(value) || !isRecord(value.group)) return null;
  const groupId = text(value.group.groupId);
  const groupName = text(value.group.name);
  const defaultDesign = design(value.defaultDesign);
  if (!groupId || !groupName || !defaultDesign) return null;
  const crestRevision = Math.max(0, Math.floor(numberValue(value.crestRevision ?? value.confirmedRevision)));
  return {
    canManage: value.canManage === true,
    catalog: Array.isArray(value.catalog)
      ? value.catalog.map(catalogItem).filter((item): item is CrestCatalogItem => Boolean(item))
      : [],
    confirmedRevision: Math.max(crestRevision, Math.floor(numberValue(value.confirmedRevision))),
    crestRevision,
    defaultDesign,
    draft: crestDraft(value.draft),
    group: { groupId, name: groupName },
    history: Array.isArray(value.history)
      ? value.history.map(crestVersion).filter((item): item is CrestVersion => Boolean(item))
      : [],
    published: crestVersion(value.published),
    serverSequence: Math.max(0, Math.floor(numberValue(value.serverSequence))),
    updatedAt: text(value.updatedAt),
  };
}

function achievement(value: unknown): ProgressionAchievement | null {
  if (!isRecord(value)) return null;
  const grantId = text(value.grantId);
  const key = text(value.key);
  const title = text(value.title);
  if (!grantId || !key || !title) return null;
  return {
    awardedAt: text(value.awardedAt),
    description: text(value.description),
    grantId,
    isFirst: value.isFirst === true,
    key,
    matchFactId: text(value.matchFactId ?? value.originMatchFactId),
    occurredAt: text(value.occurredAt ?? value.awardedAt),
    rarity: rarity(value.rarity),
    repeatable: value.repeatable === true,
    rewardKey: nullableText(value.rewardKey),
    sequenceCount: Math.max(1, Math.floor(numberValue(value.sequenceCount))),
    scope: value.scope === "external" ? "external" : "internal",
    state: value.state === "revoked" ? "revoked" : "active",
    title,
  };
}

function individualAchievementProgress(value: unknown): IndividualAchievementProgress | null {
  if (!isRecord(value)) return null;
  const key = text(value.key);
  const title = text(value.title);
  const threshold = Math.max(1, Math.floor(numberValue(value.threshold)));
  if (!key || !title) return null;
  return {
    awardedAt: nullableText(value.awardedAt),
    category: text(value.category),
    currentValue: Math.max(0, Math.floor(numberValue(value.currentValue))),
    description: text(value.description),
    grantId: nullableText(value.grantId),
    key,
    occurrenceCount: Math.max(0, Math.floor(numberValue(value.occurrenceCount))),
    progressPercent: Math.min(100, Math.max(0, Math.floor(numberValue(value.progressPercent)))),
    rarity: rarity(value.rarity),
    repeatable: value.repeatable === true,
    rewardKey: nullableText(value.rewardKey),
    rewardKind: "none",
    scope: value.scope === "external" ? "external" : "internal",
    threshold,
    title,
    unlocked: value.unlocked === true,
  };
}

export function normalizePendingReward(value: unknown): PendingReward | null {
  if (!isRecord(value) || !isRecord(value.achievement)) return null;
  const boxId = text(value.boxId);
  const rewardGrantId = text(value.rewardGrantId);
  const rewardKey = text(value.rewardKey);
  const achievementKey = text(value.achievement.key);
  if (!boxId || !rewardGrantId || !rewardKey || !achievementKey) return null;
  const rewardKind = value.rewardKind === "team_cosmetic" ? "team_cosmetic" : "collective_box";
  const status = value.status === "opened" || value.status === "revoked" || value.status === "skipped"
    ? value.status
    : "pending";
  return {
    achievement: {
      awardedAt: text(value.achievement.awardedAt),
      description: text(value.achievement.description),
      isFirst: value.achievement.isFirst === true,
      key: achievementKey,
      occurredAt: text(value.achievement.occurredAt ?? value.achievement.awardedAt),
      rarity: rarity(value.achievement.rarity),
      sequenceCount: Math.max(1, Math.floor(numberValue(value.achievement.sequenceCount))),
      title: text(value.achievement.title),
    },
    boxId,
    generatedAt: text(value.generatedAt),
    matchFactId: text(value.matchFactId),
    openedAt: nullableText(value.openedAt),
    recipientRevision: Math.max(1, Math.floor(numberValue(value.recipientRevision))),
    rewardGrantedAt: nullableText(value.rewardGrantedAt),
    rewardGrantId,
    rewardKey,
    rewardKind,
    rewardPayload: isRecord(value.rewardPayload) ? value.rewardPayload : null,
    sourceCorrection: isRecord(value.sourceCorrection) ? value.sourceCorrection : null,
    status,
  };
}

export function normalizeProgressionSnapshot(value: unknown): ProgressionSnapshot | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  if (!groupId) return null;
  return {
    confirmedRevision: Math.max(0, Math.floor(numberValue(value.confirmedRevision))),
    groupId,
    groupRevision: Math.max(0, Math.floor(numberValue(value.groupRevision))),
    personalAchievementCatalog: Array.isArray(value.personalAchievementCatalog)
      ? value.personalAchievementCatalog
        .map(individualAchievementProgress)
        .filter((item): item is IndividualAchievementProgress => Boolean(item))
      : [],
    personalAchievements: Array.isArray(value.personalAchievements)
      ? value.personalAchievements.map(achievement).filter((item): item is ProgressionAchievement => Boolean(item))
      : [],
    rewards: Array.isArray(value.rewards)
      ? value.rewards.map(normalizePendingReward).filter((item): item is PendingReward => Boolean(item))
      : [],
    serverSequence: Math.max(0, Math.floor(numberValue(value.serverSequence))),
    teamAchievements: Array.isArray(value.teamAchievements)
      ? value.teamAchievements.map(achievement).filter((item): item is ProgressionAchievement => Boolean(item))
      : [],
    updatedAt: text(value.updatedAt),
    userRevision: Math.max(0, Math.floor(numberValue(value.userRevision))),
  };
}

export function teamIdentityCacheKey(userId: string, groupId: string) {
  return `pachangas:${TEAM_IDENTITY_CACHE_VERSION}:${userId}:${groupId}`;
}

export function readTeamIdentityCache(
  storage: Pick<Storage, "getItem">,
  userId: string,
  groupId: string,
  now = Date.now(),
) {
  try {
    const parsed = JSON.parse(storage.getItem(teamIdentityCacheKey(userId, groupId)) ?? "null") as unknown;
    if (!isRecord(parsed) || parsed.version !== TEAM_IDENTITY_CACHE_VERSION) return null;
    const cachedAt = numberValue(parsed.cachedAt);
    if (!cachedAt || now - cachedAt > TEAM_IDENTITY_CACHE_MAX_AGE_MS) return null;
    return {
      crest: normalizeTeamCrestSnapshot(parsed.crest),
      progression: normalizeProgressionSnapshot(parsed.progression),
    };
  } catch {
    return null;
  }
}

export function writeTeamIdentityCache(
  storage: Pick<Storage, "setItem">,
  userId: string,
  groupId: string,
  crest: TeamCrestSnapshot | null,
  progression: ProgressionSnapshot | null,
  now = Date.now(),
) {
  const cached: CachedTeamIdentity = {
    cachedAt: now,
    crest,
    progression,
    version: TEAM_IDENTITY_CACHE_VERSION,
  };
  storage.setItem(teamIdentityCacheKey(userId, groupId), JSON.stringify(cached));
}
