export type ProvincialRankingItem = {
  components: { competition: number; opposition: number; quality: number };
  displayName: string;
  eligibilityState?: "eligible" | "pending_integrity_review" | "provisional";
  entryKey: string;
  logicalOpponents: number;
  position: number;
  recentActivityWeeks?: number;
  reliability?: number;
  score: number;
  validChallenges: number;
};

export type ProvincialRankingPayload = {
  available: boolean;
  items: ProvincialRankingItem[];
  pagination?: { offset: number; pageSize: number; total: number };
  publication?: { checksum: string; publishedAt: string; revision: number };
  reason?: string;
  season?: {
    endsAt: string;
    formulaKey: string;
    formulaVersion: number;
    id: string;
    key: string;
    label: string;
    startsAt: string;
    status: string;
  };
  territory?: { provinceCode: string; provinceName: string };
};

export type ProvincialOwnRank = {
  available: boolean;
  displayName?: string;
  entryKey?: string;
  eligibilityState?: "eligible" | "ineligible" | "pending_integrity_review" | "provisional";
  logicalOpponents?: number;
  position?: number | null;
  provinceCode?: string;
  publicationRevision?: number;
  reason?: string;
  reasonCodes?: string[];
  recentActivityWeeks?: number;
  reliability?: number;
  score?: number;
  validChallenges?: number;
};

export const PROVINCIAL_RANKING_REASON_LABELS: Record<string, string> = {
  NO_PUBLISHED_POSITION: "Aún no tienes una posición publicada.",
  PLAYER_PROFILE_REQUIRED: "Completa tu ficha para entrar en la clasificación.",
  RANKING_NOT_ACTIVE: "La clasificación provincial todavía no está activa.",
  READ_MODEL_UNAVAILABLE: "La clasificación se está preparando.",
  TERRITORY_NOT_AVAILABLE: "Esta provincia todavía no está disponible.",
  ranking_evidence_incomplete: "Necesitas más retos y rivales válidos.",
  ranking_review_pending: "Pendiente de verificación.",
  ranking_territory_pending: "Falta verificar el territorio competitivo.",
  rating_reliability_incomplete: "Tu ficha necesita mayor fiabilidad.",
  recent_activity_required: "Necesitas actividad reciente.",
};

export function provincialRankingStatusText(state?: ProvincialOwnRank["eligibilityState"]) {
  if (state === "eligible") return "Clasificado";
  if (state === "pending_integrity_review") return "Pendiente de verificación";
  if (state === "provisional") return "Provisional";
  return "Sin clasificar";
}
