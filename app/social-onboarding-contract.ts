import { validBirthDate } from "./market-age-contract";
export type SocialEntryState =
  | "NEW_USER"
  | "PROFILE_READY_NO_TEAM"
  | "TEAM_INVITATION_PENDING"
  | "TEAM_MEMBER"
  | "MULTI_TEAM_MEMBER";

export type SocialOnboardingFlow = "create" | "join" | "profile" | "start";

export type SocialProfileFieldClass =
  | "ESSENTIAL"
  | "MARKET_ONLY"
  | "OPTIONAL"
  | "PRIVATE"
  | "TEAM_ONLY"
  | "TECHNICAL";

export type SocialProfileMinimum = {
  birthDate?: string | null;
  approximateTime?: string | null;
  avatarRef?: string | null;
  confirmedRevision?: number | null;
  displayName?: string | null;
  generalArea?: string | null;
  modalities?: string[] | null;
  preferredModality?: string | null;
  primaryPosition?: string | null;
  position?: string | null;
  revision?: number | null;
  serverSequence?: number | null;
  updatedAt?: string | null;
  usualDays?: string[] | null;
};

export type SocialOnboardingDraft = {
  birthDate?: string;
  approximateTime: string;
  avatarPreviewUrl: string;
  days: string[];
  displayName: string;
  modality: "futbol11" | "futbol7" | "sala";
  position: string;
  zone: string;
};

export type TeamInvitationInput =
  | { kind: "invite"; token: string }
  | { kind: "team-code"; code: string }
  | { kind: "invalid"; reason: "EMPTY" | "INVALID" };

export const SOCIAL_ONBOARDING_VERSION = "official-ui-v3f";

export const SOCIAL_PROFILE_FIELD_CLASSIFICATION = {
  authProvider: "TECHNICAL",
  authUserId: "TECHNICAL",
  avatar: "OPTIONAL",
  availability: "OPTIONAL",
  birthDate: "PRIVATE",
  coordinates: "PRIVATE",
  displayName: "ESSENTIAL",
  email: "PRIVATE",
  groupRole: "TEAM_ONLY",
  marketBio: "MARKET_ONLY",
  marketInvitationPreferences: "MARKET_ONLY",
  marketRadius: "MARKET_ONLY",
  marketVisibility: "MARKET_ONLY",
  modalities: "ESSENTIAL",
  phone: "PRIVATE",
  position: "ESSENTIAL",
  profileRevision: "TECHNICAL",
  teamCode: "TEAM_ONLY",
  zone: "ESSENTIAL",
} as const satisfies Record<string, SocialProfileFieldClass>;

export const DEFAULT_SOCIAL_ONBOARDING_DRAFT: SocialOnboardingDraft = {
  birthDate: "",
  approximateTime: "20:00-22:00",
  avatarPreviewUrl: "",
  days: [],
  displayName: "",
  modality: "futbol7",
  position: "Mediocentro / pivote",
  zone: "",
};

export const SOCIAL_POSITION_OPTIONS = [
  "Portero",
  "Defensa central",
  "Lateral",
  "Mediocentro / pivote",
  "Interior / volante",
  "Mediapunta",
  "Extremo",
  "Delantero / punta",
] as const;

export const SOCIAL_DAY_OPTIONS = ["L", "M", "X", "J", "V", "S", "D"] as const;

export const TEAM_CREATION_AUTHORITY = {
  available: true,
  command: "command_pachanga_social_team_v1",
  message: "El servidor creará el equipo, su código, el owner y el escudo en una sola confirmación.",
} as const;

function cleanText(value: unknown, maxLength: number) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

export const SOCIAL_DISPLAY_NAME_MAX_LENGTH = 32;

export function normalizeSocialOnboardingDraft(value: unknown): SocialOnboardingDraft {
  if (!value || typeof value !== "object") return { ...DEFAULT_SOCIAL_ONBOARDING_DRAFT };
  const draft = value as Partial<SocialOnboardingDraft>;
  const modality = draft.modality === "sala" || draft.modality === "futbol11" ? draft.modality : "futbol7";
  return {
    birthDate: cleanText(draft.birthDate, 10),
    approximateTime: cleanText(draft.approximateTime, 40) || DEFAULT_SOCIAL_ONBOARDING_DRAFT.approximateTime,
    avatarPreviewUrl: "",
    days: Array.isArray(draft.days)
      ? draft.days.filter((day): day is string => SOCIAL_DAY_OPTIONS.includes(day as (typeof SOCIAL_DAY_OPTIONS)[number]))
      : [],
    // Keep the trailing space while typing the next word. Preserve legacy names
    // up to their former limit so opening the editor never shortens them.
    displayName: typeof draft.displayName === "string" ? draft.displayName.slice(0, 80) : "",
    modality,
    position: SOCIAL_POSITION_OPTIONS.includes(draft.position as (typeof SOCIAL_POSITION_OPTIONS)[number])
      ? String(draft.position)
      : DEFAULT_SOCIAL_ONBOARDING_DRAFT.position,
    zone: cleanText(draft.zone, 120),
  };
}

export function socialProfileMinimumReady(profile: SocialProfileMinimum | null | undefined) {
  return Boolean(
    cleanText(profile?.displayName, 80)
      && cleanText(profile?.primaryPosition ?? profile?.position, 80)
      && (
        cleanText(profile?.preferredModality, 40)
        || (Array.isArray(profile?.modalities) && profile.modalities.some((modality) => cleanText(modality, 40)))
      ),
  );
}

export function socialFirstTimeProfileReady(profile: SocialProfileMinimum | null | undefined) {
  return Boolean(
    socialProfileMinimumReady(profile)
      && validBirthDate(profile?.birthDate)
      && cleanText(profile?.generalArea, 120),
  );
}

export function socialProfileModalities(input: {
  assessmentSummary?: unknown;
  marketModalities?: unknown;
}) {
  const market = Array.isArray(input.marketModalities)
    ? input.marketModalities.filter((modality): modality is string => typeof modality === "string" && Boolean(modality.trim()))
    : [];
  if (market.length) return market;
  if (!input.assessmentSummary || typeof input.assessmentSummary !== "object") return [];
  const initial = (input.assessmentSummary as { initial?: { modeShares?: Array<{ mode?: string; percentage?: number }> } }).initial;
  return (initial?.modeShares ?? [])
    .filter((share) => Number(share.percentage) > 0 && typeof share.mode === "string")
    .map((share) => String(share.mode));
}

export function deriveSocialEntryState(input: {
  invitationPending: boolean;
  membershipCount: number;
  profile: SocialProfileMinimum | null;
}): SocialEntryState {
  if (input.invitationPending) return "TEAM_INVITATION_PENDING";
  if (input.membershipCount > 1) return "MULTI_TEAM_MEMBER";
  if (input.membershipCount === 1) return "TEAM_MEMBER";
  return socialProfileMinimumReady(input.profile) ? "PROFILE_READY_NO_TEAM" : "NEW_USER";
}

function normalizeUuidToken(raw: string) {
  const compact = raw.replace(/-/g, "").toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(compact)) return null;
  return [compact.slice(0, 8), compact.slice(8, 12), compact.slice(12, 16), compact.slice(16, 20), compact.slice(20)].join("-");
}

export function parseTeamInvitationInput(rawInput: string): TeamInvitationInput {
  const input = rawInput.trim();
  if (!input) return { kind: "invalid", reason: "EMPTY" };

  let candidate = input;
  try {
    const url = new URL(input, "https://pachangasiq.com");
    const pathToken = url.pathname.match(/\/invitacion\/grupo\/([^/?#]+)/i)?.[1];
    candidate = pathToken ?? url.searchParams.get("i") ?? url.searchParams.get("invite") ?? input;
  } catch {
    candidate = input;
  }

  const decodedCandidate = decodeURIComponent(candidate);
  if (/^piq_[0-9a-f]{64}$/i.test(decodedCandidate)) {
    return { kind: "invite", token: decodedCandidate.toLowerCase() };
  }
  const token = normalizeUuidToken(decodedCandidate);
  if (token) return { kind: "invite", token };
  if (/^[A-Z0-9]{6,12}$/i.test(input)) return { kind: "team-code", code: input.toUpperCase() };
  return { kind: "invalid", reason: "INVALID" };
}

export function mapTeamJoinError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error ?? "");
  const normalized = message.toLowerCase();
  if (normalized.includes("invalid_invitation_token") || normalized.includes("invalid invite") || normalized.includes("not found") || normalized.includes("invitation_not_found")) return "INVITACIÓN NO VÁLIDA";
  if (normalized.includes("expired") || normalized.includes("caduc")) return "INVITACIÓN CADUCADA";
  if (normalized.includes("revoked") || normalized.includes("revoc")) return "INVITACIÓN REVOCADA";
  if (normalized.includes("already") || normalized.includes("perteneces") || normalized.includes("already_team_member")) return "YA PERTENECES A ESTE EQUIPO";
  if (normalized.includes("suspend") || normalized.includes("archive") || normalized.includes("limited") || normalized.includes("operationally_restricted") || normalized.includes("no disponible")) return "EQUIPO NO DISPONIBLE";
  if (normalized.includes("social_profile_required")) return "GUARDA TU PERFIL ANTES DE UNIRTE";
  if (normalized.includes("disabled")) return "ESTA FUNCIÓN AÚN NO ESTÁ ACTIVA";
  return "NO PUEDES UNIRTE AHORA";
}

export function playerMarketPresentationState(profile: {
  availability?: string | null;
  enabled?: boolean | null;
  zones?: string | null;
} | null | undefined) {
  if (profile?.enabled) return "PUBLICADO" as const;
  if (cleanText(profile?.availability, 240) || cleanText(profile?.zones, 320)) return "PAUSADO" as const;
  return "NO PUBLICADO" as const;
}

export function socialWriteAvailability(online: boolean) {
  return online
    ? { allowed: true, label: "Listo para confirmar en servidor" }
    : { allowed: false, label: "Necesitas conexión para confirmar esta acción." };
}

export function socialOnboardingFlowFromSearch(search: string): SocialOnboardingFlow | null {
  const requested = new URLSearchParams(search).get("social");
  return requested === "create" || requested === "join" || requested === "profile" || requested === "start"
    ? requested
    : null;
}
