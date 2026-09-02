import { normalizeTeamShieldConfig, TEAM_SHIELD_DEFAULT_CONFIG, type TeamShieldConfig } from "./team-shield-contract";

export const SOCIAL_TEAM_CORE_VERSION = "official-ui-v3f" as const;
export const SOCIAL_TEAM_CACHE_VERSION = "v3f-1" as const;

export type SocialTeamRole = "admin" | "owner" | "player";

export type SocialTeamFeatureFlags = {
  confirmedRevision: number;
  demoSocialTeamJourneyEnabled: boolean;
  serverSequence: number;
  socialProfileFoundationEnabled: boolean;
  socialProfileIndependentWriteEnabled: boolean;
  socialTeamCreationEnabled: boolean;
  socialTeamHomeV3fEnabled: boolean;
  socialTeamInvitationV2Enabled: boolean;
  socialTeamMembershipV2Enabled: boolean;
  updatedAt: string;
};

export type CanonicalSocialProfile = {
  approximateTime: string;
  avatarRef: string | null;
  confirmedRevision: number;
  displayName: string;
  generalArea: string;
  preferredModality: "futbol11" | "futbol7" | "sala";
  primaryPosition: string;
  revision: number;
  serverSequence: number;
  updatedAt: string;
  usualDays: string[];
};

export type SocialTeamSummary = {
  confirmedRevision: number;
  generalArea: string;
  groupId: string;
  memberCount: number;
  modality: "futbol11" | "futbol7" | "sala";
  name: string;
  operationalStatus: string;
  revision: number;
  role: SocialTeamRole;
  serverSequence: number;
  shield: TeamShieldConfig;
  teamCode: string;
  updatedAt: string;
};

export type SocialTeamHome = SocialTeamSummary & {
  actions: {
    canCreateMatch: boolean;
    canEditTeam: boolean;
    canInvitePlayers: boolean;
    canManageRoster: boolean;
  };
  activeInvitationCount: number;
  nextMatch: null | {
    date: string;
    matchId: string;
    modality: string;
    place: string;
    targetPlayers: number;
    title: string;
  };
  targetPlayerCount: number;
};

export type SocialTeamRosterMember = {
  avatarRef: string | null;
  displayName: string;
  isCurrentUser: boolean;
  joinedAt: string;
  memberKey: string;
  preferredModality: string;
  primaryPosition: string;
  role: SocialTeamRole;
};

export type SocialTeamInvitation = {
  confirmedRevision: number;
  createdAt: string;
  createdByName: string;
  expiresAt: string;
  generalArea: string;
  groupId: string;
  invitationId: string;
  modality: string;
  revision: number;
  serverSequence: number;
  state: "ACTIVE" | "DECLINED" | "EXPIRED" | "REVOKED" | "USED";
  teamCode: string;
  teamName: string;
  updatedAt: string;
};

export type SocialTeamCreateDraft = {
  modality: "futbol11" | "futbol7" | "sala";
  name: string;
  shieldKey: string;
  targetPlayerCount: number;
  zone: string;
};

export type SocialTeamCachedSnapshot = {
  fetchedAt: string;
  home: SocialTeamHome;
  invitations: SocialTeamInvitation[];
  roster: SocialTeamRosterMember[];
};

function record(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function text(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function integer(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.floor(parsed)) : fallback;
}

function modality(value: unknown): SocialTeamSummary["modality"] {
  return value === "sala" || value === "futbol11" ? value : "futbol7";
}

function role(value: unknown): SocialTeamRole {
  return value === "owner" || value === "admin" ? value : "player";
}

export function modalityLabel(value: string) {
  if (value === "sala" || value === "futsal_5") return "Fútbol sala";
  if (value === "futbol11" || value === "football_11") return "Fútbol 11";
  return "Fútbol 7";
}

export function roleLabel(value: SocialTeamRole) {
  if (value === "owner") return "Owner";
  if (value === "admin") return "Admin";
  return "Jugador";
}

export function normalizeSocialTeamFlags(value: unknown): SocialTeamFeatureFlags | null {
  const source = record(value);
  if (!source) return null;
  return {
    confirmedRevision: integer(source.confirmedRevision ?? source.revision),
    demoSocialTeamJourneyEnabled: source.demoSocialTeamJourneyEnabled === true,
    serverSequence: integer(source.serverSequence),
    socialProfileFoundationEnabled: source.socialProfileFoundationEnabled === true,
    socialProfileIndependentWriteEnabled: source.socialProfileIndependentWriteEnabled === true,
    socialTeamCreationEnabled: source.socialTeamCreationEnabled === true,
    socialTeamHomeV3fEnabled: source.socialTeamHomeV3fEnabled === true,
    socialTeamInvitationV2Enabled: source.socialTeamInvitationV2Enabled === true,
    socialTeamMembershipV2Enabled: source.socialTeamMembershipV2Enabled === true,
    updatedAt: text(source.updatedAt),
  };
}

export function normalizeCanonicalSocialProfile(value: unknown): CanonicalSocialProfile | null {
  const source = record(value);
  const displayName = text(source?.displayName);
  const primaryPosition = text(source?.primaryPosition);
  if (!source || !displayName || !primaryPosition) return null;
  return {
    approximateTime: text(source.approximateTime),
    avatarRef: text(source.avatarRef) || null,
    confirmedRevision: integer(source.confirmedRevision ?? source.revision),
    displayName,
    generalArea: text(source.generalArea),
    preferredModality: modality(source.preferredModality),
    primaryPosition,
    revision: integer(source.revision),
    serverSequence: integer(source.serverSequence),
    updatedAt: text(source.updatedAt),
    usualDays: Array.isArray(source.usualDays) ? source.usualDays.filter((day): day is string => typeof day === "string") : [],
  };
}

export function normalizeSocialTeamSummary(value: unknown): SocialTeamSummary | null {
  const source = record(value);
  const groupId = text(source?.groupId);
  const name = text(source?.name);
  const teamCode = text(source?.teamCode);
  if (!source || !groupId || !name || !teamCode) return null;
  return {
    confirmedRevision: integer(source.confirmedRevision ?? source.revision),
    generalArea: text(source.generalArea),
    groupId,
    memberCount: integer(source.memberCount),
    modality: modality(source.modality),
    name,
    operationalStatus: text(source.operationalStatus, "ACTIVE"),
    revision: integer(source.revision),
    role: role(source.role),
    serverSequence: integer(source.serverSequence),
    shield: normalizeTeamShieldConfig(source.shield) ?? TEAM_SHIELD_DEFAULT_CONFIG,
    teamCode,
    updatedAt: text(source.updatedAt),
  };
}

export function normalizeSocialTeams(value: unknown): SocialTeamSummary[] {
  return Array.isArray(value) ? value.flatMap((item) => {
    const team = normalizeSocialTeamSummary(item);
    return team ? [team] : [];
  }) : [];
}

export function normalizeSocialTeamHome(value: unknown): SocialTeamHome | null {
  const source = record(value);
  const base = normalizeSocialTeamSummary(value);
  if (!source || !base) return null;
  const rawActions = record(source.actions);
  const rawNextMatch = record(source.nextMatch);
  return {
    ...base,
    actions: {
      canCreateMatch: rawActions?.canCreateMatch === true,
      canEditTeam: rawActions?.canEditTeam === true,
      canInvitePlayers: rawActions?.canInvitePlayers === true,
      canManageRoster: rawActions?.canManageRoster === true,
    },
    activeInvitationCount: integer(source.activeInvitationCount),
    nextMatch: rawNextMatch && text(rawNextMatch.matchId) ? {
      date: text(rawNextMatch.date),
      matchId: text(rawNextMatch.matchId),
      modality: text(rawNextMatch.modality, base.modality),
      place: text(rawNextMatch.place),
      targetPlayers: integer(rawNextMatch.targetPlayers),
      title: text(rawNextMatch.title, "Próximo partido"),
    } : null,
    targetPlayerCount: integer(source.targetPlayerCount, 14),
  };
}

export function normalizeSocialTeamRoster(value: unknown): SocialTeamRosterMember[] {
  return Array.isArray(value) ? value.flatMap((item) => {
    const source = record(item);
    const memberKey = text(source?.memberKey);
    const displayName = text(source?.displayName);
    if (!source || !memberKey || !displayName) return [];
    return [{
      avatarRef: text(source.avatarRef) || null,
      displayName,
      isCurrentUser: source.isCurrentUser === true,
      joinedAt: text(source.joinedAt),
      memberKey,
      preferredModality: text(source.preferredModality),
      primaryPosition: text(source.primaryPosition, "Posición pendiente"),
      role: role(source.role),
    } satisfies SocialTeamRosterMember];
  }) : [];
}

export function normalizeSocialTeamInvitation(value: unknown): SocialTeamInvitation | null {
  const source = record(value);
  const invitationId = text(source?.invitationId);
  const groupId = text(source?.groupId);
  if (!source || !invitationId || !groupId) return null;
  const rawState = text(source.state, "EXPIRED");
  const state: SocialTeamInvitation["state"] = rawState === "ACTIVE" || rawState === "USED" || rawState === "REVOKED" || rawState === "DECLINED" ? rawState : "EXPIRED";
  return {
    confirmedRevision: integer(source.confirmedRevision ?? source.revision),
    createdAt: text(source.createdAt),
    createdByName: text(source.createdByName, "Admin del equipo"),
    expiresAt: text(source.expiresAt),
    generalArea: text(source.generalArea),
    groupId,
    invitationId,
    modality: text(source.modality),
    revision: integer(source.revision),
    serverSequence: integer(source.serverSequence),
    state,
    teamCode: text(source.teamCode),
    teamName: text(source.teamName),
    updatedAt: text(source.updatedAt),
  };
}

export function normalizeSocialTeamInvitations(value: unknown): SocialTeamInvitation[] {
  return Array.isArray(value) ? value.flatMap((item) => {
    const invitation = normalizeSocialTeamInvitation(item);
    return invitation ? [invitation] : [];
  }) : [];
}

export function socialTeamCacheKey(userId: string, groupId: string) {
  return `pachangas-social-team-cache:${SOCIAL_TEAM_CACHE_VERSION}:${userId}:${groupId}`;
}

export function socialTeamsCacheKey(userId: string) {
  return `pachangas-social-teams-cache:${SOCIAL_TEAM_CACHE_VERSION}:${userId}`;
}

export function socialProfileCacheKey(userId: string) {
  return `pachangas-social-profile-cache:${SOCIAL_TEAM_CACHE_VERSION}:${userId}`;
}
