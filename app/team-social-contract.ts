export const TEAM_SOCIAL_CACHE_VERSION = "team-social-v1";
export const TEAM_SOCIAL_CACHE_MAX_AGE_MS = 5 * 60 * 1000;

export type TeamChallengeStatus = "accepted" | "cancelled" | "changes_proposed" | "proposed" | "rejected";
export type TeamChallengeAction = "accept" | "cancel" | "propose_changes" | "reject";
export type TeamChallengeModality = "futbol11" | "futbol7" | "sala";

export type TeamSummary = {
  groupId: string;
  name: string;
  teamCode: string;
};

export type TeamChallengeField = {
  address: string;
  mapsUrl: string | null;
  name: string;
  placeId: string | null;
};

export type TeamChallenge = {
  acceptedAt: string | null;
  cancelledAt: string | null;
  createdAt: string;
  direction: "incoming" | "outgoing";
  field: TeamChallengeField;
  id: string;
  lastProposedBy: "opponent" | "own";
  message: string | null;
  modality: TeamChallengeModality;
  opponent: TeamSummary;
  proposalNumber: number;
  rejectedAt: string | null;
  revision: number;
  scheduledAt: string;
  status: TeamChallengeStatus;
  updatedAt: string;
};

export type KnownOpponent = TeamSummary & {
  firstEncounterAt: string;
  lastEncounterAt: string;
  lastMatchId: string;
  matchesPlayed: number;
  revision: number;
};

export type TeamSocialSnapshot = {
  canManage: boolean;
  challenges: TeamChallenge[];
  confirmedRevision: number;
  group: TeamSummary;
  knownOpponents: KnownOpponent[];
  serverSequence: number;
  socialRevision: number;
  updatedAt: string;
};

type CachedTeamSocialSnapshot = {
  cachedAt: number;
  snapshot: TeamSocialSnapshot;
  version: typeof TEAM_SOCIAL_CACHE_VERSION;
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

function teamSummary(value: unknown): TeamSummary | null {
  if (!isRecord(value)) return null;
  const groupId = text(value.groupId);
  const name = text(value.name);
  const teamCode = text(value.teamCode);
  return groupId && name ? { groupId, name, teamCode } : null;
}

function challengeStatus(value: unknown): TeamChallengeStatus {
  return value === "accepted" || value === "cancelled" || value === "changes_proposed" || value === "rejected"
    ? value
    : "proposed";
}

function challengeModality(value: unknown): TeamChallengeModality {
  return value === "sala" || value === "futbol11" ? value : "futbol7";
}

function teamChallenge(value: unknown): TeamChallenge | null {
  if (!isRecord(value)) return null;
  const opponent = teamSummary(value.opponent);
  const field = isRecord(value.field) ? value.field : null;
  const id = text(value.id);
  const scheduledAt = text(value.scheduledAt);
  if (!opponent || !field || !id || !scheduledAt) return null;

  return {
    acceptedAt: nullableText(value.acceptedAt),
    cancelledAt: nullableText(value.cancelledAt),
    createdAt: text(value.createdAt),
    direction: value.direction === "incoming" ? "incoming" : "outgoing",
    field: {
      address: text(field.address),
      mapsUrl: nullableText(field.mapsUrl),
      name: text(field.name),
      placeId: nullableText(field.placeId),
    },
    id,
    lastProposedBy: value.lastProposedBy === "opponent" ? "opponent" : "own",
    message: nullableText(value.message),
    modality: challengeModality(value.modality),
    opponent,
    proposalNumber: Math.max(1, numberValue(value.proposalNumber)),
    rejectedAt: nullableText(value.rejectedAt),
    revision: Math.max(1, numberValue(value.revision)),
    scheduledAt,
    status: challengeStatus(value.status),
    updatedAt: text(value.updatedAt),
  };
}

function knownOpponent(value: unknown): KnownOpponent | null {
  const team = teamSummary(value);
  if (!team || !isRecord(value)) return null;
  return {
    ...team,
    firstEncounterAt: text(value.firstEncounterAt),
    lastEncounterAt: text(value.lastEncounterAt),
    lastMatchId: text(value.lastMatchId),
    matchesPlayed: Math.max(1, numberValue(value.matchesPlayed)),
    revision: Math.max(1, numberValue(value.revision)),
  };
}

export function normalizeTeamSocialSnapshot(value: unknown): TeamSocialSnapshot | null {
  if (!isRecord(value)) return null;
  const group = teamSummary(value.group);
  if (!group) return null;
  const challenges = Array.isArray(value.challenges) ? value.challenges.map(teamChallenge).filter((item): item is TeamChallenge => Boolean(item)) : [];
  const knownOpponents = Array.isArray(value.knownOpponents)
    ? value.knownOpponents.map(knownOpponent).filter((item): item is KnownOpponent => Boolean(item))
    : [];
  const socialRevision = Math.max(0, numberValue(value.socialRevision ?? value.confirmedRevision));

  return {
    canManage: value.canManage === true,
    challenges,
    confirmedRevision: Math.max(socialRevision, numberValue(value.confirmedRevision)),
    group,
    knownOpponents,
    serverSequence: Math.max(0, numberValue(value.serverSequence)),
    socialRevision,
    updatedAt: text(value.updatedAt),
  };
}

export function teamSocialCacheKey(userId: string, groupId: string) {
  return `pachangas:${TEAM_SOCIAL_CACHE_VERSION}:${userId}:${groupId}`;
}

export function readTeamSocialCache(storage: Pick<Storage, "getItem">, userId: string, groupId: string, now = Date.now()) {
  try {
    const parsed = JSON.parse(storage.getItem(teamSocialCacheKey(userId, groupId)) ?? "null") as unknown;
    if (!isRecord(parsed) || parsed.version !== TEAM_SOCIAL_CACHE_VERSION) return null;
    const cachedAt = numberValue(parsed.cachedAt);
    if (!cachedAt || now - cachedAt > TEAM_SOCIAL_CACHE_MAX_AGE_MS) return null;
    return normalizeTeamSocialSnapshot(parsed.snapshot);
  } catch {
    return null;
  }
}

export function writeTeamSocialCache(
  storage: Pick<Storage, "setItem">,
  userId: string,
  groupId: string,
  snapshot: TeamSocialSnapshot,
  now = Date.now(),
) {
  const cached: CachedTeamSocialSnapshot = { cachedAt: now, snapshot, version: TEAM_SOCIAL_CACHE_VERSION };
  storage.setItem(teamSocialCacheKey(userId, groupId), JSON.stringify(cached));
}

export function teamChallengeStatusLabel(status: TeamChallengeStatus) {
  if (status === "accepted") return "Aceptado";
  if (status === "cancelled") return "Cancelado";
  if (status === "changes_proposed") return "Cambios propuestos";
  if (status === "rejected") return "Rechazado";
  return "Pendiente";
}

export function teamChallengeModalityLabel(modality: TeamChallengeModality) {
  if (modality === "sala") return "Fútbol sala";
  if (modality === "futbol11") return "Fútbol 11";
  return "Fútbol 7";
}
